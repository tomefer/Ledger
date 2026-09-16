-- Ledger - core/series.lua
-- Declara las series temporales del modelo de datos (arrays planos
-- dentro de una sesion) y da los helpers genericos para leerlas y
-- escribirlas. Logica pura: no usa ninguna API de WoW.
--
-- Anadir una serie nueva (oro, reputacion, loot de recoleccion...) es
-- una entrada mas en Ledger.SERIES; ni el serializador ni el panel de
-- depuracion (ni nada de core/) deben referenciar el nombre de campo ni
-- el stride de una serie concreta.

local ADDON_NAME, Ledger = ...

print("Ledger: core/series.lua")

Ledger.SERIES = {
    xp = { key = "e", stride = 4, fields = { "off", "xp", "src", "rested" } },
    -- xp: xp es la xp TOTAL del evento (delta de UnitXP); rested es la
    -- parte de esa xp que vino del bono por descanso (0 si no hubo
    -- bono). Se cumple siempre xp - rested >= 0 (ver core/events.lua:
    -- AddEvent, que recorta rested si llegara mayor que xp).
    -- futuras: gold (stride 3), rep (stride 4, con campo faction),
    --          loot (stride 3).
}

-- Indice (1-based) del campo `name` dentro de un registro de la serie,
-- o nil si esa serie no tiene ese campo.
function Ledger.SeriesFieldIndex(seriesDef, name)
    for i, field in ipairs(seriesDef.fields) do
        if field == name then return i end
    end
    return nil
end

-- Anade un registro (stride valores, en el orden de seriesDef.fields) al
-- array plano de la serie dentro de session.
function Ledger.AppendRecord(session, seriesDef, ...)
    local arr = session[seriesDef.key]
    if not arr then
        arr = {}
        session[seriesDef.key] = arr
    end

    local values = { ... }
    for i = 1, seriesDef.stride do
        arr[#arr + 1] = values[i]
    end
end

-- Numero de registros almacenados.
function Ledger.RecordCount(session, seriesDef)
    local arr = session[seriesDef.key]
    if not arr then return 0 end
    return #arr / seriesDef.stride
end

-- Devuelve el registro `index` (1-based) como tabla con nombre de campo,
-- o nil si no existe.
function Ledger.ReadRecord(session, seriesDef, index)
    local arr = session[seriesDef.key]
    if not arr then return nil end

    local base = (index - 1) * seriesDef.stride
    if index < 1 or base + seriesDef.stride > #arr then return nil end

    local record = {}
    for i, field in ipairs(seriesDef.fields) do
        record[field] = arr[base + i]
    end
    return record
end

-- Concatena el array plano de una serie de varias sesiones, en el orden
-- dado (se asume cronologico: `sessions` ya viene ordenado por quien
-- llama, como la lista real de sesiones de un nivel). Sirve para
-- agregar datos de TODAS las sesiones de un nivel en vez de solo la
-- activa (p.ej. la barra de composicion de xp).
function Ledger.ConcatSeries(sessions, seriesDef)
    local combined = {}
    for _, session in ipairs(sessions) do
        local arr = session[seriesDef.key]
        if arr then
            for _, value in ipairs(arr) do
                combined[#combined + 1] = value
            end
        end
    end
    return combined
end
