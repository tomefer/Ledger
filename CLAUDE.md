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
    nivel (active/downtime/travel/dead), independiente de `/ldg bar`
    (ver "Barra de reparto de tiempo" más abajo).
  - (`/ldg recalc` ya no existe: se eliminó cuando la serie cruda pasó
    a descartarse al cerrar cada nivel — ver "Buckets de tiempo" más
    abajo; ya no hay nada que recalcular en los niveles cerrados.)
  - `/ldg rate`: muestra u oculta el número destacado de xp/hora de la
    sesión actual, anclado encima de la barra de composición de xp;
    pasar el ratón por encima abre un panel propio con el desglose
    sesión/nivel (ver "Número principal de xp/hora" más abajo).
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
  - `/ldg check`: muestra u oculta la ventana de reconciliación entre lo
    registrado y la realidad (`ui/check_frame.lua`, ver "Reconciliación"
    más abajo).
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
    tEnd    = <time() ABSOLUTO: lo refresca cada segundo el ticker de
               muestreo (ui/xp_capture.lua: SampleTimeState) mientras la
               sesión es la activa, así que en la activa es "visto vivo
               por última vez" (nunca nil una vez ha corrido un tick), y
               en una cerrada se queda congelado en el último tick;
               /ldg reset lo fija además al instante exacto del cierre.
               Es el denominador del xp/hora de una sesión leída de
               datos guardados/exportados (la UI en vivo usa time() tal
               cual, ver core/rate.lua)>,
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
    stateSeries = {
        -- array plano de la serie state (Ledger.SERIES.state, ver
        -- "Buckets de tiempo" abajo): un entero empaquetado por segundo
        -- (combat/moving/dead/taxi), muestreado en vivo por
        -- ui/xp_capture.lua: SampleTimeState. NO hay campo `buckets` en
        -- la sesión: los buckets nunca se acumulan ni se guardan aquí,
        -- siempre se derivan de esta serie con
        -- Ledger.ComputeBucketsFromState cuando hacen falta.
    },
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

### Buckets de tiempo (`core/time_buckets.lua`)

**Rediseñado 2026-09-18**: pasa de un tracker en vivo con reclasificación
retroactiva a **estado crudo muestreado + reglas de agregación puras**:
lo que se persiste es la señal cruda del nivel EN CURSO, y el bucket
siempre se DERIVA de ella, nunca se acumula en vivo. **Ajustado
2026-09-18 (análisis del SavedVariables real)**: la serie cruda solo
vive mientras el nivel está en curso; al cerrarlo se agregan los
buckets una vez y la serie se DESCARTA (guardarla entera en cada nivel
cerrado no escala), guardando en su lugar los umbrales usados
(`entry.thresholds`) para saber si dos niveles son comparables. Por eso
`/ldg recalc` y `Ledger.RecalculateAllBuckets` se eliminaron: ya no hay
serie cruda de niveles cerrados que reclasificar — un cambio de umbral
solo afecta al nivel en curso (la barra en vivo se re-deriva siempre con
los umbrales vigentes) y a los niveles que se cierren a partir de
entonces.

**1) Muestreo crudo** (`ui/xp_capture.lua: SampleTimeState`, ticker de
1s independiente del que vacía el matcher): cada segundo lee 4 flags
instantáneos de verdad —

- `combat` = `UnitAffectingCombat("player")`. A diferencia del diseño
  anterior (que evitaba esta API a propósito porque se sale de combate
  constantemente entre pull y pull), aquí SÍ se usa tal cual: el
  suavizado de "hueco corto tras combate sigue siendo activo" ya no
  vive en el muestreo, vive en la regla de agregación (ver más abajo).
- `moving` = `GetUnitSpeed("player") > 0`, crudo e instantáneo también
  (sin filtrar aquí "sostenido 3s": eso también es una regla de
  agregación, ver `Ledger.MarkSustainedRuns` más abajo).
  **Confirmado en el juego (WoW Forever beta, build 1.60.1, interface
  16001, 2026-09-18)**: este cliente marca el valor devuelto por
  `GetUnitSpeed` como "secret" — la llamada en sí no falla, pero
  compararlo (`> 0`) revienta con `attempt to compare a secret number
  value (execution tainted by 'Ledger')`, tainting nativo del motor
  contra código de addon inseguro, no un `pcall` normal de API
  ausente. `ui/xp_capture.lua: IsPlayerMoving()` envuelve también la
  comparación en su propio `pcall` y degrada a "no se mueve" con un
  aviso ERROR una sola vez por sesión — a diferencia del modo
  degradado de la barra de xp (INFO, modo soportado), esto SÍ es una
  pérdida real de datos: el bucket `travel` no se puede detectar en
  absoluto en este cliente mientras siga así. Sin confirmar todavía si
  Classic Era (1.15.x) tiene el mismo tainting o es exclusivo de esta
  build de WoW Forever; añadir a `/ldg probe` si hace falta distinguir
  entre "ausente" y "secreto" de un vistazo.
- `dead` = `UnitIsDeadOrGhost("player")` — sustituye por completo a los
  antiguos handlers `PLAYER_DEAD`/`PLAYER_UNGHOST` para este propósito
  (`PLAYER_DEAD` se mantiene SOLO para el contador `deaths`, que es una
  métrica distinta — ver "Cierre de nivel" arriba).
- `taxi` = `UnitOnTaxi("player")`.

Los 4 booleanos se empaquetan en un único entero
(`Ledger.PackStateFlags`/`Ledger.UnpackStateFlags`, suma de potencias de
2 — Lua 5.1 no tiene operadores bitwise nativos, así que la
pertenencia se comprueba con aritmética: `math.floor(v/flag) % 2`) y se
añaden como un registro más de una nueva serie declarativa,
`Ledger.SERIES.state` (`core/series.lua`, `key = "stateSeries"`
(antes `"st"`, unificado con el nombre que tenía en los niveles en la
migración v6→v7), `stride = 1`,
sin campo `off`: a diferencia de la serie `xp`, aquí la posición del
array YA es el segundo — un nivel de dos horas son 7200 enteros
pequeños). Se persiste con `Ledger.AppendRecord(session, Ledger.SERIES.state,
packed)`, igual que cualquier otra serie.

**2) Reglas de agregación** (`Ledger.ComputeBucketsFromState(rawArray,
thresholds)`, función pura — el ÚNICO sitio donde se decide a qué
bucket pertenece un segundo): recibe la serie cruda entera y un
`thresholds` opcional (`{ downtime=, sustainedMovement= }`, por defecto
`Ledger.DOWNTIME_THRESHOLD` = 15 y `Ledger.SUSTAINED_MOVEMENT_SECONDS`
= 3, ambas constantes editables en código). Prioridad por segundo, de
mayor a menor:
1. `dead` → `"dead"` (siempre gana, incluso a mitad de combate: un
   cadáver no está "activo").
2. `combat` → `"active"`.
3. movimiento sostenido (`Ledger.MarkSustainedRuns`, ver abajo) o
   `taxi` → `"travel"`.
