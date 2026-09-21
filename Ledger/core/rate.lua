-- Ledger - core/rate.lua
-- XP/hour rate math and the rate panel's content (headline number +
-- hover panel sections). Pure logic: does not use any WoW API.
--
-- The denominator is the number of activity SAMPLES (core/ticks.lua:
-- the ticker's total for a session or for the level), each one counted
-- as one second -- never the wall clock nor the game's /played, so it is
-- "xp per hour of time the addon actually observed" (time with the
-- client not running is not in it, by design). Samples are received as
-- a parameter.
--
-- The "Played time" section of the hover panel is a separate, DISPLAY-ONLY
-- concern: exact clocks (session: now - t0; level: the server's /played
-- reading plus the time elapsed since it arrived), never derived from the
-- samples and never feeding the rate or any other metric nor persisted.

local ADDON_NAME, Ledger = ...

-- Below this many samples, an xp/hour rate is too noisy to show as a
-- number: a small denominator makes it spike wildly (e.g. 50 xp in 5
-- samples reads as 36000 xp/h). Ledger.ComputeXPRate returns nil below
-- this threshold; callers show a dash instead.
Ledger.RATE_MIN_SAMPLES = 60

-- xp/hour = xp * 3600 / samples (one sample = one second). Returns nil
-- (never a distorted number) if samples is missing, non-positive, or
-- below Ledger.RATE_MIN_SAMPLES. xp = 0 with enough samples is a valid,
-- real rate of 0, not nil: only the denominator being too small
-- triggers the dash, never a small or zero numerator.
function Ledger.ComputeXPRate(xp, samples)
    if not xp or not samples or samples < Ledger.RATE_MIN_SAMPLES then
        return nil
    end
    return xp / samples * 3600
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
-- Ledger.ComputeXPRate -- not enough samples to be meaningful).
function Ledger.FormatXPRate(rate)
    if not rate then
        return "-"
    end
    local rounded = math.floor(rate + 0.5)
    return AddThousandsSeparator(tostring(rounded)) .. " xp/h"
end

-- Computes both headline rates directly from session data (never from
-- pre-summed numbers the caller derived): session is the active
-- session alone (its own xp/hour); levelSessions is every session of
-- the current level, active one included, same set the xp composition
-- bar sums (core/events.lua: XPBySourceAcrossSessions). sessionSamples/
-- levelSamples are the total activity samples of the active session and
-- of the level in progress (session.ticks.total / levelTicks.total,
-- core/ticks.lua). includeRested is forwarded to
-- Ledger.TotalXP/TotalXPAcrossSessions for both numbers: same toggle,
-- same meaning, for the session's own rate and the level's.
-- Returns { sessionRate=, levelRate= }, each a number or nil (see
-- Ledger.ComputeXPRate).
function Ledger.ComputeHeadlineRates(session, levelSessions, sessionSamples, levelSamples, includeRested)
    local sessionXP = session and Ledger.TotalXP(session, includeRested) or 0
    local levelXP    = Ledger.TotalXPAcrossSessions(levelSessions or {}, includeRested)

    return {
        sessionRate = Ledger.ComputeXPRate(sessionXP, sessionSamples),
        levelRate   = Ledger.ComputeXPRate(levelXP, levelSamples),
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
        },
    }

    -- Played time of the session and the level: exact clocks, display
    -- only (rates.sessionPlayed / rates.levelPlayed, seconds or nil --
    -- see Ledger.SessionPlayedSeconds / Ledger.LevelPlayedSeconds). A nil
    -- (level reading not received yet) is a dash, never a made-up 0.
    sections[#sections + 1] = {
        title = "Played time",
        rows = {
            { label = "This session", value = Ledger.FormatDuration(rates.sessionPlayed), color = Ledger.RATE_DEFAULT_COLOR },
            { label = "This level",   value = Ledger.FormatDuration(rates.levelPlayed),   color = Ledger.RATE_DEFAULT_COLOR },
        },
    }

    return sections
end
