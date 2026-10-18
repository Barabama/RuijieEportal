#!/usr/bin/env python3
"""End-to-end rjeportal package tests against a 127.0.0.1 fake ePortal."""

from __future__ import annotations

import os
import shlex
import shutil
import stat
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

from fake_eportal import FakeEportal

PACKAGE = Path(__file__).resolve().parents[1]
FILES = PACKAGE / "files"
CLI_SOURCE = FILES / "rjeportal"
CORE_SOURCE = FILES / "rjeportal.sh"
INIT_SOURCE = FILES / "rjeportal.init"
USERNAME = "student-test"
PASSWORD = "campus-test-password"
EXPECTED_SECRET = f"{PASSWORD}>aa:bb:cc:dd:ee:ff"
CIPHERTEXT = "test-ciphertext-0123456789"


def check(condition: bool, message: str) -> None:
    if not condition:
        raise AssertionError(message)


def run_cli(action: str, env: dict[str, str], timeout: float = 10) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        ["sh", str(CLI_SOURCE), action], env=env,
        capture_output=True, text=True, timeout=timeout, check=False,
    )


def wait_until(predicate, timeout: float, message: str) -> None:
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        time.sleep(0.05)
    raise AssertionError(message)


def write_executable(path: Path, content: str) -> None:
    path.write_text(content, encoding="utf-8", newline="\n")
    path.chmod(0o755)


def make_test_files(temp: Path) -> tuple[Path, Path, Path, Path, Path]:
    core_proxy = temp / "rjeportal-core"
    cli_proxy = temp / "rjeportal-cli"
    fake_uci = temp / "uci"
    fake_encrypt = temp / "encrypt-test"
    init_dispatcher = temp / "init-dispatcher"

    write_executable(core_proxy,
        "#!/bin/sh\nexec sh " + shlex.quote(str(CORE_SOURCE)) + " \"$@\"\n")
    write_executable(cli_proxy,
        "#!/bin/sh\nexec sh " + shlex.quote(str(CLI_SOURCE)) + " \"$@\"\n")
    write_executable(fake_encrypt, """#!/bin/sh
[ "$#" -eq 3 ] || exit 2
[ "$1" = "$RJEPORTAL_TEST_EXPECTED_SECRET" ] || exit 3
[ "$2" = "10001" ] || exit 4
[ "$3" = "abcdef0123456789" ] || exit 5
printf '%s\\n' "$RJEPORTAL_TEST_CIPHERTEXT"
""")
    write_executable(fake_uci, """#!/bin/sh
[ "${1:-}" = "-q" ] && shift
[ "${1:-}" = "get" ] || exit 2
key=${2:-}
case "$key" in
    rjeportal.main.portal_ip) printf '%s\\n' '127.0.0.1' ;;
    rjeportal.main.status_url) printf '%s\\n' "$RJEPORTAL_TEST_STATUS_URL" ;;
    rjeportal.main.username) printf '%s\\n' "$RJEPORTAL_TEST_USERNAME" ;;
    rjeportal.main.password) printf '%s\\n' "$RJEPORTAL_TEST_PASSWORD" ;;
    rjeportal.main.userindex_file) printf '%s\\n' "$RJEPORTAL_TEST_USERINDEX_FILE" ;;
    rjeportal.main.enabled) printf '%s\\n' "${RJEPORTAL_TEST_ENABLED:-0}" ;;
    rjeportal.main.start_delay) printf '%s\\n' "${RJEPORTAL_TEST_START_DELAY:-0}" ;;
    rjeportal.main.retry) printf '%s\\n' "${RJEPORTAL_TEST_RETRY:-1}" ;;
    rjeportal.main.retry_delay) printf '%s\\n' "${RJEPORTAL_TEST_RETRY_DELAY:-0}" ;;
    rjeportal.main.check_interval) printf '%s\\n' "${RJEPORTAL_TEST_CHECK_INTERVAL:-1}" ;;
    rjeportal.main.failure_cooldown) printf '%s\\n' "${RJEPORTAL_TEST_FAILURE_COOLDOWN:-3}" ;;
    *) echo "unsupported fake UCI key: $key" >&2; exit 2 ;;
esac
""")
    write_executable(init_dispatcher, """#!/bin/sh
action=$1
. "$RJEPORTAL_INIT_SOURCE" || exit 1
case "$action" in
    watchdog_status) watchdog_status ;;
    watchdog_start) watchdog_start ;;
    watchdog_stop) watchdog_stop ;;
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    *) echo "unsupported init action: $action" >&2; exit 2 ;;
esac
""")
    return core_proxy, cli_proxy, fake_uci, fake_encrypt, init_dispatcher


