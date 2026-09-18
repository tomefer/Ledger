describe("core/xp_delta.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/xp_delta.lua"))("Ledger", Ledger)
    end)

    describe("same level", function()
        it("normal, positive delta", function()
            local r = Ledger.ComputeXPDelta(100, 150, 1000, 5, 5)

            assert.is_true(r.ok)
            assert.are.equal(50, r.delta)
            assert.are.equal(0, r.levelsGained)
        end)

        it("zero delta: valid, not an error", function()
            local r = Ledger.ComputeXPDelta(100, 100, 1000, 5, 5)

            assert.is_true(r.ok)
            assert.are.equal(0, r.delta)
            assert.is_nil(r.reason)
        end)

        it("lower xp with no level-up: not computable, doesn't invent a number", function()
            local r = Ledger.ComputeXPDelta(200, 100, 1000, 5, 5)

            assert.is_false(r.ok)
            assert.is_nil(r.delta)
            assert.is_not_nil(r.reason)
        end)
    end)

    describe("one-level level-up: UnitXP resets", function()
        it("reconstructs the real delta using the old level's cached max (real reported case)", function()
            -- Real log: previousXP=809 currentXP=79 delta=-730 (with the
            -- naive subtraction). The old level's max (cached before
            -- the ding) is assumed to be 1000 for this example.
            local r = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)

            assert.is_true(r.ok)
            assert.are.equal(1, r.levelsGained)
            assert.are.equal((1000 - 809) + 79, r.delta)
            assert.is_true(r.delta > 0)
        end)

        it("uses the old level's CACHED max, not any other value", function()
            local r = Ledger.ComputeXPDelta(500, 20, 2400, 20, 21)

            assert.are.equal((2400 - 500) + 20, r.delta)
        end)

        it("exposes oldPart/newPart and their sum equals delta exactly (Real SavedVariables analysis, point 1)", function()
            local r = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)

            assert.is_not_nil(r.crossing)
            assert.are.equal(1000 - 809, r.crossing.oldPart)
            assert.are.equal(79, r.crossing.newPart)
            assert.are.equal(r.delta, r.crossing.oldPart + r.crossing.newPart)
            assert.are.equal(12, r.crossing.oldLevel)
            assert.are.equal(13, r.crossing.newLevel)
            assert.are.equal(1000, r.crossing.oldMax) -- the old level's requirement, for level-close
        end)
    end)

    describe("SplitCrossingEvent", function()
        it("the two parts sum to exactly the original event's xp and rested", function()
            local delta = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)
            local paired = { xp = delta.delta, rested = 60, crossing = delta.crossing }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(paired.xp, split.old.xp + split.new.xp)
            assert.are.equal(paired.rested, split.old.rested + split.new.rested)
        end)

        it("splits rested proportionally between each part, not all to one", function()
            -- oldPart=191, newPart=79 (same case as above), rested=100:
            -- floor(100*191/270 + 0.5) = floor(71.24) = 71.
            local delta = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)
            local paired = { xp = delta.delta, rested = 100, crossing = delta.crossing }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(71, split.old.rested)
            assert.are.equal(29, split.new.rested)
        end)

        it("inherits the same split even when rested is 0", function()
            local delta = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)
            local paired = { xp = delta.delta, rested = 0, crossing = delta.crossing }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(0, split.old.rested)
            assert.are.equal(0, split.new.rested)
        end)

        it("restedOld never exceeds oldPart, even if rested (an independent signal) came in higher than xp", function()
            -- oldPart=10, newPart=5, xp=15, but rested=20 > xp: two
            -- independent signals (UnitXP delta vs. the rested-bonus
            -- message) that don't have to fully agree, same as
            -- core/events.lua: AddEvent already accounts for. Without
            -- the clamp, restedOld would come out as 13 (> oldPart=10).
            local paired = { xp = 15, rested = 20, crossing = { oldPart = 10, newPart = 5 } }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(10, split.old.rested) -- clamped to oldPart
            assert.are.equal(20, split.old.rested + split.new.rested) -- nothing is lost, only split differently
        end)
    end)

    describe("jump of more than one level: not computable", function()
        it("marks ok=false, counts the levels and doesn't invent a delta", function()
            local r = Ledger.ComputeXPDelta(809, 79, 1000, 12, 14)

            assert.is_false(r.ok)
            assert.are.equal(2, r.levelsGained)
            assert.is_nil(r.delta)
            assert.is_not_nil(r.reason)
        end)
    end)

    describe("first event with no previous sample", function()
        it("previousXP/previousLevel as nil don't blow up and don't invent a delta", function()
            local r = Ledger.ComputeXPDelta(nil, 50, 1000, nil, 5)

            assert.is_true(r.ok)
            assert.are.equal(0, r.delta)
            assert.are.equal(0, r.levelsGained)
        end)
    end)
end)
