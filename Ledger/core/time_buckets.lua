-- Ledger - core/time_buckets.lua
-- Accumulates elapsed time into the active, idle, travel and dead
-- buckets from timestamped state samples. Pure logic: does not use any
-- WoW API, the clock is always received as a parameter.
--
-- Retroactive reclassification: if the player stays "active" and
-- `threshold` seconds or more pass without a new combat sample, that
-- whole stretch is counted as "travel" instead of "active" (it wasn't
-- combat, it was travel).

local ADDON_NAME, Ledger = ...

print("Ledger: core/time_buckets.lua")

-- Seconds without combat after which an "active" stretch starts
-- counting as "travel".
Ledger.INACTIVITY_THRESHOLD = 30

-- Common shape of an empty set of buckets, to avoid repeating the
-- literal in core/events.lua (session.buckets), core/level_close.lua
-- (the levels entry's aggregate) and core/xp.lua (migration).
function Ledger.NewEmptyBuckets()
    return { active = 0, idle = 0, travel = 0, dead = 0 }
end

-- Creates a tracker. state is the state in effect starting at t0:
-- "active", "idle", "travel" or "dead". threshold is optional (defaults
-- to Ledger.INACTIVITY_THRESHOLD).
function Ledger.NewTracker(t0, state, threshold)
    return {
        buckets   = Ledger.NewEmptyBuckets(),
        lastT     = t0,
        lastState = state,
        threshold = threshold or Ledger.INACTIVITY_THRESHOLD,
    }
end

-- Which bucket a stretch of `elapsed` seconds that was in `state` goes
-- to: the same one, unless it was "active" and the stretch reaches the
-- threshold, in which case it's reclassified entirely as "travel"
-- (retroactive reclassification). Shared by AddSample (which does
-- mutate the tracker) and PreviewBuckets (which doesn't).
local function ClassifyElapsed(state, elapsed, threshold)
    if state == "active" and elapsed >= threshold then
        return "travel"
    end
    return state
end

-- Records that starting at instant t the state becomes `state`. Closes
-- the previous stretch [lastT, t) and adds it to the bucket it
-- belongs to, applying the retroactive reclassification if it applies.
function Ledger.AddSample(tracker, t, state)
    local elapsed = t - tracker.lastT
    if elapsed > 0 then
        local bucket = ClassifyElapsed(tracker.lastState, elapsed, tracker.threshold)
        tracker.buckets[bucket] = tracker.buckets[bucket] + elapsed
    end
    tracker.lastT     = t
    tracker.lastState = state
end

-- "As of now" preview of the buckets, WITHOUT mutating the tracker: a
-- copy of tracker.buckets with the open stretch [lastT, now) already
-- added to the bucket it would belong to if closed right now (same
-- retroactive reclassification as AddSample). Lets an on-screen bar
-- appear to grow every second without actually closing the stretch on
-- every redraw -- that would break the retroactive reclassification,
-- which needs to see the whole gap at once (see core/xp_capture.lua:
-- the 1s ticker only calls AddSample on real transitions, never on
-- every tick).
function Ledger.PreviewBuckets(tracker, now)
    local preview = {
        active = tracker.buckets.active,
        idle   = tracker.buckets.idle,
        travel = tracker.buckets.travel,
        dead   = tracker.buckets.dead,
    }
    local elapsed = now - tracker.lastT
    if elapsed > 0 then
        local bucket = ClassifyElapsed(tracker.lastState, elapsed, tracker.threshold)
        preview[bucket] = preview[bucket] + elapsed
    end
    return preview
end

-- Decides whether the ongoing "active" stretch needs to be closed
-- because the inactivity clock (time since the last real activity
-- signal: an xp gain or entering combat, whichever is more recent) has
-- gone past the tracker's threshold. Pure logic: mutates nothing,
-- doesn't touch GetTime or any WoW API -- everything is received as a
-- parameter. If true, the caller must close the stretch with
-- Ledger.AddSample(tracker, now, "travel") -- straight to travel, not
-- idle: the whole inactivity gap counts as travel until the next real
-- activity, without splitting it into two buckets depending on the
-- exact instant this ticker happens to fire (see "idle" below, which is
-- a separate state for when it's known that travel is NOT happening,
-- e.g. right after resurrecting).
function Ledger.ShouldTransitionToTravel(tracker, now, lastActivityTime)
    return tracker.lastState == "active" and (now - lastActivityTime) >= tracker.threshold
end
