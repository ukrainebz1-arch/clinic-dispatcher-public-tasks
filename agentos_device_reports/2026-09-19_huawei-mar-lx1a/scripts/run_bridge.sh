#!/usr/bin/env bash
# Run the AgentOS JSON bridge server (default 0.0.0.0:8799 on Mac mini).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
HOST="${BRIDGE_HOST:-0.0.0.0}"
PORT="${BRIDGE_PORT:-8799}"
SERIAL="${ADB_SERIAL:-${ADB_WIFI:-}}"
TRANSPORT="${AGENTD_TRANSPORT:-exec-out}"

ARGS=(--transport "$TRANSPORT" --serve "${HOST}:${PORT}")
[[ -n "$SERIAL" ]] && ARGS+=(--serial "$SERIAL")

echo "Starting agentd bridge transport=$TRANSPORT serial=${SERIAL:-default} on ${HOST}:${PORT}"
exec python3 "$ROOT/agentd/agentd_bridge.py" "${ARGS[@]}"
