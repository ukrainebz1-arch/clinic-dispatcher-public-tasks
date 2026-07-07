# ChatGPT ↔ Cursor Bridge — Secure MCP Tunnel Connection Report

> **Purpose:** Connect ChatGPT to the clinic-dispatcher collaboration bridge via **OpenAI Secure MCP Tunnel** (not public Bearer auth).
>
> **Last updated:** 2026-07-07

---

## Quick summary

| Item | Value |
|------|--------|
| **Connection method** | OpenAI Secure MCP Tunnel |
| **Local MCP URL (tunnel-client → bridge)** | `http://127.0.0.1:8805/mcp` |
| **Public Bearer MCP URL** | **DISABLED** (nginx route removed) |
| **Bridge service** | `clinic-chatgpt-bridge.service` |
| **Tunnel service** | `clinic-openai-mcp-tunnel.service` |
| **Tunnel credentials file** | `/opt/clinic-dispatcher/data/private/chatgpt_tunnel.env` |
| **Tunnel configured?** | **Waiting for human credentials** |

---

## Architecture (unchanged collaboration model)

```
ChatGPT conversation
    → OpenAI-hosted Secure MCP Tunnel endpoint
    → tunnel-client (persistent systemd service on VPS)
    → local MCP bridge (127.0.0.1:8805/mcp, no app auth)
    → persistent Cursor session (agent --resume <chat_id>)
    → isolated write worktree (/opt/clinic-dispatcher-bridge-poc)
```

**Preserved unchanged:**
- Persistent Cursor chat ID on disk
- `cursor_execute` / `cursor_followup` / `cursor_get_result`
- All read-only MCP tools
- Request serialization (one active Cursor job)
- Safety restrictions (no commit/push by default, secret path blocking)
- Structured Cursor JSON responses

---

## A. Secure MCP Tunnel status

**Status: WAITING FOR HUMAN CREDENTIALS**

The VPS is prepared:
- `tunnel-client` v0.0.10 installed at `/usr/local/bin/tunnel-client`
- Bridge listens on `127.0.0.1:8805` without application-level auth
- Public nginx route `/chatgpt-bridge/` is **disabled** (returns 404)
- Systemd unit `clinic-openai-mcp-tunnel.service` is installed but **not yet running** until credentials are added

---

## B. Local MCP URL used by tunnel-client

```
http://127.0.0.1:8805/mcp
```

Health check (localhost only):

```
http://127.0.0.1:8805/healthz
```

---

## C. Tunnel systemd service name

```
clinic-openai-mcp-tunnel.service
```

Commands:

```bash
sudo systemctl status clinic-openai-mcp-tunnel
sudo journalctl -u clinic-openai-mcp-tunnel -f
sudo systemctl enable --now clinic-openai-mcp-tunnel
```

Tunnel health UI (after started): `http://127.0.0.1:8806/ui`

---

## D. Private env file path

```
/opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
```

Permissions: `600` (root only)

Template already created on the VPS with empty values.

---

## E. Values the human must obtain from OpenAI Platform

**Do NOT paste these into ChatGPT. Store only in the private env file on the VPS.**

| Variable | What it is | Where to get it |
|----------|-----------|-----------------|
| `CONTROL_PLANE_TUNNEL_ID` | Tunnel identifier (`tunnel_...`) | OpenAI Platform → Settings → Tunnels |
| `CONTROL_PLANE_API_KEY` | **Runtime** API key (NOT admin key) | OpenAI Platform → Settings → API keys (Runtime) |

**Optional (defaults are fine):**

| Variable | Default |
|----------|---------|
| `MCP_SERVER_URL` | `http://127.0.0.1:8805/mcp` |
| `CONTROL_PLANE_BASE_URL` | `https://api.openai.com` |

### Required permissions for the Runtime API key

The key used for `CONTROL_PLANE_API_KEY` needs:
- **Tunnels: Read**
- **Tunnels: Use**

Do **not** use the Admin API key for the long-running daemon.

---

## F. OpenAI Platform UI steps

1. Go to **Tunnels management**: https://platform.openai.com/settings/organization/tunnels
2. Click **Create tunnel** (or reuse an existing tunnel for this POC).
3. Copy the **tunnel ID** (format `tunnel_0123456789abcdef...`).
4. Go to **Runtime API keys**: https://platform.openai.com/settings/organization/api-keys
5. Create a new **Runtime API key** with **Tunnels Read + Use** permissions.
6. SSH to the VPS and edit:

   ```bash
   sudo nano /opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
   ```

