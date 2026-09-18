describe("core/time_buckets.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        local chunk = assert(loadfile("Ledger/core/time_buckets.lua"))
        chunk("Ledger", Ledger)
    end)

    local function packAll(records)
        local raw = {}
        for i, flags in ipairs(records) do
            raw[i] = Ledger.PackStateFlags(flags)
        end
        return raw
    end

    it("exposes the default thresholds", function()
        assert.are.equal(15, Ledger.DOWNTIME_THRESHOLD)
        assert.are.equal(3, Ledger.SUSTAINED_MOVEMENT_SECONDS)
    end)

    it("NewEmptyBuckets gives all 4 buckets as zero", function()
        assert.are.same({ active = 0, downtime = 0, travel = 0, dead = 0 }, Ledger.NewEmptyBuckets())
    end)

    describe("PackStateFlags / UnpackStateFlags", function()
        it("round-trips every combination of flags", function()
            local combos = {
                {},
                { combat = true },
                { moving = true },
                { dead = true },
                { taxi = true },
                { combat = true, moving = true, dead = true, taxi = true },
                { combat = true, taxi = true },
            }
            for _, flags in ipairs(combos) do
                local unpacked = Ledger.UnpackStateFlags(Ledger.PackStateFlags(flags))
                assert.are.equal(not not flags.combat, unpacked.combat)
                assert.are.equal(not not flags.moving, unpacked.moving)
                assert.are.equal(not not flags.dead, unpacked.dead)
                assert.are.equal(not not flags.taxi, unpacked.taxi)
            end
        end)

        it("packs to 0 when nothing is set", function()
            assert.are.equal(0, Ledger.PackStateFlags({}))
        end)
    end)

    describe("MarkSustainedRuns", function()
        it("a run shorter than the threshold never counts as sustained", function()
            assert.are.same({ false, false, false, false }, Ledger.MarkSustainedRuns({ true, true, false, false }, 3))
        end)

        it("a run that reaches the threshold counts from its very first second", function()
            assert.are.same({ true, true, true, false }, Ledger.MarkSustainedRuns({ true, true, true, false }, 3))
        end)

        it("a run still open at the end of the array counts once it reaches the threshold", function()
            assert.are.same({ false, true, true, true }, Ledger.MarkSustainedRuns({ false, true, true, true }, 3))
        end)

        it("several separate short runs never count", function()
            assert.are.same(
                { false, false, false, false, false },
                Ledger.MarkSustainedRuns({ true, true, false, true, true }, 3))
        end)
    end)

    describe("ComputeBucketsFromState", function()
        it("with no samples, all buckets are zero", function()
            assert.are.same(Ledger.NewEmptyBuckets(), Ledger.ComputeBucketsFromState({}))
        end)

        it("combat counts as active", function()
            local raw = packAll({ { combat = true }, { combat = true } })
            assert.are.equal(2, Ledger.ComputeBucketsFromState(raw).active)
        end)

        it("dead always wins, even mid-combat", function()
            local raw = packAll({ { combat = true, dead = true } })
            local buckets = Ledger.ComputeBucketsFromState(raw)
            assert.are.equal(1, buckets.dead)
            assert.are.equal(0, buckets.active)
        end)

        it("sustained movement counts as travel", function()
            local raw = packAll({ { moving = true }, { moving = true }, { moving = true } })
            assert.are.equal(3, Ledger.ComputeBucketsFromState(raw).travel)
        end)

        it("movement that doesn't reach the sustained window doesn't count as travel", function()
            -- Only 2 consecutive raw-moving seconds (below the default
            -- 3s window) and no combat nearby (downtime=0 forces the
            -- quiet-after-combat grace period off): falls through to
            -- downtime, never travel.
            local raw = packAll({ { moving = true }, { moving = true } })
            local buckets = Ledger.ComputeBucketsFromState(raw, { downtime = 0 })
            assert.are.equal(0, buckets.travel)
            assert.are.equal(2, buckets.downtime)
        end)

        it("taxi counts as travel regardless of movement", function()
            local raw = packAll({ { taxi = true } })
            assert.are.equal(1, Ledger.ComputeBucketsFromState(raw).travel)
        end)

        it("quiet with no combat ever seen counts as downtime, not active", function()
            local raw = packAll({ {}, {}, {} })
            assert.are.equal(3, Ledger.ComputeBucketsFromState(raw).downtime)
        end)

        describe("exact threshold boundary after combat", function()
            it("stays active while still short of the downtime threshold", function()
                -- combat + 3 quiet seconds: max gap seen is 2 seconds,
                -- below the threshold of 3.
                local raw = packAll({ { combat = true }, {}, {}, {} })
                local buckets = Ledger.ComputeBucketsFromState(raw, { downtime = 3 })
                assert.are.equal(4, buckets.active)
                assert.are.equal(0, buckets.downtime)
            end)

            it("switches to downtime the second the threshold is reached", function()
                -- one more quiet second than above: the gap reaches 3,
                -- crossing the threshold on the last sample.
                local raw = packAll({ { combat = true }, {}, {}, {}, {} })
                local buckets = Ledger.ComputeBucketsFromState(raw, { downtime = 3 })
                assert.are.equal(4, buckets.active)
                assert.are.equal(1, buckets.downtime)
            end)
        end)

        it("the sum of buckets always equals the number of samples", function()
            local raw = packAll({
                { combat = true }, {}, { moving = true }, { moving = true }, { moving = true },
                { dead = true }, {}, {}, { taxi = true }, {},
            })
            local buckets = Ledger.ComputeBucketsFromState(raw, { downtime = 2 })
            local total = buckets.active + buckets.downtime + buckets.travel + buckets.dead
            assert.are.equal(#raw, total)
        end)
    end)
end)
