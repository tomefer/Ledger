-- Ledger - core/time_buckets.lua
-- Raw per-second state sampling (combat/moving/dead/taxi flags, packed
-- into one integer per second -- Ledger.SERIES.state, core/series.lua)
-- plus the pure aggregation rules that turn that raw series into the 4
-- time buckets (active, downtime, travel, dead). Pure logic: does not
-- use any WoW API, the samples are always received as a parameter.
--
-- Split on purpose: the raw per-second sample is what actually gets
-- persisted, but only for the level in progress (session.stateSeries).
-- There is no live tracker object: buckets are always DERIVED from the
-- raw series, on demand, by Ledger.ComputeBucketsFromState -- so the
-- live bar always reflects today's thresholds. When a level closes
-- (core/level_close.lua) its buckets are aggregated once, the raw
-- series is DISCARDED, and the thresholds that produced those buckets
-- are stored next to them (entry.thresholds) so two closed levels can
-- be checked for comparability.

local ADDON_NAME, Ledger = ...

print("Ledger: core/time_buckets.lua")

-- Seconds without a combat sample, while quiet, after which a stretch
-- stops counting as a normal gap between pulls ("active") and starts
-- counting as real downtime. UMBRAL_CORTO.
Ledger.DOWNTIME_THRESHOLD = 15

-- Consecutive raw-moving seconds (GetUnitSpeed > 0) needed before a
-- movement run counts as travel -- filters out brief repositioning or a
-- Sprint proc, which shouldn't register as travel.
Ledger.SUSTAINED_MOVEMENT_SECONDS = 3

-- Common shape of an empty set of buckets, to avoid repeating the
-- literal in core/level_close.lua (a level entry's aggregate) and
-- core/xp.lua (migration).
function Ledger.NewEmptyBuckets()
    return { active = 0, downtime = 0, travel = 0, dead = 0 }
end

----------------------------------------------------------------------
-- Packing: one raw per-second sample is 4 booleans (combat, moving,
-- dead, taxi) packed into a single integer as a sum of powers of two --
-- Lua 5.1 has no bitwise operators, so membership is tested with
-- arithmetic (floor division + modulo) instead of a real bitwise AND.
----------------------------------------------------------------------

local FLAG_COMBAT = 1
local FLAG_MOVING = 2
local FLAG_DEAD   = 4
local FLAG_TAXI   = 8

local function HasFlag(value, flag)
    return math.floor(value / flag) % 2 == 1
end

-- flags: { combat=, moving=, dead=, taxi= } (any missing/false entry
-- counts as unset). Returns the packed integer.
function Ledger.PackStateFlags(flags)
    local value = 0
    if flags.combat then value = value + FLAG_COMBAT end
    if flags.moving then value = value + FLAG_MOVING end
    if flags.dead   then value = value + FLAG_DEAD   end
    if flags.taxi   then value = value + FLAG_TAXI   end
    return value
end

-- Inverse of PackStateFlags: { combat=, moving=, dead=, taxi= }, all
-- real booleans (never nil).
function Ledger.UnpackStateFlags(value)
    return {
        combat = HasFlag(value, FLAG_COMBAT),
        moving = HasFlag(value, FLAG_MOVING),
        dead   = HasFlag(value, FLAG_DEAD),
        taxi   = HasFlag(value, FLAG_TAXI),
    }
end

----------------------------------------------------------------------
-- Aggregation rules
----------------------------------------------------------------------

-- Given a flat list of booleans (one per second, e.g. the raw "moving"
-- flag of every sample), returns a parallel list of booleans: true for
-- every second that belongs to a run of at least `sustainedSeconds`
-- CONSECUTIVE true values. The whole run is marked true once it's long
-- enough to be confirmed -- not just from the Nth second onward -- so a
-- real travel stretch doesn't lose its first couple of seconds; a run
-- that never reaches the threshold (repositioning, a Sprint proc) stays
-- false throughout. A run still open at the end of the list is judged
-- by its length so far.
function Ledger.MarkSustainedRuns(rawFlags, sustainedSeconds)
    local n = #rawFlags
    local result = {}
    for i = 1, n do result[i] = false end

    local runStart = nil
    for i = 1, n do
        if rawFlags[i] then
            runStart = runStart or i
        elseif runStart then
            if (i - runStart) >= sustainedSeconds then
                for j = runStart, i - 1 do result[j] = true end
            end
            runStart = nil
        end
    end
    if runStart and (n - runStart + 1) >= sustainedSeconds then
        for j = runStart, n do result[j] = true end
    end

    return result
end

-- Aggregates a raw per-second state series (a flat list of packed
-- integers, see Ledger.SERIES.state -- one record per second, index
-- encodes the time) into the 4 buckets. thresholds is an optional
-- table: { downtime = seconds, sustainedMovement = seconds }, each
-- defaulting to the constants above. This is the ONLY place bucket
-- membership is decided; calling it again on the same raw data with
-- different thresholds just gives the buckets those thresholds imply.
--
-- Priority per second, highest first: dead always wins (even mid-fight,
-- a corpse isn't "active"); then combat itself; then sustained movement
-- or being on a taxi (travel); the remainder is either a short quiet
-- gap right after combat (still "active", a normal pause between
-- pulls) or real downtime.
function Ledger.ComputeBucketsFromState(rawArray, thresholds)
    thresholds = thresholds or {}
    local downtimeThreshold  = thresholds.downtime or Ledger.DOWNTIME_THRESHOLD
    local sustainedSeconds   = thresholds.sustainedMovement or Ledger.SUSTAINED_MOVEMENT_SECONDS

    local n = #rawArray
    local buckets = Ledger.NewEmptyBuckets()
    if n == 0 then return buckets end

    local combatFlags = {}
    local movingRaw   = {}
    local deadFlags   = {}
    local taxiFlags   = {}
    for i = 1, n do
        local flags = Ledger.UnpackStateFlags(rawArray[i])
        combatFlags[i] = flags.combat
        movingRaw[i]   = flags.moving
        deadFlags[i]   = flags.dead
        taxiFlags[i]   = flags.taxi
    end

    local sustainedMoving = Ledger.MarkSustainedRuns(movingRaw, sustainedSeconds)

    local secondsSinceCombat = nil
    for i = 1, n do
        local bucket
        if deadFlags[i] then
            bucket = "dead"
        elseif combatFlags[i] then
            bucket = "active"
        elseif sustainedMoving[i] or taxiFlags[i] then
            bucket = "travel"
        elseif secondsSinceCombat ~= nil and secondsSinceCombat < downtimeThreshold then
            bucket = "active"
        else
            bucket = "downtime"
        end

        buckets[bucket] = buckets[bucket] + 1

        if combatFlags[i] then
            secondsSinceCombat = 0
        elseif secondsSinceCombat ~= nil then
            secondsSinceCombat = secondsSinceCombat + 1
        end
    end

    return buckets
end
