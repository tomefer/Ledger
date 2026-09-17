-- Comprueba que busted funciona y que core/xp.lua se puede cargar con
-- lua5.1 a secas, sin ninguna API de WoW disponible.

describe("core/xp.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        -- MigrateDB (v2->v3, v3->v4, v4->v5) reescribe la serie xp y
        -- rellena los buckets de tiempo con los helpers genericos de
        -- core/series.lua y core/time_buckets.lua: hace falta cargarlos
        -- tambien, igual que en level_close_spec.lua/events_spec.lua.
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger)
        local chunk = assert(loadfile("Ledger/core/xp.lua"))
        chunk("Ledger", Ledger)
    end)

    it("se carga y expone su API", function()
        assert.is_function(Ledger.InitDB)
        assert.is_function(Ledger.FormatXP)
        assert.is_table(Ledger.DEFAULTS)
    end)

    describe("version e InitDB", function()
        it("una base de datos nueva queda en la version actual", function()
            local db = Ledger.InitDB(nil, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.are.equal(5, Ledger.DB_VERSION)
        end)

        it("migra una base de datos v1 (sin version) a la actual sin perder sus datos", function()
            local db = { shown = true }

            Ledger.InitDB(db, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)

    describe("InitCharDB", function()
        it("tabla nil: crea la estructura completa desde cero", function()
            local db = Ledger.InitCharDB(nil)

            assert.are.equal(5, db.version)
            assert.are.same({}, db.levels)
            assert.are.same({}, db.sessions)
            assert.are.equal(0, db.lastKnownTotalTimePlayed)
            assert.are.equal(0, db.levelStartTotalPlayed)
        end)

        it("tabla vacia: rellena lo que falta igual que si fuera nil", function()
            local db = Ledger.InitCharDB({})

            assert.are.equal(5, db.version)
            assert.are.same({}, db.levels)
            assert.are.same({}, db.sessions)
        end)

        it("tabla ya poblada en la version actual: no altera nada de lo que ya hubiera", function()
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

        it("tabla con version antigua: migra la version y conserva/crea el resto", function()
            local db = Ledger.InitCharDB({ version = 1, sessions = { { t0 = 1, nivel = 3 } } })

            assert.are.equal(5, db.version)
            assert.are.same({}, db.levels)
            -- La migracion v3->v4 rellena buckets a cero (no habia forma
            -- de saber retroactivamente como se repartio ese tiempo); la
            -- v4->v5 renombra nivel->level y anade deaths=0.
            assert.are.same(
                { { t0 = 1, level = 3, deaths = 0, buckets = { active = 0, idle = 0, travel = 0, dead = 0 } } },
                db.sessions)
        end)
    end)

    describe("migracion v2 -> v3: serie xp de stride 3 a 4", function()
        it("reescribe un array plano viejo (off, xp, src) anadiendo rested = 0", function()
            local session = { t0 = 0, nivel = 10, e = {
                0, 50, "kill",
                300, 20, "quest",
            } }
            local db = { version = 2, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            -- La v4->v5 traduce src a ID numerico en el mismo pase.
            assert.are.same({
                0, 50, Ledger.SRC_IDS.kill, 0,
                300, 20, Ledger.SRC_IDS.quest, 0,
            }, session.e)
        end)

        it("no toca nada si la sesion no tiene ningun evento", function()
            local session = { t0 = 0, nivel = 10 }
            local db = { version = 2, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.is_nil(session.e)
        end)

        it("no repite la migracion de stride si ya esta en stride 4", function()
            local session = { t0 = 0, nivel = 10, e = { 0, 50, "kill", 5 } }
            local db = { version = 3, sessions = { session } }

            Ledger.InitCharDB(db)

            -- Ya estaba en stride 4: si se releyera como stride 3 por
            -- error, esto se corromperia. La v4->v5 solo traduce src a
            -- numerico en el mismo sitio, sin cambiar el stride.
            assert.are.same({ 0, 50, Ledger.SRC_IDS.kill, 5 }, session.e)
        end)

        it("una base de datos sin sessions (LedgerDB) migra la version sin reventar", function()
            local db = Ledger.InitDB({ version = 2, shown = true }, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)

    describe("migracion v3 -> v4: buckets de tiempo", function()
        it("rellena session.buckets a cero si no existia", function()
            local session = { t0 = 0, nivel = 10, e = { 0, 50, "kill", 0 } }
            local db = { version = 3, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.are.same({ active = 0, idle = 0, travel = 0, dead = 0 }, session.buckets)
        end)

        it("no toca los buckets si ya existian", function()
            local session = { t0 = 0, nivel = 10, buckets = { active = 50, idle = 10, travel = 5, dead = 0 } }
            local db = { version = 3, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.same({ active = 50, idle = 10, travel = 5, dead = 0 }, session.buckets)
        end)

        it("una base de datos sin sessions (LedgerDB) migra sin reventar", function()
            local db = Ledger.InitDB({ version = 3, shown = true }, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)

    describe("migracion v4 -> v5: nivel->level, off entero, src numerico, deaths/reached", function()
        it("renombra session.nivel a session.level", function()
            local session = { t0 = 0, nivel = 10, e = {} }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.are.equal(10, session.level)
            assert.is_nil(session.nivel)
        end)

        it("renondea off a la decima de segundo mas cercana", function()
            local session = { t0 = 0, nivel = 10, e = {
                123.4999999, 50, "kill", 0, -- imprecision tipica de (GetTime()-t0)*10
                200.5000001, 20, "quest", 0,
            } }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.same({
                123, 50, Ledger.SRC_IDS.kill, 0,
                201, 20, Ledger.SRC_IDS.quest, 0,
            }, session.e)
        end)

        it("traduce src de texto a ID numerico", function()
            local session = { t0 = 0, nivel = 10, e = { 0, 50, "explore", 0 } }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(Ledger.SRC_IDS.explore, session.e[3])
        end)

        it("no vuelve a traducir un src que ya sea numerico (no repite la migracion)", function()
            local session = { t0 = 0, nivel = 10, e = { 0, 50, Ledger.SRC_IDS.kill, 0 } }
            local db = { version = 5, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(Ledger.SRC_IDS.kill, session.e[3])
        end)

        it("rellena deaths a 0 en sesiones sin ese campo", function()
            local session = { t0 = 0, nivel = 10, e = {} }
            local db = { version = 4, sessions = { session } }

            Ledger.InitCharDB(db)

            assert.are.equal(0, session.deaths)
        end)

        it("renombra entry.nivel a entry.level en niveles ya cerrados y rellena deaths/reached", function()
            local db = {
                version = 4,
                levels  = { [3] = { nivel = 3, totalXP = 900 } },
            }

            Ledger.InitCharDB(db)

            assert.are.equal(5, db.version)
            assert.are.equal(3, db.levels[3].level)
            assert.is_nil(db.levels[3].nivel)
            assert.are.equal(0, db.levels[3].deaths)
            assert.are.equal(0, db.levels[3].reached)
        end)

        it("una base de datos sin sessions ni levels (LedgerDB) migra sin reventar", function()
            local db = Ledger.InitDB({ version = 4, shown = true }, Ledger.DEFAULTS)

            assert.are.equal(5, db.version)
            assert.is_true(db.shown)
        end)
    end)
end)