7. Set:

   ```bash
   CONTROL_PLANE_API_KEY=sk-...your-runtime-key...
   CONTROL_PLANE_TUNNEL_ID=tunnel_...your-tunnel-id...
   MCP_SERVER_URL=http://127.0.0.1:8805/mcp
   ```

8. Save, ensure permissions:

   ```bash
   sudo chmod 600 /opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
   ```

9. Validate (optional, on VPS):

   ```bash
   source /opt/clinic-dispatcher/data/private/chatgpt_tunnel.env
   tunnel-client doctor --control-plane.tunnel-id "$CONTROL_PLANE_TUNNEL_ID" --mcp.server-url "$MCP_SERVER_URL"
   ```

10. Start the tunnel service:

    ```bash
    sudo systemctl enable --now clinic-openai-mcp-tunnel
    curl -fsS http://127.0.0.1:8806/readyz
    ```

---

## G. ChatGPT UI steps (after tunnel is active)

1. Open **ChatGPT connector settings**: https://chatgpt.com/#settings/Connectors
2. Add a **custom MCP app / connector** using your tunnel.
3. In the OpenAI Platform tunnel detail page, copy the **ChatGPT connector URL** or follow the tunnel setup instructions shown there for connecting ChatGPT to this tunnel.
4. Connect the app — ChatGPT will reach your private MCP bridge through the Secure MCP Tunnel (no manual Bearer token needed).
5. In a new ChatGPT conversation with the connector enabled, call `bridge_status` first.
6. Then use read-only tools, `cursor_execute`, and `cursor_followup` as the architect.

**Suggested first prompt in ChatGPT:**

```
Call bridge_status. Confirm connection_mode is secure_mcp_tunnel and public_mcp_enabled is false.
Then run the harmless smoke test from the connection report.
```

---

## H. Old public MCP URL status

| URL | Status |
|-----|--------|
| `https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp` | **DISABLED** (nginx location commented out, returns 404) |
| `http://127.0.0.1:8805/mcp` | **ACTIVE** (localhost only, no app auth, for tunnel-client) |

The Bearer-token auth code remains in the bridge but is **off** (`BRIDGE_REQUIRE_AUTH=false`). To re-enable public Bearer mode (not recommended for ChatGPT Developer Mode), set `BRIDGE_REQUIRE_AUTH=true` and restore the nginx location.

---

## I. Tunnel connectivity testing

| Test | Result |
|------|--------|
| Local MCP without auth on 127.0.0.1 | **PASS** (HTTP 200 initialize) |
| `bridge_status` via local MCP | **PASS** (`connection_mode=secure_mcp_tunnel`, `public_mcp_enabled=false`) |
| Public HTTPS `/chatgpt-bridge/` | **PASS** (404 — correctly disabled) |
| `tunnel-client` binary installed | **PASS** (v0.0.10) |
| Tunnel service without credentials | **EXPECTED FAIL** (clear error: missing API key / tunnel ID) |
| End-to-end OpenAI tunnel → ChatGPT | **NOT TESTED** — requires human to add credentials in step F |

---

## J. Persistent Cursor session + two-round continuity

**CONFIRMED STILL WORKING** after transport change.

Latest selftest (`tools/selftest_chatgpt_bridge.py`):

| Check | Result |
|-------|--------|
| Same Cursor session | `ce4726fa-060f-4a24-a8bd-7d123894b29c` |
| Round 1 `cursor_execute` | Created marker file |
| Round 2 `cursor_followup` | Appended `followup=remembered` to same file |
| Write worktree | `/opt/clinic-dispatcher-bridge-poc` |
| Structured responses | OK |
| `git_diff` | OK |
| Production services | Untouched |

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

## Service reference

| Service | Purpose |
|---------|---------|
| `clinic-chatgpt-bridge.service` | Local MCP bridge + Cursor session manager |
| `clinic-openai-mcp-tunnel.service` | OpenAI Secure MCP Tunnel client |
| `clinic-recruitment-funnel.service` | **Do not touch** — Facebook funnel |
| `clinic-sales-brain-manager.service` | **Do not touch** — email manager |

---

## END OF REPORT
