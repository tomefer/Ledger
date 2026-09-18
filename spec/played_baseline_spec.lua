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

    -- What ui/xp_capture.lua does when the current level closes at
    -- GetTime() = t, minus the WoW bits: totalPlayed from the estimate and
    -- the baseline, close, then advance the baseline. Returns the entry.
    local function CloseLevelLikeTheUI(charDB, clock, level, t)
        local s = Ledger.NewSession(0, level)
        Ledger.AddEvent(s, 0, 100, "kill")
        local entry = Ledger.CloseLevel({ s }, Ledger.LevelPlayedTime(charDB, clock, t))
        Ledger.RecordLevelClose(charDB, entry)
        Ledger.AdvancePlayedBaseline(charDB, clock, t)
        return entry
    end

    -- A charDB/clock pair as left by a TIME_PLAYED_MSG of `total` at GetTime() = at.
    local function ReplyAt(total, at, baseline)
        local charDB = { lastKnownTotalTimePlayed = total, levelStartTotalPlayed = baseline }
        local clock = Ledger.NewPlayedClock()
        clock.receivedAt = at
        return charDB, clock
    end

    describe("EstimatePlayedTotal: cached + (now - receivedAt)", function()
        it("extrapolates the cached total by the time since it was received", function()
            local charDB, clock = ReplyAt(4859, 100)

            assert.are.equal(4859, Ledger.EstimatePlayedTotal(charDB, clock, 100))
            assert.are.equal(4859 + 976, Ledger.EstimatePlayedTotal(charDB, clock, 1076))
        end)

        it("accepts a moment slightly BEFORE the reply (a ding whose reply landed a beat later)", function()
            local charDB, clock = ReplyAt(4859, 100)

            assert.are.equal(4857, Ledger.EstimatePlayedTotal(charDB, clock, 98))
        end)

        it("is nil when no total is cached (unknown, never 0)", function()
            local clock = Ledger.NewPlayedClock()
            clock.receivedAt = 100

            assert.is_nil(Ledger.EstimatePlayedTotal({}, clock, 500))
        end)

        it("is nil when the total was not received in THIS Lua state, whatever `now` is", function()
            -- What a /reload or a client restart leaves: the saved total is
            -- there, but no receivedAt (in-memory only) -- so the raw stale
            -- value is never used, and it can't be extrapolated with an
            -- unrelated GetTime() either.
            local charDB = { lastKnownTotalTimePlayed = 4859 }
            local clock = Ledger.NewPlayedClock()

            assert.is_nil(Ledger.EstimatePlayedTotal(charDB, clock, 0))
            assert.is_nil(Ledger.EstimatePlayedTotal(charDB, clock, 1e9))
        end)

        it("is nil without a `now`", function()
            local charDB, clock = ReplyAt(4859, 100)

            assert.is_nil(Ledger.EstimatePlayedTotal(charDB, clock, nil))
        end)

        it("never touches the persisted table: receivedAt is not saved anywhere in charDB", function()
            local charDB = Ledger.InitCharDB(nil)
            local clock = Ledger.NewPlayedClock()

            Ledger.ApplyTimePlayed(charDB, clock, 4859, 12345.678)

            for key, value in pairs(charDB) do
                assert.is_not.equal(12345.678, value, "GetTime() leaked into charDB." .. tostring(key))
            end
            assert.are.equal(12345.678, clock.receivedAt)
        end)
    end)

    describe("the frozen-cache bug: totalPlayed underestimated between replies", function()
        it("a level closed long after the last reply gets its real time, not the frozen difference", function()
            -- Reply at GetTime()=100: total 4859, level baseline 4859. No
            -- further reply; the level closes at GetTime()=1076, i.e. 976s later.
            local charDB, clock = ReplyAt(4859, 100, 4859)

            -- the raw frozen field would give 4859 - 4859 = 0
            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 1076)

            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)

        it("the next level's baseline is the estimate at the ding, so it isn't stale either", function()
            local charDB, clock = ReplyAt(4859, 100, 4859)

            CloseLevelLikeTheUI(charDB, clock, 6, 1076)
            assert.are.equal(4859 + 976, charDB.levelStartTotalPlayed)
            assert.is_false(clock.awaiting)

            -- 600s of level 7, still with no new reply
            local entry7 = CloseLevelLikeTheUI(charDB, clock, 7, 1676)
            assert.are.equal(600, entry7.totalPlayed)
        end)

        it("a fresh reply between closes re-anchors the estimate without double counting", function()
            local charDB, clock = ReplyAt(4859, 100, 4859)

            -- 500s later a loading screen re-requests: server says 5359
            Ledger.ApplyTimePlayed(charDB, clock, 5359, 600)
            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 1076)

            assert.are.equal(976, entry.totalPlayed)
        end)

        it("the live level time keeps growing between replies", function()
            local charDB, clock = ReplyAt(4859, 100, 4859)

            assert.are.equal(0,   Ledger.LevelPlayedTime(charDB, clock, 100))
            assert.are.equal(60,  Ledger.LevelPlayedTime(charDB, clock, 160))
            assert.are.equal(976, Ledger.LevelPlayedTime(charDB, clock, 1076))
        end)
    end)

    describe("LevelPlayedTime", function()
        it("is nil when the baseline is unknown (never estimate - 0)", function()
            local charDB, clock = ReplyAt(5835, 100)

            assert.is_nil(Ledger.LevelPlayedTime(charDB, clock, 100))
        end)

        it("is nil when the cached total is unknown", function()
            local clock = Ledger.NewPlayedClock()

            assert.is_nil(Ledger.LevelPlayedTime({ levelStartTotalPlayed = 100 }, clock, 500))
        end)

        it("a genuine 0 baseline is a known value, not unknown", function()
            local charDB, clock = ReplyAt(300, 100, 0)

            assert.are.equal(300, Ledger.LevelPlayedTime(charDB, clock, 100))
        end)

        it("never goes negative", function()
            local charDB, clock = ReplyAt(100, 50, 400)

            assert.are.equal(0, Ledger.LevelPlayedTime(charDB, clock, 50))
        end)
    end)

    describe("level close with an UNKNOWN cached total", function()
        it("records no totalPlayed and flags the entry, instead of inventing a number", function()
            local charDB = {} -- nothing cached, baseline nil
            local entry = CloseLevelLikeTheUI(charDB, Ledger.NewPlayedClock(), 6, 1000)

            assert.is_nil(entry.totalPlayed)
            assert.is_true(entry.timeUnreliable)
        end)

        it("a saved total from a previous run with no reply yet in this one is also unknown", function()
            local charDB = { lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 4859 }
            local entry = CloseLevelLikeTheUI(charDB, Ledger.NewPlayedClock(), 6, 1000)

            assert.is_nil(entry.totalPlayed)
            assert.is_true(entry.timeUnreliable)
        end)
    end)

    describe("level close with a VALID baseline", function()
        it("records the difference and leaves the entry unflagged", function()
            local charDB, clock = ReplyAt(5835, 100, 4859)
            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 100)

            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)
    end)

    describe("/ldg wipe followed by a level close", function()
        it("erases the data and forgets the readings, leaving the baseline unknown and awaiting", function()
            local charDB = Ledger.InitCharDB({
                levels = { [5] = { level = 5 } }, sessions = { { level = 5 } },
                lastKnownTotalTimePlayed = 5000, levelStartTotalPlayed = 4000,
            })
            local clock = Ledger.NewPlayedClock()
            clock.receivedAt = 50

            Ledger.WipeCharDB(charDB, clock)

            assert.are.same({}, charDB.levels)
            assert.are.same({}, charDB.sessions)
            assert.is_nil(charDB.lastKnownTotalTimePlayed)
            assert.is_nil(charDB.levelStartTotalPlayed)
            assert.is_nil(clock.receivedAt)
            assert.is_true(clock.awaiting)
            assert.are.equal(Ledger.DB_VERSION, charDB.version) -- only its own fields touched
        end)

        it("the reply seeds the baseline, so the first level after a wipe gets ITS time, not the character's total", function()
            local charDB = Ledger.InitCharDB(nil)
            local clock = Ledger.NewPlayedClock()
            Ledger.WipeCharDB(charDB, clock)

            -- TIME_PLAYED_MSG arrives at GetTime()=100: the character has 4859s in total.
            assert.is_true(Ledger.ApplyTimePlayed(charDB, clock, 4859, 100))
            assert.is_false(clock.awaiting)
            assert.are.equal(4859, charDB.levelStartTotalPlayed)

            -- the level closes 976s later with no other reading
            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 1076)

            -- the bug recorded 5835 (01:37:15); the level only lasted 976 (00:16:16)
            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)

        it("a level that closes BEFORE the reply arrives is flagged, and the next one stays unknown until it does", function()
            local charDB = Ledger.InitCharDB(nil)
            local clock = Ledger.NewPlayedClock()
            Ledger.WipeCharDB(charDB, clock)

            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 90)

            assert.is_nil(entry.totalPlayed)
            assert.is_true(entry.timeUnreliable)
            assert.is_true(clock.awaiting)
            assert.is_nil(charDB.levelStartTotalPlayed)

            -- the reply finally lands: it seeds the NEW level's baseline
            assert.is_true(Ledger.ApplyTimePlayed(charDB, clock, 6100, 100))
            assert.are.equal(6100, charDB.levelStartTotalPlayed)
            assert.is_false(clock.awaiting)
        end)
    end)

    describe("fresh install in the middle of a level", function()
        it("InitCharDB leaves both readings unknown instead of defaulting to 0", function()
            local charDB = Ledger.InitCharDB(nil)

            assert.is_nil(charDB.levelStartTotalPlayed)
            assert.is_nil(charDB.lastKnownTotalTimePlayed)
            assert.is_nil(Ledger.LevelPlayedTime(charDB, Ledger.NewPlayedClock(), 100))
        end)

        it("the first reply seeds the baseline; the level then closes with only its own time", function()
            -- Installed at level 6 with 4859s already played on the character.
            local charDB = Ledger.InitCharDB(nil)
            local clock = Ledger.NewPlayedClock()
            Ledger.StartPlayedBaseline(charDB, clock) -- cold start

            Ledger.ApplyTimePlayed(charDB, clock, 4859, 100)
            Ledger.ApplyTimePlayed(charDB, clock, 5300, 541) -- a later refresh
            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 1076)

            assert.are.equal(976, entry.totalPlayed)
            assert.is_nil(entry.timeUnreliable)
        end)

        it("only the FIRST reply seeds: later ones never move the baseline", function()
            local charDB = Ledger.InitCharDB(nil)
            local clock = Ledger.NewPlayedClock()
            Ledger.StartPlayedBaseline(charDB, clock)

            assert.is_true(Ledger.ApplyTimePlayed(charDB, clock, 4859, 100))
            assert.is_false(Ledger.ApplyTimePlayed(charDB, clock, 9999, 700))

            assert.are.equal(4859, charDB.levelStartTotalPlayed)
            assert.are.equal(9999, charDB.lastKnownTotalTimePlayed)
            assert.are.equal(700, clock.receivedAt)
        end)

        it("a reply that never arrives leaves the level flagged, not zero-based", function()
            local charDB = Ledger.InitCharDB(nil)
            local clock = Ledger.NewPlayedClock()
            Ledger.StartPlayedBaseline(charDB, clock)

            local entry = CloseLevelLikeTheUI(charDB, clock, 6, 1000)

            assert.is_true(entry.timeUnreliable)
        end)
    end)

    describe("ApplyTimePlayed", function()
        it("with a nil baseline that is NOT awaiting (migrated data) never seeds it", function()
            local charDB = { lastKnownTotalTimePlayed = 100 }
            local clock = Ledger.NewPlayedClock()

            assert.is_false(Ledger.ApplyTimePlayed(charDB, clock, 500, 10))

            assert.is_nil(charDB.levelStartTotalPlayed)
            assert.are.equal(500, charDB.lastKnownTotalTimePlayed)
            assert.are.equal(10, clock.receivedAt)
        end)
    end)

    describe("migration v7 -> v8", function()
        it("turns a bogus 0 baseline on a level past 1 back into unknown", function()
            local db = { version = 7, lastKnownTotalTimePlayed = 5835, levelStartTotalPlayed = 0,
                         sessions = { { level = 6, stateSeries = {} } } }

            Ledger.InitCharDB(db)

            assert.is_nil(db.levelStartTotalPlayed)
            assert.are.equal(5835, db.lastKnownTotalTimePlayed)
        end)

        it("keeps a 0 baseline for a character tracked from level 1 (it really had played nothing)", function()
            local db = { version = 7, lastKnownTotalTimePlayed = 900, levelStartTotalPlayed = 0,
                         sessions = { { level = 1, stateSeries = {} } } }

            Ledger.InitCharDB(db)

            assert.are.equal(0, db.levelStartTotalPlayed)
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
