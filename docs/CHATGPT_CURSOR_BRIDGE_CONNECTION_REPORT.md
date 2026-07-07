# ChatGPT ↔ Cursor Bridge — Full Connection Report

> **Purpose:** Give this entire file to ChatGPT so it can connect to the live MCP bridge, understand the architecture, and start the collaboration loop.
>
> **Last updated:** 2026-07-07

---

## Quick start for ChatGPT

You are the **architect**. A persistent **Cursor agent session** on the VPS is the **implementer**.

1. Connect to the MCP server (see section D + E below).
2. Call `bridge_status` first.
3. Use read-only tools to inspect the real project.
4. Send work via `cursor_execute`.
5. Read the structured result and diff.
6. Send corrections via `cursor_followup` to the **same** Cursor session.

---

## A. Environment discovery (what exists on the VPS)

| Item | Finding |
|------|---------|
| **Main project path** | `/opt/clinic-dispatcher` |
| **GitHub repo** | `https://github.com/ukrainebz1-arch/clinic-dispatcher` (private) |
| **Main checkout git state** | **Corrupted** (`bad tree object HEAD`) — files are readable, git commands on read workspace fail |
| **Isolated write worktree** | `/opt/clinic-dispatcher-bridge-poc` |
| **Write worktree branch** | `cursor/chatgpt-bridge-poc-90c5` (healthy git, branched from `origin/main`) |
| **Pull request** | https://github.com/ukrainebz1-arch/clinic-dispatcher/pull/138 |

### Production services — DO NOT disturb

| Service | Port | Purpose |
|---------|------|---------|
| `clinic-recruitment-funnel.service` | 8095 | Facebook ads landing pages |
| `clinic-sales-brain-manager.service` | 8793 | Email reply manager UI |
| `cursor-worker.service` | — | Existing Cursor cloud worker |
| `nginx.service` | 443/80 | Reverse proxy |

Public funnel (untouched): https://jobs.bewerbung-pflege.work/f/top5_kliniken_de

### Cursor CLI on the VPS

| Item | Value |
|------|--------|
| **Binary** | `/root/.local/bin/agent` |
| **Version** | `2026.06.16-20-30-07-a07d3ac` |
| **Auth** | Logged in as `ukraine.bz1@gmail.com` |
| **Available modes** | `--print`, `--resume`, `--continue`, `--mode plan`, `--mode ask`, `--workspace`, `--worktree`, `create-chat`, `worker` |

### Persistent Cursor session mechanism

There is **no** long-running interactive PTY/tmux Cursor shell.

Persistence works via:
1. `agent create-chat` → saves chat ID once
2. Every request: `agent -p --resume <chat_id> --trust --workspace <path> --output-format json --force "<prompt>"`

Cursor's backend preserves conversation context across `--resume` calls. This was verified with a two-round continuity test.

**Current persistent session chat ID:** `ce4726fa-060f-4a24-a8bd-7d123894b29c`

Stored at: `/opt/clinic-dispatcher/var/chatgpt_bridge/cursor_chat_id.txt`

---

## B. Architecture

```
ChatGPT (architect)
    │  HTTPS MCP + Bearer token
    ▼
https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp
    │  nginx proxy (/chatgpt-bridge/ → 127.0.0.1:8805)
    ▼
clinic-chatgpt-bridge.service (port 8805)
    │
    ├── READ-ONLY tools
    │       └── /opt/clinic-dispatcher  (real project files)
    │
    └── CURSOR EXECUTION tools
            │  subprocess: agent -p --resume <chat_id> ...
            ▼
        Persistent Cursor agent session
            │  implements + tests
            ▼
        /opt/clinic-dispatcher-bridge-poc  (isolated git worktree, writes here)
```

### Division of responsibilities

| Role | Who | What |
|------|-----|------|
| **Architect** | ChatGPT (you) | Inspect project, reason, decide changes, send tasks/patches/acceptance criteria |
| **Implementer** | Cursor agent (persistent session) | Edit files, run tests, debug, return structured evidence |
| **Broker** | VPS bridge service | Auth, read-only access, request serialization, session management |

### Intended loop

```
ChatGPT
  → inspect project (read-only tools)
  → reason
  → cursor_execute (implementation request)
  → persistent Cursor session
  → implement + test + debug
  → structured result returned
  → ChatGPT reads result + diff
  → cursor_followup (correction / next step)
  → same Cursor session continues
```

---

## C. How the persistent Cursor session is maintained

1. On first `cursor_execute`, bridge runs `agent create-chat`.
2. Chat ID saved to `/opt/clinic-dispatcher/var/chatgpt_bridge/cursor_chat_id.txt`.
3. All subsequent `cursor_execute` and `cursor_followup` calls use `--resume <chat_id>`.
4. Chat ID **survives** `systemctl restart clinic-chatgpt-bridge`.
5. Only **one** Cursor execution runs at a time (others queued/rejected).

