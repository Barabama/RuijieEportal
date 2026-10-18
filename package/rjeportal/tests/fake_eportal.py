#!/usr/bin/env python3
"""Loopback-only fake ePortal used by the package integration tests."""

from __future__ import annotations

import json
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse


class _State:
    def __init__(self) -> None:
        self._lock = threading.Lock()
        self.mode = "captive"
        self.login_result = "success"
        self.logout_result = "success"
        self.probes = 0
        self.page_info_requests: list[dict[str, str]] = []
        self.login_requests: list[dict[str, str]] = []
        self.login_times: list[float] = []
        self.logout_requests: list[dict[str, str]] = []
        self.last_user_index: str | None = None

    def set_mode(self, value: str) -> None:
        with self._lock:
            self.mode = value

    def set_login_result(self, value: str) -> None:
        with self._lock:
            self.login_result = value

    def set_logout_result(self, value: str) -> None:
        with self._lock:
            self.logout_result = value

    def set_last_user_index(self, value: str | None) -> None:
        with self._lock:
            self.last_user_index = value

    def probe_mode(self) -> str:
        with self._lock:
            self.probes += 1
            return self.mode

    def record_page_info(self, form: dict[str, str]) -> None:
        with self._lock:
            self.page_info_requests.append(form)

    def record_login(self, form: dict[str, str]) -> tuple[str, str | None]:
        with self._lock:
            self.login_requests.append(form)
            self.login_times.append(time.monotonic())
            result = self.login_result
            if result == "success":
                self.last_user_index = f"fake-session-{len(self.login_requests):04d}"
                self.mode = "online"
                return result, self.last_user_index
            return result, None

    def record_logout(self, form: dict[str, str]) -> tuple[str, str | None]:
        with self._lock:
            self.logout_requests.append(form)
            result = self.logout_result
            if result == "success":
                self.mode = "captive"
                self.last_user_index = None
            return result, self.last_user_index

    def snapshot(self) -> dict[str, object]:
        with self._lock:
            return {
                "mode": self.mode,
                "probes": self.probes,
                "page_info_requests": list(self.page_info_requests),
                "login_requests": list(self.login_requests),
                "login_times": list(self.login_times),
                "logout_requests": list(self.logout_requests),
                "last_user_index": self.last_user_index,
            }

    def reset_events(self) -> None:
        with self._lock:
            self.probes = 0
            self.page_info_requests.clear()
            self.login_requests.clear()
            self.login_times.clear()
            self.logout_requests.clear()


class _Server(ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True


class _Handler(BaseHTTPRequestHandler):
    server: _Server

    def log_message(self, _format: str, *args: object) -> None:
        # Never write request bodies or account data to test logs.
        return

    def _send(self, status: int, body: bytes = b"", headers: dict[str, str] | None = None) -> None:
        self.send_response(status)
        for name, value in (headers or {}).items():
            self.send_header(name, value)
        if body:
            self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if body:
            self.wfile.write(body)

    def _json(self, value: dict[str, str]) -> None:
        body = json.dumps(value, separators=(",", ":")).encode("utf-8")
        self._send(200, body, {"Content-Type": "application/json; charset=utf-8"})

    def _form(self) -> dict[str, str]:
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", "replace")
        return {
            key: values[-1]
            for key, values in parse_qs(body, keep_blank_values=True).items()
        }

    def do_GET(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urlparse(self.path)
        origin = f"http://127.0.0.1:{self.server.server_port}"

        if parsed.path == "/probe":
            mode = self.server.state.probe_mode()
            if mode == "online":
                self._send(204)
            elif mode == "captive":
                location = (
                    f"{origin}/eportal/index.jsp?mac=aa:bb:cc:dd:ee:ff"
                    "&nasip=192.0.2.1&userip=192.0.2.10"
                )
                self._send(302, headers={"Location": location})
            elif mode == "unreachable":
                # Emulate a transport failure instead of an HTTP error response.
                self.close_connection = True
                try:
                    self.connection.shutdown(socket.SHUT_RDWR)
                except OSError:
                    pass
                self.connection.close()
            else:
                self._send(200, b"reachable but not an ePortal response",
                           {"Content-Type": "text/plain; charset=utf-8"})
            return

        if parsed.path == "/eportal/redirectortosuccess.jsp":
            state = self.server.state.snapshot()
            user_index = state["last_user_index"]
            if user_index:
                location = f"{origin}/eportal/success.jsp?userIndex={user_index}"
                self._send(302, headers={"Location": location})
            else:
                self._send(200, b"no session")
            return

        self._send(404, b"not found")

    def do_POST(self) -> None:  # noqa: N802 - BaseHTTPRequestHandler API
        parsed = urlparse(self.path)
        method = parse_qs(parsed.query).get("method", [""])[0]
        form = self._form()

        if parsed.path != "/eportal/InterFace.do":
            self._send(404, b"not found")
            return

        if method == "pageInfo":
            self.server.state.record_page_info(form)
            self._json({"publicKeyExponent": "10001", "publicKeyModulus": "abcdef0123456789"})
            return

        if method == "login":
            result, user_index = self.server.state.record_login(form)
            if result == "success":
                self._json({"result": "success", "userIndex": user_index or ""})
            else:
                # Deliberately include a bogus userIndex: failed auth must not save it.
                self._json({"result": "fail", "message": "simulated login failure",
                            "userIndex": "must-not-be-saved"})
            return

        if method == "logout":
            result, _ = self.server.state.record_logout(form)
            if result == "success":
                self._json({"result": "success"})
            else:
                self._json({"result": "fail", "message": "simulated logout failure"})
            return

        self._send(404, b"unknown ePortal method")


class FakeEportal:
    """Context manager for a local fake portal bound only to 127.0.0.1."""

    def __init__(self) -> None:
        self.state = _State()
        self._server = _Server(("127.0.0.1", 0), _Handler)
        self._server.state = self.state
        self._thread = threading.Thread(target=self._server.serve_forever, daemon=True)
        self._thread.start()
        self.origin = f"http://127.0.0.1:{self._server.server_port}"
        self.probe_url = f"{self.origin}/probe"
        self.eportal_url = f"{self.origin}/eportal"

    def __enter__(self) -> "FakeEportal":
        return self

    def __exit__(self, _exc_type: object, _exc: object, _tb: object) -> None:
        self._server.shutdown()
        self._server.server_close()
        self._thread.join(timeout=3)
