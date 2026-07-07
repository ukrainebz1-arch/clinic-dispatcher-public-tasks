# ChatGPT ↔ Cursor Bridge — GPT Actions Connection Report

> **Purpose:** Connect a **Custom GPT** inside normal ChatGPT to the clinic-dispatcher collaboration bridge via **GPT Actions (HTTPS REST)** — NOT MCP, NOT OpenAI Secure MCP Tunnel, NOT OpenAI model API on the VPS.
>
> **Report version:** 2026-07-07T18:27:00Z

---

## LIVE STATUS

| Field | Current value |
|-------|----------------|
| **Connection method** | **GPT Actions REST API** (Custom GPT → HTTPS → VPS bridge → persistent Cursor session) |
| **Secure MCP Tunnel** | **STOPPED / not used** — do not configure OpenAI tunnel credentials |
| **OpenAI model API on VPS** | **NOT used** — ChatGPT runs the model; VPS only executes tools |
| **API base URL** | `https://jobs.bewerbung-pflege.work/chatgpt-action` |
| **OpenAPI schema URL (public, no secret)** | `https://jobs.bewerbung-pflege.work/chatgpt-action/openapi.yaml` |
| **Authentication** | Bearer API key (configured privately in Custom GPT editor) |
| **Bridge service** | `clinic-chatgpt-bridge.service` — **active** |
| **Old public MCP Bearer URL** | **DISABLED** — `/chatgpt-bridge/` returns 404 |
| **Persistent Cursor session** | `ce4726fa-060f-4a24-a8bd-7d123894b29c` |
| **Read workspace** | `/opt/clinic-dispatcher` |
| **Write worktree** | `/opt/clinic-dispatcher-bridge-poc` (branch `cursor/chatgpt-bridge-poc-90c5`) |
| **Two-round REST continuity test** | **PASS** (2026-07-07T18:27Z) |

---

## Architecture

```
Custom GPT conversation inside ChatGPT (architect / primary reasoning)
    → GPT Action (HTTPS REST + Bearer auth)
    → https://jobs.bewerbung-pflege.work/chatgpt-action/...
    → clinic-chatgpt-bridge.service (FastAPI adapter)
    → SAME persistent Cursor session (agent --resume <chat_id>)
    → isolated write worktree (/opt/clinic-dispatcher-bridge-poc)
    → structured JSON result returned to Custom GPT
    → same Custom GPT conversation reasons and sends follow-up
    → SAME Cursor session continues
```

**NOT used:**
- OpenAI Secure MCP Tunnel ❌
- ChatGPT custom MCP app ❌
- OpenAI model API calls from VPS ❌
- Public unauthenticated write endpoints ❌

**Preserved unchanged:**
- Persistent Cursor chat ID on disk
- `agent --resume` session continuity
- Request serialization (one active Cursor write task)
- Read-only safety restrictions
- Structured implementation reports
- Isolated write worktree

---

## A. Public OpenAPI schema URL

```
https://jobs.bewerbung-pflege.work/chatgpt-action/openapi.yaml
```

Import this URL in the Custom GPT Action editor. The schema contains **no secrets**.

---

## B. API base URL

```
https://jobs.bewerbung-pflege.work/chatgpt-action
```

Example endpoints:
- `GET  /chatgpt-action/status`
- `POST /chatgpt-action/cursor/execute`
- `POST /chatgpt-action/cursor/followup`
- `POST /chatgpt-action/cursor/wait`

---

## C. Authentication (Custom GPT editor)

| Setting | Value |
|---------|--------|
| **Type** | API Key |
| **Auth Type** | Bearer |
| **Header** | `Authorization: Bearer <your-api-key>` |

The API key is stored on the VPS at:

```
/opt/clinic-dispatcher/data/private/chatgpt_bridge.env
```

Retrieve on VPS only (do **not** paste into ChatGPT chat):

```bash
grep BRIDGE_AUTH_TOKEN /opt/clinic-dispatcher/data/private/chatgpt_bridge.env
```

Configure the value **only** in the Custom GPT Action authentication settings — not in the OpenAPI schema and not in this public report.

---

## D. operationIds (GPT Actions)

