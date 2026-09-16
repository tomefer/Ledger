-- Ledger - core/xp_gain_matcher.lua
-- La cantidad de una ganancia de xp (delta de UnitXP) y su origen
-- (mensaje de combate) llegan por separado y no siempre en el mismo
-- orden. Este buffer pequeño los empareja por proximidad temporal en vez
-- de asumir que uno llega siempre antes que el otro. Logica pura: no usa
-- ninguna API de WoW, el reloj se recibe siempre como parametro.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_gain_matcher.lua")

-- Segundos maximos entre la señal de cantidad y la de origen para
-- considerar que son el mismo evento de xp. En el juego se ha
-- observado una separacion real de hasta ~0.42s entre PLAYER_XP_UPDATE
-- y CHAT_MSG_COMBAT_XP_GAIN para el mismo golpe; 1.0s deja margen de
-- sobra sin arriesgarse a fundir dos eventos distintos y cercanos.
Ledger.MAX_MATCH_GAP = 1.0

function Ledger.NewMatcher(maxGap)
    return {
        maxGap  = maxGap or Ledger.MAX_MATCH_GAP,
        amounts = {}, -- pendientes de origen: { {t=, xp=}, ... }
        sources = {}, -- pendientes de cantidad: { {t=, src=}, ... }
    }
end

-- Saca de `list` el elemento mas adecuado dentro de maxGap segundos de
-- `t`. Sin `rank`, es simplemente el mas cercano en el tiempo. Con
-- `rank` (function(item) -> numero), gana primero la mayor prioridad y
-- solo se desempata por cercania temporal -- lo usa AddAmount para que
-- una fuente "quest" gane a una "explore" igual de cercana (ver
-- SOURCE_PRIORITY mas abajo). Devuelve nil si no hay ninguno dentro del
-- margen.
local function PopClosest(list, t, maxGap, rank)
    local bestIdx, bestDiff, bestRank
    for i, item in ipairs(list) do
        local diff = math.abs(item.t - t)
        if diff <= maxGap then
            local itemRank = rank and rank(item) or 0
            if not bestIdx or itemRank > bestRank or (itemRank == bestRank and diff < bestDiff) then
                bestIdx, bestDiff, bestRank = i, diff, itemRank
            end
        end
    end
    if not bestIdx then return nil end
    return table.remove(list, bestIdx)
end

-- Prioridad de un origen cuando varias fuentes caen dentro del margen a
-- la vez. "quest" siempre gana: el mensaje generico de entrega de
-- mision ("You gain N experience.") es identico al de exploracion
-- (COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED no puede desambiguarlos por si
-- solo), asi que si QUEST_TURNED_IN esta en la ventana, la xp es de
-- mision, nunca de exploracion. El resto no tiene prioridad entre si:
-- se desempata por cercania temporal como siempre.
local SOURCE_PRIORITY = { quest = 1 }
local function SourceRank(item)
    return SOURCE_PRIORITY[item.src] or 0
end

local function NoopLog() end

-- Describe el contenido de una cola (amounts o sources) para logging:
-- cada elemento con su antigüedad relativa a `now`. Nunca toca ninguna
-- API de WoW; solo formatea la tabla que se le pasa.
local function DescribeQueue(list, now, label)
    if #list == 0 then
        return label .. ": vacia"
    end

    local parts = {}
    for _, item in ipairs(list) do
        local age = now - item.t
        if item.xp then
            table.insert(parts, string.format("{xp=%d, edad=%.3fs}", item.xp, age))
        else
            table.insert(parts, string.format("{src=%s, rested=%d, expectedXP=%s, edad=%.3fs}",
                item.src, item.rested, tostring(item.expectedXP), age))
        end
    end
    return label .. ": " .. table.concat(parts, ", ")
end

