describe("core/time_bar.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/xp_bar.lua"))("Ledger", Ledger) -- Ledger.RoundedWidths
        assert(loadfile("Ledger/core/time_bar.lua"))("Ledger", Ledger)
    end)

    local function Ticks(combat, nonCombat, travel, dead)
        return { combat = combat, nonCombat = nonCombat, travel = travel, dead = dead,
                 total = combat + nonCombat + travel + dead }
    end

    describe("ComputeTimeBarSegments", function()
        it("with no samples there are no segments", function()
            assert.are.same({}, Ledger.ComputeTimeBarSegments(Ledger.NewTicks(), 200))
        end)

        it("splits proportionally and respects the fixed combat/nonCombat/travel/dead order", function()
            local segments = Ledger.ComputeTimeBarSegments(Ticks(50, 20, 20, 10), 100)

            assert.are.equal(4, #segments)
            assert.are.equal("combat", segments[1].key)
            assert.are.equal("nonCombat", segments[2].key)
            assert.are.equal("travel", segments[3].key)
            assert.are.equal("dead", segments[4].key)

            assert.are.equal(50, segments[1].width)
            assert.are.equal(20, segments[2].width)
            assert.are.equal(20, segments[3].width)
            assert.are.equal(10, segments[4].width)
        end)

        it("keeps the fixed order even when the largest activity isn't combat", function()
            -- dead is the largest, but it must still show up last.
            local segments = Ledger.ComputeTimeBarSegments(Ticks(5, 5, 5, 85), 100)

            assert.are.same({ "combat", "nonCombat", "travel", "dead" },
                { segments[1].key, segments[2].key, segments[3].key, segments[4].key })
        end)

        it("offsets are cumulative and contiguous", function()
            local segments = Ledger.ComputeTimeBarSegments(Ticks(50, 20, 20, 10), 100)

            assert.are.equal(0, segments[1].offset)
            assert.are.equal(50, segments[2].offset)
            assert.are.equal(70, segments[3].offset)
            assert.are.equal(90, segments[4].offset)
        end)

        it("the sum of widths never exceeds the total width, even with an inexact split", function()
            local segments = Ledger.ComputeTimeBarSegments(Ticks(1, 1, 1, 0), 10)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 10)
            assert.are.equal(10, total)
        end)

        it("the counters' absolute size doesn't matter, only their share", function()
            local small = Ledger.ComputeTimeBarSegments(Ticks(5, 2, 2, 1), 100)
            local large = Ledger.ComputeTimeBarSegments(Ticks(5000, 2000, 2000, 1000), 100)

            assert.are.same(small, large)
        end)
    end)
end)
