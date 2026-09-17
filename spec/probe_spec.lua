describe("core/probe.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/probe.lua"))("Ledger", Ledger)
    end)

    describe("FormatProbe: GetBuildInfo", function()
        it("reports absent when the build table says so", function()
            local text = Ledger.FormatProbe({ build = { present = false } })
            assert.is_not_nil(text:find("GetBuildInfo: absent", 1, true))
        end)

        it("reports a call failure with the error message", function()
            local text = Ledger.FormatProbe({ build = { present = true, callFailed = true, error = "boom" } })
            assert.is_not_nil(text:find("GetBuildInfo: present, call failed (boom)", 1, true))
        end)

        it("reports version/build/date/tocversion when the call succeeds", function()
            local text = Ledger.FormatProbe({
                build = { present = true, version = "1.60.1", build = "60001", date = "Jan 1 2026", tocversion = 16001 },
            })
            assert.is_not_nil(text:find("version=1.60.1 build=60001 date=Jan 1 2026 tocversion=16001", 1, true))
        end)

        it("treats a nil build field the same as absent", function()
            local text = Ledger.FormatProbe({})
            assert.is_not_nil(text:find("GetBuildInfo: absent", 1, true))
        end)
    end)

    describe("FormatProbe: APIs", function()
        it("marks a missing API as absent", function()
            local text = Ledger.FormatProbe({ apis = { { name = "UnitOnTaxi", present = false } } })
            assert.is_not_nil(text:find("UnitOnTaxi: absent", 1, true))
        end)

        it("marks a present API with a single value", function()
            local text = Ledger.FormatProbe({ apis = { { name = "UnitXP", present = true, values = { 120 } } } })
            assert.is_not_nil(text:find("UnitXP: present, value = 120", 1, true))
        end)

        it("joins several returned values with commas", function()
            local text = Ledger.FormatProbe({
                apis = { { name = "GetUnitSpeed", present = true, values = { 7, false, true } } },
            })
            assert.is_not_nil(text:find("GetUnitSpeed: present, value = 7, false, true", 1, true))
        end)

        it("reports present with no return value (e.g. RequestTimePlayed)", function()
            local text = Ledger.FormatProbe({
                apis = { { name = "RequestTimePlayed", present = true, values = {} } },
            })
            assert.is_not_nil(text:find("RequestTimePlayed: present, no return value", 1, true))
        end)

        it("reports a call failure with its error", function()
            local text = Ledger.FormatProbe({
                apis = { { name = "GetXPExhaustion", present = true, callFailed = true, error = "nope" } },
            })
            assert.is_not_nil(text:find("GetXPExhaustion: present, call failed (nope)", 1, true))
        end)

        it("with no apis list at all, prints just the header", function()
            local text = Ledger.FormatProbe({})
            assert.is_not_nil(text:find("APIs:", 1, true))
        end)
    end)

    describe("FormatProbe: COMBATLOG_XPGAIN_* globals", function()
        it("reports zero found with an empty list", function()
            local text = Ledger.FormatProbe({ xpGainGlobals = {} })
            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_* globals: 0 found", 1, true))
        end)

        it("reports the count and lists every name", function()
            local text = Ledger.FormatProbe({
                xpGainGlobals = { "COMBATLOG_XPGAIN_FIRSTPERSON", "COMBATLOG_XPGAIN_EXHAUSTION1" },
            })
            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_* globals: 2 found", 1, true))
            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_FIRSTPERSON", 1, true))
            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_EXHAUSTION1", 1, true))
        end)

        it("with no list at all, reports zero found", function()
            local text = Ledger.FormatProbe({})
            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_* globals: 0 found", 1, true))
        end)
    end)

    describe("FormatProbe: C_ChatInfo", function()
        it("reports present", function()
            local text = Ledger.FormatProbe({ chatInfoPresent = true })
            assert.is_not_nil(text:find("C_ChatInfo: present", 1, true))
        end)

        it("reports absent", function()
            local text = Ledger.FormatProbe({ chatInfoPresent = false })
            assert.is_not_nil(text:find("C_ChatInfo: absent", 1, true))
        end)
    end)

    describe("FormatProbe: XP bar anchor", function()
        it("reports not resolved yet when nil", function()
            local text = Ledger.FormatProbe({})
            assert.is_not_nil(text:find("XP bar anchor: not resolved yet", 1, true))
        end)

        it("reports the resolved source and dimensions", function()
            local text = Ledger.FormatProbe({
                xpBarAnchor = { source = "MainStatusTrackingBarContainer (matched child)", width = 200, height = 8 },
            })
            assert.is_not_nil(text:find(
                "XP bar anchor: MainStatusTrackingBarContainer (matched child) (width=200, height=8)", 1, true))
        end)

        it("reports the degraded fallback source", function()
            local text = Ledger.FormatProbe({
                xpBarAnchor = { source = "degraded (no anchor found)", width = 200, height = 8 },
            })
            assert.is_not_nil(text:find("XP bar anchor: degraded (no anchor found)", 1, true))
        end)
    end)

    describe("FormatProbe: no data at all", function()
        it("nil data doesn't blow up and reports everything absent/empty", function()
            local text = Ledger.FormatProbe(nil)
            assert.is_not_nil(text:find("GetBuildInfo: absent", 1, true))
            assert.is_not_nil(text:find("COMBATLOG_XPGAIN_* globals: 0 found", 1, true))
            assert.is_not_nil(text:find("C_ChatInfo: absent", 1, true))
        end)
    end)
end)
