-- Reconcile pending cards with Anki: log to Recently sent, delete from queue, highlight policy.

local _               = require("gettext")
local logger          = require("logger")
local CardStorage     = require("card_storage")
local CardFields      = require("card_fields")
local HighlightStatus = require("highlight_status")
local NoteTypeProfiles = require("note_type_profiles")
local PluginConstants = require("plugin_constants")

local CardReconcile = {}

local function effective_model(config, card)
    return NoteTypeProfiles.normalize_model_name(
        (card and card.target_model and card.target_model ~= "") and card.target_model
        or (card and card.model and card.model ~= "") and card.model
        or CardFields.default_vocabulary_model({ anki = config }))
end

local function card_kind_for(card, anki_config)
    if CardStorage.is_memorization(card) then
        return "memorization"
    end
    return "vocabulary"
end

function CardReconcile.send_status_label(status)
    if status == "sent" then return _("Sent")
    elseif status == "duplicate" or status == "already_in_anki" then return _("Already in Anki")
    elseif status == "verified" then return _("Verified in Anki")
    elseif status == "checked" then return _("Found in Anki")
    end
    return status or ""
end

function CardReconcile.history_warning_message(count)
    count = math.max(1, tonumber(count) or 1)
    if count == 1 then
        return _(
            "Anki was confirmed and the card was removed from pending, but Recently sent history could not be saved.")
    end
    return _("Anki was confirmed and ") .. tostring(count)
        .. _(
            " cards were removed from pending, but Recently sent history could not be saved.")
end

function CardReconcile.finish(item, anki_config, ui, opts)
    opts = opts or {}
    local card = item and item.card
    if not card then
        return false, { code = "invalid_card" }
    end

    local deck = opts.deck or card.target_deck or ""
    local model = opts.model or effective_model(anki_config, card)
    local status = opts.status or "sent"
    local pos0, pos1 = card.highlight_pos0, card.highlight_pos1
    local kind = card_kind_for(card, anki_config)
    local document_path = card.document_path

    local recent_ok, recent_reason = CardStorage.record_recent_sent({
        phrase      = card.phrase or "",
        book_title  = card.book_title or "",
        card_kind   = kind,
        deck        = deck,
        model       = model,
        status      = status,
        sent_at     = os.time(),
        highlight_pos0 = pos0,
        highlight_pos1 = pos1,
        document_path = document_path,
        memorization_text = card.memorization_text or "",
    })

    local deleted, delete_reason = CardStorage.delete_matching_card(card)
    local queue_durable = deleted or delete_reason == "not_found"
    local marked_sent = false
    local marker_reason
    if not queue_durable then
        marked_sent, marker_reason = CardStorage.mark_matching_sent(card)
        queue_durable = marked_sent and true or false
        if marked_sent then
            logger.warn(PluginConstants.ID,
                "reconcile: queue delete failed; persisted sent marker")
        end
    end

    if not queue_durable then
        logger.warn(PluginConstants.ID,
            "reconcile: accepted card could not be secured in local queue")
        return false, {
            code = "queue_persistence_failed",
            recent_saved = recent_ok and true or false,
            delete_reason = delete_reason,
            marker_reason = marker_reason,
        }
    end

    -- Highlight state changes only after the queue has durably removed or
    -- excluded the accepted card from pending/auto-send.
    local current_document = ui and ui.document and ui.document.file
    if pos0 and document_path and document_path ~= ""
        and current_document == document_path then
        HighlightStatus.remove_highlight(ui, pos0, pos1)
    end

    if not recent_ok then
        logger.warn(PluginConstants.ID,
            "reconcile: recent history write failed after queue secured")
        local queue_state = marked_sent and "marked_sent" or "deleted"
        return true, queue_state, {
            code = "recent_sent_persistence_failed",
            warning = true,
            warning_message = CardReconcile.history_warning_message(1),
            queue_state = queue_state,
            recent_reason = recent_reason,
        }
    end

    return true, marked_sent and "marked_sent" or "deleted"
end

return CardReconcile
