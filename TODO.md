# TODO — documentación y código desfasados

Anotado el 2026-09-21 (Ledger v0.14.0, tras el cambio de "Sources of truth").
Solo lo que he visto leyendo el código y los docs mientras hacía ese cambio.

Leyenda: **[V]** verificado contra el código actual · **[NV]** viene de `Audit.md`
y no lo he vuelto a comprobar.

---

## 1. README.md

Es lo más desfasado: describe un producto anterior a la reescritura del 2026-09-19
y a los cambios de hoy.

- [ ] **Barra de tiempo [V]:** dice que el no-combate "se reclasifica retroactivamente
  pasado un umbral configurable". Eso se borró el 2026-09-19 (`docs/decisions.md` 2.1:
  sin reclasificación ni umbrales). Ahora es un muestreo de un tick por segundo con
  cuatro contadores (combate, no combate, viaje, muerto), mostrado en porcentajes.
- [ ] **Rates [V]:** habla de una sola tasa "del nivel actual con el descanso excluible".
  Ahora son dos: "This session" (registro del addon, respeta `/ldg rested`) y
  "This level" (`UnitXP` / tiempo jugado del nivel, ignora `/ldg rested`).
- [ ] **Hover [V]:** promete "per-source totals and percentages" y "an estimate of time
  to next level". El tooltip da xp por origen (sin porcentajes), rested y el reparto de
  actividad en % de muestras. **No existe ninguna estimación de tiempo al siguiente nivel**
  (en `CLAUDE.md` queda la regla por si se añade). Decidir: implementarla o quitar la frase.
- [ ] **Instalación [V]:** solo menciona Classic Era. El `.toc` declara también WoW Forever
  (`## Interface: 11509, 16001`, carpeta `_classic_beta_`).
- [ ] **Tabla de comandos [V]:** faltan `/ldg rate`, `/ldg native`, `/ldg probe`,
  `/ldg strings` y `/ldg wipe confirm` (todos están en `Ledger.SLASH_COMMANDS`).
  La descripción de `/ldg rested` ("counts toward rates") ya no es cierta para
  "This level".
- [ ] **Enlace roto [V]:** el pie apunta a `[LICENSE](LICENSE)` y no hay ningún fichero
  `LICENSE` en el repo.
- [ ] Añadir una nota corta sobre la beta: ignora los SavedVariables anteriores al
  arranque del cliente, así que ahí los datos duran una sola sesión de cliente.

## 2. Texto del propio addon

- [ ] **`/ldg rested` [V]:** `core/slash_command.lua:17` dice "toggles whether the rested
  bonus counts in session and level xp metrics". Ya no afecta a la tasa "This level".
  Cambiar el texto (y `/ldg help` sale de ahí).

## 3. Comentarios y docs que afirman algo falso

- [ ] **"Un crash pierde como mucho los ticks desde el último guardado" [V]:** aparece en
  `core/ticks.lua:72`, `ui/xp_capture.lua:401` y `docs/decisions.md:145`. WoW solo
  vuelca los SavedVariables al logout, `/reload` o salida limpia; un crash pierde toda
  la sesión desde el último volcado, no unos ticks (`Audit.md` 1.6). Corregir la frase
  en los tres sitios.
- [ ] **`docs/decisions.md`, cabecera [V]:** sigue citando el commit
  "Snapshot CLAUDE.md before the cleanup" como origen. Comprobar si sigue teniendo sentido.

## 4. Audit.md (foto del 2026-09-20)

- [ ] **La foto está vieja [V]:** base `298971a`, v0.12.0, 359 tests, y avisa de que otra
  sesión estaba tocando `ui/xp_bar.lua`, `ui/time_bar.lua`, `core/rate.lua`,
  `ui/events.lua`, `core/xp.lua`, etc. Hoy es v0.14.0 con 379 tests y esos ficheros
  ya cambiaron. Las líneas citadas (`ui/xp_capture.lua:443`, `:527`, `:405-410`…)
  ya no son las de hoy.
- [ ] **1.7, segundo punto [V]:** dice que `/played` "ya solo alimenta `/ldg check`" y que
  esa ventana lo pide al abrirse, así que la petición del login sobra. Ya no aplica: la
  ventana no pide nada y `PLAYER_ENTERING_WORLD` es ahora una de las dos peticiones
  normativas (la otra, `PLAYER_LEVEL_UP`). Si el spam de "Total time played" en el chat
  molesta, hay que resolverlo de otra forma.
- [ ] **Sigue abierto, comprobado [V]:**
  - 1.1: `QUEST_TURNED_IN` se encola siempre como `quest`, aunque la xp sea 0
    (`ui/xp_capture.lua:579`) y `SourceRank` prefiere `quest` a `kill`.
  - 1.2: `Flush` recorre las cantidades en orden inverso (`core/xp_gain_matcher.lua:271`).
- [ ] **Sin re-verificar [NV]:** 1.3 (formatos posicionales `%1$s`), 1.4 (bono de descanso
  siempre 0), 1.5 (barra simple en las rutas de textura de `ui/frame.lua`), 1.8 (el
  buffer del log pierde los errores), 1.9 (valores "secret" sin proteger), y toda la
  tabla de "Riesgos menores". Pasar por cada uno, marcar los resueltos y borrarlos.
- [ ] Decidir el destino del fichero: mantenerlo al día, o convertir lo abierto en
  issues y borrarlo.

## 5. Decisiones abiertas que salen del cambio de hoy

- [ ] **Tasa de sesión tras un relog:** en Classic Era la sesión guardada se retoma con su
  `t0` original, así que `time() - t0` incluye el tiempo desconectado y la tasa "This
  session" sale diluida. Decidir entre aceptarlo, abrir sesión nueva tras un hueco largo,
  o medir el reloj desde la carga del addon (`docs/decisions.md` 9.3).
- [ ] **`DB_VERSION` 10 borra los datos [V]:** quitar `LedgerCharDB.played` cambió la forma
  de la tabla y la regla sin migraciones vacía el historial de cada personaje una vez.
  Si en el futuro se quiere evitar este borrado por quitar un campo opcional, habría
  que matizar la regla en `CLAUDE.md`.
- [ ] **Carrera `/played` en vuelo durante un ding:** una respuesta pedida antes del ding
  que llegue después quedaría etiquetada con el nivel nuevo. Ventana de segundos, la
  cubre el umbral de 60 s. No se ha protegido.
