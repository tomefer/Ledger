describe("core/events.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger) -- Ledger.NewEmptyBuckets
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
    end)

    describe("sesion vacia", function()
        it("no tiene eventos", function()
            local session = Ledger.NewSession(1000, 10)

            assert.are.equal(0, Ledger.EventCount(session))
            assert.are.equal(0, Ledger.TotalXP(session))
            assert.are.same({}, Ledger.XPBySource(session))
            assert.is_nil(Ledger.LastOffset(session))
        end)

        it("trae mode a nil y manual a false por defecto", function()
            local session = Ledger.NewSession(1000, 10)

            assert.is_nil(session.mode)
            assert.is_false(session.manual)
        end)

        it("acepta mode y manual explicitos sin que afecten al src de los eventos", function()
            local session = Ledger.NewSession(1000, 10, "farm", true)
            Ledger.AddEvent(session, 0, 50, "kill")

            assert.are.equal("farm", session.mode)
            assert.is_true(session.manual)
            assert.are.same({ kill = 50 }, Ledger.XPBySource(session))
        end)
    end)

    describe("un evento", function()
        it("se refleja en todas las consultas", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 53, 120, "kill")

            assert.are.equal(1, Ledger.EventCount(session))
            assert.are.equal(120, Ledger.TotalXP(session))
            assert.are.same({ kill = 120 }, Ledger.XPBySource(session))
            assert.are.equal(53, Ledger.LastOffset(session))
        end)
    end)

    describe("varios eventos del mismo origen", function()
        it("suma el xp de ese origen", function()
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

    describe("origenes mezclados", function()
        it("desglosa el xp por origen y mantiene el total", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 10, 50, "kill")
            Ledger.AddEvent(session, 20, 200, "quest")
            Ledger.AddEvent(session, 35, 30, "kill")
            Ledger.AddEvent(session, 40, 10, "quest_bonus")

            assert.are.equal(4, Ledger.EventCount(session))
            assert.are.equal(290, Ledger.TotalXP(session))
            assert.are.same({ kill = 80, quest = 200, quest_bonus = 10 }, Ledger.XPBySource(session))
            assert.are.equal(40, Ledger.LastOffset(session))
        end)
    end)

    describe("numero de eventos", function()
        it("es siempre #e / stride de la serie xp", function()
            local session = Ledger.NewSession(1000, 10)
            for i = 1, 7 do
                Ledger.AddEvent(session, i, i * 10, "src" .. i)
            end

            local xpSeries = Ledger.SERIES.xp
            assert.are.equal(#session[xpSeries.key] / xpSeries.stride, Ledger.EventCount(session))
        end)
    end)

    describe("bono por descanso (rested)", function()
        it("evento sin bonus: rested queda a 0 si se omite", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 50, "kill")

            local record = Ledger.ReadRecord(session, Ledger.SERIES.xp, 1)
            assert.are.equal(0, record.rested)
            assert.are.equal(0, Ledger.TotalRested(session))
        end)

        it("evento con bonus: rested se graba y se acumula", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)

            local record = Ledger.ReadRecord(session, Ledger.SERIES.xp, 1)
            assert.are.equal(172, record.xp)
            assert.are.equal(86, record.rested)
            assert.are.equal(86, Ledger.TotalRested(session))
        end)

        it("acumula rested de varios eventos", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 100, "kill", 20)
            Ledger.AddEvent(session, 10, 50, "kill", 0)
            Ledger.AddEvent(session, 20, 80, "kill", 30)

            assert.are.equal(50, Ledger.TotalRested(session))
        end)

        it("xp - rested nunca es negativo: se recorta rested a xp si llegara mayor", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 50, "kill", 999)

            local record = Ledger.ReadRecord(session, Ledger.SERIES.xp, 1)
            assert.are.equal(50, record.xp)
            assert.are.equal(50, record.rested)
            assert.is_true(record.xp - record.rested >= 0)
        end)
    end)

    describe("TotalXP con el toggle includeRested", function()
        it("por defecto (true) cuenta el bono por descanso", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)
            Ledger.AddEvent(session, 10, 50, "quest")

            assert.are.equal(222, Ledger.TotalXP(session))
            assert.are.equal(222, Ledger.TotalXP(session, true))
        end)

        it("con includeRested=false descuenta el bono de cada evento", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)
            Ledger.AddEvent(session, 10, 50, "quest")

            assert.are.equal(136, Ledger.TotalXP(session, false))
        end)

        it("nunca cuenta el bono dos veces ni deja el total negativo", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 10, "kill", 10)

            assert.are.equal(10, Ledger.TotalXP(session, true))
            assert.are.equal(0, Ledger.TotalXP(session, false))
        end)
    end)

    describe("XPBySourceAcrossSessions", function()
        it("suma el desglose por origen de varias sesiones", function()
            local a = Ledger.NewSession(0, 10)
            Ledger.AddEvent(a, 0, 50, "kill")
            Ledger.AddEvent(a, 10, 20, "quest")

            local b = Ledger.NewSession(100, 10)
            Ledger.AddEvent(b, 0, 30, "kill")
            Ledger.AddEvent(b, 10, 15, "explore")

            local bySource = Ledger.XPBySourceAcrossSessions({ a, b })

            assert.are.same({ kill = 80, quest = 20, explore = 15 }, bySource)
        end)

        it("con una lista de sesiones vacia devuelve una tabla vacia", function()
            assert.are.same({}, Ledger.XPBySourceAcrossSessions({}))
        end)
    end)
end)
