-- Ledger - ui/xp_capture.lua
-- Traduce los eventos de WoW relacionados con ganar xp, morir/resucitar
-- y el tiempo jugado a llamadas de core/. Capa fina: toda la logica de
-- emparejar cantidad+origen, acumular buckets de tiempo y componer la
-- sesion vive en core/; aqui solo se leen las APIs de WoW y se llama.

local ADDON_NAME, Ledger = ...

----------------------------------------------------------------------
-- Patrones de xp de combate, construidos en caliente desde TODOS los
-- global strings reales del cliente cuyo nombre empiece por
-- "COMBATLOG_XPGAIN_" (nunca hardcodeados ni filtrados a una lista fija:
-- el propio cliente dice que variantes existen, en cualquier idioma).
-- No hace falta restringir a las variantes "FIRSTPERSON": el propio
-- evento CHAT_MSG_COMBAT_XP_GAIN ya solo se dispara para xp del
-- jugador, y core/chat_patterns.lua: Ledger.ClassifyXPGainMatch usa la
-- presencia (o no) de un nombre de criatura en la variante que casa
-- para distinguir "kill" de "explore" -- nunca "unknown", porque el
-- evento en si ya confirma que es xp de combate o exploracion.
----------------------------------------------------------------------

-- Guarda tambien el nombre del global string y su texto literal (no solo
-- el patron derivado), para poder inspeccionarlos con /ldg strings.
local xpGainStrings = {}
for key, value in pairs(_G) do
    if type(value) == "string" and key:find("^COMBATLOG_XPGAIN_") then
        table.insert(xpGainStrings, { name = key, text = value, pattern = Ledger.BuildPattern(value) })
    end
end
Ledger.xpGainStrings = xpGainStrings

-- El sufijo de bono por descanso ("(+86 exp Rested bonus)") va pegado
-- al final del mensaje de xp de combate, no al principio, asi que se
-- busca con un patron sin anclar (Ledger.BuildSuffixPattern) contra una
-- familia de global strings aparte. MEJOR ESFUERZO, SIN CONFIRMAR EN
-- EL JUEGO: se asume que existen como COMBATLOG_XPGAIN_EXHAUSTION*
-- (convencion de Blizzard para el bono por descanso/agotamiento desde
-- hace varias expansiones) -- comprobar con /ldg strings, que imprime
-- tambien esta familia con su valor literal en este cliente.
local restedStrings = {}
for key, value in pairs(_G) do
    if type(value) == "string" and key:find("^COMBATLOG_XPGAIN_EXHAUSTION") then
        table.insert(restedStrings, { name = key, text = value, pattern = Ledger.BuildSuffixPattern(value) })
    end
end
Ledger.restedStrings = restedStrings

-- Clasifica el mensaje (core/chat_patterns.lua: Ledger.ClassifyXPGainMatch,
-- logica pura) y loguea a TRACE cada variante probada (casada o no, y lo
-- capturado si caso), mas la categoria final resultante. Ademas extrae
-- el bono por descanso si el mensaje trae el sufijo (Ledger.ExtractRestedBonus,
-- tambien pura). Devuelve category, rested.
local function HandleCombatXPGainMessage(msg, t)
    local category, attempts = Ledger.ClassifyXPGainMatch(xpGainStrings, msg)

    for _, attempt in ipairs(attempts) do
        if attempt.matched then
            Ledger.Log("trace", string.format(
                "CHAT_MSG_COMBAT_XP_GAIN match t=%.3f global=%s pattern=%s captured=[%s] categoria=%s",
                t, attempt.name, attempt.pattern, table.concat(attempt.captured, ", "), category))
        else
            Ledger.Log("trace", string.format(
                "CHAT_MSG_COMBAT_XP_GAIN no-match t=%.3f global=%s pattern=%s",
                t, attempt.name, attempt.pattern))
        end
    end

    if #attempts == 0 or not attempts[#attempts].matched then
        Ledger.Log("trace", string.format(
            "CHAT_MSG_COMBAT_XP_GAIN t=%.3f ninguna variante caso -- categoria por defecto %s (nunca unknown)",
            t, category))
    end

    local rested = Ledger.ExtractRestedBonus(restedStrings, msg)
    if rested > 0 then
        Ledger.Log("trace", string.format(
            "CHAT_MSG_COMBAT_XP_GAIN t=%.3f bono por descanso detectado: rested=%d", t, rested))
    end

    return category, rested
end

