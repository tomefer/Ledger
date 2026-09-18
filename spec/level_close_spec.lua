describe("core/level_close.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger) -- Ledger.NewEmptyBuckets
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/level_close.lua"))("Ledger", Ledger)
    end)

    describe("single-session level", function()
        it("aggregates that session's totals, breakdown and curve", function()
            local s = Ledger.NewSession(1000, 10)
            Ledger.AddEvent(s, 0, 50, "kill")
            Ledger.AddEvent(s, 300, 20, "quest")
            Ledger.AddEvent(s, 650, 100, "kill")

            local entry = Ledger.CloseLevel({ s }, 500)

            assert.are.equal(10, entry.level)
            assert.are.equal(170, entry.totalXP)
            assert.are.equal(500, entry.totalPlayed)
            assert.are.same({ kill = 150, quest = 20 }, entry.bySource)
            assert.are.same({ 70, 100 }, entry.curve)
        end)
    end)

    describe("level spanning several sessions", function()
        it("aggregates and merges the curve of all the level's sessions", function()
            local a = Ledger.NewSession(0, 20)
            Ledger.AddEvent(a, 0, 10, "kill")
            Ledger.AddEvent(a, 650, 5, "quest")

            local b = Ledger.NewSession(5000, 20)
            Ledger.AddEvent(b, 100, 20, "kill")
            Ledger.AddEvent(b, 1300, 8, "quest")

            local entry = Ledger.CloseLevel({ a, b }, 900)

            assert.are.equal(20, entry.level)
            assert.are.equal(43, entry.totalXP)
            assert.are.equal(900, entry.totalPlayed)
            assert.are.same({ kill = 30, quest = 13 }, entry.bySource)
            -- minute 1: 10 (a) + 20 (b); minute 2: 5 (a); minute 3: 8 (b)
            assert.are.same({ 30, 5, 8 }, entry.curve)
        end)
    end)

    describe("session spanning two levels", function()
        it("aggregates each piece separately without mixing or losing events", function()
            -- A real session that dings mid-game is passed to this
            -- function already pre-split by the caller: one level
            -- close per half of its events array.
            local level5 = Ledger.NewSession(2000, 5)
            Ledger.AddEvent(level5, 0, 80, "kill")
            Ledger.AddEvent(level5, 200, 40, "quest")
            Ledger.AddEvent(level5, 250, 1, "kill")   -- the hit that dings

            local level6 = Ledger.NewSession(2000, 6)
            Ledger.AddEvent(level6, 300, 60, "kill")
            Ledger.AddEvent(level6, 900, 30, "quest")

            local entry5 = Ledger.CloseLevel({ level5 }, 25)
            local entry6 = Ledger.CloseLevel({ level6 }, 90)

            assert.are.equal(5, entry5.level)
            assert.are.equal(121, entry5.totalXP)
            assert.are.same({ kill = 81, quest = 40 }, entry5.bySource)
            assert.are.same({ 121 }, entry5.curve)

            assert.are.equal(6, entry6.level)
            assert.are.equal(90, entry6.totalXP)
            assert.are.same({ kill = 60, quest = 30 }, entry6.bySource)
            assert.are.same({ 60, 30 }, entry6.curve)

            -- No xp is lost or duplicated when splitting the original session.
            assert.are.equal(80 + 40 + 1 + 60 + 30, entry5.totalXP + entry6.totalXP)
        end)
    end)

    describe("totalRested", function()
        it("accumulates the rested bonus across all the level's sessions", function()
            local a = Ledger.NewSession(0, 15)
            Ledger.AddEvent(a, 0, 172, "kill", 86)
            Ledger.AddEvent(a, 300, 50, "quest")

            local b = Ledger.NewSession(5000, 15)
            Ledger.AddEvent(b, 100, 60, "kill", 20)

            local entry = Ledger.CloseLevel({ a, b }, 900)

            assert.are.equal(106, entry.totalRested)
            -- totalXP never subtracts the bonus on its own (includeRested
            -- defaults to true).
            assert.are.equal(282, entry.totalXP)
        end)

        it("is zero when no event carried a bonus", function()
            local s = Ledger.NewSession(0, 3)
            Ledger.AddEvent(s, 0, 40, "kill")

            local entry = Ledger.CloseLevel({ s }, 60)

            assert.are.equal(0, entry.totalRested)
        end)
    end)

    describe("CloseLevel: unknown played time", function()
        it("a nil totalPlayed is kept nil and flags the entry timeUnreliable", function()
            local s = Ledger.NewSession(0, 6)
            Ledger.AddEvent(s, 0, 50, "kill")

            local entry = Ledger.CloseLevel({ s }, nil)

            assert.is_nil(entry.totalPlayed)
            assert.is_true(entry.timeUnreliable)
        end)

        it("a known totalPlayed, even 0, leaves the flag absent", function()
            local s = Ledger.NewSession(0, 6)

            assert.is_nil(Ledger.CloseLevel({ s }, 0).timeUnreliable)
            assert.are.equal(0, Ledger.CloseLevel({ s }, 0).totalPlayed)
        end)
    end)

    describe("CloseLevel: xpRequired and initialXP (for /ldg check)", function()
        it("records the level's requirement and the first session's initialXP", function()
            local a = Ledger.NewSession(0, 9)
            a.initialXP = 300
            Ledger.AddEvent(a, 0, 700, "kill")
            local b = Ledger.NewSession(5000, 9)
            b.initialXP = 999 -- only the level's FIRST session can carry it; never summed

            local entry = Ledger.CloseLevel({ a, b }, 100, true, nil, 1000)

            assert.are.equal(1000, entry.xpRequired)
            assert.are.equal(300, entry.initialXP)
        end)

        it("leaves xpRequired absent when not given, and initialXP at 0", function()
            local s = Ledger.NewSession(0, 9)
            Ledger.AddEvent(s, 0, 50, "kill")

            local entry = Ledger.CloseLevel({ s }, 100)

            assert.is_nil(entry.xpRequired)
            assert.are.equal(0, entry.initialXP)
        end)
    end)

    describe("CloseLevel with the includeRested toggle", function()
        it("with includeRested=false, totalXP and curve subtract the bonus, totalRested doesn't change", function()
            local s = Ledger.NewSession(0, 8)
            Ledger.AddEvent(s, 0, 172, "kill", 86)   -- minute 1
            Ledger.AddEvent(s, 650, 50, "quest")     -- minute 2

            local entryTrue  = Ledger.CloseLevel({ s }, 120, true)
            local entryFalse = Ledger.CloseLevel({ s }, 120, false)

            assert.are.equal(222, entryTrue.totalXP)
            assert.are.same({ 172, 50 }, entryTrue.curve)

            assert.are.equal(136, entryFalse.totalXP)
            assert.are.same({ 86, 50 }, entryFalse.curve)

            -- The real accumulated bonus is the same regardless of the
            -- toggle: the toggle only affects the calculation, never
            -- what gets recorded.
            assert.are.equal(86, entryTrue.totalRested)
            assert.are.equal(86, entryFalse.totalRested)
        end)

        it("bySource never changes with the toggle: it stays the total xp as-is", function()
            local s = Ledger.NewSession(0, 8)
            Ledger.AddEvent(s, 0, 172, "kill", 86)

            local entryTrue  = Ledger.CloseLevel({ s }, 60, true)
            local entryFalse = Ledger.CloseLevel({ s }, 60, false)

            assert.are.same({ kill = 172 }, entryTrue.bySource)
            assert.are.same({ kill = 172 }, entryFalse.bySource)
        end)
    end)

    describe("level with no events", function()
        it("returns zeroed totals and an empty curve without breaking", function()
            local s = Ledger.NewSession(3000, 42)

            local entry = Ledger.CloseLevel({ s }, 45)

            assert.are.equal(42, entry.level)
            assert.are.equal(0, entry.totalXP)
            assert.are.equal(45, entry.totalPlayed)
            assert.are.same({}, entry.bySource)
            assert.are.same({}, entry.curve)
            assert.is_nil(entry.stateSeries)
            assert.are.same({ active = 0, downtime = 0, travel = 0, dead = 0 }, entry.buckets)
        end)
    end)

    describe("time buckets", function()
        it("derives buckets from the raw state series concatenated across all the level's sessions", function()
            local a = Ledger.NewSession(0, 7)
            Ledger.AppendRecord(a, Ledger.SERIES.state, Ledger.PackStateFlags({ combat = true }))
            Ledger.AppendRecord(a, Ledger.SERIES.state, Ledger.PackStateFlags({ combat = true }))

            local b = Ledger.NewSession(5000, 7)
            Ledger.AppendRecord(b, Ledger.SERIES.state, Ledger.PackStateFlags({ dead = true }))

            local entry = Ledger.CloseLevel({ a, b }, 3)

            assert.are.equal(2, entry.buckets.active)
            assert.are.equal(1, entry.buckets.dead)
        end)

        it("a session with an empty state series (nothing sampled yet) doesn't blow up", function()
            local a = Ledger.NewSession(0, 7)
            local b = Ledger.NewSession(5000, 7)
            Ledger.AppendRecord(b, Ledger.SERIES.state, Ledger.PackStateFlags({ combat = true }))

            local entry = Ledger.CloseLevel({ a, b }, 10)

            assert.are.equal(1, entry.buckets.active)
        end)

        it("discards the raw series: the entry never carries it", function()
            local a = Ledger.NewSession(0, 7)
            Ledger.AppendRecord(a, Ledger.SERIES.state, Ledger.PackStateFlags({ combat = true }))

            local entry = Ledger.CloseLevel({ a }, 1)

            assert.is_nil(entry.stateSeries)
        end)

        it("records the current thresholds the buckets were derived with", function()
            local a = Ledger.NewSession(0, 7)

            local entry = Ledger.CloseLevel({ a }, 1)

            assert.are.same(
                { downtime = Ledger.DOWNTIME_THRESHOLD, sustainedMovement = Ledger.SUSTAINED_MOVEMENT_SECONDS },
                entry.thresholds)
        end)

        it("an explicit threshold override is both applied to the buckets and recorded", function()
            -- 1 second of combat, then 3 quiet seconds: with downtime=2
            -- the third quiet second is already downtime; with the
            -- default 15 all three would stay "active".
            local a = Ledger.NewSession(0, 7)
            local combat = Ledger.PackStateFlags({ combat = true })
            for _, v in ipairs({ combat, 0, 0, 0 }) do
                Ledger.AppendRecord(a, Ledger.SERIES.state, v)
            end

            local entry = Ledger.CloseLevel({ a }, 4, true, { downtime = 2 })

            assert.are.equal(3, entry.buckets.active)   -- combat + 2 quiet seconds
            assert.are.equal(1, entry.buckets.downtime)
            assert.are.equal(2, entry.thresholds.downtime)
            assert.are.equal(Ledger.SUSTAINED_MOVEMENT_SECONDS, entry.thresholds.sustainedMovement)
        end)
    end)

    describe("deaths", function()
        it("sums the deaths across all the level's sessions", function()
            local a = Ledger.NewSession(0, 7)
            a.deaths = 2
            local b = Ledger.NewSession(5000, 7)
            b.deaths = 1

            local entry = Ledger.CloseLevel({ a, b }, 10)

            assert.are.equal(3, entry.deaths)
        end)

        it("is 0 if no session died (deaths already defaults to 0 via NewSession)", function()
            local s = Ledger.NewSession(0, 7)

            local entry = Ledger.CloseLevel({ s }, 10)

            assert.are.equal(0, entry.deaths)
        end)
    end)

    describe("reached", function()
        it("takes the reached from the level's first session", function()
            local a = Ledger.NewSession(0, 7)
            a.reached = 1758000000
            local b = Ledger.NewSession(5000, 7)

            local entry = Ledger.CloseLevel({ a, b }, 10)

            assert.are.equal(1758000000, entry.reached)
        end)

        it("is 0 if the session carries no reached (old schema before migrating)", function()
            local s = Ledger.NewSession(0, 7)

            local entry = Ledger.CloseLevel({ s }, 10)

            assert.are.equal(0, entry.reached)
        end)
    end)

    describe("RecordLevelClose", function()
        it("creates db.levels if missing and writes the per-level entry", function()
            local db = {}
            local entry = { level = 7, totalXP = 300 }

            Ledger.RecordLevelClose(db, entry)

            assert.are.same({ [7] = entry }, db.levels)
        end)

        it("doesn't overwrite already-saved entries of other levels", function()
            local db = { levels = { [3] = { level = 3, totalXP = 10 } } }
            local entry = { level = 4, totalXP = 20 }

            Ledger.RecordLevelClose(db, entry)

            assert.are.same({ level = 3, totalXP = 10 }, db.levels[3])
            assert.are.same(entry, db.levels[4])
        end)
    end)
end)
