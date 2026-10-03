local function run_tests(assert_eq, assert_true)
    local Policy = require("memorization_policy")
    local Result = require("memorization_result")
    local Generation = require("batch_generation")

    assert_eq(Policy.DEFAULT_MAX_STEPS, 80, "default threshold")
    assert_true(not Policy.requires_confirmation(80), "threshold is allowed")
    assert_true(Policy.requires_confirmation(81), "above threshold confirms")

    local items = {}
    for i = 1, 121 do items[i] = i end
    local chunks = Policy.chunk(items)
    assert_eq(#chunks, 3, "three safe chunks")
    assert_eq(#chunks[1], 50, "first chunk capped")
    assert_eq(#chunks[2], 50, "second chunk capped")
    assert_eq(#chunks[3], 21, "final chunk keeps remainder")
    assert_eq(chunks[3][21], 121, "chunking never truncates")

    local partial = Result.from_counts(10, 4, 2, 6)
    assert_true(partial.partial, "partial metadata exposed")
    assert_true(not partial.all_sent, "partial result is not all sent")
    assert_eq(partial.failed, 4, "partial failure count")
    assert_true(not Result.should_reconcile(true, partial),
        "partial passage remains in queue")

    local complete = Result.from_counts(10, 4, 6, 10)
    assert_true(complete.all_sent, "sent plus already-present is complete")
    assert_true(Result.should_reconcile(true, complete),
        "complete passage may reconcile")

    local threshold_info = {
        requires_confirmation = true,
        step_count = 81,
        max_steps = 80,
    }
    assert_eq(Result.batch_status(false, threshold_info), "pending",
        "declined threshold confirmation remains pending")
    assert_eq(Result.batch_status(false, {}), "failed",
        "actual memorization failure remains failed")

    local order = {}
    local callback_persisted
    local persisted = Result.persist_partial_before_callback(
        partial,
        function()
            order[#order + 1] = "persist"
            return true, "saved"
        end,
        function(ok)
            callback_persisted = ok
            order[#order + 1] = "callback"
        end)
    assert_true(persisted, "partial helper reports durable passage")
    assert_eq(order[1], "persist",
        "partial passage persistence runs before direct/confirm callback")
    assert_eq(order[2], "callback",
        "partial callback runs only after persistence attempt")
    assert_true(callback_persisted,
        "partial callback receives persistence outcome")

    local state = Generation.new()
    local first = Generation.begin(state)
    assert_true(Generation.is_current(state, first), "new token is current")
    assert_true(Generation.cancel(state, first), "current chain cancels")
    assert_true(not Generation.is_current(state, first),
        "cancel blocks future scheduled iterations")
    local second = Generation.begin(state)
    assert_true(Generation.is_current(state, second), "new chain gets new token")
    assert_true(not Generation.cancel(state, first),
        "stale dismiss cannot cancel newer chain")
    local accepted = 0
    assert_true(not Generation.if_current(state, first, function()
        accepted = accepted + 1
    end), "stale callback result is rejected")
    assert_eq(accepted, 0, "stale callback cannot save or send")
    assert_true(Generation.if_current(state, second, function()
        accepted = accepted + 1
    end), "current callback result is accepted")
    assert_eq(accepted, 1, "only current generation may commit a result")
end

return run_tests
