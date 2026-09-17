-- Ledger - core/xp.lua
-- Pure logic: no WoW API here. State and time are always received as
-- parameters, never as a global. Loadable with plain lua5.1.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp.lua")

Ledger.DB_VERSION = 5

Ledger.DEFAULTS = {
    pos           = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    shown         = false,
    includeRested = true,
    barShown      = false,
    barHeight     = 8,
    timeBarShown  = false,
}

-- Historical schema of the xp series in version 2 (before splitting the
-- rested bonus from the base xp): stride 3, no `rested` field. Frozen
-- here only for the v2->v3 migration below; the current schema is
-- always Ledger.SERIES.xp (core/series.lua).
local XP_SERIES_V2 = { key = "e", stride = 3, fields = { "off", "xp", "src" } }

-- Rewrites a session's flat xp series array from the old stride
-- (3, no rested) to the new one (4, with rested = 0 for everything
-- already there: there was no way to know how much of that already
-- recorded xp was a rested bonus). Uses the same generic helpers from
-- core/series.lua to read with the old schema and write with the new
-- one: if this weren't enough and the array had to be touched raw, it
-- would mean the old stride ended up hardcoded somewhere outside
-- Ledger.SERIES.
local function MigrateSessionXPSeries(session)
    local oldCount = Ledger.RecordCount(session, XP_SERIES_V2)
    if oldCount == 0 then return end

    local records = {}
    for i = 1, oldCount do
        records[i] = Ledger.ReadRecord(session, XP_SERIES_V2, i)
    end

    session[Ledger.SERIES.xp.key] = {}
    for _, record in ipairs(records) do
        Ledger.AppendRecord(session, Ledger.SERIES.xp, record.off, record.xp, record.src, 0)
    end
end

-- v4 -> v5, three changes in the same pass over each session (Real
-- SavedVariables analysis):
--   1) off sometimes carried floating-point rounding decimals
--      ((GetTime()-t0)*10 doesn't always land on an integer); rounded
--      to the nearest tenth of a second.
--   2) src goes from text ("kill", "quest"...) to a numeric ID
--      (Ledger.SRC_IDS, core/series.lua): more compact and stable
--      against name changes. All code outside the persistence
--      boundary keeps using the text name.
--   3) the nivel field is renamed to level (the rest of the schema was
--      already in English).
-- None of the three loses any information: everything is rewritten in
-- place.
local function MigrateSessionToV5(session)
    if session.nivel ~= nil and session.level == nil then
        session.level = session.nivel
        session.nivel = nil
    end
    session.deaths = session.deaths or 0

    local xpSeries = Ledger.SERIES.xp
    local arr = session[xpSeries.key]
    if arr then
        local offIdx = Ledger.SeriesFieldIndex(xpSeries, "off")
        local srcIdx = Ledger.SeriesFieldIndex(xpSeries, "src")
        for i = 1, #arr, xpSeries.stride do
            local off = arr[i + offIdx - 1]
            arr[i + offIdx - 1] = math.floor(off + 0.5)

            local src = arr[i + srcIdx - 1]
            if type(src) == "string" then
                arr[i + srcIdx - 1] = Ledger.SRC_IDS[src] or Ledger.SRC_IDS.unknown
            end
        end
    end
end

