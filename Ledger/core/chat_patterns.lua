-- Ledger - core/chat_patterns.lua
-- Convierte un global string de Blizzard (con %s/%d como marcadores) en
-- un patron de Lua para reconocer y capturar datos de los mensajes de
-- chat reales, sin hardcodear ningun texto: los global strings cambian
-- de idioma a idioma, pero el %s/%d de sus marcadores no. Logica pura:
-- no toca ninguna API de WoW, recibe el texto del global string ya
-- leido por quien llama.

local ADDON_NAME, Ledger = ...

print("Ledger: core/chat_patterns.lua")

local function EscapeMagic(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-- Comun a BuildPattern y BuildSuffixPattern: %s pasa a ser un grupo de
-- captura de texto y %d uno de digitos; el resto del texto se escapa
-- para que se compare literalmente.
local function ConvertFormatString(formatString)
    local marked  = formatString:gsub("%%s", "\1"):gsub("%%d", "\2")
    local escaped = EscapeMagic(marked)
    return escaped:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
end

-- Convierte "%s dies, you gain %d experience." en
-- "^(.-) dies, you gain (%d+) experience%.". Solo se ancla el principio
-- (^), no el final: el mensaje real puede continuar con texto que el
-- global string no contempla (p.ej. "(+86 exp Rested bonus)" del bono
-- por descanso), y un %d+ ya para de capturar en el primer caracter no
-- numerico, asi que no hace falta un $ para que la captura sea exacta.
function Ledger.BuildPattern(formatString)
    return "^" .. ConvertFormatString(formatString)
end

-- Igual que BuildPattern pero sin anclar el principio: sirve para
-- localizar un sufijo en cualquier punto del mensaje (p.ej. el bono por
-- descanso, que va pegado al final de la frase de xp de combate, no al
-- principio).
function Ledger.BuildSuffixPattern(formatString)
    return ConvertFormatString(formatString)
end

-- Prueba `msg` contra cada entrada de `entries` (en orden; cada una
-- {name=, text=, pattern=}, ver ui/xp_capture.lua) y clasifica el
-- origen: "kill" si la variante que caso lleva nombre de criatura (su
-- global string tiene un %s), "explore" si no, o si ninguna entrada
-- casa -- CHAT_MSG_COMBAT_XP_GAIN solo se dispara para xp de combate o
-- exploracion del propio jugador, asi que su sola llegada ya descarta
-- "unknown" aunque no reconozcamos el formato exacto del mensaje.
-- Devuelve ademas `attempts`, el registro de cada entrada probada (en
-- orden) con si caso y que capturo, para que quien llame pueda loguear
-- el intento completo sin repetir este bucle. Logica pura: no toca
-- ninguna API de WoW.
function Ledger.ClassifyXPGainMatch(entries, msg)
    local attempts = {}

    for _, entry in ipairs(entries or {}) do
        local results = { msg:find(entry.pattern) }
        local matched = results[1] ~= nil

        local captured = {}
        for i = 3, #results do
            table.insert(captured, tostring(results[i]))
        end

        table.insert(attempts, { name = entry.name, pattern = entry.pattern, matched = matched, captured = captured })

        if matched then
            local category = entry.text:find("%%s") and "kill" or "explore"
            return category, attempts
        end
    end

    return "explore", attempts
end

-- Busca el sufijo del bono por descanso en cualquier punto de `msg`,
-- probando cada entrada de `entries` (en orden; {name=, text=,
-- pattern=} con pattern de BuildSuffixPattern) hasta que una case.
-- Devuelve la cantidad capturada (numero) o 0 si ninguna casa -- rested
-- = 0 es "no hubo bono", igual que cuando el mensaje no trae sufijo.
-- Logica pura: no toca ninguna API de WoW.
function Ledger.ExtractRestedBonus(entries, msg)
    for _, entry in ipairs(entries or {}) do
        local captured = msg:match(entry.pattern)
        if captured then
            return tonumber(captured) or 0
        end
    end
    return 0
end

-- Formatea la lista de global strings de xp en uso (ver
-- ui/xp_capture.lua: cada entrada es { name=, text=, pattern= }) para
-- /ldg strings: nombre del global string, su valor literal en este
-- cliente y el patron Lua derivado, para poder comprobar a ojo si la
-- conversion es correcta. Logica pura: formatea lo que se le pasa, no
-- lee _G.
function Ledger.FormatXPGainStrings(entries)
    if not entries or #entries == 0 then
        return "No se ha encontrado ningun global string COMBATLOG_XPGAIN_* en este cliente"
    end

    local lines = { "Global strings de xp en uso:" }
    for _, entry in ipairs(entries) do
        table.insert(lines, string.format("%s = %s", entry.name, entry.text))
        table.insert(lines, string.format("  patron: %s", entry.pattern))
    end
    return table.concat(lines, "\n")
end
