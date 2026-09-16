-- Ledger - ui/debug_frame.lua
-- Panel de depuracion: frame movible y redimensionable con un EditBox de
-- solo lectura y multilinea (seleccionable, para poder copiar) que
-- muestra el volcado de estado (core/state_dump.lua) o el buffer de log
-- (core/log.lua), segun lo ultimo que se haya pedido (/ldg debug o
-- /ldg log show). Capa fina: el formateo del contenido vive en core/,
-- aqui solo se pinta.

local ADDON_NAME, Ledger = ...

local frame = CreateFrame("Frame", "LedgerDebugFrame", UIParent, "BackdropTemplate")
frame:SetSize(420, 320)
frame:SetPoint("CENTER", 40, 40)
frame:SetClampedToScreen(true)
frame:SetFrameStrata("HIGH")
frame:Hide()

frame:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:SetBackdropColor(0, 0, 0, 0.8)
frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
frame.title:SetPoint("TOPLEFT", 12, -10)
frame.title:SetText("Ledger - depuracion")

----------------------------------------------------------------------
-- Redimensionado desde la esquina inferior derecha.
----------------------------------------------------------------------

frame:SetResizable(true)
if frame.SetResizeBounds then
    frame:SetResizeBounds(260, 160)
else
    frame:SetMinResize(260, 160)
end

local resizeHandle = CreateFrame("Button", nil, frame)
resizeHandle:SetSize(16, 16)
resizeHandle:SetPoint("BOTTOMRIGHT", -4, 4)
resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
resizeHandle:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
resizeHandle:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

----------------------------------------------------------------------
-- Contenido: EditBox multilinea de solo lectura dentro de un scroll.
----------------------------------------------------------------------

local scrollFrame = CreateFrame("ScrollFrame", "LedgerDebugScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 12, -32)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 36)

local editBox = CreateFrame("EditBox", nil, scrollFrame)
editBox:SetMultiLine(true)
editBox:SetAutoFocus(false)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(360)
editBox:SetScript("OnEscapePressed", editBox.ClearFocus)
-- Solo lectura: cualquier intento de teclear se deshace en el siguiente
-- disparo de OnTextChanged, pero el texto sigue siendo seleccionable con
-- el raton para copiar.
editBox:SetScript("OnTextChanged", function(self)
    if self.suppressChange then return end
    self.suppressChange = true
    self:SetText(self.currentText or "")
    self.suppressChange = false
end)

scrollFrame:SetScrollChild(editBox)

----------------------------------------------------------------------
-- Refresco manual + autorefresco cada 2s.
----------------------------------------------------------------------

local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
refreshButton:SetSize(80, 22)
refreshButton:SetPoint("BOTTOMLEFT", 10, 8)
refreshButton:SetText("Refrescar")

local autoRefreshBox = CreateFrame("CheckButton", "LedgerDebugAutoRefresh", frame, "UICheckButtonTemplate")
autoRefreshBox:SetSize(24, 24)
autoRefreshBox:SetPoint("LEFT", refreshButton, "RIGHT", 8, 0)

local autoRefreshLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
autoRefreshLabel:SetPoint("LEFT", autoRefreshBox, "RIGHT", 2, 0)
autoRefreshLabel:SetText("Auto (2s)")

Ledger.debugFrame = frame

-- currentSource: "state" (volcado de sesion/niveles, core/state_dump.lua)
-- o "log" (buffer de log, core/log.lua). Decide que compone Refresh().
local currentSource = "state"

local function ComposeContent()
    if currentSource == "log" then
        return Ledger.FormatLogBuffer(Ledger.logState)
    end
    return Ledger.FormatState(LedgerCharDB)
end

function Ledger.RefreshDebugFrame()
    local text = ComposeContent()
    editBox.currentText = text
    editBox.suppressChange = true
    editBox:SetText(text)
    editBox.suppressChange = false
end

-- Muestra el panel con la fuente indicada ("state" por defecto o "log")
-- y la recuerda para los refrescos siguientes (manual o automatico).
function Ledger.ShowDebugFrame(source)
    currentSource = source or "state"
    Ledger.RefreshDebugFrame()
    frame:Show()
end

function Ledger.ToggleDebugFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        Ledger.ShowDebugFrame("state")
    end
end

refreshButton:SetScript("OnClick", Ledger.RefreshDebugFrame)

local autoTicker
autoRefreshBox:SetScript("OnClick", function(self)
    if self:GetChecked() then
        autoTicker = C_Timer.NewTicker(2, Ledger.RefreshDebugFrame)
    elseif autoTicker then
        autoTicker:Cancel()
        autoTicker = nil
    end
end)
