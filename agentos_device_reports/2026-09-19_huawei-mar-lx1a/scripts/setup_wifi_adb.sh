#!/usr/bin/env bash
# One-time (per reboot) Wi-Fi ADB setup for AgentOS bench phone.
# Requires USB connected once to run `adb tcpip 5555`, then cable can be unplugged.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-$ROOT/bin/platform-tools/adb}"
PORT="${ADB_WIFI_PORT:-5555}"
SERIAL="${ADB_SERIAL:-}"

adb() {
  if [[ -n "$SERIAL" ]]; then
    "$ADB" -s "$SERIAL" "$@"
  else
    "$ADB" "$@"
  fi
}

echo "== AgentOS Wi-Fi ADB setup =="
echo "ADB: $ADB"

if ! adb get-state >/dev/null 2>&1; then
  echo "ERROR: no adb device. Plug in USB and authorize debugging first." >&2
  exit 1
fi

MODEL="$(adb shell getprop ro.product.model | tr -d '\r')"
echo "Device: $MODEL"

IP="$(adb shell ip -o -4 addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | tr -d '\r' | head -1)"
if [[ -z "$IP" ]]; then
  echo "ERROR: phone has no wlan0 IPv4. Connect phone to Wi-Fi first." >&2
  exit 1
fi
echo "Phone Wi-Fi IP: $IP"

echo "Enabling ADB over TCP/IP on port $PORT (needs USB once per reboot)..."
adb tcpip "$PORT"
sleep 2

TARGET="${IP}:${PORT}"
echo "Connecting host to $TARGET ..."
adb connect "$TARGET"

sleep 1
echo
echo "Connected devices:"
"$ADB" devices -l

STATE="$(adb -s "$TARGET" get-state 2>/dev/null || true)"
if [[ "$STATE" != "device" ]]; then
  echo "WARN: Wi-Fi adb state is '$STATE', not 'device'. Check same LAN / firewall." >&2
  exit 1
fi

echo
echo "OK — you can unplug USB. Use:"
echo "  export ADB_WIFI=$TARGET"
echo "  $ROOT/scripts/agentd_cmd.sh ping"
echo "  python3 $ROOT/agentd/agentd_bridge.py --serial $TARGET --serve 0.0.0.0:8799"
