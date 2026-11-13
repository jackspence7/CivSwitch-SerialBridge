# CivSwitch Linux Bridge (wired Ethernet)

Run the CivSwitch bridge on any Linux box wired straight to the Switch handheld over USB-Ethernet — no dock, no Wi-Fi, no ESP32, no Raspberry Pi. The box spoofs Nintendo's connectivity check so the Switch treats the wired link as online and skips the captive-portal popup.

```
Switch handheld ── USB-A→USB-C OTG ──> ASIX/Realtek USB-A NIC ── Ethernet ──> Linux box
  (top USB-C port)                                                          (any NIC)
```

This is the third variant, alongside the [ESP32](../esp32-bridge) and [Raspberry Pi](../pi-bridge) builds. It reuses the Pi build's spoof server, but binds it to a wired interface with a static IP instead of a Wi-Fi AP.

## ⚠️ Read these two before wiring anything

These two cost real debugging time — check both.

### 1. Adapter chipset (the `2110-1100` "LAN cable attached" trap)

The Switch handheld's USB-C port hosts Ethernet **only with a supported chipset — ASIX or Realtek**. "Driver-free" USB-C dongles (CDC-NCM / RNDIS) are **not** supported by the console, so the Switch shows error `2110-1100` / "LAN cable attached" **even though the Linux box sees a clean 1000M/full link**.

The working order is:

1. **ASIX / Realtek USB-A Ethernet adapter** → into the **Switch's top USB-C** port via a **USB-A→USB-C OTG adapter**.
2. The **"driver-free" USB-C dongle goes on the Linux box** (Linux has drivers for CDC-NCM/RNDIS, so it's fine there).

> Rule of thumb: the adapter on the **Switch** end must be ASIX/Realtek. The adapter on the **Linux** end can be anything.

### 2. Captive portal (the `python3 -m http.server` trap)

A plain `python3 -m http.server` on port 80 makes the Switch pop a captive portal. The response **must mimic Nintendo's** — right status code, `X-Organization: Nintendo` header, and the exact body — or the console flaps between "registered" and "offline".

`bridge.py` does this. After it's running, point the console's **wired DNS at the box** (manual, **primary + secondary = the wired IP**) and the connection test passes / stops flapping.

## Static IPs

| Host | Interface | IP |
|---|---|---|
| Linux box | wired NIC (e.g. `eth0`, `enx…`) | `192.168.50.1/24` |
| Switch | wired connection (manual) | `192.168.50.2/24` |

On the Switch, set the wired connection to a **static IP** and:

- IP address: `192.168.50.2`
- Subnet mask: `255.255.255.0`
- Gateway: `192.168.50.1`
- DNS (primary and secondary): `192.168.50.1`

The Switch is configured manually here — there is **no DHCP** (dnsmasq is DNS-only, because the console needs its static address pinned).

## How it works

- `setup.sh` gives the wired interface a static IP (`192.168.50.1/24`).
- dnsmasq runs a **catch-all DNS**: every name resolves to the box, with `--no-resolv` / `--no-hosts`, so nothing ever goes upstream.
- `bridge.py` answers port 80 on the wired IP and mimics Nintendo's connectivity-check endpoints.
- IP forwarding is forced to `0` and asserted — the Switch is genuinely air-gapped even if the box has internet on another interface.

## Requirements

- A Linux box (Debian/Ubuntu-oriented: `apt`, `systemd`, NetworkManager) with root access.
- `dnsmasq` and `python3` (installed by `setup.sh` on apt systems).
- An ASIX/Realtek USB-A Ethernet adapter + USB-A→USB-C OTG adapter for the Switch end.
- CivSwitch already set up with the TCP loader running on the Switch (`:9026`).

## Install

```sh
git clone https://github.com/jackspence7/CivSwitch-SerialBridge.git
cd CivSwitch-SerialBridge/linux-bridge
sudo ./setup.sh
```

`setup.sh` is idempotent — safe to re-run. Find your wired interface first if it isn't `eth0` (USB dongles are usually `enx…`):

```sh
ip link          # or: nmcli device status
sudo ./setup.sh enx00e04c680123
```

You can also pass the IP, or set env vars:

```sh
sudo ./setup.sh enx00e04c680123 192.168.50.1
WIRED_IF=enx00e04c680123 WIRED_IP=192.168.50.1 sudo -E ./setup.sh
```

## Send payloads

The box is already on the Switch's wired network, so send payloads straight at the console:

```sh
# With CivSwitch's TCP loader running on the Switch (:9026):
python3 ../pi-bridge/send_payload.py --ip 192.168.50.2 payload.js
```

(or use whatever CivSwitch sender you already use — just point it at `192.168.50.2:9026`.)

## Config

| Setting | Default | Override |
|---|---|---|
| `WIRED_IF` | `eth0` | positional arg 1 / `WIRED_IF` env |
| `WIRED_IP` | `192.168.50.1` | positional arg 2 / `WIRED_IP` env |
| prefix | `/24` | edit `WIRED_PREFIX` in `setup.sh` |

## Undo / revert

```sh
sudo systemctl disable --now civswitch-linux-bridge dnsmasq
sudo rm -f /etc/systemd/system/civswitch-linux-bridge.service
sudo rm -rf /etc/systemd/system/dnsmasq.service.d/civswitch-linux.conf
sudo rm -f /etc/dnsmasq.conf /etc/sysctl.d/99-civswitch-linux-airgap.conf
sudo mv /etc/dnsmasq.conf.civswitch-linux.bak /etc/dnsmasq.conf   # if a backup was made
sudo nmcli con del CivSwitchLinuxBridge
sudo rm -rf /opt/civswitch-linux-bridge
sudo systemctl daemon-reload
```

## License

MIT. The Nintendo connectivity-check responses are adapted from [90DNS](https://github.com/Thesola10/90dns) (GPL-2.0-or-later) via [fernando-granco/switch2-homebrew](https://github.com/fernando-granco/switch2-homebrew) (MIT), same as the ESP32 and Pi builds.
