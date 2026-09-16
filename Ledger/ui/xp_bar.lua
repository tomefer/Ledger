-- Ledger - ui/xp_bar.lua
-- Barra de composicion de xp del nivel actual: anclada justo encima de
-- la barra de xp nativa, un segmento de color por tramo de src
-- (fusionados por core/xp_bar.lua: Ledger.ComputeBarSegments). Capa
-- fina: el calculo de segmentos y sus anchuras vive en core/, aqui solo
-- se pintan con un pool de texturas reutilizables.

local ADDON_NAME, Ledger = ...

-- Paleta centralizada en ui/palette.lua (Ledger.PALETTE), compartida
-- con la barra de tiempo y sus tooltips -- ver ese fichero para los
-- colores y por que active/idle no tienen aqui entrada propia.
local PALETTE = Ledger.PALETTE
local RESTED_LIGHTEN_AMOUNT = 0.35

----------------------------------------------------------------------
-- Frame y anclaje a la barra de xp nativa.
----------------------------------------------------------------------

-- Confirmado con /fstack en el juego: este cliente NO usa el frame
-- clasico "MainMenuExpBar" (esa fue la suposicion inicial, descartada).
-- Usa el sistema de barras de seguimiento compartido con retail
-- (Interface/AddOns/Blizzard_ActionBar/Classic/StatusTrackingBarTemplate.xml):
-- la barra de xp vive dentro del contenedor global
-- "MainStatusTrackingBarContainer", como un hijo ANONIMO (sin nombre
-- global estable -- lo que /fstack muestra como
-- "MainStatusTrackingBarContainer.<hash>" es solo como esa herramienta
-- representa un frame sin nombre, no una variable real). Ese
-- contenedor puede tener mas de un hijo a la vez (reputacion, honor...)
-- confirmado en el juego: con reputacion tambien activa aparecen dos
-- hijos con StatusBar. Se localiza el correcto comparando el maximo de
-- cada StatusBar contra UnitXPMax("player") -- confirmado en el juego
-- que el hijo de la xp es el unico cuyo maximo coincide (el de
-- reputacion tenia un maximo normalizado a 1, no el rango real).
local function FindNativeXPBar()
    if not MainStatusTrackingBarContainer then
        Ledger.Log("trace", "FindNativeXPBar: MainStatusTrackingBarContainer no existe")
        return nil
    end

    local xpMax = UnitXPMax("player")
    if not xpMax or xpMax <= 0 then
        Ledger.Log("trace", string.format("FindNativeXPBar: UnitXPMax=%s, nivel maximo o sin datos todavia", tostring(xpMax)))
        return nil -- nivel maximo: no hay barra de xp que anclar
    end

    local children = { MainStatusTrackingBarContainer:GetChildren() }
    Ledger.Log("trace", string.format("FindNativeXPBar: xpMax=%d, %d hijos en el contenedor", xpMax, #children))

    for _, child in ipairs(children) do
        local statusBar = child.StatusBar
        if statusBar then
            local _, max = statusBar:GetMinMaxValues()
            Ledger.Log("trace", string.format("FindNativeXPBar: candidato con max=%s", tostring(max)))
            -- Tolerancia en vez de igualdad exacta: por si el maximo
            -- llega como float con algun redondeo interno de Blizzard.
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
-- Pool de pares de texturas (base + rested), reutilizables: nunca se
-- crean ni se destruyen por evento, solo se muestran/ocultan.
----------------------------------------------------------------------

local texturePairPool = {}
local activeCount = 0

-- Textura blanca de 8x8 de Blizzard: la forma clasica (funciona desde
-- Vanilla) de pintar un color solido es aplicar esta textura y teñirla
-- con SetVertexColor, no llamar a SetTexture con numeros -- eso se
-- interpreta como SetTexture(fileID, wrapH, wrapV, filterMode), no como
-- RGB (confirmado en el juego: SetTexture(1,0,1,1), que deberia ser
-- magenta, salio verde -- fileID 1 es otra textura cualquiera).
local WHITE_TEXTURE = "Interface\\Buttons\\WHITE8x8"

local function GetOrCreatePair(index)
    local pair = texturePairPool[index]
    if not pair then
        pair = {
            base   = frame:CreateTexture(nil, "ARTWORK"),
            rested = frame:CreateTexture(nil, "ARTWORK", nil, 1), -- por encima de base
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
-- Borde: 1px negro al 60%, alrededor de toda la barra, para separarla
-- visualmente de la barra de xp nativa justo debajo. Cuatro texturas
-- finas en OVERLAY (por encima de los segmentos en ARTWORK), creadas
-- una vez y solo reposicionadas cuando cambia el tamaño del frame
-- (AnchorToNativeBar), nunca recreadas.
----------------------------------------------------------------------

local BORDER_COLOR = { 0, 0, 0, 0.6 } -- negro al 60%

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

-- Ancla el frame a la barra de xp nativa: mismo ancho y misma posicion
-- horizontal, justo encima. Devuelve el ancho en pixeles disponible, o
-- nil si no se encuentra (nivel maximo, o el contenedor no existe en
-- este cliente; se loguea a ERROR una sola vez, no en cada intento).
local warnedMissingNativeBar = false
local function AnchorToNativeBar()
    local nativeBar = FindNativeXPBar()
    if not nativeBar then
        if not warnedMissingNativeBar and UnitXPMax("player") > 0 then
            Ledger.Log("error",
                "No se ha encontrado la barra de xp nativa dentro de MainStatusTrackingBarContainer (comparando por UnitXPMax). Puede que este cliente no tenga ese contenedor -- revisar ui/xp_bar.lua: FindNativeXPBar.")
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
-- Datos: todas las sesiones del nivel actual (nunca solo la activa,
-- para que un /ldg reset no altere la vista) + xp previa al registro.
----------------------------------------------------------------------

local function CurrentSegments(widthPx)
    local sessions  = LedgerCharDB.sessions
    local flatArray = Ledger.ConcatSeries(sessions, Ledger.SERIES.xp)
    local initialXP = sessions[1] and sessions[1].initialXP or 0
    local maxXP     = UnitXPMax("player")
    return Ledger.ComputeBarSegments(flatArray, initialXP, widthPx, maxXP)
end

-- Redibujado completo: recalcula todos los segmentos desde cero y
-- reutiliza (o crea, si hace falta crecer) las texturas del pool. Se
-- usa al cambiar de nivel o al cargar; los eventos nuevos de un mismo
-- nivel usan Ledger.ExtendXPBar en su lugar.
--
-- Devuelve (ok, width, segmentCount) para que quien llame (p.ej. el
-- comando /ldg bar) pueda informar de inmediato sin depender de que el
-- log este activo: ok=false si el frame esta oculto o no se ha podido
-- anclar a la barra nativa.
function Ledger.RedrawXPBarFull()
    if not frame:IsShown() then return false end
    local width = AnchorToNativeBar()
    if not width then return false end

    local segments = CurrentSegments(width)
    Ledger.Log("trace", string.format("RedrawXPBarFull: ancho=%dpx, %d segmentos", width, #segments))
    for i, segment in ipairs(segments) do
        PaintSegment(GetOrCreatePair(i), segment)
    end
    activeCount = #segments
    ReleaseFrom(activeCount + 1)
    return true, width, #segments
end

-- Redibujado incremental: se llama tras cada evento nuevo grabado en la
-- sesion activa. La aritmetica de reparto de anchuras
-- (core/xp_bar.lua: RoundedWidths) es estable por prefijo -- anadir un
-- evento al final nunca cambia la anchura ya calculada de segmentos
-- anteriores al ultimo -- asi que solo hace falta repintar el ultimo
-- segmento existente (si se ha extendido) o anadir uno nuevo, sin
-- tocar ni recrear el resto.
function Ledger.ExtendXPBar()
    if not frame:IsShown() then return end
    local width = frame:GetWidth()
    if not width or width <= 0 then
        Ledger.Log("trace", string.format("ExtendXPBar: frame sin ancho todavia (%s)", tostring(width)))
        return
    end

    local segments = CurrentSegments(width)
    local previousCount = activeCount
    Ledger.Log("trace", string.format("ExtendXPBar: %d segmentos (antes %d)", #segments, previousCount))

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
        -- Caso inesperado (el numero de segmentos cambio en mas de uno
        -- de golpe): recurre al redibujado completo en vez de dejar la
        -- barra a medias.
        Ledger.RedrawXPBarFull()
    end
end

----------------------------------------------------------------------
-- /ldg bar
----------------------------------------------------------------------

-- Devuelve (shown, ok, width, segmentCount): shown indica si ha quedado
-- visible tras el toggle; el resto solo tiene sentido cuando shown es
-- true (ver Ledger.RedrawXPBarFull).
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
-- Tooltip: desglose de xp por origen del nivel actual (todas las
-- sesiones, igual que la barra -- nunca solo la activa). Usa la MISMA
-- tabla Ledger.PALETTE que pinta los segmentos, para que barra y
-- tooltip no puedan desincronizarse en el color de cada origen.
----------------------------------------------------------------------

local SRC_LABELS = {
    kill    = "Combate",
    quest   = "Misiones",
    explore = "Exploracion",
    unknown = "Desconocido",
}

frame:EnableMouse(true)
frame:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:SetText("Composicion de xp del nivel", 1, 1, 1)

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
        GameTooltip:AddLine(string.format("De descanso: %d xp", totalRested), 1, 1, 1)
    end

    GameTooltip:Show()
end)
frame:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)
