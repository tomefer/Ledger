describe("core/events.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
    end)

    describe("empty session", function()
        it("has no events", function()
            local session = Ledger.NewSession(1000, 10)

            assert.are.equal(0, Ledger.EventCount(session))
            assert.are.equal(0, Ledger.TotalXP(session))
            assert.are.same({}, Ledger.XPBySource(session))
            assert.is_nil(Ledger.LastOffset(session))
        end)

        it("defaults mode to nil and manual to false", function()
            local session = Ledger.NewSession(1000, 10)

            assert.is_nil(session.mode)
            assert.is_false(session.manual)
        end)

        it("defaults deaths to 0 and level to the given value", function()
            local session = Ledger.NewSession(1000, 10)

            assert.are.equal(0, session.deaths)
            assert.are.equal(10, session.level)
        end)

        it("accepts explicit mode and manual without them affecting events' src", function()
            local session = Ledger.NewSession(1000, 10, "farm", true)
            Ledger.AddEvent(session, 0, 50, "kill")

            assert.are.equal("farm", session.mode)
            assert.is_true(session.manual)
            assert.are.same({ kill = 50 }, Ledger.XPBySource(session))
        end)
    end)

    describe("one event", function()
        it("shows up in every query", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 53, 120, "kill")

            assert.are.equal(1, Ledger.EventCount(session))
            assert.are.equal(120, Ledger.TotalXP(session))
            assert.are.same({ kill = 120 }, Ledger.XPBySource(session))
            assert.are.equal(53, Ledger.LastOffset(session))
        end)
    end)

    describe("several events from the same source", function()
        it("sums that source's xp", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 10, 50, "quest")
            Ledger.AddEvent(session, 20, 75, "quest")
            Ledger.AddEvent(session, 30, 25, "quest")

            assert.are.equal(3, Ledger.EventCount(session))
            assert.are.equal(150, Ledger.TotalXP(session))
            assert.are.same({ quest = 150 }, Ledger.XPBySource(session))
            assert.are.equal(30, Ledger.LastOffset(session))
        end)
    end)

    describe("mixed sources", function()
        it("breaks xp down by source and keeps the total", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 10, 50, "kill")
            Ledger.AddEvent(session, 20, 200, "quest")
            Ledger.AddEvent(session, 35, 30, "kill")
            Ledger.AddEvent(session, 40, 10, "explore")

            assert.are.equal(4, Ledger.EventCount(session))
            assert.are.equal(290, Ledger.TotalXP(session))
            assert.are.same({ kill = 80, quest = 200, explore = 10 }, Ledger.XPBySource(session))
            assert.are.equal(40, Ledger.LastOffset(session))
        end)
    end)

    describe("event count", function()
        it("is always #e / the xp series' stride", function()
            local session = Ledger.NewSession(1000, 10)
            for i = 1, 7 do
                Ledger.AddEvent(session, i, i * 10, "src" .. i)
            end

            local xpSeries = Ledger.SERIES.xp
            assert.are.equal(#session[xpSeries.key] / xpSeries.stride, Ledger.EventCount(session))
        end)
    end)

    describe("rested bonus", function()
        it("event with no bonus: rested stays at 0 when omitted", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 50, "kill")

            local record = Ledger.ReadRecord(session, Ledger.SERIES.xp, 1)
            assert.are.equal(0, record.rested)
            assert.are.equal(0, Ledger.TotalRested(session))
        end)

        it("event with a bonus: rested is recorded and accumulates", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)

            local record = Ledger.ReadRecord(session, Ledger.SERIES.xp, 1)
            assert.are.equal(172, record.xp)
            assert.are.equal(86, record.rested)
            assert.are.equal(86, Ledger.TotalRested(session))
        end)

        it("accumulates rested across several events", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 100, "kill", 20)
            Ledger.AddEvent(session, 10, 50, "kill", 0)
            Ledger.AddEvent(session, 20, 80, "kill", 30)

            assert.are.equal(50, Ledger.TotalRested(session))
        end)

        it("xp - rested is never negative: rested is clamped to xp if it would come in higher", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 50, "kill", 999)

            local record = Ledger.ReadRecord(session, Ledger.SERIES.xp, 1)
            assert.are.equal(50, record.xp)
            assert.are.equal(50, record.rested)
            assert.is_true(record.xp - record.rested >= 0)
        end)
    end)

    describe("TotalXP with the includeRested toggle", function()
        it("by default (true) counts the rested bonus", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)
            Ledger.AddEvent(session, 10, 50, "quest")

            assert.are.equal(222, Ledger.TotalXP(session))
            assert.are.equal(222, Ledger.TotalXP(session, true))
        end)

        it("with includeRested=false subtracts the bonus from each event", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)
            Ledger.AddEvent(session, 10, 50, "quest")

            assert.are.equal(136, Ledger.TotalXP(session, false))
        end)

        it("never counts the bonus twice nor leaves the total negative", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 10, "kill", 10)

            assert.are.equal(10, Ledger.TotalXP(session, true))
            assert.are.equal(0, Ledger.TotalXP(session, false))
        end)
    end)

    describe("XPBySourceAcrossSessions", function()
        it("sums the per-source breakdown across several sessions", function()
            local a = Ledger.NewSession(0, 10)
            Ledger.AddEvent(a, 0, 50, "kill")
            Ledger.AddEvent(a, 10, 20, "quest")

            local b = Ledger.NewSession(100, 10)
            Ledger.AddEvent(b, 0, 30, "kill")
            Ledger.AddEvent(b, 10, 15, "explore")

            local bySource = Ledger.XPBySourceAcrossSessions({ a, b })

            assert.are.same({ kill = 80, quest = 20, explore = 15 }, bySource)
        end)

        it("with an empty session list returns an empty table", function()
            assert.are.same({}, Ledger.XPBySourceAcrossSessions({}))
        end)
    end)
end)
