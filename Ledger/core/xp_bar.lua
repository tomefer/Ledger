-- Ledger - core/xp_bar.lua
-- Computes the level's xp composition bar segments: merges consecutive
-- records with the same src into a single segment (merging is
-- mandatory: without it there'd be thousands of textures) and computes
-- each one's pixel width, proportional to maxXP. Pure logic: does not
-- use any WoW API; iterates Ledger.SERIES.xp instead of assuming
-- stride or field names, per core/series.lua's hard rule.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_bar.lua")

local XP_SERIES    = Ledger.SERIES.xp
local XP_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local SRC_FIELD    = Ledger.SeriesFieldIndex(XP_SERIES, "src")
local RESTED_FIELD = Ledger.SeriesFieldIndex(XP_SERIES, "rested")

-- src reserved for the initial segment (xp from before the addon
-- started tracking the level). Doesn't match any real src
-- ("kill"/"quest"/"explore"/"unknown"), so the UI can tell it apart
-- unambiguously and always paint it gray.
Ledger.BAR_INITIAL_SRC = "previous"

-- Splits totalWidthPx across `fractions` (each 0..1; they don't need to
-- add up to 1) without the sum of rounded widths ever exceeding
-- totalWidthPx: each segment's rounding is done against the ideal
-- cumulative total, not the loose segment, so the rounding error is
-- compensated between consecutive segments instead of accumulating
-- unchecked. Exposed (not local): also reused by core/time_bar.lua for
-- the time-split bar.
function Ledger.RoundedWidths(fractions, totalWidthPx)
    local widths = {}
    local idealCumulative, actualCumulative = 0, 0
    for i, fraction in ipairs(fractions) do
        idealCumulative = idealCumulative + fraction * totalWidthPx
        local newActual = math.floor(idealCumulative + 0.5)
        widths[i] = newActual - actualCumulative
        actualCumulative = newActual
    end
    return widths
end

-- Merges consecutive records with the same src into a single segment
-- (sums xp and rested). Reads flatArray using Ledger.SERIES.xp's
-- fields, never hardcoded indices/stride. src is persisted as a
-- numeric ID (Ledger.SRC_IDS); it's translated here to the text name,
-- which is what the palette expects (ui/xp_bar.lua:
-- PALETTE[segment.src]).
local function MergeConsecutive(flatArray)
    local merged = {}
    for i = 1, #flatArray, XP_SERIES.stride do
        local xp     = flatArray[i + XP_FIELD - 1]
        local src    = Ledger.SRC_NAMES[flatArray[i + SRC_FIELD - 1]] or "unknown"
        local rested = flatArray[i + RESTED_FIELD - 1]

        local last = merged[#merged]
        if last and last.src == src then
            last.xp     = last.xp + xp
            last.rested = last.rested + rested
        else
            merged[#merged + 1] = { src = src, xp = xp, rested = rested }
        end
    end
    return merged
end

-- flatArray: the xp series' flat array (of one session, or several
-- already concatenated in chronological order with
-- Ledger.ConcatSeries -- see core/series.lua). initialXP: xp from
-- before the addon started tracking the level (0 or nil if none).
-- widthPx: the bar's total width, in pixels. maxXP: the level's
-- UnitXPMax("player"), the X axis scale (0..maxXP).
--
-- Returns an ordered list of segments: { offset=, width=, src=,
-- restedWidth= } (all in pixels; restedWidth <= width always, 0 if the
-- segment has no rested bonus).
function Ledger.ComputeBarSegments(flatArray, initialXP, widthPx, maxXP)
    local merged = MergeConsecutive(flatArray or {})

    if initialXP and initialXP > 0 then
        table.insert(merged, 1, { src = Ledger.BAR_INITIAL_SRC, xp = initialXP, rested = 0 })
    end

    if #merged == 0 or not maxXP or maxXP <= 0 then
        return {}
    end

    local fractions = {}
    for i, segment in ipairs(merged) do
        fractions[i] = segment.xp / maxXP
    end
    local widths = Ledger.RoundedWidths(fractions, widthPx)

    local segments = {}
    local offset = 0
    for i, segment in ipairs(merged) do
        local width = widths[i]
        local restedWidth = 0
        if segment.rested > 0 and segment.xp > 0 then
            restedWidth = math.floor((width * segment.rested / segment.xp) + 0.5)
            if restedWidth > width then restedWidth = width end
        end
        segments[i] = { offset = offset, width = width, src = segment.src, restedWidth = restedWidth }
        offset = offset + width
    end

    return segments
end