4. si han pasado menos de `downtime` segundos desde el último segundo
   con `combat` → `"active"` (hueco normal entre pulls).
5. si no, `"downtime"`.

`Ledger.MarkSustainedRuns(rawFlags, sustainedSeconds)` recibe la lista
cruda de flags `moving` (uno por segundo) y devuelve una lista paralela
de booleanos: verdadero para CADA segundo de una racha de al menos
`sustainedSeconds` segundos consecutivos en movimiento — la racha entera
cuenta desde su primer segundo en cuanto se confirma lo bastante larga,
no solo a partir del enésimo (si no, un tramo real de travel perdería
sus primeros 2 segundos). Una racha corta (reposicionarse, un proc de
Sprint) que nunca llega al umbral se queda en `false` todo el rato.

Los buckets pasan a ser **`active`, `downtime`, `travel`, `dead`**
(antes `active`/`idle`/`travel`/`dead` — `idle` desaparece como
concepto: ya no hace falta un estado especial "justo después de
resucitar", `dead` se muestrea de forma continua e instantánea vía
`UnitIsDeadOrGhost`, así que en cuanto deja de ser cierto el siguiente
segundo ya cae solo en la regla que le toque).

**3) Dónde vive la serie cruda y dónde se deriva el bucket**:
- `session[Ledger.SERIES.state.key]` (`session.stateSeries`): la serie
  cruda DE ESTA sesión. Ya no existe `session.buckets` en absoluto — los
  buckets nunca se acumulan ni se guardan en una sesión, siempre se
  derivan.
- Al cerrar un nivel, `core/level_close.lua: CloseLevel` concatena
  `session.stateSeries` de TODAS las sesiones del nivel
  (`Ledger.ConcatSeries(sessions, Ledger.SERIES.state)`), calcula
  `entry.buckets = Ledger.ComputeBucketsFromState(serie, umbrales)` UNA
  vez y **descarta la serie**: la entrada de `levels` no lleva
  `stateSeries`. Guarda `entry.thresholds = { downtime=, sustainedMovement= }`
  con los umbrales que produjeron esos buckets (por defecto
  `Ledger.DOWNTIME_THRESHOLD`/`Ledger.SUSTAINED_MOVEMENT_SECONDS`;
  `CloseLevel` acepta un `thresholds` opcional que los sobrescribe), y
  `/ldg dump` los muestra por nivel (`thresholds=downtime=15s/sustained=3s`,
  o `unknown` si el nivel es de antes de guardarlos).
- Para el nivel EN CURSO (barra de reparto de tiempo en vivo,
  `ui/time_bar.lua`), no hay tracker que "previsualizar": cada
  redibujado concatena `Ledger.SERIES.state` de
  `LedgerCharDB.sessions` tal cual y llama a
  `Ledger.ComputeBucketsFromState` de cero — barato (como mucho unos
  miles de enteros) y siempre exacto con los umbrales vigentes.

**`buckets` sigue siendo una métrica de reparto, NO de duración
total**: `entry.totalPlayed` (ver "Entrada de `levels`" abajo) sigue
saliendo de `TIME_PLAYED_MSG` del personaje, nunca de sumar los
buckets — eso no ha cambiado con este rediseño.

### Entrada de `levels` (`core/level_close.lua: CloseLevel(sessions, totalPlayed, includeRested)`)

