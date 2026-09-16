-- Ledger - ui/frame.lua
-- Frame principal y su persistencia. Capa fina: aqui si se usa la API de WoW.

local ADDON_NAME, Ledger = ...

local SavePosition -- declaracion adelantada (se usa en OnDragStop)

----------------------------------------------------------------------
-- Frame principal
----------------------------------------------------------------------

local frame = CreateFrame("Frame", "LedgerFrame", UIParent, "BackdropTemplate")
frame:SetSize(200, 96)
frame:SetPoint("CENTER")            -- provisional, se sobrescribe al login
frame:SetClampedToScreen(true)
frame:SetFrameStrata("MEDIUM")
frame:Hide()

frame:SetBackdrop({
    bgFile   = "Interface\Tooltips\UI-Tooltip-Background",
    edgeFile = "Interface\Tooltips\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
frame:SetBackdropColor(0, 0, 0, 0.6)          -- fondo negro semitransparente
frame:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
frame.title:SetPoint("TOP", 0, -10)
frame.title:SetText("XP TRACKER")

-- "12345 / 23456"
frame.xpText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
frame.xpText:SetPoint("CENTER", 0, -4)

-- "52.8%"
frame.pctText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.pctText:SetPoint("CENTER", 0, -20)

-- "Descanso: incluido" / "Descanso: excluido" (toggle /ldg rested)
frame.restedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.restedText:SetPoint("BOTTOM", 0, 10)

-- Arrastre con el boton izquierdo
frame:EnableMouse(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    SavePosition()
end)

Ledger.frame = frame

----------------------------------------------------------------------
-- Actualizacion de experiencia
----------------------------------------------------------------------

function Ledger.UpdateXP()
    local cur = UnitXP("player")
    local max = UnitXPMax("player")
    local xpText, pctText = Ledger.FormatXP(cur, max)
    frame.xpText:SetText(xpText)
    frame.pctText:SetText(pctText)
    Ledger.UpdateRestedLabel()
end

-- Refleja en el panel principal si el bono por descanso cuenta en las
-- metricas de xp de sesion/nivel (LedgerDB.includeRested, toggle
-- /ldg rested). Solo indica el estado: no recalcula nada por si solo.
function Ledger.UpdateRestedLabel()
    if not LedgerDB then return end
    frame.restedText:SetText(LedgerDB.includeRested and "Descanso: incluido" or "Descanso: excluido")
end

----------------------------------------------------------------------
-- Persistencia
----------------------------------------------------------------------

function SavePosition()
    if not LedgerDB then return end
    local point, _, relativePoint, x, y = frame:GetPoint()
    LedgerDB.pos = {
        point         = point or "CENTER",
        relativePoint = relativePoint or "CENTER",
        x             = x or 0,
        y             = y or 0,
    }
end
Ledger.SavePosition = SavePosition

function Ledger.RestorePosition()
    local p = LedgerDB.pos
    frame:ClearAllPoints()
    -- Anclamos siempre a UIParent: guardar una referencia a otro frame
    -- no es fiable entre sesiones.
    frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
end
