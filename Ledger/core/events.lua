-- Ledger - core/events.lua
-- Accumulator of xp gains over the "xp" series (see core/series.lua) of
-- a session. Pure logic: does not use any WoW API. The offset is
-- received already computed (in tenths of a second) by the caller.

local ADDON_NAME, Ledger = ...

print("Ledger: core/events.lua")

local XP_SERIES     = Ledger.SERIES.xp
local XP_FIELD      = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local SRC_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "src")
local OFF_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "off")
local RESTED_FIELD  = Ledger.SeriesFieldIndex(XP_SERIES, "rested")

-- Creates a new session. mode ("farm"|"quest"|"dungeon"|nil) is purely
-- informational: it must never alter any event's src. manual marks
-- sessions opened by /ldg reset; they behave just like any other.
-- buckets (core/time_buckets.lua) starts at zero: whoever keeps the
-- live count (ui/xp_capture.lua) rebinds its live tracker here, so the
-- accumulated total survives /reload just like the rest of the
-- session. deaths (deaths in this session, separate from the "dead"
-- time bucket) also starts at zero.
function Ledger.NewSession(t0, level, mode, manual)
    return {
        t0      = t0,
        level   = level,
        mode    = mode,
        manual  = manual or false,
        deaths  = 0,
        buckets = Ledger.NewEmptyBuckets(),
        [XP_SERIES.key] = {},
    }
end

-- Appends an event to the end of the xp series' flat array. src is the
-- text name of the source ("kill", "quest", "explore", "unknown");
-- it's translated here to the numeric ID from Ledger.SRC_IDS
-- (core/series.lua) before storing -- this is the persistence boundary,
-- everything else (matcher, chat_patterns, palette) keeps working with
-- the name. rested is the part of xp that came from the rested bonus
-- (0 by default if omitted). It's clamped to rested = xp if it would
-- come in higher than xp, so the base xp (xp - rested) can never go
-- negative from a mismatch between the amount (UnitXP delta) and the
-- bonus (extracted from the chat message): they're two independent
-- signals with no external guarantee that they'll agree.
function Ledger.AddEvent(session, offset, xp, src, rested)
    rested = rested or 0
    if rested > xp then rested = xp end
    local srcId = Ledger.SRC_IDS[src] or Ledger.SRC_IDS.unknown
    Ledger.AppendRecord(session, XP_SERIES, offset, xp, srcId, rested)
end

-- Number of recorded events.
function Ledger.EventCount(session)
    return Ledger.RecordCount(session, XP_SERIES)
end

-- "Effective" xp of an event according to the includeRested toggle: the
-- total xp as-is if true or omitted (default), or without the rested
-- bonus (xp - rested) if false. Never negative: see AddEvent.
function Ledger.EffectiveXP(xp, rested, includeRested)
    if includeRested == false then
        return xp - rested
    end
    return xp
end

-- Sum of xp across all events. includeRested (true by default) decides
-- whether the rested bonus counts toward the total: see EffectiveXP.
function Ledger.TotalXP(session, includeRested)
    local total = 0
    local arr = session[XP_SERIES.key]
    if arr then
        for i = 1, #arr, XP_SERIES.stride do
            local xp     = arr[i + XP_FIELD - 1]
            local rested = arr[i + RESTED_FIELD - 1]
            total = total + Ledger.EffectiveXP(xp, rested, includeRested)
        end
    end
    return total
end

-- Sum of the rested bonus across all events (always the real
-- accumulated total, no toggle: this is exactly what the toggle above
-- does or doesn't subtract from the total).
function Ledger.TotalRested(session)
    local total = 0
    local arr = session[XP_SERIES.key]
    if arr then
        for i = RESTED_FIELD, #arr, XP_SERIES.stride do
            total = total + arr[i]
        end
    end
    return total
end

-- Xp accumulated by source name: { [src] = xpTotal, ... }. Translates
-- the persisted numeric ID (see AddEvent) back to the text name: this
-- is the reading boundary, everything consuming this result (palette,
-- tooltip, state_dump) expects the name.
function Ledger.XPBySource(session)
    local bySource = {}
    local arr = session[XP_SERIES.key]
    if arr then
        for i = 1, #arr, XP_SERIES.stride do
            local xp  = arr[i + XP_FIELD - 1]
            local src = Ledger.SRC_NAMES[arr[i + SRC_FIELD - 1]] or "unknown"
            bySource[src] = (bySource[src] or 0) + xp
        end
    end
    return bySource
end

-- Xp accumulated by source, summed across several sessions (e.g. all of
-- the current level's, not just the active one). Feeds the xp
-- composition bar's tooltip.
function Ledger.XPBySourceAcrossSessions(sessions)
    local bySource = {}
    for _, session in ipairs(sessions) do
        for src, xp in pairs(Ledger.XPBySource(session)) do
            bySource[src] = (bySource[src] or 0) + xp
        end
    end
    return bySource
end

-- Sum of TotalXP (respects includeRested, see EffectiveXP) across
-- several sessions (e.g. all of the current level's, not just the
-- active one). Feeds the level xp/hour rate (core/rate.lua).
function Ledger.TotalXPAcrossSessions(sessions, includeRested)
    local total = 0
    for _, session in ipairs(sessions) do
        total = total + Ledger.TotalXP(session, includeRested)
    end
    return total
end

-- Offset of the last recorded event, or nil if there isn't one.
function Ledger.LastOffset(session)
    local arr = session[XP_SERIES.key]
    if not arr or #arr == 0 then return nil end
    return arr[#arr - XP_SERIES.stride + OFF_FIELD]
end
