-- Pure memorization result metadata and queue-reconciliation policy.

local MemorizationResult = {}

function MemorizationResult.from_counts(total, sent, already_present, confirmed)
    total = math.max(0, tonumber(total) or 0)
    sent = math.max(0, tonumber(sent) or 0)
    already_present = math.max(0, tonumber(already_present) or 0)
    confirmed = math.max(0, math.min(total, tonumber(confirmed) or 0))
    local failed = total - confirmed
    return {
        total = total,
        sent = sent,
        already_present = already_present,
        verified = math.max(0, confirmed - already_present - sent),
        failed = failed,
        all_sent = failed == 0,
        partial = confirmed > 0 and failed > 0,
    }
end

function MemorizationResult.should_reconcile(ok, info)
    return ok == true and (type(info) ~= "table" or info.all_sent == true)
end

function MemorizationResult.batch_status(ok, info)
    if ok and type(info) == "table" and (info.sent or 0) == 0
        and (info.already_present or 0) > 0 then
        return "reconciled"
    end
    if ok then return "sent" end
    if type(info) == "table" and info.requires_confirmation then
        return "pending"
    end
    return "failed"
end

-- Partial sends must be made retry-safe before any completion callback can
-- dismiss or replace the originating UI.
function MemorizationResult.persist_partial_before_callback(
    info, persist_fn, callback)
    local persisted, persist_reason
    if type(info) == "table" and info.partial == true then
        local called, result, reason = pcall(persist_fn)
        if called then
            persisted, persist_reason = result, reason
        else
            persisted, persist_reason = false, result
        end
    end
    if callback then callback(persisted, persist_reason) end
    return persisted, persist_reason
end

return MemorizationResult
