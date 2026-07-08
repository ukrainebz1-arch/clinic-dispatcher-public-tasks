# ChatGPT ↔ Cursor Bridge v1.0 — Final Engineering OS (Public Summary)

> **For Custom GPT:** Read this document at conversation start to recover engineering context.
>
> **Public raw URL:** https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CHATGPT_BRIDGE_INFRASTRUCTURE_SUMMARY.md
>
> **Updated:** 2026-07-08T00:30:00Z | **Bridge version:** 1.0.0 | **Status:** frozen — ready for ChatGPT review

---

## What changed in v1.0

Bridge v1.0 is the **final engineering operating system** between ChatGPT and Cursor. After ChatGPT accepts this milestone, **bridge development stops** and all effort moves to clinic-dispatcher product work (Candidate Brain, Clinic Brain, Timeline, Email, WhatsApp, Calls, Funnel).

**New in v1.0:**

- Generic **`readRuntimeData(source, filters)`** — inspect live SQLite/runtime data without manual exports
- Extended **`getBridgeContext()`** — git recent commits, diff summary, tests, logs, services, open PRs
- Screen Control message kinds: `TASK_COMPLETE`, `TASK_STATUS`, `REVIEW_REQUEST`, `REVIEW_RESULT`, `CHANGES_REQUESTED`
- CLI: `bridge runtime <source>`
- E2E smoke: `tools/bridge_os_e2e.py` (dry-run transport verified)

---

## Quick start for ChatGPT

1. Call **`getBridgeContext`** — one request restores full engineering state.
2. Use **`readRuntimeData`** to inspect mailbox, WhatsApp, candidates, clinics, timeline, calls, funnel, cache.
3. Before starting work, call **`getActiveCursorTask`** — cancel or wait if running.
4. Assign tasks with **`startCursorTask`** / **`continueCursorTask`**; monitor with **`getCursorTaskLogs`**.
5. If GPT Actions fail, read this public URL for offline recovery.

---

## Connection

| Item | Value |
|------|-------|
| API base (GPT Actions) | `https://jobs.bewerbung-pflege.work/chatgpt-action` |
| Stable control API | `https://jobs.bewerbung-pflege.work/bridge` |
| OpenAPI v1.0.0 (no secrets) | `https://jobs.bewerbung-pflege.work/chatgpt-action/openapi.yaml` |
| Operator dashboard | `https://jobs.bewerbung-pflege.work/bridge/dashboard` |
| Auth | Bearer token (private — never in this doc) |
| Cursor session | `ce4726fa-060f-4a24-a8bd-7d123894b29c` |
| Read workspace | `/opt/clinic-dispatcher` |
| Write worktree | `/opt/clinic-dispatcher-bridge-poc` |
| Branch | `cursor/bridge-control-layer-90c5` |
| Draft PR | https://github.com/ukrainebz1-arch/clinic-dispatcher/pull/140 |

---

## GPT Actions — full surface

| operationId | Endpoint | Purpose |
|-------------|----------|---------|
| **`getBridgeContext`** | `GET /bridge/context` | **First call** — full engineering snapshot |
| **`getBridgeHealth`** | `GET /bridge/health` | Lightweight health probe |
| **`readRuntimeData`** | `POST /chatgpt-action/runtime/read` | Read mailbox, candidates, clinics, etc. |
| `readProjectDocument` | `POST /chatgpt-action/docs/read` | Read docs / runbooks / architecture |
| `getRepoTree` | `POST /chatgpt-action/repo/tree` | Repository tree |
| `searchRepository` | `POST /chatgpt-action/repo/search` | Search code |
| `readRepositoryFile` | `POST /chatgpt-action/repo/read` | Read file |
| `getGitStatus` | `GET /chatgpt-action/git/status` | Git status |
| `getGitDiff` | `POST /chatgpt-action/git/diff` | Git diff |
| `getActiveCursorTask` | `GET /chatgpt-action/cursor/active` | Monitor running task |
| `getCursorTask` | `GET /chatgpt-action/cursor/task/{id}` | Task snapshot |
| `getCursorTaskLogs` | `GET /chatgpt-action/cursor/logs/{id}` | Task logs |
| `startCursorTask` | `POST /chatgpt-action/cursor/execute` | Start implementation |
| `continueCursorTask` | `POST /chatgpt-action/cursor/followup` | Follow-up same session |
| `waitForCursorTask` | `POST /chatgpt-action/cursor/wait` | Block until task completes |
| `cancelCursorTask` | `POST /chatgpt-action/cursor/cancel/{id}` | Cancel one task |
| `cancelActiveCursorTask` | `POST /chatgpt-action/cursor/cancel-active` | Cancel active task |

Stable `/bridge/*` paths mirror all read and control endpoints.

---

