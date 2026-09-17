-- Ledger - core/time_bar.lua
-- Computes the level's time-split bar segments: the 4
-- core/time_buckets.lua buckets (active, travel, idle, dead) in a fixed
-- order, with width proportional to their share of the total time.
-- Unlike the xp bar, here the axis is always 100% of the width (no
-- external max nor prior xp): it's not comparable pixel-to-pixel with
-- the xp bar, they're different axes. Pure logic: does not use any WoW
-- API.

local ADDON_NAME, Ledger = ...

print("Ledger: core/time_bar.lua")

-- Fixed left-to-right order, always the same -- so the shape is
-- recognizable at a glance, never reordered by size.
Ledger.TIME_BUCKET_ORDER = { "active", "travel", "idle", "dead" }

local function TotalSeconds(buckets)
    return buckets.active + buckets.travel + buckets.idle + buckets.dead
end

-- buckets: { active=, travel=, idle=, dead= } (seconds). widthPx: the
-- bar's total width. Returns a list in Ledger.TIME_BUCKET_ORDER:
-- { bucket=, offset=, width= } (offset/width in pixels). If the total
-- is 0 (level just started, no samples yet), there are no segments to
-- draw.
function Ledger.ComputeTimeBarSegments(buckets, widthPx)
    local total = TotalSeconds(buckets)
    if total <= 0 then
        return {}
    end

    local fractions = {}
    for i, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        fractions[i] = buckets[bucket] / total
    end
    local widths = Ledger.RoundedWidths(fractions, widthPx)

    local segments = {}
    local offset = 0
    for i, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        local width = widths[i]
        segments[i] = { bucket = bucket, offset = offset, width = width }
        offset = offset + width
    end
    return segments
end

local BUCKET_LABELS = {
    active = "Combat",
    travel = "Travel",
    idle   = "Idle",
    dead   = "Dead",
}

-- Formats seconds as hh:mm:ss (no limit on hours).
function Ledger.FormatHHMMSS(totalSeconds)
    totalSeconds = math.floor(totalSeconds + 0.5)
    local h = math.floor(totalSeconds / 3600)
    local m = math.floor((totalSeconds % 3600) / 60)
    local s = totalSeconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Content of the time bar's tooltip: one entry per bucket (in
-- Ledger.TIME_BUCKET_ORDER) with its absolute time in hh:mm:ss and its
-- percentage of the total. Returns a list of { bucket=, text= } -- the
-- color of each line is decided by whoever paints it (ui/), this file
-- knows nothing about colors or GameTooltip. If the total is 0, each
-- bucket's percentage is 0 (no division by zero).
function Ledger.FormatTimeBarTooltip(buckets)
    local total = TotalSeconds(buckets)
    local lines = {}
    for _, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        local seconds = buckets[bucket]
        local pct = total > 0 and (seconds / total * 100) or 0
        lines[#lines + 1] = {
            bucket = bucket,
            text = string.format("%s: %s (%.1f%%)", BUCKET_LABELS[bucket], Ledger.FormatHHMMSS(seconds), pct),
        }
    end
    return lines
end
