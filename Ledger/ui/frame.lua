-- Ledger - ui/frame.lua
-- Main frame and its persistence. Thin layer: this is where WoW API
-- usage is fine.

local ADDON_NAME, Ledger = ...

local SavePosition -- forward declaration (used in OnDragStop)

----------------------------------------------------------------------
-- Main frame
----------------------------------------------------------------------

local frame = CreateFrame("Frame", "LedgerFrame", UIParent, "BackdropTemplate")
frame:SetSize(200, 96)
frame:SetPoint("CENTER")            -- provisional, overwritten on login
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
frame:SetBackdropColor(0, 0, 0, 0.6)          -- semi-transparent black background
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

-- "Rested: included" / "Rested: excluded" (toggle /ldg rested)
frame.restedText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
frame.restedText:SetPoint("BOTTOM", 0, 10)

-- Drag with the left button
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
-- Xp update
----------------------------------------------------------------------

function Ledger.UpdateXP()
    local cur = UnitXP("player")
    local max = UnitXPMax("player")
    local xpText, pctText = Ledger.FormatXP(cur, max)
    frame.xpText:SetText(xpText)
    frame.pctText:SetText(pctText)
    Ledger.UpdateRestedLabel()
end

-- Reflects on the main panel whether the rested bonus counts toward the
-- session/level xp metrics (LedgerDB.includeRested, /ldg rested
-- toggle). Only indicates the state: it doesn't recompute anything on
-- its own.
function Ledger.UpdateRestedLabel()
    if not LedgerDB then return end
    frame.restedText:SetText(LedgerDB.includeRested and "Rested: included" or "Rested: excluded")
end

----------------------------------------------------------------------
-- Persistence
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
    -- Always anchor to UIParent: saving a reference to another frame
    -- isn't reliable across sessions.
    frame:SetPoint(p.point, UIParent, p.relativePoint, p.x, p.y)
end
