-- Ledger - core/slash_command.lua
-- Parseo del texto de /ldg y catalogo de subcomandos (para /ldg help y
-- para que quien despache sepa si un subcomando de primer nivel existe).
-- Logica pura: no usa ninguna API de WoW.

local ADDON_NAME, Ledger = ...

print("Ledger: core/slash_command.lua")

-- Orden estable para /ldg help. name = "" es el comando sin argumentos.
Ledger.SLASH_COMMANDS = {
    { name = "",      desc = "muestra u oculta el panel principal" },
    { name = "help",  desc = "lista todos los subcomandos" },
    { name = "debug", desc = "muestra u oculta el panel de depuracion" },
    { name = "dump",  desc = "vuelca el estado al chat, sin abrir panel" },
    { name = "reset", desc = "cierra la sesion actual y abre una nueva manual" },
    { name = "log",   desc = "log <off|error|info|trace> cambia el nivel; log show vuelca el buffer al panel de depuracion; log chat activa o desactiva el eco al chat" },
    { name = "strings", desc = "imprime los global strings de xp en uso, con su valor literal en este cliente" },
    { name = "rested", desc = "alterna si el bono por descanso cuenta en las metricas de xp de sesion y de nivel" },
    { name = "bar", desc = "muestra u oculta la barra de composicion de xp del nivel, anclada sobre la barra nativa" },
    { name = "time", desc = "muestra u oculta la barra de reparto de tiempo del nivel (active/travel/idle/dead), independiente de /ldg bar" },
    { name = "wipe", desc = "wipe confirm borra TODAS las sesiones y niveles guardados de este personaje (irreversible)" },
}

local KNOWN_COMMANDS = {}
for _, cmd in ipairs(Ledger.SLASH_COMMANDS) do
    KNOWN_COMMANDS[cmd.name] = true
end

-- Separa el texto de /ldg en subcomando (primera palabra, en minusculas)
-- y el resto de palabras (tambien en minusculas), tolerando espacios de
-- mas en cualquier posicion. msg puede venir a nil o vacio: en ese caso
-- el subcomando es "" (el comando sin argumentos). No valida si el
-- subcomando o sus argumentos son reconocidos: eso es cosa de quien
-- despacha, no del parseo.
function Ledger.ParseCommand(msg)
    local words = {}
    for word in (msg or ""):gmatch("%S+") do
        table.insert(words, word:lower())
    end

    local command = table.remove(words, 1) or ""
    return command, words
end

-- true si `command` es uno de los subcomandos de primer nivel conocidos
-- (incluida la cadena vacia). No dice nada sobre argumentos de segundo
-- nivel (p.ej. el argumento de "log").
function Ledger.IsKnownCommand(command)
    return KNOWN_COMMANDS[command] == true
end

-- Texto de /ldg help: una linea por subcomando declarado.
function Ledger.HelpText()
    local lines = { "Comandos disponibles:" }
    for _, cmd in ipairs(Ledger.SLASH_COMMANDS) do
        local label = (cmd.name == "") and "/ldg" or ("/ldg " .. cmd.name)
        table.insert(lines, string.format("%s - %s", label, cmd.desc))
    end
    return table.concat(lines, "\n")
end
