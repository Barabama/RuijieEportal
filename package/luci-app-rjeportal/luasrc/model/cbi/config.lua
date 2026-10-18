local sys = require "luci.sys"

local m = Map("rjeportal", translate("Ruijie ePortal"), translate(
    "Use the rjeportal core CLI for campus-network authentication. This page does not implement the ePortal protocol."))

local section = m:section(NamedSection, "main", "rjeportal", translate("Authentication settings"))
section.anonymous = true
section.addremove = false

local enabled = section:option(Flag, "enabled", translate("Enable at boot"), translate(
    "The rjeportal init script uses this option for its watchdog service."))
enabled.default = "0"
enabled.rmempty = false

local auth_user = section:option(Value, "username", translate("Username"))
auth_user.rmempty = false

local auth_password = section:option(Value, "password", translate("Password"))
auth_password.password = true
auth_password.rmempty = false
auth_password.description = translate("Stored in /etc/config/rjeportal; keep LuCI access restricted.")

local portal_ip = section:option(Value, "portal_ip", translate("Portal IP"), translate(
    "IP address of the ePortal server."))
portal_ip.default = "172.16.0.46"
portal_ip.datatype = "host"
portal_ip.rmempty = false

local status_url = section:option(Value, "status_url", translate("Connectivity test URL"), translate(
    "The core uses this URL to determine whether authentication is already active."))
status_url.default = "http://connect.rom.miui.com/generate_204"
status_url.datatype = "string"
status_url.rmempty = false

local start_delay = section:option(Value, "start_delay", translate("Startup delay (seconds)"))
start_delay.default = "30"
start_delay.datatype = "uinteger"
start_delay.rmempty = false

local retry = section:option(Value, "retry", translate("Login retries"))
retry.default = "3"
retry.datatype = "uinteger"
retry.rmempty = false

local retry_delay = section:option(Value, "retry_delay", translate("Retry delay (seconds)"))
retry_delay.default = "15"
retry_delay.datatype = "uinteger"
retry_delay.rmempty = false

local check_interval = section:option(Value, "check_interval", translate("Watchdog check interval (seconds)"))
check_interval.default = "60"
check_interval.datatype = "uinteger"
check_interval.rmempty = false

local failure_cooldown = section:option(Value, "failure_cooldown", translate("Failure cooldown (seconds)"))
failure_cooldown.default = "300"
failure_cooldown.datatype = "uinteger"
failure_cooldown.rmempty = false

local userindex_file = section:option(Value, "userindex_file", translate("Session file"), translate(
    "The core stores its returned user index here for logout."))
userindex_file.default = "/tmp/rjeportal_userindex"
userindex_file.datatype = "string"
userindex_file.rmempty = false

m.on_commit = function()
    local enabled_value = m.uci:get("rjeportal", "main", "enabled")
    if enabled_value == "1" then
        sys.call("/etc/init.d/rjeportal enable")
        sys.call("/etc/init.d/rjeportal restart")
    else
        sys.call("/etc/init.d/rjeportal stop")
        sys.call("/etc/init.d/rjeportal disable")
    end
end

return m