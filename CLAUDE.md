# Ledger

Addon de la línea de producto Classic (Lua 5.1). Se llamaba XPTrack;
renombrado a Ledger — si ves "XPTrack" en algún sitio (código, symlink de
Interface/AddOns, apuntes viejos) es residuo del nombre anterior.

**Multi-cliente desde 2026-09-17**: un solo paquete (`## Interface:
11509, 16001` en `Ledger.toc`, nunca TOCs separados por flavor) sirve
tanto a Classic Era (cliente 1.15.x, interface 11509) como a la beta de
WoW Forever (build 1.60.1, interface 16001, también línea Classic). No
se asume que ninguna API se comporte igual en ambos: `/ldg probe` (ver
más abajo) existe precisamente para comprobarlo en el cliente real en
vez de suponer.

## Restricciones
- Lua 5.1. Sin goto, sin operadores bitwise nativos, sin // .
- API de la línea de producto Classic únicamente. NADA de retail
  moderno. Con dos clientes en el mismo paquete (ver arriba), esto
  aplica a los dos: nada que solo exista en uno de ellos sin comprobar
  antes con `/ldg probe` que el otro también lo tiene.
- Sin librerías externas. Nada de Ace3.
- Si no sabes si una API existe en un cliente dado, pregunta o
  compruébalo con `/ldg probe` en vez de asumir.

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
  - `/ldg export`: muestra u oculta el panel de exportación
    (`ui/export_frame.lua`), con el volcado completo de `LedgerCharDB`
    en JSON o CSV (ver "Exportación de datos" más abajo).
  - `/ldg probe`: imprime al chat un diagnóstico de compatibilidad del
    cliente actual — versión de build/interface, presencia y valor de
    un puñado de APIs, cuántos global strings `COMBATLOG_XPGAIN_*`
    encuentra y si existe `C_ChatInfo` (ver "Diagnóstico de
    compatibilidad" más abajo). Nunca aborta por una API ausente.
- Despliegue: `./deploy.sh [flavor]` (raíz del repo, ejecutable desde
  WSL) copia `Ledger/` (la carpeta del addon, nunca `spec/` ni
  ficheros de desarrollo) a `Interface/AddOns/Ledger` dentro de la
  instalación de WoW, borrando el destino antes de copiar para que los
  ficheros eliminados del repo no queden zombis. `flavor` es
  `classic_era` (por defecto) o `forever`; cada uno resuelve a su
  propia subcarpeta bajo la raíz de la instalación (`_classic_era_` /
  `_classic_beta_` — este último es el nombre real de la carpeta de la
  beta de WoW Forever en esta máquina, confirmado, no adivinado).
  `LEDGER_WOW_PATH` apunta a esa **raíz** de la instalación de WoW (la
  carpeta que contiene `_classic_era_`, `_classic_beta_`, etc.), nunca
  a una ruta completa hasta `Interface/AddOns` — es el flavor quien
  decide ese último tramo. La ruta no está hardcodeada a esta máquina
  (el repo es público): tiene un valor por defecto que asume la ruta
  estándar de Battle.net en Windows, y se puede sobrescribir
  exportando `LEDGER_WOW_PATH` si la instalación vive en otro sitio.
  Aborta con un error claro si esa ruta no existe, o si `flavor` no es
  uno de los conocidos. Al terminar imprime la versión del .toc
  desplegada y la hora. **Hay que ejecutarlo (con el flavor que toque)
  tras cualquier cambio en los ficheros del addon** (antes recreaba a
  mano un symlink desde
  Interface/AddOns; ya no hace falta, el script sustituye ese paso
  manual). Hecho eso, basta con /reload dentro del juego.

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
    -- recorta rested si llegara mayor que xp). off se persiste como
    -- entero (décimas de segundo, redondeado con math.floor(x+0.5) al
    -- grabar); src se persiste como ID numérico (Ledger.SRC_IDS/
    -- Ledger.SRC_NAMES, ambos en core/series.lua), nunca como texto.
    -- futuras: gold (stride 3), rep (stride 4, con campo faction),
    --          loot (stride 3). Añadir una serie es una entrada aquí y
    --          nada más.
}
```

**`src` como enum numérico** (`Ledger.SRC_NAMES`/`Ledger.SRC_IDS`,
`core/series.lua`): `kill=1`, `quest=2`, `explore=3`, `unknown=4`,
`previous=5` (este último nunca se persiste de verdad: es
`Ledger.BAR_INITIAL_SRC`, el segmento sintético de xp previa al
registro). La traducción string↔id vive solo en la frontera de
persistencia — `core/events.lua: AddEvent` (string→id al escribir) y
`XPBySource` (id→string al leer); `core/xp_bar.lua: MergeConsecutive`
(id→string); `core/state_dump.lua: FormatSession` (id→string) — todo lo
demás (matcher, `chat_patterns`, paleta, `ui/xp_capture.lua`) sigue
trabajando siempre con el nombre de texto. Migrado desde texto en
v4→v5 (ver SavedVariables más abajo).

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

Creada con `core/events.lua: NewSession(t0, level, mode, manual)`:

```lua
session = {
    t0      = <time() ABSOLUTO de inicio, no GetTime(): sobrevive a un
               reinicio del cliente. GetTime() solo se usa para calcular
               offsets DENTRO de la sesión en curso (sessionStartRef,
               local a ui/xp_capture.lua, nunca persistido) — ver
               "Captura de eventos" más abajo>,
    tEnd    = <time() ABSOLUTO de cierre, o nil mientras está activa>,
    level   = <nivel del jugador al iniciar la sesión>,
    reached = <time() ABSOLUTO del instante en que se empezó a rastrear
               este nivel: el ding real si lo disparó una subida de
               nivel, o el instante de arranque si es la primera sesión
               en frío (mismo tipo de aproximación que initialXP: no se
               puede saber el ding real de antes de instalar el addon)>,
    mode    = <"farm" | "quest" | "dungeon" | nil>,  -- informativo; NUNCA
                                                       -- sobrescribe ni
                                                       -- altera el src de
                                                       -- ningún evento
    manual  = <true si se abrió con /ldg reset, false en las demás>,
    deaths  = 0,  -- contador de muertes DE ESTA SESIÓN (PLAYER_DEAD),
                   -- aparte del bucket de tiempo "dead": cuánto tiempo
                   -- se estuvo muerto no dice cuántas veces.
    buckets = { active = 0, idle = 0, travel = 0, dead = 0 },  -- ver
                -- "Buckets de tiempo" abajo; el tracker en vivo
                -- (ui/xp_capture.lua) reengancha aquí su tabla de
                -- buckets, así que sobrevive a /reload como el resto.
    e = {
        -- array plano de la serie xp (ver Ledger.SERIES.xp arriba):
        -- off, xp, src, rested, off, xp, src, rested, ...
        -- off en décimas de segundo desde el inicio de la sesión, YA
        -- REDONDEADO a entero (quien llama: ui/xp_capture.lua). src es
        -- el ID numérico del origen (Ledger.SRC_IDS: kill/quest/
        -- explore/unknown). rested es la parte de xp que vino del bono
        -- por descanso (0 si no hubo).
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
  `StartTracking`/`ResetSession`/`CloseCurrentLevel`, así que
  cualquier `AddSample` escribe directamente en la SavedVariable. Esto
  es un cambio deliberado respecto a lo documentado antes ("mismo
  tracker de tiempo" para las sesiones manuales): ahora cada sesión
  lleva su propio reparto de tiempo — `lastState`/`threshold` siguen
  siendo continuos (mismo objeto `tracker`, solo se le cambia la tabla
  `buckets`), pero los totales acumulados sí arrancan a cero por
  sesión, y `CloseLevel` los suma entre todas las del nivel (ver
  abajo).
- **`buckets` es una métrica de reparto, NO de duración total**:
  `entry.totalPlayed` (ver "Entrada de `levels`" arriba) ya NO sale de
  sumar `active+idle+travel+dead` — sale de `TIME_PLAYED_MSG` del
  personaje (ver "Cierre de nivel" y SavedVariables más abajo).
  `entry.buckets` sigue existiendo tal cual, como el desglose de CÓMO se
  repartió ese tiempo, no de cuánto es en total.

### Entrada de `levels` (`core/level_close.lua: CloseLevel(sessions, totalPlayed, includeRested)`)

```lua
levels[level] = {
    level       = <nivel>,
    reached     = <time() absoluto del ding que llevó a este nivel; 0 si
                   viene de datos de antes de esta migración (no
                   reconstruible retroactivamente) — ver sessions[1].reached>,
    totalXP     = <suma de la xp EFECTIVA de todas las sesiones del
                   nivel, xp o xp-rested segun includeRested (true por
                   defecto); ver Ledger.EffectiveXP arriba>,
    totalRested = <suma del bono por descanso real, SIN toggle: no
                   cambia con includeRested>,
    totalPlayed = <segundos jugados en el nivel, según TIME_PLAYED_MSG
                   del personaje (NO la suma de buckets, que es una
                   métrica aparte — ver "Buckets de tiempo" y "Cierre de
                   nivel" más abajo); se pasa ya calculado, CloseLevel NO
                   lo calcula>,
    deaths      = <suma de session.deaths de todas las sesiones del nivel>,
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
por cada cierre de nivel (ver "Cruce de nivel: partido en dos entradas"
más abajo — es exactamente lo que hace `ui/xp_capture.lua` ahora).

`levels[level]` **está indexado por el número real de nivel**
(`Ledger.RecordLevelClose(db, entry)`: `db.levels[entry.level] = entry`),
nunca por orden de inserción: si el addon se instala a mitad de partida
(nivel 20), `levels[20]` es el nivel 20 desde el primer cierre, no
`levels[1]`.

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
    + xpActual`. Además expone `crossing = { oldPart = maxAnteriorCacheado
    - xpAnterior, newPart = xpActual, oldLevel=, newLevel= }` — `oldPart +
    newPart == delta` siempre — para que quien grabe el evento pueda
    partirlo en dos entradas en vez de metérselo entero a un solo nivel
    (ver "Cruce de nivel" más abajo).
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

### Cierre de nivel (`ui/xp_capture.lua`: `EmitCrossingEvent` + `CloseCurrentLevel`)

**`PLAYER_LEVEL_UP` no dispara nada del cierre.** Es solo diagnóstico
(loguea a TRACE el nivel que reporta el propio evento, `UnitLevel` en
ese instante y `previousLevel` cacheado) y refresco del panel
(`Ledger.UpdateXP()`). El cierre de nivel real lo dispara siempre **el
propio evento de xp que cruza el ding**, en cuanto se empareja con su
fuente — `Ledger.ComputeXPDelta` ya detecta el cruce comparando
`UnitLevel()` antes/después en cada `PLAYER_XP_UPDATE` (ver arriba), sin
depender en absoluto de en qué orden llegue `PLAYER_LEVEL_UP` respecto a
los demás eventos. Esto sustituye por completo el mecanismo anterior de
"subida pendiente + temporizador de respaldo" (`pendingLevelUp`,
`Ledger.PENDING_LEVEL_UP_TIMEOUT`): ya no existen, ni falta el caso
límite de doble `PLAYER_LEVEL_UP` que intentaban cubrir.

**Cruce de nivel: partido en dos entradas, nunca contado entero en un
solo nivel** (Análisis del SavedVariables real, 2026-09-17: se detectó
que el nivel viejo terminaba por encima de su tope y el nuevo arrancaba
con un "unknown" huérfano — el evento de cruce se estaba contando
completo en un sitio y su sobrante otra vez en el otro). Cuando
`ComputeXPDelta` marca `levelsGained = 1`, el `crossing` que expone
(`oldPart`/`newPart`, que suman exactamente `delta`) viaja pegado a la
cantidad **a través del matcher** (`core/xp_gain_matcher.lua:
AddAmount/AddSource/Flush` propagan el campo `crossing` igual que ya
hacían con `rested`/`expectedXP`) hasta que se empareja con su fuente
real — así, tanto si la fuente llega antes, después o nunca (huérfana,
`src = "unknown"` tras el margen), **el `src` real se resuelve para el
evento COMPLETO antes de partirlo**: partirlo antes habría dejado a una
de las dos mitades sin fuente que emparejar, y esa mitad se habría
soltado como `"unknown"` aunque la otra sí tuviera un origen real (el
bug reportado).

Una vez emparejado, `ui/xp_capture.lua: EmitEvent` ve `paired.crossing`
y llama a `EmitCrossingEvent(paired)`, que:

1. Calcula el reparto con `Ledger.SplitCrossingEvent(paired)`
   (`core/xp_delta.lua`, lógica pura, testeada en
   `spec/xp_delta_spec.lua`): `old = {xp=oldPart, rested=}`, `new =
   {xp=newPart, rested=}`. `rested` se reparte proporcional a cada parte
   (`restedOld = floor(rested * oldPart/xp + 0.5)`, recortado a
   `oldPart` si el redondeo o un desajuste entre señales lo pasara);
   `restedNew` es siempre `rested - restedOld`, nunca se calcula por
   separado — así las dos partes suman exactamente `xp` y `rested` del
   evento original, sin excepción.
2. Graba `old` (con el `src` real del evento, nunca "unknown" salvo que
   el original también lo fuera) en la sesión todavía sin rotar —
   **esta es la entrada que completa el nivel viejo exactamente a su
   tope**, ni un punto más.
3. Llama a `CloseCurrentLevel(t)`: cierra el tramo de tiempo pendiente,
   calcula `totalPlayed` (ver "Buckets de tiempo"/SavedVariables — ya
   NO es la suma de buckets), `Ledger.CloseLevel` +
   `Ledger.RecordLevelClose`, y abre la sesión del nivel nuevo
   (`reached = time()`, snapshot de `levelStartTotalPlayed`,
   `RequestTimePlayed()` para refrescar el total cuanto antes),
   reiniciando `timeTracker`/`matcher`/`reconciler`.
4. Graba `new` (mismo `src`) en la sesión recién rotada, en offset 0.

Como ya no hace falta "adivinar" si hay un evento en camino que vaya a
explicar la xp del nivel nuevo (siempre lo hay: es la propia entrada
`new` de arriba), la sesión nueva **nunca** snapshotea `initialXP` en
este camino — solo lo hace el arranque en frío de verdad
(`StartTracking` cuando `#sessions == 0`, ver "Barra de composición de
xp").

Diagnóstico: `CloseCurrentLevel` loguea a TRACE el nivel cerrado,
sesiones agregadas, `totalXP`, `totalPlayed` y `muertes`.

**Caso límite conocido, no nuevo de este cambio**: si una segunda
ganancia de xp real ocurre mientras la del cruce todavía espera a su
fuente (dentro del margen de `Ledger.MAX_MATCH_GAP`), y esa segunda
cantidad sigue sin fuente en el momento exacto en que el cruce se
resuelve y rota el matcher (`matcher = Ledger.NewMatcher()`), esa
segunda cantidad se pierde sin más — el matcher viejo, con ella
pendiente dentro, se descarta entero. Ya existía en el mecanismo
anterior (la rotación al cerrar siempre ha reemplazado el matcher
entero); ventana real de menos de `Ledger.MAX_MATCH_GAP` (1s). Sin
arreglar — ver "Pendiente".

### Reset manual (`/ldg reset` → `Ledger.ResetSession(t)`)

Cierra la sesión activa (`session.tEnd = t`) y abre una nueva con
`manual = true`, del mismo nivel. **Cierra, nunca borra**: la sesión
cerrada se queda en la lista `sessions` hasta el cierre de nivel, porque
`CloseLevel` agrega TODAS las sesiones del nivel, no solo la última.
Una sesión manual se comporta igual que cualquier otra en todo lo demás
(mismas series, mismo tracker de tiempo).

### `totalPlayed` de un nivel: tiempo jugado del PERSONAJE, no suma de buckets

`entry.totalPlayed` sale de restar dos totales de tiempo jugado DEL
PERSONAJE (`TIME_PLAYED_MSG`, arg1 — el que reporta el propio servidor,
siempre exacto), nunca de sumar los buckets de actividad: **autocorrige
sesiones perdidas** (un login saltado, un crash) porque el total del
personaje no depende de que este addon haya visto todo lo que ha
pasado, a diferencia de los buckets, que solo cuentan lo que el tracker
en memoria ha ido muestreando.

- `LedgerCharDB.lastKnownTotalTimePlayed`: el último `arg1` recibido de
  `TIME_PLAYED_MSG` — se actualiza siempre que llega, sin condición.
- `LedgerCharDB.levelStartTotalPlayed`: ese mismo total en el instante
  en que se empezó a rastrear el nivel EN CURSO (snapshot en
  `StartTracking` para el arranque en frío, y en `CloseCurrentLevel`
  para cada cierre).
- `entry.totalPlayed = lastKnownTotalTimePlayed - levelStartTotalPlayed`
  (recortado a 0 si saliera negativo, salvaguarda defensiva).
- `RequestTimePlayed()` se llama en `PLAYER_ENTERING_WORLD` (ya estaba)
  y ahora también en `CloseCurrentLevel`, justo después de snapshotear
  `levelStartTotalPlayed`: la respuesta (asíncrona, vía `TIME_PLAYED_MSG`)
  no llega a tiempo para el cierre que la disparó, pero sí refina
  `lastKnownTotalTimePlayed` para el PRÓXIMO cierre — de ahí que sea
  "autocorregible" en vez de exacto al instante.

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

**Localización de la barra nativa, multi-cliente** (`ui/xp_bar.lua:
FindNativeXPBar`, reescrito 2026-09-17 para el porte a WoW Forever —
ver "Multi-cliente" al principio de este documento): resuelve en
tiempo de ejecución, probando en orden y quedándose con el primero que
exista, dos candidatos — `MainStatusTrackingBarContainer`,
`MainMenuExpBar` — **nunca** el hijo de nombre generado en runtime
(p.ej. `MainStatusTrackingBarContainer.1b57a533670`, que cambia entre
sesiones: lo que `/fstack` muestra así no es una variable global, es
solo cómo esa herramienta representa un frame sin nombre).

- **`MainStatusTrackingBarContainer`** (confirmado en el juego con
  `/fstack` tanto en Classic Era 1.15.x como en la beta de WoW Forever
  — la suposición inicial de que Classic Era usaba `MainMenuExpBar`,
  la barra clásica de Vanilla, era incorrecta): sistema de barras de
  seguimiento compartido con retail
  (`Interface/AddOns/Blizzard_ActionBar/Classic/StatusTrackingBarTemplate.xml`).
  Dentro de él, `Ledger.FindMatchingChild(container)` busca el hijo
  cuyo `child.StatusBar:GetMinMaxValues()` coincide con
  `UnitXPMax("player")` — necesario en Classic Era porque el
  contenedor puede tener más de un hijo a la vez (confirmado en el
  juego que con el seguimiento de reputación también activo aparecen
  dos hijos con `.StatusBar`; el de reputación tiene un máximo
  normalizado a `1`, no el rango real, así que comparar por
  `UnitXPMax` los distingue). Si hay hijo que coincide, se usa ESE
  como ancla (su anchura/posición, no las del contenedor) — el
  comportamiento de Classic Era no cambia respecto a antes del porte.
  Si NO hay ningún hijo que coincida (WoW Forever: su contenedor no
  tiene esa estructura de hijos, sus hijos se anclan TOPLEFT/BOTTOMRIGHT
  sin offset), se usa el **contenedor mismo** como ancla directamente
  — sirve porque su geometría ya es la de la barra.
- **`MainMenuExpBar`**: fallback defensivo si el contenedor de arriba
  no existe en absoluto. Nunca alcanzado en ninguno de los dos
  clientes confirmados hasta ahora (los dos tienen
  `MainStatusTrackingBarContainer`); existe por si un cliente futuro
  (o uno más antiguo) careciera de ambas formas del contenedor.
- **Degradación si no existe ningún candidato** (`ui/xp_bar.lua:
  DegradedAnchor`): en vez de no dibujar nada, la barra se coloca en
  una posición por defecto (`LedgerDB.barDefaultPos`, `Ledger.DEFAULTS
  .barDefaultPos` si no hay guardada) con una anchura fija
  (`Ledger.DEFAULTS.barDefaultWidth = 200`) y se vuelve arrastrable
  (`frame:RegisterForDrag`, guardando la nueva posición en
  `LedgerDB.barDefaultPos` al soltar) — nunca cuando está anclada de
  verdad: en ese caso arrastrar no serviría de nada, la próxima
  redibujada la volvería a pegar al ancla nativa, así que un flag local
  (`inDegradedMode`, no `EnableMouse`: el ratón se queda siempre
  activo, lo necesita el tooltip pase lo que pase) decide si
  `OnDragStart` hace algo o no. Se avisa una única vez por sesión a
  nivel INFO (`Ledger.Log("info", ...)`, nunca ERROR: es un modo
  soportado, no una rotura) la primera vez que se degrada.
- **Nunca constantes**: tanto en modo nativo como degradado, la
  anchura y posición salen siempre del frame resuelto
  (`nativeBar:GetWidth()`) o de la SavedVariable/default degradados —
  ninguna constante de anchura hardcodeada salvo
  `Ledger.DEFAULTS.barDefaultWidth`, que es explícitamente el valor de
  emergencia, no el camino normal.
- **Reancla en `PLAYER_ENTERING_WORLD` y `UI_SCALE_CHANGED`**
  (`ui/events.lua`): ambos disparan `Ledger.RedrawXPBarFull()` +
  `Ledger.RedrawTimeBar()`, que vuelven a resolver el ancla desde cero
  cada vez (nunca cacheada) — cubre tanto que
  `Blizzard_StatusTrackingBar` cargue tarde (no estaba disponible en
  el primer `PLAYER_LOGIN` pero sí en una pantalla de carga posterior)
  como que la interfaz se recoloque al cambiar la escala de UI.
- **`Ledger.xpBarAnchorInfo`**: cada `AnchorToNativeBar` deja aquí
  `{ source=, width=, height= }` (`source` describe qué se resolvió:
  `"MainStatusTrackingBarContainer (matched child)"`,
  `"MainStatusTrackingBarContainer (container)"`, `"MainMenuExpBar"` o
  `"degraded (no anchor found)"`) — lo lee `/ldg probe` (ver
  "Diagnóstico de compatibilidad" abajo) para poder ver de un vistazo,
  en cualquier cliente, qué ancla se resolvió de verdad.

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
formateados `mm:ss.t | xp | src | descanso=N` con `Ledger.FormatOffset`
(`src` ya traducido de vuelta a texto vía `Ledger.SRC_NAMES`, nunca el
ID numérico crudo), que no asume ningún límite superior de minutos) +
resumen de `levels` ordenado por nivel (incluye `totalRested` y
`deaths` de cada uno). Lee
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

### Exportación de datos (`core/export.lua` + `ui/export_frame.lua`, `/ldg export`)

Vuelca `LedgerCharDB` completo (todas las sesiones del nivel en curso
y todos los niveles ya cerrados, no solo la sesión activa como
`state_dump.lua`) a JSON o CSV, para copiar y analizar fuera del
juego.

- **Modelo intermedio compartido** (`Ledger.BuildExportModel(charDB)`,
  lógica pura): decodifica la forma cruda de `LedgerCharDB` (`src`
  como ID numérico, arrays planos de la serie xp, `levels` indexado
  por número) a tablas Lua planas que usan tanto `ExportJSON` como
  `ExportCSV`, para que ninguno de los dos formatos tenga que
  reimplementar la traducción de `src` (`Ledger.SRC_NAMES`) ni los
  totales (`Ledger.TotalXP`/`TotalRested`/`XPBySource`) por su cuenta.
  Itera `Ledger.SERIES.xp` igual que `state_dump.lua`, por la misma
  regla dura de `core/series.lua`.
- **JSON escrito a mano**: no hay ninguna librería JSON disponible en
  el sandbox del addon y no se pueden añadir dependencias externas
  (ver "Restricciones" arriba), así que el encoder no es genérico —
  no intenta adivinar si una tabla vacía es un array o un objeto en
  ningún sitio — sino un puñado de primitivas de bajo nivel
  (`Ledger.JSONString`/`JSONNumber`/`JSONEscapeString`) que cada punto
  de la serialización combina ya sabiendo qué forma está construyendo.
  `Ledger.JSONEscapeString` escapa barra invertida, comillas dobles y
  todo carácter de control (`0x00`-`0x1F`) como `\uXXXX`.
  `Ledger.JSONNumber` usa `string.format("%.14g", n)` para evitar tanto
  notación científica como el ruido de un `.0` final en los enteros.
  Los tests (`spec/export_spec.lua`) validan el JSON de verdad
  decodificándolo con `dkjson` — una dependencia **solo de test**
  (instalada vía luarocks en el entorno de `busted`), nunca del addon:
  el sandbox de WoW sigue sin tener ninguna librería JSON, por eso
  `core/export.lua` la escribe a mano.
- **CSV en tres secciones** (`# levels` / `# sessions` / `# events`,
  separadas por línea en blanco y un comentario `# nombre`): CSV no
  tiene un concepto nativo de varias tablas en un mismo fichero, así
  que esta es la convención más ligera que se sigue pudiendo pegar en
  una hoja de cálculo y separar a mano si hiciera falta. Las filas de
  `# sessions` siempre llevan sus agregados
  (`eventCount`/`totalXP`/`totalRested`), así que omitir `# events` por
  tamaño nunca pierde ese resumen.
- **Umbral de tamaño** (`Ledger.EXPORT_MAX_EVENTS`, 1000): un EditBox
  con cientos de miles de caracteres puede tirar el rendimiento del
  panel. Por encima de ese número de eventos xp (sumados entre todas
  las sesiones del nivel en curso), tanto `ExportJSON` como `ExportCSV`
  dejan de incluir el array/sección de eventos crudos y se quedan solo
  con los agregados por sesión (`eventCount`, `totalXP`, `totalRested`,
  `bySource`) — suficiente para revisar el historial sin poder
  reproducirlo evento a evento. `includeEvents`/`totalEventCount` en el
  JSON (y la línea `# events omitted: ...` en el CSV) dejan claro
  cuándo se ha aplicado el recorte y cuántos eventos había en realidad.
  Los niveles ya cerrados (`levels`) nunca se recortan: ya son
  agregados de por sí (`core/level_close.lua`), su tamaño no depende
  de cuánta xp se haya registrado.
- **Panel** (`ui/export_frame.lua`, mismo patrón que
  `ui/debug_frame.lua`: frame movible/redimensionable con un EditBox
  multilínea de solo lectura dentro de un scroll frame): dos botones
  (`JSON`/`CSV`) alternan el formato y un botón `Refresh` vuelve a leer
  `LedgerCharDB` sin cerrar el panel — el formato elegido persiste
  mientras dura la sesión de juego (variable local, no se guarda en
  ninguna SavedVariable), igual que `currentSource` en
  `ui/debug_frame.lua`. Cada refresco (al abrir, al cambiar de
  formato o al pulsar `Refresh`) llama a `editBox:SetFocus()` seguido
  de `editBox:HighlightText()`, para que el contenido quede
  seleccionado y Ctrl+C lo copie entero sin tener que hacer clic
  dentro antes. Escape cierra el panel por dos vías a la vez: se
  registra en `UISpecialFrames` (el mecanismo estándar de los paneles
  de Blizzard para cerrar con Escape sin depender del foco) y además
  el propio EditBox define `OnEscapePressed` para ocultar el frame —
  hace falta lo segundo porque un EditBox con el foco (el estado
  normal aquí, precisamente para que Ctrl+C funcione al momento)
  consume la tecla Escape él solo, antes de que el manejador global de
  `UISpecialFrames` llegue a verla.

**Pendiente de verificar en el juego** (nada de esto se ha probado
todavía dentro del cliente 1.15.x): que `UISpecialFrames` cierre de
verdad el panel con Escape; que `editBox:SetFocus()` +
`editBox:HighlightText()` dejen el texto realmente seleccionado y que
Ctrl+C lo copie al portapapeles del sistema (la API de WoW no da
acceso directo al portapapeles; esto depende de que el cliente trate
un EditBox enfocado como cualquier campo de texto nativo del sistema
operativo); y que un volcado real por encima de
`Ledger.EXPORT_MAX_EVENTS` no note tirón alguno al pintarse en el
EditBox.

### Diagnóstico de compatibilidad (`core/probe.lua` + `ui/probe.lua`, `/ldg probe`)

Con dos clientes distintos sirviendo desde el mismo paquete (ver
"Multi-cliente" arriba), `/ldg probe` es la herramienta para comprobar
en el cliente real, de golpe, qué API está disponible y con qué forma
— en vez de suponer que Classic Era y WoW Forever se comportan igual.
Nunca aborta: cada comprobación está aislada, así que una API ausente
o que casca al llamarla no impide ver el resto del informe.

- **Reparto core/ui, mismo patrón que `core/state_dump.lua`**:
  `ui/probe.lua: Ledger.GatherProbeData()` es la única pieza que toca
  APIs de WoW — cada llamada opcional pasa por `pcall`, nunca a pelo —
  y devuelve una tabla plana; `core/probe.lua: Ledger.FormatProbe(data)`
  es lógica pura que solo formatea esa tabla a texto, testeada con
  datos fabricados a mano (`spec/probe_spec.lua`), sin ninguna API de
  WoW de por medio.
- **`GetBuildInfo`**: versión, build, fecha y `tocversion` del cliente
  real en ejecución — la comprobación más directa de si un `/reload`
  está corriendo sobre Classic Era o sobre WoW Forever.
- **APIs concretas probadas** (`UnitXP`, `UnitXPMax`, `GetXPExhaustion`,
  `RequestTimePlayed`, `UnitOnTaxi`, `GetUnitSpeed`, orden fijo): cada
  una se marca `absent` si el global no es una función, o si lo es, se
  llama con `pcall` (con `"player"` como único argumento las que lo
  necesitan) y se marca `present, value = ...` con cada valor devuelto
  (`tostring` de cada uno, recortando los `nil` finales — así
  `RequestTimePlayed`, que no devuelve nada, sale como "no return
  value" en vez de una fila de `nil`s) o `present, call failed (...)`
  si `pcall` atrapó un error. `UnitOnTaxi`/`GetUnitSpeed` no los usa
  hoy ningún otro fichero: se prueban de cara a mejorar en el futuro la
  detección del bucket `"travel"` (hoy solo por el temporizador de
  inactividad, ver "Buckets de tiempo" arriba) sin comprometerse a
  usarlos todavía.
- **Global strings `COMBATLOG_XPGAIN_*`**: cuenta y lista TODOS los
  globales de texto con ese prefijo, las dos familias a la vez (los
  patrones base de kill/explore y los de `EXHAUSTION` del bono por
  descanso — ver "Captura de eventos" arriba, que sí las separa para su
  propia lógica; aquí solo interesa el inventario crudo).
- **`C_ChatInfo`**: presencia simple (`C_ChatInfo ~= nil`), sin llamar a
  nada dentro — no se usa en ningún sitio del addon todavía, se prueba
  como referencia de cara a un futuro filtrado de canal de chat.
- **Ancla de la barra de xp** (`xpBarAnchor`, leído de
  `Ledger.xpBarAnchorInfo` — ver "Barra de composición de xp" arriba,
  sección "Localización de la barra nativa"): qué frame se resolvió de
  verdad (contenedor, hijo emparejado, `MainMenuExpBar` o degradado) y
  sus dimensiones, para diagnosticar de un vistazo si un cliente dado
  está anclando donde toca sin tener que abrir `/fstack`. `"not
  resolved yet"` si la barra nunca se ha redibujado esta sesión (p.ej.
  `/ldg bar` nunca se ha activado).

**Degradación con gracia fuera del propio probe**: `RequestTimePlayed`
(el único de los API arriba con un punto de llamada real, en
`ui/xp_capture.lua`, aparte del probe) nunca se llama a pelo —
`SafeRequestTimePlayed()` (local a ese fichero) comprueba que es una
función antes de llamarla y envuelve la llamada en `pcall`. Si falta o
casca en un cliente dado, `lastKnownTotalTimePlayed` simplemente se
queda en su último valor conocido en vez de refrescarse — no hay
ninguna otra `RequestTimePlayed()` suelta en el resto del código.
`UnitXP`/`UnitXPMax` (el resto de lo listado en `/ldg probe` con un uso
real) se quedan sin envolver a propósito: son el núcleo del addon, no
hay ningún modo degradado con sentido si no existen — si un cliente no
las tiene, el addon simplemente no puede rastrear xp en él, y eso es
justo lo que `/ldg probe` debe dejar ver, no ocultar.

**Pendiente de verificar en el juego** (nunca probado, ni contra
Classic Era ni contra WoW Forever): que `/ldg probe` corra sin errores
en ambos clientes y que sus resultados reales confirmen (o desmientan)
los supuestos que ya hace el resto del addon sobre `UnitXP`,
`GetXPExhaustion`/el bono por descanso vía mensaje de chat, y los
global strings `COMBATLOG_XPGAIN_*` en interface 16001.

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
  `barShown`/`barHeight`/`timeBarShown` (barras). `version` está en 5
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
  - v4→v5 (Análisis del SavedVariables real, 2026-09-17), dos cambios
    en el mismo pase por sesión (`MigrateSessionToV5`) más el relleno
    de las entradas de `levels` ya cerradas:
    1. `off` se redondea a entero (`math.floor(off + 0.5)`): el esquema
       viejo lo dejaba con la imprecisión de coma flotante de
       `(GetTime()-t0)*10`.
    2. `src` se traduce de texto a `Ledger.SRC_IDS` si todavía es
       string (no repite la traducción si ya es numérico).
    3. `session.deaths`/`entry.deaths`/`entry.reached` se rellenan a 0
       si faltan — igual que `rested = 0` en v2→v3, no reconstruibles
       retroactivamente.
    El campo `level` (antes `nivel` en el esquema original del addon,
    cuando se llamaba XPTrack) ya no se traduce en esta migración: no
    hay ninguna SavedVariable real por ahí fuera con el campo viejo
    (proyecto de un solo usuario, borrable sin coste), así que se quitó
    el paso de renombrado en vez de mantenerlo como código muerto.
    `session.t0` **NO se traduce**: no hay forma de convertir
    retroactivamente un `GetTime()` viejo (tiempo de actividad del
    cliente) a un `time()` absoluto una vez perdida la correspondencia
    entre ambos relojes. Solo las sesiones nuevas a partir de esta
    versión usan `time()` — ver "Sesión activa" arriba.
- `LedgerCharDB` (por personaje, `## SavedVariablesPerCharacter`):
  `{ version, levels, sessions, lastKnownTotalTimePlayed,
  levelStartTotalPlayed }` (los dos últimos, ver "`totalPlayed` de un
  nivel" arriba). Se inicializa en `ADDON_LOADED` con `LedgerCharDB =
  Ledger.InitCharDB(LedgerCharDB)` (`core/xp.lua`), que reutiliza
  `InitDB`/`MigrateDB` con `Ledger.CHAR_DEFAULTS` — nunca pisa lo que ya
  hubiera, solo rellena lo que falte y migra la versión. `sessions` es
  la lista de sesiones del nivel en curso (ver arriba); `levels[level]`
  guarda el resultado de `CloseLevel`, indexado por nivel real (ver
  "Entrada de `levels`" arriba).
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
    `db.levels` si falta antes de escribir `db.levels[entry.level]`).
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

- `tEnd` solo se rellena hoy al cerrar por `/ldg reset` o al cerrar un
  nivel (`CloseCurrentLevel` no lo toca en la sesión que cierra —
  revisar si debería). Qué pasa con la sesión activa al hacer
  logout/desconexión sin pasar por reset sigue sin decidir. Como
  `sessions` ya es la SavedVariable real, una sesión sin `tEnd`
  sobrevive tal cual al próximo login y se le sigue añadiendo eventos.
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
- **Verificar en el juego el cruce de nivel ya rediseñado** (ver "Cierre
  de nivel" arriba: partido en dos entradas vía `crossing`, disparado
  por el propio evento de xp, ya no por `PLAYER_LEVEL_UP` + temporizador):
  que el nivel viejo cierre exactamente a su tope (no por encima), que
  el nivel nuevo arranque con el `src` real (nunca un "unknown" huérfano
  de decenas de xp), que `/ldg dump` muestre la entrada de `levels` tras
  un ding, y que la barra de composición de xp arranque limpia en el
  nivel nuevo.
- Caso límite conocido y sin arreglar (ver "Cierre de nivel" arriba): una
  segunda ganancia de xp real que llegue mientras la del cruce todavía
  espera su fuente, y siga sin fuente cuando el cruce rota el matcher,
  se pierde (el matcher viejo se descarta entero con ella dentro).
  Ventana real menor que `Ledger.MAX_MATCH_GAP` (1s); ya existía con el
  mecanismo anterior, no es una regresión de este cambio.
- **Verificar en el juego `totalPlayed` vía `TIME_PLAYED_MSG`** (ver
  "`totalPlayed` de un nivel" arriba, recién cableado): que
  `lastKnownTotalTimePlayed` se actualice con cada respuesta, que
  `levelStartTotalPlayed` snapshotee en el momento correcto tanto en
  frío como en cada cierre, y que el `totalPlayed` resultante de un
  nivel real coincida con lo esperado (sin depender de la suma de
  buckets, que ahora es una métrica aparte).
- **Verificar en el juego `reached` y `deaths`** (nuevos, sin probar con
  datos reales): que `reached` capture el instante del ding real (no
  solo el de arranque en frío) y que `deaths` cuente cada
  `PLAYER_DEAD` del nivel, separado del bucket de tiempo `dead`.
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
  `levels[level]`: ahora que `CloseLevel` sí se llama en cada cierre, se
  ha confirmado que no hace falta trasladarlo — el segmento gris solo lo
  usa la barra del nivel EN CURSO, nunca una entrada de `levels` ya
  cerrada.
- Verificar en el juego toda la alimentación real de los buckets de
  tiempo (recién cableada, nunca probada con datos de verdad): que
  `PLAYER_REGEN_DISABLED` y las ganancias de xp marquen `"active"`
  correctamente, que el ticker de 1s transicione a `"travel"` pasados
  los 30s (`Ledger.INACTIVITY_THRESHOLD`) sin ninguna de esas dos
  señales, que se vea reflejado en la barra de reparto de tiempo sin
  repartirse con `"idle"`, que `PLAYER_DEAD`/`PLAYER_UNGHOST` acumulen
  `"dead"` bien, y que el cierre de nivel sume los buckets de
  todas las sesiones correctamente en `levels[level].buckets`.
- Ver visualmente en el juego la barra de reparto de tiempo (nunca
  probada): anclaje 2px por encima de la barra de xp, el orden fijo
  active/travel/idle/dead, los colores (incluidos los que reutilizan
  `kill`/`unknown`), el borde, y su tooltip.
- Verificar en el juego el panel de exportación (`/ldg export`, ver
  "Exportación de datos" arriba, nunca probado): que `UISpecialFrames`
  cierre el panel con Escape, que `editBox:HighlightText()` deje el
  texto realmente seleccionado y que Ctrl+C lo copie al portapapeles
  del sistema, y que un volcado real por encima de
  `Ledger.EXPORT_MAX_EVENTS` no note tirón alguno al pintarse.
- Correr `/ldg probe` en el cliente real de WoW Forever (build 1.60.1,
  interface 16001) y en Classic Era, y comparar: ver "Diagnóstico de
  compatibilidad" arriba para qué comprueba y por qué nada de esto se
  puede confirmar sin el cliente de verdad. Si algo sale distinto entre
  los dos (`GetXPExhaustion` en vez del parseo de chat para el bono por
  descanso, otro nombre de global string, `UnitOnTaxi`/`GetUnitSpeed`
  con otra forma), decidir entonces si conviene ramificar algún camino
  del addon por versión de interface — hoy no hay ninguna rama de ese
  tipo en ningún sitio.
- Verificar en el juego la resolución de ancla de la barra de xp (ver
  "Localización de la barra nativa" arriba, reescrita para el porte a
  WoW Forever, nunca probada tal cual): en Classic Era, que
  `xpBarAnchor` en `/ldg probe` siga marcando `"...matched child"` y
  que el comportamiento visual sea idéntico a antes del porte; en WoW
  Forever, que el contenedor sin hijo emparejado ancle bien usando su
  propia geometría (`"...container"`); forzando el caso degradado
  (renombrando temporalmente ambos globales, o en un cliente que
  careciera de los dos) que la barra aparezca en la posición por
  defecto, se pueda arrastrar, la nueva posición sobreviva a un
  `/reload`, y el aviso INFO salga una sola vez por sesión; y que
  `UI_SCALE_CHANGED` reancle de verdad al cambiar la escala de la UI
  (`Configuración → Interfaz`), no solo `PLAYER_ENTERING_WORLD`.
