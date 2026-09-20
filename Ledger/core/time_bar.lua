-- Ledger - core/time_bar.lua
-- Computes the level's activity bar segments: the 4 core/ticks.lua
-- activities (combat, non-combat, travel, dead) in a fixed order, with
-- width proportional to their share of the total samples. Unlike the xp
-- bar, here the axis is always 100% of the width (no external max nor
-- prior xp): it's not comparable pixel-to-pixel with the xp bar, they're
-- different axes. Percentages only: no absolute time is ever shown.
-- Pure logic: does not use any WoW API.

local ADDON_NAME, Ledger = ...

-- ticks: a set of activity counters (Ledger.NewTicks). widthPx: the
-- bar's total width. Returns a list in Ledger.TICK_KEYS order:
-- { key=, offset=, width= } (offset/width in pixels). If there are no
-- samples yet (level just started), there are no segments to draw.
function Ledger.ComputeTimeBarSegments(ticks, widthPx)
    local total = ticks.total
    if total <= 0 then
        return {}
    end

    local fractions = {}
    for i, key in ipairs(Ledger.TICK_KEYS) do
        fractions[i] = ticks[key] / total
    end
    local widths = Ledger.RoundedWidths(fractions, widthPx)

    local segments = {}
    local offset = 0
    for i, key in ipairs(Ledger.TICK_KEYS) do
        local width = widths[i]
        segments[i] = { key = key, offset = offset, width = width }
        offset = offset + width
    end
    return segments
end
