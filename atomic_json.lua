-- Atomic JSON persistence with a non-destructive Windows replacement fallback.

local json = require("json")

local AtomicJson = {}
local sequence = 0
local BACKUP_SUFFIX = ".atomic-json.bak"

local function failure(code, detail)
    return false, {
        code = code,
        detail = detail and tostring(detail) or nil,
    }
end

local function default_token()
    sequence = sequence + 1
    local identity = tostring({}):gsub("[^%w]", "")
    return table.concat({
        tostring(os.time()),
        tostring(math.floor(os.clock() * 1000000)),
        tostring(sequence),
        identity,
    }, "_")
end

local function call(operation, ...)
    local ok, result, detail = pcall(operation, ...)
    if not ok then return false, result end
    return result and true or false, detail
end

local function default_probe(path, open)
    local file, open_error, open_code = open(path, "rb")
    if file then
        pcall(file.close, file)
        return "present"
    end
    local message = tostring(open_error or ""):lower()
    if open_code == 2 or message:find("no such file", 1, true)
        or message:find("cannot find the file", 1, true) then
        return "absent"
    end
    return "error", open_error
end

local function validate_json_file(path, open, decode, validate)
    if validate then
        local called, valid, detail = pcall(validate, path)
        if not called then return nil, valid end
        return valid == true, detail
    end

    local file, open_error = open(path, "rb")
    if not file then return nil, open_error end
    local read_ok, content = pcall(file.read, file, "*all")
    local close_ok, closed = pcall(file.close, file)
    if not read_ok or content == nil or not close_ok or not closed then
        return nil, not read_ok and content or (not close_ok and closed or nil)
    end
    if content:match("^%s*$") then return false, "empty_json" end
    local decoded_ok, value = pcall(decode, content)
    if not decoded_ok then return false, value end
    if type(value) ~= "table" then return false, "root_not_object_or_array" end
    return true
end

function AtomicJson.backup_path(path)
    return path .. BACKUP_SUFFIX
end

--- Restore the stable backup left by an interrupted Windows replacement.
-- A canonical file wins only after it decodes as an object/array JSON value.
function AtomicJson.recover(path, opts)
    opts = opts or {}
    local open = opts.open or io.open
    local decode = opts.decode or json.decode
    local rename = opts.rename or os.rename
    local remove = opts.remove or os.remove
    local probe = opts.probe or function(candidate)
        return default_probe(candidate, open)
    end
    local backup_path = AtomicJson.backup_path(path)
    local target_state, target_error = probe(path)
    if target_state == "error" then
        return failure("recovery_probe_failed", target_error)
    end
    local backup_state, backup_error = probe(backup_path)
    if backup_state == "error" then
        return failure("recovery_probe_failed", backup_error)
    end

    if backup_state == "absent" then
        return true, target_state == "absent" and "absent" or nil
    end

    if target_state == "present" then
        local target_valid, validation_detail = validate_json_file(
            path, open, decode, opts.validate)
        if target_valid == nil then
            local _, reason = failure(
                "recovery_validation_failed", validation_detail)
            reason.backup_path = backup_path
            return false, reason
        end
        if target_valid then
            local cleaned, cleanup_error = call(remove, backup_path)
            if not cleaned then
                return true, {
                    code = "backup_cleanup_failed",
                    detail = cleanup_error and tostring(cleanup_error) or nil,
                    committed = true,
                    backup_path = backup_path,
                }
            end
            return true
        end

        local backup_valid, backup_detail = validate_json_file(
            backup_path, open, decode, opts.validate)
        if backup_valid == nil then
            local _, reason = failure(
                "recovery_validation_failed", backup_detail)
            reason.backup_path = backup_path
            return false, reason
        end
        if not backup_valid then
            local _, reason = failure("recovery_no_valid_json",
                "canonical and backup are invalid")
            reason.backup_path = backup_path
            reason.canonical_detail = tostring(validation_detail or "")
            reason.backup_detail = tostring(backup_detail or "")
            return false, reason
        end

        local removed, remove_error = call(remove, path)
        if not removed then
            local _, reason = failure("recovery_failed", remove_error)
            reason.backup_path = backup_path
            return false, reason
        end
    else
        local backup_valid, backup_detail = validate_json_file(
            backup_path, open, decode, opts.validate)
        if backup_valid == nil then
            local _, reason = failure(
                "recovery_validation_failed", backup_detail)
            reason.backup_path = backup_path
            return false, reason
        end
        if not backup_valid then
            local _, reason = failure("recovery_no_valid_json",
                "backup is invalid and canonical is absent")
            reason.backup_path = backup_path
            reason.backup_detail = tostring(backup_detail or "")
            return false, reason
        end
    end

    local restored, restore_error = call(rename, backup_path, path)
    if not restored then
        local _, reason = failure("recovery_failed", restore_error)
        reason.backup_path = backup_path
        return false, reason
    end
    return true, {
        code = "backup_recovered",
        recovered = true,
        backup_path = backup_path,
    }