def main() -> int:
    check(shutil.which("sh") is not None, "POSIX sh is required (run under Linux or WSL)")
    curl = shutil.which("curl")
    check(curl is not None, "curl is required")

    session_file = Path("/tmp") / f"rjeportal_{uuid.uuid4().hex}_session"
    watchdog_session = Path("/tmp") / f"rjeportal_{uuid.uuid4().hex}_watchdog"
    cooldown_session = Path("/tmp") / f"rjeportal_{uuid.uuid4().hex}_cooldown"
    unreachable_session = Path("/tmp") / f"rjeportal_{uuid.uuid4().hex}_unreachable"

    try:
        with tempfile.TemporaryDirectory(prefix="rjeportal-integration-") as temp_name:
            temp = Path(temp_name)
            core_proxy, cli_proxy, fake_uci, fake_encrypt, init_dispatcher = make_test_files(temp)

            with FakeEportal() as portal:
                env = os.environ.copy()
                env.update({
                    "RJEPORTAL_UCI": str(fake_uci),
                    "RJEPORTAL_CORE": str(core_proxy),
                    "RJEPORTAL_CLI": str(cli_proxy),
                    "RJEPORTAL_INIT": str(init_dispatcher),
                    "RJEPORTAL_INIT_SOURCE": str(INIT_SOURCE),
                    "RJEPORTAL_ENCRYPTION": str(fake_encrypt),
                    "RJEPORTAL_RUNTIME_DIR": str(temp / "runtime"),
                    "RJEPORTAL_CURL": curl,
                    "RJEPORTAL_TIMEOUT": "3",
                    "RJEPORTAL_TEST_STATUS_URL": portal.probe_url,
                    "RJEPORTAL_TEST_USERNAME": USERNAME,
                    "RJEPORTAL_TEST_PASSWORD": PASSWORD,
                    "RJEPORTAL_TEST_EXPECTED_SECRET": EXPECTED_SECRET,
                    "RJEPORTAL_TEST_CIPHERTEXT": CIPHERTEXT,
                    "RJEPORTAL_TEST_USERINDEX_FILE": str(session_file),
                    "EPORTAL_URL": portal.eportal_url,
                    "RJEPORTAL_TEST_RETRY": "1",
                    "RJEPORTAL_TEST_RETRY_DELAY": "0",
                    "RJEPORTAL_TEST_START_DELAY": "0",
                    "RJEPORTAL_TEST_CHECK_INTERVAL": "1",
                    "RJEPORTAL_TEST_FAILURE_COOLDOWN": "3",
                })

                # The real package CLI and core are exercised through UCI/curl shims.
                for mode, expected, rc in (
                    ("online", "online", 0),
                    ("captive", "captive", 1),
                    ("unknown", "unknown", 3),
                    ("unreachable", "unreachable", 2),
                ):
                    portal.state.set_mode(mode)
                    result = run_cli("status", env)
                    check(result.returncode == rc,
                          f"status {mode}: expected rc={rc}, got {result.returncode}: {result.stderr}")
                    check(result.stdout.strip() == expected,
                          f"status {mode}: expected {expected!r}, got {result.stdout.strip()!r}")
                print("PASS status: online/captive/unknown/unreachable")

                portal.state.set_mode("captive")
                portal.state.set_login_result("fail")
                result = run_cli("login", env)
                check(result.returncode != 0, "failed login unexpectedly returned success")
                check(not session_file.exists(), "failed login must not save a userIndex")
                check(PASSWORD not in result.stdout and EXPECTED_SECRET not in result.stdout,
                      "login output exposed the configured password or RSA secret")
                failed_login = portal.state.snapshot()["login_requests"][-1]
                check(failed_login.get("userId") == USERNAME,
                      "login did not submit the configured username")
                check(failed_login.get("password") == CIPHERTEXT,
                      "login did not submit the encrypted test password")
                check(failed_login.get("passwordEncrypt") == "true",
                      "login did not enable password encryption")
                check("queryString" not in result.stdout,
                      "login output exposed the portal query string")
                print("PASS login failure: no false session; request/encryption path verified")

                portal.state.set_login_result("success")
                result = run_cli("login", env)
                check(result.returncode == 0, f"successful login failed: {result.stderr}")
                check(session_file.read_text(encoding="utf-8").strip().startswith("fake-session-"),
                      "successful login did not save the returned userIndex")
                check(stat.S_IMODE(session_file.stat().st_mode) == 0o600,
                      "saved userIndex file must be mode 0600")
                print("PASS login success: userIndex saved with private permissions")

                portal.state.set_logout_result("fail")
                expected_index = session_file.read_text(encoding="utf-8").strip()
                result = run_cli("logout", env)
                check(result.returncode != 0, "failed logout unexpectedly returned success")
                check(session_file.exists() and session_file.read_text(encoding="utf-8").strip() == expected_index,
                      "failed logout discarded the saved userIndex")
                print("PASS logout failure: saved session retained for retry")

                portal.state.set_logout_result("success")
                result = run_cli("logout", env)
                check(result.returncode == 0, f"successful logout failed: {result.stderr}")
                check(not session_file.exists(), "successful logout did not remove saved userIndex")
                logout_requests = portal.state.snapshot()["logout_requests"]
                check(logout_requests[-1].get("userIndex") == expected_index,
                      "logout did not submit the saved userIndex")

                portal.state.set_last_user_index("redirect-session-fallback")
                result = run_cli("logout", env)
                check(result.returncode == 0, f"logout redirect fallback failed: {result.stderr}")
                logout_requests = portal.state.snapshot()["logout_requests"]
                check(logout_requests[-1].get("userIndex") == "redirect-session-fallback",
                      "logout did not recover userIndex from redirect")
                print("PASS logout success/fallback: saved and redirected userIndex paths")

                # Init watchdog through the real package CLI. All portal traffic
                # still goes to the loopback-only fake server.
                runtime = temp / "watchdog-runtime"
                env["RJEPORTAL_RUNTIME_DIR"] = str(runtime)
                env["RJEPORTAL_TEST_USERINDEX_FILE"] = str(watchdog_session)
                portal.state.reset_events()
                portal.state.set_mode("captive")
                portal.state.set_login_result("success")
                try:
                    result = run_cli("watchdog_start", env, timeout=5)
                    check(result.returncode == 0, f"watchdog start failed/hung: {result.stderr}")
                    pid_file = runtime / "watchdog.pid"
                    check(pid_file.exists(), "watchdog did not create its PID file")
                    first_pid = pid_file.read_text(encoding="utf-8").strip()
                    result = run_cli("watchdog_start", env, timeout=5)
                    check(result.returncode == 0, f"repeated watchdog start failed: {result.stderr}")
                    check(pid_file.read_text(encoding="utf-8").strip() == first_pid,
                          "repeated watchdog start replaced active PID")
                    result = run_cli("watchdog_status", env)
                    check(result.returncode == 0 and result.stdout.strip() == "running",
                          "watchdog status did not report running")

                    wait_until(lambda: len(portal.state.snapshot()["login_requests"]) >= 1, 8,
                               "watchdog did not log in after captive status")
                    check(portal.state.snapshot()["mode"] == "online",
                          "watchdog login did not restore online state")
                    portal.state.set_mode("captive")
                    wait_until(lambda: len(portal.state.snapshot()["login_requests"]) >= 2, 8,
                               "watchdog did not reauthenticate after session expiry")
                    check(portal.state.snapshot()["mode"] == "online",
                          "watchdog reauthentication did not restore online state")
                    print("PASS watchdog: start/status/idempotence/login/reauthentication")
                finally:
                    run_cli("watchdog_stop", env, timeout=5)

                wait_until(lambda: not (runtime / "watchdog.pid").exists(), 3,
                           "watchdog stop did not remove its PID file")
                result = run_cli("watchdog_status", env)
                check(result.returncode != 0 and result.stdout.strip() == "stopped",
                      "watchdog status did not report stopped")
                probe_count = portal.state.snapshot()["probes"]
                time.sleep(1.3)
                check(portal.state.snapshot()["probes"] == probe_count,
                      "watchdog continued probing after stop")
                print("PASS watchdog stop: loop terminated")

                # A failed login should cool down, not turn into a tight retry loop.
                runtime = temp / "cooldown-runtime"
                env["RJEPORTAL_RUNTIME_DIR"] = str(runtime)
                env["RJEPORTAL_TEST_USERINDEX_FILE"] = str(cooldown_session)
                portal.state.reset_events()
                portal.state.set_mode("captive")
                portal.state.set_login_result("fail")
                try:
                    result = run_cli("watchdog_start", env, timeout=5)
                    check(result.returncode == 0, f"cooldown watchdog start failed: {result.stderr}")
                    wait_until(lambda: len(portal.state.snapshot()["login_times"]) >= 1, 8,
                               "cooldown watchdog did not attempt first login")
                    first_time = portal.state.snapshot()["login_times"][0]
                    time.sleep(0.8)
                    check(len(portal.state.snapshot()["login_times"]) == 1,
                          "watchdog retried before configured cooldown")
                    wait_until(lambda: len(portal.state.snapshot()["login_times"]) >= 2, 7,
                               "watchdog did not retry after cooldown")
                    times = portal.state.snapshot()["login_times"]
                    check(times[1] - first_time >= 2.5,
                          f"watchdog cooldown too short: {times[1] - first_time:.2f}s")
                    print("PASS watchdog cooldown: authentication failures are rate-limited")
                finally:
                    run_cli("watchdog_stop", env, timeout=5)

                # If transport is down, watchdog must wait and skip login.
                runtime = temp / "unreachable-runtime"
                env["RJEPORTAL_RUNTIME_DIR"] = str(runtime)
                env["RJEPORTAL_TEST_USERINDEX_FILE"] = str(unreachable_session)
                portal.state.reset_events()
                portal.state.set_mode("unreachable")
                portal.state.set_login_result("success")
                try:
                    result = run_cli("watchdog_start", env, timeout=5)
                    check(result.returncode == 0, f"unreachable watchdog start failed: {result.stderr}")
                    wait_until(lambda: portal.state.snapshot()["probes"] >= 2, 6,
                               "watchdog did not recheck unreachable network")
                    check(not portal.state.snapshot()["login_requests"],
                          "watchdog attempted login while probe was unreachable")
                    print("PASS watchdog unreachable: no authentication attempt")
                finally:
                    run_cli("watchdog_stop", env, timeout=5)

        print("All rjeportal local integration tests passed (loopback only).")
        return 0
    finally:
        for path in (session_file, watchdog_session, cooldown_session, unreachable_session):
            try:
                path.unlink()
            except FileNotFoundError:
                pass


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except Exception as exc:
        print(f"FAIL: {exc}", file=os.sys.stderr)
        raise
