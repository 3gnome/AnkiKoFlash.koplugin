-- Send flow: deck picker at send time; note type chosen at generation.

local ConfirmBox     = require("ui/widget/confirmbox")
local Notification   = require("ui/widget/notification")
local UIManager      = require("ui/uimanager")
local _              = require("gettext")

local AnkiSync         = require("anki_sync")
local CardDefaults     = require("card_defaults")
local CardStorage      = require("card_storage")
local DeckPicker       = require("deck_picker")
local CardFields       = require("card_fields")
local NoteTypeProfiles = require("note_type_profiles")
local SettingsPersistence = require("settings_persistence")
local UiBusy           = require("ui_busy")
local CardReconcile    = require("card_reconcile")

local SendFlow = {}

-- Sentinel for user-dismissed flows (deck picker, confirm box). Do not compare translated strings.
SendFlow.CANCELLED = "__ankikoflash_cancelled__"

function SendFlow.is_cancelled(err)
    return err == SendFlow.CANCELLED or err == _("Cancelled")
end

local function recent_decks_with(config, deck)
    local list = {}
    table.insert(list, deck)
    for _i, d in ipairs(config.recent_decks or {}) do
        if d ~= deck and #list < 5 then table.insert(list, d) end
    end
    return list
end

function SendFlow.effective_model(config, card)
    return NoteTypeProfiles.normalize_model_name(
        (card and card.target_model and card.target_model ~= "") and card.target_model
        or (card and card.model and card.model ~= "") and card.model
        or CardFields.default_vocabulary_model({ anki = config }))
end

function SendFlow.remember_send(config, deck, model, opts)
    opts = opts or {}
    config = config or {}
    local previous_deck = config.last_send_deck
    local previous_model = config.last_send_model
    local previous_recent = config.recent_decks
    config.last_send_deck  = deck
    config.last_send_model = model
    if opts.touch_recent then
        config.recent_decks = recent_decks_with(config, deck)
    end
    local ok, reason =
        SettingsPersistence.save(config, opts.operation or "recent_send")
    if not ok then
        config.last_send_deck = previous_deck
        config.last_send_model = previous_model
        config.recent_decks = previous_recent
        return false, reason
    end
    return true
end

-- use_configured_deck: prefer card.target_deck and per-type Card defaults.
-- Default (viewer quick-send): prefer last_send_deck for repeat manual sends.
function SendFlow.resolve_deck(config, card, opts)
    opts = opts or {}
    config = config or {}
    if card and card.target_deck and card.target_deck ~= "" then
        return card.target_deck
    end
    local configured = CardDefaults.deck_for_card({ anki = config }, card)
    if opts.use_configured_deck then
        return configured
    end
    return config.last_send_deck or configured
end

function SendFlow.can_quick_send(config, card, opts)
    local deck = SendFlow.resolve_deck(config, card, opts)
    return deck and deck ~= ""
end

