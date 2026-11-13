#!/usr/bin/env python3
"""Nintendo connectivity-check spoof server for the CivSwitch Linux bridge.

The Switch probes a handful of hostnames right after joining a network.
If the responses match what Nintendo's servers return, the Switch
considers itself "online" and skips the captive-portal popup entirely.

This is the same behaviour as the ESP32 build's HTTP handler, adapted
from 90DNS (GPL-2.0-or-later) via fernando-granco/switch2-homebrew (MIT).
It listens on port 80 and answers based on the HTTP Host header, so it
doesn't matter what the Switch asks for on the wire.

Run it via systemd (see civswitch-linux-bridge.service); it needs root for
port 80.
"""

import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CONNTEST_HOST = "conntest.nintendowifi.net"
CONNTEST_BODY = (
    b"<html><head><title>HTML Page</title></head>"
    b"<body>This is test.html page</body></html>"
)

CTEST_HOSTS = {
    "ctest.cdn.nintendo.net",
    "ctest.p01.ctest.srv.nintendo.net",
    "ctest-dl-lp1.cdn.nintendo.net",
    "ctest-ul-lp1.cdn.nintendo.net",
    "api.p01.lp1.ctest.srv.nintendo.net",
    "api-ipv6.p01.lp1.ctest.srv.nintendo.net",
}

DEFAULT_HOST = "192.168.50.1"
DEFAULT_PORT = 80


class Handler(BaseHTTPRequestHandler):
    def _host(self):
        # Host header can include a port, e.g. "host:80".
        return (self.headers.get("Host") or "").split(":")[0].lower()

    def _reply(self, status, body, content_type, send_body=True):
        self.send_response(status)
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Organization", "Nintendo")
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        if send_body and body:
            self.wfile.write(body)

    def _route(self, send_body=True):
        host = self._host()

        # Legacy connectivity test.
        if host == CONNTEST_HOST:
            self._reply(200, CONNTEST_BODY, "text/html", send_body)
            return

        # Modern connectivity tests.
        if host in CTEST_HOSTS:
            self._reply(200, b"ok", "text/plain", send_body)
            return

        # Everything else — no internet forwarding.
        self._reply(404, b"", "text/plain", send_body)

    def do_GET(self):
        self._route(send_body=True)

    def do_HEAD(self):
        self._route(send_body=False)

    def log_message(self, fmt, *args):
        # Quiet by default; uncomment to debug.
        pass


def main():
    # Bind only to the wired interface's address (never the box's other
    # interfaces). Override with BRIDGE_HOST / BRIDGE_PORT, or argv[1]/argv[2].
    host = sys.argv[1] if len(sys.argv) > 1 else os.environ.get(
        "BRIDGE_HOST", DEFAULT_HOST)
    port = int(sys.argv[2]) if len(sys.argv) > 2 else int(
        os.environ.get("BRIDGE_PORT", str(DEFAULT_PORT)))
    ThreadingHTTPServer((host, port), Handler).serve_forever()


if __name__ == "__main__":
    main()
