-- Ledger - ui/palette.lua
-- Centralized color palette: used both by the xp composition bar
-- (ui/xp_bar.lua) and the time-split bar (ui/time_bar.lua), and their
-- respective tooltips, so they can never fall out of sync. Never
-- hardcode a loose color in drawing code: if a new color is needed,
-- it's one more entry here.
--
-- Each entry in 0-1 format (for SetVertexColor/SetColorTexture),
-- computed from Lua hex literals (0xRR/255) so it stays traceable to
-- the hex without hand-rounding; the original hex is kept in the
-- comment next to each one.

local ADDON_NAME, Ledger = ...

Ledger.PALETTE = {
    -- Xp bar, by src.
    kill      = { 0xC8/255, 0xA3/255, 0x4E/255 }, -- #C8A34E, muted gold
    quest     = { 0x3F/255, 0xA9/255, 0x8C/255 }, -- #3FA98C, teal
    explore   = { 0x8C/255, 0x7B/255, 0xB5/255 }, -- #8C7BB5, light violet
    unknown   = { 0x6E/255, 0x6A/255, 0x66/255 }, -- #6E6A66, warm gray
    _fallback = { 0xCC/255, 0x33/255, 0x99/255 }, -- #CC3399, loud magenta: unrecognized src/bucket, should never actually show up

    -- Time bar, by bucket. travel and dead are their own entries.
    travel = { 0x4A/255, 0x6F/255, 0xA5/255 }, -- #4A6FA5, muted blue
    dead   = { 0x8B/255, 0x3A/255, 0x3A/255 }, -- #8B3A3A, muted dark red
}

-- active and downtime REUSE kill/unknown's color (same concept:
-- productive time / "we don't know"), not a copy of the same hex: if
-- kill or unknown ever change, these follow automatically.
Ledger.PALETTE.active   = Ledger.PALETTE.kill
Ledger.PALETTE.downtime = Ledger.PALETTE.unknown

-- The xp bar's initial segment ("xp earned before tracking started")
-- is, in essence, "we don't know": same gray as unknown.
if Ledger.BAR_INITIAL_SRC then
    Ledger.PALETTE[Ledger.BAR_INITIAL_SRC] = Ledger.PALETTE.unknown
end

-- Lightens a color by `amount` (0..1) toward white, computed from the
-- base color -- never a separate palette entry. Used for the "rested"
-- tint within an xp bar segment.
function Ledger.LightenColor(color, amount)
    return {
        color[1] + (1 - color[1]) * amount,
        color[2] + (1 - color[2]) * amount,
        color[3] + (1 - color[3]) * amount,
    }
end
