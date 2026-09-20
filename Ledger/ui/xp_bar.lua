-- Ledger - ui/xp_bar.lua
-- Current level's xp composition bar: one colored segment per src stretch
-- (merged by core/xp_bar.lua: Ledger.ComputeBarSegments). By default it
-- REPLACES the native xp bar: same position and size (anchored to the
-- native bar's own corners), on top of it at a higher frame level, with
-- the native bar's fill hidden (never its container: its geometry is the
-- anchor and the size reference). LedgerDB.replaceNative = false (/ldg
-- native) puts it back the way it started: native bar untouched and this
-- one sitting above it. Thin layer: computing segments and their widths
-- lives in core/, this file only paints them with a pool of reusable
-- textures. Hover (label + tooltip) lives in ui/bars_hover.lua.

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
Ledger.xpBarFrame = frame

-- This frame takes no mouse of its own: the single hover zone over both
-- bars (ui/bars_hover.lua) does, and forwards the drag here. Dragging only
-- does anything in the degraded mode (see inDegradedMode).
function Ledger.StartXPBarDrag()
    if inDegradedMode then
        frame:StartMoving()
    end
end

function Ledger.StopXPBarDrag()
    frame:StopMovingOrSizing()
    if inDegradedMode and LedgerDB then
        local point, _, relativePoint, x, y = frame:GetPoint()
        LedgerDB.barDefaultPos = {
            point         = point or "CENTER",
            relativePoint = relativePoint or "CENTER",
            x             = x or 0,
            y             = y or 0,
        }
    end
end

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

-- Segments span the frame's full height by anchoring to its top and
-- bottom edges instead of copying its height at paint time: the frame's
-- height now comes from the native bar's (see AnchorToNativeBar), which
-- may not be laid out yet when a segment is first painted.
local function PaintSegment(pair, segment)
    local color = PALETTE[segment.src] or PALETTE._fallback

    pair.base:ClearAllPoints()
    pair.base:SetPoint("TOPLEFT", frame, "TOPLEFT", segment.offset, 0)
    pair.base:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", segment.offset, 0)
    pair.base:SetWidth(math.max(segment.width, 0.01))
    pair.base:SetVertexColor(color[1], color[2], color[3], 1)
    pair.base:Show()

    if segment.restedWidth > 0 then
        local restedColor = Ledger.LightenColor(color, RESTED_LIGHTEN_AMOUNT)
        pair.rested:ClearAllPoints()
        pair.rested:SetPoint("TOPRIGHT", pair.base, "TOPRIGHT", 0, 0)
        pair.rested:SetPoint("BOTTOMRIGHT", pair.base, "BOTTOMRIGHT", 0, 0)
        pair.rested:SetWidth(math.max(segment.restedWidth, 0.01))
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

-- Anchors the frame to the resolved native xp bar (FindNativeXPBar).
-- Replacing (LedgerDB.replaceNative, the default): both corners of this
-- frame on the native bar's, so it takes its exact position and size, and
-- a frame level above it so it is drawn over it and gets the mouse first.
-- Not replacing: same width and horizontal position, 1px above it, at the
-- configured bar height. Falls back to DegradedAnchor if nothing
-- resolves. Always returns a usable width -- never nil, there's always
-- some anchor now, native or degraded. Also records
-- Ledger.xpBarAnchorInfo (source, width, height) for /ldg probe to report.
local function AnchorToNativeBar()
    local nativeBar, source = FindNativeXPBar()

    local width
    if not nativeBar then
        width = DegradedAnchor()
        source = "degraded (no anchor found)"
    else
        inDegradedMode = false
        width = nativeBar:GetWidth()
        frame:ClearAllPoints()
        if LedgerDB.replaceNative then
            frame:SetSize(width, nativeBar:GetHeight())
            frame:SetPoint("TOPLEFT", nativeBar, "TOPLEFT", 0, 0)
            frame:SetPoint("BOTTOMRIGHT", nativeBar, "BOTTOMRIGHT", 0, 0)
        else
            frame:SetSize(width, LedgerDB.barHeight or Ledger.DEFAULTS.barHeight)
            frame:SetPoint("BOTTOMLEFT", nativeBar, "TOPLEFT", 0, 1)
            frame:SetPoint("BOTTOMRIGHT", nativeBar, "TOPRIGHT", 0, 1)
        end
        -- Same strata as the native bar and a level above it, so this
        -- frame (and the hover zone over it) wins the overlap. Also the
        -- fallback when the fill can't be hidden: an opaque overlay.
        pcall(function()
            frame:SetFrameStrata(nativeBar:GetFrameStrata())
            frame:SetFrameLevel(math.min(nativeBar:GetFrameLevel() + 10, 9000))
        end)
        LayoutBorder()
    end

    Ledger.xpBarAnchorInfo = { source = source, width = width, height = frame:GetHeight() }
    return width
end

