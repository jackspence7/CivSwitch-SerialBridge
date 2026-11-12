#!/usr/bin/env python3
"""Send a CivSwitch JS payload from the Pi to the Switch over TCP.

Runs on the Raspberry Pi, which hosts the Switch's air-gapped Wi-Fi
network. Connects straight to the Switch's TCP loader and sends the
payload — no PC, no serial, no ESP32.

Usage:
  python3 send_payload.py payload.js
  python3 send_payload.py --ip 192.168.4.3 payload.js
  python3 send_payload.py --port 9027 payload.js
"""

import argparse
import socket
import sys
import time

DEFAULT_IP = "192.168.4.2"
DEFAULT_PORT = 9026


def send_payload(switch_ip, port, js_code):
    with socket.create_connection((switch_ip, port), timeout=10) as sock:
        sock.sendall(js_code.encode("utf-8"))

        # Half-close: tells the loader "payload complete, run it".
        sock.shutdown(socket.SHUT_WR)

        sock.settimeout(5)
        deadline = time.time() + 130
        output = []

        while time.time() < deadline:
            try:
                data = sock.recv(4096)
            except socket.timeout:
                data = b""
            if not data:
                break
            text = data.decode("utf-8", "replace")
            sys.stdout.write(text)
            sys.stdout.flush()
            output.append(text)
            deadline = time.time() + 5

        return "".join(output)


def main():
    ap = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("--ip", default=DEFAULT_IP,
                    help="Switch IP on the bridge network (default %(default)s)")
    ap.add_argument("--port", type=int, default=DEFAULT_PORT,
                    help="TCP loader port (default %(default)s)")
    ap.add_argument("payload", help="path to the payload .js file")
    args = ap.parse_args()

    with open(args.payload, encoding="utf-8") as f:
        js = f.read()

    print(f"Sending {len(js)} bytes -> {args.ip}:{args.port}")
    send_payload(args.ip, args.port, js)


if __name__ == "__main__":
    main()
