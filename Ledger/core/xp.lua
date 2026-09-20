-- Ledger - core/xp.lua
-- Pure logic: no WoW API here. State and time are always received as
-- parameters, never as a global. Loadable with plain lua5.1.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp.lua")

-- Saved-data schema version. There are NO migrations: if the version
-- found on disk for a character's data differs from this one, that data
-- is wiped and tracking starts clean (see Ledger.InitCharDB). Bump this
-- whenever the shape of LedgerCharDB changes.
Ledger.DB_VERSION = 9

Ledger.DEFAULTS = {
    pos             = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    shown           = false,
    includeRested   = true,
    -- The three views (xp composition bar, activity bar, xp/hour number)
    -- are visible by default. A stored value always wins over these, so a
    -- view hidden on purpose stays hidden (see Ledger.ApplyViewDefaultsOnce
    -- for the one exception).
    barShown        = true,
    barHeight       = 8, -- the activity bar's height, and the xp bar's when not replacing the native one
    -- The xp composition bar takes the native xp bar's place (see
    -- ui/xp_bar.lua); /ldg native turns that off, restoring the native
    -- bar and putting the composition bar back above it. A new key (no
    -- old stamped value to worry about), so InitDB's default just applies.
    replaceNative   = true,
    timeBarShown    = true,
    -- Fallback position/width for the xp composition bar when no
    -- native bar can be found to anchor to (ui/xp_bar.lua:
    -- DegradedAnchor). barDefaultPos is overwritten in LedgerDB once
    -- the player drags the bar in that mode; barDefaultWidth isn't
    -- user-configurable (no resize handle), just a sane fixed size.
    barDefaultPos   = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 120 },
    barDefaultWidth = 200,
    rateShown       = true,
    -- No ratePos default on purpose: nil means "anchor above the xp
    -- bar" (ui/rate_frame.lua: RestoreRatePosition). Only gets set
    -- once the player actually drags the headline number frame.
}

-- Fills db with any missing defaults, without overwriting what's
-- already there, and stamps the current schema version. db can come in
-- as nil (first load). Used as-is for the account-wide LedgerDB, whose
-- fields (UI positions and toggles) don't depend on the data schema, so
-- it is never wiped; per-character data goes through InitCharDB.
-- Returns db.
function Ledger.InitDB(db, defaults)
    db = db or {}
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
    db.version = Ledger.DB_VERSION
    return db
end

-- The view toggles in LedgerDB that default to visible.
Ledger.VIEW_KEYS = { "barShown", "timeBarShown", "rateShown" }

-- One-time reset of the view toggles to their (now visible) defaults.
-- Those three used to default to false, and InitDB stamped that false into
-- LedgerDB on the first load, so on a client that persists SavedVariables
-- a stored false is not a preference: it can't be told apart from a view
-- the player never touched. Without this, the new defaults would never
-- reach anyone who already had a LedgerDB. The marker makes it run once;
-- from then on a stored value is a real choice and always wins. Call it
-- right after InitDB. Returns db.
function Ledger.ApplyViewDefaultsOnce(db)
    if not db.viewDefaultsApplied then
        for _, key in ipairs(Ledger.VIEW_KEYS) do
            db[key] = Ledger.DEFAULTS[key]
        end
        db.viewDefaultsApplied = true
    end
    return db
end

-- Full structure of LedgerCharDB (per character):
--   levels     -- summary per closed level (core/level_close.lua),
--                 indexed by the real level number
--   sessions   -- the sessions of the level in progress; the last one is
--                 the active one (core/events.lua, ui/xp_capture.lua)
--   levelTicks -- the level in progress's activity counters
--                 (core/ticks.lua), incremented live by the sampler; on
--                 close they become that level's entry.ticks
--   played     -- optional: the last /played reading, INFORMATIONAL only
--                 (Ledger.RecordPlayedReading), absent until one arrives
Ledger.CHAR_DEFAULTS = {
    levels   = {},
    sessions = {},
}

-- Guarantees the full structure of LedgerCharDB from whatever is on
-- disk. If there IS saved data and its version isn't the current one,
-- it is wiped completely and rebuilt from scratch -- no migration, no
-- attempt to keep anything. Never silent: returns
--   db, wiped, oldVersion
-- so the caller can tell the player (wiped is true and oldVersion is the
-- version found, nil if the data had none). db can come in as nil or an
-- empty table (a first load): that is not a wipe.
function Ledger.InitCharDB(db)
    local wiped, oldVersion = false, nil
    if db ~= nil and next(db) ~= nil and db.version ~= Ledger.DB_VERSION then
        wiped, oldVersion = true, db.version
        db = nil
    end

    db = Ledger.InitDB(db, Ledger.CHAR_DEFAULTS)
    db.levelTicks = db.levelTicks or Ledger.NewTicks()
    return db, wiped, oldVersion
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
