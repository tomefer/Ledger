-- Ledger - ui/export_frame.lua
-- Export panel: a movable, resizable frame with a read-only, multiline
-- EditBox (pre-selected on every refresh so Ctrl+C copies the whole
-- dump immediately, no need to click into the box first) showing the
-- character's full data (core/export.lua), either as JSON or CSV.
-- Thin layer: serialization lives in core/, this file only paints it.
--
-- Escape closes the panel two ways at once, since either one alone
-- can miss: UISpecialFrames only fires its global handler when no
-- focused frame consumes the Escape key first, and an EditBox with
-- focus (the normal state here, so Ctrl+C works right away) consumes
-- it via its own OnEscapePressed instead of letting it propagate.

local ADDON_NAME, Ledger = ...

local frame = CreateFrame("Frame", "LedgerExportFrame", UIParent, "BackdropTemplate")
frame:SetSize(520, 380)
frame:SetPoint("CENTER", -40, -40)
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

-- Pending in-game verification, like the rest of this file's frame
-- APIs (see CLAUDE.md): UISpecialFrames is the standard mechanism
-- Blizzard's own panels use to close on Escape without needing
-- keyboard focus, but hasn't been confirmed against this client yet.
table.insert(UISpecialFrames, "LedgerExportFrame")

----------------------------------------------------------------------
-- Resizing from the bottom-right corner (same technique as
-- ui/debug_frame.lua).
----------------------------------------------------------------------

frame:SetResizable(true)
if frame.SetResizeBounds then
    frame:SetResizeBounds(320, 220)
else
    frame:SetMinResize(320, 220)
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
-- Content: read-only multiline EditBox inside a scroll frame.
----------------------------------------------------------------------

local scrollFrame = CreateFrame("ScrollFrame", "LedgerExportScrollFrame", frame, "UIPanelScrollFrameTemplate")
scrollFrame:SetPoint("TOPLEFT", 12, -32)
scrollFrame:SetPoint("BOTTOMRIGHT", -30, 36)

local editBox = CreateFrame("EditBox", nil, scrollFrame)
editBox:SetMultiLine(true)
editBox:SetAutoFocus(false)
editBox:SetFontObject(ChatFontNormal)
editBox:SetWidth(460)

-- Read-only: any typing attempt gets undone on the next OnTextChanged
-- firing, but the text stays selectable/focusable for copying (same
-- trick as ui/debug_frame.lua).
editBox:SetScript("OnTextChanged", function(self)
    if self.suppressChange then return end
    self.suppressChange = true
    self:SetText(self.currentText or "")
    self.suppressChange = false
end)

editBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
    frame:Hide()
end)

scrollFrame:SetScrollChild(editBox)

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

-- Re-renders from the current LedgerCharDB and immediately
-- re-selects everything, so Ctrl+C copies the whole dump right after
-- opening the panel or switching format, with no click needed first.
function Ledger.RefreshExportFrame()
    frame.title:SetText(string.format("Ledger - export (%s)", currentFormat:upper()))
    local text = ComposeContent()
    editBox.currentText = text
    editBox.suppressChange = true
    editBox:SetText(text)
    editBox.suppressChange = false
    editBox:SetFocus()
    editBox:HighlightText()
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
