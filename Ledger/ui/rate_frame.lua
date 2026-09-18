-- Ledger - ui/rate_frame.lua
-- The headline xp/hour number: a frame of its own, anchored above the
-- xp composition bar, plus a custom hover panel with the breakdown
-- (core/rate.lua: Ledger.BuildRatePanelSections). Thin layer: all the
-- rate math and panel content lives in core/, this file only reads
-- WoW APIs/LedgerCharDB and paints the result.

local ADDON_NAME, Ledger = ...

----------------------------------------------------------------------
-- Headline number frame: anchored above the xp bar (Ledger.xpBarFrame,
-- itself always positioned -- natively or in its own degraded fallback,
-- see ui/xp_bar.lua), centered horizontally with it, 2px gap. A single
-- anchor point (BOTTOM->TOP) keeps that live relationship automatically
-- as either frame moves or resizes, with no re-anchoring needed here.
----------------------------------------------------------------------

local PADDING_X = 12
local PADDING_Y = 6

local frame = CreateFrame("Frame", "LedgerRateFrame", UIParent, "BackdropTemplate")
frame:Hide()
frame:SetFrameStrata("HIGH") -- above the xp/time bars, so it reads as "destacado" if they overlap
frame:SetClampedToScreen(true)
frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    tile     = true,
    tileSize = 16,
    insets   = { left = 2, right = 2, top = 2, bottom = 2 },
})
frame:SetBackdropColor(0, 0, 0, 0.6)

local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalHuge")
text:SetPoint("CENTER")
text:SetTextColor(1, 1, 1, 1)

local function ResizeToText()
    frame:SetSize(text:GetStringWidth() + PADDING_X * 2, text:GetStringHeight() + PADDING_Y * 2)
end

----------------------------------------------------------------------
-- Position: LedgerDB.ratePos if the player has dragged it, otherwise
-- anchored above the xp bar by default. Restored once at PLAYER_LOGIN
-- (ui/events.lua), same as ui/frame.lua's main panel.
----------------------------------------------------------------------

function Ledger.RestoreRatePosition()
    frame:ClearAllPoints()
    local pos = LedgerDB and LedgerDB.ratePos
    if pos then
        frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    else
        frame:SetPoint("BOTTOM", Ledger.xpBarFrame, "TOP", 0, 2)
    end
end

frame:SetMovable(true)
frame:EnableMouse(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", frame.StartMoving)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if LedgerDB then
        local point, _, relativePoint, x, y = self:GetPoint()
        LedgerDB.ratePos = {
            point         = point or "CENTER",
            relativePoint = relativePoint or "CENTER",
            x             = x or 0,
            y             = y or 0,
        }
    end
end)

Ledger.rateFrame = frame

----------------------------------------------------------------------
-- Hover panel: a frame of its own, never GameTooltip -- built from
-- Ledger.BuildRatePanelSections' generic { title=, rows={label=,value=,
-- color=} } shape via a pool of reusable line FontStrings, so a future
-- section (level history, per-source breakdown...) just means more
-- lines get pulled from the same pool, no layout code to touch here.
----------------------------------------------------------------------

local hoverPanel = CreateFrame("Frame", "LedgerRateHoverPanel", UIParent, "BackdropTemplate")
hoverPanel:Hide()
hoverPanel:SetFrameStrata("TOOLTIP")
hoverPanel:SetBackdrop({
    bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile     = true,
    tileSize = 16,
    edgeSize = 16,
    insets   = { left = 4, right = 4, top = 4, bottom = 4 },
})
hoverPanel:SetBackdropColor(0, 0, 0, 0.8)
hoverPanel:SetBackdropBorderColor(0.4, 0.4, 0.4, 0.8)

local HOVER_PADDING = 10
local LINE_GAP = 2
local TITLE_COLOR = { 1, 0.82, 0 } -- gold, matches Blizzard's own tooltip section headers

local linePool = {}
local function GetOrCreateLine(index)
    local line = linePool[index]
    if not line then
        line = hoverPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        linePool[index] = line
    end
    return line
end

-- Renders `sections` (Ledger.BuildRatePanelSections' shape) into the
-- line pool and resizes the panel to fit. Walks the list generically:
-- never assumes how many sections or rows there are.
local function RenderHoverPanel(sections)
    local lineIndex = 0
    local maxWidth = 0
    local y = -HOVER_PADDING

    local function PlaceLine(text_, color)
        lineIndex = lineIndex + 1
        local line = GetOrCreateLine(lineIndex)
        line:SetText(text_)
        line:SetTextColor(color[1], color[2], color[3], 1)
        line:ClearAllPoints()
        line:SetPoint("TOPLEFT", HOVER_PADDING, y)
        line:Show()
        y = y - line:GetStringHeight() - LINE_GAP
        maxWidth = math.max(maxWidth, line:GetStringWidth())
    end

    for _, section in ipairs(sections) do
        PlaceLine(section.title, TITLE_COLOR)
        for _, row in ipairs(section.rows) do
            PlaceLine(string.format("%s: %s", row.label, row.value), row.color or Ledger.RATE_DEFAULT_COLOR)
        end
    end

    for i = lineIndex + 1, #linePool do
        linePool[i]:Hide()
    end

    hoverPanel:SetSize(maxWidth + HOVER_PADDING * 2, -y + HOVER_PADDING - LINE_GAP)
end

----------------------------------------------------------------------
-- Refresh: recomputes both rates from LedgerCharDB and redraws the
-- headline number, called from the 1s ticker below. Also re-renders
-- the hover panel if it's currently shown, so it doesn't go stale
-- while the player is hovering. lastRates is reused by OnEnter instead
-- of recomputing on hover: the ticker already keeps it fresh to within
-- a second.
----------------------------------------------------------------------

local lastRates = { sessionRate = nil, levelRate = nil }

local function CurrentSessionAndLevelSessions()
    local sessions = LedgerCharDB.sessions
    return sessions[#sessions], sessions
end

function Ledger.RefreshRateFrame()
    if not frame:IsShown() then return end

    local session, levelSessions = CurrentSessionAndLevelSessions()
    local sessionElapsed = session and (time() - session.t0) or 0
    -- nil while the played-time baseline is unknown: the level rate
    -- then shows "-" instead of dividing by a made-up number.
    local levelElapsed = Ledger.LevelPlayedTime(LedgerCharDB)

    lastRates = Ledger.ComputeHeadlineRates(session, levelSessions, sessionElapsed, levelElapsed, LedgerDB.includeRested)

    text:SetText(Ledger.FormatXPRate(lastRates.sessionRate))
    ResizeToText()

    if hoverPanel:IsShown() then
        RenderHoverPanel(Ledger.BuildRatePanelSections(lastRates))
    end
end

C_Timer.NewTicker(1, Ledger.RefreshRateFrame)

frame:SetScript("OnEnter", function(self)
    RenderHoverPanel(Ledger.BuildRatePanelSections(lastRates))
    hoverPanel:ClearAllPoints()
    hoverPanel:SetPoint("BOTTOM", self, "TOP", 0, 4)
    hoverPanel:Show()
end)
frame:SetScript("OnLeave", function()
    hoverPanel:Hide()
end)

----------------------------------------------------------------------
-- /ldg rate
----------------------------------------------------------------------

function Ledger.ToggleRateFrame()
    if frame:IsShown() then
        frame:Hide()
        hoverPanel:Hide()
        LedgerDB.rateShown = false
        return false
    end

    frame:Show()
    LedgerDB.rateShown = true
    Ledger.RefreshRateFrame()
    return true
end
