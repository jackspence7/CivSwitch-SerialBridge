# CivSwitch Pi Bridge (Raspberry Pi)

Run the CivSwitch serial-bridge job entirely on a Raspberry Pi. No ESP32, no USB serial, no PC — the Pi is the Switch's air-gapped Wi-Fi network and sends payloads to the Switch directly.

```
Switch (TCP :9026) ---Wi-Fi AP---> Raspberry Pi (AP + DNS + HTTP spoof + sender)
```

## ⚠️ Untested

This port was written quickly for someone who asked for it on Reddit, and **has not been tested on a real Raspberry Pi yet**. It targets Raspberry Pi OS **Bookworm** (which uses NetworkManager). If you try it and something breaks, open an issue — happy to fix it.

## Why a Pi version?

The [ESP32 version](../esp32-bridge) exists because an ESP32 is a tiny USB dongle that can't run Python. A Raspberry Pi is a full Linux computer, so it can do the whole job itself: host the Switch's network, spoof Nintendo's connectivity check, and send payloads. Nothing in the middle, no PC required.

## How it works

- NetworkManager puts `wlan0` into AP mode (`Switch2Bridge`, open).
- dnsmasq hands out IPs and resolves **every** DNS name to the Pi, so the Switch never reaches the real internet.
- `bridge.py` (a small HTTP server on port 80) mimics Nintendo's connectivity-check endpoints, so the Switch thinks it's online and skips the captive-portal popup.
- `send_payload.py` connects to the Switch's TCP loader (`:9026`) and sends the payload.
- IP forwarding stays off, so the Switch is genuinely air-gapped even if the Pi has an uplink.

## Requirements

- Raspberry Pi 3 / 4 / Zero 2 W (anything with onboard Wi-Fi) running Raspberry Pi OS **Bookworm**.
- CivSwitch already set up, with the TCP loader running on the Switch (`:9026`).
- A way to control the Pi: Ethernet, or a keyboard + monitor. Once the Pi is the AP, its Wi-Fi belongs to the Switch, not your LAN.

## Install

```sh
git clone https://github.com/jackspence7/CivSwitch-SerialBridge.git
cd CivSwitch-SerialBridge/pi-bridge
sudo ./setup.sh
```

`setup.sh` installs `dnsmasq` + `python3`, creates the AP, writes the DNS config, installs the HTTP spoof server as a systemd service, and brings the AP up. It's safe to re-run.

> If your Wi-Fi country isn't set, set it first: `sudo raspi-config nonint do_wlan_country US` (or your country). Channel 6 is the default.

## Send payloads

On the Pi, with CivSwitch's TCP loader running on the Switch:

```sh
python3 /opt/civswitch-bridge/send_payload.py payload.js
```

The Switch is usually `192.168.4.2`. Override if it isn't:

```sh
python3 /opt/civswitch-bridge/send_payload.py --ip 192.168.4.3 payload.js
python3 /opt/civswitch-bridge/send_payload.py --port 9027 payload.js
```

## Config

Edit the block at the top of `setup.sh` and re-run it to change network settings:

| Setting | Default |
|---|---|
| `AP_SSID` | `Switch2Bridge` |
| `AP_CHANNEL` | `6` |
| `AP_IP` | `192.168.4.1` |
| `DHCP_START` / `DHCP_END` | `192.168.4.2` – `192.168.4.50` |

The AP is open (no password) by default, matching the ESP32 build.

## Undo / revert

```sh
sudo systemctl disable --now civswitch-bridge dnsmasq
sudo nmcli con del Switch2Bridge
sudo rm -f /etc/dnsmasq.conf /etc/sysctl.d/99-civswitch-airgap.conf
sudo mv /etc/dnsmasq.conf.civswitch.bak /etc/dnsmasq.conf   # if a backup was made
sudo rm -rf /opt/civswitch-bridge
```

## License

MIT. The Nintendo connectivity-check responses are adapted from [90DNS](https://github.com/Thesola10/90dns) (GPL-2.0-or-later) via [fernando-granco/switch2-homebrew](https://github.com/fernando-granco/switch2-homebrew) (MIT), same as the ESP32 build.
