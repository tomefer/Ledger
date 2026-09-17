describe("core/xp_bar.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/xp_bar.lua"))("Ledger", Ledger)
    end)

    -- Construye el array plano de la serie xp a partir de una lista de
    -- {xp=, src=, rested=} (off no importa para la barra, siempre 0).
    -- src se traduce a su ID numerico (Ledger.SRC_IDS): es el formato en
    -- el que vive de verdad dentro del array (ver core/events.lua:
    -- AddEvent); ComputeBarSegments lo traduce de vuelta a texto al
    -- leerlo (core/xp_bar.lua: MergeConsecutive).
    local function events(list)
        local arr = {}
        for _, e in ipairs(list) do
            arr[#arr + 1] = e.off or 0
            arr[#arr + 1] = e.xp
            arr[#arr + 1] = Ledger.SRC_IDS[e.src]
            arr[#arr + 1] = e.rested or 0
        end
        return arr
    end

    describe("array vacio", function()
        it("sin eventos ni xp previa no hay segmentos", function()
            local segments = Ledger.ComputeBarSegments({}, 0, 200, 1000)
            assert.are.same({}, segments)
        end)

        it("con maxXP a 0 tampoco (evita dividir por cero)", function()
            local segments = Ledger.ComputeBarSegments(events({ { xp = 10, src = "kill" } }), 0, 200, 0)
            assert.are.same({}, segments)
        end)
    end)

    describe("un evento", function()
        it("un unico segmento con la anchura proporcional", function()
            local arr = events({ { xp = 500, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 200, 1000)

            assert.are.equal(1, #segments)
            assert.are.same({ offset = 0, width = 100, src = "kill", restedWidth = 0 }, segments[1])
        end)
    end)

    describe("varios eventos del mismo src", function()
        it("se fusionan en un solo segmento sumando xp", function()
            local arr = events({
                { xp = 100, src = "kill" },
                { xp = 150, src = "kill" },
                { xp = 50,  src = "kill" },
            })
            local segments = Ledger.ComputeBarSegments(arr, 0, 200, 1000)

            assert.are.equal(1, #segments)
            assert.are.equal(60, segments[1].width) -- (300/1000)*200
        end)

        it("suma tambien el rested al fusionar", function()
            local arr = events({
                { xp = 100, src = "kill", rested = 20 },
                { xp = 50,  src = "kill", rested = 10 },
            })
            -- Escala 1:1 (widthPx = maxXP) para que la anchura en
            -- pixeles coincida exactamente con la xp: xp total 150,
            -- rested total 30.
            local segments = Ledger.ComputeBarSegments(arr, 0, 1000, 1000)

            assert.are.equal(150, segments[1].width)
            assert.are.equal(30, segments[1].restedWidth)
        end)
    end)

    describe("src alternos", function()
        it("no fusiona eventos de distinto src, aunque un mismo src reaparezca despues", function()
            local arr = events({
                { xp = 100, src = "kill" },
                { xp = 100, src = "quest" },
                { xp = 100, src = "kill" },
            })
            local segments = Ledger.ComputeBarSegments(arr, 0, 300, 1000)

            assert.are.equal(3, #segments)
            assert.are.equal("kill", segments[1].src)
            assert.are.equal("quest", segments[2].src)
            assert.are.equal("kill", segments[3].src)
        end)
    end)

    describe("redondeo de anchuras", function()
        it("la suma de segmentos nunca supera el ancho total (tercios exactos)", function()
            local arr = events({
                { xp = 1, src = "kill" },
                { xp = 1, src = "quest" },
                { xp = 1, src = "explore" },
            })
            local segments = Ledger.ComputeBarSegments(arr, 0, 10, 3)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 10)
            assert.are.equal(10, total) -- el nivel esta completo (xp = maxXP)
        end)

        it("no se pasa del ancho total con muchos eventos pequeños", function()
            local parts = {}
            for i = 1, 37 do
                parts[i] = { xp = 1, src = (i % 2 == 0) and "kill" or "quest" }
            end
            local segments = Ledger.ComputeBarSegments(events(parts), 0, 200, 37)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 200)
            assert.are.equal(200, total)
        end)
    end)

    describe("segmento gris inicial", function()
        it("aparece primero cuando hay xp previa al registro", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 400, 500, 1000)

            assert.are.equal(2, #segments)
            assert.are.equal(Ledger.BAR_INITIAL_SRC, segments[1].src)
            assert.are.equal(0, segments[1].offset)
            assert.are.equal(200, segments[1].width) -- (400/1000)*500
            assert.are.equal("kill", segments[2].src)
            assert.are.equal(200, segments[2].offset)
        end)

        it("no aparece si no hay xp previa", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 500, 1000)

            assert.are.equal(1, #segments)
            assert.are.equal("kill", segments[1].src)
        end)

        it("tampoco aparece con initialXP a nil", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, nil, 500, 1000)

            assert.are.equal(1, #segments)
        end)

        it("puede ser el unico segmento si todavia no hay ningun evento", function()
            local segments = Ledger.ComputeBarSegments({}, 250, 500, 1000)

            assert.are.equal(1, #segments)
            assert.are.equal(Ledger.BAR_INITIAL_SRC, segments[1].src)
            assert.are.equal(125, segments[1].width)
        end)
    end)

    describe("restedWidth", function()
        it("nunca supera width, incluso con rested = xp", function()
            local arr = events({ { xp = 3, src = "kill", rested = 3 } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 1, 3)

            assert.is_true(segments[1].restedWidth <= segments[1].width)
        end)

        it("es 0 cuando el segmento no tiene bono", function()
            local arr = events({ { xp = 100, src = "kill" } })
            local segments = Ledger.ComputeBarSegments(arr, 0, 200, 1000)

            assert.are.equal(0, segments[1].restedWidth)
        end)

        it("el segmento inicial nunca tiene rested", function()
            local segments = Ledger.ComputeBarSegments({}, 100, 200, 1000)
            assert.are.equal(0, segments[1].restedWidth)
        end)
    end)
end)
