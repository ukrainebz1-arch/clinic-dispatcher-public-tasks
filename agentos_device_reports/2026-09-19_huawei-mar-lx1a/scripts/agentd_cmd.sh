#!/usr/bin/env bash
# Quick CLI to send one agentd JSON command to the phone.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE="$ROOT/agentd/agentd_bridge.py"
SERIAL="${ADB_SERIAL:-${ADB_WIFI:-}}"

CMD="${1:-ping}"
shift || true

# Build JSON from first arg or remaining key=value pairs
if [[ "$CMD" == "{"* ]]; then
  JSON="$CMD"
else
  JSON="{\"cmd\":\"$CMD\""
  for kv in "$@"; do
    key="${kv%%=*}"
    val="${kv#*=}"
    if [[ "$val" =~ ^[0-9-]+$ ]]; then
      JSON+=",\"$key\":$val"
    else
      JSON+=",\"$key\":\"$val\""
    fi
  done
  JSON+="}"
fi

ARGS=()
[[ -n "$SERIAL" ]] && ARGS+=(--serial "$SERIAL")
python3 "$BRIDGE" "${ARGS[@]}" "$JSON"
