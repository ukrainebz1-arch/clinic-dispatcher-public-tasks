#!/usr/bin/env python3
"""AgentOS host bridge (Mac mini side).

Control plane: cloud/model  <->  this bridge  <->  adb (USB)  <->  agentd.sh on phone.

Exposes a structured JSON command API two ways:
  1. CLI:   agentd_bridge.py '{"cmd":"info"}'
  2. Server: agentd_bridge.py --serve 127.0.0.1:8799   (line-delimited JSON over TCP)

Each request is dispatched to the phone by piping the JSON to agentd.sh through
`adb exec-out sh /data/local/tmp/agentos/agentd.sh`. This works on a LOCKED device
with only shell (uid 2000) privileges — no root, no bootloader unlock.

Why host-side dispatch instead of a phone-resident TCP daemon: shell uid cannot
survive reboot or bind a privileged listener reliably without a pushed static nc.
A pushed busybox listener + `adb forward` is supported too (see --forward), but the
exec-out path is the robust default and keeps the phone stateless between commands.
"""
from __future__ import annotations
import json, subprocess, sys, socket, threading, shlex, time

ADB = "/home/cursorworker1/agentos-phone/bin/platform-tools/adb"
DEVICE_SCRIPT = "/data/local/tmp/agentos/agentd.sh"


def dispatch(req: dict, serial: str | None = None) -> dict:
    payload = json.dumps(req)
    cmd = [ADB]
    if serial:
        cmd += ["-s", serial]
    cmd += ["exec-out", "sh", DEVICE_SCRIPT, payload]
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "adb timeout", "cmd": req.get("cmd")}
    raw = out.stdout.decode("utf-8", "replace").strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        return json.loads(line)
    except Exception:
        return {"ok": False, "error": "bad reply", "raw": raw[:400],
                "stderr": out.stderr.decode("utf-8", "replace")[:400], "cmd": req.get("cmd")}


def serve(host: str, port: int, serial: str | None):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(8)
    print(f"agentd bridge listening on {host}:{port} -> phone {serial or '(default)'}", flush=True)

    def handle(conn):
        with conn:
            buf = b""
            while True:
                chunk = conn.recv(4096)
                if not chunk:
                    break
                buf += chunk
                while b"\n" in buf:
                    line, buf = buf.split(b"\n", 1)
                    line = line.strip()
                    if not line:
                        continue
                    try:
                        req = json.loads(line)
                    except Exception as e:
                        conn.sendall((json.dumps({"ok": False, "error": f"bad json: {e}"}) + "\n").encode())
                        continue
                    resp = dispatch(req, serial)
                    conn.sendall((json.dumps(resp) + "\n").encode())

    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


def main():
    args = sys.argv[1:]
    serial = None
    if "--serial" in args:
        i = args.index("--serial"); serial = args[i + 1]; del args[i:i + 2]
    if args and args[0] == "--serve":
        host, port = args[1].split(":")
        serve(host, int(port), serial)
        return
    req = json.loads(args[0]) if args else {"cmd": "ping"}
    print(json.dumps(dispatch(req, serial), ensure_ascii=False))


if __name__ == "__main__":
    main()
