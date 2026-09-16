-- Ledger - ui/palette.lua
-- Paleta de colores centralizada: la usan tanto la barra de composicion
-- de xp (ui/xp_bar.lua) como la barra de reparto de tiempo
-- (ui/time_bar.lua), y sus tooltips respectivos, para que nunca puedan
-- desincronizarse. Nunca hardcodear un color suelto en el codigo de
-- dibujado: si hace falta un color nuevo, es una entrada mas aqui.
--
-- Cada entrada en formato 0-1 (para SetVertexColor/SetColorTexture),
-- calculada con literales hexadecimales de Lua (0xRR/255) para que
-- quede trazable al hex sin redondeos a mano; el hex original queda en
-- el comentario junto a cada una.

local ADDON_NAME, Ledger = ...

Ledger.PALETTE = {
    -- Barra de xp, por src.
    kill      = { 0xC8/255, 0xA3/255, 0x4E/255 }, -- #C8A34E, dorado apagado
    quest     = { 0x3F/255, 0xA9/255, 0x8C/255 }, -- #3FA98C, verde azulado
    explore   = { 0x8C/255, 0x7B/255, 0xB5/255 }, -- #8C7BB5, violeta claro
    unknown   = { 0x6E/255, 0x6A/255, 0x66/255 }, -- #6E6A66, gris calido
    _fallback = { 0xCC/255, 0x33/255, 0x99/255 }, -- #CC3399, magenta chillon: src/bucket no reconocido, no deberia verse nunca

    -- Barra de tiempo, por bucket. travel y dead son entradas propias.
    travel = { 0x4A/255, 0x6F/255, 0xA5/255 }, -- #4A6FA5, azul apagado
    dead   = { 0x8B/255, 0x3A/255, 0x3A/255 }, -- #8B3A3A, rojo oscuro apagado
}

-- active e idle REUTILIZAN el color de kill/unknown (mismo concepto:
-- tiempo productivo / "no lo sabemos"), no una copia del mismo hex: si
-- kill o unknown cambian alguna vez, estos les siguen automaticamente.
Ledger.PALETTE.active = Ledger.PALETTE.kill
Ledger.PALETTE.idle   = Ledger.PALETTE.unknown

-- El segmento inicial de la barra de xp ("xp previa al registro") es,
-- en esencia, "no lo sabemos": mismo gris que unknown.
if Ledger.BAR_INITIAL_SRC then
    Ledger.PALETTE[Ledger.BAR_INITIAL_SRC] = Ledger.PALETTE.unknown
end

-- Aclara un color un `amount` (0..1) hacia el blanco, calculado a
-- partir del color base -- nunca una entrada aparte de la paleta. Se
-- usa para el tono de "rested" dentro de un segmento de la barra de xp.
function Ledger.LightenColor(color, amount)
    return {
        color[1] + (1 - color[1]) * amount,
        color[2] + (1 - color[2]) * amount,
        color[3] + (1 - color[3]) * amount,
    }
end
