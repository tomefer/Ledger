-- Ledger - core/time_buckets.lua
-- Acumula el tiempo transcurrido en los buckets active, idle, travel y
-- dead a partir de muestras de estado con marca de tiempo. Logica pura:
-- no usa ninguna API de WoW, el reloj se recibe siempre como parametro.
--
-- Reclasificacion retroactiva: si el jugador queda en "active" y pasan
-- `threshold` segundos o mas sin una nueva muestra de combate, todo ese
-- tramo se cuenta como "travel" en vez de "active" (no era combate, era
-- desplazamiento).

local ADDON_NAME, Ledger = ...

print("Ledger: core/time_buckets.lua")

-- Segundos sin combate a partir de los cuales un tramo "active" pasa a
-- contarse como "travel".
Ledger.INACTIVITY_THRESHOLD = 30

-- Forma comun de un juego de buckets vacio, para no repetir el literal
-- en core/events.lua (session.buckets), core/level_close.lua (agregado
-- de la entrada de levels) y core/xp.lua (migracion).
function Ledger.NewEmptyBuckets()
    return { active = 0, idle = 0, travel = 0, dead = 0 }
end

-- Crea un tracker. state es el estado vigente a partir de t0: "active",
-- "idle", "travel" o "dead". threshold es opcional (por defecto
-- Ledger.INACTIVITY_THRESHOLD).
function Ledger.NewTracker(t0, state, threshold)
    return {
        buckets   = Ledger.NewEmptyBuckets(),
        lastT     = t0,
        lastState = state,
        threshold = threshold or Ledger.INACTIVITY_THRESHOLD,
    }
end

-- A que bucket va un tramo de `elapsed` segundos que estaba en `state`:
-- el mismo, salvo que fuera "active" y el tramo alcance el umbral, en
-- cuyo caso se reclasifica entero como "travel" (reclasificacion
-- retroactiva). Compartido por AddSample (que si muta el tracker) y
-- PreviewBuckets (que no).
local function ClassifyElapsed(state, elapsed, threshold)
    if state == "active" and elapsed >= threshold then
        return "travel"
    end
    return state
end

-- Registra que a partir del instante t el estado pasa a ser `state`.
-- Cierra el tramo anterior [lastT, t) y lo suma al bucket que le
-- corresponde, aplicando la reclasificacion retroactiva si procede.
function Ledger.AddSample(tracker, t, state)
    local elapsed = t - tracker.lastT
    if elapsed > 0 then
        local bucket = ClassifyElapsed(tracker.lastState, elapsed, tracker.threshold)
        tracker.buckets[bucket] = tracker.buckets[bucket] + elapsed
    end
    tracker.lastT     = t
    tracker.lastState = state
end

-- Vista previa "a fecha de now" de los buckets, SIN mutar el tracker:
-- una copia de tracker.buckets con el tramo abierto [lastT, now) ya
-- sumado al bucket que le correspondería si se cerrara ahora mismo
-- (misma reclasificacion retroactiva que AddSample). Sirve para que una
-- barra en pantalla se vea crecer cada segundo sin tener que cerrar de
-- verdad el tramo en cada redibujado -- eso rompería la
-- reclasificacion retroactiva, que necesita ver el hueco completo de
-- una vez (ver core/xp_capture.lua: el ticker de 1s solo llama a
-- AddSample en las transiciones de verdad, nunca en cada tick).
function Ledger.PreviewBuckets(tracker, now)
    local preview = {
        active = tracker.buckets.active,
        idle   = tracker.buckets.idle,
        travel = tracker.buckets.travel,
        dead   = tracker.buckets.dead,
    }
    local elapsed = now - tracker.lastT
    if elapsed > 0 then
        local bucket = ClassifyElapsed(tracker.lastState, elapsed, tracker.threshold)
        preview[bucket] = preview[bucket] + elapsed
    end
    return preview
end

-- Decide si hace falta cerrar el tramo "active" en curso porque el
-- reloj de inactividad (tiempo desde la ultima señal de actividad:
-- ganancia de xp o entrada en combate, lo que sea mas reciente) ha
-- superado el umbral del tracker. Logica pura: no muta nada, no toca
-- GetTime ni ninguna API de WoW -- todo se recibe como parametro. Si es
-- true, quien llama debe cerrar el tramo con
-- Ledger.AddSample(tracker, now, "travel") -- directo a travel, no a
-- idle: todo el hueco de inactividad se cuenta como desplazamiento
-- hasta la siguiente actividad real, sin partirlo en dos buckets segun
-- el instante exacto en que dispare el ticker (ver "idle" mas abajo,
-- que es un estado aparte para cuando se sabe que NO se esta viajando,
-- p.ej. justo despues de resucitar).
function Ledger.ShouldTransitionToTravel(tracker, now, lastActivityTime)
    return tracker.lastState == "active" and (now - lastActivityTime) >= tracker.threshold
end
