-- Ledger - core/xp_bar.lua
-- Calcula los segmentos de la barra de composicion de xp del nivel:
-- fusiona registros consecutivos del mismo src en un unico segmento
-- (fusion obligatoria: sin ella son miles de texturas) y calcula la
-- anchura en pixeles de cada uno, proporcional a maxXP. Logica pura: no
-- usa ninguna API de WoW; itera Ledger.SERIES.xp en vez de asumir
-- stride o nombres de campo, por la regla dura de core/series.lua.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_bar.lua")

local XP_SERIES    = Ledger.SERIES.xp
local XP_FIELD     = Ledger.SeriesFieldIndex(XP_SERIES, "xp")
local SRC_FIELD    = Ledger.SeriesFieldIndex(XP_SERIES, "src")
local RESTED_FIELD = Ledger.SeriesFieldIndex(XP_SERIES, "rested")

-- src reservado para el segmento inicial (xp del nivel anterior a que
-- el addon empezara a registrar). No coincide con ningun src real
-- ("kill"/"quest"/"explore"/"unknown"), para que la UI lo distinga sin
-- ambiguedad y lo pinte siempre en gris.
Ledger.BAR_INITIAL_SRC = "previous"

-- Reparte totalWidthPx entre `fractions` (cada una 0..1; no hace falta
-- que sumen 1) sin que la suma de anchuras redondeadas supere nunca
-- totalWidthPx: el redondeo de cada segmento se hace sobre el
-- acumulado ideal, no sobre el segmento suelto, asi que el error de
-- redondeo se compensa entre segmentos consecutivos en vez de
-- acumularse sin control. Expuesta (no local): la reutiliza tambien
-- core/time_bar.lua para la barra de reparto de tiempo.
function Ledger.RoundedWidths(fractions, totalWidthPx)
    local widths = {}
    local idealCumulative, actualCumulative = 0, 0
    for i, fraction in ipairs(fractions) do
        idealCumulative = idealCumulative + fraction * totalWidthPx
        local newActual = math.floor(idealCumulative + 0.5)
        widths[i] = newActual - actualCumulative
        actualCumulative = newActual
    end
    return widths
end

-- Fusiona registros consecutivos del mismo src en un solo segmento
-- (suma xp y rested). Lee flatArray con los campos de Ledger.SERIES.xp,
-- nunca con indices/stride hardcodeados.
local function MergeConsecutive(flatArray)
    local merged = {}
    for i = 1, #flatArray, XP_SERIES.stride do
        local xp     = flatArray[i + XP_FIELD - 1]
        local src    = flatArray[i + SRC_FIELD - 1]
        local rested = flatArray[i + RESTED_FIELD - 1]

        local last = merged[#merged]
        if last and last.src == src then
            last.xp     = last.xp + xp
            last.rested = last.rested + rested
        else
            merged[#merged + 1] = { src = src, xp = xp, rested = rested }
        end
    end
    return merged
end

-- flatArray: array plano de la serie xp (de una sesion, o de varias ya
-- concatenadas en orden cronologico con Ledger.ConcatSeries -- ver
-- core/series.lua). initialXP: xp del nivel anterior a que el addon
-- empezara a registrar (0 o nil si no hay). widthPx: ancho total de la
-- barra, en pixeles. maxXP: UnitXPMax("player") del nivel, la escala
-- del eje X (0..maxXP).
--
-- Devuelve una lista de segmentos en orden: { offset=, width=, src=,
-- restedWidth= } (todo en pixeles; restedWidth <= width siempre, 0 si
-- el segmento no tiene bono por descanso).
function Ledger.ComputeBarSegments(flatArray, initialXP, widthPx, maxXP)
    local merged = MergeConsecutive(flatArray or {})

    if initialXP and initialXP > 0 then
        table.insert(merged, 1, { src = Ledger.BAR_INITIAL_SRC, xp = initialXP, rested = 0 })
    end

    if #merged == 0 or not maxXP or maxXP <= 0 then
        return {}
    end

    local fractions = {}
    for i, segment in ipairs(merged) do
        fractions[i] = segment.xp / maxXP
    end
    local widths = Ledger.RoundedWidths(fractions, widthPx)

    local segments = {}
    local offset = 0
    for i, segment in ipairs(merged) do
        local width = widths[i]
        local restedWidth = 0
        if segment.rested > 0 and segment.xp > 0 then
            restedWidth = math.floor((width * segment.rested / segment.xp) + 0.5)
            if restedWidth > width then restedWidth = width end
        end
        segments[i] = { offset = offset, width = width, src = segment.src, restedWidth = restedWidth }
        offset = offset + width
    end

    return segments
end
