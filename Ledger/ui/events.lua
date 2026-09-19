-- Ledger - ui/events.lua
-- Event registration, slash command and addon lifecycle.

local ADDON_NAME, Ledger = ...

-- Reads the version from the .toc. In Classic Era 1.15.x both the
-- global GetAddOnMetadata and C_AddOns.GetAddOnMetadata exist; we try
-- the new namespace first and fall back to the global if it's missing.
local function GetVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if getter then
        return getter(ADDON_NAME, "Version") or "?"
    end
    return "?"
end

-- Each line of msg (it can carry several, separated by \n) is sent as
-- its own AddMessage, so a multiline dump (help, dump) looks right
-- without depending on how the client handles \n within a single
-- message.
local function Print(msg)
    for line in tostring(msg):gmatch("[^\n]+") do
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Ledger|r: " .. line)
    end
end

----------------------------------------------------------------------
-- Log state (level, buffer, chat echo). In memory only, like the
-- matcher: it isn't persisted.
----------------------------------------------------------------------

Ledger.logState = Ledger.NewLogState()


-- Thin wrapper over Ledger.LogMessage: adds the clock (GetTime(), which
-- core/ never touches) and, if the message passes the level filter and
-- the chat echo is enabled, prints it. Passed as a callback into core/
-- (e.g. core/xp_gain_matcher.lua) so the pure modules can describe
-- their decisions without touching any WoW API themselves.
function Ledger.Log(level, msg)
    if Ledger.LogMessage(Ledger.logState, level, msg, GetTime()) then
        -- Colored by level (Ledger.FormatLogChatLine); each line of a
        -- multiline message is colored on its own.
        for line in tostring(msg):gmatch("[^\n]+") do
            DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Ledger|r " .. Ledger.FormatLogChatLine(level, line))
        end
    end
end

----------------------------------------------------------------------
-- /ldg slash command (and /ledger alias). Parsing lives in
-- core/slash_command.lua; this only dispatches. An unknown subcommand
-- replies the same as /ldg help.
----------------------------------------------------------------------

SLASH_LEDGER1 = "/ldg"
SLASH_LEDGER2 = "/ledger"
SlashCmdList["LEDGER"] = function(msg)
    local command, args = Ledger.ParseCommand(msg)

    if command == "" then
        if Ledger.frame:IsShown() then
            Ledger.frame:Hide()
            LedgerDB.shown = false
            Print("hidden")
        else
            Ledger.UpdateXP()
            Ledger.frame:Show()
            LedgerDB.shown = true
            Print("hi")
        end

    elseif command == "help" then
        Print(Ledger.HelpText())

    elseif command == "debug" then
        Ledger.ToggleDebugFrame()

    elseif command == "dump" then
        Print(Ledger.FormatState(LedgerCharDB))

    elseif command == "reset" then
        Ledger.ResetSession(GetTime())
        Print("session reset")

    elseif command == "strings" then
        Print(Ledger.FormatXPGainStrings(Ledger.xpGainStrings))
        Print("Rested-bonus suffix (unconfirmed in-game, see CLAUDE.md):")
        Print(Ledger.FormatXPGainStrings(Ledger.restedStrings))
        Print("Area-discovery message (CHAT_MSG_SYSTEM, unconfirmed in-game, see CLAUDE.md):")
        if #Ledger.exploreStrings == 0 then
            Print("ERR_ZONE_EXPLORED_XP not found in this client")
        else
            Print(Ledger.FormatXPGainStrings(Ledger.exploreStrings))
        end

    elseif command == "rested" then
        LedgerDB.includeRested = not LedgerDB.includeRested
        Ledger.UpdateRestedLabel()
        Print("rested bonus in metrics: " .. (LedgerDB.includeRested and "included" or "excluded"))

    elseif command == "bar" then
        local shown, ok, width, segmentCount = Ledger.ToggleXPBar()
        if not shown then
            Print("xp composition bar: hidden")
        elseif not ok then
            -- No longer expected in practice: AnchorToNativeBar always
            -- resolves to something now, native or degraded (see
            -- ui/xp_bar.lua). Kept as a defensive fallback message in
            -- case frame:GetWidth() ever comes back unusable.
            Print("xp composition bar: shown, but could not be sized -- try /ldg log trace and /ldg log chat and try again")
        elseif segmentCount == 0 then
            Print(string.format(
                "xp composition bar: shown (width=%dpx), but no xp recorded yet on this level -- gain some xp to see it fill up",
                width))
        else
            Print(string.format("xp composition bar: shown (width=%dpx, %d segments)", width, segmentCount))
        end

    elseif command == "time" then
        local shown = Ledger.ToggleTimeBar()
        Print("activity bar: " .. (shown and "shown" or "hidden"))

    elseif command == "rate" then
        local shown = Ledger.ToggleRateFrame()
        Print("xp/hour number: " .. (shown and "shown" or "hidden"))

    elseif command == "export" then
        Ledger.ToggleExportFrame()

    elseif command == "check" then
        Ledger.ToggleCheckFrame()

    elseif command == "probe" then
        Print(Ledger.FormatProbe(Ledger.GatherProbeData()))

    elseif command == "wipe" then
        if args[1] == "confirm" then
            Ledger.WipeCharacterData(GetTime())
            Print("character database wiped. New session opened from the current level and xp.")
        else
            Print("this deletes ALL saved sessions and levels for this character -- it cannot be undone. Type /ldg wipe confirm to proceed.")
        end

    elseif command == "log" then
        local action = args[1]
        if Ledger.IsValidLogLevel(action) then
            Ledger.SetLogLevel(Ledger.logState, action)
            Print("log level: " .. action)
        elseif action == "show" then
            Ledger.ShowDebugFrame("log")
        elseif action == "chat" then
            local enabled = Ledger.ToggleLogChat(Ledger.logState)
            Print("log echo to chat: " .. (enabled and "enabled" or "disabled"))
        else
            Print(Ledger.HelpText())
        end

    else
        Print(Ledger.HelpText())
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------

