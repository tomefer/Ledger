describe("core/check.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/check.lua"))("Ledger", Ledger)
    end)

    -- A session of `level` with one kill event per amount in `amounts`.
    local function SessionWith(level, amounts, initialXP, reached)
        local s = Ledger.NewSession(0, level)
        s.initialXP = initialXP
        s.reached = reached
        for i, xp in ipairs(amounts) do
            Ledger.AddEvent(s, i * 10, xp, "kill")
        end
        return s
    end

    -- A closed-level entry as Ledger.CloseLevel would leave it.
    local function ClosedLevel(level, recorded, opts)
        opts = opts or {}
        return {
            level       = level,
            reached     = opts.reached or 0,
            initialXP   = opts.initialXP or 0,
            xpRequired  = opts.xpRequired,
            bySource    = { kill = recorded },
        }
    end

    local function Find(result, needle, status)
        for _, line in ipairs(result.lines) do
            if line.text:find(needle, 1, true) and (status == nil or line.status == status) then
                return line
            end
        end
        return nil
    end

    local function CountStatus(result, status)
        local n = 0
        for _, line in ipairs(result.lines) do
            if line.status == status then n = n + 1 end
        end
        return n
    end

    describe("no discrepancy", function()
        it("reports ALL OK when recorded matches real", function()
            local charDB = { sessions = { SessionWith(12, { 100, 50 }) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 150 })

            assert.are.equal(0, result.discrepancies)
            assert.are.equal("title", result.lines[1].status)
            assert.are.equal("Ledger check: ALL OK", result.lines[1].text)
            assert.are.equal(0, CountStatus(result, "bad"))
            assert.is_not_nil(Find(result, "Difference (recorded - real): +0", "ok"))
        end)

        it("sums the xp of ALL the level's sessions, not just the active one", function()
            local charDB = {
                sessions = { SessionWith(12, { 100 }), SessionWith(12, { 40, 10 }) },
                levels = {},
            }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 150 })

            assert.are.equal(0, result.discrepancies)
            assert.is_not_nil(Find(result, "Recorded xp (sum of the level's sessions): 150"))
            assert.is_not_nil(Find(result, "2 session(s), 3 event(s)"))
        end)
    end)

    describe("surplus (recorded > real)", function()
        it("flags it as a discrepancy and explains it as double counting", function()
            local charDB = { sessions = { SessionWith(12, { 100, 100 }) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 150 })

            assert.are.equal(1, result.discrepancies)
            assert.are.equal("Ledger check: 1 DISCREPANCY FOUND", result.lines[1].text)
            local line = Find(result, "Difference (recorded - real): +50", "bad")
            assert.is_not_nil(line)
            assert.is_not_nil(line.text:find("POSITIVE (recorded > real): double counting", 1, true))
        end)
    end)

    describe("shortfall (recorded < real)", function()
        it("flags it as a discrepancy and explains it as lost events", function()
            local charDB = { sessions = { SessionWith(12, { 100 }) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 150 })

            assert.are.equal(1, result.discrepancies)
            local line = Find(result, "Difference (recorded - real): -50", "bad")
            assert.is_not_nil(line)
            assert.is_not_nil(line.text:find("NEGATIVE (recorded < real): lost events", 1, true))
        end)
    end)

    describe("no closed levels", function()
        it("says so in the closed-levels section and stays OK", function()
            local charDB = { sessions = { SessionWith(3, { 10 }) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 3, xp = 10 })

            assert.are.equal(0, result.discrepancies)
            local count = 0
            for _, line in ipairs(result.lines) do
                if line.text == "(no closed levels yet)" then count = count + 1 end
            end
            assert.are.equal(1, count)
        end)

        it("copes with no active session at all", function()
            local result = Ledger.BuildCheck({ sessions = {}, levels = {} }, { level = 3, xp = 0 })
            assert.are.equal(0, result.discrepancies)
            assert.is_not_nil(Find(result, "(no xp recorded on this level yet)"))
        end)
    end)

    describe("initial gray segment", function()
        it("discounts it from the difference the verdict uses", function()
            -- Adopted mid-level with 60xp already: 90 recorded + 60 = 150 real.
            local charDB = { sessions = { SessionWith(12, { 90 }, 60) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 150 })

            assert.are.equal(0, result.discrepancies)
            assert.is_not_nil(Find(result, "Initial gray segment (xp before tracking started): 60"))
            -- the raw difference is informational, never a discrepancy
            assert.is_not_nil(Find(result, "Difference without discounting it: -60", "info"))
            assert.is_not_nil(Find(result,
                "Difference discounting the initial segment (recorded + initial - real): +0", "ok"))
        end)

        it("still flags a real discrepancy hidden behind the segment", function()
            -- 90 + 60 = 150 expected, but real is 200 -> 50 lost.
            local charDB = { sessions = { SessionWith(12, { 90 }, 60) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 200 })

            assert.are.equal(1, result.discrepancies)
            local line = Find(result, "recorded + initial - real): -50", "bad")
            assert.is_not_nil(line)
            assert.is_not_nil(line.text:find("lost events", 1, true))
        end)

        it("omits the segment lines entirely when there is none", function()
            local charDB = { sessions = { SessionWith(12, { 100 }) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 100 })
            assert.is_nil(Find(result, "Initial gray segment"))
        end)
    end)

    describe("breakdown by source", function()
        it("lists each source in stable order with its percentage", function()
            local s = Ledger.NewSession(0, 5)
            Ledger.AddEvent(s, 0, 75, "kill")
            Ledger.AddEvent(s, 10, 25, "quest")
            local result = Ledger.BuildCheck({ sessions = { s }, levels = {} }, { level = 5, xp = 100 })

            local kill  = Find(result, "kill: 75 xp (75.0%)")
            local quest = Find(result, "quest: 25 xp (25.0%)")
            assert.is_not_nil(kill)
            assert.is_not_nil(quest)
            assert.are.equal(0, result.discrepancies)
        end)

        it("flags unknown events as a discrepancy", function()
            local s = Ledger.NewSession(0, 5)
            Ledger.AddEvent(s, 0, 80, "kill")
            Ledger.AddEvent(s, 10, 20, "unknown")
            local result = Ledger.BuildCheck({ sessions = { s }, levels = {} }, { level = 5, xp = 100 })

            assert.are.equal(1, result.discrepancies)
            local line = Find(result, "unknown: 20 xp (20.0%)", "bad")
            assert.is_not_nil(line)
            assert.is_not_nil(line.text:find("could not be paired", 1, true))
        end)
    end)

    describe("session/player level mismatch", function()
        it("is flagged", function()
            local charDB = { sessions = { SessionWith(11, { 100 }) }, levels = {} }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 100 })

            assert.are.equal(1, result.discrepancies)
            assert.is_not_nil(Find(result, "a level change was not tracked", "bad"))
        end)
    end)

    describe("closed levels: xp vs required", function()
        it("marks a level that adds up exactly as OK", function()
            local charDB = {
                sessions = { SessionWith(11, { 10 }) },
                levels = { [10] = ClosedLevel(10, 1000, { xpRequired = 1000 }) },
            }
            local result = Ledger.BuildCheck(charDB, { level = 11, xp = 10 })

            assert.are.equal(0, result.discrepancies)
            assert.is_not_nil(Find(result, "Level 10: recorded 1000 vs required 1000", "ok"))
        end)

        it("flags a surplus and a shortfall with their signs", function()
            local charDB = {
                sessions = { SessionWith(12, { 10 }) },
                levels = {
                    [10] = ClosedLevel(10, 1040, { xpRequired = 1000 }),
                    [11] = ClosedLevel(11, 970,  { xpRequired = 1000 }),
                },
            }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 10 })

            assert.are.equal(2, result.discrepancies)
            local surplus = Find(result, "Level 10: recorded 1040 vs required 1000: +40", "bad")
            assert.is_not_nil(surplus)
            assert.is_not_nil(surplus.text:find("double counting", 1, true))
            local shortfall = Find(result, "Level 11: recorded 970 vs required 1000: -30", "bad")
            assert.is_not_nil(shortfall)
            assert.is_not_nil(shortfall.text:find("lost events", 1, true))
        end)

        it("counts the level's initial xp toward what it required", function()
            local charDB = {
                sessions = { SessionWith(11, { 10 }) },
                levels = { [10] = ClosedLevel(10, 700, { xpRequired = 1000, initialXP = 300 }) },
            }
            local result = Ledger.BuildCheck(charDB, { level = 11, xp = 10 })

            assert.are.equal(0, result.discrepancies)
            assert.is_not_nil(Find(result, "recorded 700 + initial 300 vs required 1000", "ok"))
        end)

        it("does not depend on the includeRested toggle in force when it closed", function()
            -- totalXP would read 900 with rested excluded; bySource is the
            -- total xp as-is, which is what has to match the requirement.
            local entry = ClosedLevel(10, 1000, { xpRequired = 1000 })
            entry.totalXP, entry.totalRested = 900, 100
            local charDB = { sessions = { SessionWith(11, { 10 }) }, levels = { [10] = entry } }

            assert.are.equal(0, Ledger.BuildCheck(charDB, { level = 11, xp = 10 }).discrepancies)
        end)

        it("skips (does not fail) a level closed before xpRequired was stored", function()
            local charDB = {
                sessions = { SessionWith(11, { 10 }) },
                levels = { [10] = ClosedLevel(10, 900) },
            }
            local result = Ledger.BuildCheck(charDB, { level = 11, xp = 10 })

            assert.are.equal(0, result.discrepancies)
            assert.is_not_nil(Find(result, "Level 10: recorded 900, but the required xp was not stored", "skip"))
        end)

        it("lists levels in ascending order regardless of insertion", function()
            local charDB = {
                sessions = { SessionWith(13, { 10 }) },
                levels = {
                    [12] = ClosedLevel(12, 100, { xpRequired = 100 }),
                    [10] = ClosedLevel(10, 100, { xpRequired = 100 }),
                    [11] = ClosedLevel(11, 100, { xpRequired = 100 }),
                },
            }
            local text = Ledger.FormatCheck(Ledger.BuildCheck(charDB, { level = 13, xp = 10 }))
            local p10 = text:find("Level 10: recorded", 1, true)
            local p11 = text:find("Level 11: recorded", 1, true)
            local p12 = text:find("Level 12: recorded", 1, true)
            assert.is_true(p10 < p11 and p11 < p12)
        end)
    end)

    describe("time section: information only, never a discrepancy", function()
        local function CharDB(opts)
            opts = opts or {}
            local session = SessionWith(12, { 100 })
            session.ticks = opts.sessionTicks or { combat = 2, nonCombat = 6, travel = 2, dead = 0, total = 10 }
            return {
                sessions = { session },
                levels = {},
                levelTicks = opts.levelTicks or { combat = 20, nonCombat = 60, travel = 15, dead = 5, total = 100 },
            }
        end

        it("shows the level and session activity as percentages of the samples", function()
            local result = Ledger.BuildCheck(CharDB(), { level = 12, xp = 100 })

            assert.is_not_nil(Find(result,
                "Level activity, % of samples: Combat 20.0% | Non-combat 60.0% | Travel 15.0% | Dead 5.0%", "info"))
            assert.is_not_nil(Find(result,
                "Session activity, % of samples: Combat 20.0% | Non-combat 60.0% | Travel 20.0% | Dead 0.0%", "info"))
        end)

        it("without any samples it says so", function()
            local result = Ledger.BuildCheck(CharDB({ levelTicks = Ledger.NewTicks() }), { level = 12, xp = 100 })

            assert.is_not_nil(Find(result, "Level activity, % of samples: no samples yet", "info"))
        end)

        it("says nothing about /played: it is another source and is never persisted", function()
            local result = Ledger.BuildCheck(CharDB(), { level = 12, xp = 100 })

            assert.is_nil(Find(result, "/played"))
            assert.are.equal(0, result.discrepancies)
        end)

        it("copes with data that has no counters at all", function()
            local result = Ledger.BuildCheck({ sessions = {}, levels = {} }, { level = 3, xp = 0 })

            assert.is_not_nil(Find(result, "Level activity, % of samples: no samples yet"))
            assert.are.equal(0, result.discrepancies)
        end)

        it("has no time invariants: nothing about closed levels' time is checked or shown", function()
            local charDB = CharDB()
            charDB.levels[10] = ClosedLevel(10, 100, { xpRequired = 100 })
            charDB.levels[10].ticks = { combat = 1, nonCombat = 0, travel = 0, dead = 0, total = 1 }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 100 })
            local text = Ledger.FormatCheck(result)

            assert.is_nil(text:find("between dings", 1, true))
            assert.is_nil(text:find("totalPlayed", 1, true))
            assert.is_nil(text:find("logged out", 1, true))
            assert.is_nil(text:find("sampled in game", 1, true))
        end)
    end)

    describe("global verdict", function()
        it("counts every discrepancy and pluralizes", function()
            local charDB = {
                sessions = { SessionWith(12, { 100 }) },
                levels = { [11] = ClosedLevel(11, 900, { xpRequired = 1000 }) },
            }
            local result = Ledger.BuildCheck(charDB, { level = 12, xp = 150 })

            assert.are.equal(2, result.discrepancies)
            assert.are.equal("Ledger check: 2 DISCREPANCIES FOUND", result.lines[1].text)
        end)
    end)

    describe("FormatCheck", function()
        it("puts the verdict first and marks discrepancies with >>> [!!]", function()
            local charDB = { sessions = { SessionWith(12, { 100 }) }, levels = {} }
            local text = Ledger.FormatCheck(Ledger.BuildCheck(charDB, { level = 12, xp = 150 }))

            assert.are.equal("Ledger check: 1 DISCREPANCY FOUND", text:match("^[^\n]+"))
            assert.is_not_nil(text:find(">>> [!!] Difference (recorded - real): -50", 1, true))
        end)

        it("marks passing lines [OK] and unverifiable ones [??]", function()
            local charDB = {
                sessions = { SessionWith(11, { 10 }) },
                levels = { [10] = ClosedLevel(10, 900) },
            }
            local text = Ledger.FormatCheck(Ledger.BuildCheck(charDB, { level = 11, xp = 10 }))

            assert.is_not_nil(text:find("    [OK] Difference (recorded - real): +0", 1, true))
            assert.is_not_nil(text:find("    [??] Level 10:", 1, true))
            assert.is_nil(text:find("[!!]", 1, true))
        end)

        it("separates sections with a blank line and a heading", function()
            local charDB = { sessions = { SessionWith(12, { 100 }) }, levels = {} }
            local text = Ledger.FormatCheck(Ledger.BuildCheck(charDB, { level = 12, xp = 100 }))

            assert.is_not_nil(text:find("\n\n== Current level ==\n", 1, true))
            assert.is_not_nil(text:find("\n\n== Closed levels: recorded xp vs required ==\n", 1, true))
        end)
    end)
end)
