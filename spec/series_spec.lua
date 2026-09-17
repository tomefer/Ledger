describe("core/series.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
    end)

    it("declares the xp series exactly as core/events.lua uses it", function()
        assert.are.same({ key = "e", stride = 4, fields = { "off", "xp", "src", "rested" } }, Ledger.SERIES.xp)
    end)

    describe("SeriesFieldIndex", function()
        it("finds the index of a declared field", function()
            local seriesDef = { key = "e", stride = 3, fields = { "off", "xp", "src" } }

            assert.are.equal(1, Ledger.SeriesFieldIndex(seriesDef, "off"))
            assert.are.equal(3, Ledger.SeriesFieldIndex(seriesDef, "src"))
        end)

        it("returns nil for a field that doesn't exist", function()
            local seriesDef = { key = "e", stride = 3, fields = { "off", "xp", "src" } }

            assert.is_nil(Ledger.SeriesFieldIndex(seriesDef, "faction"))
        end)
    end)

    -- Two test series with different strides, to check that the
    -- helpers never assume 3 fields anywhere.
    local stride3 = { key = "g", stride = 3, fields = { "off", "amount", "src" } }
    local stride4 = { key = "r", stride = 4, fields = { "off", "amount", "faction", "standing" } }

    describe("reading and writing with stride 3", function()
        it("appends, counts and reads records correctly", function()
            local session = {}

            Ledger.AppendRecord(session, stride3, 10, 5, "kill")
            Ledger.AppendRecord(session, stride3, 20, 8, "quest")

            assert.are.same({ 10, 5, "kill", 20, 8, "quest" }, session.g)
            assert.are.equal(2, Ledger.RecordCount(session, stride3))
            assert.are.same({ off = 10, amount = 5, src = "kill" }, Ledger.ReadRecord(session, stride3, 1))
            assert.are.same({ off = 20, amount = 8, src = "quest" }, Ledger.ReadRecord(session, stride3, 2))
            assert.is_nil(Ledger.ReadRecord(session, stride3, 3))
        end)
    end)

    describe("reading and writing with stride 4", function()
        it("appends, counts and reads records correctly", function()
            local session = {}

            Ledger.AppendRecord(session, stride4, 10, 50, "Orgrimmar", "honored")
            Ledger.AppendRecord(session, stride4, 20, 75, "Darnassus", "hostile")

            assert.are.same(
                { 10, 50, "Orgrimmar", "honored", 20, 75, "Darnassus", "hostile" },
                session.r
            )
            assert.are.equal(2, Ledger.RecordCount(session, stride4))
            assert.are.same(
                { off = 10, amount = 50, faction = "Orgrimmar", standing = "honored" },
                Ledger.ReadRecord(session, stride4, 1)
            )
            assert.are.same(
                { off = 20, amount = 75, faction = "Darnassus", standing = "hostile" },
                Ledger.ReadRecord(session, stride4, 2)
            )
            assert.is_nil(Ledger.ReadRecord(session, stride4, 3))
        end)
    end)

    describe("session with no records yet", function()
        it("counts zero and doesn't blow up when reading", function()
            local session = {}

            assert.are.equal(0, Ledger.RecordCount(session, stride4))
            assert.is_nil(Ledger.ReadRecord(session, stride4, 1))
        end)
    end)

    describe("ConcatSeries", function()
        it("concatenates the flat array of several sessions in order", function()
            local a, b = {}, {}
            Ledger.AppendRecord(a, stride3, 10, 5, "kill")
            Ledger.AppendRecord(b, stride3, 20, 8, "quest")
            Ledger.AppendRecord(b, stride3, 30, 2, "kill")

            local combined = Ledger.ConcatSeries({ a, b }, stride3)

            assert.are.same({ 10, 5, "kill", 20, 8, "quest", 30, 2, "kill" }, combined)
        end)

        it("ignores sessions with no records of that series", function()
            local a, b = {}, {}
            Ledger.AppendRecord(b, stride3, 10, 5, "kill")

            local combined = Ledger.ConcatSeries({ a, b }, stride3)

            assert.are.same({ 10, 5, "kill" }, combined)
        end)

        it("with an empty session list returns an empty array", function()
            assert.are.same({}, Ledger.ConcatSeries({}, stride3))
        end)
    end)
end)
