-- Checks that busted works and that core/xp.lua can be loaded with
-- plain lua5.1, with no WoW API available.

describe("core/xp.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        -- MigrateDB (v2->v3, v3->v4, v4->v5) rewrites the xp series and
        -- fills the time buckets using the generic helpers from
        -- core/series.lua and core/time_buckets.lua: they need to be loaded
        -- too, same as in level_close_spec.lua/events_spec.lua.
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger)
        local chunk = assert(loadfile("Ledger/core/xp.lua"))
        chunk("Ledger", Ledger)
    end)

    it("loads and exposes its API", function()
        assert.is_function(Ledger.InitDB)
        assert.is_function(Ledger.FormatXP)
        assert.is_table(Ledger.DEFAULTS)
    end)

    describe("version and InitDB", function()
        it("a brand-new database ends up on the current version", function()
            local db = Ledger.InitDB(nil, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.are.equal(5, Ledger.DB_VERSION)
        end)

        it("migrates a v1 database (no version) to the current one without losing its data", function()
            local db = { shown = true }

            Ledger.InitDB(db, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)

    describe("InitCharDB", function()
        it("nil table: creates the full structure from scratch", function()
            local db = Ledger.InitCharDB(nil)

            assert.are.equal(5, db.version)
            assert.are.same({}, db.levels)
            assert.are.same({}, db.sessions)
            assert.are.equal(0, db.lastKnownTotalTimePlayed)
            assert.are.equal(0, db.levelStartTotalPlayed)
        end)

        it("empty table: fills in what's missing just like if it were nil", function()
            local db = Ledger.InitCharDB({})

            assert.are.equal(5, db.version)
            assert.are.same({}, db.levels)
            assert.are.same({}, db.sessions)
        end)

        it("table already populated on the current version: doesn't alter anything already there", function()
            local original = {
                version  = 5,
                levels   = { [5] = { level = 5, totalXP = 100 } },
                sessions = { { t0 = 1000, level = 6 } },
            }

            local db = Ledger.InitCharDB(original)

            assert.are.equal(5, db.version)
            assert.are.same({ [5] = { level = 5, totalXP = 100 } }, db.levels)
            assert.are.same({ { t0 = 1000, level = 6 } }, db.sessions)
        end)

        it("table with an old version: migrates the version and keeps/creates the rest", function()
            local db = Ledger.InitCharDB({ version = 1, sessions = { { t0 = 1, level = 3 } } })

            assert.are.equal(5, db.version)
            assert.are.same({}, db.levels)
            -- The v3->v4 migration fills buckets with zero (there was no way
            -- to know retroactively how that time was split); the
            -- v4->v5 one adds deaths=0.
            assert.are.same(
                { { t0 = 1, level = 3, deaths = 0, buckets = { active = 0, idle = 0, travel = 0, dead = 0 } } },
                db.sessions)
        end)
    end)

    describe("v2 -> v3 migration: xp series from stride 3 to 4", function()
        it("rewrites an old flat array (off, xp, src) adding rested = 0", function()
            local session = { t0 = 0, level = 10, e = {
                0, 50, "kill",
                300, 20, "quest",
            } }
            local db = { version = 2, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            -- The v4->v5 pass translates src to a numeric ID in the same run.
            assert.are.same({
                0, 50, Ledger.SRC_IDS.kill, 0,
                300, 20, Ledger.SRC_IDS.quest, 0,
            }, session.e)
        end)

        it("doesn't touch anything if the session has no events", function()
            local session = { t0 = 0, level = 10 }
            local db = { version = 2, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.is_nil(session.e)
        end)

        it("doesn't repeat the stride migration if already on stride 4", function()
            local session = { t0 = 0, level = 10, e = { 0, 50, "kill", 5 } }
            local db = { version = 3, sessions = { session } }

            Ledger.InitCharDB(db)

            -- Already on stride 4: if it were misread as stride 3, this
            -- would get corrupted. v4->v5 only translates src to
            -- numeric in place, without changing the stride.
            assert.are.same({ 0, 50, Ledger.SRC_IDS.kill, 5 }, session.e)
        end)

        it("a database with no sessions (LedgerDB) migrates its version without blowing up", function()
            local db = Ledger.InitDB({ version = 2, shown = true }, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)

    describe("v3 -> v4 migration: time buckets", function()
        it("fills session.buckets with zero if it didn't exist", function()
            local session = { t0 = 0, level = 10, e = { 0, 50, "kill", 0 } }
            local db = { version = 3, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.are.same({ active = 0, idle = 0, travel = 0, dead = 0 }, session.buckets)
        end)

        it("doesn't touch the buckets if they already existed", function()
            local session = { t0 = 0, level = 10, buckets = { active = 50, idle = 10, travel = 5, dead = 0 } }
            local db = { version = 3, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.same({ active = 50, idle = 10, travel = 5, dead = 0 }, session.buckets)
        end)

        it("a database with no sessions (LedgerDB) migrates without blowing up", function()
            local db = Ledger.InitDB({ version = 3, shown = true }, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)

    describe("v4 -> v5 migration: integer off, numeric src, deaths/reached", function()
        it("rounds off to the nearest tenth of a second", function()
            local session = { t0 = 0, level = 10, e = {
                123.4999999, 50, "kill", 0, -- typical imprecision from (GetTime()-t0)*10
                200.5000001, 20, "quest", 0,
            } }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.same({
                123, 50, Ledger.SRC_IDS.kill, 0,
                201, 20, Ledger.SRC_IDS.quest, 0,
            }, session.e)
        end)

        it("translates src from text to a numeric ID", function()
            local session = { t0 = 0, level = 10, e = { 0, 50, "explore", 0 } }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(Ledger.SRC_IDS.explore, session.e[3])
        end)

        it("doesn't re-translate a src that's already numeric (migration isn't repeated)", function()
            local session = { t0 = 0, level = 10, e = { 0, 50, Ledger.SRC_IDS.kill, 0 } }
            local db = { version = 5, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(Ledger.SRC_IDS.kill, session.e[3])
        end)

        it("fills deaths with 0 in sessions missing that field", function()
            local session = { t0 = 0, level = 10, e = {} }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(0, session.deaths)
        end)

        it("fills deaths/reached with 0 on already-closed levels entries missing them", function()
            local db = {
                version = 4,
                levels  = { [3] = { level = 3, totalXP = 900 } },
            }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.are.equal(3, db.levels[3].level)
            assert.are.equal(0, db.levels[3].deaths)
            assert.are.equal(0, db.levels[3].reached)
        end)

        it("a database with no sessions or levels (LedgerDB) migrates without blowing up", function()
            local db = Ledger.InitDB({ version = 4, shown = true }, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)
end)