**Not** a always-on terminal process — it is Cursor's server-side session resume API via CLI.

---

## D. Public MCP URL (connect here)

### MCP endpoint

```
https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp
```

### Health check (no auth)

```
https://jobs.bewerbung-pflege.work/chatgpt-bridge/healthz
```

Expected response: `{"ok":true,"service":"chatgpt-bridge"}`

---

## E. Authentication setup

**Method:** Static Bearer token (for ChatGPT Developer Mode custom MCP app).

The token is stored on the VPS at:

```
/opt/clinic-dispatcher/data/private/chatgpt_bridge.env
```

The human operator must retrieve it with:

```bash
grep BRIDGE_AUTH_TOKEN /opt/clinic-dispatcher/data/private/chatgpt_bridge.env
```

**Do not publish the token in public documents.**

### ChatGPT custom app configuration

| Field | Value |
|-------|-------|
| **Server URL** | `https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp` |
| **Authentication** | Bearer token |
| **Header** | `Authorization: Bearer <token-from-env-file>` |

---

## F. MCP tools available

### Read-only tools (ChatGPT inspects real project)

| Tool | Purpose |
|------|---------|
| `bridge_status` | Bridge health, Cursor session state, workspaces, git summary, active request |
| `repo_tree` | Repository structure with bounded depth (default path `.`, max_depth 3) |
| `search_repo` | Ripgrep search across project (`query`, optional `glob`) |
| `read_file` | Read bounded file section (`path`, `offset`, `limit`) — blocks secret paths |
| `git_diff` | Git diff (`path` optional, `workspace`: `write` or `read`) |
| `git_status` | Git status (`workspace`: `write` or `read`) |

**Read workspace:** `/opt/clinic-dispatcher`
**Write workspace (for git_diff/git_status write mode):** `/opt/clinic-dispatcher-bridge-poc`

### Cursor execution tools

| Tool | Purpose |
|------|---------|
| `cursor_execute` | Send implementation task to persistent Cursor session |
| `cursor_followup` | Send follow-up to **same** session (requires `prior_request_id`) |
| `cursor_get_result` | Poll result for async/timed-out requests (`request_id`) |

### `cursor_execute` parameters

| Parameter | Description |
|-----------|-------------|
| `task` | **Required.** What to implement |
| `request_id` | Optional idempotency key |
| `reasoning_context` | Why this change is needed |
| `proposed_changes` | Architectural guidance |
| `proposed_code_or_patch` | Concrete code or patch |
| `files_of_interest` | Files Cursor should focus on |
| `acceptance_criteria` | How to verify success |
| `tests_to_run` | Commands/tests to run |
| `constraints` | Default: no commit, push, or production changes |
| `async_mode` | If true, return immediately and poll `cursor_get_result` |

### Structured response fields (from Cursor)

- `request_id`
- `status`
- `cursor_summary`
- `files_changed`
- `commands_run` / `tests_executed`
- `test_results`
- `errors`
- `debugging_performed`
- `diff_summary` / `git_diff_stat`
- `unresolved_questions`
- `recommendations_for_chatgpt`

---

## G. Service management (for human operator)

| Item | Command / path |
|------|----------------|
| **Service name** | `clinic-chatgpt-bridge.service` |
| **Status** | `sudo systemctl status clinic-chatgpt-bridge` |
| **Logs** | `sudo journalctl -u clinic-chatgpt-bridge -f` |
| **Restart** | `sudo systemctl restart clinic-chatgpt-bridge` |
| **Self-test** | `cd /opt/clinic-dispatcher-bridge-poc && /opt/clinic-dispatcher/.venv/bin/python tools/selftest_chatgpt_bridge.py` |
| **State directory** | `/opt/clinic-dispatcher/var/chatgpt_bridge/` |
| **Bridge code** | `/opt/clinic-dispatcher-bridge-poc/apps/chatgpt_bridge/` |
| **Start script** | `/opt/clinic-dispatcher-bridge-poc/tools/run_chatgpt_bridge.py` |
| **Systemd unit** | `/opt/clinic-dispatcher-bridge-poc/ops/systemd/clinic-chatgpt-bridge.service` |
| **Nginx snippet** | `/opt/clinic-dispatcher-bridge-poc/ops/nginx/chatgpt-bridge.conf` |

---

## H. Workspaces and branches

