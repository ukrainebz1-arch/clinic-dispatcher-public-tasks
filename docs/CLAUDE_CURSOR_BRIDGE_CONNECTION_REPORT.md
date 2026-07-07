# Claude ↔ Cursor Bridge — Remote MCP Connection Report

> **Purpose:** Connect the **normal Claude application** (Claude.ai / Claude app) to the clinic-dispatcher collaboration bridge via **Remote MCP over HTTPS with OAuth** — NOT Anthropic API, NOT a Claude model on the VPS.
>
> **Report version:** 2026-07-07T19:51:00Z

---

## LIVE STATUS

| Field | Current value |
|-------|----------------|
| **Connection method** | **Remote MCP (Streamable HTTP) + OAuth 2.1** |
| **Anthropic API on VPS** | **NOT used** — Claude runs the model; VPS only executes tools |
| **Public MCP URL** | `https://jobs.bewerbung-pflege.work/claude-mcp` |
| **Transport** | Streamable HTTP |
| **Authentication** | OAuth 2.1 authorization code + PKCE S256 + refresh tokens |
| **Bridge service** | `clinic-claude-mcp.service` — **active** |
| **Dedicated lane ID** | `claude-primary` |
| **Persistent Claude Cursor session** | `252a3d92-3502-4d85-91b1-781c92dac45e` |
| **Read workspace** | `/opt/clinic-dispatcher` |
| **Claude write worktree** | `/opt/clinic-dispatcher-claude-poc` (branch `cursor/claude-bridge-poc-90c5`) |
| **ChatGPT bridge** | **unchanged and operational** (`clinic-chatgpt-bridge.service`) |
| **Two-round Claude continuity test** | **PASS** (2026-07-07T18:56Z) |
| **Isolation test** | **PASS** — Claude session/worktree separate from ChatGPT |

---

## Architecture

```
Claude conversation in Claude app (architect / primary reasoning)
    → Custom Connector (Remote MCP)
    → https://jobs.bewerbung-pflege.work/claude-mcp
    → OAuth 2.1 (PKCE + operator consent)
    → clinic-claude-mcp.service
    → SAME dedicated Claude Cursor session (agent --resume <chat_id>)
    → isolated Claude write worktree (/opt/clinic-dispatcher-claude-poc)
    → structured tool result returned to SAME Claude conversation
    → Claude reasons and sends follow-up
    → SAME Claude Cursor session continues
```

**Parallel lane (unchanged):**

```
Custom GPT → GPT Actions REST → clinic-chatgpt-bridge.service
    → ChatGPT Cursor session → ChatGPT worktree (/opt/clinic-dispatcher-bridge-poc)
```

**NOT used:**
- Anthropic model API on VPS ❌
- Claude Code as primary client ❌
- Shared Cursor session between ChatGPT and Claude ❌
- Shared write worktree ❌
- Public unauthenticated write tools ❌

---

## A. Public Claude Remote MCP URL

```
https://jobs.bewerbung-pflege.work/claude-mcp
```

Use this exact URL in Claude **Customize → Connectors → Add custom connector → MCP URL**.

Both `/claude-mcp` and `/claude-mcp/` reach the service; prefer the URL above.

---

## B. Transport type

**Streamable HTTP** (MCP remote connector protocol over HTTPS).

---

## C. Authentication architecture

| Component | URL / detail |
|-----------|----------------|
| **Protected resource metadata** | `https://jobs.bewerbung-pflege.work/.well-known/oauth-protected-resource/claude-mcp` |
| **Authorization server metadata (RFC 8414 path-aware)** | `https://jobs.bewerbung-pflege.work/.well-known/oauth-authorization-server/claude-mcp` |
| **Authorization server metadata (issuer-local)** | `https://jobs.bewerbung-pflege.work/claude-mcp/.well-known/oauth-authorization-server` |
| **Authorization endpoint** | `https://jobs.bewerbung-pflege.work/claude-mcp/authorize` |
| **Token endpoint** | `https://jobs.bewerbung-pflege.work/claude-mcp/token` |
| **Registered Claude callback** | `https://claude.ai/api/mcp/auth_callback` |
| **Grant types** | `authorization_code`, `refresh_token` |
| **PKCE** | S256 required |
| **Scopes** | `repo:read`, `cursor:execute` |
| **Operator consent** | Browser page at `/claude-mcp/consent` protected by private operator secret |

