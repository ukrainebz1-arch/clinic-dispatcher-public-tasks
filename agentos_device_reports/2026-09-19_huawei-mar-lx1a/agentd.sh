#!/system/bin/sh
# agentd.sh — AgentOS device-side command dispatcher for a LOCKED Huawei MAR-LX1A
# Runs under adb shell (uid 2000, context u:r:shell:s0). No root required.
# Protocol: one JSON request per invocation on argv[1] (or stdin), one JSON line reply.
# Structured commands only — NO screenshot-coordinate guessing as the control path.
#
# Design: every capability maps to a stock Android system interface reachable at
# shell privilege: screencap, input (InputManager/Binder), cmd/service/dumpsys
# (Binder), svc, settings, pm/am, getprop, /proc. Camera/mic/boot-persistence are
# intentionally delegated to the app component (agentd-app) because they require
# runtime permissions / BOOT_COMPLETED that shell uid cannot hold.
#
# This file is deliberately dependency-free (only toybox + framework binaries).

TMP=/data/local/tmp/agentos
mkdir -p "$TMP" 2>/dev/null

# --- tiny JSON helpers (string escaping) ---
esc() { # escape stdin for a JSON string value
  sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr -d '\r' | awk 'BEGIN{ORS="\\n"}{print}' | sed 's/\\n$//'
}
ok()  { printf '{"ok":true,"cmd":"%s",%s}\n' "$CMD" "$1"; }
err() { printf '{"ok":false,"cmd":"%s","error":"%s"}\n' "$CMD" "$1"; }

# --- read request ---
REQ="$1"
[ -z "$REQ" ] && REQ="$(cat)"
# Extract a top-level key value with a naive but robust matcher.
jget() { echo "$REQ" | tr ',{}' '\n\n\n' | grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed -e "s/.*:[[:space:]]*\"//" -e 's/"$//'; }
jgetn(){ echo "$REQ" | tr ',{}' '\n\n\n' | grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9-]*" | head -1 | sed -e 's/.*:[[:space:]]*//'; }

CMD="$(jget cmd)"
[ -z "$CMD" ] && { err "missing cmd"; exit 0; }

