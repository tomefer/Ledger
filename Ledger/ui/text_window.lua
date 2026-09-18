-- Ledger - ui/text_window.lua
-- Shared factory for the "copy this text" windows (/ldg export,
-- /ldg check): a movable, resizable frame with a read-only, multiline
-- EditBox inside a scroll frame, whose content is pre-selected on every
-- SetText so Ctrl+C copies all of it immediately, no need to click into
-- the box first. Thin layer: what goes in the text is up to the caller.
--
-- Escape closes the window two ways at once, since either one alone can
-- miss: UISpecialFrames only fires its global handler when no focused
-- frame consumes the Escape key first, and an EditBox with focus (the
-- normal state here, so Ctrl+C works right away) consumes it via its
-- own OnEscapePressed instead of letting it propagate.

local ADDON_NAME, Ledger = ...

-- opts:
--   name        -- global frame name (also what UISpecialFrames needs)
--   scrollName  -- global name of the scroll frame (UIPanelScrollFrameTemplate
--                  derives its scroll bar's name from it)
--   width, height, x, y -- initial size and offset from the screen center
--   minWidth, minHeight -- resize limits
--
-- Returns the frame (with `frame.title` and `frame.editBox`) and a
-- SetText(text) function. The frame reserves 36px at the bottom for
-- buttons the caller may anchor there.
function Ledger.CreateTextWindow(opts)
    local frame = CreateFrame("Frame", opts.name, UIParent, "BackdropTemplate")
    frame:SetSize(opts.width, opts.height)
    frame:SetPoint("CENTER", opts.x, opts.y)
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
    table.insert(UISpecialFrames, opts.name)

    ------------------------------------------------------------------
    -- Resizing from the bottom-right corner (same technique as
    -- ui/debug_frame.lua).
    ------------------------------------------------------------------

    frame:SetResizable(true)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(opts.minWidth, opts.minHeight)
    else
        frame:SetMinResize(opts.minWidth, opts.minHeight)
    end

    local resizeHandle = CreateFrame("Button", nil, frame)
    resizeHandle:SetSize(16, 16)
    resizeHandle:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeHandle:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeHandle:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeHandle:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    resizeHandle:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    resizeHandle:SetScript("OnMouseUp", function() frame:StopMovingOrSizing() end)

    ------------------------------------------------------------------
    -- Content: read-only multiline EditBox inside a scroll frame.
    ------------------------------------------------------------------

    local scrollFrame = CreateFrame("ScrollFrame", opts.scrollName, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 12, -32)
    scrollFrame:SetPoint("BOTTOMRIGHT", -30, 36)

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject(ChatFontNormal)
    editBox:SetWidth(opts.width - 60)

    -- Read-only: any typing attempt gets undone on the next
    -- OnTextChanged firing, but the text stays selectable/focusable for
    -- copying (same trick as ui/debug_frame.lua).
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
    frame.editBox = editBox

    -- Replaces the content and immediately re-selects everything, so
    -- Ctrl+C copies all of it right after opening or refreshing.
    local function SetText(text)
        editBox.currentText = text
        editBox.suppressChange = true
        editBox:SetText(text)
        editBox.suppressChange = false
        editBox:SetFocus()
        editBox:HighlightText()
    end

    return frame, SetText
end
