-- Ledger - core/rate.lua
-- XP/hour rate math and the rate panel's content (headline number +
-- hover panel sections). Pure logic: does not use any WoW API; time and
-- game values arrive as parameters.
--
-- Each metric has exactly ONE source of truth (CLAUDE.md, "Sources of
-- truth"), never mixed inside the same metric:
--   "This session" -- source A, the addon's own record: xp recorded in
--                     the session over time() - session.t0.
--   "This level"   -- source B, the game's API: UnitXP("player") over the
--                     level's played time (last TIME_PLAYED_MSG reading
--                     plus the time elapsed since it arrived).
-- The activity samples (core/ticks.lua) feed the time bar only: nothing
-- in this file reads them.

local ADDON_NAME, Ledger = ...

-- Below this many SECONDS of denominator, an xp/hour rate is too noisy to
-- show as a number: a small denominator makes it spike wildly (50 xp in
-- 5 s reads as 36000 xp/h), and right after a ding the level's numerator
-- is the leftover xp while its denominator is tiny. Ledger.ComputeXPRate
-- returns nil below this threshold; callers show a dash instead. The same
-- threshold applies to anything else derived from a rate (e.g. a time to
-- next level estimate, if the panel ever gets one).
Ledger.RATE_MIN_SECONDS = 60

-- xp/hour = xp * 3600 / seconds. Returns nil (never a distorted number)
-- if either is missing, or seconds is below Ledger.RATE_MIN_SECONDS.
-- xp = 0 with enough seconds is a valid, real rate of 0, not nil: only
-- the denominator being too small triggers the dash, never a small or
-- zero numerator.
function Ledger.ComputeXPRate(xp, seconds)
    if not xp or not seconds or seconds < Ledger.RATE_MIN_SECONDS then
        return nil
    end
    return xp / seconds * 3600
end

-- Classic left-to-right thousands-separator idiom: repeatedly inserts
-- a comma before the last group of 3 digits at the start of the
-- (remaining) numeric string, until no more insertions are possible.
-- Handles a leading "-" via the pattern's optional sign, untouched.
local function AddThousandsSeparator(numStr)
    local formatted = numStr
    while true do
        local withComma, count = formatted:gsub("^(%-?%d+)(%d%d%d)", "%1,%2")
        formatted = withComma
        if count == 0 then break end
    end
    return formatted
end
-- Shared with core/bar_hover.lua (the xp label shown on hover).
Ledger.AddThousandsSeparator = AddThousandsSeparator

-- Formats a duration in seconds for the rate panel: "45s", "12m 05s",
-- "1h 23m" (from an hour up the seconds are noise and are dropped).
-- nil -> "-".
function Ledger.FormatDuration(seconds)
    if not seconds then
        return "-"
    end
    local total = math.max(math.floor(seconds), 0)
    local hours   = math.floor(total / 3600)
    local minutes = math.floor((total % 3600) / 60)
    if hours > 0 then
        return string.format("%dh %02dm", hours, minutes)
    elseif minutes > 0 then
        return string.format("%dm %02ds", minutes, total % 60)
    end
    return string.format("%ds", total)
end

-- Played time of the SESSION: exact, now - session.t0 (both absolute
-- time()). nil if there is no session or it has no t0; never negative
-- (a clock adjustment must not show a negative duration).
function Ledger.SessionPlayedSeconds(session, now)
    if not session or not session.t0 or not now then
        return nil
    end
    return math.max(now - session.t0, 0)
end

-- The last TIME_PLAYED_MSG reading, kept IN MEMORY ONLY (never in
-- LedgerCharDB) together with the level it belongs to and the absolute
-- time() at which it arrived: { level=, seconds=, receivedAt= }. Every
-- new reply builds a fresh ref that REPLACES the previous one -- never
-- accumulated on top of it (a reply after a /reload already includes
-- everything before). nil (no reading) if seconds is not a number.
function Ledger.NewLevelPlayedRef(level, seconds, receivedAt)
    if type(seconds) ~= "number" or not receivedAt then
        return nil
    end
    return { level = level, seconds = seconds, receivedAt = receivedAt }
end

-- Played time of the LEVEL in progress: the server's reading plus the
-- time elapsed since it arrived. nil (shown as a dash, never a 0) while
-- no reply has arrived yet, or if the reading belongs to another level
-- (the counter resets on a ding: until the new reply lands, the old
-- level's time must not be shown as the new one's).
function Ledger.LevelPlayedSeconds(ref, currentLevel, now)
    if not ref or not now or ref.level ~= currentLevel then
        return nil
    end
    return ref.seconds + math.max(now - ref.receivedAt, 0)
end

