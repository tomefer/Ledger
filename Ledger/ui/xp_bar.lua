-- Ledger - ui/xp_bar.lua
-- Current level's xp composition bar: anchored right above the native
-- xp bar, one colored segment per src stretch (merged by
-- core/xp_bar.lua: Ledger.ComputeBarSegments). Thin layer: computing
-- segments and their widths lives in core/, this file only paints them
-- with a pool of reusable textures.

local ADDON_NAME, Ledger = ...

-- Palette centralized in ui/palette.lua (Ledger.PALETTE), shared with
-- the time bar and its tooltips -- see that file for the colors and
-- why active/idle have no entry of their own here.
local PALETTE = Ledger.PALETTE
local RESTED_LIGHTEN_AMOUNT = 0.35

----------------------------------------------------------------------
-- Frame and anchoring to the native xp bar.
----------------------------------------------------------------------

-- Confirmed with /fstack in-game: this client does NOT use the classic
-- "MainMenuExpBar" frame (that was the initial assumption, ruled out).
-- It uses the tracking-bar system shared with retail
-- (Interface/AddOns/Blizzard_ActionBar/Classic/StatusTrackingBarTemplate.xml):
-- the xp bar lives inside the global container
-- "MainStatusTrackingBarContainer", as an ANONYMOUS child (no stable
-- global name -- what /fstack shows as
-- "MainStatusTrackingBarContainer.<hash>" is just how that tool
-- represents an unnamed frame, not a real variable). That container can
-- have more than one child at once (reputation, honor...) confirmed
-- in-game: with reputation tracking also active, two children with a
-- StatusBar show up. The right one is located by comparing each
-- StatusBar's max against UnitXPMax("player") -- confirmed in-game
-- that the xp child is the only one whose max matches (the reputation
-- one had a max normalized to 1, not the real range).
local function FindNativeXPBar()
    if not MainStatusTrackingBarContainer then
        Ledger.Log("trace", "FindNativeXPBar: MainStatusTrackingBarContainer does not exist")
        return nil
    end

    local xpMax = UnitXPMax("player")
    if not xpMax or xpMax <= 0 then
        Ledger.Log("trace", string.format("FindNativeXPBar: UnitXPMax=%s, max level or no data yet", tostring(xpMax)))
        return nil -- max level: no xp bar to anchor to
    end

    local children = { MainStatusTrackingBarContainer:GetChildren() }
    Ledger.Log("trace", string.format("FindNativeXPBar: xpMax=%d, %d children in the container", xpMax, #children))

    for _, child in ipairs(children) do
        local statusBar = child.StatusBar
        if statusBar then
            local _, max = statusBar:GetMinMaxValues()
            Ledger.Log("trace", string.format("FindNativeXPBar: candidate with max=%s", tostring(max)))
            -- Tolerance instead of exact equality: in case the max
            -- comes in as a float with some internal Blizzard rounding.
            if max and math.abs(max - xpMax) < 0.5 then
                return child
            end
        end
    end
    return nil
end

local frame = CreateFrame("Frame", "LedgerXPBar", UIParent)
frame:Hide()
Ledger.xpBarFrame = frame

----------------------------------------------------------------------
-- Pool of reusable texture pairs (base + rested): never created or
-- destroyed on an event, only shown/hidden.
----------------------------------------------------------------------

local texturePairPool = {}
local activeCount = 0

-- Blizzard's classic 8x8 white texture: the traditional way (works
-- since Vanilla) to paint a solid color is to apply this texture and
-- tint it with SetVertexColor, not calling SetTexture with numbers --
-- that gets interpreted as SetTexture(fileID, wrapH, wrapV,
-- filterMode), not as RGB (confirmed in-game: SetTexture(1,0,1,1),
-- which should be magenta, came out green -- fileID 1 is some
-- unrelated texture).
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function GetOrCreatePair(index)
    local pair = texturePairPool[index]
    if not pair then
        pair = {
            base   = frame:CreateTexture(nil, "ARTWORK"),
            rested = frame:CreateTexture(nil, "ARTWORK", nil, 1), -- above base
        }
        pair.base:SetTexture(WHITE_TEXTURE)
        pair.rested:SetTexture(WHITE_TEXTURE)
        texturePairPool[index] = pair
    end
    pair.base:Show()
    return pair
end

local function ReleaseFrom(index)
    for i = index, #texturePairPool do
        texturePairPool[i].base:Hide()
        texturePairPool[i].rested:Hide()
    end
end

----------------------------------------------------------------------
-- Border: black at 60%, 1px, around the whole bar, to visually
-- separate it from the native xp bar right below. Four thin textures
-- in OVERLAY (above the segments in ARTWORK), created once and only
-- repositioned when the frame's size changes (AnchorToNativeBar),
-- never recreated.
----------------------------------------------------------------------

local BORDER_COLOR = { 0, 0, 0, 0.6 } -- black at 60%

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

local function PaintSegment(pair, segment)
    local color  = PALETTE[segment.src] or PALETTE._fallback
    local height = frame:GetHeight()

    pair.base:ClearAllPoints()
    pair.base:SetPoint("LEFT", frame, "LEFT", segment.offset, 0)
    pair.base:SetSize(math.max(segment.width, 0.01), height)
    pair.base:SetVertexColor(color[1], color[2], color[3], 1)
    pair.base:Show()

    if segment.restedWidth > 0 then
        local restedColor = Ledger.LightenColor(color, RESTED_LIGHTEN_AMOUNT)
        pair.rested:ClearAllPoints()
        pair.rested:SetPoint("RIGHT", pair.base, "RIGHT", 0, 0)
        pair.rested:SetSize(math.max(segment.restedWidth, 0.01), height)
        pair.rested:SetVertexColor(restedColor[1], restedColor[2], restedColor[3], 1)
        pair.rested:Show()
    else
        pair.rested:Hide()
    end
end

-- Anchors the frame to the native xp bar: same width and same
-- horizontal position, right above it. Returns the available width in
-- pixels, or nil if it can't be found (max level, or the container
-- doesn't exist in this client; logged as ERROR only once, not on
-- every attempt).
local warnedMissingNativeBar = false
local function AnchorToNativeBar()
    local nativeBar = FindNativeXPBar()
    if not nativeBar then
        if not warnedMissingNativeBar and UnitXPMax("player") > 0 then
            Ledger.Log("error",
                "Could not find the native xp bar inside MainStatusTrackingBarContainer (comparing by UnitXPMax). This client might not have that container -- check ui/xp_bar.lua: FindNativeXPBar.")
            warnedMissingNativeBar = true
        end
        return nil
    end

    local width = nativeBar:GetWidth()
    frame:SetSize(width, LedgerDB.barHeight or Ledger.DEFAULTS.barHeight)
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", nativeBar, "TOPLEFT", 0, 1)
    frame:SetPoint("BOTTOMRIGHT", nativeBar, "TOPRIGHT", 0, 1)
    LayoutBorder()
    return width
