-- Ledger - ui/time_bar.lua
-- Barra de reparto de tiempo del nivel actual: paralela a la barra de
-- composicion de xp (misma anchura y posicion horizontal, misma
-- altura, 2px de separacion por encima), con los 4 buckets de
-- core/time_buckets.lua en orden fijo (active, travel, idle, dead). Eje
-- PROPORCIONAL: ocupa siempre el 100% del ancho, no es comparable
-- pixel a pixel con la barra de xp (ejes distintos). Capa fina: el
-- calculo de segmentos y el formateo del tooltip viven en core/, aqui
-- solo se pinta con texturas reutilizables (una fija por bucket: son
-- siempre los mismos 4, en el mismo orden, a diferencia de la barra de
-- xp no hace falta un pool dinamico).

local ADDON_NAME, Ledger = ...

local PALETTE = Ledger.PALETTE
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8" -- ver ui/xp_bar.lua: SetTexture con numeros no pinta color en este cliente

local frame = CreateFrame("Frame", "LedgerTimeBar", UIParent)
frame:Hide()
Ledger.timeBarFrame = frame

----------------------------------------------------------------------
-- Una textura fija por bucket (nunca un pool: siempre son los mismos 4,
-- en Ledger.TIME_BUCKET_ORDER) + borde, igual que la barra de xp.
----------------------------------------------------------------------

local bucketTextures = {}
for _, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
    local tex = frame:CreateTexture(nil, "ARTWORK")
    tex:SetTexture(WHITE_TEXTURE)
    bucketTextures[bucket] = tex
end

local BORDER_COLOR = { 0, 0, 0, 0.6 } -- negro al 60%, igual que la barra de xp

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

-- Ancla el frame paralelo a la barra de xp: mismo ancho y posicion
-- horizontal, misma altura, 2px de separacion por encima. Devuelve el
-- ancho, o nil si la barra de xp todavia no tiene un tamaño valido
-- (p.ej. no se ha anclado nunca a la barra nativa).
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
-- Datos: todas las sesiones del nivel actual (igual que la barra de
-- xp), con la sesion en curso usando la vista previa en vivo del
-- tracker (core/time_buckets.lua: Ledger.PreviewBuckets) para que la
-- barra se vea crecer cada segundo sin mutar nada.
----------------------------------------------------------------------

local function CurrentBuckets()
    local totals = Ledger.NewEmptyBuckets()
    local sessions = LedgerCharDB.sessions
    local currentSession = sessions[#sessions]
    local now = GetTime()

    for _, session in ipairs(sessions) do
        local buckets = session.buckets
        if buckets then
            if session == currentSession and Ledger.timeTracker then
                buckets = Ledger.PreviewBuckets(Ledger.timeTracker, now)
            end
            for _, bucket in ipairs(Ledger.TIME_BUCKET_ORDER) do
                totals[bucket] = totals[bucket] + (buckets[bucket] or 0)
            end
        end
    end

    return totals
end

-- Redibujado: llamado desde el mismo ticker de 1s que alimenta los
-- buckets (ui/xp_capture.lua), nunca desde los eventos de xp -- los
-- tramos de viaje/inactividad/muerte no generan ninguno, y atarlo a las
-- kills dejaria la barra congelada la mayor parte del tiempo.
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
-- Tooltip: cada bucket con su tiempo absoluto y porcentaje
-- (core/time_bar.lua: Ledger.FormatTimeBarTooltip, funcion pura), cada
-- linea coloreada con la MISMA Ledger.PALETTE que pinta los segmentos.
----------------------------------------------------------------------

frame:EnableMouse(true)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Reparto de tiempo del nivel", 1, 1, 1)

    for _, line in ipairs(Ledger.FormatTimeBarTooltip(CurrentBuckets())) do
        local color = PALETTE[line.bucket] or PALETTE._fallback
        GameTooltip:AddLine(line.text, color[1], color[2], color[3])
    end

    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
