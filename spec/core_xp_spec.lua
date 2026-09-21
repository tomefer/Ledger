-- Checks that core/xp.lua can be loaded with plain lua5.1, with no WoW
-- API available, and its saved-data initialization: defaults, and the
-- wipe-on-version-mismatch rule (there are NO migrations).

describe("core/xp.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/ticks.lua"))("Ledger", Ledger) -- Ledger.NewTicks (InitCharDB)
        assert(loadfile("Ledger/core/xp.lua"))("Ledger", Ledger)
    end)

    it("loads and exposes its API", function()
        assert.is_function(Ledger.InitDB)
        assert.is_function(Ledger.InitCharDB)
        assert.is_function(Ledger.FormatXP)
        assert.is_table(Ledger.DEFAULTS)
    end)

    it("has no migration machinery at all", function()
        assert.is_nil(Ledger.MigrateDB)
    end)

    describe("InitDB (account-wide LedgerDB)", function()
        it("nil table: creates everything from the defaults and stamps the current version", function()
            local db = Ledger.InitDB(nil, Ledger.DEFAULTS)

            assert.are.equal(Ledger.DB_VERSION, db.version)
            assert.is_true(db.includeRested)
            assert.are.same(Ledger.DEFAULTS.pos, db.pos)
        end)

        it("never overwrites what is already there, only fills in what's missing", function()
            local db = Ledger.InitDB({ shown = true, includeRested = false }, Ledger.DEFAULTS)

            assert.is_true(db.shown)
            assert.is_false(db.includeRested)
            assert.are.equal(8, db.barHeight)
        end)

        it("copies table defaults instead of sharing them", function()
            local db = Ledger.InitDB(nil, Ledger.DEFAULTS)

            db.pos.x = 999

            assert.are.equal(0, Ledger.DEFAULTS.pos.x)
        end)

        it("does NOT wipe a table saved under another version: its fields are UI settings, not schema", function()
            local db = Ledger.InitDB({ version = 3, shown = true }, Ledger.DEFAULTS)

            assert.is_true(db.shown)
            assert.are.equal(Ledger.DB_VERSION, db.version)
        end)
    end)

    describe("visibility of the three views (bar / time / rate)", function()
        local VIEWS = { "barShown", "timeBarShown", "rateShown" }

        it("are visible by default when there is no saved preference", function()
            local db = Ledger.ApplyViewDefaultsOnce(Ledger.InitDB(nil, Ledger.DEFAULTS))

            for _, key in ipairs(VIEWS) do
                assert.is_true(db[key], key)
            end
        end)

        it("the main panel stays hidden by default", function()
            assert.is_false(Ledger.InitDB(nil, Ledger.DEFAULTS).shown)
        end)

        it("VIEW_KEYS lists exactly those three", function()
            assert.are.same(VIEWS, Ledger.VIEW_KEYS)
        end)

        it("a view hidden on purpose stays hidden across later loads", function()
            -- first load under the new defaults
            local db = Ledger.ApplyViewDefaultsOnce(Ledger.InitDB(nil, Ledger.DEFAULTS))
            -- the player hides two of them (what /ldg bar and /ldg rate save)
            db.barShown, db.rateShown = false, false

            -- next login: the client hands the saved table back
            db = Ledger.ApplyViewDefaultsOnce(Ledger.InitDB(db, Ledger.DEFAULTS))

            assert.is_false(db.barShown)
            assert.is_true(db.timeBarShown)
            assert.is_false(db.rateShown)
        end)

        it("a saved true is kept as well", function()
            local db = Ledger.ApplyViewDefaultsOnce(Ledger.InitDB({ viewDefaultsApplied = true, barShown = true }, Ledger.DEFAULTS))

            assert.is_true(db.barShown)
        end)

        it("one-time: a LedgerDB from before the change (false stamped by the old defaults) becomes visible", function()
            -- what the old InitDB wrote on the first load, never a choice
            local old = { version = 9, shown = false, barShown = false, timeBarShown = false, rateShown = false, barHeight = 8 }

            local db = Ledger.ApplyViewDefaultsOnce(Ledger.InitDB(old, Ledger.DEFAULTS))

            for _, key in ipairs(VIEWS) do
                assert.is_true(db[key], key)
            end
            assert.is_true(db.viewDefaultsApplied)
        end)

        it("does not touch anything else in LedgerDB", function()
            local db = Ledger.ApplyViewDefaultsOnce(Ledger.InitDB(
                { includeRested = false, shown = true, ratePos = { point = "TOP", relativePoint = "TOP", x = 1, y = 2 } },
                Ledger.DEFAULTS))

            assert.is_false(db.includeRested)
            assert.is_true(db.shown)
            assert.are.same({ point = "TOP", relativePoint = "TOP", x = 1, y = 2 }, db.ratePos)
        end)
    end)

    describe("InitCharDB (per-character data)", function()
        it("nil table: creates the full structure from scratch, not reported as a wipe", function()
            local db, wiped, oldVersion = Ledger.InitCharDB(nil)

            assert.are.equal(Ledger.DB_VERSION, db.version)
            assert.are.same({}, db.levels)
            assert.are.same({}, db.sessions)
            assert.are.same(Ledger.NewTicks(), db.levelTicks)
            assert.is_false(wiped)
            assert.is_nil(oldVersion)
        end)

        it("empty table (a first load): fills in the structure, not reported as a wipe", function()
            local db, wiped = Ledger.InitCharDB({})

            assert.are.equal(Ledger.DB_VERSION, db.version)
            assert.are.same({}, db.levels)
            assert.is_false(wiped)
        end)

        it("data already on the current version: left exactly as it is", function()
            local session = { t0 = 1, level = 3, e = { 0, 10, 1, 0 } }
            local existing = {
                version    = Ledger.DB_VERSION,
                levels     = { [3] = { level = 3, totalXP = 100 } },
                sessions   = { session },
                levelTicks = { combat = 5, nonCombat = 3, travel = 1, dead = 0, total = 9 },
            }

            local db, wiped = Ledger.InitCharDB(existing)

            assert.is_false(wiped)
            assert.are.equal(existing, db)
            assert.are.equal(100, db.levels[3].totalXP)
            assert.are.same({ session }, db.sessions)
            assert.are.equal(9, db.levelTicks.total)
        end)

        it("a missing levelTicks on current-version data is created empty", function()
            local db = Ledger.InitCharDB({ version = Ledger.DB_VERSION, levels = {}, sessions = {} })

            assert.are.same(Ledger.NewTicks(), db.levelTicks)
        end)
    end)

    describe("version mismatch: wipe, never migrate", function()
        it("an older version is wiped completely and rebuilt clean, and reported with its old version", function()
            local old = {
                version  = Ledger.DB_VERSION - 1,
                levels   = { [3] = { level = 3, totalXP = 100 } },
                sessions = { { t0 = 1, level = 3, e = { 0, 10, 1, 0 } } },
                lastKnownTotalTimePlayed = 5835,
                levelStartTotalPlayed    = 4859,
            }

            local db, wiped, oldVersion = Ledger.InitCharDB(old)

            assert.is_true(wiped)
            assert.are.equal(Ledger.DB_VERSION - 1, oldVersion)
            assert.are.equal(Ledger.DB_VERSION, db.version)
            assert.are.same({}, db.levels)
            assert.are.same({}, db.sessions)
            assert.are.same(Ledger.NewTicks(), db.levelTicks)
            -- nothing survives, not even the fields the new schema doesn't know about
            assert.is_nil(db.lastKnownTotalTimePlayed)
            assert.is_nil(db.levelStartTotalPlayed)
        end)

        it("a NEWER version is wiped too (any mismatch, not just older)", function()
            local _, wiped, oldVersion = Ledger.InitCharDB({ version = Ledger.DB_VERSION + 5, levels = { [1] = {} } })

            assert.is_true(wiped)
            assert.are.equal(Ledger.DB_VERSION + 5, oldVersion)
        end)

        it("populated data with NO version (the oldest schema) is wiped, reporting a nil old version", function()
            local db, wiped, oldVersion = Ledger.InitCharDB({ sessions = { { t0 = 1, level = 3 } } })

            assert.is_true(wiped)
            assert.is_nil(oldVersion)
            assert.are.same({}, db.sessions)
        end)

        it("the wiped table is a fresh one: the old table is never reused", function()
            local old = { version = 1, levels = { [1] = { level = 1 } } }

            local db = Ledger.InitCharDB(old)

            assert.are_not.equal(old, db)
        end)

        it("after a wipe, initializing again is a no-op (not wiped twice)", function()
            local db = Ledger.InitCharDB({ version = 1, levels = { [1] = {} } })

            local _, wiped = Ledger.InitCharDB(db)

            assert.is_false(wiped)
        end)
    end)

    describe("FormatXP", function()
        it("formats current/max and the percentage", function()
            local xpText, pctText = Ledger.FormatXP(250, 1000)

            assert.are.equal("250 / 1000", xpText)
            assert.are.equal("25.0%", pctText)
        end)

        it("at max level (max 0 or nil) there is no percentage", function()
            local xpText, pctText = Ledger.FormatXP(0, 0)
            assert.are.equal("Max level", xpText)
            assert.are.equal("", pctText)
            assert.are.equal("Max level", (Ledger.FormatXP(0, nil)))
        end)
    end)
end)