-- Migrates db from an old schema to the current one (Ledger.DB_VERSION).
-- A missing db.version is treated as version 1 (the schema before
-- core/series.lua's declarative series, with no version field).
function Ledger.MigrateDB(db)
    local version = db.version or 1

    if version < 2 then
        -- v1 -> v2: introduces the `version` field and the declarative
        -- series model (Ledger.SERIES). No sessions/levels were
        -- persisted yet under the old v1 schema to translate; if there
        -- were, this is where their flat arrays would be rewritten to
        -- the corresponding series' key/stride/fields.
        version = 2
    end

    if version < 3 then
        -- v2 -> v3: the xp series goes from stride 3 (off, xp, src) to
        -- stride 4 (off, xp, src, rested), to split the rested bonus
        -- from the base xp. levels[nivel] needs no separate migration:
        -- level close wasn't wired up in-game yet at this point (see
        -- CLAUDE.md), so there are no curves or totals persisted under
        -- the old schema to translate.
        if db.sessions then
            for _, session in ipairs(db.sessions) do
                MigrateSessionXPSeries(session)
            end
        end
        version = 3
    end

    if version < 4 then
        -- v3 -> v4: the time buckets (core/time_buckets.lua) start
        -- being fed for real, and get persisted in session.buckets
        -- (before this the field didn't even exist: the tracker only
        -- lived in memory). There's no way to reconstruct
        -- retroactively how the already-played time was split under
        -- the old schema, so sessions missing `buckets` get filled
        -- with zero -- same as rested=0 in the v2->v3 migration.
        if db.sessions then
            for _, session in ipairs(db.sessions) do
                if not session.buckets then
                    session.buckets = Ledger.NewEmptyBuckets()
                end
            end
        end
        version = 4
    end

    if version < 5 then
        -- v4 -> v5: see MigrateSessionToV5. Also renames nivel->level
        -- on already-closed levels entries and fills deaths/reached
        -- with 0 if missing (no way to reconstruct them
        -- retroactively, same as rested=0 in v2->v3). t0 remains
        -- GetTime() (client uptime, not absolute) on already-existing
        -- sessions: there's no way to translate it retroactively to
        -- an absolute time() once the correspondence between the two
        -- clocks is lost; only sessions created from this version on
        -- use time().
        if db.sessions then
            for _, session in ipairs(db.sessions) do
                MigrateSessionToV5(session)
            end
        end
        if db.levels then
            for _, entry in pairs(db.levels) do
                if entry.nivel ~= nil and entry.level == nil then
                    entry.level = entry.nivel
                    entry.nivel = nil
                end
                entry.deaths  = entry.deaths or 0
                entry.reached = entry.reached or 0
            end
        end
        version = 5
    end

    db.version = version
    return db
end

-- Fills db with any missing defaults, without overwriting what's
-- already there. db can come in as nil (first load). Migrates before
-- filling, so the migration can tell an old schema apart from a
-- freshly created one. Returns db.
function Ledger.InitDB(db, defaults)
    db = db or {}
    Ledger.MigrateDB(db)
    for k, v in pairs(defaults) do
        if db[k] == nil then
            if type(v) == "table" then
                local copy = {}
                for k2, v2 in pairs(v) do copy[k2] = v2 end
                db[k] = copy
            else
                db[k] = v
            end
        end
    end
    return db
end

-- Full structure of LedgerCharDB (per character): levels (summary per
-- level, see core/level_close.lua) and sessions (the sessions of the
-- level in progress; the last one is active. See core/events.lua and
-- ui/xp_capture.lua). lastKnownTotalTimePlayed is the last total played
-- time of the CHARACTER reported by TIME_PLAYED_MSG (arg1);
-- levelStartTotalPlayed is that same total at the instant tracking of
-- the current level started. A closed level's totalPlayed is the
-- difference between the two (self-correcting against lost sessions:
-- if a login gets skipped, the next TIME_PLAYED_MSG compensates on its
-- own, because the character's total is always exact). See
-- ui/xp_capture.lua.
Ledger.CHAR_DEFAULTS = {
    levels   = {},
    sessions = {},
    lastKnownTotalTimePlayed = 0,
    levelStartTotalPlayed    = 0,
}

-- Guarantees the full structure of LedgerCharDB (version, levels,
-- sessions) from whatever is on disk, without overwriting anything
-- existing. db can come in as nil or half-populated; the version
-- migration is applied the same way as in InitDB.
function Ledger.InitCharDB(db)
    return Ledger.InitDB(db, Ledger.CHAR_DEFAULTS)
end

-- Computes the text to display from the current and max xp.
-- At max level, max is 0 (or nil) and there's no percentage to show.
function Ledger.FormatXP(cur, max)
    if not max or max == 0 then
        return "Max level", ""
    end
    local xpText  = string.format("%d / %d", cur, max)
    local pctText = string.format("%.1f%%", cur / max * 100)
    return xpText, pctText
end
