describe("core/level_close.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger) -- Ledger.NewEmptyBuckets
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/level_close.lua"))("Ledger", Ledger)
    end)

    describe("nivel de una sola sesion", function()
        it("agrega totales, desglose y curva de esa sesion", function()
            local s = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(s, 0, 50, "kill")
            Ledger.AddEvent(s, 300, 20, "quest")
            Ledger.AddEvent(s, 650, 100, "kill")

            local entry = Ledger.CloseLevel({ s }, 500)

            assert.are.equal(10, entry.level)
            assert.are.equal(170, entry.totalXP)
            assert.are.equal(500, entry.totalPlayed)
            assert.are.same({ kill = 150, quest = 20 }, entry.bySource)
            assert.are.same({ 70, 100 }, entry.curve)
        end)
    end)

    describe("nivel que abarca varias sesiones", function()
        it("agrega y funde la curva de todas las sesiones del nivel", function()
            local a = Ledger.NewSession(0, 20)
            Ledger.AddEvent(a, 0, 10, "kill")
            Ledger.AddEvent(a, 650, 5, "quest")

            local b = Ledger.NewSession(5000, 20)
            Ledger.AddEvent(b, 100, 20, "kill")
            Ledger.AddEvent(b, 1300, 8, "quest")

            local entry = Ledger.CloseLevel({ a, b }, 900)

            assert.are.equal(20, entry.level)
            assert.are.equal(43, entry.totalXP)
            assert.are.equal(900, entry.totalPlayed)
            assert.are.same({ kill = 30, quest = 13 }, entry.bySource)
            -- minuto 1: 10 (a) + 20 (b); minuto 2: 5 (a); minuto 3: 8 (b)
            assert.are.same({ 30, 5, 8 }, entry.curve)
        end)
    end)

    describe("sesion que abarca dos niveles", function()
        it("agrega cada trozo por separado sin mezclar ni perder eventos", function()
            -- Una sesion real que dinga a mitad de partida se le pasa a
            -- esta funcion ya trocasteada por quien llama: un cierre de
            -- nivel por cada mitad de su array de eventos.
            local level5 = Ledger.NewSession(2000, 5)
            Ledger.AddEvent(level5, 0, 80, "kill")
            Ledger.AddEvent(level5, 200, 40, "quest")
            Ledger.AddEvent(level5, 250, 1, "kill")   -- golpe que hace ding

            local level6 = Ledger.NewSession(2000, 6)
            Ledger.AddEvent(level6, 300, 60, "kill")
            Ledger.AddEvent(level6, 900, 30, "quest")

            local entry5 = Ledger.CloseLevel({ level5 }, 25)
            local entry6 = Ledger.CloseLevel({ level6 }, 90)

            assert.are.equal(5, entry5.level)
            assert.are.equal(121, entry5.totalXP)
            assert.are.same({ kill = 81, quest = 40 }, entry5.bySource)
            assert.are.same({ 121 }, entry5.curve)

            assert.are.equal(6, entry6.level)
            assert.are.equal(90, entry6.totalXP)
            assert.are.same({ kill = 60, quest = 30 }, entry6.bySource)
            assert.are.same({ 60, 30 }, entry6.curve)

            -- Ni se pierde ni se duplica xp al trocear la sesion original.
            assert.are.equal(80 + 40 + 1 + 60 + 30, entry5.totalXP + entry6.totalXP)
        end)
    end)

    describe("totalRested", function()
        it("acumula el bono por descanso de todas las sesiones del nivel", function()
            local a = Ledger.NewSession(0, 15)
            Ledger.AddEvent(a, 0, 172, "kill", 86)
            Ledger.AddEvent(a, 300, 50, "quest")

            local b = Ledger.NewSession(5000, 15)
            Ledger.AddEvent(b, 100, 60, "kill", 20)

            local entry = Ledger.CloseLevel({ a, b }, 900)

            assert.are.equal(106, entry.totalRested)
            -- totalXP nunca descuenta el bono por si solo (includeRested
            -- por defecto es true).
            assert.are.equal(282, entry.totalXP)
        end)

        it("es cero cuando ningun evento trajo bono", function()
            local s = Ledger.NewSession(0, 3)
            Ledger.AddEvent(s, 0, 40, "kill")

            local entry = Ledger.CloseLevel({ s }, 60)

            assert.are.equal(0, entry.totalRested)
        end)
    end)

    describe("CloseLevel con el toggle includeRested", function()
        it("con includeRested=false, totalXP y curve descuentan el bono, totalRested no cambia", function()
            local s = Ledger.NewSession(0, 8)
            Ledger.AddEvent(s, 0, 172, "kill", 86)   -- minuto 1
            Ledger.AddEvent(s, 650, 50, "quest")     -- minuto 2

            local entryTrue  = Ledger.CloseLevel({ s }, 120, true)
            local entryFalse = Ledger.CloseLevel({ s }, 120, false)

            assert.are.equal(222, entryTrue.totalXP)
            assert.are.same({ 172, 50 }, entryTrue.curve)

            assert.are.equal(136, entryFalse.totalXP)
            assert.are.same({ 86, 50 }, entryFalse.curve)

            -- El bono acumulado real es el mismo independientemente del
            -- toggle: el toggle solo afecta al calculo, nunca a lo
            -- grabado.
            assert.are.equal(86, entryTrue.totalRested)
            assert.are.equal(86, entryFalse.totalRested)
        end)

        it("bySource nunca cambia con el toggle: sigue siendo la xp total tal cual", function()
            local s = Ledger.NewSession(0, 8)
            Ledger.AddEvent(s, 0, 172, "kill", 86)

            local entryTrue  = Ledger.CloseLevel({ s }, 60, true)
            local entryFalse = Ledger.CloseLevel({ s }, 60, false)

            assert.are.same({ kill = 172 }, entryTrue.bySource)
            assert.are.same({ kill = 172 }, entryFalse.bySource)
        end)
    end)

    describe("nivel sin eventos", function()
        it("devuelve totales a cero y curva vacia sin romper", function()
            local s = Ledger.NewSession(3000, 42)

            local entry = Ledger.CloseLevel({ s }, 45)

            assert.are.equal(42, entry.level)
            assert.are.equal(0, entry.totalXP)
            assert.are.equal(45, entry.totalPlayed)
            assert.are.same({}, entry.bySource)
            assert.are.same({}, entry.curve)
            assert.are.same({ active = 0, idle = 0, travel = 0, dead = 0 }, entry.buckets)
        end)
    end)

    describe("buckets de tiempo", function()
        it("suma los buckets de todas las sesiones del nivel", function()
            local a = Ledger.NewSession(0, 7)
            a.buckets = { active = 100, idle = 20, travel = 30, dead = 0 }

            local b = Ledger.NewSession(5000, 7)
            b.buckets = { active = 40, idle = 10, travel = 0, dead = 15 }

            local entry = Ledger.CloseLevel({ a, b }, 215)

            assert.are.same({ active = 140, idle = 30, travel = 30, dead = 15 }, entry.buckets)
        end)

        it("una sesion sin buckets (esquema viejo antes de migrar) no revienta", function()
            local a = Ledger.NewSession(0, 7)
            a.buckets = nil
            local b = Ledger.NewSession(5000, 7)
            b.buckets = { active = 10, idle = 0, travel = 0, dead = 0 }

            local entry = Ledger.CloseLevel({ a, b }, 10)

            assert.are.same({ active = 10, idle = 0, travel = 0, dead = 0 }, entry.buckets)
        end)
    end)

    describe("deaths", function()
        it("suma las muertes de todas las sesiones del nivel", function()
            local a = Ledger.NewSession(0, 7)
            a.deaths = 2
            local b = Ledger.NewSession(5000, 7)
            b.deaths = 1

            local entry = Ledger.CloseLevel({ a, b }, 10)

            assert.are.equal(3, entry.deaths)
        end)

        it("es 0 si ninguna sesion murio (deaths ya viene a 0 por NewSession)", function()
            local s = Ledger.NewSession(0, 7)

            local entry = Ledger.CloseLevel({ s }, 10)

            assert.are.equal(0, entry.deaths)
        end)
    end)

    describe("reached", function()
        it("toma el reached de la primera sesion del nivel", function()
            local a = Ledger.NewSession(0, 7)
            a.reached = 1758000000
            local b = Ledger.NewSession(5000, 7)

            local entry = Ledger.CloseLevel({ a, b }, 10)

            assert.are.equal(1758000000, entry.reached)
        end)

        it("es 0 si la sesion no trae reached (esquema viejo antes de migrar)", function()
            local s = Ledger.NewSession(0, 7)

            local entry = Ledger.CloseLevel({ s }, 10)

            assert.are.equal(0, entry.reached)
        end)
    end)

    describe("RecordLevelClose", function()
        it("crea db.levels si no existe y escribe la entrada por nivel", function()
            local db = {}
            local entry = { level = 7, totalXP = 300 }

            Ledger.RecordLevelClose(db, entry)

            assert.are.same({ [7] = entry }, db.levels)
        end)

        it("no pisa entradas de otros niveles ya guardadas", function()
            local db = { levels = { [3] = { level = 3, totalXP = 10 } } }
            local entry = { level = 4, totalXP = 20 }

            Ledger.RecordLevelClose(db, entry)

            assert.are.same({ level = 3, totalXP = 10 }, db.levels[3])
            assert.are.same(entry, db.levels[4])
        end)
    end)
end)
