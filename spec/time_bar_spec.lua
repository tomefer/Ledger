describe("core/time_bar.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/xp_bar.lua"))("Ledger", Ledger) -- Ledger.RoundedWidths
        assert(loadfile("Ledger/core/time_bar.lua"))("Ledger", Ledger)
    end)

    describe("ComputeTimeBarSegments", function()
        it("with total 0 there are no segments", function()
            local segments = Ledger.ComputeTimeBarSegments({ active = 0, travel = 0, idle = 0, dead = 0 }, 200)
            assert.are.same({}, segments)
        end)

        it("splits proportionally and respects the fixed active/travel/idle/dead order", function()
            local buckets = { active = 50, travel = 20, idle = 20, dead = 10 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 100)

            assert.are.equal(4, #segments)
            assert.are.equal("active", segments[1].bucket)
            assert.are.equal("travel", segments[2].bucket)
            assert.are.equal("idle", segments[3].bucket)
            assert.are.equal("dead", segments[4].bucket)

            assert.are.equal(50, segments[1].width)
            assert.are.equal(20, segments[2].width)
            assert.are.equal(20, segments[3].width)
            assert.are.equal(10, segments[4].width)
        end)

        it("keeps the fixed order even when the largest bucket isn't active", function()
            -- dead is the largest, but it must still show up last.
            local buckets = { active = 5, travel = 5, idle = 5, dead = 85 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 100)

            assert.are.same({ "active", "travel", "idle", "dead" },
                { segments[1].bucket, segments[2].bucket, segments[3].bucket, segments[4].bucket })
        end)

        it("offsets are cumulative and contiguous", function()
            local buckets = { active = 50, travel = 20, idle = 20, dead = 10 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 100)

            assert.are.equal(0, segments[1].offset)
            assert.are.equal(50, segments[2].offset)
            assert.are.equal(70, segments[3].offset)
            assert.are.equal(90, segments[4].offset)
        end)

        it("the sum of widths never exceeds the total width, even with an inexact split", function()
            local buckets = { active = 1, travel = 1, idle = 1, dead = 0 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 10)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 10)
            assert.are.equal(10, total)
        end)
    end)

    describe("FormatHHMMSS", function()
        it("zero seconds", function()
            assert.are.equal("00:00:00", Ledger.FormatHHMMSS(0))
        end)

        it("less than a minute", function()
            assert.are.equal("00:00:45", Ledger.FormatHHMMSS(45))
        end)

        it("exactly one hour", function()
            assert.are.equal("01:00:00", Ledger.FormatHHMMSS(3600))
        end)

        it("more than an hour", function()
            assert.are.equal("02:05:09", Ledger.FormatHHMMSS(2 * 3600 + 5 * 60 + 9))
        end)
    end)

    describe("FormatTimeBarTooltip", function()
        it("one line per bucket, in the fixed order, with hh:mm:ss and percentage", function()
            local buckets = { active = 3600, travel = 1800, idle = 0, dead = 0 }
            local lines = Ledger.FormatTimeBarTooltip(buckets)

            assert.are.equal(4, #lines)
            assert.are.equal("active", lines[1].bucket)
            assert.is_not_nil(lines[1].text:find("01:00:00", 1, true))
            assert.is_not_nil(lines[1].text:find("66.7%", 1, true))
            assert.are.equal("travel", lines[2].bucket)
            assert.is_not_nil(lines[2].text:find("00:30:00", 1, true))
            assert.is_not_nil(lines[2].text:find("33.3%", 1, true))
        end)

        it("with the total at 0 doesn't blow up and gives 0%", function()
            local lines = Ledger.FormatTimeBarTooltip({ active = 0, travel = 0, idle = 0, dead = 0 })

            for _, line in ipairs(lines) do
                assert.is_not_nil(line.text:find("0.0%", 1, true))
            end
        end)
    end)
end)