| operationId | Method | Path | Purpose |
|-------------|--------|------|---------|
| `getBridgeStatus` | GET | `/chatgpt-action/status` | Bridge + Cursor session status |
| `getRepoTree` | POST | `/chatgpt-action/repo/tree` | Bounded repo tree |
| `searchRepository` | POST | `/chatgpt-action/repo/search` | Search code/files |
| `readRepositoryFile` | POST | `/chatgpt-action/repo/read` | Read bounded file section |
| `getGitStatus` | GET | `/chatgpt-action/git/status` | Write worktree git status |
| `getGitDiff` | POST | `/chatgpt-action/git/diff` | Bounded git diff |
| `startCursorTask` | POST | `/chatgpt-action/cursor/execute` | Start Cursor implementation |
| `continueCursorTask` | POST | `/chatgpt-action/cursor/followup` | Follow-up same Cursor session |
| `getCursorTaskResult` | GET | `/chatgpt-action/cursor/result/{request_id}` | Poll task result |
| `waitForCursorTask` | POST | `/chatgpt-action/cursor/wait` | Bounded long poll |

---

## E. Persistent Cursor session — confirmed preserved

| Item | Value |
|------|--------|
| Mechanism | `agent create-chat` once, then `agent -p --resume <chat_id>` |
| Chat ID file | `/opt/clinic-dispatcher/var/chatgpt_bridge/cursor_chat_id.txt` |
| Current session | `ce4726fa-060f-4a24-a8bd-7d123894b29c` |

---

## F. Two-round REST test results (actual, 2026-07-07)

Test script: `tools/selftest_chatgpt_actions.py`

### Round 1 — `startCursorTask`

- Created `docs/gpt-action-<marker>.md` with `marker=...`
- `waitForCursorTask` → `status=completed`
- Session: `ce4726fa-060f-4a24-a8bd-7d123894b29c`

### Round 2 — `continueCursorTask`

- Referenced `parent_request_id` from round 1
- Appended `followup=remembered` to same file
- `waitForCursorTask` → `status=completed`
- Session: **same** `ce4726fa-060f-4a24-a8bd-7d123894b29c`

**Result: PASS**

---

## G. Round 2 same-session confirmation

**YES.** Both rounds returned identical `cursor_session_id`: `ce4726fa-060f-4a24-a8bd-7d123894b29c`.

---

## H. Custom GPT Action setup steps

1. Open ChatGPT → **Explore GPTs** → create or edit your Custom GPT.
2. In the GPT editor, open **Configure** → **Actions** → **Create new action**.
3. Set **Schema** import URL to:
   ```
   https://jobs.bewerbung-pflege.work/chatgpt-action/openapi.yaml
   ```
4. Under **Authentication**, choose:
   - Auth type: **API Key**
   - API Key: paste the value from `chatgpt_bridge.env` on the VPS (see section C)
   - Auth Type: **Bearer**
5. Save the GPT.
6. Start a **new conversation** with that Custom GPT.
7. First action call: **`getBridgeStatus`**
   - Expect `connection_mode: gpt_actions`
   - Expect same `cursor_session.chat_id` across tasks
8. Normal loop:
   - inspect with read actions
   - `startCursorTask`
   - `waitForCursorTask`
   - `getGitDiff`
   - reason in the GPT conversation
   - `continueCursorTask` with `parent_request_id`
   - `waitForCursorTask`
   - repeat

**Suggested first GPT instruction snippet:**

```
You are the architect. The VPS bridge executes implementation in a persistent Cursor session.
Always call getBridgeStatus first. Use startCursorTask then waitForCursorTask.
For corrections, use continueCursorTask with parent_request_id from the prior task.
Never ask the user to paste API keys into chat.
```

---

## I. Limitations

1. **One active Cursor write task at a time** — concurrent execute/followup returns HTTP 409.
2. **Long tasks** — use `waitForCursorTask` (max 240s) or poll `getCursorTaskResult`.
3. **Read workspace git corrupted** — main repo at `/opt/clinic-dispatcher` has bad git HEAD; use read file/tree/search tools, not read-workspace git.
4. **MCP endpoint** — optional localhost-only MCP code remains but is **disabled** (`BRIDGE_ENABLE_MCP=false`); Custom GPT must use REST Actions only.
5. **Secure MCP Tunnel** — abandoned for this POC; `clinic-openai-mcp-tunnel.service` is disabled.
6. **Domain sharing** — GPT Actions live on `jobs.bewerbung-pflege.work/chatgpt-action/` alongside the recruitment funnel; funnel routes were not modified except adding this proxy block.
7. **No commit/push** — Cursor is instructed not to commit or push unless explicitly requested in a task.

---

## Service reference

```bash
sudo systemctl status clinic-chatgpt-bridge
sudo journalctl -u clinic-chatgpt-bridge -f
cd /opt/clinic-dispatcher-bridge-poc && /opt/clinic-dispatcher/.venv/bin/python tools/selftest_chatgpt_actions.py
```

PR: https://github.com/ukrainebz1-arch/clinic-dispatcher/pull/138

Related system map: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

---

## END OF REPORT
