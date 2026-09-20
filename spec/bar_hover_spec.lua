-- core/bar_hover.lua: the xp label and the unified tooltip's content.

describe("core/bar_hover.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/rate.lua"))("Ledger", Ledger) -- AddThousandsSeparator
        assert(loadfile("Ledger/core/bar_hover.lua"))("Ledger", Ledger)
    end)

    describe("FormatXPLabel", function()
        it("is '{current} / {level}' with thousands separators", function()
            assert.are.equal("1,234 / 5,678", Ledger.FormatXPLabel(1234, 5678))
            assert.are.equal("12,345 / 1,234,567", Ledger.FormatXPLabel(12345, 1234567))
        end)

        it("small numbers get no separator", function()
            assert.are.equal("0 / 400", Ledger.FormatXPLabel(0, 400))
            assert.are.equal("999 / 1,000", Ledger.FormatXPLabel(999, 1000))
        end)

        it("nil when there is no xp bar to describe (max level, no data)", function()
            assert.is_nil(Ledger.FormatXPLabel(0, 0))
            assert.is_nil(Ledger.FormatXPLabel(0, nil))
            assert.is_nil(Ledger.FormatXPLabel(nil, 100))
        end)
    end)

    describe("BuildBarTooltipSections", function()
        local palette = {
            kill = { 1, 0, 0 }, quest = { 0, 1, 0 }, explore = { 0, 0, 1 }, unknown = { 0.5, 0.5, 0.5 },
            combat = { 1, 0, 0 }, nonCombat = { 0.5, 0.5, 0.5 }, travel = { 0, 1, 1 }, dead = { 0.3, 0, 0 },
            _fallback = { 1, 0, 1 },
        }

        local function sessionWith(ticks)
            local s = Ledger.NewSession(0, 5, nil, false)
            Ledger.AddEvent(s, 10, 100, "kill", 20)
            Ledger.AddEvent(s, 20, 50, "quest", 0)
            for k, v in pairs(ticks or {}) do s.ticks[k] = v end
            return s
        end

        local function build(overrides)
            local session = sessionWith({ combat = 3, nonCombat = 1, total = 4 })
            local input = {
                sessions = { session },
                levelTicks = { combat = 30, nonCombat = 10, travel = 0, dead = 0, total = 40 },
                palette = palette,
            }
            for k, v in pairs(overrides or {}) do input[k] = v end
            return Ledger.BuildBarTooltipSections(input)
        end

        it("orders the sections: xp by source first, then the time splits", function()
            local sections = build()

            assert.are.equal(3, #sections)
            assert.are.equal("Level xp composition", sections[1].title)
            assert.are.equal("Level activity (% of samples)", sections[2].title)
            assert.are.equal("This session (% of samples)", sections[3].title)
        end)

        it("xp rows: one per source in a fixed order, with their xp and the palette's color", function()
            local rows = build()[1].rows

            assert.are.same({ text = "Kills: 100 xp",       color = palette.kill },    rows[1])
            assert.are.same({ text = "Quests: 50 xp",       color = palette.quest },   rows[2])
            assert.are.same({ text = "Exploration: 0 xp",   color = palette.explore }, rows[3])
            assert.are.same({ text = "Unknown: 0 xp",       color = palette.unknown }, rows[4])
        end)

        it("adds the rested total (white) only when there is some", function()
            local rows = build()[1].rows
            assert.are.equal(5, #rows)
            assert.are.same({ text = "Rested: 20 xp", color = { 1, 1, 1 } }, rows[5])

            local plain = Ledger.NewSession(0, 5, nil, false)
            Ledger.AddEvent(plain, 10, 100, "kill", 0)
            local noRested = Ledger.BuildBarTooltipSections({ sessions = { plain }, palette = palette, showTime = false })[1].rows
            assert.are.equal(4, #noRested)
        end)

        it("sums the xp of ALL the level's sessions, not just the active one", function()
            local a, b = sessionWith(), sessionWith()
            local sections = Ledger.BuildBarTooltipSections({ sessions = { a, b }, palette = palette, showTime = false })

            assert.are.equal("Kills: 200 xp", sections[1].rows[1].text)
            assert.are.equal("Rested: 40 xp", sections[1].rows[5].text)
        end)

        it("time rows are percentages of samples, colored by activity", function()
            local rows = build()[2].rows

            assert.are.same({ text = "Combat: 75.0%",     color = palette.combat },    rows[1])
            assert.are.same({ text = "Non-combat: 25.0%", color = palette.nonCombat }, rows[2])
            assert.are.equal("Travel: 0.0%", rows[3].text)
            assert.are.equal("Dead: 0.0%", rows[4].text)
        end)

        it("the session section is the ACTIVE (last) session's ticks", function()
            local old = sessionWith({ combat = 1, total = 1 })
            local active = sessionWith({ travel = 1, total = 1 })
            local sections = Ledger.BuildBarTooltipSections({
                sessions = { old, active }, levelTicks = active.ticks, palette = palette,
            })

            assert.are.equal("Travel: 100.0%", sections[3].rows[3].text)
        end)

        it("never shows an absolute time", function()
            for _, section in ipairs(build()) do
                for _, row in ipairs(section.rows) do
                    assert.is_nil(row.text:find("%d+s$"))
                    assert.is_nil(row.text:find("%d+m %d+s"))
                end
            end
        end)

        it("showXP=false leaves the xp section out, showTime=false the activity ones", function()
            local noXP = build({ showXP = false })
            assert.are.equal(2, #noXP)
            assert.are.equal("Level activity (% of samples)", noXP[1].title)

            local noTime = build({ showTime = false })
            assert.are.equal(1, #noTime)
            assert.are.equal("Level xp composition", noTime[1].title)
        end)

        it("no session yet: no session section, no error", function()
            local sections = Ledger.BuildBarTooltipSections({
                sessions = {}, levelTicks = Ledger.NewTicks(), palette = palette,
            })

            assert.are.equal(2, #sections)
            assert.are.equal("Level activity (% of samples)", sections[2].title)
        end)

        it("an unknown key falls back to the palette's fallback color; no palette at all is white", function()
            local s = Ledger.BuildBarTooltipSections({ sessions = {}, palette = { _fallback = { 1, 0, 1 } }, showTime = false })
            assert.are.same({ 1, 0, 1 }, s[1].rows[1].color)

            local bare = Ledger.BuildBarTooltipSections({ sessions = {}, showTime = false })
            assert.are.same({ 1, 1, 1 }, bare[1].rows[1].color)
        end)

        it("tolerates a nil input", function()
            assert.is_table(Ledger.BuildBarTooltipSections(nil))
        end)
    end)
end)
