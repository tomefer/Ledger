-- Ledger - core/log.lua
-- State of the log subsystem: active level, ring buffer and chat-echo
-- flag. Pure logic: does not use any WoW API, the clock is always
-- received as a parameter. Lives only in memory (like the bucket
-- tracker and the matcher): there's no SavedVariable for this yet.

local ADDON_NAME, Ledger = ...

print("Ledger: core/log.lua")

-- Severity order. "off" logs nothing; "trace" logs everything.
local LEVEL_RANK = { off = 0, error = 1, info = 2, trace = 3 }
Ledger.LOG_LEVELS = { "off", "error", "info", "trace" }

Ledger.LOG_BUFFER_CAPACITY = 200

-- Starts at "trace" (everything is recorded into the buffer, nothing is
-- echoed to chat until /ldg log chat): the buffer is in memory only and
-- costs nothing to look at, whereas a violation logged at ERROR under
-- "off" (e.g. a level-close invariant, ui/xp_capture.lua) was simply lost.
function Ledger.NewLogState()
    return { level = "trace", chat = false, buffer = {} }
end

function Ledger.IsValidLogLevel(level)
    return LEVEL_RANK[level] ~= nil
end

-- Changes the active level. Returns true if `level` was valid (and
-- therefore applied), false otherwise (and the state is left untouched).
function Ledger.SetLogLevel(state, level)
    if not LEVEL_RANK[level] then return false end
    state.level = level
    return true
end

function Ledger.SetLogChat(state, enabled)
    state.chat = enabled and true or false
end

-- Toggles the chat echo and returns the new value.
function Ledger.ToggleLogChat(state)
    state.chat = not state.chat
    return state.chat
end

-- Records a message if `level` passes the active level's filter.
-- Returns true if it should also be echoed to chat (state.chat enabled
-- and the message passed the filter); false in any other case,
-- including an invalid `level`.
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

-- Dumps the buffer to text, one entry per line, oldest first.
function Ledger.FormatLogBuffer(state)
    if #state.buffer == 0 then
        return "(log buffer empty)"
    end

    local lines = {}
    for _, entry in ipairs(state.buffer) do
        table.insert(lines, string.format("[%s] %s", entry.level, entry.msg))
    end
    return table.concat(lines, "\n")
end
