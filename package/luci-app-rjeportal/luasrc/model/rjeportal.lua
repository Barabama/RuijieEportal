local sys = require "luci.sys"

local M = {}

-- Keep this table deliberately closed. The LuCI application may only invoke
-- the public rjeportal CLI subcommands; authentication details stay in the
-- rjeportal core package.
local commands = {
    status = "/usr/bin/rjeportal status",
    login = "/usr/bin/rjeportal login",
    logout = "/usr/bin/rjeportal logout",
    watchdog_start = "/usr/bin/rjeportal watchdog_start",
    watchdog_stop = "/usr/bin/rjeportal watchdog_stop",
    watchdog_status = "/usr/bin/rjeportal watchdog_status"
}

local function trim(value)
    value = value or ""
    return (value:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function limit_output(value)
    value = trim(value)
    if #value > 4096 then
        return value:sub(1, 4096) .. "\n[output truncated]"
    end
    return value
end

local function normalize_output(value)
    value = value or ""
    value = value:gsub("\r\n", "\n")
    return value:gsub("\r", "\n")
end

local function unique_token()
    return tostring(os.time()) .. "_" .. tostring(math.random(100000, 999999))
end

function M.run(name)
    local command = commands[name]
    if not command then
        return 127, "Unknown rjeportal command"
    end

    -- Keep the command closed over the allow-list and append an unambiguous
    -- exit-code marker. No form value is interpolated into the command.
    local marker = "__RJEPORTAL_RC_" .. unique_token() .. "__"
    local shell = "(" .. command .. ") 2>&1; rc=$?; printf '\\n" ..
        marker .. "%s\\n' \"$rc\""
    local raw = normalize_output(sys.exec(shell) or "")
    local marker_start
    local search_from = 1

    while true do
        local found = raw:find("\n" .. marker, search_from, true)
        if not found then
            break
        end
        marker_start = found
        search_from = found + 1
    end

    if not marker_start then
        return 127, limit_output(raw)
    end

    local output = raw:sub(1, marker_start - 1)
    local rc_text = raw:sub(marker_start + #marker + 1):match("^(%d+)")
    return tonumber(rc_text) or 127, limit_output(output)
end

function M.trim(value)
    return trim(value)
end

function M.is_missing(rc, output)
    output = output or ""
    return rc == 127 or output:match("not found") ~= nil
end

function M.is_watchdog_supported(rc, output)
    output = output or ""
    if M.is_missing(rc, output) then
        return false
    end

    -- An older core prints usage without watchdog commands. A future core may
    -- report a non-zero runtime state while still supporting the command.
    if output:match("[Uu]sage") and not output:match("watchdog") then
        return false
    end
    return true
end

function M.status_label(rc, output)
    output = trim(output)
    if M.is_missing(rc, output) then
        return "rjeportal CLI unavailable"
    end
    if output:match("^online%s*$") then
        return "Online"
    end
    if output:match("^captive%s*$") then
        return "Captive portal / needs login"
    end
    if output:match("^unreachable%s*$") then
        return "Network unreachable"
    end
    if output:match("^unknown%s*$") then
        return "Unknown probe result"
    end
    if output == "" then
        return "No status output"
    end
    return "Probe result unavailable"
end

function M.action_result(label, rc, output)
    output = trim(output)
    local message
    if rc == 0 then
        message = label .. " command executed"
    else
        message = label .. " command unavailable or failed"
    end

    if output ~= "" then
        message = message .. ":\n" .. output
    end
    return message
end

return M