end

----------------------------------------------------------------------
-- Data: all of the current level's sessions (never just the active
-- one, so a /ldg reset doesn't alter the view) + xp earned before
-- tracking started.
----------------------------------------------------------------------

local function CurrentSegments(widthPx)
    local sessions  = LedgerCharDB.sessions
    local flatArray = Ledger.ConcatSeries(sessions, Ledger.SERIES.xp)
    local initialXP = sessions[1] and sessions[1].initialXP or 0
    local maxXP     = UnitXPMax("player")
    return Ledger.ComputeBarSegments(flatArray, initialXP, widthPx, maxXP)
end

-- Full redraw: recomputes all segments from scratch and reuses (or
-- creates, if it needs to grow) the pool's textures. Used on level
-- change or on login; new events within the same level use
-- Ledger.ExtendXPBar instead.
--
-- Returns (ok, width, segmentCount) so the caller (e.g. the /ldg bar
-- command) can report immediately without depending on the log being
-- enabled: ok=false if the frame is hidden or it couldn't anchor to
-- the native bar.
function Ledger.RedrawXPBarFull()
    if not frame:IsShown() then return false end
    local width = AnchorToNativeBar()
    if not width then return false end

    local segments = CurrentSegments(width)
    Ledger.Log("trace", string.format("RedrawXPBarFull: width=%dpx, %d segments", width, #segments))
    for i, segment in ipairs(segments) do
        PaintSegment(GetOrCreatePair(i), segment)
    end
    activeCount = #segments
    ReleaseFrom(activeCount + 1)
    return true, width, #segments
end

-- Incremental redraw: called after each new event recorded in the
-- active session. The width-splitting arithmetic (core/xp_bar.lua:
-- RoundedWidths) is prefix-stable -- appending an event never changes
-- the already-computed width of segments before the last one -- so it's
-- only ever necessary to repaint the last existing segment (if it
-- grew) or add a new one, without touching or recreating the rest.
function Ledger.ExtendXPBar()
    if not frame:IsShown() then return end
    local width = frame:GetWidth()
    if not width or width <= 0 then
        Ledger.Log("trace", string.format("ExtendXPBar: frame has no width yet (%s)", tostring(width)))
        return
    end

    local segments = CurrentSegments(width)
    local previousCount = activeCount
    Ledger.Log("trace", string.format("ExtendXPBar: %d segments (was %d)", #segments, previousCount))

    if #segments == previousCount then
        if previousCount > 0 then
            PaintSegment(GetOrCreatePair(previousCount), segments[previousCount])
        end
    elseif #segments == previousCount + 1 then
        if previousCount > 0 then
            PaintSegment(GetOrCreatePair(previousCount), segments[previousCount])
        end
        PaintSegment(GetOrCreatePair(previousCount + 1), segments[previousCount + 1])
        activeCount = previousCount + 1
    else
        -- Unexpected case (the segment count changed by more than one
        -- at once): fall back to a full redraw instead of leaving the
        -- bar half-updated.
        Ledger.RedrawXPBarFull()
    end
end

----------------------------------------------------------------------
-- /ldg bar
----------------------------------------------------------------------

-- Returns (shown, ok, width, segmentCount): shown indicates whether the
-- bar ended up visible after the toggle; the rest only makes sense when
-- shown is true (see Ledger.RedrawXPBarFull).
function Ledger.ToggleXPBar()
    if frame:IsShown() then
        frame:Hide()
        LedgerDB.barShown = false
        return false
    end

    frame:Show()
    LedgerDB.barShown = true
    local ok, width, segmentCount = Ledger.RedrawXPBarFull()
    return true, ok, width, segmentCount
end

----------------------------------------------------------------------
-- Tooltip: xp breakdown by source for the current level (all sessions,
-- same as the bar -- never just the active one). Uses the SAME
-- Ledger.PALETTE table that paints the segments, so the bar and the
-- tooltip can never fall out of sync on each source's color.
----------------------------------------------------------------------

local SRC_LABELS = {
    kill    = "Kills",
    quest   = "Quests",
    explore = "Exploration",
    unknown = "Unknown",
}

frame:EnableMouse(true)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Level xp composition", 1, 1, 1)

    local sessions = LedgerCharDB.sessions
    local bySource = Ledger.XPBySourceAcrossSessions(sessions)

    local totalRested = 0
    for _, session in ipairs(sessions) do
        totalRested = totalRested + Ledger.TotalRested(session)
    end

    for _, src in ipairs({ "kill", "quest", "explore", "unknown" }) do
        local xp    = bySource[src] or 0
        local color = PALETTE[src]
        GameTooltip:AddLine(string.format("%s: %d xp", SRC_LABELS[src], xp), color[1], color[2], color[3])
    end

    if totalRested > 0 then
        GameTooltip:AddLine(string.format("Rested: %d xp", totalRested), 1, 1, 1)
    end

    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
