describe("core/state_dump.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger) -- Ledger.NewEmptyBuckets
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/state_dump.lua"))("Ledger", Ledger)
    end)

    describe("FormatOffset: mm:ss boundaries", function()
        it("0 tenths", function()
            assert.are.equal("00:00.0", Ledger.FormatOffset(0))
        end)

        it("59.9s, right before completing the minute", function()
            assert.are.equal("00:59.9", Ledger.FormatOffset(599))
        end)

        it("60.0s, right at completing the minute", function()
            assert.are.equal("01:00.0", Ledger.FormatOffset(600))
        end)

        it("3600.0s, exactly one hour", function()
            assert.are.equal("60:00.0", Ledger.FormatOffset(36000))
        end)
    end)

    describe("FormatState: empty table", function()
        it("doesn't break with no sessions or levels", function()
            local text = Ledger.FormatState({})
            assert.is_not_nil(text:find("Active session: none", 1, true))
            assert.is_not_nil(text:find("Closed levels: none", 1, true))
        end)

        it("accepts charDB as nil", function()
            local text = Ledger.FormatState(nil)
            assert.is_not_nil(text:find("Active session: none", 1, true))
        end)
    end)

    describe("FormatState: session with events", function()
        it("uses the last session, most recent first, and respects the 30 limit", function()
            local session = Ledger.NewSession(0, 10)
            for i = 1, 35 do
                Ledger.AddEvent(session, i * 10, i, "kill")
            end

            local text = Ledger.FormatState({ sessions = { session } })

            assert.is_not_nil(text:find("level 10", 1, true))
            assert.is_not_nil(text:find("Last events (30 of 35)", 1, true))

            local firstEventLine = text:match("| 35 |")
            assert.is_not_nil(firstEventLine)
            assert.is_nil(text:find("| 5 |", 1, true)) -- event 5 fell outside the 30 limit
        end)
    end)

    describe("FormatState: closed levels", function()
        it("lists each level sorted with its xp and time", function()
            local levels = {
                [12] = { level = 12, totalXP = 500, totalPlayed = 600 },
                [7]  = { level = 7, totalXP = 200, totalPlayed = 300 },
            }

            local text = Ledger.FormatState({ levels = levels })

            local pos7  = text:find("level 7:", 1, true)
            local pos12 = text:find("level 12:", 1, true)
            assert.is_not_nil(pos7)
            assert.is_not_nil(pos12)
            assert.is_true(pos7 < pos12)
        end)
    end)
end)
