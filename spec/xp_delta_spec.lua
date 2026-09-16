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
