-- Ledger - core/xp_gain_matcher.lua
-- The amount of an xp gain (UnitXP delta) and its source (a combat
-- message) arrive separately and not always in the same order. This
-- small buffer pairs them up by temporal proximity instead of assuming
-- one always arrives before the other. Pure logic: does not use any
-- WoW API, the clock is always received as a parameter.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_gain_matcher.lua")

-- Maximum seconds between the amount signal and the source signal to
-- consider them the same xp event. In-game, a real gap of up to ~0.42s
-- has been observed between PLAYER_XP_UPDATE and CHAT_MSG_COMBAT_XP_GAIN
-- for the same hit; 1.0s leaves plenty of margin without risking
-- merging two distinct, close-together events.
Ledger.MAX_MATCH_GAP = 1.0

function Ledger.NewMatcher(maxGap)
    return {
        maxGap  = maxGap or Ledger.MAX_MATCH_GAP,
        amounts = {}, -- pending a source: { {t=, xp=}, ... }
        sources = {}, -- pending an amount: { {t=, src=}, ... }
    }
end

-- Pulls out of `list` the best-fitting item within maxGap seconds of
-- `t`. Without `rank`, it's simply the closest one in time. With `rank`
-- (function(item) -> number), the highest priority wins first and ties
-- are only broken by temporal proximity -- used by AddAmount so a
-- "quest" source beats an equally-close "explore" one (see
-- SOURCE_PRIORITY below). Returns nil if none falls within the margin.
local function PopClosest(list, t, maxGap, rank)
    local bestIdx, bestDiff, bestRank
    for i, item in ipairs(list) do
        local diff = math.abs(item.t - t)
        if diff <= maxGap then
            local itemRank = rank and rank(item) or 0
            if not bestIdx or itemRank > bestRank or (itemRank == bestRank and diff < bestDiff) then
                bestIdx, bestDiff, bestRank = i, diff, itemRank
            end
        end
    end
    if not bestIdx then return nil end
    return table.remove(list, bestIdx)
end

