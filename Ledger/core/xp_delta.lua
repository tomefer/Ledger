-- Ledger - core/xp_delta.lua
-- Computes how much xp was gained between two UnitXP readings, knowing
-- that UnitXP resets to a small value on level-up (so currentXP <
-- previousXP doesn't mean xp was lost, it means the event crosses a
-- ding). Pure logic: does not use any WoW API, everything is received
-- as a parameter. The caller must cache UnitXPMax("player") on every
-- PLAYER_XP_UPDATE (never read it at the instant of the jump: by then
-- it already returns the new level's max, not the old one needed to
-- complete the count).

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_delta.lua")

-- Computes the delta between two readings:
--   previousXP, currentXP       -- UnitXP("player") before/after
--   previousMaxXP               -- UnitXPMax("player") CACHED at the
--                                   previous reading (the old level's)
--   previousLevel, currentLevel -- UnitLevel("player") before/after
--
-- Returns a table:
--   { ok = true,  delta = N, levelsGained = 0|1 }
--   { ok = false, levelsGained = N, reason = "..." }  -- N levels or
--     more at once (no Classic Era API exists for the xp requirement
--     of intermediate levels: no number is invented) or lower xp with
--     no level-up (a case with no valid explanation).
--
-- previousXP/previousLevel being nil (first event, no previous
-- reading) is treated as if nothing happened: delta 0, no level gained.
function Ledger.ComputeXPDelta(previousXP, currentXP, previousMaxXP, previousLevel, currentLevel)
    previousXP = previousXP or currentXP
    previousLevel = previousLevel or currentLevel
    local levelsGained = currentLevel - previousLevel

    if levelsGained == 0 then
        if currentXP < previousXP then
            return {
                ok = false,
                levelsGained = 0,
                reason = string.format(
                    "currentXP (%d) is lower than previousXP (%d) with no level-up detected: case with no valid explanation, delta not computed",
                    currentXP, previousXP),
            }
        end
        return { ok = true, delta = currentXP - previousXP, levelsGained = 0 }
    end

    if levelsGained == 1 then
        -- The xp that was missing to complete the old level (with its
        -- cached max) plus the xp already gained in the new level.
        -- Both parts are exposed separately (crossing.oldPart/newPart,
        -- which sum exactly to delta) so whoever records them can
        -- split the event into two entries -- one that closes the old
        -- level, another that opens the new one -- instead of
        -- attributing the whole gain to just one of the two levels.
        -- oldMax is the xp the old level required (its cached max): it
        -- travels with the crossing so the level-close entry can record
        -- it (entry.xpRequired) and /ldg check can verify the level's
        -- recorded xp against it -- there is no API to ask for it once
        -- the ding has happened.
        local oldPart = previousMaxXP - previousXP
        local newPart = currentXP
        return {
            ok = true,
            delta = oldPart + newPart,
            levelsGained = 1,
            crossing = {
                oldPart  = oldPart,
                newPart  = newPart,
                oldLevel = previousLevel,
                newLevel = currentLevel,
                oldMax   = previousMaxXP,
            },
        }
    end

    return {
        ok = false,
        levelsGained = levelsGained,
        reason = string.format(
            "jump of %d levels in a single PLAYER_XP_UPDATE: no Classic Era API exists for the xp requirement of intermediate levels, delta not computable",
            levelsGained),
    }
end

-- An xp event already paired with its source (paired: {xp=, rested=,
-- crossing={oldPart=,newPart=,...}}, see core/xp_gain_matcher.lua) may
-- cross a ding: this function computes how to split it into two
-- entries -- the one that completes the old level, the one that opens
-- the new one -- that SUM EXACTLY to the original paired.xp and
-- paired.rested, without losing or gaining anything to rounding.
-- rested is split proportionally between the two parts (rounding the
-- old one to the nearest integer); the new one always takes whatever
-- is left over, it's never computed separately. Pure logic: does not
-- use any WoW API and does not decide where each part gets recorded,
-- only how much each one gets.
function Ledger.SplitCrossingEvent(paired)
    local crossing = paired.crossing
    local oldPart, newPart = crossing.oldPart, crossing.newPart

    local restedOld = 0
    if paired.rested and paired.rested > 0 and paired.xp > 0 then
        restedOld = math.floor(paired.rested * oldPart / paired.xp + 0.5)
        if restedOld > oldPart then restedOld = oldPart end
    end
    local restedNew = (paired.rested or 0) - restedOld

    return {
        old = { xp = oldPart, rested = restedOld },
        new = { xp = newPart, rested = restedNew },
    }
end
