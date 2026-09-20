-- Ledger - core/xp_reconciler.lua
-- Reconciliation counter: compares the xp that was expected to be
-- recorded (every valid delta computed by core/xp_delta.lua, whether it
-- pairs right away or stays pending) against the xp that has actually
-- ended up recorded in a session (core/events.lua: AddEvent). A
-- persistent gap between the two is the signature of a bug that
-- silently drops xp -- exactly the case that lost the whole xp amount
-- on level-up before this fix.
-- Pure logic: does not use any WoW API.

local ADDON_NAME, Ledger = ...

function Ledger.NewReconciler()
    return { expectedTotal = 0, recordedTotal = 0 }
end

-- Called with the xp that a valid delta says should get recorded
-- (regardless of whether it pairs right away or stays waiting in the
-- matcher).
function Ledger.AccountExpectedXP(reconciler, xp)
    reconciler.expectedTotal = reconciler.expectedTotal + xp
end

-- Called with the xp that has actually ended up recorded (an already
-- emitted event's xp, via AddEvent).
function Ledger.AccountRecordedXP(reconciler, xp)
    reconciler.recordedTotal = reconciler.recordedTotal + xp
end

-- Difference between what was expected and what was recorded. Can be
-- transiently nonzero while amounts are still within the pairing
-- margin (Ledger.MAX_MATCH_GAP); a gap that never closes is a bug.
function Ledger.ReconciliationGap(reconciler)
    return reconciler.expectedTotal - reconciler.recordedTotal
end
