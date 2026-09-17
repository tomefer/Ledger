describe("core/xp_delta.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/xp_delta.lua"))("Ledger", Ledger)
    end)

    describe("mismo nivel", function()
        it("delta normal, positivo", function()
            local r = Ledger.ComputeXPDelta(100, 150, 1000, 5, 5)

            assert.is_true(r.ok)
            assert.are.equal(50, r.delta)
            assert.are.equal(0, r.levelsGained)
        end)

        it("delta cero: valido, no es un error", function()
            local r = Ledger.ComputeXPDelta(100, 100, 1000, 5, 5)

            assert.is_true(r.ok)
            assert.are.equal(0, r.delta)
            assert.is_nil(r.reason)
        end)

        it("xp menor sin subida de nivel: no calculable, no inventa un numero", function()
            local r = Ledger.ComputeXPDelta(200, 100, 1000, 5, 5)

            assert.is_false(r.ok)
            assert.is_nil(r.delta)
            assert.is_not_nil(r.reason)
        end)
    end)

    describe("subida de un nivel: UnitXP se reinicia", function()
        it("reconstruye el delta real con el maximo cacheado del nivel viejo (caso real reportado)", function()
            -- Log real: xpAnterior=809 xpActual=79 delta=-730 (con la
            -- resta ingenua). El maximo del nivel viejo (cacheado antes
            -- del ding) se supone 1000 para este ejemplo.
            local r = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)

            assert.is_true(r.ok)
            assert.are.equal(1, r.levelsGained)
            assert.are.equal((1000 - 809) + 79, r.delta)
            assert.is_true(r.delta > 0)
        end)

        it("usa el maximo CACHEADO del nivel viejo, no cualquier otro valor", function()
            local r = Ledger.ComputeXPDelta(500, 20, 2400, 20, 21)

            assert.are.equal((2400 - 500) + 20, r.delta)
        end)

        it("expone oldPart/newPart y su suma iguala exactamente delta (Analisis del SavedVariables real, punto 1)", function()
            local r = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)

            assert.is_not_nil(r.crossing)
            assert.are.equal(1000 - 809, r.crossing.oldPart)
            assert.are.equal(79, r.crossing.newPart)
            assert.are.equal(r.delta, r.crossing.oldPart + r.crossing.newPart)
            assert.are.equal(12, r.crossing.oldLevel)
            assert.are.equal(13, r.crossing.newLevel)
        end)
    end)

    describe("SplitCrossingEvent", function()
        it("las dos partes suman exactamente xp y rested del evento original", function()
            local delta = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)
            local paired = { xp = delta.delta, rested = 60, crossing = delta.crossing }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(paired.xp, split.old.xp + split.new.xp)
            assert.are.equal(paired.rested, split.old.rested + split.new.rested)
        end)

        it("reparte rested proporcionalmente a cada parte, no todo a una", function()
            -- oldPart=191, newPart=79 (mismo caso que arriba), rested=100:
            -- floor(100*191/270 + 0.5) = floor(71.24) = 71.
            local delta = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)
            local paired = { xp = delta.delta, rested = 100, crossing = delta.crossing }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(71, split.old.rested)
            assert.are.equal(29, split.new.rested)
        end)

        it("hereda el mismo reparto aunque rested sea 0", function()
            local delta = Ledger.ComputeXPDelta(809, 79, 1000, 12, 13)
            local paired = { xp = delta.delta, rested = 0, crossing = delta.crossing }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(0, split.old.rested)
            assert.are.equal(0, split.new.rested)
        end)

        it("restedOld nunca supera oldPart, ni siquiera si rested (señal independiente) llegara a superar xp", function()
            -- oldPart=10, newPart=5, xp=15, pero rested=20 > xp: dos
            -- señales independientes (delta de UnitXP vs. mensaje de
            -- descanso) que no tienen por que casar del todo, igual que
            -- ya contempla core/events.lua: AddEvent. Sin el recorte,
            -- restedOld saldria en 13 (> oldPart=10).
            local paired = { xp = 15, rested = 20, crossing = { oldPart = 10, newPart = 5 } }

            local split = Ledger.SplitCrossingEvent(paired)

            assert.are.equal(10, split.old.rested) -- recortado a oldPart
            assert.are.equal(20, split.old.rested + split.new.rested) -- nada se pierde, solo se reparte distinto
        end)
    end)

    describe("salto de mas de un nivel: no calculable", function()
        it("marca ok=false, cuenta los niveles y no inventa un delta", function()
            local r = Ledger.ComputeXPDelta(809, 79, 1000, 12, 14)

            assert.is_false(r.ok)
            assert.are.equal(2, r.levelsGained)
            assert.is_nil(r.delta)
            assert.is_not_nil(r.reason)
        end)
    end)

    describe("primer evento sin muestra anterior", function()
        it("previousXP/previousLevel a nil no revientan y no inventan un delta", function()
            local r = Ledger.ComputeXPDelta(nil, 50, 1000, nil, 5)

            assert.is_true(r.ok)
            assert.are.equal(0, r.delta)
            assert.are.equal(0, r.levelsGained)
        end)
    end)
end)