## readRuntimeData — supported sources

| source | What it reads |
|--------|---------------|
| `mailbox` | `sales_brain.sqlite` mailbox cache |
| `whatsapp` | `phone_agent.sqlite` WhatsApp tasks |
| `candidate` | candidates table |
| `clinic` | companies table |
| `timeline` | activities table |
| `calls` | `call_bridge.sqlite` calls |
| `funnel` | funnel tables |
| `cache` | aggregate cache counts + mailbox preview |
| `sqlite` | allowlisted table query |
| `json` | JSON exports under `var/reports`, `var/logs` |
| `postgres` | returns `supported: false` (project uses SQLite) |

**Example request:**

```json
POST /bridge/runtime/read
{"source": "candidate", "filters": {"limit": 5, "workspace_key": "clinics_recruiting_de"}}
```

**Example response shape:**

```json
{
  "ok": true,
  "source": "candidate",
  "row_count": 5,
  "truncated": true,
  "rows": [{"candidate_id": 5, "full_name": "...", "pipeline": "...", "updated_at": "..."}]
}
```

---

## Example: GET /bridge/health

```json
{
  "status": "healthy",
  "version": "1.0.0",
  "uptime_sec": 22.5,
  "cursor_connected": true,
  "cursor_session_id": "ce4726fa-060f-4a24-a8bd-7d123894b29c",
  "active_task": false
}
```

---

## Example: GET /bridge/context (top-level keys)

`bridge` · `cursor` · `workspace` · `task` · `git` · `tests` · `logs` · `project` · `review`

Git section includes: `branch`, `changed_files`, `diff_stat`, `diff_summary`, `latest_commit`, `recent_commits`.

Project section includes: `background_services`, `open_prs`, `pending_reviews`, `last_tests`.

---

## Screen Control transport (Cursor → ChatGPT mobile)

Message kinds: `TASK_COMPLETE`, `TASK_STATUS`, `REVIEW_REQUEST`, `REVIEW_RESULT`, `CHANGES_REQUESTED`

- Module: `apps/phone_agent/chatgpt_protocol`
- Dry-run: `python3 -m apps.phone_agent.chatgpt_transport --dry-run --kind TASK_COMPLETE --from-cursor-json <file>`
- Live requires phone_agent on port 8791 + registered device
- E2E artifacts: `/opt/clinic-dispatcher/var/chatgpt_bridge/e2e_os/`

**Live execute not verified** — phone_agent offline at time of v1.0 delivery. Dry-run PASS.

---

## CLI (operator fallback)

```bash
cd /opt/clinic-dispatcher-bridge-poc
./tools/bridge health
./tools/bridge context
./tools/bridge active
./tools/bridge logs <request_id>
./tools/bridge cancel <request_id>
./tools/bridge result <request_id>
./tools/bridge runtime candidate --filters '{"limit":5}'
```

---

## Safety rules (always enforce)

- Do NOT expose secrets, tokens, passwords, or env vars in logs or public docs
- Read endpoints are read-only; no git modifications via context/runtime APIs
- Do NOT reset git or delete worktree
- Do NOT kill unrelated processes
- Cancellation stops only the selected Cursor task; preserves worktree and logs
- Do NOT merge PR #140 until ChatGPT accepts v1.0

---

## Test status

| Suite | Result |
|-------|--------|
| Bridge tests (`apps/chatgpt_bridge/tests/`) | **37 passed** |
| E2E smoke (`tools/bridge_os_e2e.py`) | **PASS** (context + runtime + dry-run transport) |
| Live `/bridge/health` on VPS | healthy **v1.0.0** |
| Live runtime reads | candidate ✓ clinic ✓ timeline ✓ |

---

## Known limitations

1. Live Screen Control execute requires phone_agent + device (dry-run works).
2. ChatGPT reply parsing not implemented (send-only v1).
3. Main repo git at `/opt/clinic-dispatcher` has corrupted HEAD; bridge uses write worktree for git context.
4. PDF docs not supported by `readProjectDocument`.
5. Re-import OpenAPI v1.0.0 in Custom GPT to register **`readRuntimeData`**.

---

## Related public docs

- Connection report: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CHATGPT_CURSOR_BRIDGE_CONNECTION_REPORT.md
- Claude lane: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CLAUDE_CURSOR_BRIDGE_CONNECTION_REPORT.md
- System map: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

---

## Ready for ChatGPT review

Bridge v1.0 delivers everything needed for ChatGPT to act as System Architect, Technical Reviewer, Engineering Coordinator, and Product Intelligence Layer — without manual coordination.

**Next step:** Call `getBridgeContext`, review snapshot, accept v1.0, then assign first **product** task (Candidate Brain, Clinic Brain, Timeline, etc.). Do not extend bridge infrastructure after acceptance.