-- Registra una cantidad de xp observada en el instante t. Si ya hay un
-- origen pendiente lo suficientemente cercano, devuelve el evento
-- emparejado {t=, xp=, src=, rested=, expectedXP=}; si no, se queda a la
-- espera y devuelve nil. Entre varias fuentes dentro del margen, gana
-- la de mayor prioridad (ver SOURCE_PRIORITY), desempatando por
-- cercania temporal. `log` es opcional: function(level, msg), para
-- instrumentacion. Nunca cambia el resultado, solo lo describe.
function Ledger.AddAmount(matcher, t, xp, log)
    log = log or NoopLog
    log("trace", string.format("AddAmount t=%.3f xp=%d -- %s",
        t, xp, DescribeQueue(matcher.sources, t, "sources")))

    local source = PopClosest(matcher.sources, t, matcher.maxGap, SourceRank)
    if source then
        log("trace", string.format(
            "AddAmount: consumida fuente src=%s rested=%d expectedXP=%s (separacion %.3fs, margen %.3fs) -> emparejado",
            source.src, source.rested, tostring(source.expectedXP), t - source.t, matcher.maxGap))
        return { t = t, xp = xp, src = source.src, rested = source.rested, expectedXP = source.expectedXP }
    end

    log("trace", "AddAmount: ninguna fuente dentro del margen -- se encola la cantidad")
    table.insert(matcher.amounts, { t = t, xp = xp })
    return nil
end

-- Registra un origen observado en el instante t. `rested` es la parte
-- de bono por descanso que trae ese origen (0 por defecto si se omite;
-- ver core/chat_patterns.lua: Ledger.ExtractRestedBonus). `expectedXP`
-- es opcional: la cantidad que la propia fuente reporta de forma
-- independiente al delta de UnitXP (p.ej. el arg2 de QUEST_TURNED_IN),
-- para que quien reciba el emparejamiento pueda hacer una verificacion
-- cruzada; nil si esa fuente no reporta ninguna cantidad propia (los
-- mensajes de combate no la tienen). Si ya hay una cantidad pendiente
-- lo suficientemente cercana, devuelve el evento emparejado {t=, xp=,
-- src=, rested=, expectedXP=} (con el t de la cantidad); si no, se
-- queda a la espera y devuelve nil. `log` es opcional, igual que en
-- AddAmount.
function Ledger.AddSource(matcher, t, src, log, rested, expectedXP)
    log = log or NoopLog
    rested = rested or 0
    log("trace", string.format("AddSource t=%.3f src=%s rested=%d expectedXP=%s -- %s",
        t, src, rested, tostring(expectedXP), DescribeQueue(matcher.amounts, t, "amounts")))

    local amount = PopClosest(matcher.amounts, t, matcher.maxGap)
    if amount then
        log("trace", string.format(
            "AddSource: consumida cantidad xp=%d (separacion %.3fs, margen %.3fs) -> emparejado",
            amount.xp, t - amount.t, matcher.maxGap))
        return { t = amount.t, xp = amount.xp, src = src, rested = rested, expectedXP = expectedXP }
    end

    log("trace", "AddSource: ninguna cantidad dentro del margen -- se encola la fuente")
    table.insert(matcher.sources, { t = t, src = src, rested = rested, expectedXP = expectedXP })
    return nil
end

-- Descarta lo que ya no puede emparejarse porque ha pasado mas de
-- maxGap desde que llego. Las cantidades huerfanas (xp ganado sin
-- mensaje de combate, p.ej. misiones) se devuelven con src = "unknown"
-- y rested = 0 (sin fuente no hay forma de saber si hubo bono) para no
-- perder ese xp; los origenes huerfanos se descartan sin mas, ya que
-- sin cantidad no hay nada que registrar. `log` es opcional, igual que
-- en AddAmount/AddSource.
function Ledger.Flush(matcher, now, log)
    log = log or NoopLog
    local flushed = {}

    for i = #matcher.amounts, 1, -1 do
        local item = matcher.amounts[i]
        local age = now - item.t
        if age > matcher.maxGap then
            log("trace", string.format(
                "Flush: cantidad xp=%d edad=%.3fs supera el margen %.3fs -- se suelta con src=unknown",
                item.xp, age, matcher.maxGap))
            table.remove(matcher.amounts, i)
            table.insert(flushed, { t = item.t, xp = item.xp, src = "unknown", rested = 0 })
        end
    end

    for i = #matcher.sources, 1, -1 do
        local item = matcher.sources[i]
        local age = now - item.t
        if age > matcher.maxGap then
            log("trace", string.format(
                "Flush: fuente src=%s edad=%.3fs supera el margen %.3fs -- se descarta sin cantidad que emparejar",
                item.src, age, matcher.maxGap))
            table.remove(matcher.sources, i)
        end
    end

    return flushed
end
