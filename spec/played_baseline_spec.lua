describe("core/played_baseline.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_buckets.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/events.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/level_close.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/xp.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/played_baseline.lua"))("Ledger", Ledger)
    end)

    -- What ui/xp_capture.lua does when the current level closes, minus the
    -- WoW bits: totalPlayed from the two totals, close, then advance the
    -- baseline. Returns the entry and the new awaiting flag.
    local function CloseLevelLikeTheUI(charDB, awaiting, level)
        local s = Ledger.NewSession(0, level)
        Ledger.AddEvent(s, 0, 100, "kill")
        local entry = Ledger.CloseLevel({ s }, Ledger.LevelPlayedTime(charDB))
        Ledger.RecordLevelClose(charDB, entry)
        return entry, Ledger.AdvancePlayedBaseline(charDB, awaiting)
    end

    describe("LevelPlayedTime", function()
        it("is the difference of the two totals when both are known", function()
            assert.are.equal(976, Ledger.LevelPlayedTime({
                lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 4859 }))
        end)

        it("is nil when the baseline is unknown (never total - 0)", function()
            assert.is_nil(Ledger.LevelPlayedTime({ lastKnownTotalTimePlayed = 5835 }))
        end)

        it("is nil when no total has been read yet", function()
            assert.is_nil(Ledger.LevelPlayedTime({ levelStartTotalPlayed = 100 }))
        end)

        it("a genuine 0 baseline is a known value, not unknown", function()
            assert.are.equal(300, Ledger.LevelPlayedTime({
                lastKnownTotalTimePlayed = 300, levelStartTotalPlayed = 0 }))
        end)

        it("never goes negative", function()
            assert.are.equal(0, Ledger.LevelPlayedTime({
                lastKnownTotalTimePlayed = 100, levelStartTotalPlayed = 400 }))
        end)
    end)

    describe("level close with an UNKNOWN baseline", function()
        it("records no totalPlayed and flags the entry, instead of inventing a number", function()
            local charDB = { lastKnownTotalTimePlayed = 5835 } -- baseline nil
            local entry = CloseLevelLikeTheUI(charDB, false, 6)

            assert.is_nil(entry.totalPlayed)
            assert.is_true(entry.timeUnreliable)
            assert.is_nil(charDB.levels[6].totalPlayed)
        end)
    end)

    describe("level close with a VALID baseline", function()
        it("records the difference and leaves the entry unflagged", function()
            local charDB = { lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 4859 }
            local entry = CloseLevelLikeTheUI(charDB, false, 6)

            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)

        it("the next level's baseline is the total at the close", function()
            local charDB = { lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 4859 }
            local _, awaiting = CloseLevelLikeTheUI(charDB, false, 6)

            assert.are.equal(5835, charDB.levelStartTotalPlayed)
            assert.is_false(awaiting)
        end)
    end)

    describe("/ldg wipe followed by a level close", function()
        it("erases the data and forgets the readings, leaving the baseline unknown and awaiting", function()
            local charDB = Ledger.InitCharDB({
                levels = { [5] = { level = 5 } }, sessions = { { level = 5 } },
                lastKnownTotalTimePlayed = 5000, levelStartTotalPlayed = 4000,
            })

            local awaiting = Ledger.WipeCharDB(charDB)

            assert.are.same({}, charDB.levels)
            assert.are.same({}, charDB.sessions)
            assert.is_nil(charDB.lastKnownTotalTimePlayed)
            assert.is_nil(charDB.levelStartTotalPlayed)
            assert.is_true(awaiting)
            assert.are.equal(Ledger.DB_VERSION, charDB.version) -- only its own fields touched
        end)

        it("the reply seeds the baseline, so the first level after a wipe gets ITS time, not the character's total", function()
            local charDB = Ledger.InitCharDB(nil)
            local awaiting = Ledger.WipeCharDB(charDB)

            -- TIME_PLAYED_MSG arrives: the character has 4859s in total.
            awaiting = Ledger.ApplyTimePlayed(charDB, 4859, awaiting)
            assert.is_false(awaiting)
            assert.are.equal(4859, charDB.levelStartTotalPlayed)

            -- ...later, a /played or a loading screen refreshes the total; the level closes.
            awaiting = Ledger.ApplyTimePlayed(charDB, 5835, awaiting)
            local entry = CloseLevelLikeTheUI(charDB, awaiting, 6)

            -- the bug recorded 5835 (01:37:15); the level only lasted 976 (00:16:16)
            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)

        it("a level that closes BEFORE the reply arrives is flagged, and the next one stays unknown until it does", function()
            local charDB = Ledger.InitCharDB(nil)
            local awaiting = Ledger.WipeCharDB(charDB)

            local entry
            entry, awaiting = CloseLevelLikeTheUI(charDB, awaiting, 6)

            assert.is_nil(entry.totalPlayed)
            assert.is_true(entry.timeUnreliable)
            assert.is_true(awaiting)
            assert.is_nil(charDB.levelStartTotalPlayed)

            -- the reply finally lands: it seeds the NEW level's baseline
            awaiting = Ledger.ApplyTimePlayed(charDB, 6100, awaiting)
            assert.are.equal(6100, charDB.levelStartTotalPlayed)
            assert.is_false(awaiting)
        end)
    end)

    describe("fresh install in the middle of a level", function()
        it("InitCharDB leaves both readings unknown instead of defaulting to 0", function()
            local charDB = Ledger.InitCharDB(nil)

            assert.is_nil(charDB.levelStartTotalPlayed)
            assert.is_nil(charDB.lastKnownTotalTimePlayed)
            assert.is_nil(Ledger.LevelPlayedTime(charDB))
        end)

        it("the first reply seeds the baseline; the level then closes with only its own time", function()
            -- Installed at level 6 with 4859s already played on the character.
            local charDB = Ledger.InitCharDB(nil)
            local awaiting = Ledger.StartPlayedBaseline(charDB) -- cold start

            awaiting = Ledger.ApplyTimePlayed(charDB, 4859, awaiting)
            awaiting = Ledger.ApplyTimePlayed(charDB, 5835, awaiting) -- later reading
            local entry = CloseLevelLikeTheUI(charDB, awaiting, 6)

            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)

        it("only the FIRST reply seeds: later ones never move the baseline", function()
            local charDB = Ledger.InitCharDB(nil)
            local awaiting = Ledger.StartPlayedBaseline(charDB)

            awaiting = Ledger.ApplyTimePlayed(charDB, 4859, awaiting)
            Ledger.ApplyTimePlayed(charDB, 9999, awaiting)

            assert.are.equal(4859, charDB.levelStartTotalPlayed)
            assert.are.equal(9999, charDB.lastKnownTotalTimePlayed)
        end)

        it("a reply that never arrives leaves the level flagged, not zero-based", function()
            local charDB = Ledger.InitCharDB(nil)
            Ledger.StartPlayedBaseline(charDB)

            local entry = CloseLevelLikeTheUI(charDB, true, 6)

            assert.is_true(entry.timeUnreliable)
        end)
    end)

    describe("ApplyTimePlayed", function()
        it("with a nil baseline that is NOT awaiting (migrated data) never seeds it", function()
            local charDB = { lastKnownTotalTimePlayed = 100 }

            local awaiting = Ledger.ApplyTimePlayed(charDB, 500, false)

            assert.is_false(awaiting)
            assert.is_nil(charDB.levelStartTotalPlayed)
            assert.are.equal(500, charDB.lastKnownTotalTimePlayed)
        end)
    end)

    describe("migration v7 -> v8", function()
        it("turns a bogus 0 baseline on a level past 1 back into unknown", function()
            local db = { version = 7, lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 0,
                         sessions = { { level = 6, stateSeries = {} } } }

            Ledger.InitCharDB(db)

            assert.is_nil(db.levelStartTotalPlayed)
            assert.are.equal(5835, db.lastKnownTotalTimePlayed)
            assert.is_nil(Ledger.LevelPlayedTime(db))
        end)

        it("keeps a 0 baseline for a character tracked from level 1 (it really had played nothing)", function()
            local db = { version = 7, lastKnownTotalTimePlayed = 900, levelStartTotalPlayed = 0,
                         sessions = { { level = 1, stateSeries = {} } } }

            Ledger.InitCharDB(db)

            assert.are.equal(0, db.levelStartTotalPlayed)
            assert.are.equal(900, Ledger.LevelPlayedTime(db))
        end)

        it("turns a lastKnown of 0 (never received) into unknown, and leaves real values alone", function()
            local a = { version = 7, lastKnownTotalTimePlayed = 0, levelStartTotalPlayed = 0 }
            local b = { version = 7, lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 4859,
                        sessions = { { level = 6, stateSeries = {} } } }

            Ledger.InitCharDB(a)
            Ledger.InitCharDB(b)

            assert.is_nil(a.lastKnownTotalTimePlayed)
            assert.are.equal(5835, b.lastKnownTotalTimePlayed)
            assert.are.equal(4859, b.levelStartTotalPlayed)
        end)
    end)
end)
