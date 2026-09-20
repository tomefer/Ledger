# Ledger

Addon de la línea de producto Classic (Lua 5.1). Se llamaba XPTrack;
renombrado a Ledger — si ves "XPTrack" en algún sitio (código, symlink de
Interface/AddOns, apuntes viejos) es residuo del nombre anterior.

**Multi-cliente desde 2026-09-17**: un solo paquete (`## Interface:
11509, 16001` en `Ledger.toc`; un único fichero en el repo, sin TOCs
separados por flavor) sirve
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
    principal, sufijo de bono por descanso y mensaje de descubrimiento de zona) con su valor literal en
    este cliente (`core/chat_patterns.lua: Ledger.FormatXPGainStrings`).
  - `/ldg rested`: alterna `LedgerDB.includeRested` (si el bono por
    descanso cuenta en `TotalXP`/`CloseLevel`; ver "Series declarativas"
    arriba) y actualiza la etiqueta del panel principal.
  - **Las tres vistas (`/ldg bar`, `/ldg time`, `/ldg rate`) están
    visibles por defecto** (`Ledger.DEFAULTS`: `barShown`, `timeBarShown`,
    `rateShown` = `true`; ver "SavedVariables"). Los comandos siguen
    alternando igual y guardan la elección, que manda en el siguiente
    login.
  - `/ldg bar`: muestra u oculta la barra de composición de xp del
    nivel, que ocupa el sitio de la barra de xp nativa (ver "Barra de
    composición de xp" más abajo). Informa directamente por chat de si
    se ha podido anclar y cuántos segmentos hay (sin depender de que el
    log esté activo): si no hay ninguno todavía es que no hay xp
    registrada en el nivel actual, no un fallo.
  - `/ldg native`: alterna `LedgerDB.replaceNative` (`true` por defecto):
    con él apagado la barra de xp nativa recupera su relleno y la barra de
    composición vuelve a ponerse ENCIMA de ella (1px de hueco, altura
    `barHeight`) — la salida de emergencia si algo falla al sustituirla.
    Informa por chat de qué pasó con el relleno nativo (`hidden` /
    `overlay only` con el motivo / `visible`). Ocultar la barra de
    composición con `/ldg bar` también devuelve el relleno nativo.
  - `/ldg time`: muestra u oculta la barra de actividad del nivel
    (combat/non-combat/travel/dead, siempre en porcentaje de muestras),
    independiente de `/ldg bar` (ver "Barra de actividad" más abajo).
  - `/ldg rate`: muestra u oculta el número destacado de xp/hora de la
    sesión actual, anclado encima de la pila de barras visibles (ver
    "Número principal de xp/hora" más abajo);
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
  - `/ldg check`: muestra u oculta la ventana de reconciliación de la xp
    registrada frente a la real, con el `/played` como dato informativo
    (`ui/check_frame.lua`, ver "Reconciliación" más abajo).
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
  desplegada y la hora. Los dos flavors despliegan el `.toc` tal cual (0.11.6–0.11.7 desplegaban
  en la beta un `.toc` con solo `## Interface: 16001`; se quitó al demostrar
  que no influía, ver "SavedVariables en la beta"). **Hay que ejecutarlo (con el flavor que toque)
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
`Ledger.CloseLevel(sessions, includeRested, xpRequired, levelTicks)` (totales y
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
    tEnd    = <time() ABSOLUTO del cierre de la sesión, fijado solo por
               /ldg reset (nil en la activa). Un sello de fecha, no una
               métrica: nada calcula con él>,
    level   = <nivel del jugador al iniciar la sesión>,
    reached = <time() ABSOLUTO del instante en que se empezó a rastrear
               este nivel: el ding real si lo disparó una subida de
               nivel, o el instante de arranque si es la primera sesión
               en frío (mismo tipo de aproximación que initialXP: no se
               puede saber el ding real de antes de instalar el addon).
               Un sello de fecha, no una métrica>,
    mode    = <"farm" | "quest" | "dungeon" | nil>,  -- informativo; NUNCA
                                                       -- sobrescribe ni
                                                       -- altera el src de
                                                       -- ningún evento
    manual  = <true si se abrió con /ldg reset, false en las demás>,
    deaths  = 0,  -- contador de muertes DE ESTA SESIÓN (PLAYER_DEAD),
                   -- aparte del contador de actividad "dead": cuántas
                   -- muestras se pasó muerto no dice cuántas veces.
    ticks   = { combat = 0, nonCombat = 0, travel = 0, dead = 0,
                total = 0 },
                   -- contadores de actividad DE ESTA SESIÓN, incrementados
                   -- en vivo por el muestreador (ver "Muestreo de
                   -- actividad" abajo). Nunca una serie ni un array por
                   -- tick, y nunca un porcentaje persistido.
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

### Muestreo de actividad (`core/ticks.lua`)

**Reescrito desde cero 2026-09-19; sin retrocompatibilidad** (lo anterior
— tracker con reclasificación, serie cruda `stateSeries`, umbrales de
"downtime"/"movimiento sostenido", buckets derivados, `totalPlayed` y todo
el modelo de tiempo jugado del personaje — se ha borrado entero).

**El ticker es un MUESTREADOR, no un reloj.** Cada segundo
(`ui/xp_capture.lua: SampleTimeState`) lee el estado instantáneo del
jugador, `Ledger.ClassifyActivity` lo convierte en UNA sola clave, y el
contador de esa actividad sube en uno. Nada más: no se guarda nada por
tick, no hay serie temporal de estado, no hay umbrales ni suavizado, no
hay aritmética de tiempo de pared.

Los contadores son **cuentas de muestras, no segundos garantizados**: si
el cliente no está en primer plano (o cerrado) el ticker no corre, y eso
es correcto por diseño — mide el tiempo que el addon realmente observó.

**Forma de los contadores** (`Ledger.NewTicks()`), la misma para una
sesión (`session.ticks`), para el nivel en curso (`LedgerCharDB.levelTicks`)
y para un nivel cerrado (`levels[n].ticks`):

```lua
ticks = {
    combat    = 0,
    nonCombat = 0,
    travel    = 0,
    dead      = 0,
    total     = 0,   -- suma de los cuatro, mantenida al incrementar
}
```

**Clasificación** (`Ledger.ClassifyActivity(state)`, pura;
`state = { dead=, combat=, moving=, taxi= }`): actividades mutuamente
excluyentes, una sola clave por muestra, por prioridad:
1. muerto → `dead` (un cadáver no está "en combate", ni siquiera a mitad
   de pelea);
2. en combate → `combat`;
3. en movimiento → `travel` (a pie, `GetUnitSpeed`, o en taxi,
   `UnitOnTaxi`: ir en taxi también es moverse);
4. resto → `nonCombat`.

**Un tick** (`Ledger.RecordActivityTick(session, levelTicks, state)`):
clasifica UNA vez y cuenta esa misma clave, con `Ledger.CountTick`
(`ticks[clave] += 1`, `ticks.total += 1`; una clave desconocida es un
error, no se rompe el total en silencio), **en vivo sobre las dos
tablas**: la de la sesión activa y la del nivel en curso. Así un crash
pierde como mucho los ticks desde el último guardado, no el nivel
entero, y no hay nada que calcular al cerrar.

**Al cerrar nivel** los contadores del nivel (`LedgerCharDB.levelTicks`)
pasan tal cual a `entry.ticks` (por referencia, `Ledger.CloseLevel`), y
`CloseCurrentLevel` empieza un `levelTicks` nuevo. Sin agregación ni
recálculo posterior: no queda ninguna serie de la que recalcular. Un
`/ldg reset` abre una sesión con sus propios contadores nuevos, y los del
nivel siguen contando a través del reset.

**Se muestra siempre en PORCENTAJE** (`Ledger.TickPercent(ticks, clave)` =
`ticks[clave] / ticks.total * 100`, 0 si no hay muestras): sobre el total
de muestras del nivel o de la sesión. Nunca en valores absolutos, para no
invitar a cuadrarlos con nada externo (el `/played`, el reloj). Los
tiempos que sí muestra el panel del número de xp/hora (`/ldg rate`) ya
no salen de las muestras: son relojes exactos, aparte (ver "Número
principal de xp/hora"). Un porcentaje se deriva al mostrar y NUNCA se
persiste. Formateadores puros:
`Ledger.FormatTickLines` (una línea por actividad, para la barra) y
`Ledger.FormatTickSummary` (una línea, para `/ldg dump` y `/ldg check`).
(Los volcados de datos, `/ldg export`, sí escriben los contadores crudos:
son el dato, no una presentación.)

**Movimiento y `GetUnitSpeed` "secret"** (confirmado 2026-09-18 en la beta
de WoW Forever, build 1.60.1): ese cliente marca el valor devuelto por
`GetUnitSpeed` como "secret" — la llamada no falla, pero compararlo
(`> 0`) revienta con `attempt to compare a secret number value`.
`ui/xp_capture.lua: IsPlayerMoving()` envuelve también la comparación en
su propio `pcall` y degrada a "no se mueve" con un aviso ERROR una vez
por sesión: es una pérdida real de datos (la actividad `travel` a pie no
se puede detectar mientras dure). En datos reales de esa beta no aparece
nunca la combinación combate+movimiento en ~700 muestras de combate, lo
que coincide con que el valor sea "secret" precisamente en combate; no
afecta al reparto (el combate gana al movimiento en la prioridad), pero
falta confirmarlo mirando `/ldg log show`. Sin confirmar si Classic Era
(1.15.x) tiene el mismo tainting.

### Entrada de `levels` (`core/level_close.lua: CloseLevel(sessions, includeRested, xpRequired, levelTicks)`)

```lua
levels[level] = {
    level       = <nivel>,
    reached     = <time() absoluto del ding que llevó a este nivel, o del
                   arranque si fue el primer nivel rastreado en frío
                   (sessions[1].reached). Un sello de fecha, no una
                   métrica>,
    initialXP   = <xp que el jugador ya llevaba en el nivel antes de que
                   el addon empezara a rastrearlo (sessions[1].initialXP,
                   0 si no hubo): la xp registrada + initialXP es lo que
                   debe sumar xpRequired. Solo el primer nivel rastreado
                   en frío lo tiene distinto de 0>,
    xpRequired  = <xp que ese nivel requería para completarse
                   (UnitXPMax del nivel viejo, `crossing.oldMax` de
                   Ledger.ComputeXPDelta, pasado por CloseCurrentLevel).
                   Puede faltar si el cierre no vino de un cruce con
                   oldMax conocido: /ldg check lo marca entonces como "no
                   verificable", no como discrepancia>,
    totalXP     = <suma de la xp EFECTIVA de todas las sesiones del
                   nivel, xp o xp-rested segun includeRested (true por
                   defecto); ver Ledger.EffectiveXP arriba>,
    totalRested = <suma del bono por descanso real, SIN toggle: no
                   cambia con includeRested>,
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
    ticks       = { combat = 0, nonCombat = 0, travel = 0, dead = 0,
                    total = 0 },
                    -- los contadores de actividad del nivel
                    -- (LedgerCharDB.levelTicks, incrementados en vivo),
                    -- tal cual: sin agregar ni recalcular. Recuentos de
                    -- muestras; se muestran siempre en porcentaje
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
  SavedVariable, sin ningún paso de guardado aparte. Los contadores de
  actividad (`session.ticks`, `LedgerCharDB.levelTicks`) tampoco tienen
  paso de guardado: se incrementan en vivo sobre la propia tabla
  guardada. El matcher sí vive solo en memoria (no se persiste — ver
  "Pendiente" más abajo).
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
  junto al matcher (solo en memoria, no se
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
- **Exploración: mensaje de sistema, no de combate** (log real
  2026-09-19: una cueva dio 70 de xp y no llegó NINGÚN
  `CHAT_MSG_COMBAT_XP_GAIN`, así que la cantidad se soltó como
  `"unknown"`): el descubrimiento de zona se anuncia por
  `CHAT_MSG_SYSTEM` con `ERR_ZONE_EXPLORED_XP` ("Discovered %s: %d
  experience gained"). `ui/xp_capture.lua` construye su patrón al cargar
  (`Ledger.exploreStrings`, mismo `Ledger.BuildPattern` que los demás),
  `Ledger.ExtractExploreXP` (`core/chat_patterns.lua`, pura) saca la
  cantidad (último grupo: el nombre del área va antes) y se encola como
  fuente `"explore"` con esa cantidad como `expectedXP`, igual que una
  quest. Por eso el emparejamiento por cantidad exacta de `AddAmount`/
  `AddSource` ya no mira `src == "quest"`: vale para cualquier fuente con
  `expectedXP` (una muerte simultánea no le roba la xp a la exploración).
  `ERR_ZONE_EXPLORED` (sin xp, nivel máximo) no se usa: no hay cantidad que
  emparejar. **Sin confirmar en el juego**: que sea `CHAT_MSG_SYSTEM` en
  ambos clientes — cada mensaje de sistema se loguea a TRACE
  (`CHAT_MSG_SYSTEM ... area discovery` / `... ignored`) y `/ldg strings`
  imprime el global string.
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
3. Llama a `CloseCurrentLevel(t, xpRequired)`: `Ledger.CloseLevel`
   (agrega la xp de las sesiones y adjunta `LedgerCharDB.levelTicks` como
   `entry.ticks`, tal cual) + `Ledger.RecordLevelClose`, empieza un
   `levelTicks` nuevo, y abre la sesión del nivel nuevo (`reached =
   time()`), reiniciando `matcher`/`reconciler` (el muestreo de actividad
   sigue su curso solo, contando en la sesión que esté activa en cada
   momento).
4. Graba `new` (mismo `src`) en la sesión recién rotada, en offset 0.

Como ya no hace falta "adivinar" si hay un evento en camino que vaya a
explicar la xp del nivel nuevo (siempre lo hay: es la propia entrada
`new` de arriba), la sesión nueva **nunca** snapshotea `initialXP` en
este camino — solo lo hace el arranque en frío de verdad
(`StartTracking` cuando `#sessions == 0`, ver "Barra de composición de
xp").

Diagnóstico: `CloseCurrentLevel` loguea a TRACE el nivel cerrado,
sesiones agregadas, `totalXP`, muestras totales y `muertes`.

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
(mismas series, mismos contadores de actividad: los suyos propios, nuevos).

### `/played`: dato informativo, nunca una fuente

**Sin tiempo jugado del personaje, sin línea base, sin estimación por
`GetTime`, sin estado "no fiable" y sin invariantes de tiempo** (todo eso
se borró 2026-09-19 junto con `totalPlayed`; el historial de por qué no
funcionaba — una línea base copiada antes de que llegara la respuesta —
queda en git). Los contadores de actividad (ver "Muestreo de actividad")
son lo que son y no se contrastan con nada.

Lo único que queda de `/played`:
- `TIME_PLAYED_MSG` (`arg2` = tiempo jugado en el nivel actual) se guarda
  en su propio campo, `LedgerCharDB.played = { level=, seconds=, samples=
  }` (`Ledger.RecordPlayedReading`, `core/ticks.lua`), junto con cuántas
  muestras tenía el nivel en ese instante (para poder compararlos sin que
  el tiempo que pase entre la petición y la lectura los desfase) y el
  nivel del jugador al llegar la respuesta.
- **No participa en ningún cálculo ni en ninguna métrica.** El único
  lector de `LedgerCharDB.played` es `/ldg check`, como línea informativa
  (ver "Reconciliación").
- **Además, una referencia SOLO EN MEMORIA** (`Ledger.levelPlayedRef =
  { level=, seconds=, receivedAt= }`, `Ledger.NewLevelPlayedRef`,
  `core/rate.lua`; asignada en el handler de `TIME_PLAYED_MSG` con el
  `time()` de la recepción, nunca persistida, nunca dentro de `levels` ni
  `sessions`): la lee el panel de `/ldg rate` para el tiempo jugado del
  nivel (ver "Número principal de xp/hora"). Cada respuesta **reemplaza**
  la referencia, nunca se acumula (tras un `/reload` el valor nuevo ya
  incluye lo anterior). Es solo para mostrar: no alimenta ningún xp/hora ni
  otra métrica, y no es una línea base persistida.
- Se pide (`RequestTimePlayed`, siempre envuelto en `pcall`:
  `Ledger.RequestPlayedReading`) en `PLAYER_ENTERING_WORLD`, en
  `PLAYER_LEVEL_UP` (el contador del nivel se reinicia en el servidor),
  tras un `/ldg wipe confirm` y al abrir o refrescar la ventana de
  `/ldg check`; al llegar la respuesta con esa ventana abierta se vuelve a
  pintar. No se pide al cerrar nivel desde el cierre en sí (en ese instante
  daría ~0; la petición del `PLAYER_LEVEL_UP` solo sirve para el reloj del
  panel de rate). Cada respuesta imprime además la línea de "tiempo
  jugado" de Blizzard en el chat, como siempre.

### Barra de composición de xp (`core/xp_bar.lua` + `ui/xp_bar.lua`, `/ldg bar`)

Barra de segmentos que **sustituye visualmente a la barra de xp nativa**
(`LedgerDB.replaceNative`, `true` por defecto), un color por tramo de
`src`, que representa de qué vino la xp del nivel actual. Eje X: 0 a
`UnitXPMax("player")`.

- **Sustitución de la nativa** (`ui/xp_bar.lua: AnchorToNativeBar` +
  `ApplyNativeFill`): el frame se ancla a las DOS esquinas de la barra
  nativa resuelta (`TOPLEFT`/`BOTTOMRIGHT` sobre las suyas), así que
  toma su posición y tamaño exactos y los sigue en vivo; toma su misma
  `FrameStrata` y un `FrameLevel` 10 por encima, para dibujarse encima
  y ganar el ratón. **Se oculta solo el relleno de la nativa, nunca su
  contenedor** (su geometría es el ancla y la referencia de tamaño, y su
  fondo/pista se queda): es la textura del `StatusBar` de la barra de xp
  (`GetStatusBarTexture():SetAlpha(0)`), sin quitar, reparentar ni
  enganchar nada, así que el código del sistema de barras de seguimiento
  de Blizzard sigue funcionando igual y restaurar es devolver el alfa.
  El `StatusBar` se busca sobre la barra resuelta, su `.StatusBar` y sus
  hijos, y se identifica por rango (`GetMinMaxValues` == `UnitXPMax`,
  como `FindMatchingChild`, para no coger la reputación). Cada paso está
  en `pcall` y se verifica (el alfa tiene que quedar en 0). **Si no se
  puede ocultar limpiamente, degrada a superponerse** (que es lo que ya
  hace el frame por su nivel superior; la parte rellena de la nativa
  queda tapada por los segmentos opacos) y deja el motivo — incluida la
  descripción de con qué está construida la barra nativa — en
  `Ledger.nativeFillInfo = { status=, detail= }` (`hidden` /
  `overlay only` / `visible` / `n/a`), que lee `/ldg native` y
  `/ldg probe` y se loguea a INFO cuando cambia. El relleno solo está
  oculto mientras la barra de composición esté visible Y sustituyendo:
  `OnShow`/`OnHide` y cada `RedrawXPBarFull` lo re-aplican (siempre
  restaurando primero: idempotente).
- **Altura**: en modo sustitución la del frame es la de la barra nativa;
  los segmentos se anclan a los bordes superior e inferior del frame (no
  copian su altura al pintar: al hacer login la nativa puede no tener aún
  layout). `LedgerDB.barHeight` solo cuenta con `/ldg native` apagado y
  para la barra de actividad.
- **Sin ratón propio**: el ratón lo lleva la zona de hover única de
  `ui/bars_hover.lua` (ver "Zona de hover unificada"), que reenvía el
  arrastre del modo degradado (`Ledger.StartXPBarDrag`/`StopXPBarDrag`).
  Tapar la nativa con esa zona anula sus tooltips nativos: es lo que
  implica sustituirla.
- **Label de xp al pasar el ratón** (`Ledger.ShowXPBarLabel`/
  `HideXPBarLabel`): `"{xp actual} / {xp del nivel}"` (`Ledger.FormatXPLabel`,
  pura, con separador de miles), centrado y en blanco sobre la barra, como
  el texto de la nativa; no se muestra en nivel máximo.

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
- **Tooltip**: ya no es propio de la barra. Es la primera sección del
  tooltip unificado de las dos barras (ver "Zona de hover unificada"):
  el desglose de xp por origen (`Ledger.XPBySourceAcrossSessions`, helper
  puro de `core/events.lua` que suma `XPBySource` de varias sesiones —
  todas las del nivel en curso, igual que la barra, nunca solo la activa)
  más el total de bono por descanso si lo hay.
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
- **Redibujado al cambiar el ancho** (`ui/xp_bar.lua`, 2026-09-19): los
  segmentos son offsets/anchuras absolutas en píxeles calculadas con el
  ancho de la barra nativa EN ESE INSTANTE; el frame sí sigue a la barra
  nativa en vivo (anclado por las dos esquinas) pero las texturas de
  dentro no. Si la barra nativa aún no tenía su layout final al hacer
  login tras un `/reload` (ancho 0), todos los segmentos salían de 0px y
  la barra era invisible hasta subir de nivel: los eventos de xp solo
  repintan el ÚLTIMO segmento y solo `PLAYER_LOGIN`/`PLAYER_ENTERING_WORLD`/
  `UI_SCALE_CHANGED` hacían redibujado completo (la barra de actividad no
  lo sufría: se redibuja cada segundo). Ahora `lastPaintedWidth` guarda el
  ancho del último pintado completo y un `OnSizeChanged` del frame, más
  una comprobación al principio de `ExtendXPBar` como red de seguridad,
  disparan `RedrawXPBarFull` si el ancho difiere (tolerancia 0.5px;
  `redrawing` evita la reentrada desde el `SetSize` de
  `AnchorToNativeBar`). Reproducido con un cliente simulado, **sin
  confirmar en el juego**: en el log TRACE tras un `/reload`, líneas
  `RedrawXPBarFull: width=0px` seguidas de `OnSizeChanged: ... full
  redraw` lo confirmarían.
- **Altura configurable**: `LedgerDB.barHeight` (`Ledger.DEFAULTS.barHeight
  = 8`), sin comando todavía para cambiarla (solo editando la
  SavedVariable a mano). Es la altura de la barra de actividad y la de
  esta con `/ldg native` apagado; sustituyendo la nativa manda la de esta.
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
  (`inDegradedMode`; el ratón lo lleva siempre la zona de hover, que
  reenvía el arrastre) decide si `Ledger.StartXPBarDrag` hace algo o no. Se avisa una única vez por sesión a
  nivel INFO (`Ledger.Log("info", ...)`, nunca ERROR: es un modo
  soportado, no una rotura) la primera vez que se degrada.
- **Nunca constantes**: tanto en modo nativo como degradado, la
  anchura y posición salen siempre del frame resuelto
  (`nativeBar:GetWidth()`) o de la SavedVariable/default degradados —
  ninguna constante de anchura hardcodeada salvo
  `Ledger.DEFAULTS.barDefaultWidth`, que es explícitamente el valor de
  emergencia, no el camino normal.
- **La barra se ancla aunque esté oculta** (`Ledger.RedrawXPBarFull`:
  ancla siempre, pinta solo si está visible): la barra de actividad y el
  número de xp/hora cuelgan de este frame, así que necesita sus puntos de
  anclaje aunque el jugador la haya ocultado a propósito; si no, tras un
  `/reload` con solo esta oculta las otras dos quedaban sin ancla e
  invisibles (WoW no dibuja un frame con el ancla sin resolver).
  `PLAYER_LOGIN` (`ui/events.lua`) la llama siempre, y las otras dos se
  muestran y anclan después, en orden.
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

### Barra de actividad (`core/time_bar.lua` + `ui/time_bar.lua`, `/ldg time`)

Paralela a la barra de composición de xp (mismo ancho y posición
horizontal, 2px de separación por encima, altura propia `barHeight` —
la de xp ya es la de la barra nativa), muestra cómo se
reparten las muestras del nivel actual entre las 4 actividades de
`core/ticks.lua`. **Eje distinto al de la barra de xp**: aquí siempre
ocupa el 100% del ancho (proporcional al total de muestras, no a un máximo
externo) — las dos barras no son comparables píxel a píxel.

- **Orden fijo** (`Ledger.TICK_KEYS = { "combat", "nonCombat", "travel",
  "dead" }`): siempre de izquierda a derecha en ese orden, para que la
  forma sea reconocible de un vistazo — nunca reordenado por tamaño, a
  diferencia de la barra de xp (que fusiona por orden de llegada).
- **Cálculo puro** (`core/time_bar.lua: Ledger.ComputeTimeBarSegments(ticks,
  widthPx)`): reparte `widthPx` proporcionalmente a `ticks[clave] /
  ticks.total`, reutilizando `Ledger.RoundedWidths` (expuesta desde
  `core/xp_bar.lua`) — misma técnica de redondeo por acumulado que la
  barra de xp, así que la suma de anchuras no supera nunca `widthPx`. Sin
  muestras todavía, no hay segmentos.
- **Fuente de datos: `LedgerCharDB.levelTicks`**, los contadores en vivo
  del nivel (que ya suman todas sus sesiones), leídos tal cual en cada
  redibujado: no hay nada que concatenar ni derivar.
- **Colores y borde: la MISMA `Ledger.PALETTE`** que la barra de xp
  (`ui/palette.lua`) — `travel` #4A6FA5 (azul apagado) y `dead` #8B3A3A
  (rojo oscuro apagado) son entradas propias; `combat` reutiliza el color
  de `kill` (mismo dorado) y `nonCombat` el de `unknown` (mismo gris
  cálido) — el mismo objeto de color, no una copia del hex. Mismo borde de
  1px negro al 60% que la barra de xp.
- **Render**: una textura fija por actividad (siempre son las mismas 4, en
  el mismo orden), sin pool. `Ledger.RedrawTimeBar()` se llama **desde el
  mismo ticker de 1s que muestrea la actividad** (`ui/xp_capture.lua:
  SampleTimeState`), **nunca desde los eventos de xp**: los tramos de
  viaje/no-combate/muerte no generan ningún evento de xp.
- **Tooltip: solo porcentajes**, nunca tiempos absolutos, y ya no es
  propio de la barra: son las secciones 2 y 3 del tooltip unificado (ver
  "Zona de hover unificada"). `Ledger.FormatTickLines(ticks)` (pura) da
  una línea por actividad (`"Combat: 42.3%"`), coloreada con
  `Ledger.PALETTE[clave]`, para el nivel y, debajo, para la sesión activa.
- `/ldg time` alterna `LedgerDB.timeBarShown` y muestra/oculta el frame —
  **independiente de `/ldg bar`**.

### Zona de hover unificada (`core/bar_hover.lua` + `ui/bars_hover.lua`)

**Una sola zona de ratón sobre las dos barras** (antes cada barra tenía su
tooltip y había que afinar el ratón para distinguirlas). `LedgerBarsHover`
es un frame sin dibujo que cubre desde la esquina inferior izquierda de la
barra visible más baja hasta la superior derecha de la más alta (el hueco
de 2px entre barras queda dentro); solo cuentan las barras visibles y sin
ninguna se oculta. Se reajusta sola con `OnShow`/`OnHide` de las dos
barras (`HookScript`), así que sirve cualquier camino que las muestre u
oculte (comandos, restauración del login). Va a la misma `FrameStrata` que
la barra de xp y 5 niveles por encima (sobre la nativa, que tiene ratón y
tooltips propios). Las barras no tienen ratón: lo lleva esta zona.

- **Contenido, puro** (`core/bar_hover.lua: Ledger.BuildBarTooltipSections`):
  devuelve `{ { title=, rows = { { text=, color={r,g,b} }, ... } }, ... }`,
  en este orden: (1) `Level xp composition` — xp por origen de TODAS las
  sesiones del nivel + bono por descanso si lo hay; (2) `Level activity (%
  of samples)`; (3) `This session (% of samples)` — actividad como
  porcentaje de muestras, nunca tiempo absoluto. Recibe `{ sessions=,
  levelTicks=, palette=, showXP=, showTime= }`: la paleta llega como
  PARÁMETRO (`core/` no puede conocer `ui/palette.lua`; `ui/` le pasa
  `Ledger.PALETTE`, así que los colores son siempre los de las barras);
  `showXP`/`showTime` a `false` omiten esas secciones (barra oculta) y una
  sección sin datos (p. ej. sin sesión) no se emite vacía. La capa `ui/` solo
  recorre esa forma.
- **Label**: al entrar se muestra el label de xp sobre la barra de xp
  (ver arriba) y se oculta al salir. Es por zona, no por barra: con el
  ratón sobre la barra de actividad también aparece.
- **Colocación**: `ANCHOR_NONE` con el tooltip colgando ENCIMA del número
  de xp/hora si está apilado sobre las barras (posición por defecto, sin
  `ratePos`), para no taparlo; si no, encima de la zona.
- **Refresco**: mientras el ratón está dentro, `OnUpdate` limitado a 1s
  reconstruye label y tooltip (cambian con cada xp y cada muestra).

### Número principal de xp/hora (`core/rate.lua` + `ui/rate_frame.lua`, `/ldg rate`)

Frame propio, "destacado" (`SetFrameStrata("HIGH")`), anclado encima de
la barra visible más alta. **La pila, de abajo arriba** (2px entre cada
una): barra de composición de xp (que ocupa el sitio de la nativa; con
`/ldg native` apagado va 1px sobre ella) → barra de actividad → este
número. Si la barra de
actividad está visible el número se ancla a ELLA (`frame:SetPoint("BOTTOM",
Ledger.timeBarFrame, "TOP", 0, 2)`); si no, a la de xp
(`Ledger.xpBarFrame`). Anclar siempre a la de xp (lo que hacía antes, con
las barras nunca visibles a la vez) pintaba el número encima de la barra
de actividad, que ya ocupa ese hueco. Un único punto de anclaje
(`"BOTTOM"`/`"TOP"` son el centro-inferior/centro-superior del frame, no
una esquina) centra horizontalmente por construcción. Es una relación de
anclaje viva de WoW, así que sigue a la barra aunque se mueva o redibuje
(incluido el modo degradado de la barra de xp — ver "Localización de la
barra nativa" arriba); solo hay que re-anclar cuando cambia CUÁL es la
barra más alta: `Ledger.RestoreRatePosition()` (que lee
`Ledger.timeBarFrame:IsShown()`) se llama en `PLAYER_LOGIN`, después de
fijar la visibilidad de la barra de actividad, y en `ToggleTimeBar`. Si el
jugador ha arrastrado el número (`LedgerDB.ratePos`), manda esa posición
absoluta y nada de esto aplica.

- **El número**: xp/hora de la **sesión activa** (`Ledger.TotalXP(session,
  includeRested) / session.ticks.total * 3600`, ver
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
- **El denominador son MUESTRAS, no reloj**: cada muestra del muestreador
  cuenta como un segundo (`session.ticks.total` para la sesión,
  `LedgerCharDB.levelTicks.total` para el nivel), nunca el tiempo de pared
  ni el `/played`. Es "xp por hora de tiempo que el addon observó": el
  tiempo con el cliente parado no está en el denominador, por diseño (ver
  "Muestreo de actividad"). Decisión de esta reescritura: el xp/hora
  necesita un denominador y no se le permite usar tiempo de pared; el
  total de muestras es la única fuente que queda. El número principal es
  una tasa (horas, no un tiempo mostrado); el tiempo jugado (ya no
  muestreado) solo se muestra en el panel al pasar el ratón, y ese sí es
  un reloj exacto que NO entra en la tasa (ver más abajo).
- **Guion con menos de 60 muestras** (`Ledger.RATE_MIN_SAMPLES = 60`,
  `core/rate.lua: Ledger.ComputeXPRate`): por debajo de ese umbral el
  denominador es tan pequeño que la tasa sale disparada (50xp en 5
  muestras son 36000 xp/h) — `ComputeXPRate` devuelve `nil` y
  `FormatXPRate` lo convierte en `"-"`. Un numerador a 0 con muestras de
  sobra sigue siendo una tasa real de `0` (no un guion): el guion es solo
  por denominador pequeño, nunca por xp pequeña o nula.
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
  encima de la pila de barras por defecto; en cuanto el jugador lo
  arrastra una vez, esa posición absoluta pasa a mandar en cada login,
  igual que la posición del panel principal.
- `/ldg rate` alterna `LedgerDB.rateShown` y muestra/oculta el frame.

**Panel al pasar el ratón** (`ui/rate_frame.lua`, frame propio —
`LedgerRateHoverPanel` — **nunca `GameTooltip`**, a diferencia de la
barra de xp/tiempo): construido a partir de una estructura genérica de
secciones que vive en `core/rate.lua`, pensada para crecer sin
rehacerse.

- **`Ledger.BuildRatePanelSections(rates)`** (pura, `rates =
  { sessionRate=, levelRate=, sessionPlayed=, levelPlayed= }`: las dos
  tasas salen de `Ledger.ComputeHeadlineRates` y los dos tiempos, en
  segundos o `nil`, los añade `ui/rate_frame.lua` en cada refresco): devuelve `{ { title=, rows = {
  {label=, value=, color=}, ... }, notes = { "línea", ... } }, ... }`
  (`notes` opcional: líneas de texto tras las filas, en
  `Ledger.RATE_NOTE_COLOR`) — hoy dos secciones. `"XP/hour"`, con dos filas
  (`"This session"`, el mismo número que el
  frame principal, en `Ledger.RATE_HIGHLIGHT_COLOR` blanco; `"This
  level"`, en `Ledger.RATE_DEFAULT_COLOR` gris claro). `"Played time"`
  (siempre presente; antes `"Sampled time"`, derivada de las muestras):
  `"This session"` y `"This level"` como duración
  (`Ledger.FormatDuration`: `45s`, `12m 05s`, `1h 23m` — desde la hora
  se quitan los segundos; `nil` → `-`), **relojes exactos, solo para
  mostrar** — no se persisten, no entran en `levels` ni `sessions` ni
  alimentan ningún xp/hora u otra métrica (las muestras siguen siendo la
  única fuente del reparto de actividad y del denominador de la tasa).
  Ya no lleva la nota de "tiempo muestreado".
  - **Sesión** (`Ledger.SessionPlayedSeconds(session, now)`):
    `time() - session.t0`. **Ojo, límite conocido**: da por hecho que se
    está conectado de principio a fin de la sesión, pero una sesión
    guardada se reanuda tras un relog (`StartTracking: resuming saved
    sessions`, con su `t0` original), así que en un cliente que sí cargue
    los SavedVariables (Classic Era) el tiempo desconectado entre medias
    cuenta como jugado. En la beta de WoW Forever (que no los carga al
    arrancar, ver "SavedVariables en la beta") cada arranque es una
    sesión en frío y no ocurre. Ver "Pendiente".
  - **Nivel** (`Ledger.LevelPlayedSeconds(ref, nivelActual, now)`):
    `ref.seconds + (time() - ref.receivedAt)`, con `ref =
    Ledger.levelPlayedRef` (ver "`/played`"). `nil` (guion, nunca un 0)
    mientras no haya llegado ninguna respuesta, o si la referencia es de
    otro nivel (`ref.level ~= UnitLevel`: tras un ding, hasta que llega la
    respuesta nueva no se enseña el tiempo del nivel viejo como el del
    nuevo).
  Añadir el
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
resumen de `levels` ordenado por nivel (incluye `totalRested`, `deaths`
y la actividad del nivel en porcentaje — `Ledger.FormatTickSummary`, nunca
tiempos absolutos; la cabecera de la sesión activa lleva la suya). Lee
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
- **Actividad**: cada nivel y cada sesión llevan sus contadores CRUDOS
  (`ticks`: `combat`/`nonCombat`/`travel`/`dead`/`total`; en CSV, columnas
  `ticks_*`) — los contadores son el dato, nunca un porcentaje ni un
  tiempo derivado. El JSON lleva además `played` (la lectura informativa
  de `/played`, o `null`). No hay campos de tiempo jugado.
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
- **Tiempo (solo información, nunca una discrepancia)**: no hay
  invariantes de tiempo (los contadores son lo que son). La sección
  "Time (information only)" muestra la actividad del nivel y de la sesión
  activa en porcentaje de muestras (`Ledger.FormatTickSummary`) y la
  última lectura de `/played` (`charDB.played`) junto a las muestras que
  tenía el nivel en ese instante, con su diferencia: `"/played, this
  level: 2472s played vs 2450 samples at that moment, difference +22"` y
  una nota de que no es un error (las muestras solo corren con el cliente
  en marcha). Todas son líneas `info`: una diferencia, en el sentido que
  sea, nunca hace fallar el veredicto. Si no hay lectura, o es de otro
  nivel, lo dice. Ver "`/played`: dato informativo".
- **Xp pendiente de emparejar** (hasta ~1s dentro del matcher) puede
  verse como un negativo transitorio justo tras un kill o un ding: la
  ventana lo avisa en sus notas; el botón `Refresh` la relee (y vuelve a
  pedir la lectura de `/played`).
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
la fábrica siga comportándose igual.

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
  `UnitIsDeadOrGhost`, orden fijo): cada una se marca `absent` si el
  global no es una función, o si lo es, se llama con `pcall` (con
  `"player"` como único argumento las que lo necesitan) y se marca
  `present, value = ...` con cada valor devuelto (`tostring` de cada
  uno, recortando los `nil` finales — así `RequestTimePlayed`, que no
  devuelve nada, sale como "no return value" en vez de una fila de
  `nil`s) o `present, call failed (...)` si `pcall` atrapó un error.
  Las 4 últimas (`UnitOnTaxi`/`GetUnitSpeed`/`UnitAffectingCombat`/
  `UnitIsDeadOrGhost`) alimentan de verdad el muestreo de actividad
  (`ui/xp_capture.lua: SampleTimeState`, ver "Muestreo de actividad"
  arriba) — no son solo una curiosidad de cara al futuro, por eso vale
  la pena comprobarlas en cualquier cliente nuevo al que se porte el
  addon.
- **Global strings `COMBATLOG_XPGAIN_*`**: cuenta y lista TODOS los
  globales de texto con ese prefijo, las dos familias a la vez (los
  patrones base de kill/explore y los de `EXHAUSTION` del bono por
  descanso — ver "Captura de eventos" arriba, que sí las separa para su
  propia lógica; aquí solo interesa el inventario crudo).
- **Relleno de la barra nativa** (`nativeFill`, leído de
  `Ledger.nativeFillInfo` — ver "Barra de composición de xp"): `hidden`,
  `overlay only` (con el motivo y la descripción de con qué está
  construida la barra nativa: es lo que hace falta para arreglar la
  búsqueda en un cliente concreto), `visible` o `n/a`. Es la forma de
  saber, en cada cliente real, si el relleno se pudo ocultar limpiamente.
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
`SafeRequestTimePlayed()` (local a ese fichero, expuesta como
`Ledger.RequestPlayedReading`) comprueba que es una función antes de
llamarla y envuelve la llamada en `pcall`. Si falta o casca en un cliente
dado, `LedgerCharDB.played` simplemente no se refresca (solo alimenta una
línea informativa de `/ldg check`) — no hay ninguna otra
`RequestTimePlayed()` suelta en el resto del código.
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

Estado en memoria (no persistido, igual que el matcher — ver
"Pendiente" más abajo), creado en `ui/events.lua` como
`Ledger.logState = Ledger.NewLogState()`:

```lua
state = {
    level  = "trace", -- "off" | "error" | "info" | "trace" (por defecto trace)
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

**Eco al chat en color** (`/ldg log chat`): cada línea sale como `Ledger
[nivel] mensaje`, coloreada por nivel con `Ledger.FormatLogChatLine` /
`Ledger.LOG_COLORS` (`core/log.lua`, puro y testeado): `error` rojo
(`ff5555`), `info` cian (`55ccff`), `trace` gris (`9a9a9a`). La etiqueta
`[nivel]` va también en el texto por si el color no se ve. Un `|` del
mensaje se duplica (`||`) para que un mensaje de chat crudo del juego no se
lea como un escape propio ni corte el color con un `|r` suelto; un mensaje
de varias líneas se colorea línea a línea (`ui/events.lua: Ledger.Log`). El
color solo existe en el chat: el panel de `/ldg log show` es un EditBox
para copiar con Ctrl+C y los escapes acabarían en el portapapeles, así que
allí el texto va sin color (`Ledger.FormatLogBuffer`, que sí lleva la
etiqueta `[nivel]`).

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

- **Versión del esquema y SIN migraciones** (`Ledger.DB_VERSION`, hoy 9,
  `core/xp.lua`): si al cargar la versión guardada de `LedgerCharDB` no
  coincide con la actual (más antigua, más nueva o inexistente en datos
  que no están vacíos), `Ledger.InitCharDB` descarta TODO el contenido y
  arranca limpio — no hay `MigrateDB` ni se intenta conservar nada.
  `InitCharDB` devuelve `db, wiped, oldVersion`, y `ui/events.lua` lo dice
  en el chat al hacer login (`saved data was version N, this addon uses
  version M: this character's data was wiped and tracking starts clean`):
  nunca en silencio. Una tabla nil o vacía (primera carga) no cuenta como
  wipe. **Hay que subir `DB_VERSION` cada vez que cambie la forma de
  `LedgerCharDB`.** (v9 = el modelo de contadores de actividad; todas las
  versiones anteriores, con sus migraciones v1→v8, se borraron.)
- `LedgerDB` (cuenta, `## SavedVariables`): `pos`, `shown`, `version`,
  `includeRested` (toggle de `/ldg rested`, `true` por defecto),
  `barShown`/`barHeight`/`timeBarShown` (barras), `barDefaultPos`/
  `barDefaultWidth`, `rateShown`, `ratePos`, `viewDefaultsApplied`,
  `replaceNative` (toggle de `/ldg native`, `true` por defecto).
  **Nunca se borra por cambio de versión**: son ajustes de interfaz que no
  dependen del esquema de datos; `Ledger.InitDB(db, defaults)` solo rellena
  lo que falte y estampa la versión.
  - **Visibilidad de las tres vistas**: `barShown`, `timeBarShown` y
    `rateShown` valen `true` por defecto (`Ledger.DEFAULTS`); un valor
    guardado siempre manda (`InitDB` nunca pisa lo que hay), así que una
    vista ocultada a propósito sigue oculta tras `/reload` en un cliente
    que persista. En la beta de WoW Forever, que no carga los
    SavedVariables previos al arranque (ver más abajo), cada arranque
    parte de los defaults: las tres visibles.
  - **Reseteo único** (`Ledger.ApplyViewDefaultsOnce`, `core/xp.lua`,
    llamado tras `InitDB` en `ADDON_LOADED`): antes esos tres valían
    `false` por defecto y `InitDB` estampaba ese `false` en `LedgerDB` en
    la primera carga, así que un `false` guardado por una versión
    anterior NO es una elección (no se distingue de una vista que nunca se
    tocó) y los nuevos defaults no habrían llegado a quien ya tenía
    `LedgerDB`. La primera vez (sin `viewDefaultsApplied`) se ponen las
    tres a su default y se estampa `viewDefaultsApplied = true`; desde
    entonces cualquier valor guardado es una elección real. Coste
    asumido: quien ocultara una vista a propósito con una versión
    anterior la vuelve a ver una vez.
- `LedgerCharDB` (por personaje, `## SavedVariablesPerCharacter`):
  `{ version, levels, sessions, levelTicks, played }`. `levels[level]`
  guarda el resultado de `CloseLevel` (con sus `ticks`), indexado por
  nivel real (ver "Entrada de `levels`"); `sessions` es la lista de
  sesiones del nivel en curso, cada una con sus `ticks`; `levelTicks` son
  los contadores en vivo del nivel en curso (al cerrarlo pasan a
  `entry.ticks`); `played` es la lectura informativa de `/played`
  (opcional, ver "`/played`"). Se inicializa en `ADDON_LOADED` con
  `LedgerCharDB = Ledger.InitCharDB(LedgerCharDB)`
  (`core/xp.lua`), que rellena lo que falte con `Ledger.CHAR_DEFAULTS`
  (más un `levelTicks` vacío) y aplica la regla de versión de arriba.
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

### SavedVariables en la beta: el cliente ignora los ficheros previos al arranque (2026-09-19)

**En la beta de WoW Forever (build 1.60.1, interface 16001) el cliente no
carga los SavedVariables que ya existían en disco cuando arrancó**, aunque
los escribe bien al hacer logout/`/reload`. Los ficheros creados durante la
sesión del cliente sí se cargan en un `/reload`. **Es un comportamiento del
cliente: el addon no puede arreglarlo.** Classic Era carga los mismos
ficheros sin problema.

Síntomas en Ledger: cada arranque del cliente abre una sesión en frío
(`initialXP` = toda la xp del nivel, `t0` = instante de la carga), las
sesiones anteriores desaparecen y los ajustes de `LedgerDB` (`ratePos`,
`barShown`...) vuelven a sus valores por defecto. Como el fichero de
Ledger casi siempre existe ya al arrancar, en la práctica los datos solo
viven mientras dure esa sesión del cliente.

**Cómo se demostró** (addons de prueba desechables, ya borrados, cada uno
con un contador en un SavedVariable de cuenta y otro de personaje):
- Un addon cuyos ficheros se crean dentro de la sesión carga en el primer
  `/reload` (`prev loads` sube); tras cerrar y volver a arrancar el cliente,
  los mismos ficheros llegan como `nil`, con el contador de nuevo en 0.
- Pasa igual con cualquier addon (5 distintos) y, con Ledger, en cuanto se
  apartaron sus ficheros del disco antes de arrancar: en ese arranque
  Ledger sí reanudó la sesión tras un `/reload` (`StartTracking: resuming
  saved sessions`), y al arranque siguiente volvió a `cold start`.
- Indicio, no prueba: los SavedVariables de Blizzard tampoco parecen acumular
  entre arranques (`Blizzard_PTRIssueReporter_Saved` guardaba 12 s con horas jugadas).

**Descartado**: el `.toc` con `## Interface: 11509, 16001` (con solo
`16001` seguía igual); el orden de carga o la posición alfabética del
addon; el nombre `Ledger`/`LedgerDB`; la forma o el tamaño de los datos
(un addon con el mismo `.toc`, subcarpetas y tablas anidadas se comporta
igual que uno mínimo); el borrado por versión (`wiped=false`, todos los
guardados dicen `version = 9`); permisos y ACL de NTFS, redirección de
VirtualStore, copias en otras rutas, y las lecturas desde WSL (mismo
resultado en un arranque sin tocar los ficheros desde WSL).

**Sin confirmar**: por qué el cliente los ignora. Se planteó que mirara la
fecha de modificación o de creación del fichero (el juego reescribe en el
sitio, y la de creación no cambia entre guardados), pero esa prueba no llegó
a hacerse. No es un fallo de `GetAddOnMetadata`: `GetAddOnMetadata(addon,
"SavedVariables")` devuelve `nil` también para addons que sí cargan, así que
no sirve como sonda.

**Cómo reconocerlo en el log** (`/ldg log show`, nivel INFO): en un personaje
que ya había jugado, `ADDON_LOADED: LedgerCharDB from disk: type=nil`
seguido de `StartTracking: cold start`. Con datos cargados sale `from disk:
version=... sessions=N ...` y `StartTracking: resuming saved sessions`.
Instrumentación que queda: solo esas dos líneas (`ui/events.lua`,
`ui/xp_capture.lua`, con `Ledger.SummarizeCharDB`); las líneas `SVState[...]`
(volcado de direcciones de tabla a varios instantes del arranque) se
quitaron en 0.11.8 al no aportar ya nada.

**Repro mínimo para reportarlo a Blizzard**: un addon con
`## SavedVariables: XDB` y un `ADDON_LOADED` que haga `XDB = XDB or {}`
y sume uno a `XDB.loads`, imprimiendo el valor previo. Arrancar, `/reload`
(carga), cerrar el cliente del todo, arrancar de nuevo: llega `nil`.

### Diagnóstico de carga

Cada fichero de `core/` hace un `print("Ledger: core/<fichero>.lua")`
incondicional nada más cargar (antes de definir nada), para que en el
chat del juego se vea exactamente qué ficheros de `core/` han llegado a
ejecutarse y en qué orden. Si falta uno en el chat al hacer `/reload`,
ese es el que se ha cortado (error de sintaxis/runtime silencioso, o
falta en el `.toc`).

### Pendiente de definir (se irá completando en próximas sesiones)

- Tras un logout/desconexión sin pasar por reset, la sesión sigue abierta
  al próximo login y se le sigue añadiendo eventos y muestras. Sigue sin
  decidir si al reabrir tras un hueco largo conviene abrir una sesión
  nueva en vez de continuar la vieja.
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
- **Verificar en el juego `reached` y `deaths`** (sin probar con datos
  reales): que `reached` capture el instante del ding real (no solo el de
  arranque en frío) y que `deaths` cuente cada `PLAYER_DEAD` del nivel,
  separado del contador de actividad `dead`.
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
- **Verificar en el juego el muestreador de actividad** (reescrito
  2026-09-19, sin probar con el cliente real; sí con un cliente simulado
  que carga el `.toc` completo): que `UnitAffectingCombat`/`GetUnitSpeed`/
  `UnitIsDeadOrGhost`/`UnitOnTaxi` se comporten como se asume en
  `ui/xp_capture.lua: SampleTimeState` en ambos clientes (`/ldg probe` ya
  los incluye); que los contadores de `LedgerCharDB.levelTicks` y de la
  sesión suban de uno en uno y `total` sea siempre su suma; que un nivel
  cerrado lleve `entry.ticks` y el siguiente arranque en cero; y que una
  `SavedVariables` de una versión anterior se borre con el aviso del
  login, sin errores.
- Ver visualmente en el juego la barra de actividad (nunca probada):
  anclaje 2px por encima de la barra de xp, el orden fijo
  combat/non-combat/travel/dead, los colores (incluidos los que reutilizan
  `kill`/`unknown`), el borde, y su tooltip (solo porcentajes, nivel y
  sesión).
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
- **Verificar en el juego la sustitución de la barra de xp nativa**
  (nunca probada; solo con un cliente simulado que reproduce la forma
  supuesta de la barra en cada cliente, no la real): en Classic Era y en
  WoW Forever, `/ldg probe` → `Native xp bar fill:` debe decir `hidden`;
  si dice `overlay only`, el motivo trae la estructura real de la barra
  para corregir la búsqueda. Comprobar que la barra de composición cubre
  exactamente la nativa (posición y tamaño), que con el relleno oculto no
  se rompe nada del sistema de barras de seguimiento (cambiar la
  reputación seguida, subir de nivel, `/reload`), que `/ldg native` y
  `/ldg bar` devuelven el relleno, y qué pasa con el texto nativo de xp
  si está activada la opción de mostrarlo siempre (no se toca: podría
  verse bajo la barra). Sin confirmar: que Blizzard no reconstruya la
  barra (y su relleno) sin pasar por un evento que Ledger reaplique.
- Ver en el juego la zona de hover unificada (nunca probada): que el
  tooltip y el label salgan al pasar por cualquiera de las dos barras y
  por el hueco entre ellas, que la zona gane el ratón a la barra nativa,
  que el tooltip cuelgue bien encima del número de xp/hora y que arrastrar
  en modo degradado siga moviendo la barra.
- Ver visualmente en el juego el número de xp/hora y su panel al pasar
  el ratón (`/ldg rate`, ver "Número principal de xp/hora" arriba,
  nunca probado): que el anclaje centrado 2px sobre la pila de barras se
  vea bien con las tres visibles a la vez (comprobado solo con un cliente
  simulado con resolutor de geometría: barra nativa, xp, actividad y
  número apilados sin solaparse, también con la barra nativa a ancho 0 en
  el login, con cada una oculta a propósito y en modo degradado; sin
  confirmar en el cliente real, ni si esa altura total choca con otros
  elementos de la interfaz sobre la barra de xp); que
  `GameFontNormalHuge` sea legible y el fondo se ajuste bien al texto
  al cambiar de dígitos; que arrastrarlo y volver a entrar al juego
  respete `LedgerDB.ratePos`; y que el guion aparezca de verdad al
  abrir una sesión nueva y desaparezca pasado el minuto.
- **Verificar en el juego el tiempo jugado del panel de rate** (nunca
  probado, solo con tests de la parte pura): que `TIME_PLAYED_MSG` llegue
  tras `RequestTimePlayed()` en `PLAYER_ENTERING_WORLD` y en
  `PLAYER_LEVEL_UP` en ambos clientes; que "This level" enseñe un guion
  hasta que llega y luego avance segundo a segundo; que tras un ding se
  reinicie a ~0 y no enseñe el tiempo del nivel viejo; que tras un
  `/reload` el valor nuevo no se acumule sobre el anterior; y que "This
  session" cuadre con el reloj. **Límite conocido de "This session"**
  (`time() - t0`): tras un relog en un cliente que reanuda sesiones
  guardadas incluye el tiempo desconectado; decidir junto con el primer
  punto de esta lista (sesión abierta tras un logout) si eso se acepta, si
  se abre sesión nueva tras un hueco largo o si el reloj de sesión debe
  medirse desde la carga del addon.
