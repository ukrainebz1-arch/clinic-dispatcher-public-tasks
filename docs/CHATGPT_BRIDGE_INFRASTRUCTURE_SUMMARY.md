# ChatGPT ↔ Cursor Bridge — Infrastructure Summary (Public)

> **For Custom GPT:** Read this document at conversation start to recover engineering context.
>
> **Public raw URL:** https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CHATGPT_BRIDGE_INFRASTRUCTURE_SUMMARY.md
>
> **Updated:** 2026-07-08T00:15:00Z | **Bridge version:** 1.2.0

---

## Quick start for ChatGPT

1. Call **`getBridgeContext`** — single request restores full engineering state.
2. If tools fail, read this public URL for offline recovery.
3. Before starting work, call **`getActiveCursorTask`** — cancel or wait if running.
4. After assigning tasks, use **`getCursorTaskLogs`** and **`cancelCursorTask`** as needed.

---

## Connection

| Item | Value |
|------|-------|
| API base (GPT Actions) | `https://jobs.bewerbung-pflege.work/chatgpt-action` |
| Stable control API | `https://jobs.bewerbung-pflege.work/bridge` |
| OpenAPI (no secrets) | `https://jobs.bewerbung-pflege.work/chatgpt-action/openapi.yaml` |
| Operator dashboard | `https://jobs.bewerbung-pflege.work/bridge/dashboard` |
| Auth | Bearer token (private — never in this doc) |
| Cursor session | `ce4726fa-060f-4a24-a8bd-7d123894b29c` |
| Read workspace | `/opt/clinic-dispatcher` |
| Write worktree | `/opt/clinic-dispatcher-bridge-poc` |
| Branch | `cursor/bridge-control-layer-90c5` |

---

## GPT Actions — call order

| Priority | operationId | Endpoint | Purpose |
|----------|-------------|----------|---------|
| 1 | `getBridgeContext` | `GET /bridge/context` | **First call** — full engineering snapshot |
| 2 | `getBridgeHealth` | `GET /bridge/health` | Lightweight health probe |
| 3 | `getActiveCursorTask` | `GET /chatgpt-action/cursor/active` | Monitor running task |
| 4 | `getCursorTaskLogs` | `GET /chatgpt-action/cursor/logs/{id}` | Inspect logs |
| 5 | `cancelCursorTask` | `POST /chatgpt-action/cursor/cancel/{id}` | Cancel one task |
| 6 | `cancelActiveCursorTask` | `POST /chatgpt-action/cursor/cancel-active` | Cancel active task |
| 7 | `startCursorTask` | `POST /chatgpt-action/cursor/execute` | Start implementation |
| 8 | `continueCursorTask` | `POST /chatgpt-action/cursor/followup` | Follow-up same session |
| 9 | `getBridgeStatus` | `GET /chatgpt-action/status` | Legacy status (still works) |

Stable `/bridge/*` paths mirror task control when GPT Actions prefix is unavailable.

---

## Example: GET /bridge/health

```json
{
  "status": "healthy",
  "version": "1.2.0",
  "uptime": 21.6,
  "uptime_sec": 21.6,
  "cursor_connected": true,
  "cursor_session_id": "ce4726fa-060f-4a24-a8bd-7d123894b29c",
  "active_task": false
}
```

---

## Example: GET /bridge/context (structure)

```json
{
  "bridge": {
    "status": "healthy",
    "version": "1.2.0",
    "write_worktree": "/opt/clinic-dispatcher-bridge-poc",
    "task_running": false
  },
  "cursor": {
    "session_id": "ce4726fa-060f-4a24-a8bd-7d123894b29c",
    "connected": true
  },
  "task": {
    "request_id": null,
    "status": "idle",
    "current_step": null,
    "progress": null,
    "recent_logs": []
  },
  "git": {
    "branch": "cursor/bridge-control-layer-90c5",
    "changed_files": ["..."],
    "diff_stat": "...",
    "latest_commit": "..."
  },
  "tests": {
    "last_run": "...",
    "status": "completed",
    "summary": "..."
  },
  "logs": {
    "request_id": "...",
    "tail": [{"stream": "control", "line": "..."}]
  },
  "project": {
    "pending_reviews": [],
    "open_prs": [],
    "last_tests": "...",
    "background_services": {
      "gmail_sync": "sales-brain-manager=active",
      "whatsapp_sync": "via phone_agent queue",
      "phone_agent": "port 8791",
      "screen_control": "phone_agent + cursor_handoff",
      "bridge": "systemd=active; http=ok"
    }
  }
}
```

---

## Active task monitor

`getActiveCursorTask` returns:

- `request_id`, `status`, `started_at`, `elapsed_sec`
- `task_summary`, `current_step`, `progress`
- `recent_logs` (redacted, no secrets)

Cancel preserves worktree, git changes, and partial logs.

---

## Screen Control transport (Cursor → ChatGPT mobile)

Structured message kinds: `TASK_COMPLETE`, `TASK_STATUS`, `REVIEW_REQUEST`

- Module: `apps/phone_agent/chatgpt_protocol`
- Dry-run CLI: `python3 -m apps.phone_agent.chatgpt_transport --dry-run --message "..."`
- Live requires phone_agent on port 8791 + device registration
- Runbook: `apps/phone_agent/docs/CHATGPT_SCREEN_CONTROL_RUNBOOK.md`

On Cursor task complete, bridge saves a dry-run transport plan automatically.

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
```

---

## Safety rules (always enforce)

- Do NOT expose secrets in logs or public docs
- Do NOT reset git or delete worktree
- Do NOT kill unrelated processes
- Do NOT commit/push unless explicitly requested
- Cancellation stops only the selected Cursor task
- Read endpoints are read-only; no git modifications via context API

---

## Test status

| Suite | Result |
|-------|--------|
| Bridge tests (`apps/chatgpt_bridge/tests/`) | 25 passed |
| Screen Control transport tests | 13 passed |
| E2E dry-run smoke (`tools/bridge_e2e_smoke.py`) | PASS |
| Live `/bridge/health` on VPS | healthy v1.2.0 |

---

## Known limitations

1. Live Screen Control send requires phone_agent service + device (dry-run works today).
2. ChatGPT reply parsing not implemented (send-only v1).
3. `running_async` orphan agents may need manual cleanup after long timeouts.
4. Re-import OpenAPI in Custom GPT to register `getBridgeHealth` and `getBridgeContext`.

---

## Related public docs

- Connection report: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CHATGPT_CURSOR_BRIDGE_CONNECTION_REPORT.md
- Claude lane: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/CLAUDE_CURSOR_BRIDGE_CONNECTION_REPORT.md
- System map: https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

---

## Ready for ChatGPT review

Infrastructure milestone complete. ChatGPT can:

- Recover engineering state with **`getBridgeContext`** (one call)
- Monitor, log, cancel, and continue Cursor tasks
- Receive structured reports via Screen Control (dry-run verified)
- Issue next implementation tasks without manual coordination

**Next step:** Call `getBridgeContext`, review snapshot, approve infrastructure or assign first product task.
