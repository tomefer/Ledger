describe("core/ticks.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
    end)

    -- The five counters of a set, as a plain table for comparisons.
    local function Snapshot(t)
        return { combat = t.combat, nonCombat = t.nonCombat, travel = t.travel, dead = t.dead, total = t.total }
    end

    describe("NewTicks", function()
        it("has one counter per activity plus the total, all at zero", function()
            assert.are.same({ combat = 0, nonCombat = 0, travel = 0, dead = 0, total = 0 }, Ledger.NewTicks())
        end)

        it("returns a distinct table every time", function()
            assert.are_not.equal(Ledger.NewTicks(), Ledger.NewTicks())
        end)

        it("a new session carries its own set", function()
            local a = Ledger.NewSession(0, 5)
            local b = Ledger.NewSession(0, 5)

            assert.are.same(Ledger.NewTicks(), a.ticks)
            assert.are_not.equal(a.ticks, b.ticks)
        end)

        it("stores no per-tick array and no state series anywhere in a session", function()
            local session = Ledger.NewSession(0, 5)

            assert.is_nil(session.stateSeries)
            assert.is_nil(session.buckets)
            for _, value in pairs(session.ticks) do
                assert.are.equal("number", type(value))
            end
        end)
    end)

    describe("ClassifyActivity: mutually exclusive, by priority", function()
        it("nothing set is nonCombat", function()
            assert.are.equal("nonCombat", Ledger.ClassifyActivity({}))
        end)

        it("moving alone is travel", function()
            assert.are.equal("travel", Ledger.ClassifyActivity({ moving = true }))
        end)

        it("being on a taxi is travel", function()
            assert.are.equal("travel", Ledger.ClassifyActivity({ taxi = true }))
        end)

        it("combat alone is combat", function()
            assert.are.equal("combat", Ledger.ClassifyActivity({ combat = true }))
        end)

        it("dead alone is dead", function()
            assert.are.equal("dead", Ledger.ClassifyActivity({ dead = true }))
        end)

        it("combat beats moving", function()
            assert.are.equal("combat", Ledger.ClassifyActivity({ combat = true, moving = true }))
        end)

        it("dead beats combat (a corpse is not fighting)", function()
            assert.are.equal("dead", Ledger.ClassifyActivity({ dead = true, combat = true }))
        end)

        it("dead beats everything at once", function()
            assert.are.equal("dead", Ledger.ClassifyActivity({ dead = true, combat = true, moving = true, taxi = true }))
        end)

        it("combat beats a taxi", function()
            assert.are.equal("combat", Ledger.ClassifyActivity({ combat = true, taxi = true }))
        end)

        it("every combination of the four flags gives exactly one known activity", function()
            local known = { combat = true, nonCombat = true, travel = true, dead = true }
            for mask = 0, 15 do
                local state = {
                    dead   = mask % 2 == 1,
                    combat = math.floor(mask / 2) % 2 == 1,
                    moving = math.floor(mask / 4) % 2 == 1,
                    taxi   = math.floor(mask / 8) % 2 == 1,
                }
                local key = Ledger.ClassifyActivity(state)
                assert.is_true(known[key], "mask " .. mask .. " gave " .. tostring(key))
            end
        end)
    end)

    describe("CountTick", function()
        it("increments exactly the chosen counter and the total, nothing else", function()
            local ticks = Ledger.NewTicks()

            Ledger.CountTick(ticks, "travel")

            assert.are.same({ combat = 0, nonCombat = 0, travel = 1, dead = 0, total = 1 }, Snapshot(ticks))
        end)

        it("keeps the total equal to the sum of the four counters through many ticks", function()
            local ticks = Ledger.NewTicks()
            local sequence = { "combat", "combat", "nonCombat", "travel", "dead", "combat", "nonCombat", "nonCombat" }

            for _, key in ipairs(sequence) do
                Ledger.CountTick(ticks, key)
                assert.are.equal(ticks.combat + ticks.nonCombat + ticks.travel + ticks.dead, ticks.total)
            end

            assert.are.same({ combat = 3, nonCombat = 3, travel = 1, dead = 1, total = 8 }, Snapshot(ticks))
        end)

        it("refuses an unknown activity instead of silently breaking the total", function()
            local ticks = Ledger.NewTicks()

            assert.has_error(function() Ledger.CountTick(ticks, "sleeping") end)
            assert.has_error(function() Ledger.CountTick(ticks, "total") end)
            assert.are.same(Ledger.NewTicks(), ticks)
        end)
    end)

    describe("RecordActivityTick: the whole per-second step", function()
        it("classifies once and counts that key on BOTH the session and the level, live", function()
            local session = Ledger.NewSession(0, 5)
            local levelTicks = Ledger.NewTicks()

            local key = Ledger.RecordActivityTick(session, levelTicks, { combat = true, moving = true })

            assert.are.equal("combat", key)
            assert.are.same({ combat = 1, nonCombat = 0, travel = 0, dead = 0, total = 1 }, Snapshot(session.ticks))
            assert.are.same(Snapshot(session.ticks), Snapshot(levelTicks))
        end)

        it("one tick moves exactly one counter (plus total) in each table", function()
            local session = Ledger.NewSession(0, 5)
            local levelTicks = Ledger.NewTicks()

            Ledger.RecordActivityTick(session, levelTicks, { moving = true })

            for _, t in ipairs({ session.ticks, levelTicks }) do
                local moved = 0
                for _, k in ipairs(Ledger.TICK_KEYS) do moved = moved + t[k] end
                assert.are.equal(1, moved)
                assert.are.equal(1, t.total)
            end
        end)

        it("the level's counters keep growing across sessions while each session has its own", function()
            local first = Ledger.NewSession(0, 5)
            local second = Ledger.NewSession(0, 5)
            local levelTicks = Ledger.NewTicks()

            for _ = 1, 3 do Ledger.RecordActivityTick(first, levelTicks, { combat = true }) end
            for _ = 1, 2 do Ledger.RecordActivityTick(second, levelTicks, {}) end

            assert.are.equal(3, first.ticks.total)
            assert.are.equal(2, second.ticks.total)
            assert.are.equal(5, levelTicks.total)
            assert.are.equal(3, levelTicks.combat)
            assert.are.equal(2, levelTicks.nonCombat)
        end)

        it("the level total is always the sum of its sessions' totals", function()
            local sessions = { Ledger.NewSession(0, 5), Ledger.NewSession(0, 5) }
            local levelTicks = Ledger.NewTicks()
            local states = { {}, { combat = true }, { moving = true }, { dead = true }, {} }

            for i, state in ipairs(states) do
                Ledger.RecordActivityTick(sessions[i % 2 + 1], levelTicks, state)
            end

            assert.are.equal(sessions[1].ticks.total + sessions[2].ticks.total, levelTicks.total)
        end)
    end)

    describe("percentages: derived on display, never stored", function()
        it("TickPercent is the activity's share of the total, 0-100", function()
            local ticks = { combat = 3, nonCombat = 1, travel = 0, dead = 0, total = 4 }

            assert.are.equal(75, Ledger.TickPercent(ticks, "combat"))
            assert.are.equal(25, Ledger.TickPercent(ticks, "nonCombat"))
            assert.are.equal(0, Ledger.TickPercent(ticks, "dead"))
        end)

        it("with no samples it is 0, never a division by zero", function()
            assert.are.equal(0, Ledger.TickPercent(Ledger.NewTicks(), "combat"))
            assert.are.equal(0, Ledger.TickPercent(nil, "combat"))
        end)

        it("the four shares add up to 100", function()
            local ticks = { combat = 7, nonCombat = 11, travel = 5, dead = 2, total = 25 }
            local sum = 0
            for _, k in ipairs(Ledger.TICK_KEYS) do sum = sum + Ledger.TickPercent(ticks, k) end

            assert.is_true(math.abs(sum - 100) < 1e-9)
        end)

        it("no percentage is ever written into the counters", function()
            local session = Ledger.NewSession(0, 5)
            local levelTicks = Ledger.NewTicks()
            Ledger.RecordActivityTick(session, levelTicks, { combat = true })

            Ledger.FormatTickLines(session.ticks)
            Ledger.FormatTickSummary(session.ticks)
            Ledger.TickPercent(session.ticks, "combat")

            assert.are.same({ combat = 1, nonCombat = 0, travel = 0, dead = 0, total = 1 }, Snapshot(session.ticks))
        end)

        it("FormatTickLines: one line per activity in the fixed order, percentages only", function()
            local lines = Ledger.FormatTickLines({ combat = 2, nonCombat = 1, travel = 0, dead = 0, total = 3 })

            assert.are.same({ "combat", "nonCombat", "travel", "dead" },
                { lines[1].key, lines[2].key, lines[3].key, lines[4].key })
            assert.are.equal("Combat: 66.7%", lines[1].text)
            assert.are.equal("Non-combat: 33.3%", lines[2].text)
            assert.are.equal("Travel: 0.0%", lines[3].text)
            assert.are.equal("Dead: 0.0%", lines[4].text)
            for _, line in ipairs(lines) do
                assert.is_nil(line.text:find("%d+:%d+"), "an absolute time leaked into: " .. line.text)
            end
        end)

        it("FormatTickLines with no samples gives 0.0% everywhere", function()
            for _, line in ipairs(Ledger.FormatTickLines(Ledger.NewTicks())) do
                assert.is_not_nil(line.text:find("0.0%", 1, true))
            end
        end)

        it("FormatTickSummary: a single line of percentages, or 'no samples yet'", function()
            assert.are.equal("Combat 50.0% | Non-combat 50.0% | Travel 0.0% | Dead 0.0%",
                Ledger.FormatTickSummary({ combat = 1, nonCombat = 1, travel = 0, dead = 0, total = 2 }))
            assert.are.equal("no samples yet", Ledger.FormatTickSummary(Ledger.NewTicks()))
            assert.are.equal("no samples yet", Ledger.FormatTickSummary(nil))
        end)
    end)
end)
