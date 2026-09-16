-- Ledger - core/state_dump.lua
-- Serializador a texto del estado en memoria (sesion activa + niveles
-- cerrados), usado tanto por /ldg debug (panel) como por /ldg dump
-- (chat). Logica pura: no usa ninguna API de WoW, lee la tabla que se le
-- pasa, nunca un SavedVariable directamente. Itera Ledger.SERIES.xp en
-- vez de asumir nombres de campo o stride, por la regla dura de
-- core/series.lua.

local ADDON_NAME, Ledger = ...

print("Ledger: core/state_dump.lua")

local XP_SERIES  = Ledger.SERIES.xp
local MAX_EVENTS = 30

-- offsetTenths esta en decimas de segundo (ver core/events.lua). Formato
-- mm:ss.t, sin limite de minutos (una sesion de mas de una hora sigue
-- creciendo: "60:00.0", "125:30.5"...).
local function FormatOffset(offsetTenths)
    local totalTenths = math.floor(offsetTenths + 0.5)
    local seconds = math.floor(totalTenths / 10)
    local tenths  = totalTenths - seconds * 10
    local minutes = math.floor(seconds / 60)
    local secs    = seconds - minutes * 60
    return string.format("%02d:%02d.%d", minutes, secs, tenths)
end
Ledger.FormatOffset = FormatOffset

-- Cabecera de la sesion activa + hasta MAX_EVENTS eventos, del mas
-- reciente al mas antiguo. session puede ser nil (sin sesion activa).
local function FormatSession(session)
    if not session then
        return "Sesion activa: ninguna"
    end

    local lines = {
        string.format("Sesion activa: nivel %s, modo %s, manual=%s",
            tostring(session.nivel), session.mode or "ninguno", tostring(session.manual)),
        string.format("XP total: %d (de descanso: %d)", Ledger.TotalXP(session), Ledger.TotalRested(session)),
    }

    local count = Ledger.RecordCount(session, XP_SERIES)
    if count == 0 then
        table.insert(lines, "Eventos: ninguno")
    else
        local from = math.max(1, count - MAX_EVENTS + 1)
        table.insert(lines, string.format("Ultimos eventos (%d de %d), mas reciente primero:", count - from + 1, count))
        for i = count, from, -1 do
            local record = Ledger.ReadRecord(session, XP_SERIES, i)
            table.insert(lines, string.format("  %s | %d | %s | descanso=%d",
                FormatOffset(record.off), record.xp, record.src, record.rested))
        end
    end

    return table.concat(lines, "\n")
end
Ledger.FormatSession = FormatSession

-- Resumen de niveles ya cerrados (levels[nivel] = CloseLevel(...)).
local function FormatLevels(levels)
    local niveles = {}
    for nivel in pairs(levels or {}) do
        table.insert(niveles, nivel)
    end
    table.sort(niveles)

    if #niveles == 0 then
        return "Niveles cerrados: ninguno"
    end

    local lines = { "Niveles cerrados:" }
    for _, nivel in ipairs(niveles) do
        local entry = levels[nivel]
        table.insert(lines, string.format("  nivel %s: xp=%d, descanso=%d, tiempo=%ds",
            tostring(entry.nivel), entry.totalXP, entry.totalRested or 0, entry.totalPlayed))
    end
    return table.concat(lines, "\n")
end
Ledger.FormatLevels = FormatLevels

-- Volcado completo: sesion activa + niveles cerrados. charDB tiene la
-- forma de LedgerCharDB (sessions, levels); puede venir a nil o vacio.
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
