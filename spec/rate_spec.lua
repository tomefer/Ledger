describe("core/rate.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/rate.lua"))("Ledger", Ledger)
    end)

    describe("ComputeXPRate", function()
        it("its minimum is a number of SECONDS of denominator (60)", function()
            assert.are.equal(60, Ledger.RATE_MIN_SECONDS)
            assert.is_nil(Ledger.RATE_MIN_SAMPLES)
        end)

        it("computes xp per hour from xp and seconds", function()
            assert.are.equal(3600, Ledger.ComputeXPRate(600, 600))
        end)

        it("a zero numerator with enough seconds is a real rate of 0, not nil", function()
            assert.are.equal(0, Ledger.ComputeXPRate(0, 600))
        end)

        it("returns nil below the minimum threshold (too noisy)", function()
            assert.is_nil(Ledger.ComputeXPRate(50, 59))
        end)

        it("returns a real rate right at the threshold", function()
            assert.are.equal(3000, Ledger.ComputeXPRate(50, 60))
        end)

        it("returns nil with nil xp or nil seconds", function()
            assert.is_nil(Ledger.ComputeXPRate(nil, 600))
            assert.is_nil(Ledger.ComputeXPRate(600, nil))
        end)

        it("returns nil with zero or negative seconds", function()
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

    -- Sources of truth: "This session" = xp the addon recorded over
    -- time() - t0 (source A); "This level" = UnitXP over the level's
    -- played time (source B). Times below are absolute time().
    local function Rates(session, unitXP, ref, level, now, includeRested)
        return Ledger.ComputeHeadlineRates(session, unitXP, ref, level, now, includeRested)
    end

    describe("ComputeHeadlineRates: This session (recorded xp over time() - t0)", function()
        it("is the session's recorded xp over the seconds since t0", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 50, "kill")
            Ledger.AddEvent(session, 300, 100, "quest")

            -- 150 xp in 1800 s = 300 xp/h
            assert.are.equal(300, Rates(session, 0, nil, 10, 2800, true).sessionRate)
        end)

        it("an empty session with enough seconds rates at 0, not a dash", function()
            local session = Ledger.NewSession(1000, 10)

            assert.are.equal(0, Rates(session, 0, nil, 10, 1600, true).sessionRate)
        end)

        it("is a dash under 60 seconds, however much xp there is", function()
            local session = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(session, 0, 500, "kill")

            assert.is_nil(Rates(session, 0, nil, 10, 1059, true).sessionRate)
            assert.is_near(30000, Rates(session, 0, nil, 10, 1060, true).sessionRate, 1e-6)
        end)

        it("is a dash without a session at all", function()
            assert.is_nil(Rates(nil, 0, nil, 10, 5000, true).sessionRate)
        end)

        it("counts the rested bonus when includeRested is true, not when false", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)

            assert.are.equal(172, Rates(session, 0, nil, 10, 3600, true).sessionRate)
            assert.are.equal(86, Rates(session, 0, nil, 10, 3600, false).sessionRate)
        end)

        it("never reads the activity samples", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 100, "kill")
            session.ticks.total = 99999

            assert.are.equal(100, Rates(session, 0, nil, 10, 3600, true).sessionRate)
        end)
    end)

    describe("ComputeHeadlineRates: This level (UnitXP over the level's played time)", function()
        local ref = function() return Ledger.NewLevelPlayedRef(10, 1800, 5000) end

        it("is UnitXP over the reading plus the time elapsed since it arrived", function()
            -- 500 xp over 1800 + 1800 = 3600 s = 500 xp/h
            assert.are.equal(500, Rates(nil, 500, ref(), 10, 6800, true).levelRate)
        end)

        it("does not use the addon's recorded xp at all", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 9999, "kill")

            assert.are.equal(500, Rates(session, 500, ref(), 10, 6800, true).levelRate)
        end)

        it("ignores includeRested: UnitXP already has the rested bonus in it", function()
            local session = Ledger.NewSession(0, 10)
            Ledger.AddEvent(session, 0, 172, "kill", 86)

            assert.are.equal(500, Rates(session, 500, ref(), 10, 6800, true).levelRate)
            assert.are.equal(500, Rates(session, 500, ref(), 10, 6800, false).levelRate)
        end)

        it("is a dash until the first TIME_PLAYED_MSG reply has arrived", function()
            assert.is_nil(Rates(nil, 500, nil, 10, 6800, true).levelRate)
        end)

        it("is a dash while the denominator is under 60 seconds", function()
            local fresh = Ledger.NewLevelPlayedRef(10, 20, 5000)

            assert.is_nil(Rates(nil, 500, fresh, 10, 5039, true).levelRate) -- 59 s
            assert.is_near(30000, Rates(nil, 500, fresh, 10, 5040, true).levelRate, 1e-6) -- 60 s
        end)

        it("right after a ding is a dash, never millions of xp/h: leftover xp over a tiny denominator", function()
            -- Level 11 just started: UnitXP is the leftover 340 xp and the
            -- new level's reply says 3 s played.
            local afterDing = Ledger.NewLevelPlayedRef(11, 3, 9000)

            assert.is_nil(Rates(nil, 340, afterDing, 11, 9002, true).levelRate)
        end)

        it("between the ding and the new reply the old level's reading is not used", function()
            -- ref is level 10's (1800 s played), the player is already 11.
            assert.is_nil(Rates(nil, 340, ref(), 11, 9002, true).levelRate)
        end)

        it("a new reply replaces the previous reading, nothing is carried over", function()
            local first  = Ledger.NewLevelPlayedRef(10, 1800, 5000)
            local second = Ledger.NewLevelPlayedRef(10, 3600, 6000)

            assert.are.equal(1800 + 100, Rates(nil, 0, first,  10, 5100, true).levelPlayed)
            assert.are.equal(3600 + 100, Rates(nil, 0, second, 10, 6100, true).levelPlayed)
        end)

        it("a nil UnitXP is a dash", function()
            assert.is_nil(Rates(nil, nil, ref(), 10, 6800, true).levelRate)
        end)

        it("never reads the activity samples", function()
            local session = Ledger.NewSession(0, 10)
            session.ticks.total = 99999

            assert.are.equal(500, Rates(session, 500, ref(), 10, 6800, true).levelRate)
        end)
    end)

    describe("ComputeHeadlineRates: the denominators it returns", function()
        it("returns both played times next to the rates", function()
            local session = Ledger.NewSession(1000, 10)
            local rates = Rates(session, 0, Ledger.NewLevelPlayedRef(10, 2472, 5000), 10, 5090, true)

            assert.are.equal(4090, rates.sessionPlayed)
            assert.are.equal(2472 + 90, rates.levelPlayed)
        end)

        it("returns nil times when there is nothing to measure", function()
            local rates = Rates(nil, 0, nil, 10, 5090, true)

            assert.is_nil(rates.sessionPlayed)
            assert.is_nil(rates.levelPlayed)
        end)
    end)

    describe("BuildRatePanelSections", function()
        it("starts with the xp/hour section: a session row and a level row", function()
            local sections = Ledger.BuildRatePanelSections({ sessionRate = 1234, levelRate = 500 })

            assert.are.equal(2, #sections)
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

        it("tells under the rates that This level includes the rested xp", function()
            local section = Ledger.BuildRatePanelSections({})[1]

            assert.are.same({ Ledger.RATE_LEVEL_NOTE }, section.notes)
            assert.is_truthy(Ledger.RATE_LEVEL_NOTE:find("rested", 1, true))
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

        describe("played time section", function()
            local function timeSection(rates)
                local sections = Ledger.BuildRatePanelSections(rates)
                assert.are.equal(2, #sections)
                return sections[2]
            end

            it("comes after the rate section, with the session's and the level's time", function()
                local section = timeSection({ sessionRate = 1, levelRate = 2, sessionPlayed = 725, levelPlayed = 5025 })

                assert.are.equal("Played time", section.title)
                assert.are.equal("This session", section.rows[1].label)
                assert.are.equal("12m 05s", section.rows[1].value)
                assert.are.equal("This level", section.rows[2].label)
                assert.are.equal("1h 23m", section.rows[2].value)
            end)

            it("is always there, even with a nil rates table", function()
                local sections = Ledger.BuildRatePanelSections(nil)

                assert.are.equal(2, #sections)
                assert.are.equal("-", sections[2].rows[1].value)
                assert.are.equal("-", sections[2].rows[2].value)
            end)

            it("has no 'sampled by the addon' note: these are exact clocks", function()
                local section = timeSection({ sessionPlayed = 10, levelPlayed = 10 })

                assert.is_nil(section.notes)
            end)

            it("a level time not received yet shows a dash, never a zero", function()
                local section = timeSection({ sessionPlayed = 90, levelPlayed = nil })

                assert.are.equal("1m 30s", section.rows[1].value)
                assert.are.equal("-", section.rows[2].value)
            end)

            it("is independent of the activity samples", function()
                local section = timeSection({ sessionSamples = 9999, levelSamples = 9999 })

                assert.are.equal("-", section.rows[1].value)
                assert.are.equal("-", section.rows[2].value)
            end)
        end)
    end)

    describe("SessionPlayedSeconds", function()
        it("is now - t0, both absolute time()", function()
            local session = Ledger.NewSession(1000, 10)

            assert.are.equal(725, Ledger.SessionPlayedSeconds(session, 1725))
        end)

        it("is 0 at the very start and never negative", function()
            local session = Ledger.NewSession(1000, 10)

            assert.are.equal(0, Ledger.SessionPlayedSeconds(session, 1000))
            assert.are.equal(0, Ledger.SessionPlayedSeconds(session, 990))
        end)

        it("is nil (a dash) without a session or without a t0", function()
            assert.is_nil(Ledger.SessionPlayedSeconds(nil, 1000))
            assert.is_nil(Ledger.SessionPlayedSeconds({}, 1000))
        end)

        it("does not read the activity samples", function()
            local session = Ledger.NewSession(1000, 10)
            session.ticks.total = 5

            assert.are.equal(100, Ledger.SessionPlayedSeconds(session, 1100))
        end)
    end)

    describe("level played time (in-memory /played reference)", function()
        it("NewLevelPlayedRef keeps level, seconds and the reception time", function()
            assert.are.same({ level = 12, seconds = 2472, receivedAt = 5000 },
                Ledger.NewLevelPlayedRef(12, 2472, 5000))
        end)

        it("NewLevelPlayedRef gives nil for a reading that is not a number", function()
            assert.is_nil(Ledger.NewLevelPlayedRef(12, nil, 5000))
            assert.is_nil(Ledger.NewLevelPlayedRef(12, "x", 5000))
        end)

        it("is the reading plus the time elapsed since it arrived", function()
            local ref = Ledger.NewLevelPlayedRef(12, 2472, 5000)

            assert.are.equal(2472, Ledger.LevelPlayedSeconds(ref, 12, 5000))
            assert.are.equal(2472 + 90, Ledger.LevelPlayedSeconds(ref, 12, 5090))
        end)

        it("is nil (a dash, not a zero) until a reply has arrived", function()
            assert.is_nil(Ledger.LevelPlayedSeconds(nil, 12, 5000))
        end)

        it("a new reply REPLACES the reference instead of adding to it", function()
            local first = Ledger.NewLevelPlayedRef(12, 2472, 5000)
            -- e.g. after a /reload: the server's new value already includes
            -- everything before, so nothing of `first` may be carried over.
            local second = Ledger.NewLevelPlayedRef(12, 2600, 5100)

            assert.are.equal(2472 + 50, Ledger.LevelPlayedSeconds(first, 12, 5050))
            assert.are.equal(2600 + 50, Ledger.LevelPlayedSeconds(second, 12, 5150))
        end)

        it("a reading of another level is not shown as this level's (counter resets on a ding)", function()
            local ref = Ledger.NewLevelPlayedRef(12, 2472, 5000)

            assert.is_nil(Ledger.LevelPlayedSeconds(ref, 13, 5010))
        end)

        it("elapsed time never goes negative", function()
            local ref = Ledger.NewLevelPlayedRef(12, 2472, 5000)

            assert.are.equal(2472, Ledger.LevelPlayedSeconds(ref, 12, 4990))
        end)
    end)

    describe("FormatDuration", function()
        it("seconds under a minute", function()
            assert.are.equal("0s", Ledger.FormatDuration(0))
            assert.are.equal("45s", Ledger.FormatDuration(45))
        end)

        it("minutes and zero-padded seconds under an hour", function()
            assert.are.equal("1m 00s", Ledger.FormatDuration(60))
            assert.are.equal("12m 05s", Ledger.FormatDuration(725))
            assert.are.equal("59m 59s", Ledger.FormatDuration(3599))
        end)

        it("hours and zero-padded minutes from an hour up (seconds dropped)", function()
            assert.are.equal("1h 00m", Ledger.FormatDuration(3600))
            assert.are.equal("1h 23m", Ledger.FormatDuration(5025))
            assert.are.equal("100h 00m", Ledger.FormatDuration(360000))
        end)

        it("nil is a dash, negative clamps to zero", function()
            assert.are.equal("-", Ledger.FormatDuration(nil))
            assert.are.equal("0s", Ledger.FormatDuration(-5))
        end)
    end)
end)
