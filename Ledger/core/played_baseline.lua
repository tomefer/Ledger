-- Ledger - core/played_baseline.lua
-- The played-time math behind a level's totalPlayed. Pure logic: does
-- not use any WoW API. The clock (GetTime()) and the TIME_PLAYED_MSG
-- value are received as parameters (see ui/xp_capture.lua, the only
-- caller that feeds them in), same as everywhere else in core/.
--
-- A level's totalPlayed is the CHARACTER's total played time (the
-- server's own counter, TIME_PLAYED_MSG arg1) when the level closes
-- minus that same total when the level started being tracked (the
-- "baseline", charDB.levelStartTotalPlayed).
--
-- ## The total is only READ occasionally, so it is ESTIMATED in between
--
-- TIME_PLAYED_MSG only answers when asked (RequestTimePlayed, at
-- PLAYER_ENTERING_WORLD and at every level close), so the cached
-- charDB.lastKnownTotalTimePlayed freezes between requests and, read
-- raw, UNDERESTIMATES the total by however long ago it was received
-- (a level closed 20 minutes after the last reply lost those 20
-- minutes). So the raw field is never used in a calculation: what is
-- used is Ledger.EstimatePlayedTotal,
--
--     cached + (now - receivedAt)
--
-- where receivedAt is the GetTime() at which the cached value arrived.
-- Played time advances 1s per second while the character is logged in
-- and so does GetTime(), so the two stay in step.
--
-- ## Why receivedAt is NEVER persisted (the offline-time question)
--
-- receivedAt lives in an in-memory `clock` table, not in
-- LedgerCharDB. GetTime() is documented as the system uptime, so its
-- origin is not the saved data's: a receivedAt saved in one client run
-- and compared against the GetTime() of the next one would be a
-- difference of two unrelated clocks -- arbitrary, possibly negative,
-- and (if GetTime() keeps running with the client closed, as system
-- uptime would) inflated by the whole time spent offline, which played
-- time does NOT count. Keeping it in memory makes that impossible by
-- construction instead of relying on GetTime()'s exact semantics
-- (which can't be verified outside the real client: see /ldg probe,
-- which prints GetTime() so it can be compared across a restart): after
-- a /reload or a restart the new Lua state has no receivedAt, so the
-- estimate is nil ("unknown") until the reply to the RequestTimePlayed
-- that PLAYER_ENTERING_WORLD sends right away -- a matter of
-- milliseconds. The one span the estimate does cover is a continuous
-- logged-in stretch, where GetTime() and played time move together.
-- (A loading screen is part of that stretch, and PLAYER_ENTERING_WORLD
-- re-requests the total after each one anyway.)
--
-- ## nil means UNKNOWN, never zero
--
-- The total isn't available the instant tracking starts (the request is
-- asynchronous). A baseline defaulted to 0 in the meantime turned the
-- first level closed after a wipe or a fresh install into "the
-- character's whole played time" (a level of 00:16:16 between dings
-- recorded 01:37:15). So whenever the total or the baseline isn't
-- known, the estimate/level time is nil, a level that closes like that
-- records NO totalPlayed (nil) and is flagged entry.timeUnreliable, and
-- nothing ever substitutes a made-up number.
--
-- ## The clock table
--
-- clock = Ledger.NewPlayedClock(), in memory only:
--   receivedAt -- GetTime() when charDB.lastKnownTotalTimePlayed was
--                 received, nil if it wasn't received in this Lua state.
--   awaiting   -- true when the baseline is nil AND the next
--                 TIME_PLAYED_MSG is the right value to seed it with.
--                 Only ever true right after tracking (re)starts and
--                 RequestTimePlayed was asked for; a nil baseline with
--                 awaiting = false (data migrated from before this
--                 rule, or a reply that never came before a reload)
--                 stays unknown for good rather than being seeded later
--                 than the level really started.

local ADDON_NAME, Ledger = ...

print("Ledger: core/played_baseline.lua")

function Ledger.NewPlayedClock()
    return { receivedAt = nil, awaiting = false }
end

-- Tracking starts for a level whose baseline can't be known yet (a
-- fresh install, /ldg wipe): forgets any baseline and starts awaiting
-- the reply. The caller must follow up with RequestTimePlayed().
function Ledger.StartPlayedBaseline(charDB, clock)
    charDB.levelStartTotalPlayed = nil
    clock.awaiting = true
end

-- A TIME_PLAYED_MSG arrived with the character's total played time
-- `total`, at GetTime() = now. Always refreshes the cached total and
-- the moment it was received; if the baseline was awaiting it, seeds it
-- with that same total too. Returns true when it seeded the baseline.
function Ledger.ApplyTimePlayed(charDB, clock, total, now)
    charDB.lastKnownTotalTimePlayed = total
    clock.receivedAt = now
    if clock.awaiting and charDB.levelStartTotalPlayed == nil then
        charDB.levelStartTotalPlayed = total
        clock.awaiting = false
        return true
    end
    return false
end

-- The character's total played time AS OF `now` (a GetTime() value):
-- the cached total plus the time elapsed since it was received. nil if
-- that can't be known -- no total cached, or none received in this Lua
-- state (a value left over from a previous run has no trustworthy
-- receivedAt: see the header) -- or if `now` itself is missing. `now`
-- may be slightly BEFORE receivedAt (e.g. the moment of a ding whose
-- reply landed a beat later): the played counter is monotonic, so
-- subtracting the gap is exactly right.
function Ledger.EstimatePlayedTotal(charDB, clock, now)
    local cached = charDB.lastKnownTotalTimePlayed
    if cached == nil or clock.receivedAt == nil or now == nil then
        return nil
    end
    return cached + (now - clock.receivedAt)
end

-- Seconds played on the level in progress as of `now`, or nil if that
-- isn't known (no baseline yet, or no estimate of the total). Never
-- negative. This is the ONE place that subtracts the baseline, so a
-- missing piece can never turn into a fabricated number: both level
-- close (totalPlayed) and the live level xp/hour go through it.
function Ledger.LevelPlayedTime(charDB, clock, now)
    local total = Ledger.EstimatePlayedTotal(charDB, clock, now)
    local start = charDB.levelStartTotalPlayed
    if total == nil or start == nil then
        return nil
    end
    return math.max(total - start, 0)
end

-- A level just closed (at GetTime() = now, the ding): the next one
-- starts at the estimated total at that instant. If that isn't known,
-- or the baseline was still awaiting its first reading (so the cached
-- total isn't "now"), the new baseline is unknown too and the clock
-- goes back to awaiting -- the caller asks RequestTimePlayed() and the
-- reply seeds it.
function Ledger.AdvancePlayedBaseline(charDB, clock, now)
    local total = Ledger.EstimatePlayedTotal(charDB, clock, now)
    if clock.awaiting or total == nil then
        charDB.levelStartTotalPlayed = nil
        clock.awaiting = true
        return
    end
    charDB.levelStartTotalPlayed = total
    clock.awaiting = false
end

-- /ldg wipe: empties the character's saved data (levels, sessions) and
-- forgets the played-time readings -- they belonged to the data being
-- thrown away, and the baseline can't be re-seeded until the server
-- answers. Leaves the clock awaiting (the caller opens the first
-- session and calls RequestTimePlayed()). Only touches the fields it
-- owns: everything else in charDB (version...) is left alone.
function Ledger.WipeCharDB(charDB, clock)
    charDB.levels   = {}
    charDB.sessions = {}
    charDB.lastKnownTotalTimePlayed = nil
    clock.receivedAt = nil
    Ledger.StartPlayedBaseline(charDB, clock)
end
