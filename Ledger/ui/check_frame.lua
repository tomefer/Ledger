-- Ledger - ui/check_frame.lua
-- /ldg check panel: a text window (ui/text_window.lua) showing the
-- reconciliation between what Ledger recorded and what the game says is
-- real (core/check.lua). Thin layer: this file only reads the live
-- player values and paints the text core/ already built, discrepancy
-- marks included.

local ADDON_NAME, Ledger = ...

local frame, SetText = Ledger.CreateTextWindow({
    name       = "LedgerCheckFrame",
    scrollName = "LedgerCheckScrollFrame",
    width      = 620,
    height     = 420,
    x          = 0,
    y          = 0,
    minWidth   = 360,
    minHeight  = 220,
})
frame.title:SetText("Ledger - check")

-- Re-reads the live player values and LedgerCharDB and re-renders
-- (re-selecting everything: see ui/text_window.lua).
function Ledger.RenderCheckFrame()
    local result = Ledger.BuildCheck(LedgerCharDB, {
        level = UnitLevel("player"),
        xp    = UnitXP("player"),
    })
    SetText(Ledger.FormatCheck(result))
end

local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
refreshButton:SetSize(70, 22)
refreshButton:SetPoint("BOTTOMLEFT", 10, 8)
refreshButton:SetText("Refresh")
refreshButton:SetScript("OnClick", Ledger.RenderCheckFrame)

Ledger.checkFrame = frame

function Ledger.ToggleCheckFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        Ledger.RenderCheckFrame()
        frame:Show()
    end
end
