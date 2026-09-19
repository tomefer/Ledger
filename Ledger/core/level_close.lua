-- Ledger - core/level_close.lua
-- Closes a level: aggregates the sessions that belong to it into the
-- data model's `levels` entry (xp totals, breakdown by source and
-- per-minute xp curve) and attaches the level's activity counters.
-- Pure logic: does not use any WoW API.
--
-- The sessions must already come pre-trimmed by the caller to the
-- level they belong to: if a real session spans two levels, its events
-- array is passed in as two separate pieces, one per level close. This
-- function does not detect or cut those boundaries, it only aggregates
-- what it's given.
--
-- Time is not computed here at all: the level's activity counters
-- (core/ticks.lua) are incremented live by the sampler on
-- LedgerCharDB.levelTicks, and this function just attaches that table
-- as entry.ticks, as it is -- no aggregation and no recalculation, there
-- is no series left to recalculate from. The caller starts a fresh
-- levelTicks for the next level.

local ADDON_NAME, Ledger = ...

print("Ledger: core/level_close.lua")

local XP_SERIES    = Ledger.SERIES.xp
local OFF_FIELD    = Ledger.SeriesFieldIndex(XP_SERIES, "off")
local XP_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local RESTED_FIELD = Ledger.SeriesFieldIndex(XP_SERIES, "rested")

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
-- levelTicks (optional; a fresh empty set when omitted) is the level's
-- activity counters, attached by reference as entry.ticks.
--
-- xpRequired (optional) is the xp the level required to complete
-- (UnitXPMax of that level, known at the ding: see
-- Ledger.ComputeXPDelta's crossing.oldMax); when omitted the entry
-- carries no xpRequired and /ldg check can't verify that level's xp.
-- entry.initialXP is the xp the player already had on this level before
-- tracking started (sessions[1].initialXP, 0 if none): the level's
-- recorded xp + initialXP is what should add up to xpRequired.
function Ledger.CloseLevel(sessions, includeRested, xpRequired, levelTicks)
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

    return {
        level       = sessions[1].level,
        reached     = sessions[1].reached or 0,
        initialXP   = sessions[1].initialXP or 0,
        xpRequired  = xpRequired,
        totalXP     = totalXP,
        totalRested = totalRested,
        deaths      = deaths,
        bySource    = bySource,
        curve       = curve,
        ticks       = levelTicks or Ledger.NewTicks(),
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
