-- Ledger - core/time_bar.lua
-- Calcula los segmentos de la barra de reparto de tiempo del nivel: los
-- 4 buckets de core/time_buckets.lua (active, travel, idle, dead) en un
-- orden fijo, con ancho proporcional a su parte del tiempo total. A
-- diferencia de la barra de xp, aqui el eje es siempre el 100% del
-- ancho (no hay maximo externo ni xp previa): no es comparable pixel a
-- pixel con la barra de xp, son ejes distintos. Logica pura: no usa
-- ninguna API de WoW.

local ADDON_NAME, Ledger = ...

print("Ledger: core/time_bar.lua")

-- Orden fijo de izquierda a derecha, siempre el mismo -- para que la
-- forma sea reconocible de un vistazo, nunca reordenado por tamaño.
Ledger.TIME_BUCKET_ORDER = { "active", "travel", "idle", "dead" }

local function TotalSeconds(buckets)
    return buckets.active + buckets.travel + buckets.idle + buckets.dead
end

-- buckets: { active=, travel=, idle=, dead= } (segundos). widthPx:
-- ancho total de la barra. Devuelve una lista en Ledger.TIME_BUCKET_ORDER:
-- { bucket=, offset=, width= } (offset/width en pixeles). Si el total
-- es 0 (nivel recien empezado, sin ninguna muestra todavia), no hay
-- segmentos que dibujar.
function Ledger.ComputeTimeBarSegments(buckets, widthPx)
    local total = TotalSeconds(buckets)
    if total <= 0 then
        return {}
    end

    local fractions = {}
    for i, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        fractions[i] = buckets[bucket] / total
    end
    local widths = Ledger.RoundedWidths(fractions, widthPx)

    local segments = {}
    local offset = 0
    for i, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        local width = widths[i]
        segments[i] = { bucket = bucket, offset = offset, width = width }
        offset = offset + width
    end
    return segments
end

local BUCKET_LABELS = {
    active = "Combate",
    travel = "Viaje",
    idle   = "Inactivo",
    dead   = "Muerto",
}

-- Formatea segundos como hh:mm:ss (sin limite de horas).
function Ledger.FormatHHMMSS(totalSeconds)
    totalSeconds = math.floor(totalSeconds + 0.5)
    local h = math.floor(totalSeconds / 3600)
    local m = math.floor((totalSeconds % 3600) / 60)
    local s = totalSeconds % 60
    return string.format("%02d:%02d:%02d", h, m, s)
end

-- Contenido del tooltip de la barra de tiempo: una entrada por bucket
-- (en Ledger.TIME_BUCKET_ORDER) con su tiempo absoluto en hh:mm:ss y su
-- porcentaje del total. Devuelve una lista de { bucket=, text= } -- el
-- color de cada linea lo decide quien la pinte (ui/), este fichero no
-- sabe nada de colores ni de GameTooltip. Si el total es 0, el
-- porcentaje de cada bucket es 0 (no divide por cero).
function Ledger.FormatTimeBarTooltip(buckets)
    local total = TotalSeconds(buckets)
    local lines = {}
    for _, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        local seconds = buckets[bucket]
        local pct = total > 0 and (seconds / total * 100) or 0
        lines[#lines + 1] = {
            bucket = bucket,
            text = string.format("%s: %s (%.1f%%)", BUCKET_LABELS[bucket], Ledger.FormatHHMMSS(seconds), pct),
        }
    end
    return lines
end
