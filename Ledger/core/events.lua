-- Ledger - core/events.lua
-- Acumulador de ganancias de xp sobre la serie "xp" (ver core/series.lua)
-- de una sesion. Logica pura: no usa ninguna API de WoW. El offset se
-- recibe ya calculado (en decimas de segundo) por quien llama.

local ADDON_NAME, Ledger = ...

print("Ledger: core/events.lua")

local XP_SERIES     = Ledger.SERIES.xp
local XP_FIELD      = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local SRC_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "src")
local OFF_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "off")
local RESTED_FIELD  = Ledger.SeriesFieldIndex(XP_SERIES, "rested")

-- Crea una sesion nueva. mode ("farm"|"quest"|"dungeon"|nil) es solo
-- informativo: nunca debe alterar el src de ningun evento. manual marca
-- las sesiones abiertas por /ldg reset; se comportan igual que las
-- demas. buckets (core/time_buckets.lua) empieza a cero: quien lleva la
-- cuenta en caliente (ui/xp_capture.lua) reengancha aqui su tracker en
-- vivo, para que el acumulado sobreviva a /reload igual que el resto de
-- la sesion.
function Ledger.NewSession(t0, nivel, mode, manual)
    return {
        t0      = t0,
        nivel   = nivel,
        mode    = mode,
        manual  = manual or false,
        buckets = Ledger.NewEmptyBuckets(),
        [XP_SERIES.key] = {},
    }
end

-- Añade un evento al final del array plano de la serie xp. rested es la
-- parte de xp que vino del bono por descanso (0 por defecto si se
-- omite). Se recorta a rested = xp si llegara mayor que xp, para que la
-- xp base (xp - rested) nunca pueda salir negativa por un desajuste
-- entre la cantidad (delta de UnitXP) y el bono (extraido del mensaje
-- de chat): son dos señales independientes y no hay garantia externa
-- de que casen.
function Ledger.AddEvent(session, offset, xp, src, rested)
    rested = rested or 0
    if rested > xp then rested = xp end
    Ledger.AppendRecord(session, XP_SERIES, offset, xp, src, rested)
end

-- Numero de eventos registrados.
function Ledger.EventCount(session)
    return Ledger.RecordCount(session, XP_SERIES)
end

-- Xp "efectiva" de un evento segun el toggle includeRested: la xp total
-- tal cual si es true o se omite (por defecto), o sin el bono por
-- descanso (xp - rested) si es false. Nunca negativa: ver AddEvent.
function Ledger.EffectiveXP(xp, rested, includeRested)
    if includeRested == false then
        return xp - rested
    end
    return xp
end

-- Suma de xp de todos los eventos. includeRested (por defecto true)
-- decide si el bono por descanso cuenta en el total: ver EffectiveXP.
function Ledger.TotalXP(session, includeRested)
    local total = 0
    local arr = session[XP_SERIES.key]
    if arr then
        for i = 1, #arr, XP_SERIES.stride do
            local xp     = arr[i + XP_FIELD - 1]
            local rested = arr[i + RESTED_FIELD - 1]
            total = total + Ledger.EffectiveXP(xp, rested, includeRested)
        end
    end
    return total
end

-- Suma del bono por descanso de todos los eventos (siempre el total
-- real acumulado, sin toggle: es precisamente lo que el toggle resta o
-- no del total de arriba).
function Ledger.TotalRested(session)
    local total = 0
    local arr = session[XP_SERIES.key]
    if arr then
        for i = RESTED_FIELD, #arr, XP_SERIES.stride do
            total = total + arr[i]
        end
    end
    return total
end

-- Xp acumulada por codigo de origen: { [src] = xpTotal, ... }
function Ledger.XPBySource(session)
    local bySource = {}
    local arr = session[XP_SERIES.key]
    if arr then
        for i = 1, #arr, XP_SERIES.stride do
            local xp  = arr[i + XP_FIELD - 1]
            local src = arr[i + SRC_FIELD - 1]
            bySource[src] = (bySource[src] or 0) + xp
        end
    end
    return bySource
end

-- Xp acumulada por origen, sumada a lo largo de varias sesiones (p.ej.
-- todas las del nivel en curso, no solo la activa). Sirve para el
-- tooltip de la barra de composicion de xp.
function Ledger.XPBySourceAcrossSessions(sessions)
    local bySource = {}
    for _, session in ipairs(sessions) do
        for src, xp in pairs(Ledger.XPBySource(session)) do
            bySource[src] = (bySource[src] or 0) + xp
        end
    end
    return bySource
end

-- Offset del ultimo evento registrado, o nil si no hay ninguno.
function Ledger.LastOffset(session)
    local arr = session[XP_SERIES.key]
    if not arr or #arr == 0 then return nil end
    return arr[#arr - XP_SERIES.stride + OFF_FIELD]
end
