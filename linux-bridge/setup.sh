#!/usr/bin/env bash
#
# CivSwitch Linux bridge — one-shot setup for a Linux box wired straight to
# the Switch handheld over USB-Ethernet (no dock, no Wi-Fi).
#
# Turns the box into the Switch's air-gapped wired network:
#   * static IP on the wired interface (default 192.168.50.1/24)
#   * catch-all DNS via dnsmasq (every name resolves to the box)
#   * HTTP server that mimics Nintendo's connectivity-check endpoints so the
#     Switch joins without a captive-portal popup
#
# The Switch never gets a route to the internet (IP forwarding is left off and
# asserted before anything else can run).
#
# Usage:  sudo ./setup.sh [interface] [ip]
#         e.g.  sudo ./setup.sh enx00e04c680123 192.168.50.1
#
# Both can also be set with WIRED_IF / WIRED_IP environment variables.
# Targets Debian/Ubuntu (apt + systemd + NetworkManager); see README.

set -euo pipefail

# ── Config ──────────────────────────────────────────────────────────
WIRED_IF="${1:-${WIRED_IF:-eth0}}"
WIRED_IP="${2:-${WIRED_IP:-192.168.50.1}}"
WIRED_PREFIX=24
CON_NAME="CivSwitchLinuxBridge"
INSTALL_DIR="/opt/civswitch-linux-bridge"
SERVICE_NAME="civswitch-linux-bridge.service"
SYSCTL_FILE="/etc/sysctl.d/99-civswitch-linux-airgap.conf"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root:  sudo ./setup.sh" >&2
  exit 1
fi

if ! ip link show "$WIRED_IF" >/dev/null 2>&1; then
  echo "ERROR: interface '$WIRED_IF' not found." >&2
  echo "List yours with 'ip link' (or 'nmcli device status'), then re-run:" >&2
  echo "  sudo ./setup.sh <interface>" >&2
  exit 1
fi

echo "== Installing packages (dnsmasq, python3) =="
if command -v apt-get >/dev/null 2>&1; then
  apt-get update
  apt-get install -y dnsmasq python3
else
  echo "  WARNING: apt-get not found — assuming dnsmasq and python3 are already installed." >&2
fi
if ! command -v dnsmasq >/dev/null 2>&1 || ! command -v python3 >/dev/null 2>&1; then
  echo "ERROR: 'dnsmasq' and 'python3' are both required. Install them and re-run." >&2
  exit 1
fi
PYTHON3="$(command -v python3)"

echo "== Assigning a static IP to $WIRED_IF ($WIRED_IP/$WIRED_PREFIX) =="
ip link set "$WIRED_IF" up

# Persist via NetworkManager when it manages the interface (idempotent: the
# connection profile is deleted and re-created on each run).
if command -v nmcli >/dev/null 2>&1; then
  nmcli con del "$CON_NAME" 2>/dev/null || true
  nmcli con add type ethernet ifname "$WIRED_IF" con-name "$CON_NAME" >/dev/null
  nmcli con modify "$CON_NAME" \
    ipv4.method manual \
    ipv4.addresses "$WIRED_IP/$WIRED_PREFIX" \
    ipv6.method disabled \
    connection.autoconnect yes
  nmcli con up "$CON_NAME" || true
fi

# Ensure it is set right now even without NetworkManager (idempotent).
ip addr replace "$WIRED_IP/$WIRED_PREFIX" dev "$WIRED_IF"
ip link set "$WIRED_IF" up

echo "== Enforcing the air-gap (net.ipv4.ip_forward = 0) =="
FORWARD_BEFORE="$(sysctl -n net.ipv4.ip_forward)"
if [[ "$FORWARD_BEFORE" != "0" ]]; then
  echo "  WARNING: ip_forward was $FORWARD_BEFORE — forcing it to 0 (hard requirement)." >&2
fi
sysctl -w net.ipv4.ip_forward=0 >/dev/null
printf 'net.ipv4.ip_forward=0\nnet.ipv6.conf.all.forwarding=0\n' > "$SYSCTL_FILE"
sysctl -p "$SYSCTL_FILE" >/dev/null

# Assert it stuck — the spoof must never forward to the real internet.
if [[ "$(sysctl -n net.ipv4.ip_forward)" != "0" ]]; then
  echo "ERROR: could not set net.ipv4.ip_forward=0 — aborting (air-gap not guaranteed)." >&2
  exit 1
fi

echo "== Writing /etc/dnsmasq.conf (catch-all DNS, no DHCP) =="
if [[ -f /etc/dnsmasq.conf && ! -f /etc/dnsmasq.conf.civswitch-linux.bak ]]; then
  cp /etc/dnsmasq.conf /etc/dnsmasq.conf.civswitch-linux.bak
fi
cat > /etc/dnsmasq.conf <<EOF
# CivSwitch Linux bridge — catch-all DNS only (no DHCP).
# The Switch is configured with a static IP, so dnsmasq only answers DNS.
bind-interfaces
listen-address=${WIRED_IP}

# Never forward upstream; answer everything ourselves.
no-resolv
no-hosts

# Catch-all: every name resolves to the box.
address=/#/${WIRED_IP}

port=53
EOF

# dnsmasq must wait for the (possibly USB) wired interface to appear at boot
# and retry if it isn't up yet.
mkdir -p /etc/systemd/system/dnsmasq.service.d
cat > /etc/systemd/system/dnsmasq.service.d/civswitch-linux.conf <<'EOF'
[Unit]
After=network-online.target
Wants=network-online.target

[Service]
Restart=on-failure
RestartSec=3
EOF

echo "== Installing the HTTP spoof server =="
mkdir -p "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/bridge.py" "$INSTALL_DIR/bridge.py"

cat > "/etc/systemd/system/$SERVICE_NAME" <<EOF
[Unit]
Description=CivSwitch Linux bridge HTTP spoof server
After=network-online.target dnsmasq.service
Wants=network-online.target

[Service]
Type=simple
ExecStart=$PYTHON3 $INSTALL_DIR/bridge.py $WIRED_IP
Restart=always
RestartSec=2

[Install]
WantedBy=multi-user.target
EOF

echo "== Enabling services =="
systemctl daemon-reload
systemctl enable dnsmasq
systemctl restart dnsmasq
systemctl enable "$SERVICE_NAME"
systemctl restart "$SERVICE_NAME"

echo
echo "Done."
echo "  Wired iface:  $WIRED_IF"
echo "  Box IP:       $WIRED_IP/$WIRED_PREFIX"
echo "  Switch IP:    set manually to 192.168.50.2/24 (see README)"
echo "  Air-gap:      net.ipv4.ip_forward = $(sysctl -n net.ipv4.ip_forward)"
echo
echo "On the Switch, set the wired connection to a static IP, then set"
echo "DNS (primary and secondary) to $WIRED_IP. See README for exact steps."