-- Priority of a source when several fall within the margin at once.
-- "quest" always wins: the generic quest-turn-in message ("You gain N
-- experience.") is identical to the exploration one
-- (COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED can't disambiguate them on its
-- own), so if a QUEST_TURNED_IN is in the window, the xp is from a
-- quest, never exploration. Nothing else has priority over anything
-- else: ties are broken by temporal proximity as usual.
local SOURCE_PRIORITY = { quest = 1 }
local function SourceRank(item)
    return SOURCE_PRIORITY[item.src] or 0
end

local function NoopLog() end

-- Describes a queue's contents (amounts or sources) for logging: each
-- item with its age relative to `now`. Never touches any WoW API; only
-- formats the table it's given.
local function DescribeQueue(list, now, label)
    if #list == 0 then
        return label .. ": empty"
    end

    local parts = {}
    for _, item in ipairs(list) do
        local age = now - item.t
        if item.xp then
            table.insert(parts, string.format("{xp=%d, age=%.3fs}", item.xp, age))
        else
            table.insert(parts, string.format("{src=%s, rested=%d, expectedXP=%s, age=%.3fs}",
                item.src, item.rested, tostring(item.expectedXP), age))
        end
    end
    return label .. ": " .. table.concat(parts, ", ")
end

-- Records an xp amount observed at instant t. If a source is already
-- pending close enough, returns the paired event {t=, xp=, src=,
-- rested=, expectedXP=, crossing=}; otherwise it waits and returns nil.
-- Among several sources within the margin, the highest-priority one
-- wins (see SOURCE_PRIORITY), breaking ties by temporal proximity.
-- `crossing` is optional: level-up metadata (see core/xp_delta.lua)
-- that travels attached to the amount until it pairs with its source,
-- so whoever receives the event knows it needs to be split in two
-- (old/new level) instead of being recorded whole into just one --
-- without this, the source's real src would never reach the half of
-- the event that opens the new level. `log` is optional:
-- function(level, msg), for instrumentation. Never changes the result,
-- only describes it.
function Ledger.AddAmount(matcher, t, xp, log, crossing)
    log = log or NoopLog
    log("trace", string.format("AddAmount t=%.3f xp=%d -- %s",
        t, xp, DescribeQueue(matcher.sources, t, "sources")))

    local source = PopClosest(matcher.sources, t, matcher.maxGap, SourceRank)
    if source then
        log("trace", string.format(
            "AddAmount: consumed source src=%s rested=%d expectedXP=%s (gap %.3fs, margin %.3fs) -> paired",
            source.src, source.rested, tostring(source.expectedXP), t - source.t, matcher.maxGap))
        return { t = t, xp = xp, src = source.src, rested = source.rested, expectedXP = source.expectedXP, crossing = crossing }
    end

    log("trace", "AddAmount: no source within the margin -- queuing the amount")
    table.insert(matcher.amounts, { t = t, xp = xp, crossing = crossing })
    return nil
end

-- Records a source observed at instant t. `rested` is the rested-bonus
-- portion carried by that source (0 by default if omitted; see
-- core/chat_patterns.lua: Ledger.ExtractRestedBonus). `expectedXP` is
-- optional: the amount the source itself reports independently of the
-- UnitXP delta (e.g. QUEST_TURNED_IN's arg2), so whoever receives the
-- pairing can do a cross-check; nil if that source doesn't report any
-- amount of its own (combat messages don't have one). If an amount is
-- already pending close enough, returns the paired event {t=, xp=,
-- src=, rested=, expectedXP=} (with the amount's t); otherwise it waits
-- and returns nil. `log` is optional, same as in AddAmount. The
-- event's `crossing` (if the amount carries one) travels through to
-- the result as-is: see AddAmount.
function Ledger.AddSource(matcher, t, src, log, rested, expectedXP)
    log = log or NoopLog
    rested = rested or 0
    log("trace", string.format("AddSource t=%.3f src=%s rested=%d expectedXP=%s -- %s",
        t, src, rested, tostring(expectedXP), DescribeQueue(matcher.amounts, t, "amounts")))

    local amount = PopClosest(matcher.amounts, t, matcher.maxGap)
    if amount then
        log("trace", string.format(
            "AddSource: consumed amount xp=%d (gap %.3fs, margin %.3fs) -> paired",
            amount.xp, t - amount.t, matcher.maxGap))
        return { t = amount.t, xp = amount.xp, src = src, rested = rested, expectedXP = expectedXP, crossing = amount.crossing }
    end

    log("trace", "AddSource: no amount within the margin -- queuing the source")
    table.insert(matcher.sources, { t = t, src = src, rested = rested, expectedXP = expectedXP })
    return nil
end

-- Discards whatever can no longer be paired because more than maxGap
-- has passed since it arrived. Orphaned amounts (xp gained with no
-- combat message, e.g. quests) are returned with src = "unknown" and
-- rested = 0 (with no source there's no way to know if there was a
-- bonus) so that xp isn't lost; orphaned sources are simply discarded,
-- since with no amount there's nothing to record. `log` is optional,
-- same as in AddAmount/AddSource.
function Ledger.Flush(matcher, now, log)
    log = log or NoopLog
    local flushed = {}

    for i = #matcher.amounts, 1, -1 do
        local item = matcher.amounts[i]
        local age = now - item.t
        if age > matcher.maxGap then
            log("trace", string.format(
                "Flush: amount xp=%d age=%.3fs exceeds margin %.3fs -- released with src=unknown",
                item.xp, age, matcher.maxGap))
            table.remove(matcher.amounts, i)
            table.insert(flushed, { t = item.t, xp = item.xp, src = "unknown", rested = 0, crossing = item.crossing })
        end
    end

    for i = #matcher.sources, 1, -1 do
        local item = matcher.sources[i]
        local age = now - item.t
        if age > matcher.maxGap then
            log("trace", string.format(
                "Flush: source src=%s age=%.3fs exceeds margin %.3fs -- discarded, no amount to pair with",
                item.src, age, matcher.maxGap))
            table.remove(matcher.sources, i)
        end
    end

    return flushed
end
