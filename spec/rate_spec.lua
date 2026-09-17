describe("core/rate.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/rate.lua"))("Ledger", Ledger)
    end)

    describe("ComputeXPRate", function()
        it("computes xp per hour from xp and elapsed seconds", function()
            assert.are.equal(3600, Ledger.ComputeXPRate(600, 600))
        end)

        it("a zero numerator with enough elapsed time is a real rate of 0, not nil", function()
            assert.are.equal(0, Ledger.ComputeXPRate(0, 600))
        end)

        it("returns nil below the minimum elapsed threshold (too noisy)", function()
            assert.is_nil(Ledger.ComputeXPRate(50, 59))
        end)

        it("returns a real rate right at the threshold", function()
            assert.are.equal(3000, Ledger.ComputeXPRate(50, 60))
        end)

        it("returns nil with nil xp or nil elapsed", function()
            assert.is_nil(Ledger.ComputeXPRate(nil, 600))
            assert.is_nil(Ledger.ComputeXPRate(600, nil))
        end)

        it("returns nil with zero or negative elapsed", function()
            assert.is_nil(Ledger.ComputeXPRate(600, 0))
            assert.is_nil(Ledger.ComputeXPRate(600, -5))
        end)
    end)

    describe("FormatXPRate", function()
        it("shows a dash for nil", function()
            assert.are.equal("-", Ledger.FormatXPRate(nil))
        end)

        it("formats a small number with no separator", function()
            assert.are.equal("450 xp/h", Ledger.FormatXPRate(450))
        end)

        it("adds a thousands separator", function()
            assert.are.equal("1,234 xp/h", Ledger.FormatXPRate(1234))
        end)

        it("adds separators for numbers in the millions", function()
            assert.are.equal("1,234,567 xp/h", Ledger.FormatXPRate(1234567))
        end)

        it("rounds to the nearest integer", function()
            assert.are.equal("1,235 xp/h", Ledger.FormatXPRate(1234.6))
        end)

        it("formats zero plainly", function()
            assert.are.equal("0 xp/h", Ledger.FormatXPRate(0))
        end)
    end)

    describe("ComputeHeadlineRates: session with no data", function()
        it("a fresh session with no events and enough elapsed time rates at 0, not a dash", function()
            local session = Ledger.NewSession(0, 10)
            local rates = Ledger.ComputeHeadlineRates(session, { session }, 600, 600, true)

            assert.are.equal(0, rates.sessionRate)
            assert.are.equal(0, rates.levelRate)
        end)

        it("a nil session (no active session at all) yields a session rate of 0, not an error", function()
            local rates = Ledger.ComputeHeadlineRates(nil, {}, 600, 600, true)

            assert.are.equal(0, rates.sessionRate)
            assert.are.equal(0, rates.levelRate)
        end)
    end)

    describe("ComputeHeadlineRates: session under a minute", function()
        it("both rates come back nil (dash) when elapsed is under the threshold", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 50, "kill")
            local rates = Ledger.ComputeHeadlineRates(session, { session }, 30, 30, true)

            assert.is_nil(rates.sessionRate)
            assert.is_nil(rates.levelRate)
        end)

        it("the session rate can be under threshold while the level rate isn't (different elapsed times)", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 50, "kill")
            local rates = Ledger.ComputeHeadlineRates(session, { session }, 30, 3600, true)

            assert.is_nil(rates.sessionRate)
            assert.are.equal(50, rates.levelRate)
        end)
    end)

    describe("ComputeHeadlineRates: both rates", function()
        it("computes the session rate from just the active session", function()
            local a = Ledger.NewSession(0, 10)
            Ledger.AddEvent(a, 0, 100, "kill")
            local b = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(b, 0, 50, "quest")

            -- session = b alone (1800s elapsed); level = a + b (3600s elapsed).
            local rates = Ledger.ComputeHeadlineRates(b, { a, b }, 1800, 3600, true)

            assert.are.equal(100, rates.sessionRate) -- 50xp/1800s*3600 = 100
            assert.are.equal(150, rates.levelRate)   -- (100+50)xp/3600s*3600 = 150
        end)
    end)

    describe("ComputeHeadlineRates: includeRested toggle", function()
        it("counts the rested bonus when includeRested is true", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)

            local rates = Ledger.ComputeHeadlineRates(session, { session }, 3600, 3600, true)

            assert.are.equal(172, rates.sessionRate)
            assert.are.equal(172, rates.levelRate)
        end)

        it("excludes the rested bonus when includeRested is false", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)

            local rates = Ledger.ComputeHeadlineRates(session, { session }, 3600, 3600, false)

            assert.are.equal(86, rates.sessionRate)
            assert.are.equal(86, rates.levelRate)
        end)
    end)

    describe("BuildRatePanelSections", function()
        it("returns one section with a session row and a level row", function()
            local sections = Ledger.BuildRatePanelSections({ sessionRate = 1234, levelRate = 500 })

            assert.are.equal(1, #sections)
            assert.are.equal("XP/hour", sections[1].title)
            assert.are.equal(2, #sections[1].rows)

            local sessionRow = sections[1].rows[1]
            assert.are.equal("This session", sessionRow.label)
            assert.are.equal("1,234 xp/h", sessionRow.value)
            assert.are.same(Ledger.RATE_HIGHLIGHT_COLOR, sessionRow.color)

            local levelRow = sections[1].rows[2]
            assert.are.equal("This level", levelRow.label)
            assert.are.equal("500 xp/h", levelRow.value)
            assert.are.same(Ledger.RATE_DEFAULT_COLOR, levelRow.color)
        end)

        it("shows dashes for nil rates instead of erroring", function()
            local sections = Ledger.BuildRatePanelSections({ sessionRate = nil, levelRate = nil })

            assert.are.equal("-", sections[1].rows[1].value)
            assert.are.equal("-", sections[1].rows[2].value)
        end)

        it("tolerates a nil rates table entirely", function()
            local sections = Ledger.BuildRatePanelSections(nil)

            assert.are.equal("-", sections[1].rows[1].value)
        end)
    end)
end)
