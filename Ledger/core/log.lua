-- Ledger - core/log.lua
-- State of the log subsystem: active level, ring buffer and chat-echo
-- flag. Pure logic: does not use any WoW API, the clock is always
-- received as a parameter. Lives only in memory (like the matcher):
-- there's no SavedVariable for this yet.

local ADDON_NAME, Ledger = ...

-- Severity order. "off" logs nothing; "trace" logs everything.
local LEVEL_RANK = { off = 0, error = 1, info = 2, trace = 3 }
Ledger.LOG_LEVELS = { "off", "error", "info", "trace" }

Ledger.LOG_BUFFER_CAPACITY = 200

-- Chat color of each level, as the RRGGBB of a |cffRRGGBB escape: red for
-- errors so they stand out while playing, cyan for info, dim gray for the
-- noisy trace. A level without an entry is printed uncolored.
Ledger.LOG_COLORS = { error = "ff5555", info = "55ccff", trace = "9a9a9a" }

-- One log line as it is echoed to chat: "[level] message", wrapped in the
-- level's color. The level tag is there too so a line is still readable
-- if the colors don't show. `|` in the message is doubled, so text
-- recorded from the game (a raw chat message) can never be read by the
-- chat frame as an escape sequence of its own, and can't cut the color
-- short with a stray |r. Meant for ONE line: the caller splits a
-- multiline message first, since the color must wrap each line.
function Ledger.FormatLogChatLine(level, msg)
    local text = string.format("[%s] %s", level, (tostring(msg):gsub("|", "||")))
    local color = Ledger.LOG_COLORS[level]
    if not color then
        return text
    end
    return "|cff" .. color .. text .. "|r"
end

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
    -- Over capacity the OLDEST TRACE line goes first: a kill alone writes
    -- ~10 trace lines, so evicting strictly oldest-first pushed an ERROR
    -- out of the buffer after ~20 events and /ldg log show stopped being
    -- useful for diagnosing. Only when no trace is left does the plain
    -- oldest entry go.
    while #state.buffer > Ledger.LOG_BUFFER_CAPACITY do
        local victim = 1
        for i, entry in ipairs(state.buffer) do
            if entry.level == "trace" then
                victim = i
                break
            end
        end
        table.remove(state.buffer, victim)
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
