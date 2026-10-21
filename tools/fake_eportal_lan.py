#!/usr/bin/env python3
"""Serve the repository's fake ePortal on a LAN address for on-device tests.

The tracked `package/rjeportal/tests/fake_eportal.py` intentionally binds only
to 127.0.0.1 so the package integration test never leaves the loopback
interface. This untracked harness reuses the same state and handler classes but
listens on 0.0.0.0 (or an explicit address) so a router can reach it.

Usage:
    python tools/fake_eportal_lan.py --host 0.0.0.0 --port 18080

Then, on the router:

    export PORTAL_IP=<pc-lan-ip>:18080
    export STATUS_URL=http://<pc-lan-ip>:18080/probe
    sh rjeportal.sh status|login|logout

The probe response's Location header contains 127.0.0.1, but the core only
extracts the index.jsp query string from it and then uses EPORTAL_URL for
pageInfo/login/logout, so the router never follows that host.

On Windows the default Python inbound firewall rules block this port; add an
inbound allow rule for the test port and remove it afterwards.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "package" / "rjeportal" / "tests"))

from fake_eportal import _Handler, _Server, _State  # noqa: E402


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18080)
    args = parser.parse_args()

    state = _State()
    server = _Server((args.host, args.port), _Handler)
    server.state = state
    print(f"fake ePortal listening on http://{args.host}:{args.port}", flush=True)
    print(f"probe:  http://{args.host}:{args.port}/probe", flush=True)
    print(f"portal: http://{args.host}:{args.port}/eportal", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())