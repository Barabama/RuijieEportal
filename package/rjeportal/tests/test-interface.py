from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
core = (ROOT / "files" / "rjeportal.sh").read_text()
cli = (ROOT / "files" / "rjeportal").read_text()
init = (ROOT / "files" / "rjeportal.init").read_text()
makefile = (ROOT / "Makefile").read_text()

for state in ("online", "captive", "unreachable", "unknown"):
    assert f"echo {state}" in core, state
assert "echo offline" not in core
assert 'echo "queryString: $query_string"' not in core
assert "mktemp -d /tmp/rjeportal.XXXXXX" in core
assert 'mktemp "${USERINDEX_FILE}.XXXXXX"' in core
assert "save_user_index" in core
assert '> "$USERINDEX_FILE"' not in core
assert "printf '%s\\n%s\\n' \"$username\" \"$password\" | run_script login" in cli
assert 'run_script login "$username" "$password"' not in cli
for action in ("watchdog_status", "watchdog_start", "watchdog_stop"):
    assert action in cli
    assert f"{action}()" in init
# rc.common rejects custom actions that are not declared in EXTRA_COMMANDS,
# which would make the wrapper/LuCI watchdog controls unusable at runtime.
assert 'EXTRA_COMMANDS="watchdog_start watchdog_stop watchdog_status"' in init
assert "single safe file" in cli
assert "rjeportal_?*" in cli
assert "[A-Za-z0-9]*" in cli
assert "check_interval" in init
assert "failure_cooldown" in init
assert "PKGARCH:=mipsel_24kc" in makefile
print("rjeportal interface contract: ok")