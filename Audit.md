# Auditoría de código — Ledger

Fecha: 2026-09-20. Base: `master` @ `298971a` (v0.12.0).

**Alcance:** todo `Ledger/` (core + ui), `spec/`, `deploy.sh` y los hooks de
`.claude/`. Auditoría de solo lectura.

**Método:** lectura completa del código, `busted` (359 tests, 0 fallos),
`luac5.1 -p` sobre todos los `.lua` (sintaxis OK), barrido de `SETGLOBAL`
(solo los globales intencionados) y reproducción de las hipótesis del
matcher y de los patrones ejecutando el código real de `core/`.

**Aviso:** durante la auditoría otra sesión estaba modificando
`ui/xp_bar.lua`, `ui/time_bar.lua`, `core/rate.lua`, `ui/events.lua`,
`core/xp.lua`, `core/probe.lua`, `core/slash_command.lua` y añadiendo
`core/bar_hover.lua` / `ui/bars_hover.lua`. Lo que se dice de esos ficheros
está marcado como "en movimiento" y puede estar ya superado. Las líneas
citadas del resto de ficheros son las de `HEAD`.

Leyenda: **[R]** reproducido ejecutando el código real · **[L]** por lectura
del código · **[?]** hipótesis que necesita comprobación en el cliente.

---

## 1. Riesgos

### 1.1 Una quest de 0 xp le roba el kill siguiente — [R] · alta

`QUEST_TURNED_IN` se encola siempre como fuente `quest`
(`ui/xp_capture.lua:527`), aunque `xp == 0` (quests grises, o a nivel
máximo). Si un kill llega en menos de 1 s, `PopClosest` con `SourceRank`
(`core/xp_gain_matcher.lua:150`) prefiere la quest sobre la fuente `kill`.

Consecuencias:

- la xp del kill se graba como `quest`;
- la fuente `kill` queda huérfana y puede emparejarse con la **siguiente**
  cantidad;
- se loguea un falso `xp discrepancy` (expected 0 vs delta real).

Reproducción:

```lua
local m = L.NewMatcher()
L.AddSource(m, 100.0, "quest", nil, 0, 0)   -- QUEST_TURNED_IN, xp=0
L.AddSource(m, 100.5, "kill",  nil, 0)      -- mensaje del kill
local p = L.AddAmount(m, 100.5, 45)         -- xp del kill
-- p.src == "quest"  (esperado: "kill"); queda 1 fuente "kill" pendiente
```

Arreglo: no encolar fuentes `quest` con `xp` nulo o 0; o dar la prioridad
de `SOURCE_PRIORITY` solo cuando `expectedXP` coincide con la cantidad.

### 1.2 `Flush` emite los eventos en orden inverso — [R] · media

`core/xp_gain_matcher.lua:273` recorre `for i = #matcher.amounts, 1, -1`, así
que con varias cantidades huérfanas salen primero las más nuevas.

Consecuencias:

- offsets desordenados en la serie;
- si la cantidad vieja lleva un `crossing`, la nueva se graba en la sesión
  del **nivel viejo** (`EmitEvent` la procesa antes del cierre).

Reproducción: dos `AddAmount` (t=10.0 con `crossing`, t=10.5 sin él) y
`Flush(m, 12.0)` devuelve primero `t=10.5` y después `t=10.0 CROSSING`.

Arreglo: ordenar `flushed` por `t` antes de devolverlo.

### 1.3 Formatos posicionales (`%1$s`) clasifican todo como `explore` — [R] · media

`ConvertFormatString` (`core/chat_patterns.lua:20-24`) solo entiende `%s` y
`%d`. Con `%1$s`:

- el patrón generado es `^%%2%$s muere, ...` y nunca casa;
- `ClassifyXPGainMatch` cae en `explore` por defecto, sin ningún aviso;
- `entry.text:find("%%s")` (línea 70) tampoco reconoce `%1$s`, así que
  aunque casara no se clasificaría como `kill`.

CLAUDE.md afirma que funciona "en cualquier idioma". No se ha comprobado qué
locales usan formato posicional, pero el fallo es silencioso.

Arreglo: soportar `%N$s` / `%N$d` (mapeando el orden de las capturas) y
avisar a nivel ERROR si ningún patrón casa.

### 1.4 El bono por descanso puede salir siempre 0 — [R] + [?] · media

