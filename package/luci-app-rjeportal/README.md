# luci-app-rjeportal

LuCI 24.10-compatible CBI frontend for the `rjeportal` OpenWrt package.

## Scope

This package only edits `/etc/config/rjeportal` and invokes the fixed public
commands exposed by `/usr/bin/rjeportal`:

- `status`
- `login`
- `logout`
- `watchdog_start`
- `watchdog_stop`
- `watchdog_status`

It does not contain ePortal request handling, `curl`, RSA encryption, or
`queryString` logic. Credentials are read by the core CLI from UCI, so they are
not placed in the LuCI command line.

## Layout

The package follows the PR #7 LuCI layout:

- `luasrc/controller/` — legacy-compatible LuCI controller
- `luasrc/model/cbi/` — CBI configuration and status pages
- `root/usr/share/rpcd/acl.d/` — UCI read/write ACL

The app depends on `rjeportal` and `luci-compat`. It intentionally does not
add `luci-lib-fs`; the app does not use that compatibility filesystem API.

## Pages

LuCI → Services → Ruijie ePortal

- **Status and Control**: status, login/logout, and watchdog controls
- **Configuration**: account, portal, probe, retry, startup, and watchdog timing settings

If the installed core does not implement the watchdog subcommands, the UI
shows an unavailable message and omits watchdog action buttons.
