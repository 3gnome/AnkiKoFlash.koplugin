-- Cloud sync for AnkiKoFlash via KOReader's SyncService.

local DataStorage   = require("datastorage")
local json          = require("json")
local logger        = require("logger")
local AtomicJson    = require("atomic_json")

local CardStorage       = require("card_storage")
local PluginConstants   = require("plugin_constants")
local SettingsPersistence = require("settings_persistence")

local CARDS_FILE = DataStorage:getDataDir() .. "/" .. PluginConstants.CARDS_FILE
local BASELINE_FILE = CARDS_FILE .. ".sync"

local CardSync = {}

-- ── Helpers ──────────────────────────────────────────────────────────────

local function card_key(card)
    return CardStorage.identity_key(card, true)
end

local function read_json_array(path)
    local recovered, recovery_reason = AtomicJson.recover(path)
    if not recovered then
        return nil, type(recovery_reason) == "table"
            and recovery_reason.code or "recovery_failed"
    end
    local f, open_error, open_code = io.open(path, "r")
    if not f then
        local message = tostring(open_error or ""):lower()
        if open_code == 2 or message:find("no such file", 1, true)
            or message:find("cannot find the file", 1, true) then
            return {}, "absent"
        end
        return nil, "read_failed"
    end
    local read_ok, content = pcall(f.read, f, "*all")
    local close_ok, closed = pcall(f.close, f)
    if not read_ok or content == nil or not close_ok or not closed then
        return nil, "read_failed"
    end
    local trimmed = content:match("^%s*(.-)%s*$")
    if trimmed == "" then return {}, "empty" end
    if trimmed:sub(1, 1) ~= "[" or trimmed:sub(-1) ~= "]" then
        return nil, "malformed"
    end
    local ok, data = pcall(json.decode, content)
    if ok and type(data) == "table" then
        local count = 0
        for key, card in pairs(data) do
            count = count + 1
            if type(key) ~= "number" or key < 1 or key % 1 ~= 0
                or type(card) ~= "table" then
                return nil, "malformed"
            end
        end
        if count == #data then return data, "ok" end
    end
    return nil, "malformed"
end

local function is_absent_error(message, code)
    message = tostring(message or ""):lower()
    return code == 2
        or message:find("no such file", 1, true) ~= nil
        or message:find("cannot find the file", 1, true) ~= nil
end

local function verify_absent(path)
    local f, open_error, open_code = io.open(path, "rb")
    if f then
        pcall(f.close, f)
        return false, "baseline_still_exists"
    end
    if is_absent_error(open_error, open_code) then return true end
    return false, "baseline_verify_failed"
end

--- Return the effective timestamp for a card (updated_at or date fallback).
local function card_timestamp(card)
    if card.updated_at then return card.updated_at end
    -- Fallback: parse date string "YYYY-MM-DD" into epoch.
    if card.date then
        local y, m, d = card.date:match("^(%d+)-(%d+)-(%d+)$")
        if y then
            return os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d) })
        end
    end
    return 0
end

local function values_equal(left, right)
    if type(left) ~= type(right) then return false end
    if type(left) ~= "table" then return left == right end
    for key, value in pairs(left) do
        if not values_equal(value, right[key]) then return false end
    end
    for key, _value in pairs(right) do
        if left[key] == nil then return false end
    end
    return true
end

local function card_changed(card, cached_card)
    if type(card) ~= "table" or type(cached_card) ~= "table" then
        return not values_equal(card, cached_card)
    end
    -- updated_at is conflict-resolution metadata, not a content edit.
    for key, value in pairs(card) do
        if key ~= "updated_at"
            and not values_equal(value, cached_card[key]) then
            return true
        end
    end
    for key, _value in pairs(cached_card) do
        if key ~= "updated_at" and card[key] == nil then return true end
    end
    return false
end

