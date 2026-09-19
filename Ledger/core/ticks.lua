-- Ledger - core/ticks.lua
-- Activity sampling. The 1-second ticker (ui/xp_capture.lua) is a
-- SAMPLER, not a clock: every tick evaluates what the player is doing
-- right now, gets ONE key back, and adds one to that activity's counter.
-- Nothing else. There is no time series, no per-second array, no
-- threshold and no wall-clock arithmetic anywhere.
--
-- The counters are counts of samples, not guaranteed seconds: a tick
-- only runs while the client does (in the background, or closed, it
-- doesn't run), and that is correct by design -- the counters measure
-- the time the addon actually observed. That is also why time is only
-- ever DISPLAYED as a percentage of the total samples of a level or a
-- session, never as an absolute value: an absolute number invites
-- reconciling it with something external (played time, the wall clock)
-- that it was never meant to match. A percentage is derived at display
-- time (Ledger.TickPercent) and never persisted.
--
-- Pure logic: does not use any WoW API. The player's state is received
-- as a parameter.

local ADDON_NAME, Ledger = ...

print("Ledger: core/ticks.lua")

-- Fixed order, used everywhere activities are listed or drawn (the time
-- bar's segments, tooltips, exports), so the shape is always
-- recognizable and never reordered by size.
Ledger.TICK_KEYS = { "combat", "nonCombat", "travel", "dead" }

local KNOWN_KEY = {}
for _, key in ipairs(Ledger.TICK_KEYS) do
    KNOWN_KEY[key] = true
end

-- One set of counters. The same shape for a session (session.ticks) and
-- for the level in progress (LedgerCharDB.levelTicks); when a level
-- closes its counters stay as they are in its `levels` entry
-- (entry.ticks). `total` is the sum of the four, kept up to date by
-- CountTick as it goes, never recomputed.
function Ledger.NewTicks()
    return { combat = 0, nonCombat = 0, travel = 0, dead = 0, total = 0 }
end

-- The single activity of one sample. state = { dead=, combat=, moving=,
-- taxi= } (any missing/false entry counts as unset); the activities are
-- mutually exclusive, so this returns exactly one key, by priority:
--   dead   -> "dead"       (a corpse is not "in combat", even mid-fight)
--   combat -> "combat"
--   moving -> "travel"     (moving on foot or riding a taxi)
--   else   -> "nonCombat"
function Ledger.ClassifyActivity(state)
    if state.dead then
        return "dead"
    elseif state.combat then
        return "combat"
    elseif state.moving or state.taxi then
        return "travel"
    end
    return "nonCombat"
end

-- One tick: exactly one activity counter and the total go up by one.
function Ledger.CountTick(ticks, key)
    if not KNOWN_KEY[key] then
        error("Ledger.CountTick: unknown activity " .. tostring(key), 2)
    end
    ticks[key]   = ticks[key] + 1
    ticks.total  = ticks.total + 1
end

-- The whole per-second step: classifies `state` once and counts that
-- same key live on BOTH the active session's counters and the level in
-- progress's, so a crash loses at most the ticks since the last save,
-- never a level. Returns the key.
function Ledger.RecordActivityTick(session, levelTicks, state)
    local key = Ledger.ClassifyActivity(state)
    Ledger.CountTick(session.ticks, key)
    Ledger.CountTick(levelTicks, key)
    return key
end

-- Share of one activity in the total samples, 0-100. 0 when there are no
-- samples yet (never a division by zero). Derived on display, never
-- stored.
function Ledger.TickPercent(ticks, key)
    if not ticks or (ticks.total or 0) <= 0 then
        return 0
    end
    return ticks[key] / ticks.total * 100
end

local LABELS = {
    combat    = "Combat",
    nonCombat = "Non-combat",
    travel    = "Travel",
    dead      = "Dead",
}
Ledger.TICK_LABELS = LABELS

-- One line per activity, in Ledger.TICK_KEYS order: { key=, text= }
-- where text is "Combat: 42.3%". Percentages only. The color of each
-- line is up to whoever paints it (ui/).
function Ledger.FormatTickLines(ticks)
    local lines = {}
    for _, key in ipairs(Ledger.TICK_KEYS) do
        lines[#lines + 1] = {
            key  = key,
            text = string.format("%s: %.1f%%", LABELS[key], Ledger.TickPercent(ticks, key)),
        }
    end
    return lines
end

-- The same on a single line for text dumps: "Combat 42.3% | Non-combat
-- 40.0% | Travel 17.7% | Dead 0.0%", or "no samples yet".
function Ledger.FormatTickSummary(ticks)
    if not ticks or (ticks.total or 0) <= 0 then
        return "no samples yet"
    end
    local parts = {}
    for _, key in ipairs(Ledger.TICK_KEYS) do
        parts[#parts + 1] = string.format("%s %.1f%%", LABELS[key], Ledger.TickPercent(ticks, key))
    end
    return table.concat(parts, " | ")
end

----------------------------------------------------------------------
-- /played reading: INFORMATIONAL ONLY. TIME_PLAYED_MSG's time on the
-- current level is kept in its own field and takes part in no
-- calculation and no metric -- the only reader is /ldg check, which
-- shows it next to the sample total as information.
----------------------------------------------------------------------

-- Stores the reading (charDB.played) together with how many samples the
-- level in progress had at that moment, so the two are comparable: a
-- reading is only ever a snapshot of the instant the reply arrived.
--   level   -- UnitLevel("player") when the reply arrived
--   seconds -- TIME_PLAYED_MSG's arg2, time played on the current level
function Ledger.RecordPlayedReading(charDB, level, seconds)
    charDB.played = {
        level   = level,
        seconds = seconds,
        samples = (charDB.levelTicks and charDB.levelTicks.total) or 0,
    }
end
