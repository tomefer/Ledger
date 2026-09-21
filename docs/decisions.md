# Ledger: decisions, history and open items

Not loaded into Claude Code sessions (unlike `CLAUDE.md`, which holds only the
rules in force). This file records what was decided, what was discarded and
why, bugs whose fix left a rule behind, the UI design reference, and every open
verification item. Read the relevant section before revisiting that area.
Dates are 2026 unless stated. The pre-cleanup `CLAUDE.md` is in git history
(commit "Snapshot CLAUDE.md before the cleanup").

Contents: 1 Clients and the beta · 2 Activity sampling · 3 xp capture ·
4 Level close · 5 Persistence · 6 UI reference · 7 Panels and tools ·
8 Hooks and deploy · 9 Open items

---

## 1. Clients and the beta

### 1.1 One package, two clients (2026-09-17)
A single `Ledger.toc` (`## Interface: 11509, 16001`) serves Classic Era (client
1.15.x) and the WoW Forever beta (build 1.60.1, also Classic line). No separate
TOCs per flavor. Nothing is assumed to behave identically on both; `/ldg probe`
exists to check on the real client instead of guessing. Today there is no
per-interface branching anywhere in the code; add one only if `/ldg probe`
shows a real difference.

### 1.2 The beta ignores SavedVariables that pre-date client launch (2026-09-19)
In the WoW Forever beta the client does **not** load SavedVariables files that
already existed on disk when it started, though it writes them correctly on
logout / `/reload`. Files created during the running client session do load on
`/reload`. Classic Era loads the same files fine. **Client behavior; the addon
cannot fix it.**

Effects on Ledger: every client start opens a cold-start session (`initialXP` =
all the xp in the level, `t0` = load time), earlier sessions vanish, and
`LedgerDB` settings (`ratePos`, `barShown`...) revert to defaults. Since
Ledger's file almost always exists at launch, data effectively lives only for
one client session.

How it was shown (throwaway test addons, since deleted, each with an account
counter and a character counter):
- An addon whose files are created inside the session loads on the first
  `/reload` (`prev loads` goes up); after closing and restarting the client,
  the same files arrive as `nil`, counter back to 0.
- Same with 5 different addons, and with Ledger as soon as its files were moved
  off disk before launch: in that launch Ledger did resume the session after
  `/reload` (`StartTracking: resuming saved sessions`), and on the next launch
  it was back to `cold start`.
- Hint, not proof: Blizzard's own SavedVariables don't seem to accumulate
  between launches either (`Blizzard_PTRIssueReporter_Saved` stored 12 s with
  hours played).

Ruled out: the `.toc` with `## Interface: 11509, 16001` (same with only
`16001`); load order or alphabetical position; the names `Ledger`/`LedgerDB`;
data shape or size (a test addon with the same `.toc`, subfolders and nested
tables behaves like a minimal one); version wipe (`wiped=false`, every saved
file says `version = 9`); NTFS permissions/ACLs, VirtualStore redirection,
copies in other paths, and reads from WSL (same result on a launch where WSL
never touched the files).

Unconfirmed: why the client ignores them. The hypothesis was that it looks at
the file's modification or creation date (the game rewrites in place, and
creation date doesn't change between saves); that test was never run. It is
not a `GetAddOnMetadata` failure: `GetAddOnMetadata(addon, "SavedVariables")`
returns `nil` even for addons that do load, so it is useless as a probe.

Recognizing it in the log (`/ldg log show`, INFO): on a character that has
played, `ADDON_LOADED: LedgerCharDB from disk: type=nil` followed by
`StartTracking: cold start`. With data loaded: `from disk: version=...
sessions=N ...` and `StartTracking: resuming saved sessions`. Remaining
instrumentation is just those two lines (`ui/events.lua`, `ui/xp_capture.lua`,
`Ledger.SummarizeCharDB`); the `SVState[...]` lines (table-address dumps at
several points of startup) were removed in 0.11.8.

Minimal repro for Blizzard: an addon with `## SavedVariables: XDB` and an
`ADDON_LOADED` that does `XDB = XDB or {}` and adds one to `XDB.loads`, printing
the previous value. Start, `/reload` (loads), fully close the client, start
again: `nil` arrives.

### 1.3 "Secret" values on the beta (2026-09-18, 2026-09-21)
Both cases are the same client mechanism: a *secret* value can be passed around,
but code with taint can't compare, index, pattern-match or format it.

**Chat messages (2026-09-21).** Looting a boss, `ExtractExploreXP` blew up with
`attempt to index local 'msg' (a secret string value, while execution tainted by
'Ledger')`: the `arg1` of `CHAT_MSG_SYSTEM` arrived as a secret string.
`ui/xp_capture.lua: IsReadableMessage(msg)` (the only piece that knows; `core/`
stays pure) uses `issecretvalue` if the client has it **and** a `pcall` probe
(`string.find`) that doesn't assume that API exists. The `CHAT_MSG_SYSTEM` and
`CHAT_MSG_COMBAT_XP_GAIN` handlers don't touch `arg1` (not even for `tostring`)
when it isn't readable, and warn at ERROR once per event and session
(`WarnSecretMessage`). Degradation: a secret `CHAT_MSG_SYSTEM` is ignored (an
exploration xp arriving that way is released as `"unknown"` by the matcher); a
secret `CHAT_MSG_COMBAT_XP_GAIN` is enqueued as `"kill"` with `rested = 0` (that
event only fires for combat xp; quests pair by exact amount with priority) — an
**assumption**, and the rested bonus of those messages is lost. The extractors
in `core/chat_patterns.lua` also tolerate a non-string `msg` (no match).
**Unconfirmed in game:** that the guard avoids the error on a boss, and which
other messages arrive secret (TRACE `... msg=<secret>`).

**`GetUnitSpeed` (2026-09-18).** On the beta (build 1.60.1) the value returned by `GetUnitSpeed` is marked
"secret": the call doesn't fail, but comparing it (`> 0`) raises `attempt to
compare a secret number value`. `ui/xp_capture.lua: IsPlayerMoving()` wraps the
comparison in its own `pcall` and degrades to "not moving" with one ERROR line
per session, a real data loss (on-foot `travel` can't be detected while it
lasts). In real beta data the combat+moving combination never appears in ~700
combat samples, consistent with the value being secret precisely in combat; it
doesn't affect the split (combat outranks movement) but is unconfirmed until
checked in `/ldg log show`. Unknown whether Classic Era 1.15.x has the same
tainting.

### 1.4 Deploy script
- Flavors resolve to their own folder under the WoW install root: `_classic_era_`
  and `_classic_beta_` (the beta's real folder name on this machine, confirmed,
  not guessed). `LEDGER_WOW_PATH` is the **root** (folder containing
  `_classic_era_`, `_classic_beta_`...), never a full path down to
  `Interface/AddOns`: the flavor decides that last stretch. The path is not
  hardcoded to this machine because the repo is public; the default assumes the
  standard Battle.net path on Windows.
- 0.11.6-0.11.7 deployed a `.toc` with only `## Interface: 16001` to the beta.
  Removed once it was shown to make no difference (see 1.2).
- Everything is deployed by deleting the destination first, so files removed
  from the repo don't linger as zombies.

---

## 2. Activity sampling

### 2.1 Rewrite from scratch (2026-09-19), no backward compatibility
Deleted entirely: the tracker with reclassification, the raw `stateSeries`
series, the "downtime" / "sustained movement" thresholds, derived buckets,
`totalPlayed` and the whole character-played-time model (baseline, estimate via
`GetTime`, "unreliable" state, time invariants). The played-time model never
worked reliably: a baseline was copied before the `/played` reply arrived, and
the derived numbers could not be reconciled with anything external.