Flow:

1. Claude initiates OAuth with pre-registered client ID (+ client secret in Advanced settings).
2. Browser opens operator consent page on the VPS.
3. Operator enters the private consent secret.
4. Authorization code returned to Claude callback.
5. Claude exchanges code + PKCE verifier for access + refresh tokens.
6. MCP tool calls use `Authorization: Bearer <access_token>`.

---

## D. Claude UI setup steps

1. Open Claude → **Settings** → **Connectors** (or **Customize → Connectors**).
2. Click **Add custom connector**.
3. **MCP URL:** `https://jobs.bewerbung-pflege.work/claude-mcp`
4. Open **Advanced settings**.
5. Enter **Client ID** from private env file (see section F).
6. Enter **Client secret** from private env file.
7. Save connector and authorize when prompted.
8. Complete the **operator consent page** in your browser (one-time per authorization).

---

## E. Private credentials required

Retrieve these from the VPS private env file — **do not commit or share them**:

| Setting | Env variable |
|---------|----------------|
| OAuth client ID | `CLAUDE_OAUTH_CLIENT_ID` |
| OAuth client secret | `CLAUDE_OAUTH_CLIENT_SECRET` |
| Operator consent secret | `CLAUDE_OPERATOR_SECRET` |

---

## F. Private env file path

```
/opt/clinic-dispatcher/data/private/claude_mcp.env
```

Permissions: `600` (root only). Contains all Claude connector secrets.

---

## G. MCP tool list (10 tools)

| Tool | Purpose |
|------|---------|
| `bridge_status` | Health, lane, workspaces, Cursor session, active task |
| `repo_tree` | Bounded repository tree (read workspace) |
| `search_repository` | Bounded code/content search |
| `read_repository_file` | Bounded file read with path safety |
| `git_status` | Git status of Claude write worktree |
| `git_diff` | Bounded diff of Claude write worktree |
| `start_cursor_task` | Start implementation in Claude Cursor session |
| `continue_cursor_task` | Follow-up in same Claude Cursor session |
| `get_cursor_task_result` | Poll task status/result |
| `wait_for_cursor_task` | Long-poll up to 240 seconds |

All tool outputs are bounded below ~120,000 characters with explicit truncation metadata.

---

## H. Dedicated Claude lane

| Field | Value |
|-------|-------|
| **Lane ID** | `claude-primary` |
| **State directory** | `/opt/clinic-dispatcher/var/claude_bridge/claude-primary` |
| **Cursor session fingerprint** | `252a3d92-3502-4d85-91b1-781c92dac45e` |
| **Write worktree** | `/opt/clinic-dispatcher-claude-poc` |
| **Branch** | `cursor/claude-bridge-poc-90c5` |

---

## I. Two-round continuity test

**Result: PASS**

Round 1: `start_cursor_task` → created marker file in Claude worktree → `wait_for_cursor_task` completed.

Round 2: `continue_cursor_task` referencing Round 1 → appended second marker line demonstrating session memory → completed.

Same Cursor session ID in both rounds: `252a3d92-3502-4d85-91b1-781c92dac45e`.

---

## J. Isolation test

**Result: PASS**

| Check | ChatGPT | Claude |
|-------|---------|--------|
| Cursor session | `ce4726fa-060f-4a24-a8bd-7d123894b29c` | `252a3d92-3502-4d85-91b1-781c92dac45e` |
| Write worktree | `/opt/clinic-dispatcher-bridge-poc` | `/opt/clinic-dispatcher-claude-poc` |

Claude test marker files do not appear in the ChatGPT worktree.

---

## K. ChatGPT bridge regression

**Result: PASS** (non-destructive)

- `getBridgeStatus` OK
- REST read operation OK
- ChatGPT session and worktree unchanged
- `clinic-chatgpt-bridge.service` still active

