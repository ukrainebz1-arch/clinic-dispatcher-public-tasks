# ChatGPT ↔ Cursor Bridge — Secure MCP Tunnel Connection Report

> **Purpose:** Connect ChatGPT to the clinic-dispatcher collaboration bridge via **OpenAI Secure MCP Tunnel** (NOT public Bearer-token MCP).
>
> **Report version:** 2026-07-07T18:01:00Z (Secure MCP Tunnel transport — supersedes all Bearer-token public endpoint instructions)

---

## LIVE STATUS (read this first)

| Field | Current value on VPS |
|-------|----------------------|
| **Secure MCP Tunnel active?** | **NO** — waiting for human to create tunnel + Runtime API key in OpenAI Platform |
| **Tunnel ID (non-secret identifier)** | **NOT SET** — will appear as `tunnel_...` after you create a tunnel in Platform |
| **Local MCP endpoint (tunnel-client → bridge)** | `http://127.0.0.1:8805/mcp` |
| **Local bridge health** | `http://127.0.0.1:8805/healthz` → `{"ok":true,"service":"chatgpt-bridge"}` |
| **Tunnel-client service** | `clinic-openai-mcp-tunnel.service` — **installed, disabled, inactive** |
| **Tunnel-client binary** | `/usr/local/bin/tunnel-client` v0.0.10 |
| **Tunnel health UI (after tunnel starts)** | `http://127.0.0.1:8806/ui` |
| **Bridge service** | `clinic-chatgpt-bridge.service` — **active** |
| **Old public Bearer MCP URL enabled?** | **NO** — `https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp` returns **404** |
| **Application auth on local MCP** | **None** (localhost-only; safe because not public) |
| **Credentials file** | `/opt/clinic-dispatcher/data/private/chatgpt_tunnel.env` — `CONTROL_PLANE_API_KEY` and `CONTROL_PLANE_TUNNEL_ID` are **empty** |
| **Persistent Cursor session chat ID** | `ce4726fa-060f-4a24-a8bd-7d123894b29c` (unchanged) |

### What is blocked right now

The VPS-side tunnel layer is **fully prepared** but **cannot connect to OpenAI** until a human operator completes the OpenAI Platform steps below and fills the private env file on the VPS. **No secret should be pasted into ChatGPT.**

---

## STOP — human action required in OpenAI Platform

Complete these steps **before** the tunnel can become active. Do **not** paste any API key or tunnel secret into ChatGPT.

### Step 1 — Create a tunnel

1. Open: https://platform.openai.com/settings/organization/tunnels
2. Click **Create tunnel** (or **New tunnel**).
3. Give it a name such as `clinic-dispatcher-bridge-poc`.
4. After creation, copy the **Tunnel ID** shown on the tunnel detail page. It looks like:
   ```
   tunnel_0123456789abcdef0123456789abcdef
   ```
5. Keep that page open — it will also show ChatGPT connector instructions after the tunnel client is running.

### Step 2 — Create a Runtime API key (NOT the Admin key)

1. Open: https://platform.openai.com/settings/organization/api-keys
2. Click **Create new secret key** (Runtime API key section).
3. Name it e.g. `clinic-bridge-tunnel-runtime`.
4. Enable permissions:
   - **Tunnels: Read**
   - **Tunnels: Use**
5. Create the key and copy it once (you will not see it again).

### Step 3 — Put values on the VPS only (SSH)

```bash
sudo nano /opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
```

Set (replace with your values):

```bash
CONTROL_PLANE_TUNNEL_ID=tunnel_YOUR_TUNNEL_ID_HERE
CONTROL_PLANE_API_KEY=sk-YOUR_RUNTIME_KEY_HERE
MCP_SERVER_URL=http://127.0.0.1:8805/mcp
```

Then:

```bash
sudo chmod 600 /opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
source /opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
tunnel-client doctor --control-plane.tunnel-id "$CONTROL_PLANE_TUNNEL_ID" --mcp.server-url "$MCP_SERVER_URL"
sudo systemctl enable --now clinic-openai-mcp-tunnel
curl -fsS http://127.0.0.1:8806/readyz
```

When `readyz` returns success, the Secure MCP Tunnel is **active**.

After you complete Step 3, ask the VPS agent to re-run the tunnel connectivity test and update this report's LIVE STATUS section with your tunnel ID (non-secret) and active=yes.

---

## Architecture (unchanged collaboration model)

```
ChatGPT conversation
    → OpenAI-hosted Secure MCP Tunnel endpoint
    → tunnel-client (clinic-openai-mcp-tunnel.service on VPS)
    → local MCP bridge (127.0.0.1:8805/mcp, no app auth)
    → persistent Cursor session (agent --resume <chat_id>)
    → isolated write worktree (/opt/clinic-dispatcher-bridge-poc)
```

**NOT used anymore:**

```
ChatGPT → https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp + Bearer token   ❌ DISABLED
```

**Preserved unchanged:**
- Persistent Cursor chat ID on disk
- `cursor_execute` / `cursor_followup` / `cursor_get_result`
- All read-only MCP tools
- Request serialization (one active Cursor job)
- Safety restrictions
- Structured Cursor JSON responses

---

## ChatGPT UI steps (after tunnel is active on VPS)

Do this **after** Step 3 above succeeds (`readyz` OK).

