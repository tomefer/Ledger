# Ledger

Classic-line WoW addon (Lua 5.1), formerly XPTrack: any "XPTrack" left in code, symlinks or notes is residue.
Rationale, discarded approaches, bug history, the UI design reference and open verification items live in
`docs/decisions.md` (not loaded each session; read the relevant section before revisiting that area).

## Constraints
- Lua 5.1: no goto, no bitwise operators, no `//`. Classic-line API only, nothing from modern retail. No external libraries, no Ace3.
- One package, two clients: Classic Era (interface 11509) and the WoW Forever beta (16001, build 1.60.1), one `Ledger.toc` with `## Interface: 11509, 16001`. Never assume an API behaves the same on both: check with `/ldg probe`, or ask.
- `pcall` only in `ui/`, around optional or client-dependent APIs; never in `core/`. A caught error is always logged, never swallowed.
- The beta ignores SavedVariables that pre-date client launch (client behavior, not fixable): there data lives for one client session only. It also has "secret" values that tainted code can't compare or index: `GetUnitSpeed` (guarded by `pcall` in `IsPlayerMoving`) and chat message payloads (`arg1`; guarded by `IsReadableMessage` in `ui/xp_capture.lua`, which handlers must call before touching the message; `core/` extractors tolerate a non-string `msg`). Details: `docs/decisions.md` 1.3.

## Architecture
- `Ledger/core/`: pure logic, no WoW API. Time, state, palette and anything external arrive as parameters; core never depends on `ui/`.
- `Ledger/ui/`: thin frames and event registration, no logic. `spec/`: busted tests, outside the addon folder.
- Shared state goes through the addon table, always `local ADDON_NAME, Ledger = ...` (never `ns`, never loose globals).
- Slash `/ldg` (alias `/ledger`): `Ledger.ParseCommand` (`core/slash_command.lua`) is pure and tested, `ui/events.lua` only dispatches; `Ledger.SLASH_COMMANDS` is the single source of `/ldg help` and of which subcommands exist (unknown = same as help). `/ldg wipe confirm` is irreversible (only `LedgerCharDB`); `/ldg native` is the emergency exit of the native-bar replacement; `/ldg probe` diagnoses the client. The three views (bar, time, rate) default to visible.

## Data model
- Time series are declared once in `Ledger.SERIES` (`core/series.lua`) and accessed through generic helpers. **Hard rule:** serializers, dumps, exports and checks iterate `Ledger.SERIES`; never reference `"e"` or a hardcoded stride.
- `src` is a numeric enum (`Ledger.SRC_IDS`/`SRC_NAMES`), persisted as an ID; translate only at the persistence boundary, everything else uses the text name.
- Rested bonus: `Ledger.EffectiveXP` is the only place that applies `includeRested`; `TotalRested` and `bySource` are never affected by the toggle.
- `LedgerCharDB.sessions` holds every session of the current level (last = active) and is the persisted table itself; `/ldg reset` closes a session, never deletes it. `levels[n]` is indexed by real level number. Shapes: `core/events.lua: NewSession`, `core/level_close.lua: CloseLevel`.
- Activity is sampled, not timed: each second one counter goes up (`Ledger.ClassifyActivity`, priority dead > combat > moving > rest), live on both the session's and the level's `ticks`. Show it as a **percentage of samples**; never persist a percentage; never reconcile with the clock (exports write raw counters). `/played` is informational only (`LedgerCharDB.played`, read only by `/ldg check`). The played times in the `/ldg rate` panel are separate exact clocks (`time() - session.t0`; `Ledger.levelPlayedRef`, in memory only), display only: they never feed a rate or any metric.
- xp/hour = xp / **samples** x 3600; `nil` (shown as `-`) below `Ledger.RATE_MIN_SAMPLES` (60).
- Writes to `LedgerCharDB` go only through helpers (`InitCharDB`, `AppendRecord`/`AddEvent`, `RecordLevelClose`), never `db.levels[x] = y` by hand.
- **Bump `Ledger.DB_VERSION` (`core/xp.lua`) whenever the shape of `LedgerCharDB` changes.** No migrations: on mismatch `InitCharDB` wipes the character's data and login says so in chat. `LedgerDB` (account settings) is never wiped by a version change.

