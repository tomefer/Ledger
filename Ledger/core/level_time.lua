-- Ledger - core/level_time.lua
-- Invariants a closed level's totalPlayed must satisfy, checked against
-- two independent measurements of the same level. Pure logic: does not
-- use any WoW API. ONE definition, shared by the level close
-- (ui/xp_capture.lua logs violations to ERROR the moment a level closes)
-- and by /ldg check (core/check.lua reports them afterward), so the two
-- can never disagree about what counts as wrong.
--
-- totalPlayed comes from the server's played-time counter (see
-- core/played_baseline.lua). Two other things measured on their own can
-- bound it, and neither depends on that counter:
--
--   * the wall-clock time between this level's ding and the next one
--     (difference of the levels' `reached`): played time can't run ahead
--     of the clock, so it is an UPPER bound;
--   * the sum of the level's time buckets (entry.buckets): the sampler
--     ticks once per second and only while the client is running, so
--     every sample is a second really played and its sum is a LOWER
--     bound (a tick can be skipped, e.g. during a loading screen, but
--     one is never invented).
--
-- Real data: buckets landed 4-25s under the wall-clock time between
-- dings, over 4 levels, so a totalPlayed outside [buckets, elapsed] by
-- more than the tolerance is wrong, not noise.

local ADDON_NAME, Ledger = ...

print("Ledger: core/level_time.lua")

-- Slack, in seconds, allowed on every comparison below: `reached` is
-- stamped with time() and totalPlayed comes from the server's counter
-- through an extrapolation (Ledger.EstimatePlayedTotal), so the sources
-- are never exactly aligned.
Ledger.TIME_TOLERANCE = 60

-- Sum of every bucket (active + downtime + travel + dead), in seconds.
-- nil (a level with no buckets) counts as 0.
function Ledger.SumBuckets(buckets)
    local total = 0
    for _, seconds in pairs(buckets or {}) do
        total = total + seconds
    end
    return total
end

-- entry: a `levels` entry (core/level_close.lua): totalPlayed, buckets,
-- curve. elapsed: seconds between this level's ding and the next one
-- (the caller knows how to get it: see ui/xp_capture.lua and
-- core/check.lua), or nil if unknown -- then only the checks that don't
-- need it run.
--
-- Returns a list of { id=, text= } violations, empty when everything
-- holds. An entry with no totalPlayed (nil: unknown, flagged
-- timeUnreliable) has nothing to check and never violates anything.
function Ledger.LevelTimeViolations(entry, elapsed)
    local played = entry.totalPlayed
    if played == nil then return {} end

    local violations = {}
    local function add(id, text)
        violations[#violations + 1] = { id = id, text = text }
    end

    -- 1) Never more than the time between the two dings.
    if elapsed and elapsed >= 0 and played > elapsed + Ledger.TIME_TOLERANCE then
        add("exceeds-elapsed", string.format(
            "played %s > %s between dings -- impossible, the played-time baseline is misaligned",
            Ledger.FormatHHMMSS(played), Ledger.FormatHHMMSS(elapsed)))
    end

    -- 2) Never less than the seconds the sampler measured in game.
    local sampled = Ledger.SumBuckets(entry.buckets)
    if played + Ledger.TIME_TOLERANCE < sampled then
        add("below-samples", string.format(
            "played %s < %s sampled in game -- impossible, the sampler only ticks while logged in, so its sum is a lower bound",
            Ledger.FormatHHMMSS(played), Ledger.FormatHHMMSS(sampled)))
    end

    -- 3) The xp curve has one entry per minute, counted from each
    -- session's start (in-game time), so the last minute touched can't
    -- go past the level's played time: minute = floor(offset/60) + 1.
    local minutes = #(entry.curve or {})
    local maxMinutes = math.floor((played + Ledger.TIME_TOLERANCE) / 60) + 1
    if minutes > maxMinutes then
        add("curve-too-long", string.format(
            "the xp curve spans %d minutes but played is only %s -- the played time can't have been that short",
            minutes, Ledger.FormatHHMMSS(played)))
    end

    return violations
end
