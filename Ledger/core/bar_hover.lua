-- Ledger - core/bar_hover.lua
-- Content of what the two bars (xp composition + activity) show on hover:
-- the xp label ("1,234 / 5,678") and the ONE tooltip that covers both
-- bars, as sections with their rows and colors. Pure logic: does not use
-- any WoW API, and does not know ui/palette.lua either -- the palette is
-- received as a parameter (core/ must load standalone), so the colors the
-- tooltip gets are always the very ones that paint the bars.

local ADDON_NAME, Ledger = ...

print("Ledger: core/bar_hover.lua")

-- "{current xp} / {level xp}" with thousands separators, like the native
-- xp bar's own hover text. nil when there is no xp bar to describe (max
-- level: max is 0 or nil) so the caller shows nothing.
function Ledger.FormatXPLabel(cur, max)
    if not cur or not max or max <= 0 then
        return nil
    end
    return string.format("%s / %s",
        Ledger.AddThousandsSeparator(tostring(math.floor(cur))),
        Ledger.AddThousandsSeparator(tostring(math.floor(max))))
end

local SRC_ORDER = { "kill", "quest", "explore", "unknown" }
local SRC_LABELS = {
    kill    = "Kills",
    quest   = "Quests",
    explore = "Exploration",
    unknown = "Unknown",
}

local WHITE = { 1, 1, 1 }

-- Builds the unified tooltip as an ordered list of sections:
--   { { title=, rows = { { text=, color = {r,g,b} }, ... } }, ... }
-- in this order: xp by source (all the level's sessions), then the
-- level's activity split, then the active session's -- the two activity
-- ones always as percentages of samples, never absolute time.
--
-- input = {
--   sessions   = the current level's sessions (LedgerCharDB.sessions),
--   levelTicks = the level's live activity counters,
--   palette    = Ledger.PALETTE-shaped table: palette[src or tick key] =
--                { r, g, b }, plus palette._fallback,
--   showXP     = false leaves out the xp section (its bar is hidden),
--   showTime   = false leaves out the activity sections,
-- }
-- A section with nothing to say (e.g. no session yet) is left out, never
-- emitted empty. The ui/ layer only walks this shape.
function Ledger.BuildBarTooltipSections(input)
    input = input or {}
    local sessions = input.sessions or {}
    local palette  = input.palette or {}
    local function colorFor(key)
        return palette[key] or palette._fallback or WHITE
    end

    local sections = {}

    if input.showXP ~= false then
        local bySource = Ledger.XPBySourceAcrossSessions(sessions)
        local rows = {}
        for _, src in ipairs(SRC_ORDER) do
            rows[#rows + 1] = {
                text  = string.format("%s: %d xp", SRC_LABELS[src], bySource[src] or 0),
                color = colorFor(src),
            }
        end

        local totalRested = 0
        for _, session in ipairs(sessions) do
            totalRested = totalRested + Ledger.TotalRested(session)
        end
        if totalRested > 0 then
            rows[#rows + 1] = { text = string.format("Rested: %d xp", totalRested), color = WHITE }
        end

        sections[#sections + 1] = { title = "Level xp composition", rows = rows }
    end

    if input.showTime ~= false then
        local function tickSection(title, ticks)
            local rows = {}
            for _, line in ipairs(Ledger.FormatTickLines(ticks)) do
                rows[#rows + 1] = { text = line.text, color = colorFor(line.key) }
            end
            return { title = title, rows = rows }
        end

        if input.levelTicks then
            sections[#sections + 1] = tickSection("Level activity (% of samples)", input.levelTicks)
        end
        local active = sessions[#sessions]
        if active and active.ticks then
            sections[#sections + 1] = tickSection("This session (% of samples)", active.ticks)
        end
    end

    return sections
end
