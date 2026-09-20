-- Ledger - ui/time_bar.lua
-- Current level's activity bar: parallel to the xp composition bar
-- (same width and horizontal position, 2px gap above it, its own thin
-- height -- LedgerDB.barHeight -- since the xp bar now takes the native
-- bar's height),
-- with the 4 core/ticks.lua activities in a fixed order (combat,
-- non-combat, travel, dead). PROPORTIONAL axis: always occupies 100% of
-- the width, not comparable pixel-to-pixel with the xp bar (different
-- axes). Everything is a share of the level's samples: no absolute time
-- is ever shown. Thin layer: segment computation lives in core/, this
-- file only paints with reusable textures (one fixed per activity:
-- they're always the same 4, in the same order, so unlike the xp bar
-- there's no need for a dynamic pool). Hover (the unified tooltip over
-- both bars) lives in ui/bars_hover.lua.

local ADDON_NAME, Ledger = ...

local PALETTE = Ledger.PALETTE
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8" -- see ui/xp_bar.lua: SetTexture with numbers doesn't paint a color in this client

local frame = CreateFrame("Frame", "LedgerTimeBar", UIParent)
frame:Hide()
Ledger.timeBarFrame = frame

----------------------------------------------------------------------
-- One fixed texture per activity (never a pool: they're always the same
-- 4, in Ledger.TICK_KEYS) + border, same as the xp bar.
----------------------------------------------------------------------

local activityTextures = {}
for _, key in ipairs(Ledger.TICK_KEYS) do
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(WHITE_TEXTURE)
    activityTextures[key] = tex
end

local BORDER_COLOR = { 0, 0, 0, 0.6 } -- black at 60%, same as the xp bar

local function CreateBorderPiece()
    local tex = frame:CreateTexture(nil, "OVERLAY")
    tex:SetTexture(WHITE_TEXTURE)
    tex:SetVertexColor(BORDER_COLOR[1], BORDER_COLOR[2], BORDER_COLOR[3], BORDER_COLOR[4])
    return tex
end

local borderTop    = CreateBorderPiece()
local borderBottom = CreateBorderPiece()
local borderLeft   = CreateBorderPiece()
local borderRight  = CreateBorderPiece()

local function LayoutBorder()
    borderTop:ClearAllPoints()
    borderTop:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borderTop:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borderTop:SetHeight(1)

    borderBottom:ClearAllPoints()
    borderBottom:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borderBottom:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borderBottom:SetHeight(1)

    borderLeft:ClearAllPoints()
    borderLeft:SetPoint("TOPLEFT", frame, "TOPLEFT", 0, 0)
    borderLeft:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 0, 0)
    borderLeft:SetWidth(1)

    borderRight:ClearAllPoints()
    borderRight:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
    borderRight:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 0, 0)
    borderRight:SetWidth(1)
end

-- Anchors the parallel frame to the xp bar: same width and horizontal
-- position, 2px gap above it, height LedgerDB.barHeight. The points are set whatever
-- the xp bar's width is (they follow it live, and the xp/hour number
-- hangs from this frame, so it must be anchored from the start); returns
-- the width, which can still be 0 while the native bar has no final
-- layout yet -- the caller must not paint then.
local function AnchorToXPBar()
    local xpBar = Ledger.xpBarFrame
    if not xpBar then
        return nil
    end
    local width = xpBar:GetWidth() or 0

    frame:SetSize(width, LedgerDB.barHeight or Ledger.DEFAULTS.barHeight)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", xpBar, "TOPLEFT", 0, 2)
    frame:SetPoint("BOTTOMRIGHT", xpBar, "TOPRIGHT", 0, 2)
    LayoutBorder()
    return width
end

local function PaintSegments(segments)
    for _, key in ipairs(Ledger.TICK_KEYS) do
        activityTextures[key]:Hide()
    end
    for _, segment in ipairs(segments) do
        local tex   = activityTextures[segment.key]
        local color = PALETTE[segment.key] or PALETTE._fallback
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", frame, "LEFT", segment.offset, 0)
        tex:SetSize(math.max(segment.width, 0.01), frame:GetHeight())
        tex:SetVertexColor(color[1], color[2], color[3], 1)
        tex:Show()
    end
end

----------------------------------------------------------------------
-- Data: the level in progress's live activity counters
-- (LedgerCharDB.levelTicks), incremented by the 1s sampler in
-- ui/xp_capture.lua -- so the bar just reads them, there is nothing to
-- concatenate or derive.
----------------------------------------------------------------------

-- Redraw: called from the same 1s ticker that samples the activity
-- (ui/xp_capture.lua), never from xp events -- travel/non-combat/dead
-- stretches don't generate any, and tying it to kills would leave the
-- bar frozen most of the time.
function Ledger.RedrawTimeBar()
    if not frame:IsShown() then return end
    local width = AnchorToXPBar()
    if not width or width <= 0 then return end

    PaintSegments(Ledger.ComputeTimeBarSegments(LedgerCharDB.levelTicks, width))
end

----------------------------------------------------------------------
-- /ldg time
----------------------------------------------------------------------

function Ledger.ToggleTimeBar()
    if frame:IsShown() then
        frame:Hide()
        LedgerDB.timeBarShown = false
        Ledger.RestoreRatePosition() -- the xp/hour number drops back onto the xp bar
        return false
    end

    frame:Show()
    LedgerDB.timeBarShown = true
    Ledger.RedrawTimeBar()
    Ledger.RestoreRatePosition() -- ...and stacks on top of this bar again
    return true
end