| Role | Path | Git branch | Notes |
|------|------|------------|-------|
| **Read (inspection)** | `/opt/clinic-dispatcher` | corrupted | Files readable; `git_status` on read workspace returns error |
| **Write (implementation)** | `/opt/clinic-dispatcher-bridge-poc` | `cursor/chatgpt-bridge-poc-90c5` | All Cursor edits go here |

Repository: `ukrainebz1-arch/clinic-dispatcher`

---

## I. Two-round continuity test results

**Status: PASS**

Test script: `tools/selftest_chatgpt_bridge.py`

| Step | Result |
|------|--------|
| 1. `bridge_status` | OK |
| 2. `repo_tree` on `apps/` | 135 entries returned |
| 3. `cursor_execute` round 1 | Created `docs/bridge-poc-d9d38f38.md` with `marker=bridge-poc-d9d38f38` |
| 4. `cursor_followup` round 2 | Appended `followup=remembered` to **same file** |
| 5. Same Cursor session | `ce4726fa-060f-4a24-a8bd-7d123894b29c` throughout |
| 6. `git_diff` | OK |
| 7. Service restart | Chat ID persisted |
| 8. Production services | Untouched |

Round 2 explicitly referenced the prior file from round 1 — continuity confirmed.

---

## J. Limitations and caveats

1. **Not a live PTY shell** — persistence is via Cursor `--resume` chat backend, not an always-on terminal. If the chat is deleted server-side, context is lost and a new session starts.

2. **Main repo git corrupted** — read workspace `git_status`/`git_diff` fail with `bad tree object HEAD`. Use `read_file`, `repo_tree`, `search_repo` for inspection instead.

3. **Long tasks** — default sync timeout 240 seconds. If exceeded, status becomes `running_async`; poll with `cursor_get_result`.

4. **Single execution lock** — only one active Cursor request at a time.

5. **No commit/push by default** — Cursor is instructed not to commit or push unless explicitly requested in the task.

6. **Secret path blocking** — `read_file` blocks `.env`, `data/private/`, credentials, keys. Outputs are redacted for obvious secret patterns.

7. **Bearer auth only** — not a full OAuth server. If ChatGPT requires OAuth-only for your account, an OAuth wrapper may be needed later.

8. **Shared domain** — bridge lives at `jobs.bewerbung-pflege.work/chatgpt-bridge/` (valid Let's Encrypt cert). Funnel routes (`/f/`, `/api/funnel/`) were not modified except adding the bridge proxy block.

9. **Test artifacts** — harmless POC marker files may exist in worktree: `docs/bridge-poc-*.md`

---

## K. Safety rules (enforced by design)

- No generic remote shell tool exposed to ChatGPT
- No unrestricted filesystem access (workspace-scoped paths)
- Secret/env files blocked from `read_file`
- No commit, push, or production service changes unless explicitly requested
- No emails, external business actions, or database modifications
- Request serialization prevents concurrent writes to same Cursor session

---

## L. Suggested first ChatGPT session prompt

Paste this after connecting the MCP app:

```
You are the architect in a ChatGPT ↔ Cursor collaboration loop on clinic-dispatcher.

1. Call bridge_status and summarize the environment.
2. Call repo_tree on path "apps" with max_depth 2.
3. Call cursor_execute with task:
   "Create docs/chatgpt-loop-smoke.md containing exactly one line: smoke=ok.
    Do not modify any other files. Run: test -f docs/chatgpt-loop-smoke.md"
4. Read the structured result and git_diff on workspace write.
5. Call cursor_followup with prior_request_id from step 3 and task:
   "Append a second line to docs/chatgpt-loop-smoke.md: prior=remembered.
    Do not change unrelated files."
6. Confirm the same cursor_session_id was used in both steps.
7. Report whether the collaboration loop is working.
```

---

## M. Related project context (clinic-dispatcher system map)

For a full audit map of all subsystems (Sales Brain, Candidate Brain, WhatsApp, phone, Facebook funnel, etc.):

- **Public raw URL:** https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md
- **GitHub view:** https://github.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/blob/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

---

## N. Key links summary

| Link | Purpose |
|------|---------|
| https://jobs.bewerbung-pflege.work/chatgpt-bridge/mcp | **MCP endpoint — connect ChatGPT here** |
| https://jobs.bewerbung-pflege.work/chatgpt-bridge/healthz | Health check |
| https://github.com/ukrainebz1-arch/clinic-dispatcher/pull/138 | Bridge implementation PR |
| https://github.com/ukrainebz1-arch/clinic-dispatcher | Main private repo |
| https://jobs.bewerbung-pflege.work/f/top5_kliniken_de | Public recruitment funnel (do not break) |
| https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md | Full system audit map |
| https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CHATGPT_CURSOR_BRIDGE_CONNECTION_REPORT.md | **This document (public raw)** |

---

## END OF REPORT
