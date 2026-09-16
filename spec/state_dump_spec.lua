describe("core/state_dump.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger) -- Ledger.NewEmptyBuckets
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/state_dump.lua"))("Ledger", Ledger)
    end)

    describe("FormatOffset: limites de mm:ss", function()
        it("0 decimas", function()
            assert.are.equal("00:00.0", Ledger.FormatOffset(0))
        end)

        it("59.9s, justo antes de cumplir el minuto", function()
            assert.are.equal("00:59.9", Ledger.FormatOffset(599))
        end)

        it("60.0s, justo al cumplir el minuto", function()
            assert.are.equal("01:00.0", Ledger.FormatOffset(600))
        end)

        it("3600.0s, una hora exacta", function()
            assert.are.equal("60:00.0", Ledger.FormatOffset(36000))
        end)
    end)

    describe("FormatState: tabla vacia", function()
        it("no rompe sin sesiones ni niveles", function()
            local text = Ledger.FormatState({})
            assert.is_not_nil(text:find("Sesion activa: ninguna", 1, true))
            assert.is_not_nil(text:find("Niveles cerrados: ninguno", 1, true))
        end)

        it("acepta charDB a nil", function()
            local text = Ledger.FormatState(nil)
            assert.is_not_nil(text:find("Sesion activa: ninguna", 1, true))
        end)
    end)

    describe("FormatState: sesion con eventos", function()
        it("usa la ultima sesion, la mas reciente primero y respeta el limite de 30", function()
            local session = Ledger.NewSession(0, 10)
            for i = 1, 35 do
                Ledger.AddEvent(session, i * 10, i, "kill")
            end

            local text = Ledger.FormatState({ sessions = { session } })

            assert.is_not_nil(text:find("nivel 10", 1, true))
            assert.is_not_nil(text:find("Ultimos eventos (30 de 35)", 1, true))

            local firstEventLine = text:match("| 35 |")
            assert.is_not_nil(firstEventLine)
            assert.is_nil(text:find("| 5 |", 1, true)) -- evento 5 quedo fuera del limite de 30
        end)
    end)

    describe("FormatState: niveles cerrados", function()
        it("lista cada nivel ordenado con su xp y tiempo", function()
            local levels = {
                [12] = { nivel = 12, totalXP = 500, totalPlayed = 600 },
                [7]  = { nivel = 7, totalXP = 200, totalPlayed = 300 },
            }

            local text = Ledger.FormatState({ levels = levels })

            local pos7  = text:find("nivel 7:", 1, true)
            local pos12 = text:find("nivel 12:", 1, true)
            assert.is_not_nil(pos7)
            assert.is_not_nil(pos12)
            assert.is_true(pos7 < pos12)
        end)
    end)
end)