Replacement: the ticker is a **sampler, not a clock**. Each second it reads the
instantaneous player state, `Ledger.ClassifyActivity` turns it into ONE key and
that counter goes up by one. Nothing per tick is stored, no thresholds, no
smoothing, no wall-clock arithmetic. Counters are sample counts, not guaranteed
seconds: if the client is not in the foreground (or closed) the ticker doesn't
run, correct by design since it measures time the addon actually observed.

Decisions that came with it:
- **Counters increment live on both tables** (active session and current
  level), so a crash loses at most the ticks since the last save, not the whole
  level, and there is nothing to compute at close.
- **Priority** dead > combat > moving > rest: "a corpse is not in combat, not
  even mid-fight"; moving includes taxi (`UnitOnTaxi`).
- **Always shown as a percentage** of samples so nobody is tempted to reconcile
  absolute values with `/played` or the clock. The times the `/ldg rate` hover
  panel shows are exact clocks kept apart, not derived from samples (see 6.5;
  it used to show the sampled duration, replaced 2026-09-21). Percentages are
  derived at display time, never persisted. Data dumps (`/ldg export`) do write
  the raw counters: they are the data, not a presentation.
- **xp/hour denominator = samples** (1 sample = 1 s), never wall-clock or
  `/played`. Time the client was stopped is not in the denominator, by design.
