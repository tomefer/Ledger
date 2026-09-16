-- Ledger - core/level_close.lua
-- Cierra un nivel: agrega las sesiones que le pertenecen en la entrada de
-- `levels` del modelo de datos (totales, desglose por origen y curva de
-- xp por minuto). Logica pura: no usa ninguna API de WoW.
--
-- Las sesiones ya deben venir recortadas por quien llama a la del nivel
-- que corresponda: si una sesion real abarca dos niveles, se le pasan por
-- separado los dos trozos de su array de eventos, uno por cada cierre de
-- nivel. Esta funcion no detecta ni corta esos limites, solo agrega lo
-- que se le da.
--
-- totalPlayed se recibe ya calculado (p.ej. sumando los buckets de
-- core/time_buckets.lua de las sesiones del nivel); esta funcion no lo
-- calcula.

local ADDON_NAME, Ledger = ...

print("Ledger: core/level_close.lua")

local XP_SERIES    = Ledger.SERIES.xp
local OFF_FIELD    = Ledger.SeriesFieldIndex(XP_SERIES, "off")
local XP_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local RESTED_FIELD = Ledger.SeriesFieldIndex(XP_SERIES, "rested")

-- offset esta en decimas de segundo; 1 minuto = 600 decimas.
local TENTHS_PER_MINUTE = 600

-- Suma la xp efectiva (ver Ledger.EffectiveXP, respeta includeRested) de
-- cada evento de la sesion al minuto (relativo al t0 de esa sesion) al
-- que pertenece, acumulando en minuteXP. Devuelve el minuto mas alto
-- tocado, para poder densificar la curva despues.
local function AddToCurve(minuteXP, session, includeRested)
    local arr = session[XP_SERIES.key]
    if not arr then return 0 end

    local maxMinute = 0
    for i = 1, #arr, XP_SERIES.stride do
        local offset = arr[i + OFF_FIELD - 1]
        local xp     = arr[i + XP_FIELD - 1]
        local rested = arr[i + RESTED_FIELD - 1]
        local minute = math.floor(offset / TENTHS_PER_MINUTE) + 1
        minuteXP[minute] = (minuteXP[minute] or 0) + Ledger.EffectiveXP(xp, rested, includeRested)
        if minute > maxMinute then
            maxMinute = minute
        end
    end
    return maxMinute
end

-- includeRested (por defecto true) decide si el bono por descanso cuenta
-- en totalXP y en curve (ver Ledger.EffectiveXP); nunca afecta a
-- totalRested, que es siempre el acumulado real del bono, ni a
-- bySource, que sigue siendo el desglose de la xp total tal cual.
function Ledger.CloseLevel(sessions, totalPlayed, includeRested)
    local totalXP     = 0
    local totalRested = 0
    local bySource    = {}
    local minuteXP    = {}
    local maxMinute   = 0
    local buckets     = Ledger.NewEmptyBuckets()

    for _, session in ipairs(sessions) do
        totalXP     = totalXP + Ledger.TotalXP(session, includeRested)
        totalRested = totalRested + Ledger.TotalRested(session)

        for src, xp in pairs(Ledger.XPBySource(session)) do
            bySource[src] = (bySource[src] or 0) + xp
        end

        if session.buckets then
            for bucket, seconds in pairs(session.buckets) do
                buckets[bucket] = (buckets[bucket] or 0) + seconds
            end
        end

        local sessionMaxMinute = AddToCurve(minuteXP, session, includeRested)
        if sessionMaxMinute > maxMinute then
            maxMinute = sessionMaxMinute
        end
    end

    local curve = {}
    for minute = 1, maxMinute do
        curve[minute] = minuteXP[minute] or 0
    end

    return {
        nivel       = sessions[1].nivel,
        totalXP     = totalXP,
        totalRested = totalRested,
        totalPlayed = totalPlayed,
        bySource    = bySource,
        curve       = curve,
        buckets     = buckets,
    }
end

-- Registra en `db` (con la forma de LedgerCharDB) el resultado de cerrar
-- un nivel. Garantiza que db.levels existe en vez de asumirlo, para que
-- ningun llamador tenga que indexar esa clave a pelo.
function Ledger.RecordLevelClose(db, entry)
    db.levels = db.levels or {}
    db.levels[entry.nivel] = entry
end