----------------------------------------------------------------------
-- Hiding the native bar's FILL (only the fill: its container keeps its
-- geometry, which is our anchor and size reference, and its background
-- track stays). The native fill is the StatusBar's own texture; hidden by
-- alpha 0 -- nothing is removed, reparented or hooked, so the client's
-- status tracking bar code keeps running exactly as before and
-- restoring is just putting the alpha back. Every step is verified and
-- guarded: if the fill can't be identified or the alpha doesn't take,
-- the bar is left as a plain overlay (see AnchorToNativeBar) and
-- Ledger.nativeFillInfo says why, for /ldg native and /ldg probe.
----------------------------------------------------------------------

local hiddenFill = {} -- texture -> the alpha it had before we hid it

local function RestoreNativeFill()
    for texture, alpha in pairs(hiddenFill) do
        pcall(texture.SetAlpha, texture, alpha)
        hiddenFill[texture] = nil
    end
end

-- Short description of what the native bar is made of, for the failure
-- message (this is what would be needed to fix the lookup for a client).
local function DescribeNativeBar(nativeBar)
    local parts = {}
    local function describe(label, obj)
        local max = "?"
        if type(obj) == "table" and obj.GetMinMaxValues then
            local ok, _, m = pcall(obj.GetMinMaxValues, obj)
            max = ok and tostring(m) or "err"
        end
        parts[#parts + 1] = string.format("%s[%s max=%s]", label, type(obj) == "table" and obj.GetObjectType and obj:GetObjectType() or type(obj), max)
    end
    if nativeBar.StatusBar then describe("StatusBar", nativeBar.StatusBar) end
    for i, child in ipairs({ nativeBar:GetChildren() }) do
        describe("child" .. i, child)
        if child.StatusBar then describe("child" .. i .. ".StatusBar", child.StatusBar) end
    end
    return #parts > 0 and table.concat(parts, ", ") or "no StatusBar and no children"
end

-- The StatusBar (or StatusBar-like frame) whose range is the xp range:
-- looked up on the resolved native bar itself, its .StatusBar, and its
-- children, and matched by UnitXPMax like FindMatchingChild does, so a
-- reputation bar next to it is never picked. Returns the object, or
-- (nil, reason).
local function FindXPStatusBar(nativeBar)
    local xpMax = UnitXPMax("player")
    if not xpMax or xpMax <= 0 then
        return nil, "no xp bar to hide (max level)"
    end

    local candidates = {}
    local function add(obj)
        if type(obj) == "table" then candidates[#candidates + 1] = obj end
    end
    add(nativeBar.StatusBar)
    add(nativeBar)
    for _, child in ipairs({ nativeBar:GetChildren() }) do
        add(child.StatusBar)
        add(child)
    end

    for _, obj in ipairs(candidates) do
        if obj.GetMinMaxValues and obj.GetStatusBarTexture then
            local _, max = obj:GetMinMaxValues()
            if max and math.abs(max - xpMax) < 0.5 then
                return obj
            end
        end
    end
    return nil, "no StatusBar with the xp range (" .. DescribeNativeBar(nativeBar) .. ")"
end

local function SetFillInfo(status, detail)
    local previous = Ledger.nativeFillInfo
    Ledger.nativeFillInfo = { status = status, detail = detail }
    if not previous or previous.status ~= status or previous.detail ~= detail then
        Ledger.Log("info", string.format("Native xp bar fill: %s (%s)", status, detail))
    end
end

-- Puts the native fill in the state it should be in right now: hidden
-- while this bar is shown and replacing it, visible in every other case
-- (bar hidden, /ldg native off, no native bar at all). Idempotent: it
-- always restores first, so it is safe to call as often as needed.
local function ApplyNativeFill()
    RestoreNativeFill()

    if not LedgerDB or not LedgerDB.replaceNative then
        return SetFillInfo("visible", "not replacing the native bar (/ldg native)")
    end
    if not frame:IsShown() then
        return SetFillInfo("visible", "the xp bar is hidden")
    end

    local nativeBar, source = FindNativeXPBar()
    if not nativeBar then
        return SetFillInfo("n/a", "no native bar found: degraded mode")
    end

    local ok, statusBar, reason = pcall(FindXPStatusBar, nativeBar)
    if not ok then
        return SetFillInfo("overlay only", "lookup failed: " .. tostring(statusBar))
    end
    if not statusBar then
        return SetFillInfo("overlay only", reason)
    end

    local hidden, err = pcall(function()
        local texture = statusBar:GetStatusBarTexture()
        if not texture or not texture.SetAlpha then
            error("the StatusBar has no texture to hide", 0)
        end
        hiddenFill[texture] = texture:GetAlpha()
        texture:SetAlpha(0)
        if texture:GetAlpha() ~= 0 then
            error("SetAlpha(0) did not take (alpha is " .. tostring(texture:GetAlpha()) .. ")", 0)
        end
    end)
    if not hidden then
        RestoreNativeFill()
        return SetFillInfo("overlay only", tostring(err))
    end
    SetFillInfo("hidden", source)
end

-- The fill follows this frame's visibility: hidden bar -> native fill back.
frame:SetScript("OnShow", ApplyNativeFill)
frame:SetScript("OnHide", ApplyNativeFill)

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

-- Width the segments were last computed for. The segments are absolute
-- pixel offsets/widths, so they're only right for that width: the
-- frame itself is anchored to the native bar by both corners and follows
-- it live, but the textures inside don't. If the native bar isn't laid
-- out yet when we draw (seen after a /reload: width 0 at login), every
-- segment comes out 0px wide and the bar is invisible until something
-- forces a redraw -- the xp events only repaint the LAST segment, so a
-- level's worth of earlier ones would stay wrong. Hence the
-- OnSizeChanged hook below and the check in ExtendXPBar.
local lastPaintedWidth
local redrawing = false
local WIDTH_TOLERANCE = 0.5

-- Full redraw: recomputes all segments from scratch and reuses (or
-- creates, if it needs to grow) the pool's textures. Used on level
-- change or on login; new events within the same level use
-- Ledger.ExtendXPBar instead.
--
-- The anchoring happens even while the bar is hidden: the activity bar
-- and the xp/hour number hang from this frame, so it must always have its
-- points -- otherwise hiding only this bar would leave them unanchored
-- (and invisible) after a /reload. Only the painting needs it shown.
--
-- Returns (ok, width, segmentCount) so the caller (e.g. the /ldg bar
-- command) can report immediately without depending on the log being
-- enabled: ok=false if the frame is hidden or it couldn't anchor to
-- the native bar.
function Ledger.RedrawXPBarFull()
    redrawing = true
    local width = AnchorToNativeBar()
    ApplyNativeFill() -- re-resolved on every full redraw: the native bar can be rebuilt or load late
    if not width or not frame:IsShown() then
        redrawing = false
        return false
    end

    local segments = CurrentSegments(width)
    Ledger.Log("trace", string.format("RedrawXPBarFull: width=%dpx, %d segments", width, #segments))
    for i, segment in ipairs(segments) do
        PaintSegment(GetOrCreatePair(i), segment)
    end
    activeCount = #segments
    ReleaseFrom(activeCount + 1)
    lastPaintedWidth = width
    redrawing = false
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

    -- The native bar changed size since the last full draw: every
    -- segment is stale, not just the last one.
    if not lastPaintedWidth or math.abs(width - lastPaintedWidth) > WIDTH_TOLERANCE then
        Ledger.Log("trace", string.format(
            "ExtendXPBar: width %s differs from last painted %s -- full redraw",
            tostring(width), tostring(lastPaintedWidth)))
        Ledger.RedrawXPBarFull()
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

-- The native bar (and with it this frame, anchored to it) got its real
-- size after we had already drawn: redraw for the new width. `redrawing`
-- stops the SetSize inside AnchorToNativeBar from re-entering here.
frame:SetScript("OnSizeChanged", function(self, width)
    if redrawing or not self:IsShown() then return end
    if not width or width <= 0 then return end
    if lastPaintedWidth and math.abs(width - lastPaintedWidth) <= WIDTH_TOLERANCE then return end
    Ledger.Log("trace", string.format(
        "OnSizeChanged: width %s differs from last painted %s -- full redraw",
        tostring(width), tostring(lastPaintedWidth)))
    Ledger.RedrawXPBarFull()
end)

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
-- /ldg native: back to the native bar (and out again)
----------------------------------------------------------------------

-- Flips LedgerDB.replaceNative and re-applies everything: with it off the
-- native fill is visible again and this bar goes back above the native
-- one (nothing is lost, both are on screen); with it on, this bar takes
-- the native one's place. Returns (replacing, Ledger.nativeFillInfo) so
-- the caller can report what actually happened.
function Ledger.ToggleReplaceNative()
    LedgerDB.replaceNative = not LedgerDB.replaceNative
    Ledger.RedrawXPBarFull()
    return LedgerDB.replaceNative, Ledger.nativeFillInfo
end

----------------------------------------------------------------------
-- Hover label: "{current xp} / {level xp}" centered in white over the
-- bar, like the native bar's own text. Shown and hidden by the hover
-- zone (ui/bars_hover.lua); the text itself is composed in core/
-- (Ledger.FormatXPLabel).
----------------------------------------------------------------------

local label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("CENTER", frame, "CENTER", 0, 0)
label:SetTextColor(1, 1, 1, 1)
label:Hide()

-- Recomputes the text from the live values and shows it (or hides it
-- when there is nothing to say, e.g. max level).
function Ledger.ShowXPBarLabel()
    local text = Ledger.FormatXPLabel(UnitXP("player"), UnitXPMax("player"))
    if text then
        label:SetText(text)
        label:Show()
    else
        label:Hide()
    end
end

function Ledger.HideXPBarLabel()
    label:Hide()
end