1. Open ChatGPT connector settings: https://chatgpt.com/#settings/Connectors
2. Click **Create** / **Add connector** (wording may vary by account).
3. Choose **MCP / custom connector** (not a manual Bearer URL).
4. Open your tunnel in Platform: https://platform.openai.com/settings/organization/tunnels
5. Open the tunnel you created (`clinic-dispatcher-bridge-poc` or your name).
6. On the tunnel detail page, use the **Connect to ChatGPT** / **ChatGPT connector** instructions or link shown there (OpenAI generates the correct Secure MCP Tunnel connector binding for your tunnel ID).
7. Complete the connector setup in ChatGPT — **no manual Bearer token header is required**.
8. Start a **new ChatGPT conversation** with the connector enabled.
9. First tool call: **`bridge_status`**
   - Expect: `"connection_mode": "secure_mcp_tunnel"`
   - Expect: `"public_mcp_enabled": false`
   - Expect: `"secure_mcp_tunnel_configured": true` (after credentials are set)
10. Proceed with read-only tools, then `cursor_execute`, then `cursor_followup`.

**First ChatGPT prompt after connecting:**

```
Call bridge_status. Confirm:
- connection_mode is secure_mcp_tunnel
- public_mcp_enabled is false
- secure_mcp_tunnel_configured is true
Then repo_tree on apps/ with max_depth 2.
```

---

## Old public Bearer-token endpoint

| URL | Status | Verified |
|-----|--------|----------|
| `https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp` | **DISABLED** | HTTP **404** |
| `https://jobs.bewerbung-pflege.work/chatgpt-bridge/healthz` | **DISABLED** | HTTP **404** |
| `http://127.0.0.1:8805/mcp` | **ACTIVE** (localhost only) | HTTP **200** initialize |

Nginx location `/chatgpt-bridge/` is commented out in `/etc/nginx/sites-available/jobs-bewerbung-pflege`.

Bridge env: `BRIDGE_REQUIRE_AUTH=false` — Bearer auth code exists but is **off**.

---

## Tunnel connectivity test results (2026-07-07T18:01:00Z)

Tests run on VPS **before** human adds tunnel credentials:

| # | Test | Command / check | Result |
|---|------|-----------------|--------|
| 1 | Local bridge health | `curl http://127.0.0.1:8805/healthz` | **PASS** — `{"ok":true}` |
| 2 | Local MCP without auth | POST `http://127.0.0.1:8805/mcp` initialize | **PASS** — HTTP 200, session ID returned |
| 3 | `bridge_status` via local MCP | tools/call `bridge_status` | **PASS** — `connection_mode=secure_mcp_tunnel`, `public_mcp_enabled=false` |
| 4 | Public Bearer route disabled | POST `https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp` | **PASS** — HTTP **404** (not exposed) |
| 5 | Public health disabled | GET `https://jobs.bewerbung-pflege.work/chatgpt-bridge/healthz` | **PASS** — HTTP **404** |
| 6 | Bridge bound to localhost | `ss -tlnp \| grep 8805` | **PASS** — `127.0.0.1:8805` only |
| 7 | tunnel-client installed | `tunnel-client --version` | **PASS** — v0.0.10 |
| 8 | Tunnel start without credentials | `run_openai_mcp_tunnel.sh` | **EXPECTED FAIL** — "CONTROL_PLANE_API_KEY and CONTROL_PLANE_TUNNEL_ID must be set" |
| 9 | Tunnel service state | `systemctl is-active clinic-openai-mcp-tunnel` | **inactive** (disabled until credentials added) |
| 10 | OpenAI tunnel → ChatGPT end-to-end | Platform + ChatGPT connector | **NOT RUN** — blocked on human Steps 1–3 |
| 11 | Cursor two-round continuity | `tools/selftest_chatgpt_bridge.py` | **PASS** — same session `ce4726fa-060f-4a24-a8bd-7d123894b29c` |

---

## Services reference

| Service | Status | Purpose |
|---------|--------|---------|
| `clinic-chatgpt-bridge.service` | active | Local MCP bridge + Cursor session |
| `clinic-openai-mcp-tunnel.service` | inactive/disabled | OpenAI Secure MCP Tunnel client |
| `clinic-recruitment-funnel.service` | active — **do not touch** | Facebook funnel |
| `clinic-sales-brain-manager.service` | active — **do not touch** | Email manager |

Logs:

```bash
sudo journalctl -u clinic-chatgpt-bridge -f
sudo journalctl -u clinic-openai-mcp-tunnel -f   # after enabled
```

---

## MCP tools (unchanged)

**Read-only:** `bridge_status`, `repo_tree`, `search_repo`, `read_file`, `git_diff`, `git_status`

**Cursor execution:** `cursor_execute`, `cursor_followup`, `cursor_get_result`

---

## Workspaces (unchanged)

| Role | Path |
|------|------|
| Read (ChatGPT inspection) | `/opt/clinic-dispatcher` |
| Write (Cursor implementation) | `/opt/clinic-dispatcher-bridge-poc` |

Branch: `cursor/chatgpt-bridge-poc-90c5`  
PR: https://github.com/ukrainebz1-arch/clinic-dispatcher/pull/138

---

## Related docs

- Full system audit map: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md
- OpenAI Secure MCP Tunnel guide: https://developers.openai.com/api/docs/guides/secure-mcp-tunnels
- Platform Tunnels: https://platform.openai.com/settings/organization/tunnels

---

## END OF REPORT
