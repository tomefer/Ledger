describe("core/series.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
    end)

    it("declara la serie xp tal y como la usa core/events.lua", function()
        assert.are.same({ key = "e", stride = 4, fields = { "off", "xp", "src", "rested" } }, Ledger.SERIES.xp)
    end)

    describe("SeriesFieldIndex", function()
        it("encuentra el indice de un campo declarado", function()
            local seriesDef = { key = "e", stride = 3, fields = { "off", "xp", "src" } }

            assert.are.equal(1, Ledger.SeriesFieldIndex(seriesDef, "off"))
            assert.are.equal(3, Ledger.SeriesFieldIndex(seriesDef, "src"))
        end)

        it("devuelve nil para un campo que no existe", function()
            local seriesDef = { key = "e", stride = 3, fields = { "off", "xp", "src" } }

            assert.is_nil(Ledger.SeriesFieldIndex(seriesDef, "faction"))
        end)
    end)

    -- Dos series de prueba con stride distinto, para comprobar que los
    -- helpers no dan por hecho 3 campos en ningun sitio.
    local stride3 = { key = "g", stride = 3, fields = { "off", "amount", "src" } }
    local stride4 = { key = "r", stride = 4, fields = { "off", "amount", "faction", "standing" } }

    describe("lectura y escritura con stride 3", function()
        it("anade, cuenta y lee registros correctamente", function()
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

    describe("lectura y escritura con stride 4", function()
        it("anade, cuenta y lee registros correctamente", function()
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

    describe("sesion sin ningun registro todavia", function()
        it("cuenta cero y no revienta al leer", function()
            local session = {}

            assert.are.equal(0, Ledger.RecordCount(session, stride4))
            assert.is_nil(Ledger.ReadRecord(session, stride4, 1))
        end)
    end)

    describe("ConcatSeries", function()
        it("concatena el array plano de varias sesiones en orden", function()
            local a, b = {}, {}
            Ledger.AppendRecord(a, stride3, 10, 5, "kill")
            Ledger.AppendRecord(b, stride3, 20, 8, "quest")
            Ledger.AppendRecord(b, stride3, 30, 2, "kill")

            local combined = Ledger.ConcatSeries({ a, b }, stride3)

            assert.are.same({ 10, 5, "kill", 20, 8, "quest", 30, 2, "kill" }, combined)
        end)

        it("ignora sesiones sin ningun registro de esa serie", function()
            local a, b = {}, {}
            Ledger.AppendRecord(b, stride3, 10, 5, "kill")

            local combined = Ledger.ConcatSeries({ a, b }, stride3)

            assert.are.same({ 10, 5, "kill" }, combined)
        end)

        it("con una lista de sesiones vacia devuelve un array vacio", function()
            assert.are.same({}, Ledger.ConcatSeries({}, stride3))
        end)
    end)
end)
