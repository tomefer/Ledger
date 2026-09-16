describe("core/time_buckets.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        local chunk = assert(loadfile("Ledger/core/time_buckets.lua"))
        chunk("Ledger", Ledger)
    end)

    it("expone el umbral por defecto", function()
        assert.are.equal(30, Ledger.INACTIVITY_THRESHOLD)
    end)

    it("NewEmptyBuckets da los 4 buckets a cero", function()
        assert.are.same({ active = 0, idle = 0, travel = 0, dead = 0 }, Ledger.NewEmptyBuckets())
    end)

    -- El resto de tests pasa un umbral explicito (180) en vez de
    -- depender del valor por defecto de Ledger.INACTIVITY_THRESHOLD:
    -- asi no se rompen si ese valor por defecto vuelve a cambiar mas
    -- adelante.

    describe("umbral exacto", function()
        it("reclasifica active a travel cuando el hueco iguala el umbral", function()
            local t = Ledger.NewTracker(0, "active", 180)
            Ledger.AddSample(t, 180, "idle")

            assert.are.equal(0, t.buckets.active)
            assert.are.equal(180, t.buckets.travel)
        end)
    end)

    describe("tramo corto que no lo cruza", function()
        it("mantiene el tramo como active si no llega al umbral", function()
            local t = Ledger.NewTracker(0, "active", 180)
            Ledger.AddSample(t, 50, "idle")

            assert.are.equal(50, t.buckets.active)
            assert.are.equal(0, t.buckets.travel)
        end)
    end)

    describe("secuencia viaje-combate-viaje", function()
        it("cuenta el combate como active y los huecos largos como travel", function()
            local t = Ledger.NewTracker(0, "travel", 180)

            Ledger.AddSample(t, 50, "active")   -- 50s de viaje
            Ledger.AddSample(t, 55, "active")   -- 5s de combate (hueco corto)
            Ledger.AddSample(t, 60, "active")   -- 5s de combate (hueco corto)
            Ledger.AddSample(t, 260, "travel")  -- 200s sin combate: se reclasifica
            Ledger.AddSample(t, 300, "idle")    -- 40s mas de viaje

            assert.are.equal(10, t.buckets.active)
            assert.are.equal(290, t.buckets.travel)
        end)
    end)

    describe("hueco de inactividad tras un kill, contado entero como travel", function()
        it("mata, espera 190s (por encima del umbral), mata: los 190s son travel, no se reparten con idle", function()
            local t = Ledger.NewTracker(0, "active", 180) -- t=0: instante del kill 1

            -- El ticker de ui/xp_capture.lua detecta a los 180s de
            -- inactividad que toca transicionar, y llama AddSample con
            -- "travel" (nunca "idle") -- una unica vez.
            Ledger.AddSample(t, 180, "travel")  -- transicion a los 180s
            Ledger.AddSample(t, 190, "active")  -- kill 2, 190s despues del kill 1

            assert.are.equal(190, t.buckets.travel)
            assert.are.equal(0, t.buckets.idle)
        end)
    end)

    describe("suma de buckets", function()
        it("es igual al tiempo total transcurrido", function()
            local t = Ledger.NewTracker(1000, "idle")

            Ledger.AddSample(t, 1030, "active")
            Ledger.AddSample(t, 1050, "active")
            Ledger.AddSample(t, 1550, "dead")
            Ledger.AddSample(t, 1565, "travel")
            Ledger.AddSample(t, 1600, "idle")

            local total = t.buckets.active + t.buckets.idle + t.buckets.travel + t.buckets.dead
            assert.are.equal(1600 - 1000, total)
        end)
    end)

    describe("PreviewBuckets", function()
        it("no muta el tracker", function()
            local t = Ledger.NewTracker(0, "active", 180)
            Ledger.PreviewBuckets(t, 50)

            assert.are.equal(0, t.lastT)
            assert.are.equal("active", t.lastState)
            assert.are.equal(0, t.buckets.active)
        end)

        it("suma el tramo abierto al bucket del estado vigente", function()
            local t = Ledger.NewTracker(0, "idle", 180)
            Ledger.AddSample(t, 10, "active") -- 10s de idle ya cerrados
            local preview = Ledger.PreviewBuckets(t, 15) -- 5s de active abiertos

            assert.are.equal(10, preview.idle)
            assert.are.equal(5, preview.active)
            -- el tracker de verdad no se ha tocado
            assert.are.equal(0, t.buckets.active)
        end)

        it("aplica la misma reclasificacion retroactiva que AddSample", function()
            local t = Ledger.NewTracker(0, "active", 180)
            local preview = Ledger.PreviewBuckets(t, 200) -- 200s >= umbral(180)

            assert.are.equal(0, preview.active)
            assert.are.equal(200, preview.travel)
        end)

        it("con el tramo abierto todavia corto, no reclasifica", function()
            local t = Ledger.NewTracker(0, "active", 180)
            local preview = Ledger.PreviewBuckets(t, 50)

            assert.are.equal(50, preview.active)
            assert.are.equal(0, preview.travel)
        end)
    end)

    describe("ShouldTransitionToTravel", function()
        it("false si el estado vigente no es active", function()
            local t = Ledger.NewTracker(0, "idle", 180)
            assert.is_false(Ledger.ShouldTransitionToTravel(t, 500, 0))
        end)

        it("false si el reloj de inactividad no ha llegado al umbral", function()
            local t = Ledger.NewTracker(0, "active", 180)
            assert.is_false(Ledger.ShouldTransitionToTravel(t, 179, 0))
        end)

        it("true justo al llegar al umbral", function()
            local t = Ledger.NewTracker(0, "active", 180)
            assert.is_true(Ledger.ShouldTransitionToTravel(t, 180, 0))
        end)

        it("usa lastActivityTime, no lastT del tracker", function()
            local t = Ledger.NewTracker(0, "active", 180)
            t.lastT = 1000 -- ultima muestra reciente...
            -- ...pero la ultima actividad real (xp/combate) fue hace mucho
            assert.is_true(Ledger.ShouldTransitionToTravel(t, 1000, 800))
        end)
    end)
end)
