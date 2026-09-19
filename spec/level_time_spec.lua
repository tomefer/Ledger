describe("core/level_time.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/series.lua"))("Ledger", Ledger)
        assert(loadfile("Ledger/core/time_bar.lua"))("Ledger", Ledger) -- Ledger.FormatHHMMSS
        assert(loadfile("Ledger/core/level_time.lua"))("Ledger", Ledger)
    end)

    local function Ids(violations)
        local ids = {}
        for i, v in ipairs(violations) do ids[i] = v.id end
        return ids
    end

    -- A curve with `n` one-per-minute entries.
    local function Curve(n)
        local curve = {}
        for i = 1, n do curve[i] = 10 end
        return curve
    end

    describe("SumBuckets", function()
        it("adds every bucket", function()
            assert.are.equal(2527, Ledger.SumBuckets({ active = 796, downtime = 289, travel = 1442, dead = 0 }))
        end)

        it("counts a missing table as 0", function()
            assert.are.equal(0, Ledger.SumBuckets(nil))
        end)
    end)

    describe("a level whose numbers are consistent", function()
        it("has no violations (real level 9: played 2552, dings 2552 apart, buckets 2527, curve 43)", function()
            local entry = { totalPlayed = 2552, curve = Curve(43),
                            buckets = { active = 796, downtime = 289, travel = 1442, dead = 0 } }

            assert.are.same({}, Ledger.LevelTimeViolations(entry, 2552))
        end)

        it("played below the time between dings is fine on its own (logged-out time)", function()
            local entry = { totalPlayed = 900, curve = Curve(10), buckets = { active = 800 } }

            assert.are.same({}, Ledger.LevelTimeViolations(entry, 5000))
        end)
    end)

    describe("1) never more than the time between the two dings", function()
        it("flags played above elapsed + tolerance (real level 8: 10405 vs 530)", function()
            local entry = { totalPlayed = 10405, curve = Curve(9),
                            buckets = { active = 110, downtime = 136, travel = 280, dead = 0 } }

            local v = Ledger.LevelTimeViolations(entry, 530)

            assert.is_true(Ledger.LevelTimeViolations(entry, 530)[1].id == "exceeds-elapsed")
            assert.is_not_nil(v[1].text:find("played 02:53:25 > 00:08:50 between dings", 1, true))
        end)

        it("allows exactly the tolerance, flags one second more", function()
            local entry = { totalPlayed = 1000 + Ledger.TIME_TOLERANCE, curve = Curve(5) }
            assert.are.same({}, Ledger.LevelTimeViolations(entry, 1000))

            entry.totalPlayed = 1000 + Ledger.TIME_TOLERANCE + 1
            assert.are.same({ "exceeds-elapsed" }, Ids(Ledger.LevelTimeViolations(entry, 1000)))
        end)

        it("is skipped when elapsed is unknown", function()
            local entry = { totalPlayed = 10405, curve = Curve(9), buckets = { active = 526 } }

            assert.are.same({}, Ledger.LevelTimeViolations(entry, nil))
        end)
    end)

    describe("2) never less than the sum of the buckets", function()
        it("flags played below the sampled seconds (real level 6: 373 vs 2391)", function()
            local entry = { totalPlayed = 373, curve = Curve(1),
                            buckets = { active = 800, downtime = 200, travel = 1391, dead = 0 } }

            local v = Ledger.LevelTimeViolations(entry, 2405)

            assert.are.same({ "below-samples" }, Ids(v))
            assert.is_not_nil(v[1].text:find("played 00:06:13 < 00:39:51 sampled in game", 1, true))
        end)

        it("the sampler running a bit short of the real time (4-25s in real data) is not a violation", function()
            -- level 9: played is the real 2552, sampled 2527
            local entry = { totalPlayed = 2552, curve = Curve(43), buckets = { active = 2527 } }

            assert.are.same({}, Ledger.LevelTimeViolations(entry, 2552))
        end)

        it("allows exactly the tolerance, flags one second more", function()
            local entry = { totalPlayed = 1000, curve = Curve(5), buckets = { active = 1000 + Ledger.TIME_TOLERANCE } }
            assert.are.same({}, Ledger.LevelTimeViolations(entry, 5000))

            entry.buckets.active = 1000 + Ledger.TIME_TOLERANCE + 1
            assert.are.same({ "below-samples" }, Ids(Ledger.LevelTimeViolations(entry, 5000)))
        end)
    end)

    describe("3) the xp curve must fit in the played time", function()
        it("flags 41 minute entries for a played time of 6 minutes (real level 6)", function()
            local entry = { totalPlayed = 373, curve = Curve(41) }

            local v = Ledger.LevelTimeViolations(entry, 2405)

            assert.are.same({ "curve-too-long" }, Ids(v))
            assert.is_not_nil(v[1].text:find("spans 41 minutes but played is only 00:06:13", 1, true))
        end)

        it("accepts the tight real cases (played 2552 -> 43 entries, 1124 -> 19, 856 -> 15, 530 -> 9)", function()
            assert.are.same({}, Ledger.LevelTimeViolations({ totalPlayed = 2552, curve = Curve(43) }, 2552))
            assert.are.same({}, Ledger.LevelTimeViolations({ totalPlayed = 1124, curve = Curve(19) }, 1124))
            assert.are.same({}, Ledger.LevelTimeViolations({ totalPlayed = 856,  curve = Curve(15) }, 856))
            assert.are.same({}, Ledger.LevelTimeViolations({ totalPlayed = 530,  curve = Curve(9) }, 530))
        end)

        it("a level with no curve has nothing to violate", function()
            assert.are.same({}, Ledger.LevelTimeViolations({ totalPlayed = 100 }, 100))
        end)
    end)

    describe("an unknown totalPlayed", function()
        it("has nothing to check, whatever else the entry says", function()
            local entry = { totalPlayed = nil, timeUnreliable = true, curve = Curve(41),
                            buckets = { active = 5000 } }

            assert.are.same({}, Ledger.LevelTimeViolations(entry, 10))
        end)
    end)

    describe("several violations at once", function()
        it("reports each of them (real level 9 as the old build recorded it: 531)", function()
            local entry = { totalPlayed = 531, curve = Curve(43),
                            buckets = { active = 796, downtime = 289, travel = 1442, dead = 0 } }

            local v = Ledger.LevelTimeViolations(entry, 2552)

            assert.are.same({ "below-samples", "curve-too-long" }, Ids(v))
        end)
    end)
end)
