local rjeportal = require "luci.model.rjeportal"
local util = require "luci.util"

-- LuCI 24.10 moved pcdata() to luci.xml and made luci.util.pcdata() print a
-- deprecation notice to syslog on every call. Prefer the new location and
-- fall back to luci.util for older releases.
local ok, xml = pcall(require, "luci.xml")
local pcdata = (ok and xml and xml.pcdata) or util.pcdata

local m = Map("rjeportal", translate("Ruijie ePortal status and control"), translate(
    "All operations below call fixed subcommands of /usr/bin/rjeportal. Authentication protocol code is kept in the rjeportal core package."))

local status_rc, status_output = rjeportal.run("status")
local watchdog_rc, watchdog_output = rjeportal.run("watchdog_status")

local function refresh_status()
    status_rc, status_output = rjeportal.run("status")
    watchdog_rc, watchdog_output = rjeportal.run("watchdog_status")
end

local function add_action(section, command, label, description)
    local button = section:option(Button, "_" .. command, translate(label), translate(description))
    button.inputstyle = "apply"
    function button.write()
        local rc, output = rjeportal.run(command)
        m.message = rjeportal.action_result(translate(label), rc, output)
        refresh_status()
    end
    return button
end

local section = m:section(SimpleSection)
section.anonymous = true

local status = section:option(DummyValue, "_status", translate("Authentication status"))
function status.cfgvalue()
    return rjeportal.status_label(status_rc, status_output)
end

local status_detail = section:option(DummyValue, "_status_detail", translate("CLI output"), translate(
    "This is the output returned by the core status command."))
function status_detail.cfgvalue()
    local value = rjeportal.trim(status_output)
    if value == "" then
        return translate("(no output)")
    end
    return pcdata(value)
end

local watchdog = section:option(DummyValue, "_watchdog", translate("Watchdog"))
function watchdog.cfgvalue()
    if not rjeportal.is_watchdog_supported(watchdog_rc, watchdog_output) then
        return translate("Not available in the installed rjeportal core")
    end

    local value = rjeportal.trim(watchdog_output)
    if value == "" then
        return translate("Supported; no status output")
    end
    return pcdata(value)
end

local login = add_action(section, "login", "Log in", "Run /usr/bin/rjeportal login using the saved UCI credentials.")
login.inputstyle = "apply"

local logout = add_action(section, "logout", "Log out", "Run /usr/bin/rjeportal logout.")
logout.inputstyle = "apply"

if rjeportal.is_watchdog_supported(watchdog_rc, watchdog_output) then
    local watchdog_start = add_action(section, "watchdog_start", "Start watchdog",
        "Run /usr/bin/rjeportal watchdog_start.")
    watchdog_start.inputstyle = "apply"

    local watchdog_stop = add_action(section, "watchdog_stop", "Stop watchdog",
        "Run /usr/bin/rjeportal watchdog_stop.")
    watchdog_stop.inputstyle = "apply"
else
    local unsupported = section:option(DummyValue, "_watchdog_controls", translate("Watchdog controls"))
    function unsupported.cfgvalue()
        return translate("Not available: install a rjeportal core exposing watchdog_start/stop/status.")
    end
end

local refresh = section:option(Button, "_refresh", translate("Refresh status"), translate(
    "Run the core status commands again."))
refresh.inputstyle = "reload"
function refresh.write()
    refresh_status()
end

return m