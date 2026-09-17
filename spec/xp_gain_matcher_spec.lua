describe("core/xp_gain_matcher.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/xp_gain_matcher.lua"))("Ledger", Ledger)
    end)

    describe("amount followed by source", function()
        it("pairs them when the source arrives", function()
            local m = Ledger.NewMatcher(1)

            assert.is_nil(Ledger.AddAmount(m, 10.0, 50))
            local paired = Ledger.AddSource(m, 10.05, "kill")

            assert.are.same({ t = 10.0, xp = 50, src = "kill", rested = 0 }, paired)
        end)

        it("propagates the source's rested, not the amount's", function()
            local m = Ledger.NewMatcher(1)

            Ledger.AddAmount(m, 10.0, 172)
            local paired = Ledger.AddSource(m, 10.05, "kill", nil, 86)

            assert.are.same({ t = 10.0, xp = 172, src = "kill", rested = 86 }, paired)
        end)
    end)

    describe("source followed by amount", function()
        it("pairs them even when the source arrives first", function()
            local m = Ledger.NewMatcher(1)

            assert.is_nil(Ledger.AddSource(m, 20.0, "kill"))
            local paired = Ledger.AddAmount(m, 20.05, 75)

            assert.are.same({ t = 20.05, xp = 75, src = "kill", rested = 0 }, paired)
        end)

        it("propagates the queued source's rested", function()
            local m = Ledger.NewMatcher(1)

            Ledger.AddSource(m, 20.0, "kill", nil, 40)
            local paired = Ledger.AddAmount(m, 20.05, 75)

            assert.are.same({ t = 20.05, xp = 75, src = "kill", rested = 40 }, paired)
        end)
    end)

    describe("several pending at once", function()
        it("pairs by temporal proximity, not arrival order", function()
            local m = Ledger.NewMatcher(1)

            assert.is_nil(Ledger.AddAmount(m, 5.0, 10))
            assert.is_nil(Ledger.AddAmount(m, 5.5, 20))

            -- Closer to 5.5 than to 5.0: must pair with the 5.5 one.
            local paired1 = Ledger.AddSource(m, 5.45, "kill")
            assert.are.same({ t = 5.5, xp = 20, src = "kill", rested = 0 }, paired1)

            -- The 5.0 amount is still pending and pairs now.
            local paired2 = Ledger.AddSource(m, 5.05, "other")
            assert.are.same({ t = 5.0, xp = 10, src = "other", rested = 0 }, paired2)
        end)
    end)

    describe("amount with no source", function()
        it("gets flushed with src unknown and rested=0 after the margin, not before", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddAmount(m, 100.0, 30)

            assert.are.same({}, Ledger.Flush(m, 100.5))

            local flushed = Ledger.Flush(m, 101.5)
            assert.are.same({ { t = 100.0, xp = 30, src = "unknown", rested = 0 } }, flushed)

            -- It doesn't get released again on the next flush.
            assert.are.same({}, Ledger.Flush(m, 200))
        end)
    end)

    describe("source with no amount", function()
        it("simply gets discarded after the margin", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 50.0, "kill")

            assert.are.same({}, Ledger.Flush(m, 52.0))

            -- The source is no longer available to pair with.
            assert.is_nil(Ledger.AddAmount(m, 52.0, 99))
        end)
    end)

    describe("default margin", function()
        it("Ledger.MAX_MATCH_GAP is 1.0s", function()
            assert.are.equal(1.0, Ledger.MAX_MATCH_GAP)
        end)
    end)

    describe("exact margin boundary", function()
        it("pairs when the gap is exactly equal to the margin", function()
            local m = Ledger.NewMatcher(1.0)
            Ledger.AddAmount(m, 10.0, 50)

            local paired = Ledger.AddSource(m, 11.0, "kill") -- exact gap: 1.0s

            assert.are.same({ t = 10.0, xp = 50, src = "kill", rested = 0 }, paired)
        end)

        it("doesn't pair when the gap exceeds the margin by a little", function()
            local m = Ledger.NewMatcher(1.0)
            Ledger.AddAmount(m, 10.0, 50)

            local paired = Ledger.AddSource(m, 11.001, "kill") -- gap: 1.001s

            assert.is_nil(paired)
        end)

        it("pairs the real reported case (0.423s gap, previously discarded with a smaller margin)", function()
            local m = Ledger.NewMatcher(Ledger.MAX_MATCH_GAP)
            Ledger.AddAmount(m, 100.000, 172)

            local paired = Ledger.AddSource(m, 100.423, "kill")

            assert.are.same({ t = 100.0, xp = 172, src = "kill", rested = 0 }, paired)
        end)
    end)

    describe("crossing (level-up) travels attached to the amount", function()
        it("shows up in the result if the source matches afterward", function()
            local m = Ledger.NewMatcher(1)
            local crossing = { oldPart = 191, newPart = 79, oldLevel = 12, newLevel = 13 }

            assert.is_nil(Ledger.AddAmount(m, 10.0, 270, nil, crossing))
            local paired = Ledger.AddSource(m, 10.05, "kill")

            assert.are.same(crossing, paired.crossing)
        end)

        it("shows up in the result if the source matches first (source queued first)", function()
            local m = Ledger.NewMatcher(1)
            local crossing = { oldPart = 191, newPart = 79, oldLevel = 12, newLevel = 13 }

            Ledger.AddSource(m, 20.0, "kill")
            local paired = Ledger.AddAmount(m, 20.05, 270, nil, crossing)

            assert.are.same(crossing, paired.crossing)
        end)

        it("survives Flush if no source ever arrives (orphaned, src=unknown)", function()
            local m = Ledger.NewMatcher(1)
            local crossing = { oldPart = 191, newPart = 79, oldLevel = 12, newLevel = 13 }

            Ledger.AddAmount(m, 100.0, 270, nil, crossing)
            local flushed = Ledger.Flush(m, 101.5)

            assert.are.equal(1, #flushed)
            assert.are.equal("unknown", flushed[1].src)
            assert.are.same(crossing, flushed[1].crossing)
        end)

        it("an amount with no crossing still carries no such field", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddAmount(m, 10.0, 50)
            local paired = Ledger.AddSource(m, 10.05, "kill")

            assert.is_nil(paired.crossing)
        end)
    end)

    describe("quest source and priority over explore", function()
        it("a normal quest turn-in pairs with src=quest and expectedXP", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 10.0, "quest", nil, 0, 50)

            local paired = Ledger.AddAmount(m, 10.05, 50)

            assert.are.same({ t = 10.05, xp = 50, src = "quest", rested = 0, expectedXP = 50 }, paired)
        end)

        it("a quest turn-in that also levels up still pairs as quest", function()
            local m = Ledger.NewMatcher(1)
            -- the quest's arg2 (50) doesn't have to match the real delta
            -- already corrected for the level-up (270).
            Ledger.AddSource(m, 10.0, "quest", nil, 0, 50)

            local paired = Ledger.AddAmount(m, 10.05, 270)

            assert.are.equal("quest", paired.src)
            assert.are.equal(270, paired.xp)
            assert.are.equal(50, paired.expectedXP)
        end)

        it("exploration with no QUEST_TURNED_IN in the window pairs as explore", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 10.0, "explore")

            local paired = Ledger.AddAmount(m, 10.05, 45)

            assert.are.equal("explore", paired.src)
            assert.is_nil(paired.expectedXP)
        end)

        it("with quest and explore pending at once, quest wins even if explore is closer in time", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 10.00, "quest", nil, 0, 45)
            Ledger.AddSource(m, 10.09, "explore") -- closer to the amount than the quest

            local paired = Ledger.AddAmount(m, 10.10, 45)

            assert.are.equal("quest", paired.src)
            -- The "explore" source (closer but without priority) stays
            -- pending, it isn't discarded or lost.
            assert.are.equal(1, #m.sources)
            assert.are.equal("explore", m.sources[1].src)
        end)
    end)
end)