case "$CMD" in
  ping)
    ok "\"uid\":$(id -u),\"ctx\":\"$(cat /proc/self/attr/current 2>/dev/null | tr -d '\0')\",\"ts\":$(date +%s)"
    ;;

  info)
    M=$(getprop ro.product.model); D=$(getprop ro.product.device); R=$(getprop ro.build.version.release)
    F=$(getprop ro.build.fingerprint); BL=$(getprop ro.boot.verifiedbootstate)
    ok "\"model\":\"$M\",\"device\":\"$D\",\"android\":\"$R\",\"verifiedboot\":\"$BL\",\"fingerprint\":\"$F\""
    ;;

  # ---------- SCREEN ----------
  screencap)     # returns base64 PNG (structured, not for coordinate control)
    OUT="$TMP/cap.png"
    screencap -p "$OUT" 2>/dev/null || { err "screencap failed"; exit 0; }
    B64=$(toybox base64 "$OUT" 2>/dev/null | tr -d '\n')
    ok "\"format\":\"png\",\"bytes\":$(toybox wc -c < "$OUT"),\"b64\":\"$B64\""
    ;;
  uidump)        # structured UI tree (accessibility-free, via uiautomator dump)
    uiautomator dump "$TMP/ui.xml" >/dev/null 2>&1
    if [ -f "$TMP/ui.xml" ]; then
      B64=$(toybox base64 "$TMP/ui.xml" | tr -d '\n'); ok "\"format\":\"xml\",\"b64\":\"$B64\""
    else err "uidump failed"; fi
    ;;

  # ---------- INPUT (structured via InputManager/Binder) ----------
  tap)     X=$(jgetn x); Y=$(jgetn y); input tap "$X" "$Y" && ok "\"x\":$X,\"y\":$Y" || err "tap failed" ;;
  swipe)   X=$(jgetn x); Y=$(jgetn y); X2=$(jgetn x2); Y2=$(jgetn y2); MS=$(jgetn ms); [ -z "$MS" ] && MS=300
           input swipe "$X" "$Y" "$X2" "$Y2" "$MS" && ok "\"swipe\":true" || err "swipe failed" ;;
  text)    T=$(jget text); input text "$T" && ok "\"typed\":true" || err "text failed" ;;
  key)     K=$(jget keycode); input keyevent "$K" && ok "\"key\":\"$K\"" || err "key failed" ;;

  # ---------- APP / BINDER (structured) ----------
  launch)  P=$(jget package); monkey -p "$P" -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1 && ok "\"launched\":\"$P\"" || err "launch failed" ;;
  stop)    P=$(jget package); am force-stop "$P" && ok "\"stopped\":\"$P\"" || err "stop failed" ;;
  start)   A=$(jget action); U=$(jget uri); am start -a "$A" ${U:+-d "$U"} >/dev/null 2>&1 && ok "\"started\":true" || err "start failed" ;;
  fg)      ok "\"foreground\":\"$(dumpsys activity activities 2>/dev/null | grep -m1 -oE 'ResumedActivity.*' | grep -oE '[a-zA-Z0-9_.]+/[a-zA-Z0-9_.]+' | head -1)\"" ;;
  svccall) S=$(jget service); C=$(jgetn code); ok "\"raw\":\"$(service call "$S" "$C" 2>&1 | tr '\n' ' ' | esc)\"" ;;

  # ---------- NETWORK ----------
  net)     WIFI=$(dumpsys wifi 2>/dev/null | grep -m1 'Wi-Fi is'); IP=$(ip -o -4 addr show wlan0 2>/dev/null | awk '{print $4}')
           ok "\"wifi\":\"$(echo $WIFI|esc)\",\"ip\":\"$IP\"" ;;
  wifi)    V=$(jget on); svc wifi "$V" && ok "\"wifi\":\"$V\"" || err "wifi failed" ;;
  data)    V=$(jget on); svc data "$V" && ok "\"data\":\"$V\"" || err "data failed" ;;

  # ---------- SENSORS / RADIO snapshot ----------
  sensors) ok "\"list\":\"$(dumpsys sensorservice 2>/dev/null | sed -n '/Sensor List/,/^$/p' | grep -oE 'android.sensor.[a-z_]+' | sort -u | tr '\n' ',' | esc)\"" ;;
  battery) L=$(dumpsys battery 2>/dev/null | grep -m1 ' level:' | grep -oE '[0-9]+'); T=$(dumpsys battery 2>/dev/null | grep -m1 ' temperature:' | grep -oE '[0-9]+')
           ok "\"level\":${L:-null},\"temp_dC\":${T:-null}" ;;
  gps)     ok "\"providers\":\"$(dumpsys location 2>/dev/null | grep -oE '(gps|network|fused|passive) provider' | tr '\n' ',' | esc)\"" ;;

  # ---------- FILES / PROCESS / POWER ----------
  getprop) P=$(jget name); ok "\"value\":\"$(getprop "$P" | esc)\"" ;;
  ps)      ok "\"count\":$(ps -A 2>/dev/null | wc -l)" ;;
  read)    F=$(jget path); [ -r "$F" ] && ok "\"b64\":\"$(toybox base64 "$F" | tr -d '\n')\"" || err "unreadable" ;;
  write)   F=$(jget path); B=$(jget b64); echo "$B" | toybox base64 -d > "$F" 2>/dev/null && ok "\"wrote\":\"$F\"" || err "write failed" ;;
  power)   K=$(jget which); case "$K" in wake) input keyevent KEYCODE_WAKEUP;; sleep) input keyevent KEYCODE_SLEEP;; esac; ok "\"power\":\"$K\"" ;;

  *) err "unknown cmd: $CMD" ;;
esac
