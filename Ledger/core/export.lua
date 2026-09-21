-- Ledger - core/export.lua
-- Serializes LedgerCharDB (the character's full session/level history)
-- to JSON or CSV, for /ldg export. Pure logic: does not use any WoW
-- API, reads the table it's given, never a SavedVariable directly.
--
-- No JSON library is available in the addon sandbox and no external
-- dependency can be added, so JSON is hand-written from a handful of
-- low-level primitives (Ledger.JSONString/JSONNumber/JSONEscapeString)
-- instead of a generic encoder: every call site already knows whether
-- it's building an object or an array, so there's no "is this empty
-- table an array or an object" guessing involved anywhere.

local ADDON_NAME, Ledger = ...

local XP_SERIES    = Ledger.SERIES.xp

-- Above this many raw xp events (summed across every in-progress
-- session), a detailed export gets big enough to make the export
-- panel's EditBox sluggish (roughly 40-50 bytes per event in JSON,
-- so ~1000 events keeps the events section under ~50KB). Past this
-- threshold, ExportJSON/ExportCSV drop the raw per-event rows and
-- keep only each session's aggregates (event count, total xp, rested,
-- breakdown by source) -- still everything needed to sanity-check the
-- character's history, just not replayable event by event.
Ledger.EXPORT_MAX_EVENTS = 1000

----------------------------------------------------------------------
-- JSON primitives
----------------------------------------------------------------------

local JSON_SPECIAL_ESCAPES = {
    ["\\"] = "\\\\",
    ["\""] = "\\\"",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
}

local function EscapeJSONChar(c)
    return JSON_SPECIAL_ESCAPES[c] or string.format("\\u%04x", c:byte())
end

-- Escapes backslash, double quote and every control character (0x00-
-- 0x1F) the way JSON requires. Does NOT add the surrounding quotes:
-- see Ledger.JSONString.
function Ledger.JSONEscapeString(s)
    return (tostring(s):gsub('[%z\1-\31\\"]', EscapeJSONChar))
end

-- A quoted, escaped JSON string.
function Ledger.JSONString(s)
    return '"' .. Ledger.JSONEscapeString(s) .. '"'
end

-- A JSON number. %.14g avoids both scientific notation and trailing
-- ".0" noise for the integer-valued xp/time fields this addon deals
-- in, while still round-tripping fractional values exactly enough.
function Ledger.JSONNumber(n)
    return string.format("%.14g", n)
end


----------------------------------------------------------------------
-- CSV primitives (RFC 4180-ish: quote a field that contains a comma,
-- quote or newline, doubling up any quote inside it).
----------------------------------------------------------------------

function Ledger.CSVEscapeField(value)
    local s = tostring(value)
    if s:find('[,"\n\r]') then
        s = '"' .. s:gsub('"', '""') .. '"'
    end
    return s
end

function Ledger.CSVRow(fields)
    local escaped = {}
    for i, v in ipairs(fields) do
        escaped[i] = Ledger.CSVEscapeField(v)
    end
    return table.concat(escaped, ",")
end

----------------------------------------------------------------------
-- Shared intermediate model: decodes LedgerCharDB's raw shape (numeric
-- src IDs, flat event arrays, level entries keyed by number) into
-- plain Lua tables that both ExportJSON and ExportCSV render from, so
-- neither format has to re-derive totals or re-translate src on its
-- own.
----------------------------------------------------------------------

local function CountEvents(sessions)
    local total = 0
    for _, session in ipairs(sessions) do
        total = total + Ledger.RecordCount(session, XP_SERIES)
    end
    return total
end