-- Formats an xp/hour rate for display: a thousands-separated integer
-- with the "xp/h" suffix, or "-" if rate is nil (see
-- Ledger.ComputeXPRate -- denominator too small to be meaningful).
function Ledger.FormatXPRate(rate)
    if not rate then
        return "-"
    end
    local rounded = math.floor(rate + 0.5)
    return AddThousandsSeparator(tostring(rounded)) .. " xp/h"
end

-- Computes both headline rates plus the two denominators they use (the
-- panel shows those as "Played time"):
--   session -- source A: Ledger.TotalXP(session, includeRested) (xp the
--              addon recorded in the active session) over
--              Ledger.SessionPlayedSeconds (time() - t0). Respects the
--              includeRested toggle.
--   level   -- source B: unitXP (UnitXP("player"), read by the caller) over
--              Ledger.LevelPlayedSeconds (the in-memory /played reference
--              plus the time elapsed since it arrived). includeRested does
--              NOT apply: UnitXP already includes the rested bonus and
--              there is no way to split it out.
-- now is an absolute time(); ref is Ledger.levelPlayedRef (nil until the
-- first TIME_PLAYED_MSG reply); currentLevel is UnitLevel("player").
-- Returns { sessionRate=, levelRate=, sessionPlayed=, levelPlayed= }: the
-- rates are numbers or nil (see Ledger.ComputeXPRate), the times seconds
-- or nil.
function Ledger.ComputeHeadlineRates(session, unitXP, ref, currentLevel, now, includeRested)
    local sessionPlayed = Ledger.SessionPlayedSeconds(session, now)
    local levelPlayed   = Ledger.LevelPlayedSeconds(ref, currentLevel, now)
    local sessionXP     = session and Ledger.TotalXP(session, includeRested) or 0

    return {
        sessionRate   = Ledger.ComputeXPRate(sessionXP, sessionPlayed),
        levelRate     = Ledger.ComputeXPRate(unitXP, levelPlayed),
        sessionPlayed = sessionPlayed,
        levelPlayed   = levelPlayed,
    }
end

-- Row colors for the hover panel, 0-1 format like Ledger.PALETTE
-- (ui/palette.lua) -- kept local rather than reusing that table:
-- these are about visual emphasis (the headline row vs. everything
-- else), not xp source/time-bucket identity, and core/ must stay
-- loadable and testable standalone (core/series.lua's hard rule),
-- never depending on anything ui/ defines.
Ledger.RATE_HIGHLIGHT_COLOR = { 1, 1, 1 }       -- white: the session rate, same number as the headline
Ledger.RATE_DEFAULT_COLOR   = { 0.8, 0.8, 0.8 } -- light gray: everything else
Ledger.RATE_NOTE_COLOR      = { 0.6, 0.6, 0.6 } -- dimmer gray: explanatory notes under a section

-- Under the xp/hour rows: says why "This level" ignores the rested toggle.
Ledger.RATE_LEVEL_NOTE = "This level includes rested xp (the game's own xp value can't be split)."

-- Builds the hover panel's content as a list of sections:
-- { { title=, rows = { { label=, value=, color= }, ... }, notes = { "line", ... } }, ... }
-- (notes is optional: plain explanatory lines shown under the rows).
-- Adding a new section later (level history, per-source breakdown...)
-- is just appending another { title=, rows=... } entry here -- the ui/
-- layer (ui/rate_frame.lua) only ever walks this generic shape, never
-- assumes which sections exist, how many there are, or how many rows
-- each one has.
function Ledger.BuildRatePanelSections(rates)
    rates = rates or {}
    local sections = {
        {
            title = "XP/hour",
            rows = {
                { label = "This session", value = Ledger.FormatXPRate(rates.sessionRate), color = Ledger.RATE_HIGHLIGHT_COLOR },
                { label = "This level",   value = Ledger.FormatXPRate(rates.levelRate),   color = Ledger.RATE_DEFAULT_COLOR },
            },
            notes = { Ledger.RATE_LEVEL_NOTE },
        },
    }

    -- Played time of the session and the level: the denominators of the
    -- two rows above (rates.sessionPlayed / rates.levelPlayed, seconds or
    -- nil -- see Ledger.SessionPlayedSeconds / Ledger.LevelPlayedSeconds).
    -- A nil (level reading not received yet) is a dash, never a made-up 0.
    sections[#sections + 1] = {
        title = "Played time",
        rows = {
            { label = "This session", value = Ledger.FormatDuration(rates.sessionPlayed), color = Ledger.RATE_DEFAULT_COLOR },
            { label = "This level",   value = Ledger.FormatDuration(rates.levelPlayed),   color = Ledger.RATE_DEFAULT_COLOR },
        },
    }

    return sections
end
