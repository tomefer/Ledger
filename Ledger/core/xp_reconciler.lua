-- Ledger - core/xp_reconciler.lua
-- Contador de reconciliacion: compara la xp que se esperaba grabar
-- (cada delta valido calculado por core/xp_delta.lua, se emparejara ya
-- o se quede pendiente) contra la xp que realmente ha acabado grabada
-- en una sesion (core/events.lua: AddEvent). Un hueco persistente entre
-- ambas es la firma de un bug que descarta xp en silencio -- exactamente
-- el caso que perdia la xp entera al subir de nivel antes de este fix.
-- Logica pura: no usa ninguna API de WoW.

local ADDON_NAME, Ledger = ...

print("Ledger: core/xp_reconciler.lua")

function Ledger.NewReconciler()
    return { expectedTotal = 0, recordedTotal = 0 }
end

-- Se llama con la xp que un delta valido dice que deberia grabarse
-- (independientemente de si se empareja al momento o se queda a la
-- espera en el matcher).
function Ledger.AccountExpectedXP(reconciler, xp)
    reconciler.expectedTotal = reconciler.expectedTotal + xp
end

-- Se llama con la xp que realmente ha llegado a grabarse (el xp de un
-- evento ya emitido, via AddEvent).
function Ledger.AccountRecordedXP(reconciler, xp)
    reconciler.recordedTotal = reconciler.recordedTotal + xp
end

-- Diferencia entre lo esperado y lo grabado. Puede ser transitoriamente
-- distinta de 0 mientras hay cantidades todavia dentro del margen de
-- emparejamiento (Ledger.MAX_MATCH_GAP); un hueco que no se cierra
-- nunca es un bug.
function Ledger.ReconciliationGap(reconciler)
    return reconciler.expectedTotal - reconciler.recordedTotal
end