El test inventa el global como `" (+%d exp Rested bonus)"`
(`spec/chat_patterns_spec.lua:121`). El real `COMBATLOG_XPGAIN_EXHAUSTION*`
probablemente es una frase completa, p. ej.
`"%s dies, you gain %d experience. (%s exp %s bonus)"`. Con ese texto,
`ExtractRestedBonus` devuelve **0** (la primera captura es el nombre de la
criatura, `tonumber` da `nil`).

Los datos guardados que existen (esquemas v6/v7) tenían `totalRested = 0`
en todos los niveles: coherente con esto, pero no concluyente.

Comprobar: `/ldg strings` imprime el valor literal del global.

Alternativa independiente del idioma: la variación de `GetXPExhaustion`
antes/después del evento (`/ldg probe` ya la comprueba).

### 1.5 Rutas de textura rotas en `ui/frame.lua` — [R] · baja (cosmético)

`ui/frame.lua:21-22`: `"Interface\Tooltips\UI-Tooltip-Background"` con una
sola barra. Lua 5.1 descarta la barra de los escapes desconocidos y produce
`InterfaceTooltipsUI-Tooltip-Background`: el panel principal se queda sin
fondo ni borde. Los demás ficheros usan `\\`. Arreglo: duplicar las barras.

### 1.6 Durabilidad de los datos — [L] · media

CLAUDE.md ("Un tick") dice que un crash "pierde como mucho los ticks desde
el último guardado". WoW solo vuelca los SavedVariables al hacer logout,
`/reload` o salir; un crash o un cierre a la fuerza pierde **toda** la sesión
desde el último volcado, no unos ticks. Corregir la frase; no hay API para
forzar el guardado. (Se suma a que la beta no carga los ficheros previos al
arranque, ver CLAUDE.md.)

### 1.7 Spam en el chat — [L]/[?] · media

- Los 19 ficheros de `core/` hacen un `print("Ledger: core/x.lua")`
  incondicional: ~19 líneas en cada login o `/reload`. El hook ya las filtra
  de la salida de los tests (`post-edit.sh:95`), señal de que son ruido.
  Quitarlos o ponerlos detrás de un flag de depuración.
- `RequestTimePlayed` se llama en cada `PLAYER_ENTERING_WORLD`
  (`ui/xp_capture.lua:443`), es decir, en cada pantalla de carga. **[?]**
  Creo que el chat por defecto imprime las líneas de "Total time played" cada
  vez (no comprobado en el juego). Como `/played` ya solo alimenta
  `/ldg check`, y esa ventana lo pide al abrirse, la petición del login sobra.

### 1.8 El log pierde los errores — [L] · media

`LOG_BUFFER_CAPACITY = 200` y nivel por defecto `trace` (`core/log.lua`).
Un kill genera ~10 líneas, así que una entrada ERROR sale del buffer tras
~20 eventos y `/ldg log show` deja de servir para diagnosticar (el aviso de
`GetUnitSpeed`, los `xp discrepancy`...). Arreglo: anillo aparte para
`error`/`info`, o nivel por defecto `info`.

### 1.9 Posibles valores "secret" en la beta — [?] · media/baja

Solo `GetUnitSpeed` está protegido con `pcall`. `UnitIsDeadOrGhost`,
`UnitAffectingCombat` y `UnitOnTaxi` se usan en tests de verdad sin
protección (`ui/xp_capture.lua:405-410`), y `FindMatchingChild` compara
`max - xpMax` sin proteger (`ui/xp_bar.lua:66`). Si el cliente marca alguno
como "secret" (ya pasó con `GetUnitSpeed`), el ticker fallaría cada segundo.
Arreglo: helper de lectura segura reutilizable, con aviso una vez por sesión.

---

## 2. Riesgos menores

