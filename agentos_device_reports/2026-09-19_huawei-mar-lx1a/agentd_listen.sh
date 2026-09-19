#!/system/bin/sh
# agentd_listen.sh — JSON line server on the phone (optional, for adb forward / low-latency).
# Reach from host: adb forward tcp:8798 tcp:8798  then connect to localhost:8798
# Requires toybox nc with -e (present on most Android 10+). Else use Wi-Fi ADB + exec-out.

PORT="${1:-8798}"
SCRIPT="/data/local/tmp/agentos/agentd.sh"
HANDLER="/data/local/tmp/agentos/agentd_conn.sh"
LOG="/data/local/tmp/agentos/listen.log"

mkdir -p /data/local/tmp/agentos 2>/dev/null

cat >"$HANDLER" <<'EOF'
#!/system/bin/sh
IFS= read -r line || exit 0
[ -z "$line" ] && exit 0
exec sh /data/local/tmp/agentos/agentd.sh "$line"
EOF
chmod 755 "$HANDLER"

echo "agentd_listen port=$PORT $(date)" >>"$LOG"

while true; do
  if toybox nc -l -p "$PORT" -e sh "$HANDLER" 2>>"$LOG"; then
    :
  else
    echo "nc -e failed, retry in 2s" >>"$LOG"
    sleep 2
  fi
done
