#!/usr/bin/env bash
#
# CivSwitch Pi bridge — one-shot setup for Raspberry Pi OS Bookworm.
#
# Turns the Pi into the Switch's air-gapped Wi-Fi bridge:
#   * open AP "Switch2Bridge" (via NetworkManager)
#   * DHCP + catch-all DNS via dnsmasq (every name resolves to the Pi)
#   * HTTP server that mimics Nintendo's connectivity-check endpoints
#     so the Switch joins without a captive-portal popup
#
# The Switch never gets a route to the internet (IP forwarding is left off).
#
# Usage:  sudo ./setup.sh
#
# NOTE: Untested on hardware — see README. Targets Raspberry Pi OS
# Bookworm (NetworkManager), not the older dhcpcd-based releases.

set -euo pipefail

# ── Config (edit these if you want) ────────────────────────────────
AP_SSID="Switch2Bridge"
AP_CHANNEL=6
AP_IP="192.168.4.1"
DHCP_START="192.168.4.2"
DHCP_END="192.168.4.50"
CON_NAME="Switch2Bridge"
INSTALL_DIR="/opt/civswitch-bridge"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ $EUID -ne 0 ]]; then
  echo "Run as root:  sudo ./setup.sh" >&2
  exit 1
fi

echo "== Installing packages (dnsmasq, python3) =="
apt-get update
apt-get install -y dnsmasq python3

echo "== Creating the AP in NetworkManager =="
nmcli con del "$CON_NAME" 2>/dev/null || true
nmcli con add type wifi ifname wlan0 con-name "$CON_NAME" ssid "$AP_SSID"
nmcli con modify "$CON_NAME" \
  802-11-wireless.mode ap \
  802-11-wireless.band bg \
  802-11-wireless.channel "$AP_CHANNEL" \
  ipv4.method manual \
  ipv4.addresses "$AP_IP/24" \
  connection.autoconnect yes
# (No 802-11-wireless-security settings -> open network, like the ESP32.)

echo "== Writing /etc/dnsmasq.conf (DHCP + catch-all DNS) =="
if [[ -f /etc/dnsmasq.conf && ! -f /etc/dnsmasq.conf.civswitch.bak ]]; then
  cp /etc/dnsmasq.conf /etc/dnsmasq.conf.civswitch.bak
fi
cat > /etc/dnsmasq.conf <<EOF
# CivSwitch Pi bridge — DHCP + catch-all DNS for the Switch's air-gapped AP.
interface=wlan0
bind-dynamic

# Never forward upstream; answer everything ourselves.
no-resolv
no-hosts

dhcp-range=${DHCP_START},${DHCP_END},255.255.255.0,24h

# Resolve every name to the Pi (mirrors the ESP32's catch-all DNS).
address=/#/${AP_IP}
EOF

echo "== Installing the HTTP spoof server =="
mkdir -p "$INSTALL_DIR"
install -m 0755 "$SCRIPT_DIR/bridge.py" "$INSTALL_DIR/bridge.py"
install -m 0755 "$SCRIPT_DIR/send_payload.py" "$INSTALL_DIR/send_payload.py"
install -m 0644 "$SCRIPT_DIR/civswitch-bridge.service" /etc/systemd/system/civswitch-bridge.service

echo "== Keeping the Switch air-gapped (no IP forwarding) =="
sysctl -w net.ipv4.ip_forward=0
printf 'net.ipv4.ip_forward=0\n' > /etc/sysctl.d/99-civswitch-airgap.conf

echo "== Enabling services =="
systemctl daemon-reload
systemctl enable dnsmasq
systemctl restart dnsmasq
systemctl enable civswitch-bridge
systemctl restart civswitch-bridge

echo "== Bringing up the AP =="
nmcli con up "$CON_NAME"

echo
echo "Done."
echo "  SSID:    $AP_SSID (open)"
echo "  Pi IP:   $AP_IP"
echo "  Switch:  usually $DHCP_START (check Settings > Internet)"
echo
echo "Connect the Switch to \"$AP_SSID\", then send a payload:"
echo "  python3 $INSTALL_DIR/send_payload.py payload.js"
