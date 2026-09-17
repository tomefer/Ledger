describe("core/chat_patterns.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/chat_patterns.lua"))("Ledger", Ledger)
    end)

    describe("patron con nombre", function()
        it("captura el nombre y la cantidad", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")
            local name, xp = ("Young Wolf dies, you gain 10 experience."):match(pattern)

            assert.are.equal("Young Wolf", name)
            assert.are.equal("10", xp)
        end)
    end)

    describe("patron sin nombre", function()
        it("captura solo la cantidad", function()
            local pattern = Ledger.BuildPattern("You gain %d experience.")
            local xp = ("You gain 45 experience."):match(pattern)

            assert.are.equal("45", xp)
        end)
    end)

    describe("mensajes que no encajan", function()
        it("no coincide con un texto distinto", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")

            assert.is_nil(("Young Wolf dies, you gain 10 gold."):match(pattern))
        end)

        it("escapa los caracteres magicos literales del global string", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")

            -- Si el punto final no estuviera escapado, funcionaria como
            -- comodin y esto coincidiria igualmente.
            assert.is_nil(("Young Wolf dies, you gain 10 experiencex"):match(pattern))
        end)
    end)

    describe("sufijo de bono por descanso", function()
        it("casa el mensaje aunque continue con el sufijo de bono", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")
            local name, xp = ("Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)"):match(pattern)

            assert.are.equal("Young Goretusk", name)
            assert.are.equal("172", xp)
        end)

        it("sigue casando el mismo mensaje sin ningun sufijo", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")
            local name, xp = ("Young Goretusk dies, you gain 172 experience."):match(pattern)

            assert.are.equal("Young Goretusk", name)
            assert.are.equal("172", xp)
        end)
    end)

    describe("ClassifyXPGainMatch", function()
        local killEntry, unnamedEntry

        before_each(function()
            killEntry = {
                name = "COMBATLOG_XPGAIN_FIRSTPERSON",
                text = "%s dies, you gain %d experience.",
                pattern = Ledger.BuildPattern("%s dies, you gain %d experience."),
            }
            unnamedEntry = {
                name = "COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED",
                text = "You gain %d experience.",
                pattern = Ledger.BuildPattern("You gain %d experience."),
            }
        end)

        it("clasifica como kill cuando casa una variante con nombre de criatura, incluso con sufijo de bono", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(
                { killEntry, unnamedEntry },
                "Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)")

            assert.are.equal("kill", category)
            assert.is_true(attempts[1].matched)
            assert.are.same({ "Young Goretusk", "172" }, attempts[1].captured)
        end)

        it("clasifica como explore cuando casa una variante sin nombre de criatura", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(
                { killEntry, unnamedEntry },
                "You gain 45 experience.")

            assert.are.equal("explore", category)
            assert.is_false(attempts[1].matched)
            assert.is_true(attempts[2].matched)
            assert.are.same({ "45" }, attempts[2].captured)
        end)

        it("nunca devuelve unknown: si ninguna variante casa, usa explore por defecto", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(
                { killEntry },
                "Un formato de mensaje que todavia no reconocemos.")

            assert.are.equal("explore", category)
            assert.is_false(attempts[1].matched)
        end)

        it("con la lista de variantes vacia tambien devuelve explore, nunca unknown", function()
            local category, attempts = Ledger.ClassifyXPGainMatch({}, "cualquier mensaje")

            assert.are.equal("explore", category)
            assert.are.same({}, attempts)
        end)
    end)

    describe("BuildSuffixPattern y ExtractRestedBonus", function()
        local restedEntry

        before_each(function()
            restedEntry = {
                name = "COMBATLOG_XPGAIN_EXHAUSTION1",
                text = " (+%d exp Rested bonus)",
                pattern = Ledger.BuildSuffixPattern(" (+%d exp Rested bonus)"),
            }
        end)

        it("BuildSuffixPattern no ancla el principio: casa en cualquier punto del mensaje", function()
            local xp = ("Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)"):match(restedEntry.pattern)
            assert.are.equal("86", xp)
        end)

        it("ExtractRestedBonus devuelve la cantidad cuando el mensaje trae el sufijo", function()
            local rested = Ledger.ExtractRestedBonus(
                { restedEntry },
                "Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)")

            assert.are.equal(86, rested)
        end)

        it("ExtractRestedBonus devuelve 0 cuando el mensaje no trae ningun sufijo", function()
            local rested = Ledger.ExtractRestedBonus(
                { restedEntry },
                "Young Goretusk dies, you gain 172 experience.")

            assert.are.equal(0, rested)
        end)

        it("ExtractRestedBonus devuelve 0 con la lista de variantes vacia o nil", function()
            assert.are.equal(0, Ledger.ExtractRestedBonus({}, "cualquier mensaje"))
            assert.are.equal(0, Ledger.ExtractRestedBonus(nil, "cualquier mensaje"))
        end)

        it("prueba varias variantes en orden hasta encontrar la que casa", function()
            local otherEntry = {
                name = "COMBATLOG_XPGAIN_EXHAUSTION2",
                text = " (+%d exp bonus)",
                pattern = Ledger.BuildSuffixPattern(" (+%d exp bonus)"),
            }

            local rested = Ledger.ExtractRestedBonus(
                { otherEntry, restedEntry },
                "You gain 45 experience. (+86 exp Rested bonus)")

            assert.are.equal(86, rested)
        end)
    end)

    describe("FormatXPGainStrings", function()
        it("indica cuando no hay ningun global string", function()
            local text = Ledger.FormatXPGainStrings({})
            assert.is_not_nil(text:find("No COMBATLOG_XPGAIN_", 1, true))
        end)

        it("acepta nil como si no hubiera ninguno", function()
            local text = Ledger.FormatXPGainStrings(nil)
            assert.is_not_nil(text:find("No COMBATLOG_XPGAIN_", 1, true))
        end)

        it("lista nombre, valor literal y patron de cada entrada", function()
            local entries = {
                { name = "COMBATLOG_XPGAIN_FIRSTPERSON", text = "%s dies, you gain %d experience.",
                  pattern = "^(.-) dies, you gain (%d+) experience%." },
            }
            local text = Ledger.FormatXPGainStrings(entries)

            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_FIRSTPERSON = %s dies, you gain %d experience.", 1, true))
            assert.is_not_nil(text:find("^(.-) dies, you gain (%d+) experience%.", 1, true))
        end)
    end)
end)
