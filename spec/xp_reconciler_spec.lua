describe("core/xp_reconciler.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/xp_reconciler.lua"))("Ledger", Ledger)
    end)

    it("empieza sin descuadre", function()
        local r = Ledger.NewReconciler()
        assert.are.equal(0, Ledger.ReconciliationGap(r))
    end)

    it("se mantiene a cero cuando lo esperado y lo grabado coinciden", function()
        local r = Ledger.NewReconciler()
        Ledger.AccountExpectedXP(r, 270)
        Ledger.AccountRecordedXP(r, 270)

        assert.are.equal(0, Ledger.ReconciliationGap(r))
    end)

    it("detecta el descuadre del bug de subida de nivel: xp esperada que nunca llega a grabarse", function()
        local r = Ledger.NewReconciler()
        -- El caso real: un delta de xp valido (270, ya corregido por
        -- core/xp_delta.lua) que un bug descarta antes de grabarse.
        Ledger.AccountExpectedXP(r, 270)

        assert.are.equal(270, Ledger.ReconciliationGap(r))
    end)

    it("acumula el hueco a lo largo de varios eventos, no solo el ultimo", function()
        local r = Ledger.NewReconciler()
        Ledger.AccountExpectedXP(r, 100)
        Ledger.AccountRecordedXP(r, 100)
        Ledger.AccountExpectedXP(r, 50) -- este se pierde
        Ledger.AccountExpectedXP(r, 30)
        Ledger.AccountRecordedXP(r, 30)

        assert.are.equal(50, Ledger.ReconciliationGap(r))
    end)

    it("un exceso de xp grabada (mas de la esperada) tambien se refleja, en negativo", function()
        local r = Ledger.NewReconciler()
        Ledger.AccountExpectedXP(r, 50)
        Ledger.AccountRecordedXP(r, 80)

        assert.are.equal(-30, Ledger.ReconciliationGap(r))
    end)
end)