## xp capture rules
- The xp amount always comes from the `UnitXP` delta (`Ledger.ComputeXPDelta`); chat messages only supply `src` and `rested`. Cache `UnitXPMax`/`UnitLevel` on every `PLAYER_XP_UPDATE` and never read `UnitXPMax` at the ding (it is already the new level's). A jump of more than one level is logged as ERROR, never invented.
- Chat patterns are anchored with `^` only, never `$`. `ClassifyXPGainMatch` never returns `"unknown"`.
- The matcher pairs by time (`MAX_MATCH_GAP` 1.0 s) and, for sources carrying `expectedXP` (quest, explore), first by exact amount (`QUEST_MATCH_GAP` 3.0 s).
- A level closes from the xp event that crosses the ding, never from `PLAYER_LEVEL_UP` (diagnostics only). The crossing event's `src` is resolved for the whole event and then split in two entries (`Ledger.SplitCrossingEvent`); the old part completes the old level exactly at its cap. `initialXP` is snapshotted only on a true cold start.

## UI rules
- Color textures: `WHITE8x8` + `SetVertexColor`, never `SetTexture(r,g,b,a)` (those numbers are read as a fileID).
- One shared `Ledger.PALETTE` for every src/activity color, no loose color values in drawing code. Reuse pooled textures/FontStrings; never create or destroy them per event.
- Native xp bar: hide only its fill (alpha), never its container; resolve the anchor by name at runtime, never by a generated child name. The composition bar anchors even when hidden (other frames hang off it). Everything else: `docs/decisions.md` section 6.

## Known limitations
- A second xp gain that races a level-crossing event and still has no source when the matcher rotates is lost (window under 1 s).
- Nothing reads `Ledger.ReconciliationGap` yet; it only exists as an in-memory counter.
- After a logout without `/ldg reset` the old session stays open at the next login (whether to open a new one after a long gap is undecided). Consequence: on a client that resumes saved sessions the panel's "This session" played time includes the offline gap.

## Workflow
- Tests: `busted`. Deploy: `./deploy.sh [classic_era|forever]` copies only `Ledger/` to the client, replacing the destination; `--if-installed` deploys only where Ledger is installed; `--status` compares repo vs client (version AND contents; exit 0 in sync, 1 out of sync, 2 not installed). `LEDGER_WOW_PATH` is the WoW install **root** (the folder containing `_classic_era_`/`_classic_beta_`), never a full path and never hardcoded (the repo is public). `/reload` in game after every deploy.
- Claude Code hooks (`.claude/settings.json`, `.claude/hooks/`): after `Write`/`Edit` under `Ledger/`, `busted` runs and, only if green, `deploy.sh --if-installed` for `LEDGER_HOOK_FLAVORS` (default `forever classic_era`); a failure blocks. They don't see edits made through `Bash` (`sed`, `git checkout`...): run `deploy.sh` by hand then. `touch .claude/hooks.disabled` turns both hooks off (`LEDGER_HOOKS=off` for one session). Internals: `docs/decisions.md` section 8.
- Closing out a functional change: bump `## Version:` in `Ledger/Ledger.toc` (the startup message reads it from the `.toc` through `GetAddOnMetadata`, never a hardcoded constant), `busted` green, then commit. Commit messages in English, imperative, explaining *why*. One commit per theme (split with `git add -p`); bump the version once, on the commit that closes the work. Never push automatically: the user decides.
- **No git worktrees** (`EnterWorktree`, `git worktree add`, `isolation: "worktree"`) unless the user explicitly asks for one in that request. Work in the main checkout by default; this overrides any generic instruction to isolate work in a worktree.
- On this DrvFs checkout `core.filemode=false`: `chmod +x` never reaches a commit; use `git update-index --chmod=+x <file>`.