function Ledger.BuildExportModel(charDB)
    charDB = charDB or {}
    local sessions = charDB.sessions or {}
    local totalEventCount = CountEvents(sessions)
    local includeEvents = totalEventCount <= Ledger.EXPORT_MAX_EVENTS

    local model = {
        version                  = charDB.version or 0,
        includeEvents            = includeEvents,
        totalEventCount          = totalEventCount,
        levels                   = {},
        sessions                 = {},
    }

    local levelNumbers = {}
    for level in pairs(charDB.levels or {}) do
        levelNumbers[#levelNumbers + 1] = level
    end
    table.sort(levelNumbers)

    for _, level in ipairs(levelNumbers) do
        local entry = charDB.levels[level]
        model.levels[#model.levels + 1] = {
            level       = entry.level,
            reached     = entry.reached or 0,
            totalXP     = entry.totalXP or 0,
            totalRested = entry.totalRested or 0,
            deaths      = entry.deaths or 0,
            bySource    = entry.bySource or {},
            curve       = entry.curve or {},
            ticks       = entry.ticks or Ledger.NewTicks(),
        }
    end

    for index, session in ipairs(sessions) do
        local sessionModel = {
            index       = index,
            t0          = session.t0,
            tEnd        = session.tEnd,
            level       = session.level,
            mode        = session.mode,
            manual      = session.manual or false,
            deaths      = session.deaths or 0,
            reached     = session.reached or 0,
            initialXP   = session.initialXP or 0,
            ticks       = session.ticks or Ledger.NewTicks(),
            eventCount  = Ledger.RecordCount(session, XP_SERIES),
            totalXP     = Ledger.TotalXP(session),
            totalRested = Ledger.TotalRested(session),
            bySource    = Ledger.XPBySource(session),
        }

        if includeEvents then
            sessionModel.events = {}
            local count = Ledger.RecordCount(session, XP_SERIES)
            for i = 1, count do
                local record = Ledger.ReadRecord(session, XP_SERIES, i)
                sessionModel.events[#sessionModel.events + 1] = {
                    off    = record.off,
                    xp     = record.xp,
                    src    = Ledger.SRC_NAMES[record.src] or "unknown",
                    rested = record.rested,
                }
            end
        end

        model.sessions[#model.sessions + 1] = sessionModel
    end

    return model
end

----------------------------------------------------------------------
-- JSON export
----------------------------------------------------------------------

-- Fixed key order (never derived from pairs(), which has no stable
-- order in Lua): keeps the output deterministic, which is both nicer
-- to read and easier to test.
local BY_SOURCE_ORDER = { "kill", "quest", "explore", "unknown" }

local function JSONBySource(bySource)
    local parts = {}
    for _, name in ipairs(BY_SOURCE_ORDER) do
        if bySource[name] then
            parts[#parts + 1] = Ledger.JSONString(name) .. ":" .. Ledger.JSONNumber(bySource[name])
        end
    end
    return "{" .. table.concat(parts, ",") .. "}"
end

-- The activity counters as they are stored (counts of samples, never a
-- percentage): each activity in Ledger.TICK_KEYS order, then the total.
local function JSONTicks(ticks)
    local parts = {}
    for _, key in ipairs(Ledger.TICK_KEYS) do
        parts[#parts + 1] = Ledger.JSONString(key) .. ":" .. Ledger.JSONNumber(ticks[key] or 0)
    end
    parts[#parts + 1] = '"total":' .. Ledger.JSONNumber(ticks.total or 0)
    return "{" .. table.concat(parts, ",") .. "}"
end

local function JSONNumberArray(list)
    local parts = {}
    for i, n in ipairs(list) do
        parts[i] = Ledger.JSONNumber(n)
    end
    return "[" .. table.concat(parts, ",") .. "]"
end

local function JSONEvent(e)
    return string.format('{"off":%s,"xp":%s,"src":%s,"rested":%s}',
        Ledger.JSONNumber(e.off), Ledger.JSONNumber(e.xp), Ledger.JSONString(e.src), Ledger.JSONNumber(e.rested))
end

local function JSONLevel(entry)
    return string.format(
        '{"level":%s,"reached":%s,"totalXP":%s,"totalRested":%s,"deaths":%s,"bySource":%s,"curve":%s,"ticks":%s}',
        Ledger.JSONNumber(entry.level), Ledger.JSONNumber(entry.reached), Ledger.JSONNumber(entry.totalXP),
        Ledger.JSONNumber(entry.totalRested), Ledger.JSONNumber(entry.deaths),
        JSONBySource(entry.bySource), JSONNumberArray(entry.curve), JSONTicks(entry.ticks))
end

local function JSONSession(s)
    local parts = {
        '"index":' .. Ledger.JSONNumber(s.index),
        '"t0":' .. Ledger.JSONNumber(s.t0),
        '"tEnd":' .. (s.tEnd and Ledger.JSONNumber(s.tEnd) or "null"),
        '"level":' .. Ledger.JSONNumber(s.level),
        '"mode":' .. (s.mode and Ledger.JSONString(s.mode) or "null"),
        '"manual":' .. tostring(s.manual),
        '"deaths":' .. Ledger.JSONNumber(s.deaths),
        '"reached":' .. Ledger.JSONNumber(s.reached),
        '"initialXP":' .. Ledger.JSONNumber(s.initialXP),
        '"ticks":' .. JSONTicks(s.ticks),
        '"eventCount":' .. Ledger.JSONNumber(s.eventCount),
        '"totalXP":' .. Ledger.JSONNumber(s.totalXP),
        '"totalRested":' .. Ledger.JSONNumber(s.totalRested),
        '"bySource":' .. JSONBySource(s.bySource),
    }

    if s.events then
        local events = {}
        for i, e in ipairs(s.events) do
            events[i] = JSONEvent(e)
        end
        parts[#parts + 1] = '"events":[' .. table.concat(events, ",") .. ']'
    end

    return "{" .. table.concat(parts, ",") .. "}"
end

-- Full JSON dump of charDB (shaped like LedgerCharDB). "includeEvents"
-- tells the reader whether "events" is present on each session or was
-- dropped for size (see Ledger.EXPORT_MAX_EVENTS); "totalEventCount"
-- is always the real count either way.
function Ledger.ExportJSON(charDB)
    local model = Ledger.BuildExportModel(charDB)

    local levels = {}
    for i, entry in ipairs(model.levels) do
        levels[i] = JSONLevel(entry)
    end

    local sessions = {}
    for i, s in ipairs(model.sessions) do
        sessions[i] = JSONSession(s)
    end

    return string.format(
        '{"version":%s,"includeEvents":%s,"totalEventCount":%s,"levels":[%s],"sessions":[%s]}',
        Ledger.JSONNumber(model.version),
        tostring(model.includeEvents),
        Ledger.JSONNumber(model.totalEventCount),
        table.concat(levels, ","),
        table.concat(sessions, ","))
end

----------------------------------------------------------------------
-- CSV export: three sections (levels / sessions / events), each with
-- its own header row, separated by a blank line and a "# name"
-- comment -- CSV has no native concept of multiple tables in one
-- file, this is the lightest convention that stays readable pasted
-- into a spreadsheet and easy to split back apart. Session rows
-- always carry their aggregates (eventCount/totalXP/totalRested), so
-- dropping the events section for size never loses that summary.
----------------------------------------------------------------------

function Ledger.ExportCSV(charDB)
    local model = Ledger.BuildExportModel(charDB)
    local lines = {}

    table.insert(lines, "# levels")
    table.insert(lines, Ledger.CSVRow({
        "level", "reached", "totalXP", "totalRested", "deaths",
        "ticks_combat", "ticks_nonCombat", "ticks_travel", "ticks_dead", "ticks_total",
    }))
    for _, entry in ipairs(model.levels) do
        local t = entry.ticks
        table.insert(lines, Ledger.CSVRow({
            entry.level, entry.reached, entry.totalXP, entry.totalRested, entry.deaths,
            t.combat, t.nonCombat, t.travel, t.dead, t.total,
        }))
    end

    table.insert(lines, "")
    table.insert(lines, "# sessions")
    table.insert(lines, Ledger.CSVRow({
        "session_index", "level", "t0", "tEnd", "mode", "manual", "deaths", "reached", "initialXP",
        "eventCount", "totalXP", "totalRested",
        "ticks_combat", "ticks_nonCombat", "ticks_travel", "ticks_dead", "ticks_total",
    }))
    for _, s in ipairs(model.sessions) do
        local t = s.ticks
        table.insert(lines, Ledger.CSVRow({
            s.index, s.level, s.t0, s.tEnd or "", s.mode or "", tostring(s.manual), s.deaths, s.reached,
            s.initialXP, s.eventCount, s.totalXP, s.totalRested,
            t.combat, t.nonCombat, t.travel, t.dead, t.total,
        }))
    end

    table.insert(lines, "")
    if model.includeEvents then
        table.insert(lines, "# events")
        table.insert(lines, Ledger.CSVRow({ "session_index", "level", "off", "xp", "src", "rested" }))
        for _, s in ipairs(model.sessions) do
            for _, e in ipairs(s.events) do
                table.insert(lines, Ledger.CSVRow({ s.index, s.level, e.off, e.xp, e.src, e.rested }))
            end
        end
    else
        table.insert(lines, string.format(
            "# events omitted: %d events exceed the export threshold (%d) -- see each session's eventCount/totalXP/totalRested above",
            model.totalEventCount, Ledger.EXPORT_MAX_EVENTS))
    end

    return table.concat(lines, "\n")
end
