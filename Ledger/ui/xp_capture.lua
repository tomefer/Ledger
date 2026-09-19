-- Ledger - ui/xp_capture.lua
-- Translates WoW events related to gaining xp, dying/resurrecting and
-- played time into core/ calls. Thin layer: all the logic for pairing
-- amount+source, classifying the activity samples and composing the
-- session lives in core/; this file only reads WoW APIs and calls into
-- it.

local ADDON_NAME, Ledger = ...

-- RequestTimePlayed only feeds an INFORMATIONAL reading (the /played
-- line in /ldg check: nothing is calculated from it), and its presence
-- across client builds is exactly the kind of thing /ldg probe exists to
-- check -- so it's never called bare: a build where it's missing or
-- errors just skips the reading instead of breaking the handler that
-- called this. Exposed so /ldg check can ask for a fresh reading when
-- its window opens.
local function SafeRequestTimePlayed()
    if type(RequestTimePlayed) == "function" then
        pcall(RequestTimePlayed)
    end
end
Ledger.RequestPlayedReading = SafeRequestTimePlayed

----------------------------------------------------------------------
-- Combat xp patterns, built at load time from ALL of the client's real
-- global strings whose name starts with "COMBATLOG_XPGAIN_" (never
-- hardcoded nor filtered to a fixed list: the client itself says which
-- variants exist, in any language). No need to restrict to
-- "FIRSTPERSON" variants: the CHAT_MSG_COMBAT_XP_GAIN event itself
-- already only fires for the player's own xp, and
-- core/chat_patterns.lua: Ledger.ClassifyXPGainMatch uses the presence
-- (or not) of a creature name in the matching variant to tell "kill"
-- apart from "explore" -- never "unknown", because the event itself
-- already confirms it's combat or exploration xp.
----------------------------------------------------------------------

-- Also stores the global string's name and its literal text (not just
-- the derived pattern), so they can be inspected with /ldg strings.
local xpGainStrings = {}
for key, value in pairs(_G) do
    if type(value) == "string" and key:find("^COMBATLOG_XPGAIN_") then
        table.insert(xpGainStrings, { name = key, text = value, pattern = Ledger.BuildPattern(value) })
    end
end
Ledger.xpGainStrings = xpGainStrings

-- The rested-bonus suffix ("(+86 exp Rested bonus)") is attached to the
-- end of the combat xp message, not the start, so it's searched for
-- with an unanchored pattern (Ledger.BuildSuffixPattern) against a
-- separate family of global strings. BEST EFFORT, UNCONFIRMED IN-GAME:
-- it's assumed they exist as COMBATLOG_XPGAIN_EXHAUSTION* (Blizzard's
-- convention for the rested/exhaustion bonus for several expansions
-- now) -- check with /ldg strings, which also prints this family with
-- its literal value in this client.
local restedStrings = {}
for key, value in pairs(_G) do
    if type(value) == "string" and key:find("^COMBATLOG_XPGAIN_EXHAUSTION") then
        table.insert(restedStrings, { name = key, text = value, pattern = Ledger.BuildSuffixPattern(value) })
    end
end
Ledger.restedStrings = restedStrings

-- Area-discovery xp ("Discovered %s: %d experience gained") is announced
-- as a SYSTEM message, never as CHAT_MSG_COMBAT_XP_GAIN (confirmed from
-- a real log: a cave's 70 xp produced no combat-xp event at all and got
-- released as "unknown"). Built from the client's own global strings
-- like the two families above; ERR_ZONE_EXPLORED (no xp, max level) is
-- deliberately not included -- there's no amount to pair. UNCONFIRMED
-- IN-GAME that the event is CHAT_MSG_SYSTEM on both clients: every
-- system message is TRACE-logged (see the handler) to check.
local exploreStrings = {}
for _, name in ipairs({ "ERR_ZONE_EXPLORED_XP" }) do
    local value = _G[name]
    if type(value) == "string" then
        table.insert(exploreStrings, { name = name, text = value, pattern = Ledger.BuildPattern(value) })
    end
end
Ledger.exploreStrings = exploreStrings

