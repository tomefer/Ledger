-- Ledger - core/played_baseline.lua
-- The played-time baseline behind a level's totalPlayed. Pure logic:
-- does not use any WoW API, the TIME_PLAYED_MSG value is received as a
-- parameter (see ui/xp_capture.lua, which is the only caller).
--
-- A level's totalPlayed is the CHARACTER's total played time (the
-- server's own counter, TIME_PLAYED_MSG arg1) at the moment the level
-- closes minus that same total at the moment the level started being
-- tracked (the "baseline", charDB.levelStartTotalPlayed).
--
-- **nil means UNKNOWN, never zero.** The total isn't available the
-- instant tracking starts: RequestTimePlayed() is asynchronous and
-- answers through TIME_PLAYED_MSG a moment later. A baseline defaulted
-- to 0 in the meantime turned the first level closed after a wipe or a
-- fresh install into "the character's whole played time" (a level of
-- 00:16:16 between dings recorded 01:37:15). So while it isn't known the
-- baseline stays nil, and a level that closes without one records NO
-- totalPlayed (nil) and is flagged entry.timeUnreliable rather than
-- carrying an invented number. lastKnownTotalTimePlayed follows the same
-- rule: nil until the first TIME_PLAYED_MSG.
--
-- `awaiting` (a boolean the caller keeps in memory, deliberately never
-- persisted) says "the baseline is nil AND the next TIME_PLAYED_MSG is
-- the right value to seed it with". It's only ever true right after
-- tracking (re)starts and RequestTimePlayed was asked for; a nil
-- baseline with awaiting = false (data migrated from before this rule,
-- or the reply never arrived before a reload) stays unknown for good
-- rather than being seeded later than the level really started.

local ADDON_NAME, Ledger = ...

print("Ledger: core/played_baseline.lua")

-- Tracking starts for a level whose baseline can't be known yet (a
-- fresh install, /ldg wipe): forgets any baseline and returns
-- awaiting = true. The caller must follow up with RequestTimePlayed().
function Ledger.StartPlayedBaseline(charDB)
    charDB.levelStartTotalPlayed = nil
    return true
end

-- A TIME_PLAYED_MSG arrived with the character's total played time
-- `total`. Always refreshes lastKnownTotalTimePlayed; if the baseline
-- was awaiting it, seeds it with that same total too. Returns the new
-- awaiting flag (false once seeded).
function Ledger.ApplyTimePlayed(charDB, total, awaiting)
    charDB.lastKnownTotalTimePlayed = total
    if awaiting and charDB.levelStartTotalPlayed == nil then
        charDB.levelStartTotalPlayed = total
        return false
    end
    return awaiting
end

-- Seconds played on the level in progress so far, or nil if that isn't
-- known (no baseline yet, or no reading of the total yet). Never
-- negative. This is the ONE place that subtracts the two totals, so a
-- missing one can never turn into a fabricated number: both level close
-- (totalPlayed) and the live level xp/hour go through it.
function Ledger.LevelPlayedTime(charDB)
    local total, start = charDB.lastKnownTotalTimePlayed, charDB.levelStartTotalPlayed
    if total == nil or start == nil then
        return nil
    end
    return math.max(total - start, 0)
end

-- A level just closed: the next one starts NOW, at the last known
-- total. If that isn't known (never read, or the baseline was still
-- awaiting its first reading so lastKnown is stale, not "now"), the new
-- baseline is unknown too and awaiting is returned true -- the caller
-- asks RequestTimePlayed() and the reply seeds it. Returns awaiting.
function Ledger.AdvancePlayedBaseline(charDB, awaiting)
    if awaiting or charDB.lastKnownTotalTimePlayed == nil then
        charDB.levelStartTotalPlayed = nil
        return true
    end
    charDB.levelStartTotalPlayed = charDB.lastKnownTotalTimePlayed
    return false
end

-- /ldg wipe: empties the character's saved data (levels, sessions) and
-- forgets the played-time readings -- they belonged to the data being
-- thrown away, and the baseline can't be re-seeded until the server
-- answers. Returns awaiting = true (the caller opens the first session
-- and calls RequestTimePlayed()). Only touches the fields it owns:
-- everything else in charDB (version...) is left alone.
function Ledger.WipeCharDB(charDB)
    charDB.levels   = {}
    charDB.sessions = {}
    charDB.lastKnownTotalTimePlayed = nil
    return Ledger.StartPlayedBaseline(charDB)
end
