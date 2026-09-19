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

-- Retention window for QUEST_TURNED_IN sources specifically, longer
-- than MAX_MATCH_GAP. Confirmed in-game (2026-09-18): some turn-ins
-- were seen classified as "explore" not because of a tie-break
-- problem (SOURCE_PRIORITY already makes "quest" win a tie) but a
-- temporal one -- the generic "You gain N experience." chat message
-- (queued as a competing "explore" source, see
-- core/chat_patterns.lua: Ledger.ClassifyXPGainMatch) or the delta's
-- own PLAYER_XP_UPDATE could get paired away before QUEST_TURNED_IN's
-- source ever arrived or was checked. Quest turn-ins are infrequent
-- (no risk of pairing with the wrong one the way a burst of kills
-- would), so it's safe to let a quest source wait longer -- especially
-- now that AddAmount/AddSource match it by its exact expectedXP first
-- (see below), which removes any ambiguity a longer window could
-- otherwise introduce.
Ledger.QUEST_MATCH_GAP = 3.0

function Ledger.NewMatcher(maxGap, questGap)
    return {
        maxGap   = maxGap or Ledger.MAX_MATCH_GAP,
        questGap = questGap or Ledger.QUEST_MATCH_GAP,
        amounts  = {}, -- pending a source: { {t=, xp=}, ... }
        sources  = {}, -- pending an amount: { {t=, src=}, ... }
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

-- Scans `list` in arrival order for the first item satisfying
-- `predicate(item)` and removes+returns it (FIFO among ties -- e.g.
-- two quest turn-ins awarding the same xp: the first one queued pairs
-- with the first matching amount, not an arbitrary one). Returns nil
-- if nothing matches. Unlike PopClosest, this never checks the time
-- gap -- callers that need one bake it into `predicate`.
local function PopFirstMatch(list, predicate)
    for i, item in ipairs(list) do
        if predicate(item) then
            return table.remove(list, i)
        end
    end
    return nil
end

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

    -- Quantity match first, ignoring the time gap entirely: a source
    -- that reports its own amount (QUEST_TURNED_IN, or an area-discovery
    -- message) is exact, so if it matches this delta there's no
    -- ambiguity to break by proximity, however many milliseconds (or
    -- seconds, within the source's retention -- see Flush) separate
    -- them. Only then falls through to the FIFO/temporal rule below,
    -- which is what kills still rely on.
    local exactSource = PopFirstMatch(matcher.sources, function(item)
        return item.expectedXP == xp
    end)
    if exactSource then
        log("trace", string.format(
            "AddAmount: %s source expectedXP=%d matches xp=%d exactly (gap %.3fs, ignored) -> paired",
            exactSource.src, exactSource.expectedXP, xp, t - exactSource.t))
        return { t = t, xp = xp, src = exactSource.src, rested = exactSource.rested, expectedXP = exactSource.expectedXP, crossing = crossing }
    end

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

    -- Symmetric to AddAmount's quantity match: a source with a known
    -- expectedXP (quest, exploration) pairs with a pending amount of
    -- that exact value regardless of the time gap between them.
    if expectedXP then
        local amount = PopFirstMatch(matcher.amounts, function(item)
            return item.xp == expectedXP
        end)
        if amount then
            log("trace", string.format(
                "AddSource: %s expectedXP=%d matches pending amount xp=%d exactly (gap %.3fs, ignored) -> paired",
                src, expectedXP, amount.xp, t - amount.t))
            return { t = amount.t, xp = amount.xp, src = src, rested = rested, expectedXP = expectedXP, crossing = amount.crossing }
        end
    end

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

-- Whether a pending "quest" source already explains this xp better
-- than exploration would -- see core/chat_patterns.lua:
-- Ledger.ClassifyXPGainMatch, which can't tell a quest turn-in and
-- real exploration apart from the chat text alone (both produce "You
-- gain N experience."). Called from the CHAT_MSG_COMBAT_XP_GAIN
-- handler (ui/xp_capture.lua) before it queues a message classified
-- "explore" as a competing source: if QUEST_TURNED_IN's own source
-- already arrived (queued here moments earlier, or about to be), that
-- source is what should pair with the xp, not this message.
--
-- `amount` is the xp figure captured from the message's own text, if
-- any (the "explore" global string still carries a %d -- see
-- ui/xp_capture.lua: HandleCombatXPGainMessage); nil if the message
-- matched no variant at all. Checked in order: an exact match against
-- a pending quest's expectedXP wins outright (reliable regardless of
-- how the two arrived); failing that, the mere presence of ANY
-- pending quest source still counts -- an entry with no exact-amount
-- match might just be one whose amount we couldn't read from the
-- message, not proof this really is exploration. Only when no quest
-- source is pending at all does this return false. A peek, not a pop:
-- doesn't touch the queue, the actual pairing still happens through
-- AddAmount/AddSource so the bookkeeping stays single-sourced there.
-- `log` is optional, same contract as the rest of this file.
function Ledger.HasPendingQuestSource(matcher, t, amount, log)
    log = log or NoopLog
    log("trace", string.format("ExploreCheck t=%.3f amount=%s -- %s",
        t, amount and tostring(amount) or "unknown", DescribeQueue(matcher.sources, t, "sources")))

    local pendingQuest = false
    for _, item in ipairs(matcher.sources) do
        if item.src == "quest" then
            pendingQuest = true
            if amount and item.expectedXP == amount then
                log("trace", string.format(
                    "ExploreCheck: quest source expectedXP=%s matches amount exactly -- not exploration, deferring to it",
                    tostring(item.expectedXP)))
                return true
            end
            log("trace", string.format(
                "ExploreCheck: quest source expectedXP=%s doesn't match amount=%s by value (age %.3fs) -- still pending by mere presence",
                tostring(item.expectedXP), amount and tostring(amount) or "unknown", t - item.t))
        end
    end

    if pendingQuest then
        log("trace", "ExploreCheck: no exact amount match, but a quest source is still pending -- not exploration")
        return true
    end

    log("trace", "ExploreCheck: no quest source pending -- genuine exploration")
    return false
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
        -- Quest sources get their own, longer retention (questGap):
        -- see Ledger.QUEST_MATCH_GAP above for why.
        local retention = (item.src == "quest") and matcher.questGap or matcher.maxGap
        if age > retention then
            log("trace", string.format(
                "Flush: source src=%s age=%.3fs exceeds margin %.3fs -- discarded, no amount to pair with",
                item.src, age, retention))
            table.remove(matcher.sources, i)
        end
    end

    return flushed
end