end

--- Encode and atomically replace a JSON file.
-- opts is an additive test seam; production callers use the standard Lua I/O.
function AtomicJson.write(path, value, opts)
    opts = opts or {}
    local encode = opts.encode or json.encode
    local open = opts.open or io.open
    local rename = opts.rename or os.rename
    local remove = opts.remove or os.remove
    local token = opts.token or default_token()

    -- Encoding must finish before any filesystem mutation.
    local encoded_ok, encoded = pcall(encode, value)
    if not encoded_ok or type(encoded) ~= "string" then
        return failure("encode_failed", encoded)
    end

    local recovery_ok, recovery_reason = AtomicJson.recover(path, {
        open = opts.probe_open or io.open,
        rename = rename,
        remove = remove,
        probe = opts.probe,
        decode = opts.decode,
        validate = opts.validate,
    })
    if not recovery_ok then return false, recovery_reason end

    local temp_path = path .. ".tmp." .. token
    local backup_path = AtomicJson.backup_path(path)
    local file, open_error = open(temp_path, "wb")
    if not file then
        return failure("temp_open_failed", open_error)
    end

    local write_ok, wrote = pcall(file.write, file, encoded)
    local close_ok, closed = pcall(file.close, file)
    if not write_ok or not wrote or not close_ok or not closed then
        call(remove, temp_path)
        return failure("temp_write_failed",
            not write_ok and wrote or (not close_ok and closed or nil))
    end

    -- POSIX replaces an existing destination atomically here.
    local replaced, replace_error = call(rename, temp_path, path)
    if replaced then
        return true
    end

    -- Windows does not rename over an existing file. Move the original aside,
    -- install the completed temp file, then remove only our owned backup.
    local backed_up, backup_error = call(rename, path, backup_path)
    if not backed_up then
        call(remove, temp_path)
        return failure("replace_failed", replace_error or backup_error)
    end

    local installed, install_error = call(rename, temp_path, path)
    if installed then
        local cleaned, cleanup_error = call(remove, backup_path)
        if not cleaned then
            return true, {
                code = "backup_cleanup_failed",
                detail = cleanup_error and tostring(cleanup_error) or nil,
                committed = true,
                backup_path = backup_path,
            }
        end
        return true
    end

    -- Replacement failed after the fallback moved the original. Restore it
    -- before returning and clean the still-owned temp file.
    local restored, restore_error = call(rename, backup_path, path)
    call(remove, temp_path)
    if not restored then
        -- The backup is deliberately retained: it is now the only preserved
        -- copy of the original and must not be destroyed.
        local _, reason = failure("restore_failed", restore_error or install_error)
        reason.backup_path = backup_path
        return false, reason
    end
    call(remove, backup_path)
    local _, reason = failure("replace_failed", install_error)
    reason.restored = true
    return false, reason
end

return AtomicJson
