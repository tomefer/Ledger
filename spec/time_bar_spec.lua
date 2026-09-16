describe("core/time_bar.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/xp_bar.lua"))("Ledger", Ledger) -- Ledger.RoundedWidths
        assert(loadfile("Ledger/core/time_bar.lua"))("Ledger", Ledger)
    end)

    describe("ComputeTimeBarSegments", function()
        it("con total 0 no hay segmentos", function()
            local segments = Ledger.ComputeTimeBarSegments({ active = 0, travel = 0, idle = 0, dead = 0 }, 200)
            assert.are.same({}, segments)
        end)

        it("reparte proporcionalmente y respeta el orden fijo active/travel/idle/dead", function()
            local buckets = { active = 50, travel = 20, idle = 20, dead = 10 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 100)

            assert.are.equal(4, #segments)
            assert.are.equal("active", segments[1].bucket)
            assert.are.equal("travel", segments[2].bucket)
            assert.are.equal("idle", segments[3].bucket)
            assert.are.equal("dead", segments[4].bucket)

            assert.are.equal(50, segments[1].width)
            assert.are.equal(20, segments[2].width)
            assert.are.equal(20, segments[3].width)
            assert.are.equal(10, segments[4].width)
        end)

        it("mantiene el orden fijo aunque el bucket mas grande sea otro distinto de active", function()
            -- dead es el mayor, pero debe seguir apareciendo el ultimo.
            local buckets = { active = 5, travel = 5, idle = 5, dead = 85 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 100)

            assert.are.same({ "active", "travel", "idle", "dead" },
                { segments[1].bucket, segments[2].bucket, segments[3].bucket, segments[4].bucket })
        end)

        it("los offsets son acumulativos y contiguos", function()
            local buckets = { active = 50, travel = 20, idle = 20, dead = 10 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 100)

            assert.are.equal(0, segments[1].offset)
            assert.are.equal(50, segments[2].offset)
            assert.are.equal(70, segments[3].offset)
            assert.are.equal(90, segments[4].offset)
        end)

        it("la suma de anchuras nunca supera el ancho total, incluso con reparto no exacto", function()
            local buckets = { active = 1, travel = 1, idle = 1, dead = 0 }
            local segments = Ledger.ComputeTimeBarSegments(buckets, 10)

            local total = 0
            for _, s in ipairs(segments) do total = total + s.width end

            assert.is_true(total <= 10)
            assert.are.equal(10, total)
        end)
    end)

    describe("FormatHHMMSS", function()
        it("cero segundos", function()
            assert.are.equal("00:00:00", Ledger.FormatHHMMSS(0))
        end)

        it("menos de un minuto", function()
            assert.are.equal("00:00:45", Ledger.FormatHHMMSS(45))
        end)

        it("justo una hora", function()
            assert.are.equal("01:00:00", Ledger.FormatHHMMSS(3600))
        end)

        it("mas de una hora", function()
            assert.are.equal("02:05:09", Ledger.FormatHHMMSS(2 * 3600 + 5 * 60 + 9))
        end)
    end)

    describe("FormatTimeBarTooltip", function()
        it("una linea por bucket, en el orden fijo, con hh:mm:ss y porcentaje", function()
            local buckets = { active = 3600, travel = 1800, idle = 0, dead = 0 }
            local lines = Ledger.FormatTimeBarTooltip(buckets)

            assert.are.equal(4, #lines)
            assert.are.equal("active", lines[1].bucket)
            assert.is_not_nil(lines[1].text:find("01:00:00", 1, true))
            assert.is_not_nil(lines[1].text:find("66.7%", 1, true))
            assert.are.equal("travel", lines[2].bucket)
            assert.is_not_nil(lines[2].text:find("00:30:00", 1, true))
            assert.is_not_nil(lines[2].text:find("33.3%", 1, true))
        end)

        it("con el total a 0 no revienta y da 0%", function()
            local lines = Ledger.FormatTimeBarTooltip({ active = 0, travel = 0, idle = 0, dead = 0 })

            for _, line in ipairs(lines) do
                assert.is_not_nil(line.text:find("0.0%", 1, true))
            end
        end)
    end)
end)