---

## L. Service management

| Item | Value |
|------|-------|
| **Service name** | `clinic-claude-mcp.service` |
| **Status** | `systemctl status clinic-claude-mcp.service` |
| **Logs** | `journalctl -u clinic-claude-mcp.service -f` |
| **Restart** | `systemctl restart clinic-claude-mcp.service` |
| **Local bind** | `127.0.0.1:8806` |
| **Nginx public path** | `/claude-mcp` |

ChatGPT service remains: `clinic-chatgpt-bridge.service` on port `8805`.

---

## M. Human action still required

1. Copy **client ID**, **client secret**, and **operator secret** from `/opt/clinic-dispatcher/data/private/claude_mcp.env`.
2. Add the custom connector in Claude with those values.
3. Complete the **operator consent page** when Claude triggers OAuth.
4. Verify tools appear in Claude and run a harmless read (`bridge_status`) before write tasks.

---

## N. Known limitations

- Fixed single lane (`claude-primary`) for this POC; lane abstraction supports future expansion.
- One active Cursor write task per lane at a time.
- Operator must approve each OAuth authorization via consent page.
- Main read workspace git HEAD is corrupted; reads still work; writes go to isolated worktrees.
- MCP URL must be reachable from Anthropic cloud (public HTTPS required).

---

## O. OAuth routing fix (2026-07-07)

### Root cause

Claude (and MCP OAuth clients per RFC 8414) discover authorization-server metadata at:

```
https://jobs.bewerbung-pflege.work/.well-known/oauth-authorization-server/claude-mcp
```

That URL returned **404**. Metadata discovery failed, so the client fell back to a legacy default:

```
https://jobs.bewerbung-pflege.work/authorize   ← wrong (404)
```

instead of the canonical:

```
https://jobs.bewerbung-pflege.work/claude-mcp/authorize
```

A secondary issue: the operator consent HTML form posted to `/consent` (domain root) instead of `/claude-mcp/consent`.

### Fix applied

1. **nginx** — added RFC 8414 path-aware metadata proxy:
   - `/.well-known/oauth-authorization-server/claude-mcp` → backend `/.well-known/oauth-authorization-server`
2. **Consent form** — POST action now uses `{issuer_url}/consent` (full `/claude-mcp/consent` path).

No OAuth credentials were rotated. Existing Client ID, Client Secret, and Operator Secret remain valid.

### Public OAuth URLs after fix

| Endpoint | URL |
|----------|-----|
| Protected resource metadata | `https://jobs.bewerbung-pflege.work/.well-known/oauth-protected-resource/claude-mcp` |
| AS metadata (RFC 8414) | `https://jobs.bewerbung-pflege.work/.well-known/oauth-authorization-server/claude-mcp` |
| AS metadata (issuer-local) | `https://jobs.bewerbung-pflege.work/claude-mcp/.well-known/oauth-authorization-server` |
| Authorization | `https://jobs.bewerbung-pflege.work/claude-mcp/authorize` |
| Token | `https://jobs.bewerbung-pflege.work/claude-mcp/token` |
| Consent | `https://jobs.bewerbung-pflege.work/claude-mcp/consent` |
| MCP resource | `https://jobs.bewerbung-pflege.work/claude-mcp` |

### Live OAuth test result (post-fix)

**PASS** — `tools/selftest_claude_mcp.py` (2026-07-07T19:51Z):

- RFC 8414 AS metadata returns `authorization_endpoint` = `/claude-mcp/authorize`
- Claude-style authorize → consent → callback code → token exchange (PKCE S256)
- Refresh token exchange
- Authenticated MCP initialize + 10 tools listed
- ChatGPT bridge regression unchanged

**No connector recreation required** — use existing Client ID and Client Secret.

---

## Related docs

- ChatGPT bridge: [CHATGPT_CURSOR_BRIDGE_CONNECTION_REPORT.md](https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CHATGPT_CURSOR_BRIDGE_CONNECTION_REPORT.md)
- System map: [EXTERNAL_SYSTEM_AUDIT_MAP.md](https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md)
