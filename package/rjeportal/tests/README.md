# rjeportal tests

Run under Linux or WSL with Python 3, POSIX `sh`, and `curl`:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 package/rjeportal/tests/test-integration.py
sh package/rjeportal/tests/test-status.sh
python3 package/rjeportal/tests/test-interface.py
```

The integration test runs a fake ePortal bound exclusively to `127.0.0.1`. It
exercises the package CLI and core for status/login/logout, and the init-script
watchdog for startup, repeated start, reauthentication, cooldown, unreachable
network handling, and stop. All HTTP endpoints stay on loopback; the test does
not contact the campus network.

The RSA executable is replaced with a deterministic test stub. The integration
test validates the encryption input/output handoff, but does not validate the
production MIPS binary, R3G-specific behavior, or compatibility with every
campus portal variant.
