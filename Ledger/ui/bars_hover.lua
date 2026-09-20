-- Ledger - ui/bars_hover.lua
-- ONE hover zone over the two bars (xp composition + activity), so
-- there is a single place to point the mouse at instead of two thin
-- strips to tell apart. Entering it shows the xp label over the xp bar
-- (ui/xp_bar.lua: Ledger.ShowXPBarLabel) and ONE tooltip with everything:
-- xp by source first, then the time split in percentages. The tooltip's
-- content is composed in core/bar_hover.lua
-- (Ledger.BuildBarTooltipSections, pure); this file only lays the zone
-- out and paints those sections into GameTooltip.
--
-- The bars themselves take no mouse: this frame does, and forwards the
-- drag (only meaningful for the xp bar's degraded mode, see
-- ui/xp_bar.lua) to the xp bar.

local ADDON_NAME, Ledger = ...

local xpBar   = Ledger.xpBarFrame
local timeBar = Ledger.timeBarFrame

local zone = CreateFrame("Frame", "LedgerBarsHover", UIParent)
zone:Hide()
zone:EnableMouse(true)
zone:RegisterForDrag("LeftButton")
zone:SetScript("OnDragStart", function() Ledger.StartXPBarDrag() end)
zone:SetScript("OnDragStop", function() Ledger.StopXPBarDrag() end)
Ledger.barsHoverFrame = zone

local REFRESH_INTERVAL = 1 -- seconds, while the mouse is over the zone
local sinceRefresh = 0

local function FillTooltip()
    local sections = Ledger.BuildBarTooltipSections({
        sessions   = LedgerCharDB.sessions,
        levelTicks = LedgerCharDB.levelTicks,
        palette    = Ledger.PALETTE,
        showXP     = xpBar:IsShown(),
        showTime   = timeBar:IsShown(),
    })
    if #sections == 0 then
        GameTooltip:Hide()
        return
    end

    GameTooltip:ClearLines()
    for i, section in ipairs(sections) do
        if i == 1 then
            GameTooltip:SetText(section.title, 1, 1, 1)
        else
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(section.title, 1, 1, 1)
        end
        for _, row in ipairs(section.rows) do
            GameTooltip:AddLine(row.text, row.color[1], row.color[2], row.color[3])
        end
    end
    GameTooltip:Show()
end

local function EndHover()
    zone:SetScript("OnUpdate", nil)
    Ledger.HideXPBarLabel()
    if GameTooltip:GetOwner() == zone then
        GameTooltip:Hide()
    end
end

zone:SetScript("OnEnter", function(self)
    Ledger.ShowXPBarLabel()

    -- Above whatever sits on top of the bars: by default the xp/hour
    -- number is stacked right over the zone (ui/rate_frame.lua), and the
    -- tooltip would cover it if it hung from the zone itself.
    local above = self
    if Ledger.rateFrame:IsShown() and not (LedgerDB and LedgerDB.ratePos) then
        above = Ledger.rateFrame
    end
    GameTooltip:SetOwner(self, "ANCHOR_NONE")
    GameTooltip:SetPoint("BOTTOM", above, "TOP", 0, 4)
    FillTooltip()

    -- The label and the tooltip would go stale while the mouse rests here.
    sinceRefresh = 0
    self:SetScript("OnUpdate", function(_, elapsed)
        sinceRefresh = sinceRefresh + elapsed
        if sinceRefresh >= REFRESH_INTERVAL then
            sinceRefresh = 0
            Ledger.ShowXPBarLabel()
            FillTooltip()
        end
    end)
end)
zone:SetScript("OnLeave", EndHover)

----------------------------------------------------------------------
-- Layout: from the lowest visible bar's bottom-left to the highest
-- one's top-right (the 2px gap between the bars is inside the zone, so
-- the mouse never falls in a dead strip). Only the bars that are shown
-- count; with none shown the zone is hidden. The bars are stacked
-- xp (bottom) -> activity (top), see ui/time_bar.lua.
----------------------------------------------------------------------

function Ledger.LayoutBarsHover()
    local low, high
    if xpBar:IsShown() then low, high = xpBar, xpBar end
    if timeBar:IsShown() then low, high = low or timeBar, timeBar end

    if not low then
        EndHover()
        zone:Hide()
        return
    end

    zone:ClearAllPoints()
    zone:SetPoint("BOTTOMLEFT", low, "BOTTOMLEFT", 0, 0)
    zone:SetPoint("TOPRIGHT", high, "TOPRIGHT", 0, 0)
    -- Over the xp bar, which in replace mode sits over the native bar
    -- (which has mouse and tooltips of its own).
    pcall(function()
        zone:SetFrameStrata(xpBar:GetFrameStrata())
        zone:SetFrameLevel(math.min(xpBar:GetFrameLevel() + 5, 9500))
    end)
    zone:Show()
end

-- The bars are shown and hidden from several places (the slash
-- commands, the login restore); following their own visibility keeps the
-- zone in step with all of them.
for _, bar in ipairs({ xpBar, timeBar }) do
    bar:HookScript("OnShow", Ledger.LayoutBarsHover)
    bar:HookScript("OnHide", Ledger.LayoutBarsHover)
end
