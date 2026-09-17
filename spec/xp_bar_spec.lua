describe("core/xp_bar.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/xp_bar.lua"))("Ledger", Ledger)
    end)

    -- Builds the xp series' flat array from a list of
    -- {xp=, src=, rested=} (off doesn't matter for the bar, always 0).
    -- src is translated to its numeric ID (Ledger.SRC_IDS): that's the
    -- format it really lives in inside the array (see core/events.lua:
    -- AddEvent); ComputeBarSegments translates it back to text when
    -- reading it (core/xp_bar.lua: MergeConsecutive).
    local function events(list)
        local arr = {}
        for _, e in ipairs(list) do
            arr[#arr + 1] = e.off or 0
            arr[#arr + 1] = e.xp
            arr[#arr + 1] = Ledger.SRC_IDS[e.src]
            arr[#arr + 1] = e.rested or 0
        end
        return arr
    end

    describe("empty array", function()
        it("with no events or prior xp there are no segments", function()
            local segments = Ledger.ComputeBarSegments({}, 0, 200, 1000)
            assert.are.same({}, segments)
        end)

        it("nor with maxXP at 0 (avoids dividing by zero)", function()
            local segments = Ledger.ComputeBarSegments(events({ { xp = 10, src = "kill" } }), 0, 200, 0)
            assert.are.same({}, segments)
        end)
    end)

    describe("one event", function()
        it("a single segment with proportional width", function()
            local arr = events({ { xp = 500, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 200, 1000)

            assert.are.equal(1, #segments)
            assert.are.same({ offset = 0, width = 100, src = "kill", restedWidth = 0 }, segments[1])
        end)
    end)

    describe("several events with the same src", function()
        it("merge into a single segment, summing xp", function()
            local arr = events({
                { xp = 100, src = "kill" },
                { xp = 150, src = "kill" },
                { xp = 50,  src = "kill" },
            })
            local segments = Ledger.ComputeBarSegments(arr, 0, 200, 1000)

            assert.are.equal(1, #segments)
            assert.are.equal(60, segments[1].width) -- (300/1000)*200
        end)

        it("also sums rested when merging", function()
            local arr = events({
                { xp = 100, src = "kill", rested = 20 },
                { xp = 50,  src = "kill", rested = 10 },
            })
            -- 1:1 scale (widthPx = maxXP) so the width in pixels matches
            -- the xp exactly: total xp 150, total rested 30.
            local segments = Ledger.ComputeBarSegments(arr, 0, 1000, 1000)

            assert.are.equal(150, segments[1].width)
            assert.are.equal(30, segments[1].restedWidth)
        end)
    end)

    describe("alternating src", function()
        it("doesn't merge events with different src, even if the same src reappears later", function()
            local arr = events({
                { xp = 100, src = "kill" },
                { xp = 100, src = "quest" },
                { xp = 100, src = "kill" },
            })
            local segments = Ledger.ComputeBarSegments(arr, 0, 300, 1000)

            assert.are.equal(3, #segments)
            assert.are.equal("kill", segments[1].src)
            assert.are.equal("quest", segments[2].src)
            assert.are.equal("kill", segments[3].src)
        end)
    end)

    describe("width rounding", function()
        it("the sum of segments never exceeds the total width (exact thirds)", function()
            local arr = events({
                { xp = 1, src = "kill" },
                { xp = 1, src = "quest" },
                { xp = 1, src = "explore" },
            })
            local segments = Ledger.ComputeBarSegments(arr, 0, 10, 3)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 10)
            assert.are.equal(10, total) -- the level is complete (xp = maxXP)
        end)

        it("doesn't exceed the total width with many small events", function()
            local parts = {}
            for i = 1, 37 do
                parts[i] = { xp = 1, src = (i % 2 == 0) and "kill" or "quest" }
            end
            local segments = Ledger.ComputeBarSegments(events(parts), 0, 200, 37)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 200)
            assert.are.equal(200, total)
        end)
    end)

    describe("initial gray segment", function()
        it("shows up first when there's xp from before tracking started", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 400, 500, 1000)

            assert.are.equal(2, #segments)
            assert.are.equal(Ledger.BAR_INITIAL_SRC, segments[1].src)
            assert.are.equal(0, segments[1].offset)
            assert.are.equal(200, segments[1].width) -- (400/1000)*500
            assert.are.equal("kill", segments[2].src)
            assert.are.equal(200, segments[2].offset)
        end)

        it("doesn't show up if there's no prior xp", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 500, 1000)

            assert.are.equal(1, #segments)
            assert.are.equal("kill", segments[1].src)
        end)

        it("doesn't show up with initialXP as nil either", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, nil, 500, 1000)

            assert.are.equal(1, #segments)
        end)

        it("can be the only segment if there are no events yet", function()
            local segments = Ledger.ComputeBarSegments({}, 250, 500, 1000)

            assert.are.equal(1, #segments)
            assert.are.equal(Ledger.BAR_INITIAL_SRC, segments[1].src)
            assert.are.equal(125, segments[1].width)
        end)
    end)

    describe("restedWidth", function()
        it("never exceeds width, even with rested = xp", function()
            local arr = events({ { xp = 3, src = "kill", rested = 3 } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 1, 3)

            assert.is_true(segments[1].restedWidth <= segments[1].width)
        end)

        it("is 0 when the segment has no bonus", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 200, 1000)

            assert.are.equal(0, segments[1].restedWidth)
        end)

        it("the initial segment never has rested", function()
            local segments = Ledger.ComputeBarSegments({}, 100, 200, 1000)
            assert.are.equal(0, segments[1].restedWidth)
        end)
    end)
end)
