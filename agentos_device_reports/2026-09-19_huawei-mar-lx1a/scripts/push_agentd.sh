#!/usr/bin/env bash
# Push agentd scripts to phone and optionally start the on-device listener.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ADB="${ADB:-$ROOT/bin/platform-tools/adb}"
SERIAL="${ADB_SERIAL:-${ADB_WIFI:-}}"
LISTEN="${START_LISTEN:-0}"
PORT="${AGENTD_LISTEN_PORT:-8798}"

adb() {
  if [[ -n "$SERIAL" ]]; then
    "$ADB" -s "$SERIAL" "$@"
  else
    "$ADB" "$@"
  fi
}

if ! adb get-state >/dev/null 2>&1; then
  echo "ERROR: no adb device." >&2
  exit 1
fi

echo "Pushing agentd to phone..."
adb shell mkdir -p /data/local/tmp/agentos
adb push "$ROOT/agentd/agentd.sh" /data/local/tmp/agentos/agentd.sh
adb push "$ROOT/agentd/agentd_listen.sh" /data/local/tmp/agentos/agentd_listen.sh
adb shell chmod 755 /data/local/tmp/agentos/agentd.sh /data/local/tmp/agentos/agentd_listen.sh

echo "Smoke test:"
adb exec-out sh /data/local/tmp/agentos/agentd.sh '{"cmd":"ping"}'

if [[ "$LISTEN" == "1" ]]; then
  echo "Starting agentd_listen on port $PORT (background)..."
  adb shell "pkill -f agentd_listen.sh 2>/dev/null; nohup sh /data/local/tmp/agentos/agentd_listen.sh $PORT >/data/local/tmp/agentos/listen.out 2>&1 &"
  sleep 1
  adb forward "tcp:$PORT" "tcp:$PORT"
  echo "Forward: localhost:$PORT -> phone:$PORT"
fi

echo "Done."