local function stable_wrap(tag, payload)
    payload = tostring(payload or "")
    return tag .. tostring(#payload) .. ":" .. payload
end

local function stable_value_key(value, stack)
    local kind = type(value)
    if kind == "nil" then return "n" end
    if kind == "boolean" then return value and "b1" or "b0" end
    if kind == "number" then
        return stable_wrap("d", string.format("%.17g", value))
    end
    if kind == "string" then return stable_wrap("s", value) end
    if kind ~= "table" then return stable_wrap(kind:sub(1, 1), value) end
    stack = stack or {}
    if stack[value] then return "cycle" end
    stack[value] = true
    local parts = {}
    for key, child in pairs(value) do
        parts[#parts + 1] = stable_wrap("k", stable_value_key(key, stack))
            .. stable_wrap("v", stable_value_key(child, stack))
    end
    table.sort(parts)
    stack[value] = nil
    return stable_wrap("t", table.concat(parts))
end

local function merge_equal_timestamp_values(local_value, remote_value, cached_value)
    if values_equal(local_value, remote_value) then return local_value end
    local local_changed = not values_equal(local_value, cached_value)
    local remote_changed = not values_equal(remote_value, cached_value)
    if local_changed and not remote_changed then return local_value end
    if remote_changed and not local_changed then return remote_value end

    if type(local_value) == "table" and type(remote_value) == "table" then
        local cached_table = type(cached_value) == "table" and cached_value or {}
        local merged = {}
        local keys = {}
        for key in pairs(local_value) do keys[key] = true end
        for key in pairs(remote_value) do keys[key] = true end
        for key in pairs(cached_table) do keys[key] = true end
        for key in pairs(keys) do
            merged[key] = merge_equal_timestamp_values(
                local_value[key], remote_value[key], cached_table[key])
        end
        return merged
    end

    -- A primitive changed differently on both sides. Schema fields cannot hold
    -- both values, so choose by content rather than device/merge direction.
    if stable_value_key(local_value) >= stable_value_key(remote_value) then
        return local_value
    end
    return remote_value
end

local function resolve_both_present(local_card, remote_card, cached_card)
    if cached_card then
        local local_changed = card_changed(local_card, cached_card)
        local remote_changed = card_changed(remote_card, cached_card)
        if local_changed and not remote_changed then return local_card end
        if remote_changed and not local_changed then return remote_card end
    end

    local local_timestamp = card_timestamp(local_card)
    local remote_timestamp = card_timestamp(remote_card)
    if remote_timestamp > local_timestamp then return remote_card end
    if local_timestamp > remote_timestamp then return local_card end
    return merge_equal_timestamp_values(local_card, remote_card, cached_card or {})
end

-- ── Three-Way Merge ──────────────────────────────────────────────────────

--- SyncService merge callback.
-- @param local_path   Path to the local cards file.
-- @param cached_path  Path to the cached baseline (last upload snapshot).
-- @param income_path  Path to the file just downloaded from the cloud.
-- @return true on success (required by SyncService).
function CardSync.merge_cards(local_path, cached_path, income_path)
    local local_cards, local_status = read_json_array(local_path)
    local cached_cards, cached_status = read_json_array(cached_path)
    local income_cards, income_status = read_json_array(income_path)
    if not local_cards or not cached_cards or not income_cards then
        local status = not local_cards and local_status
            or (not cached_cards and cached_status) or income_status
        logger.warn(PluginConstants.ID,
            "card sync merge: JSON input unavailable:", status)
        return false, {
            code = "read_failed",
            source_status = status,
        }
    end

    -- Build index tables keyed by card_key.
    local function index_by_key(cards)
        local idx = {}
        for _i, c in ipairs(cards) do
            idx[card_key(c)] = c
        end
        return idx
    end

    local cached_idx = index_by_key(cached_cards)
    local income_idx = index_by_key(income_cards)
    -- Missing keys express deletions only in decoded JSON arrays compared
    -- against a decoded baseline. Missing/zero-byte inputs are read as empty
    -- but remain non-authoritative; malformed inputs abort above.
    local remote_authoritative =
        income_status == "ok" and cached_status == "ok"
    local local_authoritative =
        local_status == "ok" and cached_status == "ok"

    local merged = {}
    local seen   = {}

    -- Pass 1: iterate local cards.
    for _i, lc in ipairs(local_cards) do
        local key = card_key(lc)
        if not seen[key] then
            seen[key] = true
            local rc = income_idx[key]
            local cc = cached_idx[key]

            if rc then
                -- Prefer the only content-edited side regardless of clock skew.
                -- True concurrent edits retain timestamp precedence; equal
                -- timestamps merge non-conflicting fields deterministically.
                table.insert(merged, resolve_both_present(lc, rc, cc))
            elseif cc and remote_authoritative then
                -- Card in local + cached but NOT in remote → deleted remotely.
                -- Preserve a concurrent local edit; otherwise propagate delete.
                if card_changed(lc, cc) then
                    table.insert(merged, lc)
                end
            else
                -- Card only in local → new on this device → keep.
                table.insert(merged, lc)
            end
        end
    end

    -- Pass 2: remote-only cards (in income but not in local).
    for _i, rc in ipairs(income_cards) do
        local key = card_key(rc)
        if not seen[key] then
            seen[key] = true
            local cc = cached_idx[key]

            if not cc or not local_authoritative or card_changed(rc, cc) then
                -- New on other device → add.
                -- A remote edit also wins over a concurrent local deletion.
                table.insert(merged, rc)
            end
        end
    end

    local written, reason = AtomicJson.write(local_path, merged)
    if not written then
        logger.warn(PluginConstants.ID,
            "card sync merge: atomic write failed:",
            type(reason) == "table" and reason.code or "unknown")
        return false, reason
    end
    return true
end

CardSync.card_key = card_key

function CardSync.remove_sync_baseline()
    local called, removed, remove_error, remove_code =
        pcall(os.remove, BASELINE_FILE)
    if not called then return false, "baseline_remove_failed" end
    if not removed and not is_absent_error(remove_error, remove_code) then
        return false, "baseline_remove_failed"
    end
    return verify_absent(BASELINE_FILE)
end

function CardSync.persist_server(cfg, server, on_saved, operation)
    cfg = cfg or {}
    local ok, candidate, reason, message = SettingsPersistence.transaction(
        cfg, function(next_cfg) next_cfg.sync_server = server end,
        operation or "cloud_sync_server")
    if not ok then return false, reason, message end
    SettingsPersistence.commit(cfg, candidate)
    if on_saved then on_saved(cfg) end
    return true
end

function CardSync.change_server(cfg, server, on_saved)
    cfg = cfg or {}
    local removed, remove_reason = CardSync.remove_sync_baseline()
    if not removed then
        return false, {
            code = "baseline_reset_failed",
            reason = remove_reason,
        }
    end

    local persisted, persist_reason, persist_message = CardSync.persist_server(
        cfg, server, on_saved, "cloud_sync_server")
    if persisted then return true end
    return false, {
        code = "server_persistence_failed",
        reason = persist_reason,
        message = persist_message,
        baseline_removed = true,
    }
end

-- ── Sync Runner ──────────────────────────────────────────────────────────

function CardSync.run_sync(server, is_silent)
    local SyncService = require("frontend/apps/cloudstorage/syncservice")
    SyncService.sync(server, CARDS_FILE, CardSync.merge_cards, is_silent)
end

-- ── Cloud Sync Dialog ────────────────────────────────────────────────────

function CardSync.show_cloud_sync_dialog(cfg, on_saved, opts)
    local ButtonDialog  = require("ui/widget/buttondialog")
    local ConfirmBox    = require("ui/widget/confirmbox")
    local InfoMessage   = require("ui/widget/infomessage")
    local Notification  = require("ui/widget/notification")
    local SyncService   = require("frontend/apps/cloudstorage/syncservice")
    local UIManager     = require("ui/uimanager")
    local _             = require("gettext")
    local Nav           = require("nav")
    opts = opts or {}
    local parent_fn = opts.parent_fn

    local function finish()
        Nav.after_close(nil, parent_fn)
    end

    local function change_server(server, success_message)
        local changed, reason = CardSync.change_server(cfg, server, on_saved)
        if changed then
            UIManager:show(Notification:new {
                text = success_message,
                timeout = 3,
            })
            return true
        end

        if reason and reason.code == "server_persistence_failed" then
            UIManager:show(InfoMessage:new {
                text = reason.message or _(
                    "Could not save cloud sync settings. Please retry."),
                timeout = 7,
            })
            return false
        end

        UIManager:show(InfoMessage:new {
            text = _(
                "Could not reset cloud sync state. The previous server was kept."),
            timeout = 8,
        })
        return false
    end

    if not cfg.sync_server then
        local sync_settings = SyncService:new{}
        sync_settings.onClose = function(this)
            UIManager:close(this)
            finish()
        end
        sync_settings.onConfirm = function(server)
            if change_server(server, _("Cloud sync server saved")) then
                CardSync.run_sync(server, false)
            end
            finish()
        end
        UIManager:show(sync_settings)
        return
    end

    local server_name = cfg.sync_server.name or cfg.sync_server.address or "Cloud"
    local dlg
    dlg = ButtonDialog:new {
        title   = _("Cloud Sync"),
        buttons = {
            {{
                text     = _("Sync Now"),
                callback = function()
                    UIManager:close(dlg)
                    CardSync.run_sync(cfg.sync_server, false)
                    finish()
                end,
            }},
            {{
                text     = _("Change Server"),
                callback = function()
                    UIManager:close(dlg)
                    local sync_settings = SyncService:new{}
                    sync_settings.onClose = function(this)
                        UIManager:close(this)
                        finish()
                    end
                    sync_settings.onConfirm = function(new_server)
                        change_server(new_server, _("Server changed"))
                        finish()
                    end
                    UIManager:show(sync_settings)
                end,
            }},
            {{
                text     = _("Remove Server"),
                callback = function()
                    UIManager:close(dlg)
                    UIManager:show(ConfirmBox:new {
                        text = _("Remove cloud sync server?"),
                        ok_text = _("Remove"),
                        ok_callback = function()
                            change_server(nil, _("Cloud sync removed"))
                            finish()
                        end,
                        cancel_callback = finish,
                    })
                end,
            }},
            {{
                text     = _("Close"),
                callback = function()
                    UIManager:close(dlg)
                    finish()
                end,
            }},
        },
    }
    UIManager:show(dlg)
end

return CardSync
