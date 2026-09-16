-- Ledger - core/xp.lua
-- Logica pura: nada de API de WoW aqui. El estado y el tiempo se reciben
-- siempre como parametro, nunca como global. Cargable con lua5.1 a secas.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp.lua")

Ledger.DB_VERSION = 4

Ledger.DEFAULTS = {
    pos           = { point = "CENTER", relativePoint = "CENTER", x = 0, y = 0 },
    shown         = false,
    includeRested = true,
    barShown      = false,
    barHeight     = 8,
    timeBarShown  = false,
}

-- Esquema historico de la serie xp en la version 2 (antes de separar el
-- bono por descanso de la xp base): stride 3, sin campo `rested`. Se
-- congela aqui solo para la migracion v2->v3 de abajo; el esquema
-- vigente es siempre Ledger.SERIES.xp (core/series.lua).
local XP_SERIES_V2 = { key = "e", stride = 3, fields = { "off", "xp", "src" } }

-- Reescribe el array plano de la serie xp de una sesion del stride
-- viejo (3, sin rested) al nuevo (4, con rested = 0 en todo lo
-- existente: no habia forma de saber cuanto de esa xp ya grabada era
-- bono por descanso). Usa los mismos helpers genericos de
-- core/series.lua para leer con el esquema viejo y escribir con el
-- nuevo: si esto no bastara y hiciera falta tocar el array a pelo, es
-- que quedo el stride viejo hardcodeado en alguna parte fuera de
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

-- Migra db de un esquema antiguo al actual (Ledger.DB_VERSION). db.version
-- ausente se trata como version 1 (esquema previo a las series
-- declarativas de core/series.lua, sin campo version).
function Ledger.MigrateDB(db)
    local version = db.version or 1

    if version < 2 then
        -- v1 -> v2: se introduce el campo `version` y el modelo de series
        -- declarativas (Ledger.SERIES). No hay sesiones/niveles
        -- persistidos todavia bajo el esquema v1 que traducir; de
        -- haberlos, aqui es donde se reescribirian sus arrays planos al
        -- key/stride/fields de la serie correspondiente.
        version = 2
    end

    if version < 3 then
        -- v2 -> v3: la serie xp pasa de stride 3 (off, xp, src) a stride
        -- 4 (off, xp, src, rested), para separar el bono por descanso de
        -- la xp base. levels[nivel] no necesita migracion aparte: todavia
        -- no hay ningun cierre de nivel cableado en el juego (ver
        -- CLAUDE.md), asi que no hay curvas ni totales persistidos bajo
        -- el esquema viejo que traducir.
        if db.sessions then
            for _, session in ipairs(db.sessions) do
                MigrateSessionXPSeries(session)
            end
        end
        version = 3
    end

    if version < 4 then
        -- v3 -> v4: se empiezan a alimentar los buckets de tiempo
        -- (core/time_buckets.lua) de verdad, y a persistirlos en
        -- session.buckets (antes de esto ni existia el campo: el
        -- tracker vivia solo en memoria). No hay forma de reconstruir
        -- retroactivamente como se repartio el tiempo ya jugado bajo el
        -- esquema viejo, asi que las sesiones que no traigan `buckets`
        -- se rellenan a cero -- igual que rested=0 en la migracion
        -- v2->v3.
        if db.sessions then
            for _, session in ipairs(db.sessions) do
                if not session.buckets then
                    session.buckets = Ledger.NewEmptyBuckets()
                end
            end
        end
        version = 4
    end

    db.version = version
    return db
end

-- Rellena db con los valores de defaults que falten, sin pisar los que ya
-- hay. db puede venir a nil (primera carga). Migra antes de rellenar, para
-- que la migracion pueda distinguir un esquema viejo de uno recien creado.
-- Devuelve db.
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

-- Estructura completa de LedgerCharDB (por personaje): levels (resumen
-- por nivel, ver core/level_close.lua) y sessions (las sesiones del
-- nivel en curso; la ultima es la activa. Ver core/events.lua y
-- ui/xp_capture.lua).
Ledger.CHAR_DEFAULTS = {
    levels   = {},
    sessions = {},
}

-- Garantiza la estructura completa de LedgerCharDB (version, levels,
-- sessions) a partir de lo que haya en disco, sin pisar nada existente.
-- db puede venir a nil o a medio poblar; la migracion de version se
-- aplica igual que en InitDB.
function Ledger.InitCharDB(db)
    return Ledger.InitDB(db, Ledger.CHAR_DEFAULTS)
end

-- A partir de la xp actual y maxima calcula el texto a mostrar.
-- A nivel maximo, max es 0 (o nil) y no hay porcentaje que mostrar.
function Ledger.FormatXP(cur, max)
    if not max or max == 0 then
        return "Nivel maximo", ""
    end
    local xpText  = string.format("%d / %d", cur, max)
    local pctText = string.format("%.1f%%", cur / max * 100)
    return xpText, pctText
end