-- SavedVariables diagnostics (INFO, see /ldg log show). On the WoW Forever
-- beta neither LedgerDB nor LedgerCharDB arrive from disk at ADDON_LOADED
-- although both get written at logout (Classic Era loads them fine): this
-- records what each global looks like at several points of the startup
-- and what the client parsed from the .toc's SavedVariables lines, to
-- tell "never loaded" from "loaded late". `tostring(table)` is the
-- table's address, so a later replacement of the global shows as a
-- different one.
local function LogSavedVariablesState(where)
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    local function meta(field) return getter and tostring(getter(ADDON_NAME, field)) or "?" end
    local dbKeys = 0
    if type(LedgerDB) == "table" then
        for _ in pairs(LedgerDB) do dbKeys = dbKeys + 1 end
    end
    Ledger.Log("info", string.format(
        "SVState[%s]: LedgerDB=%s keys=%d ratePos=%s | LedgerCharDB=%s %s | toc SavedVariables=%s PerCharacter=%s",
        where, tostring(LedgerDB), dbKeys,
        type(LedgerDB) == "table" and tostring(LedgerDB.ratePos ~= nil) or "n/a",
        tostring(LedgerCharDB), Ledger.SummarizeCharDB(LedgerCharDB),
        meta("SavedVariables"), meta("SavedVariablesPerCharacter")))
end

local wipeNotice -- set on ADDON_LOADED when saved data of another version was wiped

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("UI_SCALE_CHANGED")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        -- SavedVariables are already loaded by the time our own name arrives.
        if arg1 == ADDON_NAME then
            LogSavedVariablesState("ADDON_LOADED, from disk")
            LedgerDB = Ledger.InitDB(LedgerDB, Ledger.DEFAULTS)
            local wiped, oldVersion
            -- Startup diagnostics (INFO, see /ldg log show): what the
            -- client actually handed us from disk vs what we ended up
            -- with, to catch a /reload that loses the level's sessions.
            local onDisk = Ledger.SummarizeCharDB(LedgerCharDB)
            LedgerCharDB, wiped, oldVersion = Ledger.InitCharDB(LedgerCharDB)
            Ledger.Log("info", string.format("ADDON_LOADED: LedgerCharDB from disk: %s | after init: %s | wiped=%s",
                onDisk, Ledger.SummarizeCharDB(LedgerCharDB), tostring(wiped)))
            if wiped then
                -- No migrations: data saved under another schema version is
                -- wiped and tracking starts clean -- never silently. Held
                -- until PLAYER_LOGIN, when the chat is surely ready.
                wipeNotice = string.format(
                    "saved data was version %s, this addon uses version %d: this character's data was wiped and tracking starts clean",
                    tostring(oldVersion), Ledger.DB_VERSION)
            end
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_LOGIN" then
        LogSavedVariablesState("PLAYER_LOGIN")
        if C_Timer and C_Timer.After then
            C_Timer.After(5,  function() LogSavedVariablesState("+5s") end)
            C_Timer.After(30, function() LogSavedVariablesState("+30s") end)
        end
        Ledger.RestorePosition()
        Ledger.UpdateRestedLabel()
        if LedgerDB.shown then
            Ledger.frame:Show()
        end
        if LedgerDB.barShown then
            Ledger.xpBarFrame:Show()
            Ledger.RedrawXPBarFull()
        end
        if LedgerDB.timeBarShown then
            Ledger.timeBarFrame:Show()
            Ledger.RedrawTimeBar()
        end
        Ledger.RestoreRatePosition()
        if LedgerDB.rateShown then
            Ledger.rateFrame:Show()
            Ledger.RefreshRateFrame()
        end
        Print("loaded, version " .. GetVersion())
        if wipeNotice then
            Print(wipeNotice)
        end
        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Login and every loading screen (zone, instance, resurrection).
        LogSavedVariablesState("PLAYER_ENTERING_WORLD")
        Ledger.UpdateXP()
        -- Safety net: if the native bar didn't have its final width yet
        -- at PLAYER_LOGIN, it does by now -- also covers
        -- Blizzard_StatusTrackingBar loading late (see ui/xp_bar.lua).
        Ledger.RedrawXPBarFull()
        Ledger.RedrawTimeBar()

    elseif event == "UI_SCALE_CHANGED" then
        -- The scale changing can shift the native bar's on-screen
        -- geometry, or Blizzard_StatusTrackingBar can get repositioned
        -- -- reanchor both bars instead of letting them drift out of
        -- place until the next PLAYER_ENTERING_WORLD.
        Ledger.RedrawXPBarFull()
        Ledger.RedrawTimeBar()

    elseif event == "PLAYER_XP_UPDATE" then
        -- arg1 is the unit; we only care about the player.
        if arg1 == "player" then
            Ledger.UpdateXP()
        end

    elseif event == "PLAYER_LOGOUT" then
        -- Safety net in case the frame got moved without an OnDragStop.
        Ledger.SavePosition()
    end
end)
