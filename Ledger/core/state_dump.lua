-- Ledger - core/state_dump.lua
-- Text serializer of the in-memory state (active session + closed
-- levels), used both by /ldg debug (panel) and /ldg dump (chat). Pure
-- logic: does not use any WoW API, reads the table it's given, never a
-- SavedVariable directly. Iterates Ledger.SERIES.xp instead of assuming
-- field names or stride, per core/series.lua's hard rule.

local ADDON_NAME, Ledger = ...

print("Ledger: core/state_dump.lua")

local XP_SERIES  = Ledger.SERIES.xp
local MAX_EVENTS = 30

-- offsetTenths is in tenths of a second (see core/events.lua). Format
-- mm:ss.t, with no upper limit on minutes (a session longer than an
-- hour keeps growing: "60:00.0", "125:30.5"...).
local function FormatOffset(offsetTenths)
    local totalTenths = math.floor(offsetTenths + 0.5)
    local seconds = math.floor(totalTenths / 10)
    local tenths  = totalTenths - seconds * 10
    local minutes = math.floor(seconds / 60)
    local secs    = seconds - minutes * 60
    return string.format("%02d:%02d.%d", minutes, secs, tenths)
end
Ledger.FormatOffset = FormatOffset

-- Active session header + up to MAX_EVENTS events, most recent first.
-- session can be nil (no active session).
local function FormatSession(session)
    if not session then
        return "Active session: none"
    end

    local lines = {
        string.format("Active session: level %s, mode %s, manual=%s",
            tostring(session.level), session.mode or "none", tostring(session.manual)),
        string.format("Total XP: %d (rested: %d)", Ledger.TotalXP(session), Ledger.TotalRested(session)),
        "Activity, % of samples: " .. Ledger.FormatTickSummary(session.ticks),
    }

    local count = Ledger.RecordCount(session, XP_SERIES)
    if count == 0 then
        table.insert(lines, "Events: none")
    else
        local from = math.max(1, count - MAX_EVENTS + 1)
        table.insert(lines, string.format("Last events (%d of %d), most recent first:", count - from + 1, count))
        for i = count, from, -1 do
            local record = Ledger.ReadRecord(session, XP_SERIES, i)
            local srcName = Ledger.SRC_NAMES[record.src] or "?"
            table.insert(lines, string.format("  %s | %d | %s | rested=%d",
                FormatOffset(record.off), record.xp, srcName, record.rested))
        end
    end

    return table.concat(lines, "\n")
end
Ledger.FormatSession = FormatSession

-- Summary of already-closed levels (levels[level] = CloseLevel(...)).
local function FormatLevels(levels)
    local levelNumbers = {}
    for level in pairs(levels or {}) do
        table.insert(levelNumbers, level)
    end
    table.sort(levelNumbers)

    if #levelNumbers == 0 then
        return "Closed levels: none"
    end

    local lines = { "Closed levels:" }
    for _, level in ipairs(levelNumbers) do
        local entry = levels[level]
        table.insert(lines, string.format("  level %s: xp=%d, rested=%d, deaths=%d, activity: %s",
            tostring(entry.level), entry.totalXP, entry.totalRested or 0, entry.deaths or 0,
            Ledger.FormatTickSummary(entry.ticks)))
    end
    return table.concat(lines, "\n")
end
Ledger.FormatLevels = FormatLevels

-- Full dump: active session + closed levels. charDB is shaped like
-- LedgerCharDB (sessions, levels); it can come in as nil or empty.
function Ledger.FormatState(charDB)
    charDB = charDB or {}
    local sessions = charDB.sessions or {}
    local session  = sessions[#sessions]

    return table.concat({
        FormatSession(session),
        "",
        FormatLevels(charDB.levels),
    }, "\n")
end