local function finish_send(config, card, deck, model, ui, done, opts)
    opts = opts or {}
    local ok, err_or_suffix, send_status, sent_deck, sent_model =
        AnkiSync.send_card(config, card, {
        deck      = deck,
        model     = model,
        skip_sync = opts.skip_sync,
    })
    if ok then
        sent_deck = sent_deck or deck
        sent_model = sent_model or model
        local settings_ok, settings_reason = true, nil
        local reconcile_warning
        if card then
            card.target_deck  = sent_deck
            card.target_model = sent_model
            local reconciled, _queue_state
            reconciled, _queue_state, reconcile_warning =
                CardReconcile.finish({ card = card }, config, ui, {
                status = send_status == "duplicate" and "already_in_anki"
                    or send_status == "verified" and "verified"
                    or "sent",
                deck   = sent_deck,
                model  = sent_model,
            })
            if not reconciled then
                ok = false
                err_or_suffix = _(
                    "Anki was confirmed, but the local queue could not be updated.")
            end
        end
        settings_ok, settings_reason = SendFlow.remember_send(
            config, sent_deck, sent_model, {
                touch_recent = true,
                operation = "recent_send",
            })
        local notices = {}
        -- Warn when the note type has no Etymology field, so the looked-up
        -- etymology was silently left out of the card.
        local cached_fields = config and config.cached_model_fields
        local sent_fields = cached_fields and cached_fields[sent_model or model]
        if sent_fields and CardFields.etymology_will_be_dropped(card, sent_fields) then
            notices[#notices + 1] = _(
                "This note type has no Etymology field, so the etymology was not included.")
        end
        if send_status == "duplicate" then
            notices[#notices + 1] = _(
                "Exact note already in Anki; pending card reconciled.")
        elseif send_status == "verified" then
            notices[#notices + 1] = _(
                "Send was uncertain, but the exact note was verified in Anki.")
        end
        if err_or_suffix and err_or_suffix ~= "" then
            notices[#notices + 1] = err_or_suffix:gsub("^%s+", "")
        end
        if reconcile_warning and reconcile_warning.warning_message then
            notices[#notices + 1] = reconcile_warning.warning_message
        end
        if not settings_ok and not opts.background then
            notices[#notices + 1] = _(
                "Sent to Anki, but recent deck settings could not be saved.")
        end
        if #notices > 0 and not opts.background then
            UIManager:show(Notification:new {
                text    = table.concat(notices, "\n"),
                timeout = 4,
            })
        end
        if done then
            local callback_error
            if not ok then callback_error = err_or_suffix end
            done(ok, callback_error, {
                settings_saved = settings_ok,
                settings_error = settings_reason,
                reconcile_warning = reconcile_warning,
                send_status = send_status,
            })
        end
        return
    end
    if done then
        done(ok, ok and nil or err_or_suffix, {
            send_status = send_status,
            pending = true,
        })
    end
end

function SendFlow.execute_send(config, card, deck, model, ui, done, opts)
    opts = opts or {}
    config = config or {}
    model = model or SendFlow.effective_model(config, card)
    deck = deck or SendFlow.resolve_deck(config, card, opts)

    if not deck or deck == "" then
        if done then done(nil, _("No deck selected")) end
        return
    end

    local function proceed()
        UiBusy.run(_("Sending to Anki…"), function()
            finish_send(config, card, deck, model, ui, done, opts)
        end)
    end

    if opts.skip_duplicate_check then
        proceed()
        return
    end

    local dup = CardStorage.find_pending_duplicate(
        card and card.phrase, card and card.book_title, card)
    if dup then
        UIManager:show(ConfirmBox:new {
            text = _("This phrase is already in your pending queue for this book. Send anyway?"),
            ok_text = _("Send anyway"),
            ok_callback = proceed,
            cancel_callback = function()
                if done then done(nil, SendFlow.CANCELLED) end
            end,
        })
        return
    end
    proceed()
end

function SendFlow.prompt_and_send(config, card, done, opts)
    opts = opts or {}
    config = config or {}
    if not config.url or config.url == "" then
        if done then
            done(nil, _("AnkiConnect URL not set. Use AnkiKoFlash → Settings."))
        end
        return
    end
    local model = SendFlow.effective_model(config, card)
    local deck_initial = (card and card.target_deck and card.target_deck ~= "")
                       and card.target_deck
                       or config.last_send_deck
                       or AnkiSync.resolve_base_deck(config, card)

    DeckPicker.show(config, card, function(chosen_deck)
        SendFlow.execute_send(
            config, card, chosen_deck, model,
            opts.ui, done, opts)
    end, {
        current_deck = deck_initial,
        title        = _("Choose Deck"),
        on_cancel    = function()
            if done then done(nil, SendFlow.CANCELLED) end
        end,
    })
end

function SendFlow.quick_send(config, card, done, opts)
    opts = opts or {}
    local deck = SendFlow.resolve_deck(config, card, opts)
    if not SendFlow.can_quick_send(config, card, opts) then
        SendFlow.prompt_and_send(config, card, done, opts)
        return
    end
    SendFlow.execute_send(
        config, card, deck,
        SendFlow.effective_model(config, card),
        opts.ui, done, opts)
end

function SendFlow.viewer_callbacks(config, card, ui)
    config = config or {}
    return {
        can_quick_send = SendFlow.can_quick_send(config, card),
        on_send = function(done)
            SendFlow.prompt_and_send(config, card, done, { ui = ui })
        end,
        on_quick_send = function(done)
            SendFlow.quick_send(config, card, done, { ui = ui })
        end,
    }
end

return SendFlow
