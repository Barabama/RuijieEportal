module("luci.controller.rjeportal", package.seeall)

function index()
    entry({"admin", "services", "rjeportal"},
        alias("admin", "services", "rjeportal", "status"),
        _("Ruijie ePortal"), 60).dependent = false

    entry({"admin", "services", "rjeportal", "status"},
        cbi("status"),
        _("Status and Control"), 10).leaf = true

    entry({"admin", "services", "rjeportal", "config"},
        cbi("config"),
        _("Configuration"), 20).leaf = true
end
