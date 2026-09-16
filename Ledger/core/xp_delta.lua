-- Ledger - core/xp_delta.lua
-- Calcula cuanta xp se ha ganado entre dos lecturas de UnitXP, sabiendo
-- que UnitXP se reinicia a un valor pequeño al subir de nivel (por lo
-- que xpActual < xpAnterior no significa que se haya perdido xp, sino
-- que el evento cruza un ding). Logica pura: no usa ninguna API de WoW,
-- todo se recibe como parametro. Quien llama debe cachear
-- UnitXPMax("player") en cada PLAYER_XP_UPDATE (nunca leerlo en el
-- instante del salto: para entonces ya devuelve el maximo del nivel
-- nuevo, no el del viejo que hace falta para completar la cuenta).

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_delta.lua")

-- Calcula el delta entre dos muestras:
--   previousXP, currentXP       -- UnitXP("player") antes/despues
--   previousMaxXP               -- UnitXPMax("player") CACHEADO en la
--                                   muestra anterior (el del nivel viejo)
--   previousLevel, currentLevel -- UnitLevel("player") antes/despues
--
-- Devuelve una tabla:
--   { ok = true,  delta = N, levelsGained = 0|1 }
--   { ok = false, levelsGained = N, reason = "..." }  -- N niveles o mas
--     de golpe (no hay API en Classic Era para el requisito de xp de
--     niveles intermedios: no se inventa un numero) o xp menor sin
--     subida de nivel (caso sin explicacion valida).
--
-- previousXP/previousLevel a nil (primer evento, sin muestra anterior)
-- se tratan como si no hubiera pasado nada: delta 0, sin nivel ganado.
function Ledger.ComputeXPDelta(previousXP, currentXP, previousMaxXP, previousLevel, currentLevel)
    previousXP = previousXP or currentXP
    previousLevel = previousLevel or currentLevel
    local levelsGained = currentLevel - previousLevel

    if levelsGained == 0 then
        if currentXP < previousXP then
            return {
                ok = false,
                levelsGained = 0,
                reason = string.format(
                    "xpActual (%d) menor que xpAnterior (%d) sin subida de nivel detectada: caso sin explicacion valida, delta no calculado",
                    currentXP, previousXP),
            }
        end
        return { ok = true, delta = currentXP - previousXP, levelsGained = 0 }
    end

    if levelsGained == 1 then
        -- La xp que faltaba para completar el nivel viejo (con su
        -- maximo cacheado) mas la xp ya ganada en el nivel nuevo.
        return { ok = true, delta = (previousMaxXP - previousXP) + currentXP, levelsGained = 1 }
    end

    return {
        ok = false,
        levelsGained = levelsGained,
        reason = string.format(
            "salto de %d niveles en un solo PLAYER_XP_UPDATE: no hay API en Classic Era para el requisito de xp de niveles intermedios, delta no calculable",
            levelsGained),
    }
end
