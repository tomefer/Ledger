-- Ledger - core/level_close.lua
-- Closes a level: aggregates the sessions that belong to it into the
-- data model's `levels` entry (totals, breakdown by source and
-- per-minute xp curve). Pure logic: does not use any WoW API.
--
-- The sessions must already come pre-trimmed by the caller to the
-- level they belong to: if a real session spans two levels, its events
-- array is passed in as two separate pieces, one per level close. This
-- function does not detect or cut those boundaries, it only aggregates
-- what it's given.
--
-- totalPlayed is received already computed (from TIME_PLAYED_MSG, see
-- ui/xp_capture.lua); this function does not compute it.

local ADDON_NAME, Ledger = ...

print("Ledger: core/level_close.lua")

local XP_SERIES    = Ledger.SERIES.xp
local OFF_FIELD    = Ledger.SeriesFieldIndex(XP_SERIES, "off")
local XP_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local RESTED_FIELD = Ledger.SeriesFieldIndex(XP_SERIES, "rested")
local STATE_SERIES = Ledger.SERIES.state

-- offset is in tenths of a second; 1 minute = 600 tenths.
local TENTHS_PER_MINUTE = 600

-- Adds the effective xp (see Ledger.EffectiveXP, respects includeRested)
-- of each session event to the minute (relative to that session's t0)
-- it belongs to, accumulating into minuteXP. Returns the highest minute
-- touched, so the curve can be densified afterward.
local function AddToCurve(minuteXP, session, includeRested)
    local arr = session[XP_SERIES.key]
    if not arr then return 0 end

    local maxMinute = 0
    for i = 1, #arr, XP_SERIES.stride do
        local offset = arr[i + OFF_FIELD - 1]
        local xp     = arr[i + XP_FIELD - 1]
        local rested = arr[i + RESTED_FIELD - 1]
        local minute = math.floor(offset / TENTHS_PER_MINUTE) + 1
        minuteXP[minute] = (minuteXP[minute] or 0) + Ledger.EffectiveXP(xp, rested, includeRested)
        if minute > maxMinute then
            maxMinute = minute
        end
    end
    return maxMinute
end

-- includeRested (true by default) decides whether the rested bonus
-- counts toward totalXP and curve (see Ledger.EffectiveXP); it never
-- affects totalRested, which is always the real accumulated bonus, nor
-- bySource, which stays the breakdown of the total xp as-is.
--
-- Time buckets are never summed from a per-session accumulator anymore:
-- entry.stateSeries is the level's raw per-second state series (every
-- session's Ledger.SERIES.state slice, concatenated in order) and
-- entry.buckets is DERIVED from it (Ledger.ComputeBucketsFromState,
-- core/time_buckets.lua) using today's thresholds. stateSeries is kept
-- alongside the derived buckets specifically so /ldg recalc
-- (Ledger.RecalculateAllBuckets below) can redo that derivation later
-- with different thresholds, without needing the original sessions
-- (which get discarded once the level closes).
function Ledger.CloseLevel(sessions, totalPlayed, includeRested)
    local totalXP     = 0
    local totalRested = 0
    local deaths      = 0
    local bySource    = {}
    local minuteXP    = {}
    local maxMinute   = 0

    for _, session in ipairs(sessions) do
        totalXP     = totalXP + Ledger.TotalXP(session, includeRested)
        totalRested = totalRested + Ledger.TotalRested(session)
        deaths      = deaths + (session.deaths or 0)

        for src, xp in pairs(Ledger.XPBySource(session)) do
            bySource[src] = (bySource[src] or 0) + xp
        end

        local sessionMaxMinute = AddToCurve(minuteXP, session, includeRested)
        if sessionMaxMinute > maxMinute then
            maxMinute = sessionMaxMinute
        end
    end

    local curve = {}
    for minute = 1, maxMinute do
        curve[minute] = minuteXP[minute] or 0
    end

    local stateSeries = Ledger.ConcatSeries(sessions, STATE_SERIES)

    return {
        level       = sessions[1].level,
        reached     = sessions[1].reached or 0,
        totalXP     = totalXP,
        totalRested = totalRested,
        totalPlayed = totalPlayed,
        deaths      = deaths,
        bySource    = bySource,
        curve       = curve,
        stateSeries = stateSeries,
        buckets     = Ledger.ComputeBucketsFromState(stateSeries),
    }
end

-- Records the result of closing a level into `db` (shaped like
-- LedgerCharDB). Guarantees db.levels exists instead of assuming it,
-- so no caller has to index that key raw. Indexed by the actual level
-- number (entry.level), never by insertion order: if the addon is
-- installed mid-game, levels[20] is level 20, not the first item in
-- the list.
function Ledger.RecordLevelClose(db, entry)
    db.levels = db.levels or {}
    db.levels[entry.level] = entry
end

-- Recomputes entry.buckets for every already-closed level in db (shaped
-- like LedgerCharDB) from its persisted entry.stateSeries, using
-- whatever Ledger.DOWNTIME_THRESHOLD/Ledger.SUSTAINED_MOVEMENT_SECONDS
-- stand as right now (core/time_buckets.lua). This is the whole reason
-- that raw series gets kept: changing a threshold and running /ldg
-- recalc redoes the classification over history without losing
-- anything, because the raw sample -- not the derived bucket -- is what
-- was actually persisted. A level with no stateSeries (data from before
-- this capability existed, see the v5->v6 migration in core/xp.lua) is
-- left untouched: there's no raw data to recompute from. Returns how
-- many levels were recalculated.
function Ledger.RecalculateAllBuckets(db)
    local count = 0
    for _, entry in pairs((db or {}).levels or {}) do
        if entry.stateSeries and #entry.stateSeries > 0 then
            entry.buckets = Ledger.ComputeBucketsFromState(entry.stateSeries)
            count = count + 1
        end
    end
    return count
end
