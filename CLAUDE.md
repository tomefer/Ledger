# Ledger

Addon de WoW Classic Era (cliente 1.15.x, Lua 5.1). Se llamaba XPTrack;
renombrado a Ledger — si ves "XPTrack" en algún sitio (código, symlink de
Interface/AddOns, apuntes viejos) es residuo del nombre anterior.

## Restricciones
- Lua 5.1. Sin goto, sin operadores bitwise nativos, sin // .
- API de Classic Era únicamente. NADA de retail moderno.
- Sin librerías externas. Nada de Ace3.
- Si no sabes si una API existe en Classic Era, pregunta en vez de asumir.

## Arquitectura
- `Ledger/core/` — lógica pura. NO puede referenciar ninguna API de WoW.
  El tiempo y el estado se pasan como parámetros.
- `Ledger/ui/` — frames y registro de eventos. Capa fina, sin lógica.
- `spec/` — tests con busted. Fuera de la carpeta del addon.
- Para compartir estado entre ficheros se usa el namespace del segundo
  valor de `...` (la tabla de addon que da WoW), asignado siempre a la
  variable local `Ledger` — nunca `ns` ni una global suelta. Ejemplo:
  `local ADDON_NAME, Ledger = ...`.

## Comandos
- Tests: `busted`
- Slash command en el juego: `/ldg` (alias `/ledger`). El parseo del
  texto (`core/slash_command.lua: Ledger.ParseCommand(msg)`) es lógica
  pura y testeada (`spec/slash_command_spec.lua`); `ui/events.lua` solo
  despacha. Insensible a mayúsculas, tolerante a espacios de más. Un
  subcomando de primer nivel desconocido (o un argumento de `log` no
  reconocido) responde lo mismo que `/ldg help`.
  - Sin argumentos: alterna el panel principal.
  - `/ldg help`: lista todos los subcomandos con su descripción
    (`Ledger.SLASH_COMMANDS` en `core/slash_command.lua`, fuente única
    tanto del texto de ayuda como de qué se considera un subcomando
    conocido).
  - `/ldg debug`: alterna el panel de depuración (`ui/debug_frame.lua`):
    frame movible/redimensionable con un EditBox multilínea de solo
    lectura (seleccionable, para copiar), botón de refresco manual y
    checkbox de autorefresco cada 2s. Muestra el volcado de
    `core/state_dump.lua: Ledger.FormatState(LedgerCharDB)`.
  - `/ldg dump`: el mismo volcado de `Ledger.FormatState`, pero al chat
    y sin abrir el panel.
  - `/ldg reset`: cierra la sesión activa y abre una nueva con
    `manual = true`.
  - `/ldg log <off|error|info|trace>`: cambia el nivel de log activo
    (`core/log.lua: Ledger.SetLogLevel`).
  - `/ldg log show`: vuelca el buffer de log al panel de depuración
    (abre `ui/debug_frame.lua` en modo "log" en vez de "state").
  - `/ldg log chat`: activa o desactiva el eco del log al chat.
  - `/ldg strings`: imprime los global strings de xp en uso (patrón
    principal y sufijo de bono por descanso) con su valor literal en
    este cliente (`core/chat_patterns.lua: Ledger.FormatXPGainStrings`).
  - `/ldg rested`: alterna `LedgerDB.includeRested` (si el bono por
    descanso cuenta en `TotalXP`/`CloseLevel`; ver "Series declarativas"
    arriba) y actualiza la etiqueta del panel principal.
  - `/ldg bar`: muestra u oculta la barra de composición de xp del
    nivel, anclada sobre la barra de xp nativa (ver "Barra de
    composición de xp" más abajo). Informa directamente por chat de si
    se ha podido anclar y cuántos segmentos hay (sin depender de que el
    log esté activo): si no hay ninguno todavía es que no hay xp
    registrada en el nivel actual, no un fallo.
  - `/ldg time`: muestra u oculta la barra de reparto de tiempo del
    nivel (active/travel/idle/dead), independiente de `/ldg bar` (ver
    "Barra de reparto de tiempo" más abajo).
  - `/ldg wipe confirm`: borra por completo `LedgerCharDB` (todas las
    sesiones y niveles guardados de este personaje) y arranca el
    seguimiento desde cero, sin `/reload`
    (`ui/xp_capture.lua: Ledger.WipeCharacterData`). `/ldg wipe` a
    secas no borra nada, solo avisa — hace falta el `confirm` explícito
    porque es irreversible. Solo afecta a `LedgerCharDB` (por
    personaje); no toca `LedgerDB` (posición del panel, `includeRested`,
    `barShown`, etc., que son de cuenta).
- Despliegue: hay un symlink desde Interface/AddOns. Como el addon se
  ha renombrado (carpeta y .toc pasan de `XPTrack` a `Ledger`), **hay que
  recrear ese symlink** apuntando a la carpeta `Ledger/` — WoW exige que
  el nombre de la carpeta coincida con el del .toc. Hecho eso, basta con
  /reload dentro del juego.

## Modelo de datos

### Series declarativas (`core/series.lua`)

Cada serie temporal (array plano dentro de una sesión) se declara una
vez en `Ledger.SERIES`:

```lua
Ledger.SERIES = {
    xp = { key = "e", stride = 4, fields = { "off", "xp", "src", "rested" } },
    -- xp es la xp TOTAL del evento (delta de UnitXP); rested es la parte
    -- de esa xp que vino del bono por descanso (0 si no hubo bono).
    -- Se cumple siempre xp - rested >= 0 (core/events.lua: AddEvent
    -- recorta rested si llegara mayor que xp).
    -- futuras: gold (stride 3), rep (stride 4, con campo faction),
    --          loot (stride 3). Añadir una serie es una entrada aquí y
    --          nada más.
}
```

- `key`: campo de `session` donde vive el array plano de esa serie.
- `stride`: valores por registro.
- `fields`: nombre de cada posición dentro de un registro, en orden.

Helpers genéricos, parametrizados por la definición de serie (nunca
asumen 3 campos ni el nombre `"e"`):

- `Ledger.SeriesFieldIndex(seriesDef, name)` → índice (1-based) del
  campo `name`, o `nil`.
- `Ledger.AppendRecord(session, seriesDef, ...)` → añade un registro
  (`stride` valores) al array plano.
- `Ledger.RecordCount(session, seriesDef)` → `#array / stride`.
- `Ledger.ReadRecord(session, seriesDef, index)` → tabla con nombre de
  campo para el registro `index` (1-based), o `nil` si no existe.

**Regla dura**: el serializador a texto y el panel de depuración (aún
sin construir) deben iterar `Ledger.SERIES`, nunca referenciar `"e"` ni
el `3` de la serie xp directamente.

`core/events.lua` es la capa específica de la serie `xp` construida
sobre esos helpers (`NewSession`, `AddEvent`, `EventCount`, `TotalXP`,
`TotalRested`, `XPBySource`, `LastOffset`, `EffectiveXP`).
`core/level_close.lua` también consume `Ledger.SERIES.xp` en vez de
hardcodear el stride al construir la curva por minuto.

**Bono por descanso e `includeRested`**: `Ledger.EffectiveXP(xp, rested,
includeRested)` es el punto único que decide si el bono cuenta —
`includeRested` es `true` por defecto (cuenta `xp` tal cual) o `false`
(cuenta `xp - rested`). `Ledger.TotalXP(session, includeRested)` y
`Ledger.CloseLevel(sessions, totalPlayed, includeRested)` (totales y
curva por minuto) lo aceptan como parámetro opcional; `XPBySource`
sigue siendo siempre la xp total tal cual (desglose, no métrica de
velocidad), y `TotalRested`/`entry.totalRested` son siempre el bono
real acumulado, nunca afectados por el toggle — es precisamente lo que
el toggle resta o no de los totales de arriba. El ajuste persistente
vive en `LedgerDB.includeRested` (cuenta, no por personaje: ver
SavedVariables más abajo); `/ldg rested` lo alterna y
`ui/frame.lua: Ledger.UpdateRestedLabel()` lo refleja en el panel
principal ("Descanso: incluido"/"excluido").

### Sesión activa

Creada con `core/events.lua: NewSession(t0, nivel, mode, manual)`:

```lua
session = {
    t0     = <GetTime() de inicio>,
    tEnd   = <GetTime() de cierre, o nil mientras está activa>,
    nivel  = <nivel del jugador al iniciar la sesión>,
    mode   = <"farm" | "quest" | "dungeon" | nil>,  -- informativo; NUNCA
                                                      -- sobrescribe ni
                                                      -- altera el src de
                                                      -- ningún evento
    manual = <true si se abrió con /ldg reset, false en las demás>,
    buckets = { active = 0, idle = 0, travel = 0, dead = 0 },  -- ver
                -- "Buckets de tiempo" abajo; el tracker en vivo
                -- (ui/xp_capture.lua) reengancha aquí su tabla de
                -- buckets, así que sobrevive a /reload como el resto.
    e = {
        -- array plano de la serie xp (ver Ledger.SERIES.xp arriba):
        -- off, xp, src, rested, off, xp, src, rested, ...
        -- off en décimas de segundo desde t0 (ya calculado por quien
        -- llama; core/events.lua no toca GetTime ni ninguna API de WoW).
        -- src es un código de origen ("kill", "explore", "unknown"; ver
        -- "Captura de eventos" más abajo). rested es la parte de xp que
        -- vino del bono por descanso (0 si no hubo).
    },
}
```

### Buckets de tiempo (`core/time_buckets.lua: NewTracker(t0, state, threshold)`)

```lua
tracker = {
    buckets   = { active = 0, idle = 0, travel = 0, dead = 0 },
    lastT     = <marca de tiempo de la ultima muestra>,
    lastState = <estado vigente desde lastT: "active"|"idle"|"travel"|"dead">,
    threshold = 30,  -- segundos sin combate para reclasificar active -> travel
}
```

`AddSample(tracker, t, state)` cierra el tramo `[lastT, t)` y lo suma al
bucket de `lastState`. Reclasificación retroactiva: si `lastState` era
`"active"` y el hueco alcanza `threshold` segundos (por defecto 30, en
`Ledger.INACTIVITY_THRESHOLD` — bajado desde los 180 iniciales a
petición del usuario, mismo mecanismo, solo la ventana es más corta),
ese tramo entero se cuenta como `"travel"` en vez de `"active"` (se
asume desplazamiento, no combate).

**Alimentación real (`ui/xp_capture.lua`)**, antes solo existía en
`core/` con tests en verde pero sin ningún llamador desde el juego:

- **Reloj de inactividad**: el instante de la última señal de
  actividad, la más reciente entre una ganancia de xp real (delta
  distinto de 0 en `PLAYER_XP_UPDATE`) y un `PLAYER_REGEN_DISABLED`
  (entrada en combate). **Nunca `UnitAffectingCombat`**: se sale de
  combate constantemente entre pull y pull, y eso no debe contar como
  "dejar de estar activo". Ambas señales llaman a
  `Ledger.AddSample(tracker, t, "active")` en el momento exacto,
  cerrando lo que hubiera antes.
- **`dead`**: `PLAYER_DEAD` → `AddSample(tracker, t, "dead")`;
  `PLAYER_UNGHOST` → `AddSample(tracker, t, "idle")`. El AFK no pausa
  nada: el tiempo muerto (o inactivo) es parte de lo que se mide, no se
  descuenta de ningún sitio.
- **Ticker de 1s** (`TickTimeState`, separado del que vacía el
  matcher): en cada tick comprueba
  `Ledger.ShouldTransitionToTravel(tracker, now, lastActivityTime)` —
  true solo si `lastState` sigue siendo `"active"` y el reloj de
  inactividad ya superó el umbral — y si es así hace la ÚNICA llamada a
  `AddSample(tracker, now, "travel")` que cierra el tramo entero de una
  vez (para que la reclasificación retroactiva vea el hueco completo,
  no fragmentado en trocitos de ~1s: si se resampleara `"active"` cada
  segundo mientras siguiera por debajo del umbral, ningún hueco entre
  muestras llegaría nunca a superar el umbral). **Va directo a
  `"travel"`, nunca a `"idle"`**: si fuera a `"idle"` primero, un hueco
  de inactividad algo mayor que el umbral se repartiría entre el tramo
  ya reclasificado como travel y lo que sigue acumulándose después de
  la transición como idle, hasta la siguiente actividad real — nada
  intuitivo, dos buckets para un único hueco continuo sin ninguna razón
  de comportamiento real detrás, solo un artefacto de cuándo dispara el
  ticker. Con la transición directa a `"travel"`, todo el hueco (desde
  la última actividad real hasta la siguiente) cae en el mismo bucket:
  la primera llamada (al detectar el umbral) cierra el primer tramo ya
  reclasificado, y la siguiente actividad real cierra el resto también
  como `"travel"` (`ClassifyElapsed` no lo reclasifica de nuevo porque
  `lastState` ya no es `"active"`). `"idle"` queda solo para su otro
  uso: justo después de `PLAYER_UNGHOST`, un caso distinto donde no se
  asume desplazamiento. El mismo ticker redibuja la barra
  de tiempo cada segundo usando `Ledger.PreviewBuckets(tracker, now)`
  (vista previa sin mutar nada, para que se vea crecer en vivo aunque
  no haya transición de verdad).
- **Persistencia por sesión**: `timeTracker.buckets` se reengancha
  (misma tabla, no una copia) a `session.buckets` en
  `StartTracking`/`ResetSession`/el cierre de nivel diferido, así que
  cualquier `AddSample` escribe directamente en la SavedVariable. Esto
  es un cambio deliberado respecto a lo documentado antes ("mismo
  tracker de tiempo" para las sesiones manuales): ahora cada sesión
  lleva su propio reparto de tiempo — `lastState`/`threshold` siguen
  siendo continuos (mismo objeto `tracker`, solo se le cambia la tabla
  `buckets`), pero los totales acumulados sí arrancan a cero por
  sesión, y `CloseLevel` los suma entre todas las del nivel (ver
  abajo).

### Entrada de `levels` (`core/level_close.lua: CloseLevel(sessions, totalPlayed, includeRested)`)

```lua
levels[nivel] = {
    nivel       = <nivel>,
    totalXP     = <suma de la xp EFECTIVA de todas las sesiones del
                   nivel, xp o xp-rested segun includeRested (true por
                   defecto); ver Ledger.EffectiveXP arriba>,
    totalRested = <suma del bono por descanso real, SIN toggle: no
                   cambia con includeRested>,
    totalPlayed = <segundos jugados en el nivel; se pasa ya calculado,
                   CloseLevel NO lo calcula>,
    bySource    = { kill = ..., explore = ..., ... },  -- xp total tal
                                                         -- cual, nunca
                                                         -- afectado por
                                                         -- includeRested
    curve       = { xpMinuto1, xpMinuto2, ... },  -- downsampleada, densa
                                                    -- (sin huecos), minuto
                                                    -- relativo al t0 de
                                                    -- cada sesion; xp
                                                    -- efectiva, tambien
                                                    -- sujeta a includeRested
    buckets     = { active = 0, idle = 0, travel = 0, dead = 0 },  -- suma
                    -- de session.buckets de TODAS las sesiones del nivel
                    -- (Ledger.NewEmptyBuckets si alguna sesion no
                    -- trajera el campo, p.ej. datos de antes de esta
                    -- migracion)
}
```

`sessions` es un array de tablas con la forma de `session`. Importante:
`CloseLevel` NO detecta límites de nivel — si una sesión real abarca dos
niveles, quien llama le pasa el array de eventos ya troceado en dos, uno
por cada cierre de nivel.

### Captura de eventos (`ui/xp_capture.lua` + `core/xp_gain_matcher.lua` + `core/chat_patterns.lua`)

- Todas las sesiones del nivel actual viven en una lista (`sessions`,
  local de `ui/xp_capture.lua`); la última es la activa. Esa lista **es**
  `LedgerCharDB.sessions` (misma tabla, asignada por referencia en
  `StartTracking`, que corre en el primer `PLAYER_ENTERING_WORLD`), así
  que cada evento que se añade a una sesión persiste directamente en la
  SavedVariable, sin ningún paso de guardado aparte. El tracker de
  buckets y el matcher siguen viviendo solo en memoria (no se persisten
  — ver "Pendiente" más abajo).
- **Cantidad de xp y subida de nivel** (`core/xp_delta.lua:
  Ledger.ComputeXPDelta`, lógica pura): la cantidad sale de comparar
  `UnitXP("player")` con el valor anterior en cada `PLAYER_XP_UPDATE`,
  pero `UnitXP` se reinicia a un valor pequeño al subir de nivel — una
  resta ingenua (`xpActual - xpAnterior`) da un delta negativo y pierde
  la xp entera (bug real observado: `xpAnterior=809 xpActual=79
  delta=-730`). `ui/xp_capture.lua` cachea `UnitXPMax("player")` y
  `UnitLevel("player")` en cada `PLAYER_XP_UPDATE` (nunca se lee
  `UnitXPMax` en el instante del ding: para entonces ya devuelve el
  máximo del nivel **nuevo**, no el del viejo que hace falta para la
  cuenta) y se los pasa a `ComputeXPDelta` junto con los valores
  actuales:
  - Mismo nivel: `delta = xpActual - xpAnterior` (si sale negativo sin
    subida de nivel de por medio, es un caso sin explicación válida:
    `ok=false`, se loguea a ERROR, no se inventa un número).
  - Sube exactamente un nivel: `delta = (maxAnteriorCacheado - xpAnterior)
    + xpActual`.
  - Sube más de un nivel de golpe: **no hay API en Classic Era para el
    requisito de xp de niveles intermedios**, así que no es calculable.
    Se detecta contando `UnitLevel` antes/después y se loguea a ERROR
    con los datos en vez de calcular un número incorrecto en silencio.
  - `delta = 0` es válido (no es un error) y se ignora sin loguearse
    como tal.
- **Contador de reconciliación** (`core/xp_reconciler.lua`, nuevo — no
  existía nada parecido antes de este fix): acumula por un lado toda la
  xp que un delta válido dice que debería grabarse
  (`Ledger.AccountExpectedXP`, llamado en cuanto `ComputeXPDelta`
  devuelve `ok=true` con `delta ~= 0`) y por otro la que realmente
  acaba grabada en una sesión (`Ledger.AccountRecordedXP`, llamado en
  `EmitEvent`). `Ledger.ReconciliationGap(reconciler)` es la diferencia;
  puede ser transitoriamente distinta de 0 mientras algo espera dentro
  del margen de emparejamiento, pero un hueco que no se cierra nunca es
  la firma de un bug que descarta xp en silencio — exactamente el caso
  del bug de subida de nivel de arriba. Vive en `ui/xp_capture.lua`
  junto al matcher y al tracker de tiempo (solo en memoria, no se
  persiste; aún no hay ningún sitio que lea `ReconciliationGap` para
  avisar en caliente si se dispara — ver "Pendiente").
- El origen sale de
  `CHAT_MSG_COMBAT_XP_GAIN`: `ui/xp_capture.lua` enumera en tiempo de
  carga **todos** los global strings de `_G` cuyo nombre empiece por
  `COMBATLOG_XPGAIN_` (nunca una lista fija ni filtrada a
  `FIRSTPERSON`: el evento en sí ya solo se dispara para xp del propio
  jugador) y construye un patrón por cada uno
  (`core/chat_patterns.lua: Ledger.BuildPattern`, ancla solo el
  principio del mensaje con `^`, nunca el final: el cliente puede
  añadir sufijos que el global string no contempla, como el bono por
  descanso — `"... you gain 172 experience. (+86 exp Rested bonus)"` —
  y un `$` al final rompía ese caso). `core/chat_patterns.lua:
  Ledger.ClassifyXPGainMatch` (lógica pura) prueba el mensaje contra
  cada variante en orden y clasifica: `"kill"` si la variante que casó
  lleva nombre de criatura (tiene `%s` en su global string), `"explore"`
  si no lo lleva o si ninguna variante casó. **Nunca devuelve
  `"unknown"`**: la sola llegada del evento ya confirma que es xp de
  combate o exploración, aunque el formato exacto no se reconozca.
- **Bono por descanso**: `ui/xp_capture.lua` enumera además (por
  separado de la lista de arriba) los global strings de `_G` cuyo
  nombre empiece por `COMBATLOG_XPGAIN_EXHAUSTION` y construye un
  patrón sin anclar por cada uno
  (`core/chat_patterns.lua: Ledger.BuildSuffixPattern`, a diferencia de
  `BuildPattern` no ancla ni el principio: el sufijo de bono va pegado
  al final de la frase, no al principio). `Ledger.ExtractRestedBonus`
  (lógica pura) prueba el mensaje contra cada variante y devuelve la
  cantidad capturada, o `0` si el mensaje no trae sufijo. **Supuesto sin
  confirmar en el juego**: que el nombre `COMBATLOG_XPGAIN_EXHAUSTION*`
  es correcto en el cliente 1.15.x (convención de Blizzard desde varias
  expansiones, pero no verificada aquí). Comprobar con `/ldg strings`,
  que imprime también esta familia con su valor literal en este
  cliente. **La cantidad total (`xp`) sigue saliendo siempre del delta
  de `UnitXP`, nunca del mensaje**: el mensaje solo aporta `rested`, la
  parte de esa xp que vino del bono.
- Cantidad y origen llegan por separado y no siempre en el mismo orden:
  `core/xp_gain_matcher.lua` los empareja por proximidad temporal
  (margen `Ledger.MAX_MATCH_GAP`, 1.0s), propagando también `rested`
  como atributo del origen. El xp que nunca tiene ninguna fuente que
  emparejar se suelta cada segundo (`C_Timer.NewTicker`) con
  `src = "unknown"`, `rested = 0`.
- **`QUEST_TURNED_IN` y prioridad sobre "explore"**: el mensaje de
  entrega de misión ("You gain N experience.") es idéntico al de
  exploración — `COMBATLOG_XPGAIN_FIRSTPERSON_UNNAMED` no puede
  desambiguarlos por sí solo — así que `QUEST_TURNED_IN`
  (`questID, xp, dinero`) se encola como fuente propia
  (`Ledger.AddSource(matcher, t, "quest", log, 0, xp)`), igual que
  cualquier mensaje de combate, en vez de solo loguearse. Cuando varias
  fuentes caen dentro del margen a la vez, `core/xp_gain_matcher.lua:
  SOURCE_PRIORITY` hace que `"quest"` gane siempre a cualquier otra
  (`PopClosest` desempata primero por prioridad y solo luego por
  cercanía temporal); `"explore"` solo se usa cuando no hay ningún
  `QUEST_TURNED_IN` en la ventana. El `xp` otorgado por la quest (arg2)
  viaja como `expectedXP` en el evento emparejado, para verificación
  cruzada: `ui/xp_capture.lua: EmitEvent` compara `expectedXP` contra el
  `xp` real (siempre el delta de `UnitXP`, nunca el de la quest) y
  loguea a ERROR si no coinciden — la cantidad grabada sigue siendo
  siempre la del delta, la discrepancia es solo una señal de alarma.
- **Instrumentación de diagnóstico (ver más abajo, "Sistema de log")**:
  todo el flujo anterior (eventos crudos, intentos de casado con sus
  capturas, bono por descanso detectado, estado de la cola de
  emparejamiento) se loguea a nivel TRACE. `/ldg strings` imprime cada
  global string en uso (las dos familias) con su valor literal en este
  cliente y el patrón derivado.

### Cierre de nivel (`ui/xp_capture.lua`: `PLAYER_LEVEL_UP` + cierre diferido)

`PLAYER_LEVEL_UP` no cierra el nivel al momento: solo marca una subida
pendiente (`pendingLevelUp = { oldLevel = previousLevel, timer = }`,
local a `ui/xp_capture.lua`) y programa un `C_Timer.NewTimer` de
respaldo (`Ledger.PENDING_LEVEL_UP_TIMEOUT`, 0.25s). El cierre real
(`ProcessPendingLevelUp`) lo dispara **lo primero que llegue**:

- El primer evento de xp (`PLAYER_XP_UPDATE`, `CHAT_MSG_COMBAT_XP_GAIN`
  o `QUEST_TURNED_IN`) — comprobado al principio del despachador de
  eventos, antes de la cadena de `if/elseif`, para que cualquiera de
  los tres consuma la subida pendiente antes de tocar el
  matcher/sesión (si solo se comprobara en `PLAYER_XP_UPDATE`, un
  `CHAT_MSG_COMBAT_XP_GAIN` o `QUEST_TURNED_IN` que llegara antes
  seguiría escribiendo en el matcher del nivel viejo).
- El temporizador de respaldo, si no llega ninguno de esos tres a
  tiempo — el cierre nunca depende de que llegue un evento que quizá no
  llegue.

`ProcessPendingLevelUp` es idempotente (pone `pendingLevelUp = nil` y
cancela el temporizador nada más entrar, así que si el disparador de
respaldo y un evento de xp casi coinciden, el segundo no hace nada) y
hace, en orden: cierra el tramo de tiempo pendiente en `timeTracker`
para tener un `totalPlayed` exacto, llama a
`Ledger.CloseLevel(sessions, totalPlayed, LedgerDB.includeRested)` y
`Ledger.RecordLevelClose(LedgerCharDB, entry)`, y abre la sesión del
nivel nuevo (`LedgerCharDB.sessions = {}` + `OpenSession`), reiniciando
`timeTracker`/`matcher`/`reconciler` para el nivel que empieza.

**`initialXP` de la sesión nueva, con cuidado de no contar la xp dos
veces**: si el disparador fue un evento de xp de verdad, esa xp que ya
había cruzado al nivel nuevo la va a grabar ESE MISMO evento a
continuación como un evento normal (con su `src` real) — así que la
sesión nueva arranca con `initialXP` sin poner (0), porque ponerlo a
`UnitXP("player")` la contaría dos veces (una como segmento gris
"previous" y otra como el evento). Solo se snapshotea `initialXP =
UnitXP("player")` cuando el disparador es el temporizador de respaldo
(o el caso límite de doble `PLAYER_LEVEL_UP`, ver abajo): ahí no hay
ningún evento en camino que vaya a explicar esa xp.

**Caso límite sin resolver del todo**: si llega un segundo
`PLAYER_LEVEL_UP` antes de procesar el primero (dos dings muy
seguidos), se fuerza el cierre del primero con el nivel que tenía
capturado (`previousLevel`, que en ese momento sigue siendo el de
antes del primer ding) antes de marcar el segundo. Funciona sin
reventar pero no está pensado a fondo — ver "Pendiente".

Diagnóstico: `PLAYER_LEVEL_UP` loguea a TRACE el nivel que reporta el
propio evento, `UnitLevel("player")` en ese instante y el
`previousLevel` cacheado (para poder ver si `UnitLevel` va con retraso
respecto al evento); `ProcessPendingLevelUp` loguea a TRACE quién la
consume y, al cerrar, el nivel cerrado, cuántas sesiones se agregaron,
el `totalXP` y el `totalPlayed`.

### Reset manual (`/ldg reset` → `Ledger.ResetSession(t)`)

Cierra la sesión activa (`session.tEnd = t`) y abre una nueva con
`manual = true`, del mismo nivel. **Cierra, nunca borra**: la sesión
cerrada se queda en la lista `sessions` hasta el cierre de nivel, porque
`CloseLevel` agrega TODAS las sesiones del nivel, no solo la última.
Una sesión manual se comporta igual que cualquier otra en todo lo demás
(mismas series, mismo tracker de tiempo).

### Barra de composición de xp (`core/xp_bar.lua` + `ui/xp_bar.lua`, `/ldg bar`)

Barra de segmentos anclada justo encima de la barra de xp nativa, un
color por tramo de `src`, que representa de qué vino la xp del nivel
actual. Eje X: 0 a `UnitXPMax("player")`, mismo ancho y misma posición
horizontal que la barra nativa (`ui/xp_bar.lua: AnchorToNativeBar`).

- **Fuente de datos: TODAS las sesiones del nivel, nunca solo la
  activa** — `Ledger.ConcatSeries(sessions, seriesDef)` (nuevo helper
  genérico de `core/series.lua`, parametrizado por la definición de
  serie como el resto) concatena el array `e` de cada sesión de
  `LedgerCharDB.sessions` en orden. Un `/ldg reset` no altera la vista:
  abre una sesión nueva, pero la anterior se queda en la lista y sigue
  contando.
- **Cálculo puro** (`core/xp_bar.lua: Ledger.ComputeBarSegments(flatArray,
  initialXP, widthPx, maxXP)`, sin API de WoW, itera `Ledger.SERIES.xp`
  sin asumir stride ni nombres de campo): fusiona registros consecutivos
  del mismo `src` en un único segmento (**obligatorio**: sin fusión son
  miles de texturas) y reparte `widthPx` proporcionalmente a `maxXP`.
  El redondeo de cada segmento se hace sobre el acumulado ideal, no
  sobre el segmento suelto (`RoundedWidths`), para que la suma de
  anchuras nunca supere `widthPx` aunque haya muchos segmentos
  pequeños. Devuelve `{ offset=, width=, src=, restedWidth= }` por
  segmento (todo en píxeles; `restedWidth` es la parte de `width` que
  corresponde al bono por descanso del segmento, proporcional a
  `rested/xp`, siempre `<= width`).
- **Segmento inicial gris**: si `initialXP > 0`, se antepone un segmento
  con `src = Ledger.BAR_INITIAL_SRC` ("previous") y ese `initialXP`. Es
  la xp que el jugador ya llevaba en el nivel antes de que el addon
  empezara a registrar: `UnitXP("player")` en el instante en que se
  abre la primera sesión del nivel (`ui/xp_capture.lua: StartTracking`,
  cuando `#sessions == 0`), menos la xp registrada en ese instante
  (0, porque es la primera vez). Se guarda como `sessions[1].initialXP`
  — la sesión ya es la SavedVariable real, así que sobrevive a
  `/reload` sin ningún paso de guardado aparte, igual que el resto de
  `session`. **Nota**: vive en la sesión, no en `levels[nivel]` (que
  todavía no existe para el nivel en curso — ver "Pendiente"); si algún
  día se cablea `CloseLevel` para el nivel activo, revisar si conviene
  trasladarlo allí.
- **Paleta** (`ui/palette.lua: Ledger.PALETTE`, tabla única y
  **compartida con la barra de tiempo** — ver esa sección más abajo —
  nunca valores sueltos repartidos por el código de dibujado): `kill`
  #C8A34E (dorado apagado) / `quest` #3FA98C (verde azulado) /
  `explore` #8C7BB5 (violeta claro) / `unknown` #6E6A66 (gris cálido),
  más `_fallback` (magenta chillón, src/bucket no reconocido — no
  debería verse nunca). El segmento inicial `Ledger.BAR_INITIAL_SRC`
  ("previous") reutiliza el color de `unknown`: ambos son, en esencia,
  "no lo sabemos". Cada entrada en formato 0-1, calculada con literales
  hexadecimales de Lua (`0xC8/255`, no redondeos a mano) y el hex
  original en un comentario junto a cada una. El bono por descanso
  dentro de un segmento se pinta con el mismo color base aclarado un
  35% hacia el blanco (`Ledger.LightenColor`, en `ui/palette.lua`,
  calculado en código, no como entrada aparte de la tabla). **La misma
  `Ledger.PALETTE` la usa el tooltip** (ver abajo) para las líneas del
  desglose por origen, así que barra y tooltip no pueden
  desincronizarse en el color de cada origen.
- **Tooltip** (`ui/xp_bar.lua`, `frame:SetScript("OnEnter"/"OnLeave", ...)`,
  nuevo — no existía ningún tooltip en el addon antes de esto): al pasar
  el ratón por la barra, muestra el desglose de xp por origen
  (`Ledger.XPBySourceAcrossSessions`, nuevo helper puro en
  `core/events.lua` que suma `XPBySource` de varias sesiones — todas
  las del nivel en curso, igual que la barra, nunca solo la activa) más
  el total de bono por descanso si lo hay.
- **Borde**: 1px negro al 60% (`ui/xp_bar.lua: BORDER_COLOR`) alrededor
  de toda la barra, para separarla visualmente de la barra de xp nativa
  justo debajo — cuatro texturas finas en capa `OVERLAY` (por encima de
  los segmentos, que están en `ARTWORK`), creadas una vez y solo
  reposicionadas cuando cambia el tamaño del frame
  (`AnchorToNativeBar: LayoutBorder()`), nunca recreadas.
- **Color de las texturas, confirmado en el juego**: los colores se
  aplican con la textura blanca clásica de Blizzard
  (`"Interface\Buttons\WHITE8x8"`, `ui/xp_bar.lua: WHITE_TEXTURE`) más
  `texture:SetVertexColor(r, g, b, a)`, **nunca**
  `texture:SetTexture(r, g, b, a)`: pasarle números a `SetTexture` no
  se interpreta como RGB, sino como `SetTexture(fileID, wrapH, wrapV,
  filterMode)` — confirmado en el juego que `SetTexture(1, 0, 1, 1)`
  (que debería salir magenta) salía verde chillón, porque `1` es el ID
  de otra textura cualquiera del juego. Esta fue la causa real de que
  la barra no se viera pese a estar bien anclada y con los segmentos
  calculados correctamente.
- **Render**: pool de pares de texturas reutilizables (`base` +
  `rested`, una encima de la otra en el mismo `ARTWORK` layer) — nunca
  se crean ni se destruyen por evento, solo se muestran/ocultan
  (`GetOrCreatePair`/`ReleaseFrom`). `Ledger.RedrawXPBarFull()`
  (recalcula todo, se usa al cambiar de nivel o al cargar) y
  `Ledger.ExtendXPBar()` (tras cada evento nuevo grabado, en
  `ui/xp_capture.lua: EmitEvent`): como `RoundedWidths` es estable por
  prefijo (añadir un evento al final nunca cambia la anchura ya
  calculada de segmentos anteriores al último), basta con repintar el
  último segmento si se ha extendido o añadir uno nuevo, sin recrear ni
  retocar el resto — ese es el "redibujado incremental".
- **Altura configurable**: `LedgerDB.barHeight` (`Ledger.DEFAULTS.barHeight
  = 8`), sin comando todavía para cambiarla (solo editando la
  SavedVariable a mano).
- `/ldg bar` alterna `LedgerDB.barShown` y muestra/oculta el frame.

**Localización de la barra nativa, confirmada en el juego con
`/fstack`**: la suposición inicial (`MainMenuExpBar`, la barra clásica
de Vanilla) era incorrecta — este cliente usa el sistema de barras de
seguimiento compartido con retail
(`Interface/AddOns/Blizzard_ActionBar/Classic/StatusTrackingBarTemplate.xml`).
La barra de xp vive dentro del contenedor global
`MainStatusTrackingBarContainer` (ese sí es un global real y estable),
pero como un hijo **anónimo**: lo que `/fstack` muestra como
`MainStatusTrackingBarContainer.<hash>` no es una variable global, es
solo cómo esa herramienta representa un frame sin nombre — cambia cada
vez que Blizzard lo crea, así que no se puede referenciar así. Además
el contenedor puede tener más de un hijo a la vez: confirmado en el
juego que con el seguimiento de reputación también activo aparecen dos
hijos con `.StatusBar`. `ui/xp_bar.lua: FindNativeXPBar()` localiza el
correcto en tiempo de ejecución comparando el máximo de cada
`child.StatusBar:GetMinMaxValues()` contra `UnitXPMax("player")` —
confirmado en el juego que solo el de la xp coincide (el de reputación
tenía un máximo normalizado a `1`, no el rango real). A nivel máximo
(`UnitXPMax` es `0`) no hay barra que anclar y no se loguea error;
si hubiera contenedor pero ninguno de sus hijos coincidiera con un
`UnitXPMax` positivo, `AnchorToNativeBar` loguea a ERROR una sola vez.

### Barra de reparto de tiempo (`core/time_bar.lua` + `ui/time_bar.lua`, `/ldg time`)

Paralela a la barra de composición de xp (mismo ancho y posición
horizontal, misma altura, 2px de separación por encima), muestra cómo
se reparte el tiempo del nivel actual entre los 4 buckets de
`core/time_buckets.lua`. **Eje distinto al de la barra de xp**: aquí
siempre ocupa el 100% del ancho (proporcional al tiempo total, no a un
máximo externo) — las dos barras no son comparables píxel a píxel.

- **Orden fijo** (`Ledger.TIME_BUCKET_ORDER = { "active", "travel",
  "idle", "dead" }`): siempre de izquierda a derecha en ese orden, para
  que la forma sea reconocible de un vistazo — nunca reordenado por
  tamaño, a diferencia de la barra de xp (que fusiona por orden de
  llegada).
- **Cálculo puro** (`core/time_bar.lua: Ledger.ComputeTimeBarSegments(buckets,
  widthPx)`): reparte `widthPx` proporcionalmente al peso de cada
  bucket sobre el total, reutilizando `Ledger.RoundedWidths` (expuesta
  desde `core/xp_bar.lua` para esto) — misma técnica de redondeo por
  acumulado que la barra de xp, así que tampoco aquí la suma de
  anchuras supera nunca `widthPx`. Si el total es 0 (nivel recién
  empezado, sin ninguna muestra todavía), no hay segmentos.
- **Fuente de datos: TODAS las sesiones del nivel** (igual que la barra
  de xp, nunca solo la activa): para la sesión en curso se usa
  `Ledger.PreviewBuckets(Ledger.timeTracker, now)` (vista previa en
  vivo, sin mutar nada) en vez de sus `buckets` congelados, para que la
  barra se vea crecer cada segundo; el resto de sesiones usan
  directamente su `session.buckets` ya cerrado.
  `Ledger.timeTracker` — el tracker en vivo de `ui/xp_capture.lua` — se
  expone en `Ledger` precisamente para que este fichero pueda leerlo
  sin acoplarse a variables locales de otro módulo.
- **Colores y borde: la MISMA `Ledger.PALETTE`** que la barra de xp
  (`ui/palette.lua`) — `travel` #4A6FA5 (azul apagado) y `dead` #8B3A3A
  (rojo oscuro apagado) son entradas propias; `active` reutiliza el
  color de `kill` (mismo dorado: es tiempo productivo) e `idle` el de
  `unknown` (mismo gris cálido) — ninguno es una copia del hex, son el
  mismo objeto de color, así que si `kill`/`unknown` cambiaran algún
  día estos les seguirían automáticamente. Mismo borde de 1px negro al
  60% que la barra de xp (`ui/time_bar.lua: LayoutBorder`, código casi
  idéntico al de `ui/xp_bar.lua`).
- **Render**: a diferencia del pool dinámico de la barra de xp, aquí
  hay una textura fija por bucket (siempre son los mismos 4, en el
  mismo orden) — no hace falta un pool. `Ledger.RedrawTimeBar()` se
  llama **desde el mismo ticker de 1s que alimenta los buckets**
  (`ui/xp_capture.lua: TickTimeState`), **nunca desde los eventos de
  xp**: los tramos de viaje/inactividad/muerte no generan ningún
  evento de xp, y la reclasificación retroactiva de `travel` ocurre sin
  ningún evento cerca — atarlo a las kills dejaría la barra congelada
  la mayor parte del tiempo.
- **Tooltip**: `core/time_bar.lua: Ledger.FormatTimeBarTooltip(buckets)`
  (función pura) devuelve una línea por bucket con su tiempo absoluto
  en `hh:mm:ss` (`Ledger.FormatHHMMSS`) y su porcentaje del total;
  `ui/time_bar.lua` colorea cada línea con `Ledger.PALETTE[bucket]` al
  pintarla en el `GameTooltip`.
- `/ldg time` alterna `LedgerDB.timeBarShown` y muestra/oculta el
  frame — **independiente de `/ldg bar`**, cada una se muestra u oculta
  por su cuenta.

### Panel de depuración y volcado de estado (`core/state_dump.lua`)

`Ledger.FormatState(charDB)` es el serializador puro que comparten
`/ldg debug` (panel) y `/ldg dump` (chat): cabecera de la sesión activa
(nivel, modo, manual, xp total y xp de descanso —
`Ledger.TotalRested`—) + hasta 30 eventos (los más recientes primero,
formateados `mm:ss.t | xp | src | descanso=N` con `Ledger.FormatOffset`,
que no asume ningún límite superior de minutos) + resumen de
`levels` ordenado por nivel (incluye `totalRested` de cada uno). Lee
`charDB.sessions`/`charDB.levels`
(la forma de `LedgerCharDB`) que se le pasa como parámetro — nunca
`LedgerCharDB` directamente ni ninguna API de WoW — e itera
`Ledger.SERIES.xp` en vez de asumir stride o nombres de campo, por la
regla dura de `core/series.lua`. `ui/debug_frame.lua` es la capa fina
que pinta ese texto en un frame movible/redimensionable con un EditBox
multilínea de solo lectura (seleccionable, para copiar), botón de
refresco manual y checkbox de autorefresco cada 2s (`C_Timer.NewTicker`).
El mismo panel también muestra el buffer de log (ver abajo) cuando se
abre con `/ldg log show`.

**Pendiente de verificar en el juego**: el panel usa `SetResizable`,
`StartSizing`/`StopMovingOrSizing`, `SetResizeBounds` (con fallback a
`SetMinResize` si no existe) y las texturas
`Interface\ChatFrame\UI-ChatIM-SizeGrabber-*`; son API estables desde
hace mucho pero no se han probado todavía dentro del cliente 1.15.x.
Comprobar con `/reload` tras cargar el addon.

### Sistema de log (`core/log.lua`)

Estado en memoria (no persistido, igual que el tracker de buckets y el
matcher — ver "Pendiente" más abajo), creado en `ui/events.lua` como
`Ledger.logState = Ledger.NewLogState()`:

```lua
state = {
    level  = "off",  -- "off" | "error" | "info" | "trace"
    chat   = false,  -- eco al chat activado/desactivado
    buffer = {},     -- anillo de hasta Ledger.LOG_BUFFER_CAPACITY (200)
                      -- entradas { t, level, msg }, más antigua primero
}
```

`Ledger.LogMessage(state, level, msg, t)` descarta el mensaje si su
nivel es más verboso que `state.level` (orden `off < error < info <
trace`); si no, lo añade al buffer (recortando por el principio si se
pasa de capacidad) y devuelve `true` cuando además hay que ecoarlo al
chat (`state.chat` activo). El tiempo se recibe como parámetro, como en
el resto de `core/`.

**Puntos de emisión conectados** (`ui/xp_capture.lua`, todos a nivel
TRACE vía `Ledger.Log(level, msg)`, el envoltorio de `ui/events.lua`
que añade `GetTime()` y hace de eco a chat si `/ldg log chat` está
activo):
- `PLAYER_XP_UPDATE`: xp anterior, xp actual, delta.
- `CHAT_MSG_COMBAT_XP_GAIN`: el mensaje sin procesar entre `<<...>>`, y
  además por cada variante `COMBATLOG_XPGAIN_*` conocida: si su patrón
  casó o no, los valores capturados si casó, y la categoría final
  (`"kill"`/`"explore"`) resultante.
- `QUEST_TURNED_IN`: sus argumentos tal cual (evento nuevo, antes no
  registrado; solo se loguea, no se usa todavía para nada más).
- `core/xp_gain_matcher.lua` (`AddAmount`/`AddSource`/`Flush`): reciben
  un `log` opcional (`function(level, msg)`, no-op si se omite — por
  eso `spec/xp_gain_matcher_spec.lua` sigue en verde sin tocarlo) y
  describen con él el contenido de sus colas (`amounts`/`sources`, con
  antigüedad) y por qué cada etiqueta se consume, se descarta o se
  encola, incluida la separación real de cada emparejamiento exitoso
  (para poder recalibrar `Ledger.MAX_MATCH_GAP` con datos reales).

`/ldg strings` (`core/chat_patterns.lua: Ledger.FormatXPGainStrings`)
imprime cada global string `COMBATLOG_XPGAIN_*` en uso con su valor
literal en este cliente y el patrón Lua derivado, para verificar a ojo
la conversión.

**Diagnosticado y corregido (2026-09-16)**: el bug de `src` siempre
`"unknown"` tenía dos causas, encontradas con la instrumentación de
arriba:
1. `Ledger.BuildPattern` anclaba el final del patrón con `$`; el
   mensaje real de un kill con bono por descanso continúa después de
   "experience." (`"... you gain 172 experience. (+86 exp Rested
   bonus)"`), así que ningún patrón casaba nunca que ese sufijo
   estuviera presente. Se quitó el `$`: un `%d+` ya para de capturar en
   el primer carácter no numérico, así que la captura sigue siendo
   exacta sin necesidad de anclar el final.
2. La clasificación era todo-o-nada: si ningún patrón casaba, no se
   llamaba a `Ledger.AddSource` en absoluto, así que la cantidad
   correspondiente siempre acababa huérfana y se soltaba como
   `"unknown"` al cabo de `Ledger.MAX_MATCH_GAP`. Ahora
   `Ledger.ClassifyXPGainMatch` siempre devuelve una categoría
   (`"kill"` o `"explore"`, nunca `nil`) y `AddSource` se llama
   siempre que llega el evento.

### SavedVariables

- `LedgerDB` (cuenta, `## SavedVariables`): `pos`, `shown`, `version`,
  `includeRested` (toggle de `/ldg rested`, `true` por defecto),
  `barShown`/`barHeight`/`timeBarShown` (barras). `version` está en 4
  (`Ledger.DB_VERSION`); `core/xp.lua: MigrateDB(db)` sube cualquier
  `db` por debajo de la versión actual:
  - v1→v2: solo estampa el número de versión (esquema previo a las
    series declarativas; no había sesiones/niveles persistidos bajo el
    esquema viejo que traducir).
  - v2→v3: reescribe el array plano `e` de cada sesión de
    `db.sessions` (si las hay: `LedgerDB` no tiene `sessions` y este
    paso no hace nada en ese caso) del stride viejo (3: `off, xp, src`)
    al nuevo (4: añade `rested = 0` a todo lo existente, porque no hay
    forma de saber retroactivamente cuánto de esa xp ya grabada era
    bono por descanso). Usa los mismos helpers genéricos de
    `core/series.lua` (`RecordCount`/`ReadRecord`/`AppendRecord`) para
    leer con el esquema viejo (congelado como `XP_SERIES_V2`, solo para
    esta migración) y escribir con `Ledger.SERIES.xp` vigente — es
    exactamente la prueba de que el modelo de series declarativas
    funciona de verdad sin tocar nada a pelo fuera de esos helpers.
  - v3→v4: rellena `session.buckets` a cero (`Ledger.NewEmptyBuckets()`)
    en cualquier sesión que no lo trajera — igual que `rested = 0` en la
    v2→v3, no hay forma de reconstruir retroactivamente cómo se repartió
    el tiempo ya jugado bajo el esquema viejo (el tracker de buckets
    vivía solo en memoria hasta esta versión, nunca se persistía).
- `LedgerCharDB` (por personaje, `## SavedVariablesPerCharacter`):
  `{ version, levels, sessions }`. Se inicializa en `ADDON_LOADED` con
  `LedgerCharDB = Ledger.InitCharDB(LedgerCharDB)` (`core/xp.lua`), que
  reutiliza `InitDB`/`MigrateDB` con `Ledger.CHAR_DEFAULTS = { levels =
  {}, sessions = {} }` — nunca pisa lo que ya hubiera, solo rellena lo
  que falte y migra la versión. `sessions` es la lista de sesiones del
  nivel en curso (ver arriba); `levels[nivel]` guarda el resultado de
  `CloseLevel` una vez que el cierre de nivel esté cableado (todavía no
  lo está — ver "Pendiente").
  - **Historial de este bug**: primero se declaró en el `.toc` sin
    ningún código que la tocara (quedaba en `nil`). Se corrigió con
    `LedgerCharDB = LedgerCharDB or {}`, pero eso solo crea el
    contenedor: sin `levels`/`sessions` garantizados, cualquier intento
    de escritura futura indexando esas claves habría fallado igual.
    `InitCharDB` es el arreglo definitivo: garantiza la estructura
    completa de una vez, de forma pura y testeada.
  - Toda escritura a esta base de datos pasa por helpers que garantizan
    la estructura antes de indexar: `Ledger.InitCharDB` (estructura
    completa), `Ledger.AppendRecord`/`Ledger.AddEvent` (crean el array
    de la serie si falta), `Ledger.RecordLevelClose(db, entry)` (crea
    `db.levels` si falta antes de escribir `db.levels[entry.nivel]`).
    Ningún sitio debe hacer `db.levels[x] = y` ni `db.sessions[#x+1]=y`
    a pelo sin pasar antes por uno de estos.
  - No hay ningún `pcall`/`xpcall` en el addon que trague errores de
    handlers en silencio (revisado explícitamente); si se añade uno en
    el futuro, debe loguear siempre con `geterrorhandler()(msg)` o
    equivalente, nunca descartar el error sin más.

### Diagnóstico de carga

Cada fichero de `core/` hace un `print("Ledger: core/<fichero>.lua")`
incondicional nada más cargar (antes de definir nada), para que en el
chat del juego se vea exactamente qué ficheros de `core/` han llegado a
ejecutarse y en qué orden. Si falta uno en el chat al hacer `/reload`,
ese es el que se ha cortado (error de sintaxis/runtime silencioso, o
falta en el `.toc`).

### Pendiente de definir (se irá completando en próximas sesiones)

- `tEnd` solo se rellena hoy al cerrar por `/ldg reset`; qué pasa con la
  sesión activa al hacer logout/desconexión sin pasar por reset sigue
  sin decidir. Como `sessions` ya es la SavedVariable real, una sesión
  sin `tEnd` sobrevive tal cual al próximo login y se le sigue añadiendo
  eventos.
- Confirmar en el juego (con la instrumentación TRACE) que la corrección
  del bug `src = "unknown"` (ver "Sistema de log" arriba) funciona con
  el resto de variantes reales de este cliente, no solo con el caso del
  bono por descanso ya reproducido en tests.
- Nada lee todavía `Ledger.ReconciliationGap(reconciler)` para avisar en
  caliente si se dispara — hoy solo existe el contador en memoria
  (`ui/xp_capture.lua`). Falta decidir dónde mostrarlo: ¿un aviso
  automático si el hueco no se cierra tras un tiempo, una línea más en
  `/ldg dump`/el panel de depuración, o ambos?
- Confirmar en el juego que `UnitXPMax("player")` en el instante de
  `PLAYER_ENTERING_WORLD` es siempre el del nivel correcto (para el
  cacheo inicial de `previousMaxXP` en `ui/xp_capture.lua`) y que un
  salto de más de un nivel de golpe (`ComputeXPDelta` con
  `levelsGained > 1`) realmente puede ocurrir con `PLAYER_XP_UPDATE`
  disparándose una sola vez por el salto entero, no una vez por nivel.
- Verificar en el juego que el cierre de nivel diferido (ver "Cierre de
  nivel" más abajo) funciona con una subida real: que `/ldg dump`
  muestre la entrada de `levels` tras un ding, y que la barra de
  composición de xp arranque limpia en el nivel nuevo en vez de seguir
  pintando junto lo del nivel anterior.
- El caso de doble `PLAYER_LEVEL_UP` sin procesar el primero (dos dings
  muy seguidos) fuerza el cierre del primero con el nivel que tenía
  capturado, pero no está pensado a fondo ni testeado con un caso real:
  revisar si hace falta algo más fino si llega a darse.
- Ver visualmente en el juego el resultado final de la barra de
  composición de xp ya con color de verdad (localización del frame y
  pintado con `WHITE8x8`/`SetVertexColor` confirmados en el juego, pero
  todavía no se ha visto la barra real con segmentos de colores, solo
  la prueba de un rectángulo suelto): anclaje pixel a pixel, contraste
  de la nueva paleta (dorado/verde azulado/violeta/gris) sobre la UI
  real, el tono más claro del segmento de bono por descanso, el borde
  de 1px, y el tooltip (nunca probado: `GameTooltip:SetOwner`/`AddLine`
  con `OnEnter`/`OnLeave` sobre un frame sin `BackdropTemplate` debería
  funcionar igual, pero no se ha confirmado en este cliente).
- `sessions[1].initialXP` se queda viviendo en la sesión, no en
  `levels[nivel]`: ahora que `CloseLevel` sí se llama (en el cierre de
  nivel diferido), se ha confirmado que no hace falta trasladarlo — el
  segmento gris solo lo usa la barra del nivel EN CURSO, nunca una
  entrada de `levels` ya cerrada.
- Verificar en el juego toda la alimentación real de los buckets de
  tiempo (recién cableada, nunca probada con datos de verdad): que
  `PLAYER_REGEN_DISABLED` y las ganancias de xp marquen `"active"`
  correctamente, que el ticker de 1s transicione a `"travel"` pasados
  los 30s (`Ledger.INACTIVITY_THRESHOLD`) sin ninguna de esas dos
  señales, que se vea reflejado en la barra de reparto de tiempo sin
  repartirse con `"idle"`, que `PLAYER_DEAD`/`PLAYER_UNGHOST` acumulen
  `"dead"` bien, y que el cierre de nivel sume los buckets de
  todas las sesiones correctamente en `levels[nivel].buckets`.
- Ver visualmente en el juego la barra de reparto de tiempo (nunca
  probada): anclaje 2px por encima de la barra de xp, el orden fijo
  active/travel/idle/dead, los colores (incluidos los que reutilizan
  `kill`/`unknown`), el borde, y su tooltip.
