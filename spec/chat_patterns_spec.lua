describe("core/chat_patterns.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/chat_patterns.lua"))("Ledger", Ledger)
    end)

    describe("pattern with a name", function()
        it("captures the name and the amount", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")
            local name, xp = ("Young Wolf dies, you gain 10 experience."):match(pattern)

            assert.are.equal("Young Wolf", name)
            assert.are.equal("10", xp)
        end)
    end)

    describe("pattern without a name", function()
        it("captures only the amount", function()
            local pattern = Ledger.BuildPattern("You gain %d experience.")
            local xp = ("You gain 45 experience."):match(pattern)

            assert.are.equal("45", xp)
        end)
    end)

    describe("messages that don't match", function()
        it("does not match a different text", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")

            assert.is_nil(("Young Wolf dies, you gain 10 gold."):match(pattern))
        end)

        it("escapes the global string's literal magic characters", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")

            -- If the trailing period weren't escaped, it would act as a
            -- wildcard and this would match anyway.
            assert.is_nil(("Young Wolf dies, you gain 10 experiencex"):match(pattern))
        end)
    end)

    describe("rested-bonus suffix", function()
        it("matches the message even when it continues with the bonus suffix", function()
            local pattern = Ledger.BuildPattern("%s dies, you gain %d experience.")
            local name, xp = ("Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)"):match(pattern)

            assert.are.equal("Young Goretusk", name)
            assert.are.equal("172", xp)
        end)

        it("still matches the same message with no suffix at all", function()
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

        it("classifies as kill when a variant with a creature name matches, even with the bonus suffix", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(
                { killEntry, unnamedEntry },
                "Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)")

            assert.are.equal("kill", category)
            assert.is_true(attempts[1].matched)
            assert.are.same({ "Young Goretusk", "172" }, attempts[1].captured)
        end)

        it("classifies as explore when a variant with no creature name matches", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(
                { killEntry, unnamedEntry },
                "You gain 45 experience.")

            assert.are.equal("explore", category)
            assert.is_false(attempts[1].matched)
            assert.is_true(attempts[2].matched)
            assert.are.same({ "45" }, attempts[2].captured)
        end)

        it("never returns unknown: if no variant matches, defaults to explore", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(
                { killEntry },
                "A message format we don't recognize yet.")

            assert.are.equal("explore", category)
            assert.is_false(attempts[1].matched)
        end)

        it("with an empty variant list it also returns explore, never unknown", function()
            local category, attempts = Ledger.ClassifyXPGainMatch({}, "any message")

            assert.are.equal("explore", category)
            assert.are.same({}, attempts)
        end)
    end)

    describe("a message that is not a string (nil; ui/ never passes a secret one)", function()
        local entries

        before_each(function()
            entries = {
                { name = "X", text = "You gain %d experience.", pattern = Ledger.BuildPattern("You gain %d experience.") },
            }
        end)

        it("ClassifyXPGainMatch matches nothing and falls back to explore", function()
            local category, attempts = Ledger.ClassifyXPGainMatch(entries, nil)
            assert.are.equal("explore", category)
            assert.are.same({}, attempts)
        end)

        it("ExtractRestedBonus returns 0", function()
            assert.are.equal(0, Ledger.ExtractRestedBonus(entries, nil))
        end)

        it("ExtractExploreXP returns nil", function()
            assert.is_nil(Ledger.ExtractExploreXP(entries, nil))
        end)
    end)

    describe("BuildSuffixPattern and ExtractRestedBonus", function()
        local restedEntry

        before_each(function()
            restedEntry = {
                name = "COMBATLOG_XPGAIN_EXHAUSTION1",
                text = " (+%d exp Rested bonus)",
                pattern = Ledger.BuildSuffixPattern(" (+%d exp Rested bonus)"),
            }
        end)

        it("BuildSuffixPattern doesn't anchor the start: matches anywhere in the message", function()
            local xp = ("Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)"):match(restedEntry.pattern)
            assert.are.equal("86", xp)
        end)

        it("ExtractRestedBonus returns the amount when the message carries the suffix", function()
            local rested = Ledger.ExtractRestedBonus(
                { restedEntry },
                "Young Goretusk dies, you gain 172 experience. (+86 exp Rested bonus)")

            assert.are.equal(86, rested)
        end)

        it("ExtractRestedBonus returns 0 when the message carries no suffix", function()
            local rested = Ledger.ExtractRestedBonus(
                { restedEntry },
                "Young Goretusk dies, you gain 172 experience.")

            assert.are.equal(0, rested)
        end)

        it("ExtractRestedBonus returns 0 with an empty or nil variant list", function()
            assert.are.equal(0, Ledger.ExtractRestedBonus({}, "any message"))
            assert.are.equal(0, Ledger.ExtractRestedBonus(nil, "any message"))
        end)

        it("tries several variants in order until one matches", function()
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

    describe("ExtractExploreXP", function()
        local entries

        before_each(function()
            local text = "Discovered %s: %d experience gained"
            entries = { { name = "ERR_ZONE_EXPLORED_XP", text = text, pattern = Ledger.BuildPattern(text) } }
        end)

        it("returns the xp of an area-discovery message (real case: a cave, 70 xp)", function()
            assert.are.equal(70, Ledger.ExtractExploreXP(entries, "Discovered Wailing Caverns: 70 experience gained"))
        end)

        it("takes the amount, not the area name, even if the name has digits or colons", function()
            assert.are.equal(45, Ledger.ExtractExploreXP(entries, "Discovered Area 52: East: 45 experience gained"))
        end)

        it("returns nil for any other system message", function()
            assert.is_nil(Ledger.ExtractExploreXP(entries, "Tomef has come online."))
            assert.is_nil(Ledger.ExtractExploreXP(entries, "You gain 45 experience."))
        end)

        it("returns nil when there are no entries at all", function()
            assert.is_nil(Ledger.ExtractExploreXP({}, "Discovered X: 70 experience gained"))
            assert.is_nil(Ledger.ExtractExploreXP(nil, "Discovered X: 70 experience gained"))
        end)
    end)

    describe("FormatXPGainStrings", function()
        it("indicates when there is no global string at all", function()
            local text = Ledger.FormatXPGainStrings({})
            assert.is_not_nil(text:find("No COMBATLOG_XPGAIN_", 1, true))
        end)

        it("accepts nil as if there were none", function()
            local text = Ledger.FormatXPGainStrings(nil)
            assert.is_not_nil(text:find("No COMBATLOG_XPGAIN_", 1, true))
        end)

        it("lists each entry's name, literal value and pattern", function()
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
