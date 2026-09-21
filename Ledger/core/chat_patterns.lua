-- Ledger - core/chat_patterns.lua
-- Converts a Blizzard global string (with %s/%d as placeholders) into a
-- Lua pattern to recognize and capture data from real chat messages,
-- without hardcoding any text: global strings change from language to
-- language, but their %s/%d placeholders don't. Pure logic: does not
-- touch any WoW API, receives the global string's text already read by
-- the caller.

local ADDON_NAME, Ledger = ...

local function EscapeMagic(text)
    return (text:gsub("([%(%)%.%%%+%-%*%?%[%]%^%$])", "%%%1"))
end

-- Shared by BuildPattern and BuildSuffixPattern: %s becomes a text
-- capture group and %d a digit one; the rest of the text is escaped so
-- it's compared literally.
local function ConvertFormatString(formatString)
    local marked  = formatString:gsub("%%s", "\1"):gsub("%%d", "\2")
    local escaped = EscapeMagic(marked)
    return escaped:gsub("\1", "(.-)"):gsub("\2", "(%%d+)")
end

-- Converts "%s dies, you gain %d experience." into
-- "^(.-) dies, you gain (%d+) experience%.". Only the start is anchored
-- (^), not the end: the real message can continue with text the global
-- string doesn't account for (e.g. "(+86 exp Rested bonus)" for the
-- rested bonus), and %d+ already stops capturing at the first
-- non-digit character, so there's no need for a $ to keep the capture
-- exact.
function Ledger.BuildPattern(formatString)
    return "^" .. ConvertFormatString(formatString)
end

-- Same as BuildPattern but without anchoring the start: used to locate
-- a suffix anywhere in the message (e.g. the rested bonus, which is
-- attached to the end of the combat xp sentence, not the start).
function Ledger.BuildSuffixPattern(formatString)
    return ConvertFormatString(formatString)
end

-- Tests `msg` against each entry of `entries` (in order; each one
-- {name=, text=, pattern=}, see ui/xp_capture.lua) and classifies the
-- source: "kill" if the variant that matched carries a creature name
-- (its global string has a %s), "explore" if not, or if no entry
-- matches at all -- CHAT_MSG_COMBAT_XP_GAIN only fires for the
-- player's own combat or exploration xp, so its mere arrival already
-- rules out "unknown" even if we don't recognize the message's exact
-- format. Also returns `attempts`, the record of each entry tried (in
-- order) with whether it matched and what it captured, so the caller
-- can log the whole attempt without repeating this loop. A non-string
-- `msg` (nil) matches nothing. Pure logic: does not touch any WoW API.
function Ledger.ClassifyXPGainMatch(entries, msg)
    local attempts = {}
    if type(msg) ~= "string" then return "explore", attempts end

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

-- Looks for the rested-bonus suffix anywhere in `msg`, trying each
-- entry of `entries` (in order; {name=, text=, pattern=} with a
-- pattern from BuildSuffixPattern) until one matches. Returns the
-- captured amount (a number) or 0 if none matches -- rested = 0 means
-- "there was no bonus", same as when the message carries no suffix at
-- all. Pure logic: does not touch any WoW API.
function Ledger.ExtractRestedBonus(entries, msg)
    if type(msg) ~= "string" then return 0 end
    for _, entry in ipairs(entries or {}) do
        local captured = msg:match(entry.pattern)
        if captured then
            return tonumber(captured) or 0
        end
    end
    return 0
end

-- Looks for an area-discovery message ("Discovered %s: %d experience
-- gained", ERR_ZONE_EXPLORED_XP) in `msg`, trying each entry of
-- `entries` (in order; {name=, text=, pattern=} with a pattern from
-- BuildPattern). Exploration xp does NOT arrive through
-- CHAT_MSG_COMBAT_XP_GAIN: it's a system message, so this is the only
-- signal that tells exploration apart from an unknown xp gain. Returns
-- the captured xp amount (the LAST capture: the area name comes first)
-- or nil if nothing matches. Pure logic: does not touch any WoW API.
function Ledger.ExtractExploreXP(entries, msg)
    if type(msg) ~= "string" then return nil end
    for _, entry in ipairs(entries or {}) do
        local results = { msg:match(entry.pattern) }
        if #results > 0 then
            return tonumber(results[#results])
        end
    end
    return nil
end

-- Formats the list of xp global strings in use (see ui/xp_capture.lua:
-- each entry is { name=, text=, pattern= }) for /ldg strings: the
-- global string's name, its literal value in this client and the
-- derived Lua pattern, to eyeball whether the conversion is correct.
-- Pure logic: formats what it's given, does not read _G.
function Ledger.FormatXPGainStrings(entries)
    if not entries or #entries == 0 then
        return "No COMBATLOG_XPGAIN_* global string found in this client"
    end

    local lines = { "Xp global strings in use:" }
    for _, entry in ipairs(entries) do
        table.insert(lines, string.format("%s = %s", entry.name, entry.text))
        table.insert(lines, string.format("  pattern: %s", entry.pattern))
    end
    return table.concat(lines, "\n")
end