```lua
levels[level] = {
    level       = <nivel>,
    reached     = <time() absoluto del ding que llevó a este nivel; 0 si
                   viene de datos de antes de esta migración (no
                   reconstruible retroactivamente) — ver sessions[1].reached>,
    initialXP   = <xp que el jugador ya llevaba en el nivel antes de que
                   el addon empezara a rastrearlo (sessions[1].initialXP,
                   0 si no hubo): la xp registrada + initialXP es lo que
                   debe sumar xpRequired. Solo el primer nivel rastreado
                   en frío lo tiene distinto de 0>,
    xpRequired  = <xp que ese nivel requería para completarse
                   (UnitXPMax del nivel viejo, `crossing.oldMax` de
                   Ledger.ComputeXPDelta, pasado por CloseCurrentLevel).
                   Ausente en niveles cerrados antes de guardarlo: no hay
                   API para pedirlo a posteriori — /ldg check los marca
                   como "no verificable", no como discrepancia>,
    totalXP     = <suma de la xp EFECTIVA de todas las sesiones del
                   nivel, xp o xp-rested segun includeRested (true por
                   defecto); ver Ledger.EffectiveXP arriba>,
    totalRested = <suma del bono por descanso real, SIN toggle: no
                   cambia con includeRested>,
    totalPlayed = <segundos jugados en el nivel, según TIME_PLAYED_MSG
                   del personaje (NO la suma de buckets, que es una
                   métrica aparte — ver "Buckets de tiempo" y "Cierre de
                   nivel" más abajo); se pasa ya calculado, CloseLevel NO
                   lo calcula. **`nil` si la línea base de tiempo era
                   desconocida al cerrar** (ver "`totalPlayed` de un
                   nivel"): nunca un 0 ni un número inventado>,
    timeUnreliable = <`true` exactamente cuando `totalPlayed` es nil
                   (dato de tiempo no fiable); AUSENTE en un nivel con
                   tiempo válido, nunca `false`. Todo lo que lea
                   `totalPlayed` debe saltarse estos niveles>,
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
    buckets     = { active = 0, downtime = 0, travel = 0, dead = 0 },
                    -- DERIVADO UNA VEZ al cerrar, de la serie state de
                    -- todas las sesiones del nivel, con
                    -- Ledger.ComputeBucketsFromState; la serie cruda se
                    -- descarta (no hay entry.stateSeries)
    thresholds  = { downtime = 15, sustainedMovement = 3 },
                    -- umbrales con los que se derivaron esos buckets,
                    -- para saber si dos niveles son comparables; ausente
                    -- en niveles migrados desde antes de guardarlos
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
    - xpAnterior, newPart = xpActual, oldLevel=, newLevel=, oldMax =
    maxAnteriorCacheado }` — `oldPart + newPart == delta` siempre — para
    que quien grabe el evento pueda partirlo en dos entradas en vez de
    metérselo entero a un solo nivel (ver "Cruce de nivel" más abajo).
    `oldMax` es la xp que requería el nivel viejo: acaba en
    `entry.xpRequired` al cerrarlo (`EmitCrossingEvent` →
    `CloseCurrentLevel(t, xpRequired)` → `Ledger.CloseLevel(..., xpRequired)`).
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
  cualquier mensaje de combate, en vez de solo loguearse. El `xp`
  otorgado por la quest (arg2) viaja como `expectedXP` en el evento
  emparejado, para verificación cruzada: `ui/xp_capture.lua: EmitEvent`
  compara `expectedXP` contra el `xp` real (siempre el delta de
  `UnitXP`, nunca el de la quest) y loguea a ERROR si no coinciden — la
  cantidad grabada sigue siendo siempre la del delta, la discrepancia
  es solo una señal de alarma.
  - **Emparejamiento por cantidad, no por tiempo (confirmado en el
    juego 2026-09-18: algunas entregas se clasificaban como "explore",
    no todas)**: el desempate por prioridad
    (`core/xp_gain_matcher.lua: SOURCE_PRIORITY`, `"quest"` siempre
    gana a cualquier otra dentro del margen) nunca fue el problema —
    el problema era de ventana temporal: el mensaje genérico de
    combate y el propio `QUEST_TURNED_IN` no siempre llegan a tiempo
    de coincidir DENTRO del margen a la vez, así que uno de los dos
    podía emparejarse (o quedar huérfano) antes de que el otro
    llegara a competir. `Ledger.AddAmount`/`Ledger.AddSource` ahora
    buscan primero, antes que la regla FIFO por proximidad, una
    etiqueta `"quest"` pendiente cuyo `expectedXP` coincida EXACTO con
    la cantidad — si la hay, gana sin importar los milisegundos de
    separación (una entrega de quest es infrecuente, no hay riesgo de
    emparejar con la equivocada, a diferencia de los kills, que sí
    llegan en ráfaga y siguen usando solo la ventana normal). Las
    etiquetas `"quest"` además sobreviven más en la cola
    (`Ledger.QUEST_MATCH_GAP = 3.0`, frente a `Ledger.MAX_MATCH_GAP =
    1.0` para todo lo demás — `matcher.questGap`, usado solo en el
    `Flush` de fuentes) para dar tiempo a que llegue la cantidad. Y un
    mensaje genérico solo se clasifica de verdad como `"explore"` si
    `core/xp_gain_matcher.lua: Ledger.HasPendingQuestSource` (llamada
    desde `ui/xp_capture.lua` antes de encolarlo) no encuentra ninguna
    etiqueta `"quest"` pendiente en la cola — ni por cantidad (usando
    el propio `%d` que ese mensaje captura) ni por sola presencia; si
    la encuentra, el mensaje se descarta sin encolarse como fuente
    competidora, porque ya sabemos que la fuente real de esa xp es la
    quest. Todo TRACE (`ExploreCheck: ...`).
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
3. Llama a `CloseCurrentLevel(t)`: calcula `totalPlayed` (ver "Buckets
   de tiempo"/SavedVariables — NO es la suma de buckets),
   `Ledger.CloseLevel` (que deriva `entry.buckets` de las series `state`
   de las sesiones que cierran) + `Ledger.RecordLevelClose`, y abre la
   sesión del nivel nuevo (`reached = time()`, snapshot de
   `levelStartTotalPlayed`, `RequestTimePlayed()` para refrescar el
   total cuanto antes), reiniciando `matcher`/`reconciler` (no hay
   ningún tracker de tiempo que reiniciar: el muestreo de estado sigue
   su curso solo, escribiendo en la sesión que esté activa en cada
   momento).
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
  **Es un dato guardado, nunca se usa crudo en un cálculo** (ver
  "Estimación entre respuestas" abajo).
- `LedgerCharDB.levelStartTotalPlayed`: el total (estimado, ver abajo)
  en el instante en que se empezó a rastrear el nivel EN CURSO.
- `entry.totalPlayed = EstimatePlayedTotal(t) - levelStartTotalPlayed`
  (recortado a 0 si saliera negativo, salvaguarda defensiva), calculado
  SOLO por `Ledger.LevelPlayedTime(charDB, clock, now)`
  (`core/played_baseline.lua`): el único sitio que resta la base, usado
  tanto por el cierre de nivel como por el xp/hora en vivo del nivel.
- `RequestTimePlayed()` se llama en `PLAYER_ENTERING_WORLD`, en
  `CloseCurrentLevel` (justo después de avanzar la base) y tras un
  `/ldg wipe`; la respuesta (asíncrona, vía `TIME_PLAYED_MSG`) no llega
  a tiempo para el cierre que la disparó, pero re-ancla la estimación
  para lo que venga después.

**Estimación entre respuestas** (`Ledger.EstimatePlayedTotal(charDB,
clock, now) = cached + (now - clock.receivedAt)`): `TIME_PLAYED_MSG`
solo contesta cuando se le pide, así que el total cacheado se congela
entre peticiones y, leído crudo, INFRAVALORA el total por el tiempo que
hace que llegó (un nivel cerrado 20 min después de la última respuesta
perdía esos 20 min). `receivedAt` es el `GetTime()` de recepción; el
tiempo jugado avanza 1s por segundo mientras el personaje está conectado
y `GetTime()` también, así que van a la par. `now` es siempre un
parámetro (`core/` no toca el reloj): el cierre de nivel usa `t`, el
`GetTime()` del propio evento de xp que cruza el ding (mejor que el
instante en que acaba emparejándose), y `rate_frame` usa `GetTime()`.
`now` puede quedar unos segundos ANTES de `receivedAt` (un ding cuya
respuesta llegó un instante después): vale igual, el contador es
monótono y restar el hueco es exacto. La base del nivel siguiente
(`AdvancePlayedBaseline`) es la estimación en el ding, no el cacheado
crudo, así que tampoco arrastra el desfase.

- **`receivedAt` NUNCA se persiste** — vive en `Ledger.playedClock`
  (`{ receivedAt=, awaiting= }`, en memoria, creado en `ui/events.lua`
  junto a `logState`), no en `LedgerCharDB`. Motivo (tiempo
  desconectado): `GetTime()` está documentado como el uptime del
  SISTEMA, con lo que su origen no es el de los datos guardados: un
  `receivedAt` guardado en una ejecución y comparado con el `GetTime()`
  de la siguiente sería la diferencia de dos relojes sin relación —
  arbitraria, posiblemente negativa, y (si `GetTime()` sigue corriendo
  con el cliente cerrado, como haría un uptime de sistema) inflada con
  todo el tiempo desconectado, que el tiempo jugado NO cuenta. Al vivir
  solo en memoria eso es imposible por construcción, sin depender de la
  semántica exacta de `GetTime()`: tras un `/reload` o reinicio el
  nuevo estado Lua no tiene `receivedAt`, así que la estimación es
  `nil` (desconocido) hasta la respuesta al `RequestTimePlayed` que
  `PLAYER_ENTERING_WORLD` manda enseguida (milisegundos). El único
  tramo que cubre la estimación es uno continuo con el personaje
  conectado, donde `GetTime()` y el tiempo jugado avanzan juntos; una
  pantalla de carga forma parte de ese tramo, y
  `PLAYER_ENTERING_WORLD` vuelve a pedir el total tras cada una.
  **Pendiente de confirmar en el cliente real** la premisa de que
  `GetTime()` no avanza con el cliente cerrado: la documentación dice lo
  contrario (uptime del sistema); no importa para la corrección, pero
  `/ldg probe` imprime `GetTime()` para comprobarlo (ejecutarlo, reiniciar
  el cliente, ejecutarlo otra vez: si el valor sigue subiendo es uptime
  de sistema; si vuelve a empezar pequeño es relativo al cliente).
- **Desconocido → `nil`**: si el total cacheado es `nil`, o no se recibió
  en ESTE estado Lua (un valor guardado de una ejecución anterior no
  tiene `receivedAt` fiable, y no se usa crudo), `EstimatePlayedTotal`
  devuelve `nil`, `LevelPlayedTime` también, y el nivel se cierra con
  `timeUnreliable` igual que con la base desconocida (ver abajo).

**`nil` significa DESCONOCIDO, nunca cero** (bug real, wipe/instalación
nueva: el primer nivel cerrado registró 01:37:15 jugados frente a
00:16:16 entre dings, porque `CHAR_DEFAULTS` y `WipeCharacterData`
dejaban la base a 0 y el cierre calculaba `lastKnown - 0` = el tiempo
jugado TOTAL del personaje). El total no está disponible en el instante
en que empieza el rastreo — `RequestTimePlayed` es asíncrono — así que
`lastKnownTotalTimePlayed` y `levelStartTotalPlayed` **no tienen default**
en `Ledger.CHAR_DEFAULTS` y valen `nil` mientras no se sepan. Las
transiciones son lógica pura en `core/played_baseline.lua`
(`StartPlayedBaseline`, `ApplyTimePlayed`, `LevelPlayedTime`,
`AdvancePlayedBaseline`, `WipeCharDB`, `EstimatePlayedTotal`,
`NewPlayedClock`), testeada en
`spec/played_baseline_spec.lua`; `ui/xp_capture.lua` solo las llama.

- **`clock.awaiting`** (en `Ledger.playedClock`, en memoria, a propósito
  NO persistido): "la base es nil Y el próximo
  `TIME_PLAYED_MSG` es el valor correcto para sembrarla". Se activa al
  arrancar el rastreo en frío (`StartTracking` con `#sessions == 0`:
  instalación nueva) y en `/ldg wipe`, y en `CloseCurrentLevel` si al
  avanzar la base tampoco se sabía el total. `ApplyTimePlayed` siempre
  refresca `lastKnown` y, solo si estaba esperando, siembra la base con
  ese mismo valor (`TIME_PLAYED_MSG` trae el total del personaje, no el
  del nivel: en el instante de arranque ambos coinciden). Una base nil
  con `awaiting = false` (datos migrados, o la respuesta no llegó antes
  de un `/reload`) se queda desconocida para siempre: sembrarla después
  sería posterior al inicio real del nivel.
- **`/ldg wipe`** (`Ledger.WipeCharDB`) vacía `levels`/`sessions` y
  también olvida `lastKnownTotalTimePlayed` (pertenecía a los datos
  borrados; el wipe no resetea el tiempo jugado del personaje, solo los
  registros de Ledger) y deja la base desconocida hasta que llegue la
  respuesta.
- **Cierre con base o total desconocidos**: `totalPlayed = nil` y
  `entry.timeUnreliable = true` (`Ledger.CloseLevel`), nunca un número
  inventado. Un cierre que ocurre ANTES de que llegue la respuesta
  también deja el nivel siguiente con base desconocida
  (`AdvancePlayedBaseline` no copia un `lastKnown` que aún no es "ahora").
- **Lectores** que respetan el nil: `/ldg check` (`skip`, "sin dato de
  tiempo fiable", nunca discrepancia — no es un error del addon),
  `ui/rate_frame.lua` (el "This level" del xp/hora sale como `"-"` en vez
  de dividir por un número falso — es el único cálculo de xp/hora que
  usa esta resta; los niveles cerrados no tienen ninguno),
  `core/state_dump.lua` (`time=unknown (no reliable played-time data)`) y
  `core/export.lua` (JSON `null` + `"timeUnreliable"`, y en CSV celda
  vacía + columna `timeUnreliable`; también `lastKnownTotalTimePlayed`/
  `levelStartTotalPlayed` salen `null`, nunca 0).
- Los niveles cerrados ANTES de este arreglo conservan el `totalPlayed`
  que tuvieran (no se destruye dato); `/ldg check` marca como
  discrepancia los que rompen los invariantes de abajo.

**Causa de fondo del `totalPlayed` erróneo en las versiones anteriores a
0.9.0** (análisis de dos exports reales, 2026-09-19; el algoritmo viejo
está reproducido en `spec/played_baseline_spec.lua`): al cerrar un
nivel, `totalPlayed = lastKnown - base` y luego `base := lastKnown`, con
`lastKnown` capturado ANTES de que llegara la respuesta de
`RequestTimePlayed` pedida en ese mismo cierre. La base quedaba una
respuesta por detrás, y como `lastKnown` solo se mueve cuando llega una
respuesta (login, cierres, pantallas de carga), `totalPlayed` de un nivel
salía como *(instante de la última respuesta antes de este cierre) menos
(instante de la última respuesta antes del cierre anterior)*: en el caso
típico, con respuestas solo en cada cierre, **la duración del nivel
ANTERIOR** (un off-by-one exacto: 531 frente a los 530s del nivel previo),
y con respuestas por pantallas de carga, un valor arbitrario en cualquiera
de los dos sentidos. De ahí también que la suma de los `totalPlayed`
escritos fuera EXACTAMENTE la base (`base := lastKnown` con base inicial
0 telescopa: es una identidad, no un segundo fallo), y que el nivel en
curso heredara el desfase. Nada en `PLAYER_ENTERING_WORLD` ni en un
`/reload` escribe la base (los únicos escritores son
`StartPlayedBaseline`, `WipeCharDB`, `AdvancePlayedBaseline`, la siembra
de `ApplyTimePlayed` y la migración; y el flag `awaiting` no sobrevive a
un `/reload`). El arreglo (0.9.0) es que la base al cerrar es el total
ABSOLUTO estimado en el ding (`AdvancePlayedBaseline` →
`EstimatePlayedTotal(t)`), nunca `base + totalPlayed` ni el cacheado
crudo, así que un cierre erróneo ya no contamina los siguientes.

### Invariantes del tiempo jugado (`core/level_time.lua`)

Una sola definición, compartida por el cierre de nivel y por
`/ldg check`, de qué es imposible en el `totalPlayed` de un nivel cerrado,
contrastándolo con dos medidas independientes del contador del servidor:

- **Cota superior**: nunca más que el tiempo de reloj entre el ding de
  este nivel y el del siguiente (`reached` de cada uno; en el cierre, con
  `time() - entry.reached`) → `exceeds-elapsed`.
- **Cota inferior**: nunca menos que la suma de los buckets
  (`Ledger.SumBuckets(entry.buckets)`): el ticker solo corre con el
  cliente abierto, así que cada muestra es un segundo realmente jugado y
  su suma es una cota inferior (se pueden perder ticks, p. ej. en una
  pantalla de carga, pero nunca inventarse) → `below-samples`. Con datos
  reales la suma queda 4–25s POR DEBAJO del tiempo real entre dings.
- **Curva**: `curve` tiene una entrada por minuto de tiempo en juego, así
  que no puede tener más de `floor((totalPlayed + tolerancia)/60) + 1`
  entradas → `curve-too-long` (un nivel de 41 minutos con `totalPlayed` de
  6 los rompía). Con datos reales el límite es justo (2552s → 43
  entradas), por eso la tolerancia.
- `Ledger.TIME_TOLERANCE = 60` s en las tres comparaciones (antes
  `CHECK_TIME_TOLERANCE`, en `core/check.lua`).
- Un `totalPlayed` `nil` (`timeUnreliable`) no tiene nada que comprobar.
- **En el cierre** (`ui/xp_capture.lua: CloseCurrentLevel`): cada
  violación se loguea a ERROR (`LevelClose invariant violated (level N,
  id): ...`). La entrada se guarda tal cual se calculó, no se "corrige" en
  silencio. Ojo: el nivel de log por defecto es `off`, así que ese ERROR
  solo llega al buffer con `/ldg log error` (o más verboso) activo;
  `/ldg check` lo vuelve a mostrar siempre.
- **En `/ldg check`**: cada violación es una línea `[!!]` por nivel. La
  antigua frase "not played: logged out or away" sobre un nivel que los
  buckets desmienten era FALSA (el cliente estaba dentro del juego todo
  ese tiempo); ahora solo sale en niveles que cumplen los invariantes, y
  dice "logged out" (estar AFK sí cuenta como jugado).

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

- **Orden fijo** (`Ledger.TIME_BUCKET_ORDER = { "active", "downtime",
  "travel", "dead" }`): siempre de izquierda a derecha en ese orden,
  para que la forma sea reconocible de un vistazo — nunca reordenado
  por tamaño, a diferencia de la barra de xp (que fusiona por orden de
  llegada).
- **Cálculo puro** (`core/time_bar.lua: Ledger.ComputeTimeBarSegments(buckets,
  widthPx)`): reparte `widthPx` proporcionalmente al peso de cada
  bucket sobre el total, reutilizando `Ledger.RoundedWidths` (expuesta
  desde `core/xp_bar.lua` para esto) — misma técnica de redondeo por
  acumulado que la barra de xp, así que tampoco aquí la suma de
  anchuras supera nunca `widthPx`. Si el total es 0 (nivel recién
  empezado, sin ninguna muestra todavía), no hay segmentos.
- **Fuente de datos: TODAS las sesiones del nivel** (igual que la barra
  de xp, nunca solo la activa), y siempre DERIVADA, nunca cacheada: cada
  redibujado concatena la serie cruda de estado
  (`Ledger.ConcatSeries(LedgerCharDB.sessions, Ledger.SERIES.state)`) y
  la agrega de cero con `Ledger.ComputeBucketsFromState` (ver "Buckets
  de tiempo" arriba) — no hay tracker en vivo que previsualizar, el
  muestreo real de cada segundo ya deja el dato crudo ahí, así que la
  barra crece sola sin ningún caso especial en este fichero.
- **Colores y borde: la MISMA `Ledger.PALETTE`** que la barra de xp
  (`ui/palette.lua`) — `travel` #4A6FA5 (azul apagado) y `dead` #8B3A3A
  (rojo oscuro apagado) son entradas propias; `active` reutiliza el
  color de `kill` (mismo dorado: es tiempo productivo) y `downtime` el
  de `unknown` (mismo gris cálido) — ninguno es una copia del hex, son
  el mismo objeto de color, así que si `kill`/`unknown` cambiaran algún
  día estos les seguirían automáticamente. Mismo borde de 1px negro al
  60% que la barra de xp (`ui/time_bar.lua: LayoutBorder`, código casi
  idéntico al de `ui/xp_bar.lua`).
- **Render**: a diferencia del pool dinámico de la barra de xp, aquí
  hay una textura fija por bucket (siempre son los mismos 4, en el
  mismo orden) — no hace falta un pool. `Ledger.RedrawTimeBar()` se
  llama **desde el mismo ticker de 1s que muestrea el estado crudo**
  (`ui/xp_capture.lua: SampleTimeState`), **nunca desde los eventos de
  xp**: los tramos de viaje/downtime/muerte no generan ningún evento de
  xp — atarlo a las kills dejaría la barra congelada la mayor parte del
  tiempo.
- **Tooltip**: `core/time_bar.lua: Ledger.FormatTimeBarTooltip(buckets)`
  (función pura) devuelve una línea por bucket con su tiempo absoluto
  en `hh:mm:ss` (`Ledger.FormatHHMMSS`) y su porcentaje del total;
  `ui/time_bar.lua` colorea cada línea con `Ledger.PALETTE[bucket]` al
  pintarla en el `GameTooltip`.
- `/ldg time` alterna `LedgerDB.timeBarShown` y muestra/oculta el
  frame — **independiente de `/ldg bar`**, cada una se muestra u oculta
  por su cuenta.

### Número principal de xp/hora (`core/rate.lua` + `ui/rate_frame.lua`, `/ldg rate`)

Frame propio, "destacado" (`SetFrameStrata("HIGH")`, por encima de las
barras de xp/tiempo si llegaran a solaparse), anclado justo encima de
la barra de composición de xp — `frame:SetPoint("BOTTOM",
Ledger.xpBarFrame, "TOP", 0, 2)`, un único punto de anclaje que centra
horizontalmente por construcción (`"BOTTOM"`/`"TOP"` son ya el
centro-superior/centro-inferior del frame, no una esquina) y con 2px de
separación. Como es una relación de anclaje viva de WoW, no hace falta
re-anclar nunca tras el primer `SetPoint`: el número sigue a
`Ledger.xpBarFrame` automáticamente aunque ese frame se mueva o
redibuje (incluido su propio modo degradado — ver "Localización de la
barra nativa" arriba), sin ningún código adicional aquí.

- **El número**: xp/hora de la **sesión activa** (`Ledger.TotalXP(session,
  includeRested) / (time() - session.t0) * 3600`, ver
  `core/rate.lua: Ledger.ComputeXPRate`), nunca del nivel — ese es el
  dato del panel al pasar el ratón (ver abajo). Tipografía
  `GameFontNormalHuge`, blanco (`text:SetTextColor(1,1,1,1)`), sobre
  fondo negro semitransparente (`SetBackdropColor(0,0,0,0.6)`) que se
  ajusta al texto con padding (`ui/rate_frame.lua: ResizeToText`,
  `PADDING_X`/`PADDING_Y`) en vez de tener un ancho fijo.
- **Formato** (`core/rate.lua: Ledger.FormatXPRate`, pura): redondea al
  entero más cercano, separador de miles a mano (idioma clásico de
  Lua: inserta una coma antes de cada grupo de 3 dígitos repetidamente
  hasta que `gsub` deja de encontrar más, sin ninguna librería) y
  sufijo `" xp/h"`. `nil` (ver el umbral justo abajo) se formatea como
  `"-"`, nunca como `"0 xp/h"` ni un número inventado.
- **Guion con menos de un minuto de sesión**
  (`Ledger.RATE_MIN_SECONDS = 60`, `core/rate.lua: Ledger.ComputeXPRate`):
  por debajo de ese umbral de segundos transcurridos, el denominador es
  tan pequeño que la tasa sale disparada (50xp en 5s son 36000 xp/h) —
  `ComputeXPRate` devuelve `nil` y `FormatXPRate` lo convierte en `"-"`.
  Un numerador a 0 con tiempo transcurrido de sobra sigue siendo una
  tasa real de `0` (no un guion): el guion es solo por denominador
  pequeño, nunca por xp pequeña o nula.
- **Respeta `includeRested`**: `Ledger.ComputeHeadlineRates` recibe el
  toggle (`LedgerDB.includeRested`) y lo reenvía a `Ledger.TotalXP`/
  `Ledger.TotalXPAcrossSessions` para las dos tasas (sesión y nivel) —
  mismo significado que en el resto del addon (ver "Series
  declarativas" arriba), nunca una lógica aparte aquí.
- **Refresco**: `C_Timer.NewTicker(1, Ledger.RefreshRateFrame)`, un
  ticker propio de este fichero (independiente de los dos ya existentes
  en `ui/xp_capture.lua` — el addon ya tenía más de un ticker de 1s a
  la vez antes de esto, cada uno con su responsabilidad propia).
  `RefreshRateFrame` no hace nada si el frame está oculto
  (`frame:IsShown()`), y si el panel al pasar el ratón está abierto en
  ese momento, también lo redibuja — para que no se quede desfasado
  mientras el jugador lo tiene abierto.
- **Movible, posición persistida**: `frame:RegisterForDrag` +
  `OnDragStop` guardan `LedgerDB.ratePos` (mismo patrón que
  `ui/frame.lua: SavePosition`). **A propósito, sin entrada en
  `Ledger.DEFAULTS`**: mientras `LedgerDB.ratePos` sea `nil`
  (nunca arrastrado), `Ledger.RestoreRatePosition()` vuelve a anclar
  encima de la barra de xp por defecto; en cuanto el jugador lo
  arrastra una vez, esa posición absoluta pasa a mandar en cada login,
  igual que la posición del panel principal.
- `/ldg rate` alterna `LedgerDB.rateShown` y muestra/oculta el frame.

**Panel al pasar el ratón** (`ui/rate_frame.lua`, frame propio —
`LedgerRateHoverPanel` — **nunca `GameTooltip`**, a diferencia de la
barra de xp/tiempo): construido a partir de una estructura genérica de
secciones que vive en `core/rate.lua`, pensada para crecer sin
rehacerse.

- **`Ledger.BuildRatePanelSections(rates)`** (pura, `rates =
  { sessionRate=, levelRate= }` ya calculado por
  `Ledger.ComputeHeadlineRates`): devuelve `{ { title=, rows = {
  {label=, value=, color=}, ... } }, ... }` — hoy una única sección
  `"XP/hour"` con dos filas (`"This session"`, el mismo número que el
  frame principal, en `Ledger.RATE_HIGHLIGHT_COLOR` blanco; `"This
  level"`, en `Ledger.RATE_DEFAULT_COLOR` gris claro). Añadir el
  histórico de últimos niveles o un desglose por origen más adelante es
  añadir otra entrada a esta lista — `ui/rate_frame.lua:
  RenderHoverPanel` recorre secciones y filas genéricamente, sin
  asumir cuántas hay de cada.
- **Colores propios, no `Ledger.PALETTE`**: `RATE_HIGHLIGHT_COLOR`/
  `RATE_DEFAULT_COLOR` viven en `core/rate.lua`, no en
  `ui/palette.lua` — son sobre énfasis visual (fila destacada vs. el
  resto), no identidad de src/bucket, y `core/` debe seguir siendo
  cargable y testeable en solitario (regla dura de
  `core/series.lua`), nunca dependiendo de nada que defina `ui/`.
- **Render**: pool de `FontString` reutilizables
  (`ui/rate_frame.lua: GetOrCreateLine`, mismo patrón de pool que la
  barra de xp) — nunca se crean ni destruyen por evento, las sobrantes
  de un render más corto que el anterior simplemente se ocultan. El
  panel se redimensiona a su contenido (`hoverPanel:SetSize`) igual que
  el número principal.
- `lastRates` (local a `ui/rate_frame.lua`) cachea el último cálculo
  del ticker: `OnEnter` reutiliza ese valor en vez de recalcular — el
  ticker ya lo mantiene fresco con menos de un segundo de margen.

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

### Reconciliación (`core/check.lua` + `ui/check_frame.lua`, `/ldg check`)

Comprueba si lo que Ledger ha registrado cuadra con lo que el juego dice
que es real, y deja cada discrepancia marcada. Mismo reparto que
`core/state_dump.lua`: `Ledger.BuildCheck(charDB, player)` es lógica pura
(`player = { level=, xp= }`, leídos por la UI con `UnitLevel`/`UnitXP`;
`core/` no toca ninguna API de WoW) y devuelve `{ discrepancies=,
lines = { { status=, text= }, ... } }`; `Ledger.FormatCheck(result)` lo
pinta a texto plano; `ui/check_frame.lua` solo lee los valores vivos y
muestra el texto. Tests en `spec/check_spec.lua`.

- **Estados de línea**: `title` (siempre la primera: el veredicto global,
  `ALL OK` o `N DISCREPANC(Y|IES) FOUND`), `section`, `info`, `ok`,
  `bad` (discrepancia: la única que cuenta para el veredicto) y `skip`
  (no verificable por falta de datos: ni cuenta como discrepancia ni se
  da por buena en silencio). Marcas **de texto, no códigos de color**:
  el panel es un EditBox pensado para copiar con Ctrl+C y los escapes
  acabarían en el portapapeles. `bad` → `>>> [!!] `, `ok` → `    [OK] `,
  `skip` → `    [??] `.
- **Nivel actual**: xp registrada (suma de la serie de TODAS las sesiones
  del nivel, xp cruda, nunca afectada por `includeRested`) frente a
  `UnitXP`. `diff = registrado - real`: **positivo → doble
  contabilización, negativo → eventos perdidos**. Con segmento gris
  inicial (`sessions[1].initialXP > 0`) se muestra su valor y la
  diferencia sin descontar (solo informativa: se espera que valga
  `-initialXP`) y el veredicto usa `registrado + initial - real`. Se
  marca también si el nivel de las sesiones no coincide con el del
  jugador. Cualquier xp `unknown` en el desglose por origen cuenta como
  discrepancia (evento sin fuente emparejada).
- **Niveles cerrados, xp**: por cada `levels[n]` (orden ascendente),
  `suma(bySource) + initialXP` frente a `entry.xpRequired`. Se usa
  `bySource` y no `totalXP` porque este depende del `includeRested` que
  hubiera al cerrar (no se guarda). Un nivel sin `xpRequired` (cerrado
  antes de guardarlo) sale como `skip`.
- **Niveles cerrados, tiempo**: `entry.totalPlayed` frente a
  `nextReached - entry.reached`, donde `nextReached` sale de
  `levels[n+1].reached` o, si `n+1` es el nivel en curso, de
  `sessions[1].reached`. Solo se marca la dirección imposible: jugado
  MAYOR que el tiempo de reloj entre dings (más `Ledger.TIME_TOLERANCE`
  = 60s de margen), MENOR que la suma de los buckets, o con una curva
  demasiado larga (invariantes de `core/level_time.lua`, ver "Invariantes
  del tiempo jugado"); jugado menor que el tiempo entre dings, sin más,
  es normal (tiempo desconectado no cuenta) y se muestra como dato.
  También se marca si los dings salen desordenados. `reached = 0`, `n+1` sin seguimiento o sin `reached`
  → `skip`. Un nivel con `timeUnreliable` (o sin `totalPlayed`) también
  → `skip`, "no reliable played-time data", explícitamente no un error
  del addon (ver "`totalPlayed` de un nivel"). Sospechoso principal de
  un desfase real: la base `levelStartTotalPlayed` desalineada (ver
  "Pendiente").
- **Xp pendiente de emparejar** (hasta ~1s dentro del matcher) puede
  verse como un negativo transitorio justo tras un kill o un ding: la
  ventana lo avisa en sus notas; el botón `Refresh` la relee.
- **Ventana**: `ui/text_window.lua: Ledger.CreateTextWindow(opts)` es la
  fábrica compartida con `/ldg export` (frame movible/redimensionable +
  EditBox multilínea de solo lectura en un ScrollFrame, contenido ya
  seleccionado con `HighlightText` en cada `SetText`, Escape por
  `UISpecialFrames` y por `OnEscapePressed`). `ui/export_frame.lua` y
  `ui/check_frame.lua` solo añaden sus botones y su contenido.
  `ui/debug_frame.lua` conserva su propia copia del patrón (autorefresco,
  otro layout).

**Pendiente de verificar en el juego** (nunca probado): que la ventana
se abra, se pueda mover/redimensionar, quede el texto seleccionado y
Escape la cierre — es exactamente el mismo mecanismo que `/ldg export`,
que tampoco está confirmado; y que tras refactorizar `/ldg export` sobre
la fábrica siga comportándose igual. Los niveles cerrados con esta
versión ya llevan `xpRequired`/`initialXP`; los anteriores saldrán como
`skip` en la comprobación de xp.

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
  `RequestTimePlayed`, `UnitOnTaxi`, `GetUnitSpeed`, `UnitAffectingCombat`,
  `UnitIsDeadOrGhost`, `GetTime`, orden fijo — esta última no alimenta
  el muestreo de estado sino la estimación del tiempo jugado, ver
  "`totalPlayed` de un nivel"): cada una se marca `absent` si el
  global no es una función, o si lo es, se llama con `pcall` (con
  `"player"` como único argumento las que lo necesitan) y se marca
  `present, value = ...` con cada valor devuelto (`tostring` de cada
  uno, recortando los `nil` finales — así `RequestTimePlayed`, que no
  devuelve nada, sale como "no return value" en vez de una fila de
  `nil`s) o `present, call failed (...)` si `pcall` atrapó un error.
  Las 4 últimas (`UnitOnTaxi`/`GetUnitSpeed`/`UnitAffectingCombat`/
  `UnitIsDeadOrGhost`) alimentan de verdad el muestreo crudo de estado
  (`ui/xp_capture.lua: SampleTimeState`, ver "Buckets de tiempo"
  arriba) — no son solo una curiosidad de cara al futuro, por eso vale
  la pena comprobarlas en cualquier cliente nuevo al que se porte el
  addon.
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
  `barShown`/`barHeight`/`timeBarShown` (barras). `version` está en 8
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
  - v5→v6 (rediseño de los buckets de tiempo, ver "Buckets de tiempo"
    arriba): `session.buckets` desaparece por completo (se pone a `nil`
    si existía) y se garantiza una serie de estado vacía (entonces `session.st`, hoy `session.stateSeries`) si no existiera ya —
    las sesiones en curso nunca vuelven a acumular buckets, solo
    muestrean crudo. Los niveles ya cerrados (`db.levels`) reciben
    `entry.stateSeries = {}` y `entry.buckets` recién puesto a cero en
    la forma nueva (`active`/`downtime`/`travel`/`dead`): el reparto
    viejo (`active`/`idle`/`travel`/`dead`) clasificaba una señal
    distinta (un tracker en vivo con reclasificación retroactiva) y no
    es traducible a las reglas nuevas, así que no hay forma de
    reconstruirlo retroactivamente — mismo criterio que `rested = 0` en
    v2→v3.
  - v6→v7 (análisis del SavedVariables real, 2026-09-18): la serie
    cruda solo vive en el nivel en curso. Las sesiones en curso mueven
    `session.st` a `session.stateSeries` (sin perder muestras; no pisa
    una `stateSeries` que ya exista). Los niveles ya cerrados
    DESCARTAN su `stateSeries` (los `buckets` ya derivados se quedan) y
    reciben `entry.thresholds` con los umbrales vigentes solo si tenían
    muestras (sus buckets se derivaron con esas constantes); un nivel
    con serie vacía (migrado desde v5, buckets a cero) no tiene
    umbrales conocidos y se queda sin el campo.
  - v7→v8 (bug del tiempo jugado del primer nivel tras wipe/instalación
    nueva, ver "`totalPlayed` de un nivel"): la base de tiempo jugado
    pasa de "0 por defecto" a "nil = desconocido".
    `lastKnownTotalTimePlayed = 0` (solo pudo significar "nunca
    recibido") vuelve a nil. `levelStartTotalPlayed = 0` se conserva
    únicamente si el nivel en curso es el 1 (el personaje de verdad no
    había jugado nada); en cualquier otro nivel es el bug, y vuelve a
    nil SIN resembrarse con el próximo `TIME_PLAYED_MSG` (sería más
    tarde que el inicio real del nivel): ese nivel se cierra con
    `timeUnreliable`. **Ampliado**: cualquier `levelStartTotalPlayed`
    distinto de cero en datos v7 también vuelve a nil (excepto el 0 de un
    personaje en nivel 1), porque toda base escrita por una versión
    anterior a 0.8.0 iba una respuesta por detrás (ver "Causa de fondo").
    Supuesto: ningún dato v8 procede de la 0.8.0 con base cacheada (esa
    versión, igual que la 0.7, copiaba el `lastKnown` sin extrapolar y
    tampoco es fiable; solo la 0.9.0 escribe bases correctas). Los
    niveles ya cerrados no se tocan.
- `LedgerCharDB` (por personaje, `## SavedVariablesPerCharacter`):
  `{ version, levels, sessions, lastKnownTotalTimePlayed,
  levelStartTotalPlayed }` (los dos últimos, sin default y `nil` =
  desconocido; ver "`totalPlayed` de un nivel" arriba). Se inicializa en `ADDON_LOADED` con `LedgerCharDB =
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

- `tEnd` ya lo refresca el ticker de 1s en la sesión activa (ver "Sesión
  activa"), así que tras un logout/desconexión sin pasar por reset queda
  en el último segundo visto; al próximo login la sesión sigue abierta
  y se le sigue añadiendo eventos (y el ticker vuelve a moverle `tEnd`).
  Sigue sin decidir si al reabrir tras un hueco largo conviene abrir una
  sesión nueva en vez de continuar la vieja.
- **Comprobar en el juego `totalPlayed` tras el análisis del
  SavedVariables real** (2026-09-18): se observó `levelStartTotalPlayed=3534`
  con `lastKnownTotalTimePlayed=4343` (diferencia 809 = duración ya
  registrada del nivel anterior, es decir, base un nivel por detrás).
  El código de `CloseCurrentLevel` ya calcula `totalPlayed` con la base
  vigente y DESPUÉS la avanza al total actual desde `1e8a942`, así que
  se sospecha una build desplegada anterior; `CloseCurrentLevel` ahora
  loguea a TRACE `lastKnown`/`levelStart` de cada cierre y el avance de
  la base para poder confirmarlo. (La causa que se sospechaba como
  alternativa, un `lastKnownTotalTimePlayed` obsoleto en el instante del
  cierre, ya está resuelta: se extrapola con `GetTime()`, ver
  "Estimación entre respuestas" en "`totalPlayed` de un nivel".)
- **Verificar en el juego el arreglo de la base desconocida** (nunca
  probado con el cliente real; solo con tests): tras `/ldg wipe confirm`
  y tras una instalación nueva a mitad de nivel, que el TRACE
  `TIME_PLAYED_MSG ... seeded the played-time baseline` salga una vez y
  que el primer nivel cerrado tenga un `totalPlayed` cercano al tiempo
  entre dings (no al total del personaje); que un nivel que cierra antes
  de la respuesta salga con `time=unknown` en `/ldg dump` y como `[??]`
  en `/ldg check`. Y la estimación por `GetTime()` (nunca probada en el
  cliente real): que un nivel cerrado bastante después de la última
  respuesta dé un `totalPlayed` cercano al tiempo entre dings (el TRACE
  `LevelClose` muestra `estimated total=... [cached=..., received Ns
  ago]`), y que con `/ldg probe` se pueda contrastar qué reloj es
  `GetTime()` (ver "Estimación entre respuestas").
- El sobrante de un cruce de nivel hereda el `src` del evento original
  (`EmitCrossingEvent` usa `paired.src` en las dos mitades): un sobrante
  `explore` en `off=0` del nivel nuevo solo puede venir de que el evento
  original ya saliera mal clasificado (el bug quest→explore corregido
  por cantidad, ver "Captura de eventos"), no de reclasificar el
  sobrante. Confirmar con datos nuevos.
- Confirmar en el juego (con la instrumentación TRACE) que la corrección
  del bug `src = "unknown"` (ver "Sistema de log" arriba) funciona con
  el resto de variantes reales de este cliente, no solo con el caso del
  bono por descanso ya reproducido en tests.
- Confirmar en el juego el emparejamiento de `QUEST_TURNED_IN` por
  cantidad exacta (ver "Captura de eventos", "QUEST_TURNED_IN y
  prioridad sobre explore" arriba, corregido 2026-09-18, solo probado
  con tests): que las entregas de quest ya no se clasifiquen como
  "explore" en ningún caso real, revisando el TRACE `ExploreCheck:` de
  varias entregas seguidas y alguna con un kill simultáneo de verdad.
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
- **Verificar en el juego el muestreo crudo de estado, rediseñado
  2026-09-18** (nunca probado con datos reales): que
  `UnitAffectingCombat`/`GetUnitSpeed`/`UnitIsDeadOrGhost`/`UnitOnTaxi`
  se comporten como se asume en `ui/xp_capture.lua: SampleTimeState` en
  ambos clientes (`/ldg probe` ya los incluye, ver "Diagnóstico de
  compatibilidad"); que `Ledger.ComputeBucketsFromState` clasifique bien
  en vivo (el hueco corto tras combate sigue contando `"active"`, un
  movimiento sostenido pasa a `"travel"` solo tras
  `Ledger.SUSTAINED_MOVEMENT_SECONDS`, la muerte gana siempre); que la
  serie guardada en `session.stateSeries` tenga combinaciones de bits
  (no solo 0/1/2: en un análisis del SavedVariables solo aparecían esos
  tres valores, lo que casaba con una build anterior al muestreo crudo
  — descartar tras redesplegar), y que un nivel recién cerrado no lleve
  `stateSeries` y sí `thresholds`.
- **Muestreo crudo, comprobado sobre exports reales (2026-09-19)**: el
  refactor a estado crudo está completo y el bit de combate SÍ se escribe.
  Un personaje con 51 kills en su sesión tiene `{0: 739, 1: 510, 2: 1366}`
  muestras; otro `{0: 664, 1: 191, 2: 129}`; los buckets `active` de los
  niveles cerrados (796s, 110s) solo pueden salir de muestras con el bit
  de combate. Un nivel en curso con solo `{0, 2}` no es un fallo: su único
  evento (`off=0`, `src=kill`) es el sobrante del cruce de nivel
  (`newPart`) grabado en la sesión nueva, la pelea de ese kill ocurrió en
  la sesión ANTERIOR, y en esos 871s no hubo combate. **Observación sin
  explicar del todo**: en ~700 muestras de combate no aparece nunca el
  valor 3 (combate + movimiento), cuando en la práctica se pelea
  moviéndose; coincide con que `GetUnitSpeed` sea "secret" (y por tanto
  `IsPlayerMoving` degrade a `false`) precisamente en combate. No afecta a
  los buckets (en `ComputeBucketsFromState` el combate gana al
  movimiento), pero conviene confirmarlo mirando `/ldg log show` en busca
  del ERROR único por sesión de `GetUnitSpeed`.
- Ver visualmente en el juego la barra de reparto de tiempo (nunca
  probada): anclaje 2px por encima de la barra de xp, el orden fijo
  active/downtime/travel/dead, los colores (incluidos los que reutilizan
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
- Ver visualmente en el juego el número de xp/hora y su panel al pasar
  el ratón (`/ldg rate`, ver "Número principal de xp/hora" arriba,
  nunca probado): que el anclaje centrado 2px sobre la barra de xp se
  vea bien (incluido cómo queda si la barra de reparto de tiempo
  también está activa — ambas reclaman ese mismo hueco encima de la
  barra de xp, y hoy nada evita que se solapen visualmente más allá de
  que el número tiene una `FrameStrata` más alta); que
  `GameFontNormalHuge` sea legible y el fondo se ajuste bien al texto
  al cambiar de dígitos; que arrastrarlo y volver a entrar al juego
  respete `LedgerDB.ratePos`; y que el guion aparezca de verdad al
  abrir una sesión nueva y desaparezca pasado el minuto.
