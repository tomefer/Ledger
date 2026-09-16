describe("core/xp_gain_matcher.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/xp_gain_matcher.lua"))("Ledger", Ledger)
    end)

    describe("cantidad seguida de origen", function()
        it("los empareja cuando llega el origen", function()
            local m = Ledger.NewMatcher(1)

            assert.is_nil(Ledger.AddAmount(m, 10.0, 50))
            local paired = Ledger.AddSource(m, 10.05, "kill")

            assert.are.same({ t = 10.0, xp = 50, src = "kill", rested = 0 }, paired)
        end)

        it("propaga el rested del origen, no de la cantidad", function()
            local m = Ledger.NewMatcher(1)

            Ledger.AddAmount(m, 10.0, 172)
            local paired = Ledger.AddSource(m, 10.05, "kill", nil, 86)

            assert.are.same({ t = 10.0, xp = 172, src = "kill", rested = 86 }, paired)
        end)
    end)

    describe("origen seguido de cantidad", function()
        it("los empareja aunque el origen llegue primero", function()
            local m = Ledger.NewMatcher(1)

            assert.is_nil(Ledger.AddSource(m, 20.0, "kill"))
            local paired = Ledger.AddAmount(m, 20.05, 75)

            assert.are.same({ t = 20.05, xp = 75, src = "kill", rested = 0 }, paired)
        end)

        it("propaga el rested del origen encolado", function()
            local m = Ledger.NewMatcher(1)

            Ledger.AddSource(m, 20.0, "kill", nil, 40)
            local paired = Ledger.AddAmount(m, 20.05, 75)

            assert.are.same({ t = 20.05, xp = 75, src = "kill", rested = 40 }, paired)
        end)
    end)

    describe("varios pendientes a la vez", function()
        it("empareja por proximidad temporal, no por orden de llegada", function()
            local m = Ledger.NewMatcher(1)

            assert.is_nil(Ledger.AddAmount(m, 5.0, 10))
            assert.is_nil(Ledger.AddAmount(m, 5.5, 20))

            -- Mas cerca de 5.5 que de 5.0: debe emparejar con la de 5.5.
            local paired1 = Ledger.AddSource(m, 5.45, "kill")
            assert.are.same({ t = 5.5, xp = 20, src = "kill", rested = 0 }, paired1)

            -- La cantidad de 5.0 sigue pendiente y se empareja ahora.
            local paired2 = Ledger.AddSource(m, 5.05, "other")
            assert.are.same({ t = 5.0, xp = 10, src = "other", rested = 0 }, paired2)
        end)
    end)

    describe("cantidad sin origen", function()
        it("se vacia con src desconocido y rested=0 tras el margen, no antes", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddAmount(m, 100.0, 30)

            assert.are.same({}, Ledger.Flush(m, 100.5))

            local flushed = Ledger.Flush(m, 101.5)
            assert.are.same({ { t = 100.0, xp = 30, src = "unknown", rested = 0 } }, flushed)

            -- No se vuelve a soltar en el siguiente vaciado.
            assert.are.same({}, Ledger.Flush(m, 200))
        end)
    end)

    describe("origen sin cantidad", function()
        it("se descarta sin mas tras el margen", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 50.0, "kill")

            assert.are.same({}, Ledger.Flush(m, 52.0))

            -- El origen ya no esta disponible para emparejar.
            assert.is_nil(Ledger.AddAmount(m, 52.0, 99))
        end)
    end)

    describe("margen por defecto", function()
        it("Ledger.MAX_MATCH_GAP es 1.0s", function()
            assert.are.equal(1.0, Ledger.MAX_MATCH_GAP)
        end)
    end)

    describe("limite exacto del margen", function()
        it("empareja cuando la separacion es exactamente igual al margen", function()
            local m = Ledger.NewMatcher(1.0)
            Ledger.AddAmount(m, 10.0, 50)

            local paired = Ledger.AddSource(m, 11.0, "kill") -- separacion exacta: 1.0s

            assert.are.same({ t = 10.0, xp = 50, src = "kill", rested = 0 }, paired)
        end)

        it("no empareja cuando la separacion supera el margen por poco", function()
            local m = Ledger.NewMatcher(1.0)
            Ledger.AddAmount(m, 10.0, 50)

            local paired = Ledger.AddSource(m, 11.001, "kill") -- separacion: 1.001s

            assert.is_nil(paired)
        end)

        it("empareja el caso real reportado (separacion de 0.423s, antes descartada con un margen menor)", function()
            local m = Ledger.NewMatcher(Ledger.MAX_MATCH_GAP)
            Ledger.AddAmount(m, 100.000, 172)

            local paired = Ledger.AddSource(m, 100.423, "kill")

            assert.are.same({ t = 100.0, xp = 172, src = "kill", rested = 0 }, paired)
        end)
    end)

    describe("fuente quest y prioridad sobre explore", function()
        it("una entrega de quest normal se empareja con src=quest y expectedXP", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 10.0, "quest", nil, 0, 50)

            local paired = Ledger.AddAmount(m, 10.05, 50)

            assert.are.same({ t = 10.05, xp = 50, src = "quest", rested = 0, expectedXP = 50 }, paired)
        end)

        it("una entrega de quest que ademas sube de nivel tambien se empareja como quest", function()
            local m = Ledger.NewMatcher(1)
            -- arg2 de la quest (50) no tiene por que coincidir con el
            -- delta real ya corregido por la subida de nivel (270).
            Ledger.AddSource(m, 10.0, "quest", nil, 0, 50)

            local paired = Ledger.AddAmount(m, 10.05, 270)

            assert.are.equal("quest", paired.src)
            assert.are.equal(270, paired.xp)
            assert.are.equal(50, paired.expectedXP)
        end)

        it("exploracion sin ningun QUEST_TURNED_IN en la ventana se empareja como explore", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 10.0, "explore")

            local paired = Ledger.AddAmount(m, 10.05, 45)

            assert.are.equal("explore", paired.src)
            assert.is_nil(paired.expectedXP)
        end)

        it("con quest y explore pendientes a la vez, gana quest aunque explore este mas cerca en el tiempo", function()
            local m = Ledger.NewMatcher(1)
            Ledger.AddSource(m, 10.00, "quest", nil, 0, 45)
            Ledger.AddSource(m, 10.09, "explore") -- mas cerca del amount que la quest

            local paired = Ledger.AddAmount(m, 10.10, 45)

            assert.are.equal("quest", paired.src)
            -- La fuente "explore" (mas cercana pero sin prioridad) se
            -- queda pendiente, no se descarta ni se pierde.
            assert.are.equal(1, #m.sources)
            assert.are.equal("explore", m.sources[1].src)
        end)
    end)
end)
