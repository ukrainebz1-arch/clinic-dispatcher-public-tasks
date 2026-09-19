#!/usr/bin/env python3
"""AgentOS host bridge (Mac mini side).

Control plane: cloud/model  <->  this bridge  <->  phone agentd

Transports (pick one):
  exec-out (default) — `adb exec-out sh agentd.sh` over USB or Wi-Fi ADB
  forward            — TCP to localhost:8798 via `adb forward` -> agentd_listen.sh
  direct             — TCP to phone IP:8798 (same LAN, listener on phone)

Exposes JSON API:
  CLI:    agentd_bridge.py '{"cmd":"info"}'
  Server: agentd_bridge.py --serve 127.0.0.1:8799
"""
from __future__ import annotations

import argparse
import json
import socket
import subprocess
import sys
import threading

ADB = "/home/cursorworker1/agentos-phone/bin/platform-tools/adb"
DEVICE_SCRIPT = "/data/local/tmp/agentos/agentd.sh"
DEFAULT_FORWARD_PORT = 8798


def _adb_base(serial: str | None) -> list[str]:
    cmd = [ADB]
    if serial:
        cmd += ["-s", serial]
    return cmd


def dispatch_exec_out(req: dict, serial: str | None) -> dict:
    payload = json.dumps(req)
    cmd = _adb_base(serial) + ["exec-out", "sh", DEVICE_SCRIPT, payload]
    try:
        out = subprocess.run(cmd, capture_output=True, timeout=60)
    except subprocess.TimeoutExpired:
        return {"ok": False, "error": "adb timeout", "cmd": req.get("cmd")}
    raw = out.stdout.decode("utf-8", "replace").strip()
    line = raw.splitlines()[-1] if raw else ""
    try:
        return json.loads(line)
    except Exception:
        return {
            "ok": False,
            "error": "bad reply",
            "raw": raw[:400],
            "stderr": out.stderr.decode("utf-8", "replace")[:400],
            "cmd": req.get("cmd"),
        }


def dispatch_tcp(req: dict, host: str, port: int, timeout: float = 30.0) -> dict:
    payload = (json.dumps(req) + "\n").encode()
    try:
        with socket.create_connection((host, port), timeout=timeout) as sock:
            sock.sendall(payload)
            sock.shutdown(socket.SHUT_WR)
            buf = b""
            while True:
                chunk = sock.recv(4096)
                if not chunk:
                    break
                buf += chunk
            line = buf.decode("utf-8", "replace").strip().splitlines()
            line = line[-1] if line else ""
            return json.loads(line) if line else {"ok": False, "error": "empty tcp reply"}
    except json.JSONDecodeError:
        return {"ok": False, "error": "bad tcp json", "raw": buf.decode("utf-8", "replace")[:400]}
    except OSError as e:
        return {"ok": False, "error": f"tcp: {e}", "cmd": req.get("cmd")}


def make_dispatcher(mode: str, serial: str | None, tcp_host: str, tcp_port: int):
    def dispatch(req: dict) -> dict:
        if mode == "exec-out":
            return dispatch_exec_out(req, serial)
        return dispatch_tcp(req, tcp_host, tcp_port)

    return dispatch


def serve(host: str, port: int, dispatch):
    srv = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    srv.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    srv.bind((host, port))
    srv.listen(8)
    print(f"agentd bridge listening on {host}:{port}", flush=True)

    def handle(conn: socket.socket):
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
                    resp = dispatch(req)
                    conn.sendall((json.dumps(resp) + "\n").encode())

    while True:
        conn, _ = srv.accept()
        threading.Thread(target=handle, args=(conn,), daemon=True).start()


def parse_args(argv: list[str]) -> tuple[argparse.Namespace, list[str]]:
    p = argparse.ArgumentParser(description="AgentOS host bridge")
    p.add_argument("--serial", help="adb serial or IP:5555 for Wi-Fi ADB")
    p.add_argument(
        "--transport",
        choices=("exec-out", "forward", "direct"),
        default="exec-out",
        help="exec-out=adb shell (USB/Wi-Fi ADB); forward=localhost via adb forward; direct=phone IP",
    )
    p.add_argument("--tcp-host", default="127.0.0.1", help="for forward/direct transports")
    p.add_argument("--tcp-port", type=int, default=DEFAULT_FORWARD_PORT)
    p.add_argument("--serve", metavar="HOST:PORT", help="run JSON line TCP server")
    args, rest = p.parse_known_args(argv)
    return args, rest


def main():
    args, rest = parse_args(sys.argv[1:])

    if args.transport == "forward":
        tcp_host, tcp_port = "127.0.0.1", args.tcp_port
    elif args.transport == "direct":
        tcp_host, tcp_port = args.tcp_host, args.tcp_port
    else:
        tcp_host, tcp_port = args.tcp_host, args.tcp_port

    dispatch = make_dispatcher(args.transport, args.serial, tcp_host, tcp_port)

    if args.serve:
        host, port = args.serve.split(":")
        serve(host, int(port), dispatch)
        return

    if not rest:
        req = {"cmd": "ping"}
    else:
        req = json.loads(rest[0])
    print(json.dumps(dispatch(req), ensure_ascii=False))


if __name__ == "__main__":
    main()