-- Classifies the message (core/chat_patterns.lua: Ledger.ClassifyXPGainMatch,
-- pure logic) and logs every variant tried at TRACE level (matched or
-- not, and what it captured if it matched), plus the resulting final
-- category. Also extracts the rested bonus if the message carries the
-- suffix (Ledger.ExtractRestedBonus, also pure).
--
-- Returns category, rested, capturedAmount. capturedAmount is the xp
-- figure the matched variant itself captured (nil if nothing matched,
-- or the matched variant has no %d) -- for a "kill" variant
-- ("%s dies, you gain %d experience.") that's the LAST captured group,
-- since %d follows %s in the text; for "explore"
-- ("You gain %d experience.", no %s) it's the only one. Fed to
-- Ledger.HasPendingQuestSource by the caller so a category="explore"
-- message can be checked against a pending QUEST_TURNED_IN by exact
-- amount, not just by presence.
local function HandleCombatXPGainMessage(msg, t)
    local category, attempts = Ledger.ClassifyXPGainMatch(xpGainStrings, msg)

    for _, attempt in ipairs(attempts) do
        if attempt.matched then
            Ledger.Log("trace", string.format(
                "CHAT_MSG_COMBAT_XP_GAIN match t=%.3f global=%s pattern=%s captured=[%s] category=%s",
                t, attempt.name, attempt.pattern, table.concat(attempt.captured, ", "), category))
        else
            Ledger.Log("trace", string.format(
                "CHAT_MSG_COMBAT_XP_GAIN no-match t=%.3f global=%s pattern=%s",
                t, attempt.name, attempt.pattern))
        end
    end

    if #attempts == 0 or not attempts[#attempts].matched then
        Ledger.Log("trace", string.format(
            "CHAT_MSG_COMBAT_XP_GAIN t=%.3f no variant matched -- default category %s (never unknown)",
            t, category))
    end

    local rested = Ledger.ExtractRestedBonus(restedStrings, msg)
    if rested > 0 then
        Ledger.Log("trace", string.format(
            "CHAT_MSG_COMBAT_XP_GAIN t=%.3f rested bonus detected: rested=%d", t, rested))
    end

    local capturedAmount
    local lastAttempt = attempts[#attempts]
    if lastAttempt and lastAttempt.matched then
        capturedAmount = tonumber(lastAttempt.captured[#lastAttempt.captured])
    end

    return category, rested, capturedAmount
end

----------------------------------------------------------------------
-- State: all sessions of the current level (the last one is active)
-- and the buffer that pairs amount (PLAYER_XP_UPDATE) with source
-- (combat message).
--
-- `sessions` is not an in-memory copy: it IS the same table as
-- LedgerCharDB.sessions (assigned by reference in StartTracking), so
-- adding a session or an event to an existing session writes directly
-- into the SavedVariable, with no separate "save" step. Closed sessions
-- are kept here until the level closes: that close (core/level_close.lua
-- + Ledger.RecordLevelClose) aggregates ALL of the level's sessions,
-- not just the last one.
----------------------------------------------------------------------

local sessions -- nil until the first PLAYER_ENTERING_WORLD
local matcher
local reconciler
local previousXP
local previousMaxXP -- cached UnitXPMax: see PLAYER_XP_UPDATE, never
                     -- read UnitXPMax at the instant of a ding
local previousLevel

-- GetTime() corresponding to offset 0 of the current session.
-- session.t0 no longer serves this purpose (see OpenSession: it's now
-- time(), absolute, not GetTime()): sessionStartRef is only for
-- computing offsets within the current session, and gets rebound
-- whenever `sessions` starts pointing at a different session (a new one
-- or one resumed after /reload), so the offset keeps counting from
-- where it left off without depending on GetTime() surviving a client
-- restart.
local sessionStartRef

local function CurrentSession()
    if not sessions then return nil end
    return sessions[#sessions]
end

-- Opens a new session. t0 is stored as absolute time() (survives a
-- client restart; GetTime() doesn't) -- see Real SavedVariables
-- analysis, point 3. sessionStartRef (the GetTime() reference for THIS
-- session's offsets) gets rebound right here to "now": the new
-- session's first event falls at offset 0.
local function OpenSession(t, level, manual)
    local session = Ledger.NewSession(time(), level, nil, manual)
    table.insert(sessions, session)
    sessionStartRef = t
    return session
end

-- Closes the current level: aggregates all in-progress sessions (whole
-- and entirely of that level, the boundary is never detected here)
-- into the `levels` entry and opens the new level's session. Always
-- triggered by EmitCrossingEvent (below), never by PLAYER_LEVEL_UP
-- directly: that event today is only diagnostic and refreshes the
-- panel, see the dispatcher.
--
-- Time takes no calculation here: the level's activity counters were
-- incremented live by the sampler (SampleTimeState) on
-- LedgerCharDB.levelTicks, and they simply become the entry's `ticks`
-- as they are -- no aggregation, no recalculation. The next level then
-- starts with a fresh set.
--
-- xpRequired is the closed level's own xp requirement (the crossing's
-- oldMax), recorded on the entry so /ldg check can verify the level's
-- xp against it.
local function CloseCurrentLevel(t, xpRequired)
    if not sessions or #sessions == 0 then return end

    local entry = Ledger.CloseLevel(sessions, LedgerDB.includeRested, xpRequired, LedgerCharDB.levelTicks)
    Ledger.RecordLevelClose(LedgerCharDB, entry)
    Ledger.Log("trace", string.format(
        "LevelClose: closed level %d, %d session(s) aggregated, totalXP=%d, samples=%d, deaths=%d",
        entry.level, #sessions, entry.totalXP, entry.ticks.total, entry.deaths))

    LedgerCharDB.levelTicks = Ledger.NewTicks()
    LedgerCharDB.sessions = {}
    sessions = LedgerCharDB.sessions
    local newSession = OpenSession(t, UnitLevel("player"), false)
    newSession.reached = time()

    matcher    = Ledger.NewMatcher()
    reconciler = Ledger.NewReconciler()

    Ledger.RedrawXPBarFull()
    Ledger.RedrawTimeBar()
end

-- An xp event that crosses a ding arrives here already paired with its
-- real src (paired.crossing was set by Ledger.ComputeXPDelta and has
-- traveled attached through the matcher -- core/xp_gain_matcher.lua --
-- so the real source, whenever it arrives, gets applied to the WHOLE
-- event before it's split: if it were split before pairing, only one
-- of the two halves could match the source and the other would be
-- released as "unknown"). It's split into two entries that add up to
-- exactly paired.xp: the one that completes the old level
-- (crossing.oldPart) is recorded into the not-yet-rotated session and
-- that level is then closed; the one that opens the new one
-- (crossing.newPart) is recorded into the freshly-rotated session.
-- Both inherit the same src; rested is split proportionally between the
-- two without losing or gaining anything to rounding -- the new part
-- takes whatever is left over.
local function EmitCrossingEvent(paired)
    local split = Ledger.SplitCrossingEvent(paired) -- pure logic: core/xp_delta.lua

    local oldSession = CurrentSession()
    if oldSession then
        local offset = math.floor((paired.t - sessionStartRef) * 10 + 0.5)
        Ledger.AddEvent(oldSession, offset, split.old.xp, paired.src, split.old.rested)
    end

    CloseCurrentLevel(paired.t, paired.crossing.oldMax)

    -- offset 0: sessionStartRef was just rebound to paired.t in
    -- OpenSession (inside CloseCurrentLevel).
    local newSession = CurrentSession()
    if newSession then
        Ledger.AddEvent(newSession, 0, split.new.xp, paired.src, split.new.rested)
        Ledger.ExtendXPBar()
    end
end

-- Records the event and, if the source carried its own amount
-- (expectedXP: e.g. QUEST_TURNED_IN's arg2), cross-checks it against
-- the real UnitXP delta -- which is always what gets recorded, the
-- discrepancy is only a warning signal. Also feeds the reconciliation
-- counter with what has actually ended up recorded (see
-- PLAYER_XP_UPDATE for the expected side) -- once, with the FULL xp,
-- whether it crosses a level or not: splitting it into two entries
-- (EmitCrossingEvent) is only a detail of where it gets recorded, it
-- doesn't change how much gets recorded.
local function EmitEvent(paired)
    if paired.expectedXP and paired.expectedXP ~= paired.xp then
        Ledger.Log("error", string.format(
            "xp discrepancy: source %s reported %d, real UnitXP delta was %d -- recording the delta (UnitXP wins)",
            paired.src, paired.expectedXP, paired.xp))
    end

    Ledger.AccountRecordedXP(reconciler, paired.xp)

    if paired.crossing then
        EmitCrossingEvent(paired)
        return
    end

    local session = CurrentSession()
    if not session then return end
    local offset = math.floor((paired.t - sessionStartRef) * 10 + 0.5) -- tenths of a second, rounded
    Ledger.AddEvent(session, offset, paired.xp, paired.src, paired.rested)
    Ledger.ExtendXPBar()
end

-- Binds `sessions` to LedgerCharDB.sessions (guaranteed by
-- Ledger.InitCharDB on ADDON_LOADED, which runs before this event can
-- fire). If there were already unclosed sessions from a previous play
-- session of the same level, it keeps writing into them (rebinding
-- sessionStartRef to the last recorded offset, so the next event
-- continues the count instead of resetting it); if there were none, it
-- opens the first one and stores `initialXP` on it (the xp the player
-- already had on this level before the addon started tracking, UnitXP
-- at this instant) and `reached` (approximate: the instant tracking
-- started, not the real ding -- that already happened before installing
-- the addon, just as inexact as initialXP).
local function StartTracking(t, level)
    sessions = LedgerCharDB.sessions
    if #sessions == 0 then
        local session = OpenSession(t, level, false)
        session.initialXP = UnitXP("player")
        session.reached   = time()
    else
        local lastOffset = Ledger.LastOffset(CurrentSession()) or 0
        sessionStartRef = t - (lastOffset / 10)
    end
    matcher     = Ledger.NewMatcher()
    reconciler  = Ledger.NewReconciler()
end

-- Completely wipes LedgerCharDB (all of this character's saved
-- sessions, levels and activity counters) and starts tracking from
-- scratch, without needing a /reload: a fresh LedgerCharDB replaces the
-- old one, `sessions` is rebound to its new table (StartTracking) and the
-- current level's first session opens with initialXP = current xp (same
-- as a brand-new character). Also resets matcher/reconciler (via
-- StartTracking) and the previousXP/previousMaxXP/previousLevel
-- reference so the first PLAYER_XP_UPDATE after the wipe doesn't
-- compute a fake delta. Irreversible action: meant for /ldg wipe
-- confirm.
function Ledger.WipeCharacterData(t)
    LedgerCharDB = Ledger.InitCharDB(nil)
    sessions = nil
    StartTracking(t, UnitLevel("player"))
    previousXP    = UnitXP("player")
    previousMaxXP = UnitXPMax("player")
    previousLevel = UnitLevel("player")
    SafeRequestTimePlayed()
    Ledger.RedrawXPBarFull()
end

-- Closes the active session (tEnd) and opens a new one marked as
-- manual. Closes, never deletes: the closed session stays in `sessions`
-- until the level closes. The new session starts its own set of
-- activity counters (session.ticks), while the level's counters
-- (LedgerCharDB.levelTicks) just keep counting across the reset. tEnd
-- is stored as absolute time(), same as t0 (see OpenSession).
function Ledger.ResetSession(t)
    local current = CurrentSession()
    if not current then return end
    current.tEnd = time()
    OpenSession(t, current.level, true)
end

----------------------------------------------------------------------
-- Periodic buffer flush: combat, exploration and quests all have a
-- source of their own today (CHAT_MSG_COMBAT_XP_GAIN classified, or
-- QUEST_TURNED_IN), so an amount should only end up here with
-- src="unknown" if the corresponding message/event is lost entirely
-- (e.g. event saturation). This periodic flush is still needed so we
-- don't wait for that source forever.
----------------------------------------------------------------------

local function FlushMatcher()
    if not matcher then return end
    for _, paired in ipairs(Ledger.Flush(matcher, GetTime(), Ledger.Log)) do
        EmitEvent(paired)
    end
end

C_Timer.NewTicker(1, FlushMatcher)

----------------------------------------------------------------------
-- 1s activity sampler. The ticker is a SAMPLER, not a clock: each second
-- it reads the player's instantaneous state, Ledger.ClassifyActivity
-- (core/ticks.lua) turns it into exactly one activity, and that
-- activity's counter goes up by one -- live, on the active session's
-- counters AND on the level in progress's (LedgerCharDB.levelTicks), so
-- a crash loses at most the ticks since the last save, never a level.
-- Nothing is stored per tick and nothing is derived later. The counters
-- are counts of samples, not guaranteed seconds: with the client not
-- running the ticker doesn't run either, which is correct by design.
----------------------------------------------------------------------

-- Some clients (confirmed 2026-09-18 on the WoW Forever beta) taint
-- GetUnitSpeed's return as a "secret value": the call itself succeeds,
-- but comparing it (`> 0`) throws "attempt to compare a secret number
-- value (execution tainted by 'Ledger')" -- unlike an absent API, this
-- isn't caught by wrapping just the call in pcall, the comparison
-- itself needs its own pcall. Degrades to "not moving" and warns once
-- per session at ERROR (not the xp bar's INFO-level degraded anchor:
-- this isn't a supported fallback, it means movement -- hence "travel"
-- -- can't be detected at all in this client -- see CLAUDE.md Pendiente).
local warnedSecretSpeed = false
local function IsPlayerMoving()
    local ok, speed = pcall(GetUnitSpeed, "player")
    if not ok then return false end

    local cmpOk, moving = pcall(function() return (speed or 0) > 0 end)
    if not cmpOk then
        if not warnedSecretSpeed then
            Ledger.Log("error",
                "GetUnitSpeed(\"player\") returned a secret value this client won't let us compare (" ..
                tostring(moving) .. ") -- movement-based 'travel' detection is disabled for this session.")
            warnedSecretSpeed = true
        end
        return false
    end
    return moving
end

local function SampleTimeState()
    local session = CurrentSession()
    if not session then return end

    Ledger.RecordActivityTick(session, LedgerCharDB.levelTicks, {
        dead   = UnitIsDeadOrGhost("player"),
        combat = UnitAffectingCombat("player"),
        moving = IsPlayerMoving(),
        taxi   = UnitOnTaxi("player"),
    })
    Ledger.RedrawTimeBar()
end

C_Timer.NewTicker(1, SampleTimeState)

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("CHAT_MSG_SYSTEM")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("TIME_PLAYED_MSG")
ev:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    local t = GetTime()

    if event == "PLAYER_ENTERING_WORLD" then
        -- Login and every loading screen. If there's no session yet we
        -- start it here; if there already was one, we just resync the
        -- reference xp (and its max/level) so the first comparison
        -- after loading doesn't compute a fake delta.
        if not sessions then
            StartTracking(t, UnitLevel("player"))
        end
        previousXP     = UnitXP("player")
        previousMaxXP  = UnitXPMax("player")
        previousLevel  = UnitLevel("player")
        SafeRequestTimePlayed()

    elseif event == "PLAYER_XP_UPDATE" then
        local currentXP    = UnitXP("player")
        local currentMax   = UnitXPMax("player")
        local currentLevel = UnitLevel("player")

        local result = Ledger.ComputeXPDelta(previousXP, currentXP, previousMaxXP, previousLevel, currentLevel)

        Ledger.Log("trace", string.format(
            "PLAYER_XP_UPDATE t=%.3f previousXP=%s currentXP=%d previousMaxCached=%s previousLevel=%s currentLevel=%d delta=%s",
            t, tostring(previousXP), currentXP, tostring(previousMaxXP), tostring(previousLevel), currentLevel,
            result.ok and tostring(result.delta) or "?"))

        if result.ok then
            if result.levelsGained == 1 then
                Ledger.Log("info", string.format(
                    "PLAYER_XP_UPDATE t=%.3f level up: reconstructed xp = %d (old level's cached max = %d)",
                    t, result.delta, previousMaxXP))
            end

            -- delta = 0 is valid (e.g. a PLAYER_XP_UPDATE with no real
            -- change): ignored without logging it as an error.
            if result.delta ~= 0 then
                Ledger.AccountExpectedXP(reconciler, result.delta)
                local paired = Ledger.AddAmount(matcher, t, result.delta, Ledger.Log, result.crossing)
                if paired then EmitEvent(paired) end
            end
        else
            Ledger.Log("error", string.format("PLAYER_XP_UPDATE t=%.3f %s", t, result.reason))
        end

        previousXP, previousMaxXP, previousLevel = currentXP, currentMax, currentLevel

    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        Ledger.Log("trace", string.format("CHAT_MSG_COMBAT_XP_GAIN t=%.3f msg=<<%s>>", t, tostring(arg1)))
        local category, rested, capturedAmount = HandleCombatXPGainMessage(arg1, t)

        -- A generic "You gain N experience." is identical to a quest
        -- turn-in's own message (core/chat_patterns.lua can't tell them
        -- apart from the text alone) -- if QUEST_TURNED_IN's source is
        -- already pending (or about to be, see Ledger.QUEST_MATCH_GAP),
        -- that's what should pair with this xp, not a competing
        -- "explore" source queued here. See core/xp_gain_matcher.lua:
        -- Ledger.HasPendingQuestSource.
        if category == "explore" and Ledger.HasPendingQuestSource(matcher, t, capturedAmount, Ledger.Log) then
            Ledger.Log("trace", string.format(
                "CHAT_MSG_COMBAT_XP_GAIN t=%.3f suppressed as explore -- a quest source explains this xp instead", t))
        else
            local paired = Ledger.AddSource(matcher, t, category, Ledger.Log, rested)
            if paired then EmitEvent(paired) end
        end

    elseif event == "CHAT_MSG_SYSTEM" then
        -- Area discovery: queued as an "explore" source carrying the
        -- amount the message reports (expectedXP), so it pairs with the
        -- UnitXP delta by exact value like a quest does and EmitEvent
        -- cross-checks the two. Everything else that comes through here
        -- is only TRACE-logged, to confirm the event carries what we
        -- assume.
        local exploreXP = Ledger.ExtractExploreXP(exploreStrings, arg1)
        if exploreXP then
            Ledger.Log("trace", string.format(
                "CHAT_MSG_SYSTEM t=%.3f area discovery xp=%d msg=<<%s>>", t, exploreXP, tostring(arg1)))
            local paired = Ledger.AddSource(matcher, t, "explore", Ledger.Log, 0, exploreXP)
            if paired then EmitEvent(paired) end
        else
            Ledger.Log("trace", string.format("CHAT_MSG_SYSTEM t=%.3f ignored msg=<<%s>>", t, tostring(arg1)))
        end

    elseif event == "QUEST_TURNED_IN" then
        -- arg1 = questID, arg2 = xp awarded, arg3 = money awarded.
        -- Queued as a source just like a combat message (never just
        -- logged): the quest-turn-in message is identical to the
        -- exploration one ("You gain N experience."), so without
        -- queuing QUEST_TURNED_IN as its own source there's no way to
        -- tell one from the other (see SOURCE_PRIORITY in
        -- core/xp_gain_matcher.lua). arg2 is passed as expectedXP so
        -- EmitEvent can do the cross-check against the real delta; the
        -- amount recorded is always still the delta's.
        local questID, questXP, questMoney = arg1, arg2, arg3
        Ledger.Log("trace", string.format(
            "QUEST_TURNED_IN t=%.3f questID=%s xp=%s money=%s",
            t, tostring(questID), tostring(questXP), tostring(questMoney)))
        local paired = Ledger.AddSource(matcher, t, "quest", Ledger.Log, 0, questXP)
        if paired then EmitEvent(paired) end

    elseif event == "PLAYER_LEVEL_UP" then
        -- Diagnostics and panel refresh only: the real level close is
        -- triggered by the xp event that crosses the ding itself, as
        -- soon as it pairs with its source (Ledger.ComputeXPDelta
        -- detects the crossing by looking at UnitLevel() on every
        -- PLAYER_XP_UPDATE, without depending on this event arriving in
        -- any particular order -- see EmitCrossingEvent). arg1 is the
        -- new level reported by the event itself; UnitLevel("player") is
        -- what the API says RIGHT NOW -- if they don't match, UnitLevel
        -- hasn't updated yet at this instant.
        Ledger.Log("trace", string.format(
            "PLAYER_LEVEL_UP t=%.3f newLevel(arg1)=%s UnitLevel=%s cached previousLevel=%s",
            t, tostring(arg1), tostring(UnitLevel("player")), tostring(previousLevel)))
        Ledger.UpdateXP()

    elseif event == "PLAYER_DEAD" then
        -- Level death counter, separate from the "dead" activity counter
        -- (sampled independently every second via UnitIsDeadOrGhost,
        -- see SampleTimeState): how many samples you were dead doesn't
        -- say how many times. See core/level_close.lua, entry.deaths.
        local session = CurrentSession()
        if session then
            session.deaths = (session.deaths or 0) + 1
        end

    elseif event == "TIME_PLAYED_MSG" then
        -- arg1 = the CHARACTER's total played time, arg2 = time played
        -- on the current level. INFORMATIONAL ONLY: arg2 is kept in its
        -- own field (LedgerCharDB.played, together with how many
        -- samples the level had at that moment) and takes part in no
        -- calculation and no metric -- the only reader is /ldg check.
        Ledger.RecordPlayedReading(LedgerCharDB, UnitLevel("player"), arg2)
        if Ledger.checkFrame and Ledger.checkFrame:IsShown() then
            Ledger.RenderCheckFrame()
        end
    end
end)
