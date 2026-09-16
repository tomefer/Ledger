-- Ledger - core/log.lua
-- Estado del sistema de log: nivel activo, buffer en anillo y flag de
-- eco al chat. Logica pura: no usa ninguna API de WoW, el reloj se
-- recibe siempre como parametro. Vive solo en memoria (como el tracker
-- de buckets y el matcher): no hay SavedVariable para esto todavia.

local ADDON_NAME, Ledger = ...

print("Ledger: core/log.lua")

-- Orden de severidad. "off" no registra nada; "trace" registra todo.
local LEVEL_RANK = { off = 0, error = 1, info = 2, trace = 3 }
Ledger.LOG_LEVELS = { "off", "error", "info", "trace" }

Ledger.LOG_BUFFER_CAPACITY = 200

function Ledger.NewLogState()
    return { level = "off", chat = false, buffer = {} }
end

function Ledger.IsValidLogLevel(level)
    return LEVEL_RANK[level] ~= nil
end

-- Cambia el nivel activo. Devuelve true si `level` era valido (y por
-- tanto se aplico), false si no (y el estado no se toca).
function Ledger.SetLogLevel(state, level)
    if not LEVEL_RANK[level] then return false end
    state.level = level
    return true
end

function Ledger.SetLogChat(state, enabled)
    state.chat = enabled and true or false
end

-- Alterna el eco al chat y devuelve el nuevo valor.
function Ledger.ToggleLogChat(state)
    state.chat = not state.chat
    return state.chat
end

-- Registra un mensaje si `level` pasa el filtro del nivel activo.
-- Devuelve true si ademas hay que ecoarlo al chat (state.chat activo y
-- el mensaje paso el filtro); false en cualquier otro caso, incluido
-- `level` invalido.
function Ledger.LogMessage(state, level, msg, t)
    local rank = LEVEL_RANK[level]
    if not rank then return false end
    if rank > LEVEL_RANK[state.level] then return false end

    table.insert(state.buffer, { t = t, level = level, msg = msg })
    while #state.buffer > Ledger.LOG_BUFFER_CAPACITY do
        table.remove(state.buffer, 1)
    end

    return state.chat
end

-- Vuelca el buffer a texto, una entrada por linea, mas antigua primero.
function Ledger.FormatLogBuffer(state)
    if #state.buffer == 0 then
        return "(buffer de log vacio)"
    end

    local lines = {}
    for _, entry in ipairs(state.buffer) do
        table.insert(lines, string.format("[%s] %s", entry.level, entry.msg))
    end
    return table.concat(lines, "\n")
end
