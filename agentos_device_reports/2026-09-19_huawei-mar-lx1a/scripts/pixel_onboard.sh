#!/usr/bin/env bash
# First-boot checklist when a carrier-unlocked Google Pixel arrives.
# Run from Mac mini with USB connected. Destructive steps require explicit --go.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-$ROOT/bin/platform-tools/adb}"
FASTBOOT="${FASTBOOT:-$ROOT/bin/platform-tools/fastboot}"
GO="${GO:-0}"

red() { echo -e "\033[31m$*\033[0m"; }
grn() { echo -e "\033[32m$*\033[0m"; }
ylw() { echo -e "\033[33m$*\033[0m"; }

section() { echo; echo "=== $* ==="; }

section "1. ADB visibility"
"$ADB" devices -l || true
SERIAL="$("$ADB" devices | awk 'NR>1 && $2=="device" {print $1; exit}')"
if [[ -z "$SERIAL" ]]; then
  red "No device in 'device' state. Enable USB debugging + authorize RSA."
  exit 1
fi
grn "Serial: $SERIAL"

section "2. Identity"
"$ADB" -s "$SERIAL" shell getprop ro.product.manufacturer
"$ADB" -s "$SERIAL" shell getprop ro.product.model
"$ADB" -s "$SERIAL" shell getprop ro.product.device
"$ADB" -s "$SERIAL" shell getprop ro.build.version.release
FP="$("$ADB" -s "$SERIAL" shell getprop ro.build.fingerprint | tr -d '\r')"
echo "fingerprint: $FP"

section "3. Bootloader / unlock readiness (CRITICAL)"
OEM="$("$ADB" -s "$SERIAL" shell getprop sys.oem_unlock_allowed | tr -d '\r')"
FLASH="$("$ADB" -s "$SERIAL" shell getprop ro.boot.flash.locked 2>/dev/null | tr -d '\r' || true)"
VBS="$("$ADB" -s "$SERIAL" shell getprop ro.boot.verifiedbootstate | tr -d '\r' || true)"
echo "sys.oem_unlock_allowed = $OEM"
echo "ro.boot.flash.locked     = $FLASH"
echo "verifiedbootstate        = $VBS"

if [[ "$OEM" != "1" ]]; then
  red "OEM unlocking NOT allowed — do not buy / return device if greyed out in Developer options."
else
  grn "OEM unlock allowed in software — confirm toggle visible in Developer options on screen."
fi

section "4. Developer options checklist (manual on phone)"
ylw "  [ ] Settings → Developer options → OEM unlocking ON"
ylw "  [ ] USB debugging ON"
ylw "  [ ] (optional) Wireless debugging ON for Wi-Fi ADB without cable"

section "5. Fastboot probe (non-destructive reboot)"
if [[ "$GO" != "1" ]]; then
  ylw "Skip fastboot (dry run). To reboot to bootloader: GO=1 $0"
else
  echo "Rebooting to bootloader..."
  "$ADB" -s "$SERIAL" reboot bootloader
  sleep 8
  "$FASTBOOT" devices
  "$FASTBOOT" oem device-info 2>/dev/null || "$FASTBOOT" flashing get_unlock_ability 2>/dev/null || true
  ylw "To unlock (WIPES DEVICE): fastboot flashing unlock"
  ylw "Then: flash LineageOS or AOSP userdebug — see agentos-device-report.md §10"
fi

section "6. Next steps after unlock"
echo "  1. fastboot flashing unlock"
echo "  2. Flash boot + system (LineageOS or AOSP userdebug + vendor blobs)"
echo "  3. Install agentd as system service (init.rc, root)"
echo "  4. Enable Wi-Fi TLS listener on device (no Mac-mini relay required)"
grn "Report: $ROOT/work/clinic-dispatcher-public-tasks/agentos_device_reports/"
