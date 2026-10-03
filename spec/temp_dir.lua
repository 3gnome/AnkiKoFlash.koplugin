-- Owned temporary directories for specs. All paths are direct children of the
-- operating system's temporary directory and only tracked paths are removed.

local TempDir = {}
TempDir.__index = TempDir

local is_windows = package.config:sub(1, 1) == "\\"
local separator = is_windows and "\\" or "/"

local function pack(...)
    return { n = select("#", ...), ... }
end

local function command_succeeded(result)
    return result == true or result == 0
end

local function shell_quote(path)
    if is_windows then
        return '"' .. path:gsub('"', '""') .. '"'
    end
    return "'" .. path:gsub("'", "'\\''") .. "'"
end

local function is_absolute(path)
    if is_windows then
        return path:match("^%a:[/\\]") ~= nil
            or path:match("^[/\\][/\\]") ~= nil
    end
    return path:sub(1, 1) == "/"
end

local function normalize_root(path)
    if not path or path == "" or not is_absolute(path) then
        return nil
    end
    path = path:gsub("[/\\]", separator)
    local minimum_length = is_windows and 3 or 1
    while #path > minimum_length and path:sub(-1) == separator do
        path = path:sub(1, -2)
    end
    return path
end

local function os_temp_root()
    local names
    if is_windows then
        names = { "TEMP", "TMP", "TMPDIR" }
    else
        names = { "TMPDIR", "TEMP", "TMP" }
    end
    for _, name in ipairs(names) do
        local root = normalize_root(os.getenv(name))
        if root then
            return root
        end
    end
    if not is_windows then
        return "/tmp"
    end
    error("no absolute OS temporary directory found in TEMP, TMP, or TMPDIR")
end

local function path_exists(path)
    local command
    if is_windows then
        command = "if exist " .. shell_quote(path .. "\\NUL")
            .. " (exit /b 0) else (exit /b 1)"
    else
        command = "test -e " .. shell_quote(path)
    end
    return command_succeeded(os.execute(command))
end

local function safe_prefix(prefix)
    prefix = tostring(prefix or "ankikoflash")
    prefix = prefix:gsub("[^%w_-]", "_")
    if prefix == "" then
        prefix = "ankikoflash"
    end
    return prefix
end

local function unique_token(attempt)
    local identity = tostring({}):gsub("[^%w]", "")
    return table.concat({
        tostring(os.time()),
        tostring(math.floor(os.clock() * 1000000)),
        tostring(attempt),
        identity,
    }, "_")
end

local function make_directory(path)
    local command
    if is_windows then
        command = "mkdir " .. shell_quote(path) .. " >nul 2>nul"
    else
        command = "mkdir -- " .. shell_quote(path) .. " >/dev/null 2>&1"
    end
    return command_succeeded(os.execute(command))
end

local function remove_directory(path)
    local command
    if is_windows then
        command = "rmdir /s /q " .. shell_quote(path) .. " >nul 2>nul"
    else
        command = "rm -rf -- " .. shell_quote(path)
    end
    return command_succeeded(os.execute(command))
end

function TempDir.new(prefix)
    return setmetatable({
        root = os_temp_root(),
        prefix = safe_prefix(prefix),
        owned = {},
    }, TempDir)
end

TempDir.path_exists = path_exists

function TempDir:create()
    for attempt = 1, 100 do
        local path = self.root .. separator .. self.prefix .. "_" .. unique_token(attempt)
        if not path_exists(path) and make_directory(path) then
            self.owned[path] = true
            return path
        end
    end
    error("unable to create an owned temporary directory under " .. self.root)
end

function TempDir:cleanup(path)
    if not self.owned[path] then
        return false, "refusing to remove an unowned path"
    end
    local prefix = self.root .. separator
    if path:sub(1, #prefix) ~= prefix then
        return false, "refusing to remove a path outside the OS temporary directory"
    end
    if not remove_directory(path) then
        return false, "failed to remove owned temporary directory: " .. path
    end
    self.owned[path] = nil
    return true
end

function TempDir:cleanup_all()
    local failures = {}
    local paths = {}
    for path in pairs(self.owned) do
        paths[#paths + 1] = path
    end
    for _, path in ipairs(paths) do
        local ok, err = self:cleanup(path)
        if not ok then
            failures[#failures + 1] = err
        end
    end
    if #failures > 0 then
        return false, table.concat(failures, "\n")
    end
    return true
end

function TempDir:with_temp_dir(callback)
    local path = self:create()
    local results
    local ok, callback_error = xpcall(function()
        results = pack(callback(path))
    end, debug.traceback)
    local cleaned, cleanup_error = self:cleanup(path)
    if not ok then
        error(callback_error .. (cleaned and "" or "\n" .. cleanup_error), 0)
    end
    if not cleaned then
        error(cleanup_error, 0)
    end
    return unpack(results, 1, results.n)
end

return TempDir
