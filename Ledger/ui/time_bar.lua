-- Ledger - ui/time_bar.lua
-- Current level's time-split bar: parallel to the xp composition bar
-- (same width and horizontal position, same height, 2px gap above it),
-- with the 4 core/time_buckets.lua buckets in a fixed order (active,
-- downtime, travel, dead). PROPORTIONAL axis: always occupies 100% of
-- the width, not comparable pixel-to-pixel with the xp bar (different
-- axes). Thin layer: segment computation and tooltip formatting live in
-- core/, this file only paints with reusable textures (one fixed per
-- bucket: they're always the same 4, in the same order, so unlike the
-- xp bar there's no need for a dynamic pool).

local ADDON_NAME, Ledger = ...

local PALETTE = Ledger.PALETTE
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8" -- see ui/xp_bar.lua: SetTexture with numbers doesn't paint a color in this client

local frame = CreateFrame("Frame", "LedgerTimeBar", UIParent)
frame:Hide()
Ledger.timeBarFrame = frame

----------------------------------------------------------------------
-- One fixed texture per bucket (never a pool: they're always the same
-- 4, in Ledger.TIME_BUCKET_ORDER) + border, same as the xp bar.
----------------------------------------------------------------------

local bucketTextures = {}
for _, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(WHITE_TEXTURE)
    bucketTextures[bucket] = tex
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
-- position, same height, 2px gap above it. Returns the width, or nil if
-- the xp bar doesn't have a valid size yet (e.g. it has never anchored
-- to the native bar).
local function AnchorToXPBar()
    local xpBar = Ledger.xpBarFrame
    local width = xpBar and xpBar:GetWidth()
    if not width or width <= 0 then
        return nil
    end

    frame:SetSize(width, xpBar:GetHeight())
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", xpBar, "TOPLEFT", 0, 2)
    frame:SetPoint("BOTTOMRIGHT", xpBar, "TOPRIGHT", 0, 2)
    LayoutBorder()
    return width
end

local function PaintSegments(segments)
    for _, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
        bucketTextures[bucket]:Hide()
    end
    for _, segment in ipairs(segments) do
        local tex   = bucketTextures[segment.bucket]
        local color = PALETTE[segment.bucket] or PALETTE._fallback
        tex:ClearAllPoints()
        tex:SetPoint("LEFT", frame, "LEFT", segment.offset, 0)
        tex:SetSize(math.max(segment.width, 0.01), frame:GetHeight())
        tex:SetVertexColor(color[1], color[2], color[3], 1)
        tex:Show()
    end
end

----------------------------------------------------------------------
-- Data: all of the current level's sessions (same as the xp bar),
-- concatenated (core/series.lua: Ledger.ConcatSeries) and derived fresh
-- every redraw (core/time_buckets.lua: Ledger.ComputeBucketsFromState)
-- -- no live tracker to preview: the raw per-second sample IS the data,
-- appended for real every second by ui/xp_capture.lua's sampler, so the
-- bar already grows on its own without any special-casing here.
----------------------------------------------------------------------

local function CurrentBuckets()
    local rawState = Ledger.ConcatSeries(LedgerCharDB.sessions, Ledger.SERIES.state)
    return Ledger.ComputeBucketsFromState(rawState)
end

-- Redraw: called from the same 1s ticker that samples the raw state
-- (ui/xp_capture.lua), never from xp events -- travel/downtime/dead
-- stretches don't generate any, and tying it to kills would leave the
-- bar frozen most of the time.
function Ledger.RedrawTimeBar()
    if not frame:IsShown() then return end
    local width = AnchorToXPBar()
    if not width then return end

    local segments = Ledger.ComputeTimeBarSegments(CurrentBuckets(), width)
    PaintSegments(segments)
end

----------------------------------------------------------------------
-- /ldg time
----------------------------------------------------------------------

function Ledger.ToggleTimeBar()
    if frame:IsShown() then
        frame:Hide()
        LedgerDB.timeBarShown = false
        return false
    end

    frame:Show()
    LedgerDB.timeBarShown = true
    Ledger.RedrawTimeBar()
    return true
end

----------------------------------------------------------------------
-- Tooltip: each bucket with its absolute time and percentage
-- (core/time_bar.lua: Ledger.FormatTimeBarTooltip, a pure function),
-- each line colored with the SAME Ledger.PALETTE that paints the
-- segments.
----------------------------------------------------------------------

frame:EnableMouse(true)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Level time split", 1, 1, 1)

    for _, line in ipairs(Ledger.FormatTimeBarTooltip(CurrentBuckets())) do
        local color = PALETTE[line.bucket] or PALETTE._fallback
        GameTooltip:AddLine(line.text, color[1], color[2], color[3])
    end

    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
