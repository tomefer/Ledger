-- dkjson is a test-only dependency (installed via luarocks in this
-- spec environment) used to verify that the hand-written JSON encoder
-- in core/export.lua produces real, parseable JSON. The addon itself
-- never requires it: no JSON library exists in the WoW sandbox, so
-- core/export.lua's encoder is entirely hand-written.
local dkjson = require("dkjson")

describe("core/export.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/export.lua"))("Ledger", Ledger)
    end)

    describe("JSONEscapeString", function()
        it("escapes backslash and double quote", function()
            assert.are.equal('a\\\\b\\"c', Ledger.JSONEscapeString('a\\b"c'))
        end)

        it("escapes newline, carriage return and tab", function()
            assert.are.equal("a\\nb\\rc\\td", Ledger.JSONEscapeString("a\nb\rc\td"))
        end)

        it("escapes other control characters as \\u00XX", function()
            assert.are.equal("a\\u0001b", Ledger.JSONEscapeString("a\1b"))
            assert.are.equal("a\\u001fb", Ledger.JSONEscapeString("a\31b"))
        end)

        it("leaves plain text untouched", function()
            assert.are.equal("Young Goretusk", Ledger.JSONEscapeString("Young Goretusk"))
        end)

        it("coerces non-string values with tostring", function()
            assert.are.equal("5", Ledger.JSONEscapeString(5))
        end)
    end)

    describe("JSONString", function()
        it("wraps the escaped text in double quotes", function()
            assert.are.equal('"a\\"b"', Ledger.JSONString('a"b'))
        end)
    end)

    describe("JSONNumber", function()
        it("formats integers without a trailing .0", function()
            assert.are.equal("50", Ledger.JSONNumber(50))
            assert.are.equal("0", Ledger.JSONNumber(0))
        end)

        it("formats negative and fractional numbers", function()
            assert.are.equal("-30", Ledger.JSONNumber(-30))
            assert.are.equal("1.5", Ledger.JSONNumber(1.5))
        end)
    end)

    describe("CSVEscapeField", function()
        it("leaves a plain field untouched", function()
            assert.are.equal("kill", Ledger.CSVEscapeField("kill"))
            assert.are.equal("50", Ledger.CSVEscapeField(50))
        end)

        it("quotes a field containing a comma", function()
            assert.are.equal('"a,b"', Ledger.CSVEscapeField("a,b"))
        end)

        it("quotes a field containing a newline", function()
            assert.are.equal('"a\nb"', Ledger.CSVEscapeField("a\nb"))
        end)

        it("quotes a field containing a quote and doubles it", function()
            assert.are.equal('"a""b"', Ledger.CSVEscapeField('a"b'))
        end)
    end)

    describe("CSVRow", function()
        it("joins escaped fields with commas", function()
            assert.are.equal('kill,50,"a,b"', Ledger.CSVRow({ "kill", 50, "a,b" }))
        end)

        it("with an empty field list returns an empty string", function()
            assert.are.equal("", Ledger.CSVRow({}))
        end)
    end)

    describe("ExportJSON: empty charDB", function()
        it("nil charDB produces valid JSON with empty levels and sessions", function()
            local text = Ledger.ExportJSON(nil)
            local decoded, _, err = dkjson.decode(text)

            assert.is_nil(err)
            assert.are.same({}, decoded.levels)
            assert.are.same({}, decoded.sessions)
            assert.are.equal(0, decoded.totalEventCount)
            assert.is_true(decoded.includeEvents)
        end)

        it("empty table charDB produces the same empty result", function()
            local text = Ledger.ExportJSON({})
            local decoded, _, err = dkjson.decode(text)

            assert.is_nil(err)
            assert.are.same({}, decoded.levels)
            assert.are.same({}, decoded.sessions)
        end)
    end)

    describe("ExportCSV: empty charDB", function()
        it("nil charDB produces just the three section headers, no data rows", function()
            local text = Ledger.ExportCSV(nil)

            assert.is_not_nil(text:find("# levels", 1, true))
            assert.is_not_nil(text:find("# sessions", 1, true))
            assert.is_not_nil(text:find("# events", 1, true))
            assert.is_not_nil(text:find(
                "level,reached,totalXP,totalRested,deaths,ticks_combat,ticks_nonCombat,ticks_travel,ticks_dead,ticks_total",
                1, true))
        end)
    end)

    describe("activity ticks are exported as the raw counters, never as percentages", function()
        local function Charlie()
            local session = Ledger.NewSession(0, 7)
            session.ticks = { combat = 30, nonCombat = 50, travel = 15, dead = 5, total = 100 }
            return {
                version = 9,
                sessions = { session },
                levels = {
                    [6] = { level = 6, reached = 100, totalXP = 500, totalRested = 0, deaths = 0,
                            bySource = { kill = 500 }, curve = { 500 },
                            ticks = { combat = 40, nonCombat = 30, travel = 20, dead = 10, total = 100 } },
                },
            }
        end

        it("JSON: each level and session carries its counters, total included", function()
            local decoded, _, err = dkjson.decode(Ledger.ExportJSON(Charlie()))

            assert.is_nil(err)
            assert.are.same({ combat = 40, nonCombat = 30, travel = 20, dead = 10, total = 100 },
                decoded.levels[1].ticks)
            assert.are.same({ combat = 30, nonCombat = 50, travel = 15, dead = 5, total = 100 },
                decoded.sessions[1].ticks)
        end)

        it("JSON: none of the removed time fields is there", function()
            local decoded = dkjson.decode(Ledger.ExportJSON(Charlie()))

            assert.is_nil(decoded.lastKnownTotalTimePlayed)
            assert.is_nil(decoded.levelStartTotalPlayed)
            assert.is_nil(decoded.levels[1].totalPlayed)
            assert.is_nil(decoded.levels[1].timeUnreliable)
            assert.is_nil(decoded.levels[1].buckets)
            assert.is_nil(decoded.sessions[1].buckets)
        end)

        it("CSV: the counters are columns, on levels and on sessions", function()
            local text = Ledger.ExportCSV(Charlie())

            assert.is_not_nil(text:find("6,100,500,0,0,40,30,20,10,100", 1, true))
            assert.is_not_nil(text:find("ticks_combat,ticks_nonCombat,ticks_travel,ticks_dead,ticks_total", 1, true))
            assert.is_not_nil(text:find(",30,50,15,5,100", 1, true))
        end)

        it("a level or session without counters exports zeros instead of failing", function()
            local decoded, _, err = dkjson.decode(Ledger.ExportJSON({
                sessions = { { t0 = 1, level = 3, e = {} } },
                levels = { [2] = { level = 2, bySource = {}, curve = {} } },
            }))

            assert.is_nil(err)
            assert.are.equal(0, decoded.levels[1].ticks.total)
            assert.are.equal(0, decoded.sessions[1].ticks.total)
        end)
    end)

    describe("nothing from /played is exported (it is never persisted)", function()
        it("JSON has no played key, even if a stale one is in the data", function()
            local decoded = dkjson.decode(Ledger.ExportJSON({
                sessions = {}, levels = {}, played = { level = 12, seconds = 2472, samples = 2450 } }))

            assert.is_nil(decoded.played)
        end)
    end)

    describe("ExportJSON: full charDB is valid, round-trippable JSON", function()
        it("decodes back to the expected structure, including escaped special characters", function()
            local session = Ledger.NewSession(1000, 12, 'farm "solo"', false)
            Ledger.AddEvent(session, 0, 172, "kill", 86)
            Ledger.AddEvent(session, 300, 20, "quest")
            session.reached = 1000
            session.initialXP = 50

            local charDB = {
                version = 5,
                sessions = { session },
                levels = {
                    [11] = {
                        level = 11, reached = 900, totalXP = 5000, totalRested = 200,
                        deaths = 2, bySource = { kill = 4000, quest = 1000 }, curve = { 100, 200, 50 },
                        ticks = { combat = 1000, nonCombat = 500, travel = 2000, dead = 100, total = 3600 },
                    },
                },
            }

            local text = Ledger.ExportJSON(charDB)
            local decoded, _, err = dkjson.decode(text)

            assert.is_nil(err)
            assert.are.equal(5, decoded.version)
            assert.is_true(decoded.includeEvents)
            assert.are.equal(2, decoded.totalEventCount)

            assert.are.equal(1, #decoded.levels)
            assert.are.equal(11, decoded.levels[1].level)
            assert.are.equal(4000, decoded.levels[1].bySource.kill)
            assert.are.same({ 100, 200, 50 }, decoded.levels[1].curve)
            assert.are.equal(2000, decoded.levels[1].ticks.travel)

            assert.are.equal(1, #decoded.sessions)
            local s = decoded.sessions[1]
            assert.are.equal(12, s.level)
            -- The double quotes inside mode must survive the JSON round trip intact.
            assert.are.equal('farm "solo"', s.mode)
            assert.are.equal(2, s.eventCount)
            assert.are.equal(192, s.totalXP)
            assert.are.equal(86, s.totalRested)
            assert.are.equal(2, #s.events)
            assert.are.equal("kill", s.events[1].src)
            assert.are.equal(86, s.events[1].rested)
            assert.are.equal("quest", s.events[2].src)
        end)
    end)

    describe("size threshold: falls back to aggregates when there are too many events", function()
        it("drops the events array but keeps session totals when over the threshold", function()
            Ledger.EXPORT_MAX_EVENTS = 2
            local session = Ledger.NewSession(0, 5)
            Ledger.AddEvent(session, 0, 10, "kill")
            Ledger.AddEvent(session, 10, 20, "kill")
            Ledger.AddEvent(session, 20, 30, "kill")
            local charDB = { sessions = { session } }

            local text = Ledger.ExportJSON(charDB)
            local decoded = dkjson.decode(text)

            assert.is_false(decoded.includeEvents)
            assert.are.equal(3, decoded.totalEventCount)
            assert.is_nil(decoded.sessions[1].events)
            assert.are.equal(60, decoded.sessions[1].totalXP)
            assert.are.equal(3, decoded.sessions[1].eventCount)
        end)

        it("CSV omits the events section but keeps the sessions section's totals", function()
            Ledger.EXPORT_MAX_EVENTS = 2
            local session = Ledger.NewSession(0, 5)
            Ledger.AddEvent(session, 0, 10, "kill")
            Ledger.AddEvent(session, 10, 20, "kill")
            Ledger.AddEvent(session, 20, 30, "kill")
            local charDB = { sessions = { session } }

            local text = Ledger.ExportCSV(charDB)

            assert.is_not_nil(text:find("events omitted", 1, true))
            assert.is_not_nil(text:find("60", 1, true)) -- session's totalXP still present
        end)

        it("stays under the threshold: keeps the full events section", function()
            Ledger.EXPORT_MAX_EVENTS = 1000
            local session = Ledger.NewSession(0, 5)
            Ledger.AddEvent(session, 0, 10, "kill")
            local charDB = { sessions = { session } }

            local text = Ledger.ExportCSV(charDB)

            assert.is_nil(text:find("events omitted", 1, true))
            assert.is_not_nil(text:find("# events", 1, true))
        end)
    end)
end)