| Tema | Detalle |
|---|---|
| Offsets negativos | Un `/ldg reset` con una cantidad pendiente en el matcher graba el evento con offset < 0 (`sessionStartRef` se reasigna al reset). `AddToCurve` calcula `minute ≤ 0` (`core/level_close.lua:45`) y el bucle de densificación empieza en 1: el evento no entra en `curve` (sí en los totales). |
| Tiempo comprimido al reanudar | `sessionStartRef = t - lastOffset/10` (`ui/xp_capture.lua:304`) descarta el tiempo inactivo: los offsets dejan de equivaler a `t0 + off` y `curve` mide "tiempo de eventos". Sería más fiel derivarlo de `time() - t0`. |
| Export incompleto | `BuildExportModel` omite `xpRequired` e `initialXP` de los niveles cerrados (`core/export.lua:127-136`) y `levelTicks`. Con el export no se puede repetir la reconciliación de `/ldg check` fuera del juego. |
| Ticker del panel de debug | El auto-refresco (`ui/debug_frame.lua:141`) sigue corriendo cada 2 s con el panel oculto. |
| Panel de debug / texto | `editBox:SetWidth(360)` fijo: no sigue al redimensionar. |
| Wipe por versión sin copia | Cualquier subida de `DB_VERSION` (o bajada de versión) destruye el historial (`Ledger.InitCharDB`). Es deliberado; una copia de la tabla anterior costaría poco. |
| `deploy.sh` no atómico | `rm -rf` + `cp -r`: si el `cp` falla a medias, el cliente se queda con un addon parcial. Copiar a un temporal y `mv`. |
| Higiene del repo | Fichero vacío `aa` sin trackear; `.claude/` y `.gitignore` sin commitear; `Notes` del `.toc` dice "Minimal skeleton"; el título del panel es "XP TRACKER" (residuo de XPTrack). |
| Alloc por pintado | `Ledger.LightenColor` crea una tabla nueva en cada `PaintSegment`. Despreciable, pero trivial de cachear. |
| **En movimiento** | El panel de `rate` muestra duraciones absolutas ("Sampled time") y CLAUDE.md dice que nunca se muestran; `Ledger.AddThousandsSeparator` sigue exportada y un comentario de `rate.lua` apunta a `bar_hover`; en `xp_bar`, un segmento de 0 px ocupa igualmente un par de texturas y si la suma de segmentos supera `maxXP` la barra se desborda (`RoundedWidths` no recorta). |

---

## 3. Refactors recomendados

1. **Extraer un `core/tracker.lua`** (el más rentable).
   `ui/xp_capture.lua` (566 líneas) contiene la lógica más delicada —
   `EmitEvent`, `EmitCrossingEvent`, `CloseCurrentLevel`, `StartTracking`,
   `ResetSession`, cálculo de offsets— y rompe la regla "ui = capa fina".
   No tiene ni un test: los 359 tests cubren solo módulos puros, y los bugs
   1.1, 1.2 y el de offsets negativos viven precisamente ahí. Con el reloj,
   `time()` y las lecturas de `UnitXP` inyectados se podrían testear cruces
   de nivel, quest + kill simultáneos, reset con pendientes y el orden del
   `Flush`.
2. **Unificar `ui/debug_frame.lua` con `ui/text_window.lua`.** Duplican unas
   80 líneas (frame, redimensionado, EditBox de solo lectura).
3. **Un solo scheduler de 1 s** para el volcado del matcher, el muestreo y
   el refresco del rate (hoy son tres `C_Timer.NewTicker`). Además,
   `RedrawTimeBar` reancla y recoloca los 4 bordes cada segundo; basta con
   hacerlo cuando cambia el ancho.
4. **Despachar `/ldg` con una tabla de handlers** indexada por
   `Ledger.SLASH_COMMANDS`, en vez del `if/elseif` de 15 ramas de
   `ui/events.lua`. `Ledger.IsKnownCommand` solo lo usan los tests.
5. **Log perezoso.** Casi cada `Ledger.Log("trace", string.format(...))`
   formatea la cadena aunque el nivel la vaya a descartar.

---

## 4. Lo que está bien

- `core/` es realmente puro: sin `GetTime`, `time()` ni `_G`.
- Los únicos globales son los intencionados (`LedgerDB`, `LedgerCharDB`,
  `SLASH_LEDGER1/2`).
- El manejo del cruce de nivel (`ComputeXPDelta` + `SplitCrossingEvent`,
  partiendo el evento en dos que suman exactamente el original) está bien
  diseñado.
- La regla "sin migraciones y avisar siempre" está bien resuelta.
- Los hooks de Claude Code y `deploy.sh` (modos `--if-installed` /
  `--status`, comparación por contenido) están cuidados.
- Cobertura de tests sólida en la lógica pura (359 tests).

---

## 5. Orden de ataque sugerido

1. Test-first de 1.1 y 1.2 (matcher), y arreglos triviales (1.5).
2. Comprobar 1.4 con `/ldg strings` en el cliente; decidir entre arreglar el
   parseo o usar `GetXPExhaustion`.
3. Quitar los `print` de carga y la petición de `/played` del login (1.7).
4. Separar el buffer de log (1.8).
5. Extraer `core/tracker.lua` (refactor 1) y, con él, cubrir offsets y reset.
6. Soportar formatos posicionales (1.3) y proteger las lecturas "secret"
   (1.9) cuando haya forma de probarlo en el cliente.
