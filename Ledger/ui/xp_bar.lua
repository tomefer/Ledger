-- Ledger - ui/xp_bar.lua
-- Current level's xp composition bar: anchored right above the native
-- xp bar, one colored segment per src stretch (merged by
-- core/xp_bar.lua: Ledger.ComputeBarSegments). Thin layer: computing
-- segments and their widths lives in core/, this file only paints them
-- with a pool of reusable textures.

local ADDON_NAME, Ledger = ...

-- Palette centralized in ui/palette.lua (Ledger.PALETTE), shared with
-- the time bar and its tooltips -- see that file for the colors and
-- why combat/nonCombat have no entry of their own here.
local PALETTE = Ledger.PALETTE
local RESTED_LIGHTEN_AMOUNT = 0.35

----------------------------------------------------------------------
-- Frame and anchoring to the native xp bar.
----------------------------------------------------------------------

-- Confirmed with /fstack in-game (Classic Era, 1.15.x): this client
-- does NOT use the classic "MainMenuExpBar" frame (that was the
-- initial assumption, ruled out) -- it uses the tracking-bar system
-- shared with retail
-- (Interface/AddOns/Blizzard_ActionBar/Classic/StatusTrackingBarTemplate.xml),
-- with the xp bar living inside the global container
-- "MainStatusTrackingBarContainer" as an ANONYMOUS child (no stable
-- global name -- what /fstack shows as
-- "MainStatusTrackingBarContainer.<hash>" is just how that tool
-- represents an unnamed frame, never a real variable to reference by
-- name). WoW Forever (build 1.60.1, interface 16001, see CLAUDE.md)
-- also has that same container, but unlike Classic Era its children
-- anchor TOPLEFT/BOTTOMRIGHT with no offset, so the container's own
-- bounds already ARE the bar's -- no child search needed there.
-- ANCHOR_CANDIDATES is tried in order, first one that exists wins;
-- MainMenuExpBar is kept only as a defensive fallback for a client
-- that has neither container shape (never actually reached on either
-- client confirmed so far).
local ANCHOR_CANDIDATES = { "MainStatusTrackingBarContainer", "MainMenuExpBar" }

