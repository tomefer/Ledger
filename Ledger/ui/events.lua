-- Ledger - ui/events.lua
-- Registro de eventos, slash command y ciclo de vida del addon.

local ADDON_NAME, Ledger = ...

-- Lee la version desde el .toc. En Classic Era 1.15.x conviven el global
-- GetAddOnMetadata y C_AddOns.GetAddOnMetadata; probamos el namespace nuevo
-- primero y caemos al global si no existe.
local function GetVersion()
    local getter = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    if getter then
        return getter(ADDON_NAME, "Version") or "?"
    end
    return "?"
end

-- Cada linea de msg (puede traer varias, separadas por \n) se manda como
-- un AddMessage aparte, para que un volcado multilinea (help, dump) se
-- vea bien sin depender de como el cliente maneje \n dentro de un unico
-- mensaje.
local function Print(msg)
    for line in tostring(msg):gmatch("[^\n]+") do
        DEFAULT_CHAT_FRAME:AddMessage("|cff33ff99Ledger|r: " .. line)
    end
end

----------------------------------------------------------------------
-- Estado del log (nivel, buffer, eco a chat). Solo en memoria, como el
-- tracker de buckets y el matcher: no se persiste.
----------------------------------------------------------------------

Ledger.logState = Ledger.NewLogState()

-- Envoltorio fino sobre Ledger.LogMessage: añade el reloj (GetTime(),
-- que core/ nunca toca) y, si el mensaje pasa el filtro de nivel y el
-- eco a chat esta activo, lo imprime. Se pasa como callback a core/ (p.
-- ej. core/xp_gain_matcher.lua) para que los módulos puros puedan
-- describir sus decisiones sin tocar ninguna API de WoW ellos mismos.
function Ledger.Log(level, msg)
    if Ledger.LogMessage(Ledger.logState, level, msg, GetTime()) then
        Print(msg)
    end
end

----------------------------------------------------------------------
-- Slash command /ldg (y alias /ledger). El parseo vive en
-- core/slash_command.lua; aqui solo se despacha. Un subcomando
-- desconocido responde lo mismo que /ldg help.
----------------------------------------------------------------------

SLASH_LEDGER1 = "/ldg"
SLASH_LEDGER2 = "/ledger"
SlashCmdList["LEDGER"] = function(msg)
    local command, args = Ledger.ParseCommand(msg)

    if command == "" then
        if Ledger.frame:IsShown() then
            Ledger.frame:Hide()
            LedgerDB.shown = false
            Print("oculto")
        else
            Ledger.UpdateXP()
            Ledger.frame:Show()
            LedgerDB.shown = true
            Print("hola")
        end

    elseif command == "help" then
        Print(Ledger.HelpText())

    elseif command == "debug" then
        Ledger.ToggleDebugFrame()

    elseif command == "dump" then
        Print(Ledger.FormatState(LedgerCharDB))

    elseif command == "reset" then
        Ledger.ResetSession(GetTime())
        Print("sesion reiniciada")

    elseif command == "strings" then
        Print(Ledger.FormatXPGainStrings(Ledger.xpGainStrings))
        Print("Sufijo de bono por descanso (sin confirmar en el juego, ver CLAUDE.md):")
        Print(Ledger.FormatXPGainStrings(Ledger.restedStrings))

    elseif command == "rested" then
        LedgerDB.includeRested = not LedgerDB.includeRested
        Ledger.UpdateRestedLabel()
        Print("bono por descanso en las metricas: " .. (LedgerDB.includeRested and "incluido" or "excluido"))

    elseif command == "bar" then
        local shown, ok, width, segmentCount = Ledger.ToggleXPBar()
        if not shown then
            Print("barra de composicion de xp: oculta")
        elseif not ok then
            Print("barra de composicion de xp: mostrada, pero no se ha encontrado la barra de xp nativa para anclarse (a nivel maximo no hay ninguna; si no es el caso, prueba /ldg log trace y /ldg log chat y vuelve a intentarlo)")
        elseif segmentCount == 0 then
            Print(string.format(
                "barra de composicion de xp: mostrada (ancho=%dpx), pero sin xp registrada todavia en este nivel -- gana algo de xp para verla rellenarse",
                width))
        else
            Print(string.format("barra de composicion de xp: mostrada (ancho=%dpx, %d segmentos)", width, segmentCount))
        end

    elseif command == "time" then
        local shown = Ledger.ToggleTimeBar()
        Print("barra de reparto de tiempo: " .. (shown and "mostrada" or "oculta"))

    elseif command == "wipe" then
        if args[1] == "confirm" then
            Ledger.WipeCharacterData(GetTime())
            Print("base de datos del personaje borrada. Sesion nueva abierta desde el nivel y xp actuales.")
        else
            Print("esto borra TODAS las sesiones y niveles guardados de este personaje -- no se puede deshacer. Escribe /ldg wipe confirm para continuar.")
        end

    elseif command == "log" then
        local action = args[1]
        if Ledger.IsValidLogLevel(action) then
            Ledger.SetLogLevel(Ledger.logState, action)
            Print("nivel de log: " .. action)
        elseif action == "show" then
            Ledger.ShowDebugFrame("log")
        elseif action == "chat" then
            local enabled = Ledger.ToggleLogChat(Ledger.logState)
            Print("eco de log al chat: " .. (enabled and "activado" or "desactivado"))
        else
            Print(Ledger.HelpText())
        end

    else
        Print(Ledger.HelpText())
    end
end

----------------------------------------------------------------------
-- Eventos
----------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_LOGOUT")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" then
        -- Las SavedVariables ya estan cargadas cuando llega nuestro propio nombre.
        if arg1 == ADDON_NAME then
            LedgerDB = Ledger.InitDB(LedgerDB, Ledger.DEFAULTS)
            LedgerCharDB = Ledger.InitCharDB(LedgerCharDB)
            self:UnregisterEvent("ADDON_LOADED")
        end

    elseif event == "PLAYER_LOGIN" then
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
        Print("cargado, version " .. GetVersion())
        self:UnregisterEvent("PLAYER_LOGIN")

    elseif event == "PLAYER_ENTERING_WORLD" then
        -- Login y cada pantalla de carga (zona, instancia, resurreccion).
        Ledger.UpdateXP()
        -- Red de seguridad: si la barra nativa no tenia todavia su
        -- ancho definitivo en PLAYER_LOGIN, aqui ya lo tiene.
        Ledger.RedrawXPBarFull()
        Ledger.RedrawTimeBar()

    elseif event == "PLAYER_XP_UPDATE" then
        -- arg1 es la unidad; solo nos interesa el jugador.
        if arg1 == "player" then
            Ledger.UpdateXP()
        end

    elseif event == "PLAYER_LOGOUT" then
        -- Red de seguridad por si el frame quedo movido sin OnDragStop.
        Ledger.SavePosition()
    end
end)