----------------------------------------------------------------------
-- Estado: todas las sesiones del nivel actual (la ultima es la activa),
-- el tracker de buckets de tiempo y el buffer que empareja cantidad
-- (PLAYER_XP_UPDATE) con origen (mensaje de combate).
--
-- `sessions` no es una copia en memoria: es la MISMA tabla que
-- LedgerCharDB.sessions (asignada por referencia en StartTracking), asi
-- que anadir una sesion o un evento a una sesion ya existente escribe
-- directamente en la SavedVariable, sin ningun paso de "guardado"
-- aparte. Las sesiones cerradas se conservan aqui hasta el cierre de
-- nivel: ese cierre (core/level_close.lua + Ledger.RecordLevelClose)
-- agrega TODAS las sesiones del nivel, no solo la ultima.
----------------------------------------------------------------------

local sessions -- nil hasta el primer PLAYER_ENTERING_WORLD
local timeTracker
local matcher
local reconciler
local previousXP
local previousMaxXP -- UnitXPMax cacheado: ver PLAYER_XP_UPDATE, nunca
                     -- se lee UnitXPMax en el instante de un ding
local previousLevel

-- Reloj de inactividad para los buckets de tiempo (core/time_buckets.lua):
-- el instante de la ultima señal de actividad, la mas reciente entre
-- una ganancia de xp y una entrada en combate (PLAYER_REGEN_DISABLED).
-- Nunca UnitAffectingCombat como reloj: se sale de combate
-- constantemente entre pull y pull, y eso no significa que se haya
-- dejado de "estar activo" para el umbral (Ledger.INACTIVITY_THRESHOLD,
-- 30s).
local lastXPGainTime
local lastCombatEnterTime