-- Inside MainStatusTrackingBarContainer, finds the specific child
-- whose StatusBar's max matches UnitXPMax("player"). That container
-- can have more than one child at once (reputation, honor...)
-- confirmed in-game on Classic Era: with reputation tracking also
-- active, two children with a StatusBar show up, and comparing by
-- UnitXPMax is what tells them apart (the reputation one had a max
-- normalized to 1, not the real range). Returns nil if nothing
-- matches -- e.g. WoW Forever, whose container doesn't have this
-- child shape at all, or max level (no xp bar to match against).
local function FindMatchingChild(container)
    local xpMax = UnitXPMax("player")
    if not xpMax or xpMax <= 0 then
        Ledger.Log("trace", string.format("FindMatchingChild: UnitXPMax=%s, max level or no data yet", tostring(xpMax)))
        return nil
    end

    local children = { container:GetChildren() }
    Ledger.Log("trace", string.format("FindMatchingChild: xpMax=%d, %d children in the container", xpMax, #children))

    for _, child in ipairs(children) do
        local statusBar = child.StatusBar
        if statusBar then
            local _, max = statusBar:GetMinMaxValues()
            Ledger.Log("trace", string.format("FindMatchingChild: candidate with max=%s", tostring(max)))
            -- Tolerance instead of exact equality: in case the max
            -- comes in as a float with some internal Blizzard rounding.
            if max and math.abs(max - xpMax) < 0.5 then
                return child
            end
        end
    end
    return nil
end

-- Resolves what to anchor to. Returns (frame, sourceDescription), or
-- (nil, nil) if none of ANCHOR_CANDIDATES exists at all. Never
-- references a runtime-generated child name directly -- the matching
-- child (if any) is always found by live enumeration
-- (GetChildren/FindMatchingChild), never by a hardcoded name string.
local function FindNativeXPBar()
    for _, name in ipairs(ANCHOR_CANDIDATES) do
        local candidate = _G[name]
        if candidate then
            if name == "MainStatusTrackingBarContainer" then
                local child = FindMatchingChild(candidate)
                if child then
                    return child, name .. " (matched child)"
                end
                -- No matching child: this client's container already
                -- has the bar's own geometry (WoW Forever), so it
                -- serves directly instead of failing.
                return candidate, name .. " (container)"
            end
            return candidate, name
        end
    end
    return nil, nil
end

-- Whether the frame is currently in the degraded (no native anchor
-- found) fallback -- set by AnchorToNativeBar/DegradedAnchor below,
-- read by OnDragStart/OnDragStop so dragging only actually moves the
-- frame in that mode. Mouse stays enabled unconditionally (below):
-- the tooltip at the end of this file needs it regardless of anchor
-- mode, so gating on EnableMouse instead of this flag would silently
-- break the tooltip whenever natively anchored -- the common case.
local inDegradedMode = false

local frame = CreateFrame("Frame", "LedgerXPBar", UIParent)
frame:Hide()
frame:SetClampedToScreen(true)
frame:SetMovable(true)
frame:RegisterForDrag("LeftButton")
frame:SetScript("OnDragStart", function(self)
    if inDegradedMode then
        self:StartMoving()
    end
end)
frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if inDegradedMode and LedgerDB then
        local point, _, relativePoint, x, y = self:GetPoint()
        LedgerDB.barDefaultPos = {
            point         = point or "CENTER",
            relativePoint = relativePoint or "CENTER",
            x             = x or 0,
            y             = y or 0,
        }
    end
end)
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

-- Fallback when neither ANCHOR_CANDIDATES exists: instead of failing
-- to draw at all, place the frame at a movable default position
-- (LedgerDB.barDefaultPos, saved on drag -- see the frame's
-- OnDragStop above) with a fixed default width. Logged once per
-- session at INFO (never ERROR: this is a supported, working mode,
-- not a broken one).
local warnedDegraded = false
local function DegradedAnchor()
    if not warnedDegraded then
        Ledger.Log("info",
            "No native xp bar found to anchor to (neither MainStatusTrackingBarContainer nor MainMenuExpBar exist) -- showing the composition bar at a movable default position instead. Drag it where you want.")
        warnedDegraded = true
    end

    inDegradedMode = true

    local pos = (LedgerDB and LedgerDB.barDefaultPos) or Ledger.DEFAULTS.barDefaultPos
    frame:ClearAllPoints()
    frame:SetPoint(pos.point, UIParent, pos.relativePoint, pos.x, pos.y)
    frame:SetSize(Ledger.DEFAULTS.barDefaultWidth, (LedgerDB and LedgerDB.barHeight) or Ledger.DEFAULTS.barHeight)
    LayoutBorder()

    return frame:GetWidth()
end

-- Anchors the frame to the resolved native xp bar (FindNativeXPBar):
-- same width and same horizontal position, right above it. Falls back
-- to DegradedAnchor if nothing resolves. Always returns a usable
-- width -- never nil, there's always some anchor now, native or
-- degraded. Also records Ledger.xpBarAnchorInfo (source, width,
-- height) for /ldg probe to report.
local function AnchorToNativeBar()
    local nativeBar, source = FindNativeXPBar()

    local width
    if not nativeBar then
        width = DegradedAnchor()
        source = "degraded (no anchor found)"
    else
        inDegradedMode = false
        width = nativeBar:GetWidth()
        frame:SetSize(width, LedgerDB.barHeight or Ledger.DEFAULTS.barHeight)
        frame:ClearAllPoints()
        frame:SetPoint("BOTTOMLEFT", nativeBar, "TOPLEFT", 0, 1)
        frame:SetPoint("BOTTOMRIGHT", nativeBar, "TOPRIGHT", 0, 1)
        LayoutBorder()
    end

    Ledger.xpBarAnchorInfo = { source = source, width = width, height = frame:GetHeight() }
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
