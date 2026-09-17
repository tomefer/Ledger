describe("core/time_buckets.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        local chunk = assert(loadfile("Ledger/core/time_buckets.lua"))
        chunk("Ledger", Ledger)
    end)

    it("exposes the default threshold", function()
        assert.are.equal(30, Ledger.INACTIVITY_THRESHOLD)
    end)

    it("NewEmptyBuckets gives all 4 buckets as zero", function()
        assert.are.same({ active = 0, idle = 0, travel = 0, dead = 0 }, Ledger.NewEmptyBuckets())
    end)

    -- The rest of the tests pass an explicit threshold (180) instead
    -- of depending on Ledger.INACTIVITY_THRESHOLD's default value:
    -- that way they don't break if that default changes again
    -- later.

    describe("exact threshold", function()
        it("reclassifies active as travel when the gap equals the threshold", function()
            local t = Ledger.NewTracker(0, "active", 180)
            Ledger.AddSample(t, 180, "idle")

            assert.are.equal(0, t.buckets.active)
            assert.are.equal(180, t.buckets.travel)
        end)
    end)

    describe("short stretch that doesn't cross it", function()
        it("keeps the stretch as active if it doesn't reach the threshold", function()
            local t = Ledger.NewTracker(0, "active", 180)
            Ledger.AddSample(t, 50, "idle")

            assert.are.equal(50, t.buckets.active)
            assert.are.equal(0, t.buckets.travel)
        end)
    end)

    describe("travel-combat-travel sequence", function()
        it("counts combat as active and long gaps as travel", function()
            local t = Ledger.NewTracker(0, "travel", 180)

            Ledger.AddSample(t, 50, "active")   -- 50s of travel
            Ledger.AddSample(t, 55, "active")   -- 5s of combat (short gap)
            Ledger.AddSample(t, 60, "active")   -- 5s of combat (short gap)
            Ledger.AddSample(t, 260, "travel")  -- 200s without combat: gets reclassified
            Ledger.AddSample(t, 300, "idle")    -- 40s more of travel

            assert.are.equal(10, t.buckets.active)
            assert.are.equal(290, t.buckets.travel)
        end)
    end)

    describe("inactivity gap after a kill, counted entirely as travel", function()
        it("kills, waits 190s (above the threshold), kills again: the 190s are travel, not split with idle", function()
            local t = Ledger.NewTracker(0, "active", 180) -- t=0: instant of kill 1

            -- The ui/xp_capture.lua ticker detects at 180s of inactivity
            -- that a transition is due, and calls AddSample with
            -- "travel" (never "idle") -- exactly once.
            Ledger.AddSample(t, 180, "travel")  -- transition at 180s
            Ledger.AddSample(t, 190, "active")  -- kill 2, 190s after kill 1

            assert.are.equal(190, t.buckets.travel)
            assert.are.equal(0, t.buckets.idle)
        end)
    end)

    describe("sum of buckets", function()
        it("equals the total elapsed time", function()
            local t = Ledger.NewTracker(1000, "idle")

            Ledger.AddSample(t, 1030, "active")
            Ledger.AddSample(t, 1050, "active")
            Ledger.AddSample(t, 1550, "dead")
            Ledger.AddSample(t, 1565, "travel")
            Ledger.AddSample(t, 1600, "idle")

            local total = t.buckets.active + t.buckets.idle + t.buckets.travel + t.buckets.dead
            assert.are.equal(1600 - 1000, total)
        end)
    end)

    describe("PreviewBuckets", function()
        it("doesn't mutate the tracker", function()
            local t = Ledger.NewTracker(0, "active", 180)
            Ledger.PreviewBuckets(t, 50)

            assert.are.equal(0, t.lastT)
            assert.are.equal("active", t.lastState)
            assert.are.equal(0, t.buckets.active)
        end)

        it("adds the open stretch to the current state's bucket", function()
            local t = Ledger.NewTracker(0, "idle", 180)
            Ledger.AddSample(t, 10, "active") -- 10s of idle already closed
            local preview = Ledger.PreviewBuckets(t, 15) -- 5s of active still open

            assert.are.equal(10, preview.idle)
            assert.are.equal(5, preview.active)
            -- the real tracker hasn't been touched
            assert.are.equal(0, t.buckets.active)
        end)

        it("applies the same retroactive reclassification as AddSample", function()
            local t = Ledger.NewTracker(0, "active", 180)
            local preview = Ledger.PreviewBuckets(t, 200) -- 200s >= threshold(180)

            assert.are.equal(0, preview.active)
            assert.are.equal(200, preview.travel)
        end)

        it("with the open stretch still short, doesn't reclassify", function()
            local t = Ledger.NewTracker(0, "active", 180)
            local preview = Ledger.PreviewBuckets(t, 50)

            assert.are.equal(50, preview.active)
            assert.are.equal(0, preview.travel)
        end)
    end)

    describe("ShouldTransitionToTravel", function()
        it("false if the current state isn't active", function()
            local t = Ledger.NewTracker(0, "idle", 180)
            assert.is_false(Ledger.ShouldTransitionToTravel(t, 500, 0))
        end)

        it("false if the inactivity clock hasn't reached the threshold", function()
            local t = Ledger.NewTracker(0, "active", 180)
            assert.is_false(Ledger.ShouldTransitionToTravel(t, 179, 0))
        end)

        it("true right when reaching the threshold", function()
            local t = Ledger.NewTracker(0, "active", 180)
            assert.is_true(Ledger.ShouldTransitionToTravel(t, 180, 0))
        end)

        it("uses lastActivityTime, not the tracker's lastT", function()
            local t = Ledger.NewTracker(0, "active", 180)
            t.lastT = 1000 -- recent last sample...
            -- ...but the last real activity (xp/combat) was long ago
            assert.is_true(Ledger.ShouldTransitionToTravel(t, 1000, 800))
        end)
    end)
end)
