describe("core/xp_reconciler.lua", function()
    local Ledger

    before_each(function()
        Ledger = {}
        assert(loadfile("Ledger/core/xp_reconciler.lua"))("Ledger", Ledger)
    end)

    it("starts with no gap", function()
        local r = Ledger.NewReconciler()
        assert.are.equal(0, Ledger.ReconciliationGap(r))
    end)

    it("stays at zero when expected and recorded match", function()
        local r = Ledger.NewReconciler()
        Ledger.AccountExpectedXP(r, 270)
        Ledger.AccountRecordedXP(r, 270)

        assert.are.equal(0, Ledger.ReconciliationGap(r))
    end)

    it("detects the level-up bug's gap: expected xp that never gets recorded", function()
        local r = Ledger.NewReconciler()
        -- The real case: a valid xp delta (270, already corrected by
        -- core/xp_delta.lua) that a bug discards before it gets recorded.
        Ledger.AccountExpectedXP(r, 270)

        assert.are.equal(270, Ledger.ReconciliationGap(r))
    end)

    it("accumulates the gap across several events, not just the last one", function()
        local r = Ledger.NewReconciler()
        Ledger.AccountExpectedXP(r, 100)
        Ledger.AccountRecordedXP(r, 100)
        Ledger.AccountExpectedXP(r, 50) -- this one gets lost
        Ledger.AccountExpectedXP(r, 30)
        Ledger.AccountRecordedXP(r, 30)

        assert.are.equal(50, Ledger.ReconciliationGap(r))
    end)

    it("an excess of recorded xp (more than expected) also shows up, negative", function()
        local r = Ledger.NewReconciler()
        Ledger.AccountExpectedXP(r, 50)
        Ledger.AccountRecordedXP(r, 80)

        assert.are.equal(-30, Ledger.ReconciliationGap(r))
    end)
end)