local function CurrentSession()
    if not sessions then return nil end
    return sessions[#sessions]
end

local function OpenSession(t, level, manual)
    local session = Ledger.NewSession(t, level, nil, manual)
    table.insert(sessions, session)
    return session
end

-- Graba el evento y, si la fuente traia su propia cantidad
-- (expectedXP: p.ej. el arg2 de QUEST_TURNED_IN), la contrasta contra
-- el delta real de UnitXP -- que es siempre el que se graba, la
-- discrepancia es solo una señal de alarma. Tambien alimenta el
-- contador de reconciliacion con lo que realmente se ha llegado a
-- grabar (ver PLAYER_XP_UPDATE para el lado de lo esperado).
local function EmitEvent(paired)
    if paired.expectedXP and paired.expectedXP ~= paired.xp then
        Ledger.Log("error", string.format(
            "discrepancia de xp: fuente %s reporto %d, delta real de UnitXP fue %d -- se graba el delta (UnitXP manda)",
            paired.src, paired.expectedXP, paired.xp))
    end

    Ledger.AccountRecordedXP(reconciler, paired.xp)

    local session = CurrentSession()
    if not session then return end
    local offset = (paired.t - session.t0) * 10 -- decimas de segundo
    Ledger.AddEvent(session, offset, paired.xp, paired.src, paired.rested)
    Ledger.ExtendXPBar()
end

-- Engancha `sessions` a LedgerCharDB.sessions (garantizado por
-- Ledger.InitCharDB en ADDON_LOADED, que corre antes de que este evento
-- pueda llegar). Si ya habia sesiones sin cerrar de una partida anterior
-- del mismo nivel, se sigue escribiendo en ellas; si no habia ninguna,
-- se abre la primera y se guarda en ella `initialXP`: la xp que el
-- jugador ya llevaba en este nivel antes de que el addon empezara a
-- registrar (UnitXP en este instante, ya que la xp registrada es
-- todavia 0). Solo se calcula esta vez -- vive en la sesion, que ya es
-- la SavedVariable real, asi que sobrevive a /reload -- para el
-- segmento gris inicial de la barra de composicion de xp
-- (core/xp_bar.lua).
local function StartTracking(t, level)
    sessions = LedgerCharDB.sessions
    if #sessions == 0 then
        local session = OpenSession(t, level, false)
        session.initialXP = UnitXP("player")
    end
    timeTracker = Ledger.NewTracker(t, "idle")
    -- Reengancha el tracker a los buckets YA PERSISTIDOS de la sesion
    -- actual (misma tabla, no una copia): cualquier AddSample futuro
    -- escribe directamente en la sesion (SavedVariable), sin paso de
    -- guardado aparte -- igual que sessions/session.e. Si la sesion es
    -- nueva sus buckets ya estan a cero (Ledger.NewSession); si se
    -- retoma tras un /reload, sigue por donde lo dejo.
    timeTracker.buckets = CurrentSession().buckets
    Ledger.timeTracker = timeTracker -- expuesto para ui/time_bar.lua
    matcher     = Ledger.NewMatcher()
    reconciler  = Ledger.NewReconciler()
end

-- Segundos que se espera tras un PLAYER_LEVEL_UP a que llegue un evento
-- de xp (PLAYER_XP_UPDATE, CHAT_MSG_COMBAT_XP_GAIN o QUEST_TURNED_IN)
-- antes de cerrar el nivel viejo por temporizador. El cierre nunca debe
-- depender de que llegue un evento que quiza no llegue (p.ej. una
-- entrega de mision que no dispara CHAT_MSG_COMBAT_XP_GAIN si no casa
-- ningun patron... aunque hoy siempre clasifica algo, ver
-- core/chat_patterns.lua): por eso hay temporizador de respaldo.
Ledger.PENDING_LEVEL_UP_TIMEOUT = 0.25

-- No nil mientras hay una subida de nivel esperando a cerrarse:
-- { oldLevel=, timer= }. oldLevel es el nivel que hay que cerrar
-- (previousLevel cacheado en el momento del ding). timer es el
-- C_Timer.NewTimer de respaldo, cancelable si se consume antes por un
-- evento de xp.
local pendingLevelUp

-- Cierra oldLevel (todas las sesiones actuales, que en este punto son
-- integramente de ese nivel) y abre la sesion del nivel nuevo, sin
-- esperar a nada mas. Idempotente: si ya se proceso (pendingLevelUp ya
-- es nil), no hace nada -- necesario porque puede llamarse tanto desde
-- el primer evento de xp que llegue como desde el temporizador de
-- respaldo, y ambos podrian dispararse casi a la vez.
local function ProcessPendingLevelUp(t, reason)
    if not pendingLevelUp then return end
    local oldLevel = pendingLevelUp.oldLevel
    if pendingLevelUp.timer then
        pendingLevelUp.timer:Cancel()
    end
    pendingLevelUp = nil

    Ledger.Log("trace", string.format(
        "CierreNivel: consumida subida pendiente (nivel viejo=%d) via %s, t=%.3f", oldLevel, reason, t))

    local totalPlayed = 0
    if timeTracker then
        -- Cierra el tramo de tiempo hasta ahora sin cambiar de estado,
        -- para que el total incluya lo transcurrido desde la ultima
        -- muestra.
        Ledger.AddSample(timeTracker, t, timeTracker.lastState)
        local b = timeTracker.buckets
        totalPlayed = b.active + b.idle + b.travel + b.dead
    end

    local entry = Ledger.CloseLevel(sessions, totalPlayed, LedgerDB.includeRested)
    Ledger.RecordLevelClose(LedgerCharDB, entry)
    Ledger.Log("trace", string.format(
        "CierreNivel: cerrado nivel %d, %d sesion(es) agregadas, totalXP=%d, totalPlayed=%ds",
        entry.nivel, #sessions, entry.totalXP, entry.totalPlayed))

    -- Abre la sesion del nivel nuevo. No se reutiliza StartTracking
    -- aqui: su snapshot de initialXP (para arranques en frio) daria por
    -- perdida la xp que ya hay en el nivel nuevo, pero esa xp NO esta
    -- perdida -- si esto lo ha disparado un evento de xp de verdad
    -- (no el temporizador), ese mismo evento va a grabarla a
    -- continuacion como un evento normal con su src real. Ponerla
    -- ademas como initialXP la contaria dos veces (una vez como
    -- segmento gris "previous" y otra como el evento). Solo se
    -- snapshotea initialXP cuando el disparador es el temporizador de
    -- respaldo: ahi no hay ningun evento en camino que vaya a
    -- explicarla, igual que un arranque en frio.
    LedgerCharDB.sessions = {}
    sessions = LedgerCharDB.sessions
    local newSession = OpenSession(t, UnitLevel("player"), false)
    if reason == "temporizador" or reason == "PLAYER_LEVEL_UP duplicado" then
        newSession.initialXP = UnitXP("player")
    end

    timeTracker = Ledger.NewTracker(t, "idle")
    timeTracker.buckets = newSession.buckets
    Ledger.timeTracker = timeTracker
    matcher     = Ledger.NewMatcher()
    reconciler  = Ledger.NewReconciler()

    Ledger.RedrawXPBarFull()
    Ledger.RedrawTimeBar()
end

-- Borra por completo LedgerCharDB (todas las sesiones y niveles
-- guardados de este personaje) y arranca el seguimiento desde cero,
-- sin necesidad de /reload: vacia sessions/levels, reengancha
-- `sessions` a la tabla nueva (StartTracking) y abre la primera sesion
-- del nivel actual con initialXP = xp actual (igual que un personaje
-- nuevo). Reinicia tambien matcher/tracker/reconciler (via
-- StartTracking) y la referencia previousXP/previousMaxXP/previousLevel
-- para que el primer PLAYER_XP_UPDATE tras el borrado no calcule un
-- delta falso. Accion irreversible: pensada para /ldg wipe confirm.
function Ledger.WipeCharacterData(t)
    LedgerCharDB.levels   = {}
    LedgerCharDB.sessions = {}
    sessions = nil
    StartTracking(t, UnitLevel("player"))
    previousXP    = UnitXP("player")
    previousMaxXP = UnitXPMax("player")
    previousLevel = UnitLevel("player")
    Ledger.RedrawXPBarFull()
end

-- Cierra la sesion activa (tEnd) y abre una nueva marcada como manual.
-- Cierra, nunca borra: la sesion cerrada se queda en `sessions` hasta el
-- cierre de nivel. Tambien cierra el tramo de tiempo pendiente en la
-- sesion vieja y reengancha el tracker a los buckets (a cero) de la
-- nueva: cada sesion lleva su propio reparto de tiempo, que
-- core/level_close.lua suma con las demas del nivel al cerrarlo.
function Ledger.ResetSession(t)
    local current = CurrentSession()
    if not current then return end
    current.tEnd = t
    local newSession = OpenSession(t, current.nivel, true)
    if timeTracker then
        Ledger.AddSample(timeTracker, t, timeTracker.lastState)
        timeTracker.buckets = newSession.buckets
    end
end

----------------------------------------------------------------------
-- Vaciado periodico del buffer: combate, exploracion y mision tienen
-- todos una fuente propia hoy (CHAT_MSG_COMBAT_XP_GAIN clasificado, o
-- QUEST_TURNED_IN), asi que una cantidad solo debería acabar aqui con
-- src="unknown" si el mensaje/evento correspondiente se pierde del
-- todo (p.ej. saturacion de eventos). Sigue haciendo falta este
-- vaciado periodico para no esperar esa fuente para siempre.
----------------------------------------------------------------------

local function FlushMatcher()
    if not matcher then return end
    for _, paired in ipairs(Ledger.Flush(matcher, GetTime(), Ledger.Log)) do
        EmitEvent(paired)
    end
end

C_Timer.NewTicker(1, FlushMatcher)

----------------------------------------------------------------------
-- Ticker de 1s para los buckets de tiempo: comprueba si hace falta
-- cerrar el tramo "active" en curso (el reloj de inactividad -- tiempo
-- desde la ultima ganancia de xp o la ultima entrada en combate, lo que
-- sea mas reciente -- ha superado el umbral) y redibuja la barra de
-- tiempo. Se llama a AddSample solo en esa transicion real, nunca en
-- cada tick: si se resampleara "active" cada segundo mientras siguiera
-- por debajo del umbral, cada gap entre muestras seria de ~1s y la
-- reclasificacion retroactiva (core/time_buckets.lua) nunca llegaria a
-- ver un hueco largo de una vez. La barra en si se redibuja cada
-- segundo igualmente, usando Ledger.PreviewBuckets (sin mutar el
-- tracker) para que se vea crecer en vivo aunque no haya transicion.
----------------------------------------------------------------------

local function TickTimeState()
    if not timeTracker then return end
    local now = GetTime()

    local lastActivity = math.max(lastXPGainTime or 0, lastCombatEnterTime or 0)
    if Ledger.ShouldTransitionToTravel(timeTracker, now, lastActivity) then
        -- Directo a "travel", no a "idle": todo el hueco de inactividad
        -- (desde la ultima actividad real hasta ahora) se cuenta como
        -- desplazamiento de una vez, sin partirlo segun el instante
        -- exacto en que dispare este ticker.
        Ledger.Log("trace", string.format(
            "TimeBuckets: %.0fs sin actividad -- transicion active->travel", now - lastActivity))
        Ledger.AddSample(timeTracker, now, "travel")
    end

    Ledger.RedrawTimeBar()
end

C_Timer.NewTicker(1, TickTimeState)

----------------------------------------------------------------------
-- Eventos
----------------------------------------------------------------------

local ev = CreateFrame("Frame")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("PLAYER_XP_UPDATE")
ev:RegisterEvent("CHAT_MSG_COMBAT_XP_GAIN")
ev:RegisterEvent("QUEST_TURNED_IN")
ev:RegisterEvent("PLAYER_LEVEL_UP")
ev:RegisterEvent("PLAYER_REGEN_DISABLED")
ev:RegisterEvent("PLAYER_DEAD")
ev:RegisterEvent("PLAYER_UNGHOST")
ev:RegisterEvent("TIME_PLAYED_MSG")
ev:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    local t = GetTime()

    -- Si hay una subida de nivel pendiente de cerrar, la consume el
    -- primer evento de xp que llegue (de cualquiera de los tres tipos:
    -- no solo PLAYER_XP_UPDATE, porque CHAT_MSG_COMBAT_XP_GAIN o
    -- QUEST_TURNED_IN podrian llegar antes y tocar el matcher/sesion
    -- viejos si no se cierra antes). Si no llega ninguno a tiempo, la
    -- consume Ledger.PENDING_LEVEL_UP_TIMEOUT despues el temporizador
    -- de respaldo (ver ProcessPendingLevelUp).
    if pendingLevelUp and (event == "PLAYER_XP_UPDATE"
        or event == "CHAT_MSG_COMBAT_XP_GAIN"
        or event == "QUEST_TURNED_IN") then
        ProcessPendingLevelUp(t, event)
    end

    if event == "PLAYER_ENTERING_WORLD" then
        -- Login y cada pantalla de carga. Si no hay sesion todavia la
        -- arrancamos aqui; si ya la habia, solo resincronizamos la xp de
        -- referencia (y su maximo/nivel) para que la primera comparacion
        -- tras la carga no calcule un delta falso.
        if not sessions then
            StartTracking(t, UnitLevel("player"))
        end
        previousXP     = UnitXP("player")
        previousMaxXP  = UnitXPMax("player")
        previousLevel  = UnitLevel("player")
        RequestTimePlayed()

    elseif event == "PLAYER_XP_UPDATE" then
        local currentXP    = UnitXP("player")
        local currentMax   = UnitXPMax("player")
        local currentLevel = UnitLevel("player")

        local result = Ledger.ComputeXPDelta(previousXP, currentXP, previousMaxXP, previousLevel, currentLevel)

        Ledger.Log("trace", string.format(
            "PLAYER_XP_UPDATE t=%.3f xpAnterior=%s xpActual=%d maxAnteriorCacheado=%s nivelAnterior=%s nivelActual=%d delta=%s",
            t, tostring(previousXP), currentXP, tostring(previousMaxXP), tostring(previousLevel), currentLevel,
            result.ok and tostring(result.delta) or "?"))

        if result.ok then
            if result.levelsGained == 1 then
                Ledger.Log("info", string.format(
                    "PLAYER_XP_UPDATE t=%.3f subida de nivel: xp reconstruida = %d (maximo cacheado del nivel viejo = %d)",
                    t, result.delta, previousMaxXP))
            end

            -- delta = 0 es valido (p.ej. un PLAYER_XP_UPDATE sin cambio
            -- real): se ignora sin loguearlo como error.
            if result.delta ~= 0 then
                -- Ganancia de xp real: marca "active" ahora mismo (cierra
                -- lo que hubiera antes -- idle/travel -- y reinicia el
                -- reloj de inactividad de los buckets de tiempo).
                lastXPGainTime = t
                if timeTracker then
                    Ledger.AddSample(timeTracker, t, "active")
                end

                Ledger.AccountExpectedXP(reconciler, result.delta)
                local paired = Ledger.AddAmount(matcher, t, result.delta, Ledger.Log)
                if paired then EmitEvent(paired) end
            end
        else
            Ledger.Log("error", string.format("PLAYER_XP_UPDATE t=%.3f %s", t, result.reason))
        end

        previousXP, previousMaxXP, previousLevel = currentXP, currentMax, currentLevel

    elseif event == "CHAT_MSG_COMBAT_XP_GAIN" then
        Ledger.Log("trace", string.format("CHAT_MSG_COMBAT_XP_GAIN t=%.3f msg=<<%s>>", t, tostring(arg1)))
        local category, rested = HandleCombatXPGainMessage(arg1, t)
        local paired = Ledger.AddSource(matcher, t, category, Ledger.Log, rested)
        if paired then EmitEvent(paired) end

    elseif event == "QUEST_TURNED_IN" then
        -- arg1 = questID, arg2 = xp otorgada, arg3 = dinero otorgado.
        -- Se encola como fuente igual que un mensaje de combate (nunca
        -- solo se loguea): el mensaje de entrega de mision es identico
        -- al de exploracion ("You gain N experience."), asi que sin
        -- encolar QUEST_TURNED_IN como fuente propia no hay forma de
        -- distinguir uno de otro (ver SOURCE_PRIORITY en
        -- core/xp_gain_matcher.lua). arg2 se pasa como expectedXP para
        -- que EmitEvent haga la verificacion cruzada contra el delta
        -- real; la cantidad grabada sigue siendo siempre la del delta.
        local questID, questXP, questMoney = arg1, arg2, arg3
        Ledger.Log("trace", string.format(
            "QUEST_TURNED_IN t=%.3f questID=%s xp=%s dinero=%s",
            t, tostring(questID), tostring(questXP), tostring(questMoney)))
        local paired = Ledger.AddSource(matcher, t, "quest", Ledger.Log, 0, questXP)
        if paired then EmitEvent(paired) end

    elseif event == "PLAYER_LEVEL_UP" then
        -- Diagnostico de orden de llegada respecto a PLAYER_XP_UPDATE:
        -- arg1 es el nivel nuevo que reporta el propio evento;
        -- UnitLevel("player") es lo que la API dice AHORA MISMO -- si
        -- no coinciden, UnitLevel todavia no se ha actualizado en este
        -- instante. previousLevel es lo que este addon tenia cacheado
        -- del ultimo PLAYER_XP_UPDATE procesado (= el nivel que hay que
        -- cerrar).
        Ledger.Log("trace", string.format(
            "PLAYER_LEVEL_UP t=%.3f nivelNuevo(arg1)=%s UnitLevel=%s previousLevel_cacheado=%s",
            t, tostring(arg1), tostring(UnitLevel("player")), tostring(previousLevel)))
        Ledger.UpdateXP()

        if pendingLevelUp then
            -- Dos PLAYER_LEVEL_UP muy seguidos sin que se haya
            -- procesado el primero (doble ding). Caso limite: se fuerza
            -- el cierre del primero ya, con el nivel que tenia
            -- capturado, antes de marcar el segundo.
            Ledger.Log("error", "PLAYER_LEVEL_UP con una subida ya pendiente sin procesar -- se fuerza su cierre antes de marcar la nueva")
            ProcessPendingLevelUp(t, "PLAYER_LEVEL_UP duplicado")
        end

        if previousLevel then
            pendingLevelUp = { oldLevel = previousLevel }
            Ledger.Log("trace", string.format(
                "CierreNivel: subida pendiente marcada (nivel viejo=%d), esperando un evento de xp o %.0fms",
                previousLevel, Ledger.PENDING_LEVEL_UP_TIMEOUT * 1000))
            pendingLevelUp.timer = C_Timer.NewTimer(Ledger.PENDING_LEVEL_UP_TIMEOUT, function()
                Ledger.Log("trace", "CierreNivel: temporizador disparado, ningun evento de xp llego a tiempo")
                ProcessPendingLevelUp(GetTime(), "temporizador")
            end)
        else
            Ledger.Log("error", "PLAYER_LEVEL_UP sin previousLevel cacheado todavia -- no se puede saber que nivel cerrar")
        end

    elseif event == "PLAYER_REGEN_DISABLED" then
        -- Entrada en combate: marca "active" ya mismo. Nunca se usa
        -- PLAYER_REGEN_ENABLED (salir de combate) como señal de nada --
        -- se sale de combate constantemente entre pull y pull, y eso no
        -- significa dejar de estar "activo" para el reloj de
        -- inactividad.
        lastCombatEnterTime = t
        if timeTracker then
            Ledger.AddSample(timeTracker, t, "active")
        end

    elseif event == "PLAYER_DEAD" then
        if timeTracker then
            Ledger.AddSample(timeTracker, t, "dead")
        end

    elseif event == "PLAYER_UNGHOST" then
        if timeTracker then
            Ledger.AddSample(timeTracker, t, "idle")
        end

    elseif event == "TIME_PLAYED_MSG" then
        -- arg1 = tiempo total, arg2 = tiempo jugado en el nivel actual.
        local session = CurrentSession()
        if session then
            session.levelTimePlayed = arg2
        end
    end
end)