- **`/played` demoted to information.** `TIME_PLAYED_MSG` (`arg2` = played time
  in the current level) is stored in `LedgerCharDB.played = { level, seconds,
  samples }` (`Ledger.RecordPlayedReading`) next to the level's sample count at
  that instant, so they can be compared without the delay between request and
  reply skewing them. Requested (always under `pcall`, `Ledger.RequestPlayedReading`)
  on `PLAYER_ENTERING_WORLD`, on `PLAYER_LEVEL_UP` (the server-side level counter
  resets; this request only feeds the rate panel's clock), after `/ldg wipe
  confirm`, and when `/ldg check` opens or refreshes; not requested from the
  level close itself (it would give ~0). The only reader of
  `LedgerCharDB.played` is `/ldg check`. Each reply also prints Blizzard's
  "time played" line to chat, as always.
- **In-memory played reference** (`Ledger.levelPlayedRef = { level, seconds,
  receivedAt }`, `Ledger.NewLevelPlayedRef`, `core/rate.lua`): set in the
  `TIME_PLAYED_MSG` handler with the `time()` of reception, never persisted,
  never inside `levels` or `sessions`. Read only by the `/ldg rate` panel for the
  level's played time. Each reply **replaces** it (after a `/reload` the new
  value already includes the old one); display only, feeds no xp/hour or other
  metric.
- Per-session and per-level counters share the shape
  `{ combat, nonCombat, travel, dead, total }` (`Ledger.NewTicks()`). At level
  close the level counters pass by reference to `entry.ticks`; a `/ldg reset`
  opens a session with fresh counters while the level's keep counting.

---

## 3. xp capture

### 3.1 Level-up delta bug (fixed)
Naive `xpNow - xpPrev` lost all xp on a level-up because `UnitXP` resets:
observed `xpPrev=809 xpNow=79 delta=-730`. `Ledger.ComputeXPDelta` (pure,
`core/xp_delta.lua`) now takes the cached `UnitXPMax`/`UnitLevel` from the
previous `PLAYER_XP_UPDATE`. `UnitXPMax` is never read at the ding itself: by
then it already returns the **new** level's max, not the old one the arithmetic
needs.
- Same level: `delta = xpNow - xpPrev`; a negative result without a level-up is
  unexplained (`ok=false`, logged as ERROR, no invented number).
- One level up: `delta = (cachedOldMax - xpPrev) + xpNow`, plus `crossing =
  { oldPart, newPart, oldLevel, newLevel, oldMax }`, `oldPart + newPart ==
  delta`. `oldMax` ends up in `entry.xpRequired`.
- More than one level at once: there is **no Classic Era API for the xp
  requirement of intermediate levels**, so it is not computable; detected by
  counting `UnitLevel` before/after and logged as ERROR.
- `delta = 0` is valid and silently ignored.

### 3.2 Source always `"unknown"` (diagnosed and fixed 2026-09-16)
Found with the TRACE instrumentation. Two causes:
1. `Ledger.BuildPattern` anchored the pattern end with `$`, but a real kill
   message with rested bonus continues past "experience." (`"... you gain 172
   experience. (+86 exp Rested bonus)"`), so no pattern ever matched. `$` was
   dropped; `%d+` stops capturing at the first non-digit anyway. (Rule kept:
   anchor with `^` only.)
2. Classification was all-or-nothing: with no matching pattern `AddSource` was
   never called, so the amount always ended up orphaned and released as
   `"unknown"` after `MAX_MATCH_GAP`. Now `ClassifyXPGainMatch` always returns
   a category (`kill` if the matching variant has a creature name, i.e. `%s` in
   its global string; `explore` otherwise or if nothing matched) and `AddSource`
   is always called: the mere arrival of `CHAT_MSG_COMBAT_XP_GAIN` already
   confirms it is combat or exploration xp.

Patterns are built at load from **all** `_G` global strings starting with
`COMBATLOG_XPGAIN_` (never a fixed or `FIRSTPERSON`-only list: the event only
fires for the player's own xp anyway).

### 3.3 Rested bonus
`COMBATLOG_XPGAIN_EXHAUSTION*` strings build unanchored suffix patterns
(`BuildSuffixPattern`, unlike `BuildPattern` not even anchored at the start: the
bonus suffix is glued to the end of the sentence). `Ledger.ExtractRestedBonus`
returns the captured amount, or 0. **Unconfirmed in game** that the name
`COMBATLOG_XPGAIN_EXHAUSTION*` is right on 1.15.x (Blizzard convention for
several expansions, not verified here); `/ldg strings` prints that family too.
The total (`xp`) always comes from the `UnitXP` delta; the message only
contributes `rested`.

### 3.4 Quest turn-ins misclassified as "explore" (fixed 2026-09-18)
The quest-turn-in message ("You gain N experience.") is identical to the
exploration one (`COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED` can't tell them apart),
so `QUEST_TURNED_IN` (`questID, xp, money`) is enqueued as its own source
(`Ledger.AddSource(matcher, t, "quest", log, 0, xp)`) carrying `expectedXP`;
`EmitEvent` compares `expectedXP` with the real delta and logs an ERROR on
mismatch (the recorded amount is always the delta).

Confirmed in game that some turn-ins were classified "explore", not all. The
priority tie-break (`SOURCE_PRIORITY`, quest always wins within the margin) was
never the problem; the time window was: the generic combat message and
`QUEST_TURNED_IN` don't always both arrive within the margin, so one of them
could pair up (or be orphaned) before the other got to compete. Fix:
- `AddAmount`/`AddSource` look first, before the FIFO-by-proximity rule, for a
  pending tag whose `expectedXP` equals the amount exactly. A quest turn-in is
  rare, so no risk of pairing with the wrong one (kills arrive in bursts and
  keep using the normal window). Later generalized to any source with
  `expectedXP` (see 3.5).
- Quest tags survive longer in the queue (`Ledger.QUEST_MATCH_GAP = 3.0` vs
  `MAX_MATCH_GAP = 1.0`, `matcher.questGap`, used only in source `Flush`).
- A generic message is only classified `explore` if
  `Ledger.HasPendingQuestSource` (called from `ui/xp_capture.lua` before
  enqueueing) finds no pending `quest` tag, by amount (using the `%d` that
  message captures) or by mere presence; otherwise the message is dropped
  instead of competing. All TRACE (`ExploreCheck: ...`).

Still to confirm with real data: that no turn-in is misclassified any more,
including one with a simultaneous real kill (see section 9).

### 3.5 Exploration is a system message, not a combat message (2026-09-19)
A real log showed a cave giving 70 xp with **no** `CHAT_MSG_COMBAT_XP_GAIN` at
all, so the amount was released as `"unknown"`. Zone discovery is announced via
`CHAT_MSG_SYSTEM` with `ERR_ZONE_EXPLORED_XP` ("Discovered %s: %d experience
gained"). Its pattern is built at load (`Ledger.exploreStrings`),
`Ledger.ExtractExploreXP` takes the last group (the area name comes first) and
it is enqueued as an `explore` source with that amount as `expectedXP`, like a
quest. That's why exact-amount matching no longer looks at `src == "quest"`: a
simultaneous kill can't steal exploration xp. `ERR_ZONE_EXPLORED` (no xp, max
level) is unused: no amount to match. **Unconfirmed in game** that it is
`CHAT_MSG_SYSTEM` on both clients: every system message is TRACE-logged
(`CHAT_MSG_SYSTEM ... area discovery` / `... ignored`).

### 3.6 Reconciliation counter (`core/xp_reconciler.lua`)
Accumulates the xp a valid delta says should be recorded
(`AccountExpectedXP`, on `ok=true, delta ~= 0`) against what actually gets
recorded (`AccountRecordedXP`, in `EmitEvent`); `ReconciliationGap` is the
difference. Transiently non-zero while something waits inside the pairing
margin; a gap that never closes is the signature of a bug dropping xp silently
(exactly the level-up bug of 3.1). In memory only, next to the matcher, and
nothing reads it yet.

### 3.7 Instrumentation
The whole flow (raw events, match attempts with their captures, detected rested
bonus, queue state, real pairing separation for recalibrating `MAX_MATCH_GAP`)
logs at TRACE. `/ldg strings` prints every global string in use (both
families) with its literal value and derived pattern.

The `print("Ledger: core/<file>.lua")` line every `core/` file used to emit at
load (to see which files had executed and in what order) was removed on
2026-09-20 as leftover debugging noise.

---

## 4. Level close

### 4.1 Crossing split in two entries, never counted whole in one level
Found in the real SavedVariables analysis (2026-09-17): the old level ended
above its cap and the new one started with an orphan `unknown`, because the
crossing event was counted whole in one place and its remainder again in the
other. When `ComputeXPDelta` reports `levelsGained = 1`, the `crossing` rides
with the amount **through the matcher** (`AddAmount`/`AddSource`/`Flush`
propagate it like `rested`/`expectedXP`) until it pairs with its real source.
So whether the source arrives before, after or never (orphan, `unknown` after
the margin), **the real `src` is resolved for the whole event before splitting**;
splitting first would leave one half with no source to pair with, released as
`unknown` though the other half had a real origin (the reported bug).

Once paired, `EmitEvent` sees `paired.crossing` and `EmitCrossingEvent(paired)`:
1. `Ledger.SplitCrossingEvent` (pure, `core/xp_delta.lua`): `old = {xp=oldPart,
   rested=}`, `new = {xp=newPart, rested=}`. `rested` splits proportionally
   (`restedOld = floor(rested * oldPart/xp + 0.5)`, clamped to `oldPart`);
   `restedNew = rested - restedOld` always, never computed separately, so the
   halves add up exactly to the original `xp` and `rested`.
2. Records `old` (real `src`) in the not-yet-rotated session: **this completes
   the old level exactly at its cap**.
3. `CloseCurrentLevel(t, xpRequired)`: `Ledger.CloseLevel` (aggregates sessions,
   attaches `levelTicks` as `entry.ticks`) + `Ledger.RecordLevelClose`, starts a
   fresh `levelTicks`, opens the new level's session (`reached = time()`), and
   resets `matcher`/`reconciler` (activity sampling carries on by itself).
4. Records `new` (same `src`) in the freshly rotated session, at offset 0.
`CloseCurrentLevel` logs the closed level, aggregated sessions, `totalXP`,
total samples and deaths at TRACE. The new session never snapshots `initialXP`
on this path (a real event, the `new` entry, always explains the new level's xp);
only a true cold start (`StartTracking` with `#sessions == 0`) does.

### 4.2 `PLAYER_LEVEL_UP` no longer closes anything
The former mechanism ("pending level-up + fallback timer": `pendingLevelUp`,
`Ledger.PENDING_LEVEL_UP_TIMEOUT`) is gone, including the double-`PLAYER_LEVEL_UP`
edge case it tried to cover. `PLAYER_LEVEL_UP` is now diagnostics only (TRACE of
the event's level, `UnitLevel` at that instant and cached `previousLevel`) plus
`Ledger.UpdateXP()`. The close is triggered by the xp event that crosses the
ding, since `ComputeXPDelta` already detects the crossing by comparing
`UnitLevel()` before/after on each `PLAYER_XP_UPDATE`, independent of event order.

### 4.3 Small decisions
- `CloseLevel` does NOT detect level boundaries: if a real session spans two
  levels the caller hands it the events already split (that is what
  `EmitCrossingEvent` does).
- `levels[level]` is indexed by real level (`db.levels[entry.level] = entry`),
  never insertion order: if the addon is installed at level 20, `levels[20]` is
  level 20 from the first close.
- `sessions[1].initialXP` lives in the session, not in `levels[n]`. Confirmed no
  need to move it: the grey segment is only used by the bar of the level in
  progress, never by a closed `levels` entry.
- The crossing remainder inherits the original event's `src`; an `explore`
  remainder at `off=0` of the new level can only come from the original event
  already being misclassified (the quest→explore bug of 3.4), not from
  reclassifying the remainder. To confirm with new data.
- `reached` = real ding time if a level-up triggered it, or start time on a
  cold start (same kind of approximation as `initialXP`: the pre-install ding
  is unknowable). `deaths` counts each `PLAYER_DEAD`, separate from the `dead`
  activity counter (samples spent dead don't say how many times).

### 4.4 Known limitation, not fixed
If a second real xp gain happens while the crossing's is still waiting for its
source (within `MAX_MATCH_GAP`) and that second amount still has no source at
the instant the crossing resolves and rotates the matcher
(`matcher = Ledger.NewMatcher()`), it is lost: the old matcher, with it pending
inside, is discarded whole. Window under 1 s; existed with the previous
mechanism, not a regression.

---

## 5. Persistence

- **No migrations (`Ledger.DB_VERSION`, now 9).** On version mismatch (older,
  newer or missing on non-empty data) `Ledger.InitCharDB` discards everything
  and starts clean, returns `db, wiped, oldVersion`, and `ui/events.lua` says
  so in chat at login (never silent). A nil/empty table (first load) is not a
  wipe. v9 = the activity-counter model; all earlier versions and their v1→v8
  migrations were deleted. Reason: the schema changed too often for migrations
  to be worth carrying.
- `LedgerDB` (account) is never wiped by a version change: UI settings don't
  depend on the data schema; `Ledger.InitDB` only fills gaps and stamps the
  version.
- **View defaults reset (`Ledger.ApplyViewDefaultsOnce`).** `barShown`,
  `timeBarShown`, `rateShown` used to default to `false`, and `InitDB` stamped
  that `false` in `LedgerDB` on first load, so a saved `false` from an old
  version is not a choice (indistinguishable from a never-touched view) and the
  new `true` defaults wouldn't have reached anyone with an existing `LedgerDB`.
  The first time (no `viewDefaultsApplied`) all three are set to default and
  `viewDefaultsApplied = true` is stamped; after that, any saved value is a
  real choice. Accepted cost: whoever hid a view on purpose with an old version
  sees it once more. On the beta (1.2) every launch starts from defaults.
- **`LedgerCharDB` history.** First declared in the `.toc` with no code touching
  it (stayed `nil`); then `LedgerCharDB = LedgerCharDB or {}`, which only made
  the container, so writes to `levels`/`sessions` would still have failed;
  `InitCharDB` (pure, tested) guarantees the full structure at once. Every
  write goes through structure-guaranteeing helpers (`InitCharDB`,
  `AppendRecord`/`AddEvent`, `RecordLevelClose`).
- **No swallowed errors.** A review found no `pcall`/`xpcall` that silently ate
  handler errors; the standing rule is in `CLAUDE.md`.
- The event list persists directly: `sessions` (local of `ui/xp_capture.lua`)
  **is** `LedgerCharDB.sessions` (same table, assigned by reference in
  `StartTracking` on the first `PLAYER_ENTERING_WORLD`), so no separate save
  step exists; likewise the counters. The matcher and reconciler are memory only.
- The `src` enum migration (v4→v5): `kill=1, quest=2, explore=3, unknown=4,
  previous=5` (`previous` is `Ledger.BAR_INITIAL_SRC`, the synthetic segment for
  xp before recording, never persisted for real). String↔id translation lives
  only at the persistence boundary: `AddEvent`, `XPBySource`,
  `xp_bar.lua: MergeConsecutive`, `state_dump.lua: FormatSession`.

---

## 6. UI reference (composition bar, activity bar, hover, rate number)

Moved out of `CLAUDE.md`. The hard rules that came from here are in
`CLAUDE.md` ("UI rules").

### 6.1 Composition bar (`core/xp_bar.lua` + `ui/xp_bar.lua`, `/ldg bar`)
A segmented bar that **visually replaces the native xp bar**
(`LedgerDB.replaceNative`, default `true`), one color per `src` span, showing
what the current level's xp came from. X axis: 0 to `UnitXPMax("player")`.

- **Replacing the native bar** (`AnchorToNativeBar` + `ApplyNativeFill`): the
  frame is anchored to BOTH corners of the resolved native bar
  (`TOPLEFT`/`BOTTOMRIGHT` on its own), so it takes its exact position and size
  and follows them live; same `FrameStrata`, `FrameLevel` +10 to draw over it
  and win the mouse. **Only the native fill is hidden, never its container**
  (its geometry is the anchor and size reference, and its background/track
  stays): it is the `StatusBar` texture of the xp bar
  (`GetStatusBarTexture():SetAlpha(0)`), without removing, reparenting or
  hooking anything, so Blizzard's tracking-bar code keeps working and restoring
  is giving the alpha back. The `StatusBar` is searched on the resolved bar,
  its `.StatusBar` and its children, and identified by range
  (`GetMinMaxValues` == `UnitXPMax`, like `FindMatchingChild`, so the
  reputation bar isn't picked). Each step is under `pcall` and verified (alpha
  must end at 0). **If it can't be hidden cleanly it degrades to overlaying**
  (what the frame already does through its higher level; the native filled part
  is covered by opaque segments) and records the reason, including a
  description of what the native bar is built from, in `Ledger.nativeFillInfo =
  { status, detail }` (`hidden` / `overlay only` / `visible` / `n/a`), read by
  `/ldg native` and `/ldg probe` and logged at INFO when it changes. The fill is
  hidden only while the composition bar is visible AND replacing; `OnShow`/
  `OnHide` and each `RedrawXPBarFull` reapply it (always restoring first:
  idempotent).
- **Height:** replacing, the frame's is the native bar's; segments anchor to
  the frame's top and bottom edges (they don't copy its height when painting:
  at login the native bar may have no layout yet). `LedgerDB.barHeight`
  (`Ledger.DEFAULTS.barHeight = 8`, no command to change it, edit the
  SavedVariable) only counts with `/ldg native` off and for the activity bar.
  With `/ldg native` off the native fill returns and the composition bar goes
  ON TOP of it (1px gap, height `barHeight`).
- **No mouse of its own:** the unified hover zone (6.4) carries the mouse and
  forwards the degraded-mode drag (`Ledger.StartXPBarDrag`/`StopXPBarDrag`).
  Covering the native bar with that zone cancels its native tooltips; that is
  what replacing it implies.
- **xp label on hover** (`ShowXPBarLabel`/`HideXPBarLabel`): `"{current xp} /
  {level xp}"` (`Ledger.FormatXPLabel`, pure, thousands separator), centered
  and white like the native text; not shown at max level. Not touched: the
  native xp text if "always show" is on (might show under the bar).
- **Data source: ALL the level's sessions, never just the active one.**
  `Ledger.ConcatSeries(sessions, seriesDef)` (generic, `core/series.lua`)
  concatenates each session's `e` array. A `/ldg reset` doesn't change the view.
- **Pure computation** (`Ledger.ComputeBarSegments(flatArray, initialXP,
  widthPx, maxXP)`, iterates `Ledger.SERIES.xp`, assumes no stride or field
  names): merges consecutive records of the same `src` (**mandatory**: without
  merging it is thousands of textures) and spreads `widthPx` proportionally to
  `maxXP`. Rounding is done on the ideal cumulative, not the individual segment
  (`RoundedWidths`), so the width sum never exceeds `widthPx`. Returns
  `{ offset, width, src, restedWidth }` per segment (pixels; `restedWidth` is
  the rested part of `width`, proportional to `rested/xp`, always `<= width`).
- **Initial grey segment:** if `initialXP > 0`, a segment with
  `src = Ledger.BAR_INITIAL_SRC` ("previous") is prepended: the xp the player
  already had in the level before the addon started recording (`UnitXP` when
  the level's first session opens, `StartTracking` with `#sessions == 0`, minus
  the recorded xp at that instant, 0). Stored as `sessions[1].initialXP`, so it
  survives `/reload` like the rest of the session.
- **Palette** (`ui/palette.lua: Ledger.PALETTE`, one table, **shared with the
  activity bar**, never loose values in drawing code): `kill` #C8A34E (muted
  gold), `quest` #3FA98C (teal), `explore` #8C7BB5 (light violet), `unknown`
  #6E6A66 (warm grey), `travel` #4A6FA5 (muted blue), `dead` #8B3A3A (muted dark
  red), `_fallback` (loud magenta, unrecognized src/bucket, should never show).
  `previous` reuses the `unknown` color; `combat` reuses `kill`'s and
  `nonCombat` `unknown`'s (the same color object, not a copy of the hex). Each
  entry is 0-1, computed with Lua hex literals (`0xC8/255`, not hand-rounded)
  and the original hex in a comment. Rested inside a segment is the base color
  lightened 35% toward white (`Ledger.LightenColor`, computed, not a table
  entry). The tooltip uses the same palette, so bar and tooltip can't drift.
- **Border:** 1px black at 60% (`BORDER_COLOR`) around the whole bar, four thin
  `OVERLAY` textures (above the `ARTWORK` segments), created once and only
  repositioned when the frame resizes (`AnchorToNativeBar: LayoutBorder()`).
- **Texture color (confirmed in game):** colors use Blizzard's classic white
  texture (`"Interface\Buttons\WHITE8x8"`, `WHITE_TEXTURE`) plus
  `texture:SetVertexColor(r, g, b, a)`, **never** `texture:SetTexture(r, g, b,
  a)`: numbers passed to `SetTexture` aren't read as RGB but as
  `SetTexture(fileID, wrapH, wrapV, filterMode)`. Confirmed in game that
  `SetTexture(1, 0, 1, 1)` (should be magenta) came out loud green, since `1` is
  some other texture's ID. This was the real reason the bar didn't show despite
  being anchored and having correct segments.
- **Render:** pool of reusable texture pairs (`base` + `rested`, same `ARTWORK`
  layer), never created or destroyed per event, only shown/hidden
  (`GetOrCreatePair`/`ReleaseFrom`). `Ledger.RedrawXPBarFull()` (recompute all;
  level change or load) and `Ledger.ExtendXPBar()` (after each recorded event,
  from `EmitEvent`): since `RoundedWidths` is prefix-stable (appending an event
  never changes already-computed widths before the last segment), repainting
  only the last segment or adding one is enough.
- **Redraw on width change** (2026-09-19): segments are absolute pixel
  offsets/widths computed with the native bar's width AT THAT MOMENT; the frame
  follows the native bar live (two-corner anchor) but the textures inside don't.
  If the native bar had no final layout at login after `/reload` (width 0), every
  segment came out 0px and the bar was invisible until a level-up: xp events
  only repaint the LAST segment and only `PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD`/
  `UI_SCALE_CHANGED` did a full redraw (the activity bar didn't suffer: it
  redraws every second). Now `lastPaintedWidth` keeps the last fully painted
  width, and the frame's `OnSizeChanged`, plus a check at the start of
  `ExtendXPBar` as a safety net, trigger `RedrawXPBarFull` if it differs
  (tolerance 0.5px; `redrawing` prevents reentry from `AnchorToNativeBar`'s
  `SetSize`). Reproduced with a simulated client, **unconfirmed in game**:
  TRACE lines `RedrawXPBarFull: width=0px` followed by `OnSizeChanged: ... full
  redraw` after a `/reload` would confirm it.
- `/ldg bar` toggles `LedgerDB.barShown`.

### 6.2 Locating the native bar, multi-client (`FindNativeXPBar`)
Rewritten 2026-09-17 for the WoW Forever port. Resolved at runtime, trying in
order and keeping the first that exists: `MainStatusTrackingBarContainer`,
`MainMenuExpBar`. **Never** the runtime-generated child name (e.g.
`MainStatusTrackingBarContainer.1b57a533670`, which changes between sessions:
what `/fstack` shows that way is not a global variable, only how that tool
represents an unnamed frame).
- **`MainStatusTrackingBarContainer`** (confirmed in game with `/fstack` on both
  Classic Era 1.15.x and the beta; the initial assumption that Classic Era used
  `MainMenuExpBar`, the classic Vanilla bar, was wrong): the tracking-bar system
  shared with retail (`Interface/AddOns/Blizzard_ActionBar/Classic/
  StatusTrackingBarTemplate.xml`). Inside it `Ledger.FindMatchingChild(container)`
  finds the child whose `child.StatusBar:GetMinMaxValues()` equals
  `UnitXPMax("player")`: needed on Classic Era because the container can have
  several children at once (confirmed: with reputation tracking also on there
  are two children with `.StatusBar`; the reputation one has its max normalized
  to `1`, so comparing by `UnitXPMax` tells them apart). A matching child is the
  anchor (its width/position, not the container's). With no matching child (WoW
  Forever: its container has no such child structure, children anchor
  TOPLEFT/BOTTOMRIGHT with no offset), the **container itself** is the anchor:
  its geometry already is the bar's.
- **`MainMenuExpBar`:** defensive fallback if the container doesn't exist at
  all. Never reached on either confirmed client.
- **Degraded mode** (`DegradedAnchor`) if no candidate exists: the bar sits at a
  default position (`LedgerDB.barDefaultPos`, `Ledger.DEFAULTS.barDefaultPos`)
  with fixed width (`Ledger.DEFAULTS.barDefaultWidth = 200`) and becomes
  draggable (`RegisterForDrag`, saving to `LedgerDB.barDefaultPos`), never when
  truly anchored (dragging would be pointless: the next redraw would glue it
  back), so a local flag (`inDegradedMode`) decides whether
  `Ledger.StartXPBarDrag` does anything. One INFO notice per session the first
  time it degrades (never ERROR: a supported mode, not a breakage).
- **Never constants:** width and position always come from the resolved frame
  (`nativeBar:GetWidth()`) or the degraded SavedVariable/default; the only
  hardcoded width is `barDefaultWidth`, the emergency value.
- **The bar anchors even when hidden** (`RedrawXPBarFull` always anchors, paints
  only if visible): the activity bar and the xp/hour number hang off this
  frame, so it needs its anchor points even if the player hid it on purpose;
  otherwise after `/reload` with only this one hidden the other two were left
  without an anchor and invisible (WoW doesn't draw a frame whose anchor is
  unresolved). `PLAYER_LOGIN` always calls it; the others are shown and
  anchored after, in order.
- **Re-anchor on `PLAYER_ENTERING_WORLD` and `UI_SCALE_CHANGED`**: both fire
  `RedrawXPBarFull()` + `RedrawTimeBar()`, re-resolving the anchor from scratch
  (never cached): covers `Blizzard_StatusTrackingBar` loading late and the UI
  being rearranged by a scale change.
- **`Ledger.xpBarAnchorInfo = { source, width, height }`** is left by each
  `AnchorToNativeBar` (`source`: `"MainStatusTrackingBarContainer (matched
  child)"`, `"... (container)"`, `"MainMenuExpBar"`, `"degraded (no anchor
  found)"`); read by `/ldg probe`.

### 6.3 Activity bar (`core/time_bar.lua` + `ui/time_bar.lua`, `/ldg time`)
Parallel to the composition bar (same width and horizontal position, 2px above
it, its own height `barHeight`), shows how the current level's samples split
among the four activities. **Different axis from the xp bar:** it always fills
100% of the width (proportional to total samples, not to an external maximum),
so the two bars are not comparable pixel to pixel.
- **Fixed order** (`Ledger.TICK_KEYS = { "combat", "nonCombat", "travel",
  "dead" }`), left to right, so the shape is recognizable at a glance; never
  reordered by size, unlike the xp bar (which merges by arrival order).
- **Pure computation** (`ComputeTimeBarSegments(ticks, widthPx)`): splits
  `widthPx` by `ticks[key] / ticks.total` reusing `Ledger.RoundedWidths`. No
  samples yet, no segments.
- **Data source:** `LedgerCharDB.levelTicks`, read as is on each redraw.
- **Colors and border:** the same `Ledger.PALETTE` and 1px border as the xp bar.
- **Render:** one fixed texture per activity, no pool. `RedrawTimeBar()` is
  called **from the same 1 s ticker that samples activity**
  (`SampleTimeState`), **never from xp events**: travel/non-combat/dead spans
  generate no xp event.
- **Tooltip: percentages only**, sections 2 and 3 of the unified tooltip
  (`Ledger.FormatTickLines`, colored by `PALETTE[key]`), level then active
  session. `/ldg time` toggles `LedgerDB.timeBarShown`, independent of
  `/ldg bar`.

### 6.4 Unified hover zone (`core/bar_hover.lua` + `ui/bars_hover.lua`)
One mouse zone over both bars (before, each bar had its own tooltip and the
mouse had to be fine-tuned to tell them apart). `LedgerBarsHover` is a
drawing-less frame covering from the bottom-left of the lowest visible bar to
the top-right of the highest (the 2px gap between bars is inside); only visible
bars count, and with none it hides. It readjusts itself with each bar's
`OnShow`/`OnHide` (`HookScript`), so any path that shows or hides them works.
Same `FrameStrata` as the xp bar and 5 levels above it (over the native bar,
which has its own mouse and tooltips). The bars have no mouse.
- **Content, pure** (`Ledger.BuildBarTooltipSections`) returns `{ { title,
  rows = { { text, color = {r,g,b} }, ... } }, ... }` in order: (1) `Level xp
  composition` (xp by origin over ALL the level's sessions + rested if any,
  `Ledger.XPBySourceAcrossSessions`); (2) `Level activity (% of samples)`;
  (3) `This session (% of samples)`. Takes `{ sessions, levelTicks, palette,
  showXP, showTime }`: the palette arrives as a PARAMETER (`core/` can't know
  `ui/palette.lua`); `showXP`/`showTime` false omit those sections; a section
  with no data isn't emitted empty. The `ui/` layer only walks that shape.
- **Label:** on enter, the xp label shows over the xp bar, hidden on leave. Per
  zone, not per bar: hovering the activity bar shows it too.
- **Placement:** `ANCHOR_NONE` with the tooltip hanging ABOVE the xp/hour number
  if it is stacked on the bars (default position, no `ratePos`), so it doesn't
  cover it; otherwise above the zone.
- **Refresh:** while the mouse is inside, an `OnUpdate` limited to 1 s rebuilds
  label and tooltip.

### 6.5 xp/hour number and hover panel (`core/rate.lua` + `ui/rate_frame.lua`, `/ldg rate`)
Its own "prominent" frame (`SetFrameStrata("HIGH")`), anchored above the highest
visible bar. **The stack, bottom up** (2px between each): composition bar (in
the native bar's spot; 1px over it with `/ldg native` off) → activity bar →
this number. If the activity bar is visible the number anchors to IT
(`frame:SetPoint("BOTTOM", Ledger.timeBarFrame, "TOP", 0, 2)`), else to the xp
bar (`Ledger.xpBarFrame`). (It used to always anchor to the xp bar, from when the
bars were never visible together; that painted the number over the activity
bar.) A single anchor point centers it horizontally by construction. It is a
live WoW anchor relation, so it follows the bar when it moves or redraws
(including degraded mode); re-anchoring is only needed when WHICH bar is
highest changes: `Ledger.RestoreRatePosition()` (reads
`Ledger.timeBarFrame:IsShown()`) is called on `PLAYER_LOGIN` after the activity
bar's visibility is set, and in `ToggleTimeBar`. If the player dragged it
(`LedgerDB.ratePos`), that absolute position wins.
- **The number:** xp/hour of the **active session**
  (`Ledger.TotalXP(session, includeRested) / session.ticks.total * 3600`,
  `Ledger.ComputeXPRate`), never of the level (that is the hover panel's data).
  `GameFontNormalHuge`, white, on a semi-transparent black background
  (`SetBackdropColor(0,0,0,0.6)`) that fits the text with padding
  (`ResizeToText`, `PADDING_X`/`PADDING_Y`) instead of a fixed width.
- **Format** (`Ledger.FormatXPRate`, pure): rounds to the nearest integer,
  thousands separator by hand (classic Lua idiom: insert a comma before each
  group of 3 digits repeatedly until `gsub` finds no more) and suffix
  `" xp/h"`. `nil` formats as `"-"`, never `"0 xp/h"` or an invented number.
- **Dash under 60 samples** (`Ledger.RATE_MIN_SAMPLES = 60`): below that the
  denominator is so small the rate explodes (50 xp in 5 samples = 36000 xp/h);
  `ComputeXPRate` returns `nil`. A zero numerator with plenty of samples is
  still a real rate of `0` (not a dash): the dash is only for a small
  denominator, never for small or zero xp.
- **Respects `includeRested`:** `Ledger.ComputeHeadlineRates` takes the toggle
  and forwards it to `TotalXP`/`TotalXPAcrossSessions` for both rates.
- **Refresh:** its own `C_Timer.NewTicker(1, Ledger.RefreshRateFrame)`,
  independent of the two in `ui/xp_capture.lua` (the addon already had more than
  one 1 s ticker, each with its own responsibility). `RefreshRateFrame` does
  nothing if the frame is hidden, and redraws the hover panel too if open.
- **Draggable, position persisted:** `RegisterForDrag` + `OnDragStop` save
  `LedgerDB.ratePos` (same pattern as `ui/frame.lua: SavePosition`).
  **Deliberately no `Ledger.DEFAULTS` entry**: while `ratePos` is `nil` (never
  dragged) `RestoreRatePosition()` re-anchors over the bar stack; once dragged,
  that absolute position wins at every login, like the main panel's.
- `/ldg rate` toggles `LedgerDB.rateShown`.

**Hover panel** (`LedgerRateHoverPanel`, own frame, **never `GameTooltip`**,
unlike the bars): built from a generic section structure in `core/rate.lua`.
- `Ledger.BuildRatePanelSections(rates)` (pure, `rates = { sessionRate,
  levelRate, sessionPlayed, levelPlayed }`: the two rates come from
  `ComputeHeadlineRates`, the two times, in seconds or `nil`, are added by
  `ui/rate_frame.lua` on each refresh) returns `{ { title, rows = { {label,
  value, color}, ... }, notes = { "line", ... } }, ... }` (`notes` optional, in
  `Ledger.RATE_NOTE_COLOR`): `"XP/hour"` with `"This session"` (same number as
  the main frame, white, `RATE_HIGHLIGHT_COLOR`) and `"This level"` (light grey,
  `RATE_DEFAULT_COLOR`); and `"Played time"` (always present) with `"This
  session"`/`"This level"` as a duration (`Ledger.FormatDuration`: `45s`,
  `12m 05s`, `1h 23m`, seconds dropped from the hour up; `nil` → `-`). These are
  **exact clocks, display only**: not persisted, not in `levels`/`sessions`,
  feeding no xp/hour or other metric (samples stay the only source of the
  activity split and of the rate's denominator). Adding recent-level history or a
  per-source breakdown later is one more entry in that list; `RenderHoverPanel`
  walks sections and rows generically.
  - **History:** the section was `"Sampled time"` (1 sample = 1 s, with a note
    that it might differ from real played time) until 2026-09-21, when the
    played clocks replaced it; the note went with it.
  - **Session** (`Ledger.SessionPlayedSeconds(session, now)`): `time() -
    session.t0`. **Known limit:** it assumes being connected from start to end of
    the session, but a saved session resumes after a relog (`StartTracking:
    resuming saved sessions`, with its original `t0`), so on a client that does
    load SavedVariables (Classic Era) the offline time in between counts as
    played. On the beta (which doesn't load them at startup, see 1.2) every start
    is a cold session and it doesn't happen. See 9.3.
  - **Level** (`Ledger.LevelPlayedSeconds(ref, currentLevel, now)`):
    `ref.seconds + (time() - ref.receivedAt)`, with `ref = Ledger.levelPlayedRef`
    (see 2.1). `nil` (a dash, never a 0) while no reply has arrived, or if the
    reference is from another level (`ref.level ~= UnitLevel`: after a ding, the
    old level's time is not shown as the new one's until the new reply arrives).
- **Own colors, not `Ledger.PALETTE`:** they are about visual emphasis, not
  src/bucket identity, and `core/` must stay loadable and testable alone.
- **Render:** pool of reusable `FontString`s (`GetOrCreateLine`); the panel
  resizes to its content. `lastRates` (local) caches the ticker's last
  computation so `OnEnter` doesn't recompute.

---

## 7. Panels and tools

- **Debug panel and dump** (`core/state_dump.lua`): `Ledger.FormatState(charDB)`
  is the pure serializer shared by `/ldg debug` and `/ldg dump`: active-session
  header (level, mode, manual, xp, rested, activity %) + up to 30 events (most
  recent first, `mm:ss.t | xp | src | rested=N` via `Ledger.FormatOffset`, `src`
  translated back through `Ledger.SRC_NAMES`, no upper bound on minutes) +
  summary of `levels` in level order (with `totalRested`, `deaths` and activity
  in percent). It reads `charDB` as a parameter and iterates `Ledger.SERIES.xp`.
  `ui/debug_frame.lua` is the thin layer (movable/resizable frame, read-only
  multiline EditBox, refresh button, 2 s auto-refresh checkbox via
  `C_Timer.NewTicker`) and also shows the log buffer (`/ldg log show`). It keeps
  its own copy of the text-window pattern (auto-refresh, other layout).
- **Text windows** (`ui/text_window.lua: Ledger.CreateTextWindow(opts)`): shared
  factory for `/ldg export` and `/ldg check`: movable/resizable frame + read-only
  EditBox in a ScrollFrame, content selected (`HighlightText`) on every
  `SetText`, Escape via `UISpecialFrames` AND `OnEscapePressed` (a focused
  EditBox, the normal state here so Ctrl+C works at once, swallows Escape before
  the global handler sees it).
- **Export** (`core/export.lua` + `ui/export_frame.lua`): dumps the whole
  `LedgerCharDB` (all current-level sessions and all closed levels). Shared
  intermediate model (`Ledger.BuildExportModel`, pure) decodes the raw shape
  (numeric `src`, flat arrays, `levels` by number) so neither format
  reimplements the `src` translation or totals. Activity is exported as RAW
  counters (`ticks_*` in CSV); JSON also carries `played` (or `null`). **JSON is
  written by hand**: no JSON library exists in the addon sandbox and none can be
  added, so the encoder isn't generic (it never guesses whether an empty table
  is an array or object) but a handful of primitives (`JSONString`/`JSONNumber`/
  `JSONEscapeString`, the last escaping backslash, quotes and all control
  characters `0x00`-`0x1F` as `\uXXXX`; `JSONNumber` uses `%.14g` to avoid both
  scientific notation and a trailing `.0`). Tests (`spec/export_spec.lua`)
  validate the JSON by decoding with `dkjson`, a **test-only** dependency (via
  luarocks). CSV has three sections (`# levels` / `# sessions` / `# events`,
  blank-line separated), the lightest convention that still pastes into a
  spreadsheet; `# sessions` rows always carry their aggregates. **Size cap**
  `Ledger.EXPORT_MAX_EVENTS = 1000` (sum over the current level's sessions): a
  huge EditBox can drag the panel down, so above it both formats drop the raw
  events and keep per-session aggregates (`includeEvents`/`totalEventCount` in
  the JSON, a `# events omitted: ...` line in the CSV); closed levels are never
  trimmed (already aggregates). Format choice persists for the game session
  only (local variable). Each refresh calls `editBox:SetFocus()` then
  `HighlightText()`.
- **Reconciliation** (`core/check.lua` + `ui/check_frame.lua`): same split as the
  dump. `Ledger.BuildCheck(charDB, player)` (pure, `player = { level, xp }`)
  returns `{ discrepancies, lines = { {status, text}, ... } }`;
  `Ledger.FormatCheck` renders plain text. Line states: `title` (first: `ALL OK`
  or `N DISCREPANC(Y|IES) FOUND`), `section`, `info`, `ok`, `bad` (the only one
  that counts), `skip` (not verifiable, neither counted nor silently accepted).
  Markers are **text, not color codes** (Ctrl+C would copy the escapes): `bad` →
  `>>> [!!] `, `ok` → `    [OK] `, `skip` → `    [??] `.
  - Current level: recorded xp (raw sum over ALL the level's sessions, never
    affected by `includeRested`) vs `UnitXP`; `diff = recorded - real`,
    **positive = double counting, negative = lost events**. With an initial grey
    segment the verdict uses `recorded + initial - real`. Also flags a session
    level different from the player's, and any `unknown` xp.
  - Closed levels: `sum(bySource) + initialXP` vs `entry.xpRequired`; `bySource`
    not `totalXP` because the latter depends on the `includeRested` at close
    (not stored). No `xpRequired` → `skip`.
  - Time is information only, never a discrepancy: level and session activity as
    percentages plus the last `/played` next to the samples the level had then
    (`"/played, this level: 2472s played vs 2450 samples at that moment,
    difference +22"`) with a note that it isn't an error.
  - xp pending pairing (up to ~1 s in the matcher) can look like a transient
    negative right after a kill or ding; the window says so and `Refresh` rereads.
- **Probe** (`core/probe.lua` + `ui/probe.lua`, `/ldg probe`): with two clients
  from one package, it checks on the real client what API exists and in what
  shape, instead of assuming. Never aborts: each check is isolated. Same split as
  the dump: `ui/probe.lua: Ledger.GatherProbeData()` is the only piece touching
  WoW API (every optional call through `pcall`) and returns a flat table;
  `core/probe.lua: Ledger.FormatProbe(data)` is pure, tested with hand-made data.
  Reports: `GetBuildInfo` (version, build, date, tocversion: the most direct
  check of which client a `/reload` is running on); the APIs `UnitXP`,
  `UnitXPMax`, `GetXPExhaustion`, `RequestTimePlayed`, `UnitOnTaxi`,
  `GetUnitSpeed`, `UnitAffectingCombat`, `UnitIsDeadOrGhost`, `issecretvalue`
  (`absent` if not a function, else `pcall` with `"player"` and every returned
  value, trailing `nil`s trimmed, or `call failed (...)`); the four before
  `issecretvalue` feed the activity sampler; `issecretvalue` (should give
  `false`) is what `IsReadableMessage` prefers for secret chat messages (1.3),
  and absent only means the `pcall` probe is used instead; all `COMBATLOG_XPGAIN_*` globals (both families); `nativeFill`
  (`Ledger.nativeFillInfo`); `C_ChatInfo` presence (unused so far, a reference
  for future chat-channel filtering); `xpBarAnchor` (`Ledger.xpBarAnchorInfo`,
  `"not resolved yet"` if the bar was never redrawn this session).
  `RequestTimePlayed` is never called bare: `SafeRequestTimePlayed()` (exposed
  as `Ledger.RequestPlayedReading`) checks it's a function and wraps it in
  `pcall`; if missing, `LedgerCharDB.played` just isn't refreshed.
  `UnitXP`/`UnitXPMax` stay unwrapped on purpose: they are the addon's core and
  no degraded mode makes sense; if a client lacks them the addon can't track xp
  there, which is exactly what `/ldg probe` should show, not hide.
- **Log** (`core/log.lua`): in-memory state (`Ledger.logState =
  Ledger.NewLogState()` in `ui/events.lua`): `level` (`off | error | info |
  trace`, default trace), `chat` (echo), `buffer` (ring of up to
  `Ledger.LOG_BUFFER_CAPACITY = 200` `{t, level, msg}`, oldest first).
  `Ledger.LogMessage(state, level, msg, t)` drops a message more verbose than
  `state.level`, else appends (trimming from the front) and returns `true` when
  it must also echo to chat. Time is a parameter. `Ledger.Log(level, msg)`
  (`ui/events.lua`) adds `GetTime()` and echoes. The matcher functions take an
  optional `log(level, msg)` (no-op if omitted, which is why
  `spec/xp_gain_matcher_spec.lua` passes untouched). Chat echo is colored per
  level (`Ledger.FormatLogChatLine`/`Ledger.LOG_COLORS`: `error` ff5555, `info`
  55ccff, `trace` 9a9a9a; `[level]` also in the text in case color isn't seen;
  `|` doubled to `||` so a raw game message isn't read as an escape; multi-line
  colored line by line). No color in the `/ldg log show` panel (EditBox for
  Ctrl+C; `Ledger.FormatLogBuffer`, which keeps the `[level]` tag).

---

## 8. Hooks and deploy internals

- `PostToolUse` on `Write|Edit` (`hooks/post-edit.sh`): a no-op unless the file
  is under `Ledger/`; runs `busted`; if it fails, **doesn't deploy** and returns
  `decision: "block"` with the detail plus a `systemMessage` summary; if it
  passes, runs `./deploy.sh --if-installed <flavor>` for each flavor of
  `LEDGER_HOOK_FLAVORS` (default `forever classic_era`); a failed deploy also
  blocks; with no flavor to deploy to it warns without blocking; confirms with
  `Ledger v<toc version> deployed to <flavors> at <time>  [<busted summary>]`.
- **Speed** (~1.2 s with tests and two flavors): `busted` on DrvFs (`/mnt/c`)
  takes ~2.3 s, mostly I/O (specs do many `loadfile`s over the 9p mount) and
  ~0.2 s on ext4. Since specs only load `Ledger/core/*`, the hook runs them on a
  fresh copy of `Ledger/` + `spec/` in a native temp directory (same content and
  relative paths); if the copy fails it runs in place. A `flock` serializes
  simultaneous runs.
- `SessionStart` (`startup|resume|clear`, `hooks/session-start.sh`): prints the
  repo `.toc` version next to each flavor's deployed one (`deploy.sh --status`)
  and says so explicitly on mismatch; also compares **content** (`SAME VERSION BUT
  CONTENT DIFFERS (N files: ...)`), since the version only bumps when a change is
  closed out. Claude gets the same text as context. A flavor without Ledger is
  informational, not a mismatch.
- Runs in WSL and uses only `python3` (no `jq` on this machine) to read/write
  JSON. If Claude Code was opened before `.claude/` existed, open `/hooks` once
  or restart the session.
- Disabling, least to most drastic: `touch .claude/hooks.disabled` (both hooks,
  no restart; `rm` to re-enable; gitignored); `LEDGER_HOOKS=off claude`;
  `"disableAllHooks": true` in `.claude/settings.local.json` (also gitignored,
  turns off every Claude Code hook); `/hooks` to review the active ones.
- Load-time `print` lines in `core/`: removed 2026-09-20 (see 3.7).

---

## 9. Open items

### 9.1 Unconfirmed assumptions the code relies on
- `COMBATLOG_XPGAIN_EXHAUSTION*` is the right global-string family for the
  rested bonus on 1.15.x and interface 16001 (3.3). Check `/ldg strings`.
- Zone discovery arrives via `CHAT_MSG_SYSTEM` / `ERR_ZONE_EXPLORED_XP` on both
  clients (3.5).
- Whether Classic Era 1.15.x has the same `GetUnitSpeed` "secret" tainting
  (1.3), and confirming combat+moving never appears via `/ldg log show`.
- That a secret `CHAT_MSG_COMBAT_XP_GAIN` is always combat xp (so enqueuing it as
  `"kill"` is right), and which other chat messages arrive secret (1.3).
- `UnitXPMax("player")` at `PLAYER_ENTERING_WORLD` is always the right level's
  (for the initial `previousMaxXP` cache), and a multi-level jump really fires
  `PLAYER_XP_UPDATE` once for the whole jump, not once per level.
- Blizzard doesn't rebuild the native xp bar (and its fill) through an event
  Ledger doesn't reapply.

### 9.2 To verify in game (deduplicated; nothing here has been tested on a real client)
- **Level-up:** the old level closes exactly at its cap (not above); the new one
  starts with the real `src` (never an orphan `unknown` of tens of xp);
  `/ldg dump` shows the `levels` entry after a ding; the composition bar starts
  clean in the new level. Confirm the crossing remainder's `src` with new data.
- **Quest vs explore:** no real turn-in classified `explore` (3.4), reviewing the
  TRACE `ExploreCheck:` of several in a row and one with a real simultaneous
  kill. Confirm the bug `src = "unknown"` fix (3.2) holds for the other real
  variants of this client, not just the rested case reproduced in tests.
- **`reached` / `deaths`:** `reached` captures the real ding instant (not just
  cold start); `deaths` counts every `PLAYER_DEAD` of the level, separately from
  the `dead` activity counter.
- **Activity sampler** (rewritten 2026-09-19; tested only with a simulated
  client that loads the full `.toc`): `UnitAffectingCombat`/`GetUnitSpeed`/
  `UnitIsDeadOrGhost`/`UnitOnTaxi` behave as `SampleTimeState` assumes on both
  clients (`/ldg probe` includes them); `levelTicks` and session counters go up
  one at a time and `total` is always their sum; a closed level carries
  `entry.ticks` and the next starts at zero; a SavedVariable of an older version
  is wiped with the login notice and no errors.
- **`/ldg probe` on both real clients** (WoW Forever 1.60.1 / interface 16001
  and Classic Era) and compare: it must run without errors, and its results
  confirm or refute the assumptions about `UnitXP`, `GetXPExhaustion` vs the
  chat-message rested bonus, and the `COMBATLOG_XPGAIN_*` global strings. If
  anything differs, decide whether to branch a path by interface version.
- **Anchor resolution** (6.2): on Classic Era `xpBarAnchor` in `/ldg probe` still
  says `"...matched child"` with visuals identical to before the port; on WoW
  Forever the child-less container anchors with its own geometry
  (`"...container"`); forcing the degraded case (temporarily renaming both
  globals) the bar appears at the default position, is draggable, the position
  survives `/reload`, and the INFO notice comes out once per session; and
  `UI_SCALE_CHANGED` truly re-anchors when changing the UI scale.
- **Native bar replacement** (6.1; tested only with a simulated client
  reproducing the assumed shape of the bar on each client): on both clients
  `/ldg probe` → `Native xp bar fill:` says `hidden` (if `overlay only`, the
  reason carries the real structure to fix the search); the composition bar
  covers the native one exactly; nothing breaks in the tracking-bar system
  (changing tracked reputation, leveling up, `/reload`); `/ldg native` and
  `/ldg bar` give the fill back; what happens to the native xp text when "always
  show" is on.
- **Composition bar visuals:** pixel-exact anchoring, contrast of the palette
  over the real UI, the lighter rested tone, the 1px border, and the tooltip
  (`GameTooltip:SetOwner`/`AddLine` with `OnEnter`/`OnLeave` on a frame without
  `BackdropTemplate` should work but is unconfirmed on this client). Only a
  loose rectangle test was seen so far; the `WHITE8x8`/`SetVertexColor` painting
  and the frame lookup are confirmed. The full-redraw-on-resize TRACE
  confirmation (6.1).
- **Activity bar visuals:** 2px above the xp bar, the fixed order
  combat/non-combat/travel/dead, colors (incl. those reusing `kill`/`unknown`),
  border, tooltip (percentages only, level and session).
- **Unified hover zone:** tooltip and label appear over either bar and the gap
  between them; the zone wins the mouse over the native bar; the tooltip hangs
  well above the xp/hour number; dragging in degraded mode still moves the bar.
- **xp/hour number and panel:** the centered stack looks right with all three
  visible (checked only in a simulated client with a geometry resolver: native
  bar, xp bar, activity bar and number stacked without overlap, also with the
  native bar at width 0 at login, with each hidden on purpose and in degraded
  mode; unconfirmed on the real client, and whether that total height collides
  with other UI above the xp bar); `GameFontNormalHuge` is legible and the
  background fits when digits change; dragging it and re-entering the game
  respects `LedgerDB.ratePos`; the dash really shows on a fresh session and goes
  away after a minute.
- **Played time in the rate panel** (only the pure part is tested):
  `TIME_PLAYED_MSG` arrives after `RequestTimePlayed()` on
  `PLAYER_ENTERING_WORLD` and `PLAYER_LEVEL_UP` on both clients; "This level"
  shows a dash until it arrives and then advances second by second; after a ding
  it resets to ~0 and doesn't show the old level's time; after a `/reload` the
  new value doesn't accumulate on the old one; "This session" matches the clock.
- **Windows** (`/ldg export`, `/ldg check`, `/ldg debug`; same mechanism, none
  confirmed, and `/ldg export` must still behave the same after being
  refactored onto `CreateTextWindow`): `UISpecialFrames` closes with Escape;
  `SetFocus()` + `HighlightText()` really leave the text selected and Ctrl+C
  copies it to the system clipboard (WoW has no direct clipboard API; it relies
  on the client treating a focused EditBox like any native text field); a real
  dump above `Ledger.EXPORT_MAX_EVENTS` doesn't hitch when painted; and for the
  debug panel `SetResizable`, `StartSizing`/`StopMovingOrSizing`,
  `SetResizeBounds` (with `SetMinResize` fallback) and the
  `Interface\ChatFrame\UI-ChatIM-SizeGrabber-*` textures work on 1.15.x.

### 9.3 To decide
- After a logout/disconnect without a reset, the session stays open at the next
  login and keeps receiving events and samples. Undecided whether reopening
  after a long gap should open a new session instead of continuing the old one.
  Decide it together with the rate panel's "This session" clock (`time() - t0`,
  6.5), which counts the offline time after a relog on a client that resumes
  saved sessions: accept it, open a new session after a long gap, or measure the
  session clock from the addon load.
- Nothing reads `Ledger.ReconciliationGap(reconciler)` to warn live if it
  fires; today only the in-memory counter exists (`ui/xp_capture.lua`). Undecided
  where to show it: an automatic warning if the gap doesn't close after a while,
  a line in `/ldg dump` / the debug panel, or both.
- The known limitation of 4.4 (xp lost when a second gain races a crossing).
