-- Ledger - ui/export_frame.lua
-- Export panel: a text window (ui/text_window.lua: movable, resizable,
-- read-only multiline EditBox pre-selected on every refresh so Ctrl+C
-- copies the whole dump immediately) showing the character's full data
-- (core/export.lua), either as JSON or CSV. Thin layer: serialization
-- lives in core/, this file only paints it.

local ADDON_NAME, Ledger = ...

local frame, SetText = Ledger.CreateTextWindow({
    name       = "LedgerExportFrame",
    scrollName = "LedgerExportScrollFrame",
    width      = 520,
    height     = 380,
    x          = -40,
    y          = -40,
    minWidth   = 320,
    minHeight  = 220,
})

----------------------------------------------------------------------
-- Format toggle (JSON / CSV) + manual refresh.
----------------------------------------------------------------------

-- "json" or "csv"; persists across hide/show within the same session
-- (not saved to any SavedVariable, same as ui/debug_frame.lua's
-- currentSource) so re-opening the panel doesn't lose the format the
-- player picked last.
local currentFormat = "json"

local function ComposeContent()
    if currentFormat == "csv" then
        return Ledger.ExportCSV(LedgerCharDB)
    end
    return Ledger.ExportJSON(LedgerCharDB)
end

-- Re-renders from the current LedgerCharDB (and re-selects everything:
-- see ui/text_window.lua).
function Ledger.RefreshExportFrame()
    frame.title:SetText(string.format("Ledger - export (%s)", currentFormat:upper()))
    SetText(ComposeContent())
end

local jsonButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
jsonButton:SetSize(60, 22)
jsonButton:SetPoint("BOTTOMLEFT", 10, 8)
jsonButton:SetText("JSON")
jsonButton:SetScript("OnClick", function()
    currentFormat = "json"
    Ledger.RefreshExportFrame()
end)

local csvButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
csvButton:SetSize(60, 22)
csvButton:SetPoint("LEFT", jsonButton, "RIGHT", 6, 0)
csvButton:SetText("CSV")
csvButton:SetScript("OnClick", function()
    currentFormat = "csv"
    Ledger.RefreshExportFrame()
end)

local refreshButton = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
refreshButton:SetSize(70, 22)
refreshButton:SetPoint("LEFT", csvButton, "RIGHT", 6, 0)
refreshButton:SetText("Refresh")
refreshButton:SetScript("OnClick", Ledger.RefreshExportFrame)

Ledger.exportFrame = frame

function Ledger.ToggleExportFrame()
    if frame:IsShown() then
        frame:Hide()
    else
        Ledger.RefreshExportFrame()
        frame:Show()
    end
end
