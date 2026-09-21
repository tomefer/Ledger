# Auditoría de código — Ledger: lo que sigue abierto

Foto original: 2026-09-20 (`master` @ `298971a`, v0.12.0). Revisada punto por
punto el 2026-09-21 contra v0.14.1; las líneas de código ya no se citan porque
cambian con cada commit: busca por nombre de función.

Este fichero solo conserva lo **no resuelto**. Lo resuelto vive en el historial
de git y en `docs/decisions.md` (3.8 matcher, 3.7 log, 1.3 lecturas "secret").

Leyenda: **[R]** reproducido ejecutando el código real · **[L]** por lectura ·
**[?]** hipótesis que necesita comprobación en el cliente.

**Resuelto desde la foto original:** 1.1 quest de 0 xp (`AddSource` ya no la
encola), 1.2 orden de `Flush`, 1.5 rutas de textura de `ui/frame.lua`, 1.6
(frase falsa sobre crashes corregida en código y docs), 1.7 (los `print` de
carga se quitaron el 2026-09-20; `RequestTimePlayed` en el login es ahora una de
las dos peticiones normativas, ver `CLAUDE.md` "Sources of truth"), 1.8 (el
buffer del log expulsa antes el trace que los errores), 1.9 parcial (las
lecturas del muestreador ya van con `pcall`), y de la tabla menor: `aa` sin
trackear, `.claude/`/`.gitignore` sin commitear, `Notes` del `.toc`, título
"XP TRACKER", duraciones absolutas en el panel de rate, `AddThousandsSeparator`.

---

## 1. Riesgos abiertos

### 1.3 Formatos posicionales (`%1$s`) clasifican todo como `explore` — [R] · media

`ConvertFormatString` (`core/chat_patterns.lua`) solo entiende `%s` y `%d`. Con
`%1$s` el patrón generado nunca casa y `ClassifyXPGainMatch` cae en `explore`
sin ningún aviso; `entry.text:find("%%s")` tampoco lo reconoce como `kill`.
No se sabe qué locales usan formato posicional, pero el fallo es silencioso.

Arreglo: soportar `%N$s` / `%N$d` (mapeando el orden de las capturas) y avisar a
nivel ERROR si ningún patrón casa. Sin forma de comprobar el locale real en el
cliente, se puede cubrir con tests de core.

### 1.4 El bono por descanso puede salir siempre 0 — [R] + [?] · media

El test inventa el global como `" (+%d exp Rested bonus)"`. El real
`COMBATLOG_XPGAIN_EXHAUSTION*` probablemente es una frase completa con varios
`%s`, y `ExtractRestedBonus` toma la primera captura (con esa forma sería el
nombre de la criatura, `tonumber` da `nil`, resultado 0). Los datos guardados
antiguos tenían `totalRested = 0` en todos los niveles: coherente, no concluyente.

Comprobar: `/ldg strings` imprime el valor literal del global. Alternativa
independiente del idioma: la variación de `GetXPExhaustion` antes/después del
evento (`/ldg probe` ya la comprueba). Ver `docs/decisions.md` 3.3 y 9.1.

### 1.9 (resto) `FindMatchingChild` compara sin proteger — [?] · baja

`ui/xp_bar.lua: FindMatchingChild` hace `max - xpMax` con valores que salen de
un `StatusBar` de Blizzard y de `UnitXPMax`, sin `pcall`. Nada indica que sean
"secret"; si un cliente lo hiciera, fallaría al anclar la barra.

---

## 2. Riesgos menores abiertos

| Tema | Detalle |
|---|---|
| Offsets negativos | Un `/ldg reset` con una cantidad pendiente en el matcher graba el evento con offset < 0 (`sessionStartRef` se reasigna al reset). `AddToCurve` calcula `minute ≤ 0` (`core/level_close.lua`) y el evento no entra en `curve` (sí en los totales). |
| Tiempo comprimido al reanudar | `sessionStartRef = t - lastOffset/10` (`ui/xp_capture.lua`) descarta el tiempo inactivo: los offsets dejan de equivaler a `t0 + off` y `curve` mide "tiempo de eventos". Sería más fiel derivarlo de `time() - t0`. |
| Export incompleto | `BuildExportModel` no exporta `xpRequired` ni `initialXP` de los niveles cerrados: con el export no se puede repetir la reconciliación de `/ldg check` fuera del juego. (Los `ticks` de nivel ya se exportan.) |
| Ticker del panel de debug | Con "auto refresh" marcado sigue refrescando cada 2 s aunque el panel esté oculto (`ui/debug_frame.lua`). |
| Panel de debug / texto | `editBox:SetWidth(360)` fijo: no sigue al redimensionar. |
| Wipe por versión sin copia | Cualquier cambio de `DB_VERSION` destruye el historial (`Ledger.InitCharDB`). Deliberado; una copia de la tabla anterior costaría poco. |
| `deploy.sh` no atómico | `rm -rf` + `cp -r`: si el `cp` falla a medias, el cliente se queda con un addon parcial. Copiar a un temporal y `mv`. |
| Alloc por pintado | `Ledger.LightenColor` crea una tabla nueva en cada `PaintSegment`. Despreciable, trivial de cachear. |
| `xp_bar` | Un segmento de 0 px ocupa igualmente un par de texturas, y si la suma de fracciones supera 1 la barra se desborda (`RoundedWidths` no recorta). |

---

## 3. Refactors recomendados

1. **Extraer un `core/tracker.lua`** (el más rentable). `ui/xp_capture.lua`
   contiene la lógica más delicada (`EmitEvent`, `EmitCrossingEvent`,
   `CloseCurrentLevel`, `StartTracking`, `ResetSession`, cálculo de offsets) y
   rompe la regla "ui = capa fina". No tiene tests: los bugs 1.1 y 1.2 vivían
   justo ahí de forma indirecta y el de offsets negativos sigue ahí. Con el reloj,
   `time()` y las lecturas de `UnitXP` inyectados se podrían testear cruces de
   nivel, quest + kill simultáneos, reset con pendientes y el orden del `Flush`.
2. **Unificar `ui/debug_frame.lua` con `ui/text_window.lua`.** Duplican unas 80
   líneas (frame, redimensionado, EditBox de solo lectura).
3. **Un solo scheduler de 1 s** para el volcado del matcher, el muestreo y el
   refresco del rate (hoy son varios `C_Timer.NewTicker`). Además,
   `RedrawTimeBar` reancla y recoloca los bordes cada segundo; basta con
   hacerlo cuando cambia el ancho.
4. **Despachar `/ldg` con una tabla de handlers** indexada por
   `Ledger.SLASH_COMMANDS`, en vez del `if/elseif` de `ui/events.lua`.
5. **Log perezoso.** Casi cada `Ledger.Log("trace", string.format(...))`
   formatea la cadena aunque el nivel la vaya a descartar.

---

## 4. Orden de ataque sugerido

1. Formatos posicionales (1.3), con tests de core.
2. Comprobar 1.4 con `/ldg strings` en el cliente; decidir entre arreglar el
   parseo o usar `GetXPExhaustion`.
3. Extraer `core/tracker.lua` (refactor 1) y, con él, cubrir offsets y reset.
4. Resto de la tabla menor según apetezca.
