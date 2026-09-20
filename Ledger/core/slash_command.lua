-- Ledger - core/slash_command.lua
-- Parses /ldg's text and catalogs its subcommands (for /ldg help and so
-- whoever dispatches knows whether a top-level subcommand exists).
-- Pure logic: does not use any WoW API.

local ADDON_NAME, Ledger = ...

-- Stable order for /ldg help. name = "" is the no-argument command.
Ledger.SLASH_COMMANDS = {
    { name = "",      desc = "shows or hides the main panel" },
    { name = "help",  desc = "lists all subcommands" },
    { name = "debug", desc = "shows or hides the debug panel" },
    { name = "dump",  desc = "dumps the state to chat, without opening the panel" },
    { name = "reset", desc = "closes the current session and opens a new manual one" },
    { name = "log",   desc = "log <off|error|info|trace> changes the level; log show dumps the buffer to the debug panel; log chat toggles the chat echo" },
    { name = "strings", desc = "prints the xp global strings in use, with their literal value in this client" },
    { name = "rested", desc = "toggles whether the rested bonus counts in session and level xp metrics" },
    { name = "bar", desc = "shows or hides the level's xp composition bar (it replaces the native xp bar: same place and size)" },
    { name = "native", desc = "toggles the composition bar replacing the native xp bar; off gives the native bar back and moves the composition bar above it" },
    { name = "time", desc = "shows or hides the level's activity bar (combat/non-combat/travel/dead, as a percentage of samples), independent of /ldg bar" },
    { name = "rate", desc = "shows or hides the headline xp/hour number above the xp bar; hover it for the session/level breakdown" },
    { name = "wipe", desc = "wipe confirm deletes ALL saved sessions and levels for this character (irreversible)" },
    { name = "export", desc = "shows or hides a window with the character's full data (JSON/CSV), pre-selected to copy with Ctrl+C" },
    { name = "check", desc = "shows or hides a window reconciling recorded xp against the real value, with every discrepancy flagged (plus /played as information)" },
    { name = "probe", desc = "prints a compatibility snapshot of this client build: GetBuildInfo, key APIs, xp global strings, C_ChatInfo" },
}

local KNOWN_COMMANDS = {}
for _, cmd in ipairs(Ledger.SLASH_COMMANDS) do
    KNOWN_COMMANDS[cmd.name] = true
end

-- Splits /ldg's text into a subcommand (the first word, lowercased) and
-- the rest of the words (also lowercased), tolerating extra whitespace
-- anywhere. msg can come in as nil or empty: in that case the
-- subcommand is "" (the no-argument command). Does not validate
-- whether the subcommand or its arguments are recognized: that's up to
-- the dispatcher, not the parser.
function Ledger.ParseCommand(msg)
    local words = {}
    for word in (msg or ""):gmatch("%S+") do
        table.insert(words, word:lower())
    end

    local command = table.remove(words, 1) or ""
    return command, words
end

-- true if `command` is one of the known top-level subcommands
-- (including the empty string). Says nothing about second-level
-- arguments (e.g. "log"'s argument).
function Ledger.IsKnownCommand(command)
    return KNOWN_COMMANDS[command] == true
end

-- /ldg help text: one line per declared subcommand.
function Ledger.HelpText()
    local lines = { "Available commands:" }
    for _, cmd in ipairs(Ledger.SLASH_COMMANDS) do
        local label = (cmd.name == "") and "/ldg" or ("/ldg " .. cmd.name)
        table.insert(lines, string.format("%s - %s", label, cmd.desc))
    end
    return table.concat(lines, "\n")
end
