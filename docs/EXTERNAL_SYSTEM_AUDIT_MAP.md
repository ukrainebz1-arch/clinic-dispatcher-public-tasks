# clinic-dispatcher — External System Audit Map

> **Purpose:** Give this entire file to an external AI model (ChatGPT, Claude, etc.) so it can audit and understand the full system without server access.
>
> **Copy everything below the line**, or download this file from the repo.

---

## PROMPT — paste from here

You are auditing a healthcare staffing platform called **clinic-dispatcher**. The business places nurses/care workers (candidates) into German clinics (B2B customers). The platform has two brains that share one database:

- **Sales Brain (B2B)** — find clinics, enrich contacts, outbound email, sign contracts
- **Candidate Brain (B2C)** — Facebook ads → applications → WhatsApp/email/phone follow-up → placement

Your job: read the linked docs and code paths below, build a mental model of the whole system, and produce a structured audit (architecture diagram, data flows, gaps, risks, and what is built vs planned).

You do NOT have server access. Do not assume you can curl production APIs except the public funnel URL listed below. Treat private repo paths as readable only if the user grants GitHub access or pastes file contents.

---

### 1. START HERE — business + system map

Read in this order:

1. Architecture vision (Sales Brain + Candidate Brain + placement ops):
   https://github.com/ukrainebz1-arch/clinic-dispatcher/blob/main/data/imports/candidate_hub/2026-06-20/ARCHITECTURE.md

2. Production services (what runs where, public vs internal):
   https://github.com/ukrainebz1-arch/clinic-dispatcher/blob/main/ops/README-production-urls.md

3. Project entry point (legacy Telegram/Tasker pipeline — still important):
   https://github.com/ukrainebz1-arch/clinic-dispatcher/blob/main/PROJECT_STATE.md

4. Critical “do not break” contract (Telegram markers):
   https://github.com/ukrainebz1-arch/clinic-dispatcher/blob/main/DO_NOT_BREAK.md

5. This audit map (you are reading it):
   https://github.com/ukrainebz1-arch/clinic-dispatcher/blob/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

---

### 2. SUBSYSTEM MAP — where each product part lives

#### A. Facebook ads → Recruitment funnel (Candidate Brain entry)

**What it does:** Meta/Facebook ads drive traffic to a self-hosted landing page. Applicants submit forms; leads are stored and notified.

| What | Where |
|------|--------|
| **Live public site** | https://jobs.bewerbung-pflege.work/f/top5_kliniken_de (short: https://jobs.bewerbung-pflege.work/funnel) |
| **Health check** | https://jobs.bewerbung-pflege.work/api/funnel/health |
| **Backend code** | https://github.com/ukrainebz1-arch/clinic-dispatcher/tree/main/apps/recruitment_funnel |
| **Flask routes** | `apps/recruitment_funnel/web.py` |
| **DB schema** | `apps/recruitment_funnel/schema.sql` |
| **Nginx config** | `ops/nginx/jobs-bewerbung-pflege.conf` |
| **Systemd service** | `ops/systemd/clinic-recruitment-funnel.service` |
| **Start script** | `tools/run_recruitment_funnel_server.py` |
| **Meta ads launcher** | `tools/launch_meta_recruitment_ads.py` |

---

#### B. Sales Brain — clinic outbound email + manager UI (B2B)

**What it does:** Syncs Gmail, classifies clinic emails, tracks sales pipeline stages, AI drafts replies, manager approves/sends from a web UI.

| What | Where |
|------|--------|
| **Manager UI (internal only, not public HTTPS)** | http://37.27.182.1:8793/manager |
| **Web UI + API** | `apps/sales_brain/agent/web.py` |
| **AI chat / draft engine** | `apps/sales_brain/agent/chat_engine.py`, `draft_generator.py`, `inbox_tools.py` |
| **Email send** | `apps/sales_brain/agent/email_send.py` |
| **Thread timeline analysis** | `apps/sales_brain/agent/thread_analysis.py` |
| **Gmail sync + mailbox** | `apps/sales_brain/mailbox/history_sync.py`, `clinic_correspondence.py` |
| **Sales pipeline stages** | `apps/sales_brain/mailbox/sales_pipeline.py` + `sales_pipeline_schema.sql` |
| **Email classifier** | `apps/sales_brain/mailbox/email_classifier.py` |
| **Clinic contact registry** | `apps/sales_brain/mailbox/clinic_contact_registry.py` |
| **Contract register import** | `apps/sales_brain/mailbox/contract_register_import.py` |
| **Snov.io campaign export** | `apps/sales_brain/integrations/snov/campaign_export.py` |
| **LLM enrichment loop** | `apps/sales_brain/enrichment/llm_orchestrator/` |
| **Shared DB layer** | `apps/sales_brain/db.py`, `repository.py`, `var/sales_brain.sqlite` (runtime, not in git) |
| **Start script** | `tools/run_sales_brain_manager.py` |
| **Systemd** | `ops/systemd/clinic-sales-brain-manager.service` |

---

#### C. Candidate Brain — candidates, cases, communication timeline (B2C data model)

**What it does:** Stores nurse applicants (from Zoho/Facebook), links WhatsApp + email history, tracks placement cases.

| What | Where |
|------|--------|
| **Candidate schema** | `apps/sales_brain/candidate_brain_schema.sql` |
| **Candidate journey** | `apps/sales_brain/mailbox/candidate_journey.py` |
| **Case chain events** | `apps/sales_brain/mailbox/candidate_case_chain.py` |
| **Import/analysis plan** | `data/imports/candidate_hub/2026-06-20/UNIFIED_IMPORT_PLAN.md` |
| **Cross-channel analysis tool** | `tools/analyze_candidate_communication_hub.py` |
| **Call Bridge ↔ candidates** | `apps/call_bridge/candidate_brain.py` |

Two candidate segments (documented in ARCHITECTURE.md):

- `ukrainian_anerkennung` — Ukrainian nurses, recognition path
- `german_b2_nurse_ad` — German B2+ nurse ads (Top 5 Kliniken funnel)

---

#### D. WhatsApp — via Phone Agent (Android automation)

**What it does:** An Android phone runs an accessibility agent. Server sends vision-based tasks (open WhatsApp, send message, create contact). No official WhatsApp Business API.

| What | Where |
|------|--------|
| **Server API** | `apps/phone_agent/api.py` |
| **Vision planner (OpenAI)** | `apps/phone_agent/planner.py`, `vision.py` |
| **Task lanes (whatsapp, telegram, parking, etc.)** | `apps/phone_agent/task_lanes.py` |
| **App package hints** | `apps/phone_agent/app_hints.py` (`com.whatsapp`) |
| **Android app** | `mobile/phone_agent/` |
| **README / setup** | `mobile/phone_agent/README.md` |
| **Start script** | `tools/run_phone_agent_server.py` (port 8791) |
| **Example WhatsApp goal** | `var/queue_whatsapp_test.py` — goal format: `whatsapp_send: phone=+49... name=...` |

---

#### E. Phone calls — Call Bridge (AI voice over GSM)

**What it does:** Outbound/inbound AI phone calls to candidates. Two hardware paths:

1. **Dinstar GSM gateway** (production) — Asterisk + SIP + WireGuard + OpenAI Realtime
2. **Rooted Android call_bridge app** (alternate path)

| What | Where |
|------|--------|
| **Call Bridge API** | `apps/call_bridge/api.py` (port 8792) |
| **OpenAI Realtime voice** | `apps/call_bridge/realtime_openai.py` |
| **Call scheduler / queue** | `apps/call_bridge/scheduler.py` |
| **Dinstar + Asterisk setup doc** | `docs/DINSTAR_CALL_BRIDGE.md` |
| **Root setup doc** | `docs/CALL_BRIDGE_ROOT_SETUP.md` |
| **Feasibility notes** | `docs/CALL_BRIDGE_FEASIBILITY.md` |
| **Android GSM bridge app** | `mobile/call_bridge/README.md` |
| **Native call panel apps (Mac + Android)** | `mobile/NATIVE_CALL_APPS.md` |
| **Start scripts** | `tools/run_call_bridge_server.py`, `run_dinstar_call_worker.py`, `run_audiosocket_bridge.py`, `run_call_scheduler.py` |

Flow: Candidate Brain → Call Bridge API → Asterisk/Dinstar or Android → GSM → candidate ↔ OpenAI Realtime AI.

---

#### F. B2B data pipeline — clinic discovery & outreach (Stages 01–06)

**What it does:** CSV pipeline: discover clinic decision-makers → enrich email/LinkedIn/phone → generate outreach messages → export to Snov/campaign tools. Originally executed via Telegram + Tasker + ChatGPT on a phone.

| What | Where |
|------|--------|
| **Pipeline architecture** | `docs/PIPELINE_ARCHITECTURE_V2.md` |
| **Stage contracts (CSV schemas)** | `docs/STAGE_CONTRACTS_V2.md` |
| **Stage 04 phone enrichment** | `docs/STAGE_04_PHONE_ENRICHMENT_CONTRACT.md` |
| **Outreach master spec** | `docs/OUTREACH_INPUT_MASTER_SPEC.md` |
| **Company packs spec** | `docs/COMPANY_PACKS_SPEC.md` |
| **Stage 06 export** | `docs/STAGE06_PARTIAL_EXPORT_CONTRACT.md` |
| **Schema configs** | `configs/schemas/` |
| **Stage runners** | `tools/run_real_stage_chain_strict_v2.py`, `run_mvp_stage01_stage06.py`, `run_stage05_outreach_generation_live.py` |

Pipeline layers:

```
Pre-stage sourcing → Stage 01 people_master.csv
→ Stage 02 email → Stage 03 LinkedIn → Stage 04 phone
→ outreach_input_master.csv → Stage 05 messages → Stage 06 SnowReady export
```

---

#### G. Telegram / Tasker / ChatGPT dispatcher (original transport layer)

**What it does:** Long AI tasks are published as public GitHub TXT files. Telegram sends a short message with URL to an Android phone. Tasker opens ChatGPT, executes the task, returns results via HTTP receiver.

| What | Where |
|------|--------|
| **Public task hosting policy** | `docs/PUBLIC_TASK_HOSTING_POLICY.md` |
| **Public tasks repo (readable without auth)** | https://github.com/ukrainebz1-arch/clinic-dispatcher-public-tasks |
| **Raw task URL pattern** | `https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/tasks/<run_id>/tasks/<task_id>.txt` |
| **Tasker router contract** | `docs/TASKER_ROUTER_CONTRACT.md` |
| **Supervisor engine (orchestrates runs)** | `docs/SUPERVISOR_ENGINE_USAGE.md`, `tools/supervisor_engine.py` |
| **Full cycle runner** | `tools/run_full_cycle_29_public.py` |
| **Publish tasks to GitHub** | `tools/publish_public_tasks_via_gh_api.py` |

Critical Telegram markers (must not be removed):

- `MODE:SEND_CHUNK` → sends task to ChatGPT
- `MODE:COLLECT_RESULT` → collects result back

---

### 3. REPOSITORY STRUCTURE (private main repo)

Main repo (private — needs access or pasted files):
https://github.com/ukrainebz1-arch/clinic-dispatcher

```
apps/
  sales_brain/        ← B2B email, manager UI, enrichment, candidate tables
  recruitment_funnel/ ← Facebook landing pages + lead capture
  phone_agent/        ← WhatsApp/Telegram Android automation server
  call_bridge/        ← AI phone calls (GSM)
mobile/
  phone_agent/        ← Android accessibility agent APK
  call_bridge/        ← Rooted Android GSM audio bridge
  lead_call_panel_*   ← Native apps to trigger calls
docs/                 ← Architecture contracts + setup guides
ops/                  ← Nginx, systemd, production URLs
tools/                ← All server start scripts + pipeline runners
data/imports/         ← Import plans and analysis (some paths reference private data)
var/                  ← Runtime SQLite DBs and logs (NOT in git)
data/private/         ← Secrets, WhatsApp archives, API keys (NOT in git)
```

Public companion repo (task TXT files only):
https://github.com/ukrainebz1-arch/clinic-dispatcher-public-tasks

---

### 4. PRODUCTION URL SUMMARY

| Service | URL / port | Public? |
|---------|------------|---------|
| Recruitment funnel | https://jobs.bewerbung-pflege.work | Yes |
| Sales Brain manager | http://37.27.182.1:8793/manager | Internal IP only |
| Phone Agent server | port 8791 | Internal |
| Call Bridge API | port 8792 | Internal |
| AudioSocket bridge | port 9092 | Internal |

The funnel domain is intentionally isolated from the manager so manager outages do not break Facebook ads.

---

### 5. HIGH-LEVEL SYSTEM DIAGRAM

```
┌─────────────────────────────────────┐     ┌─────────────────────────────────────┐
│         SALES BRAIN (B2B)           │     │       CANDIDATE BRAIN (B2C)         │
│  Clinics as customers               │     │  Nurses/care workers as applicants  │
├─────────────────────────────────────┤     ├─────────────────────────────────────┤
│ • Stages 01–06 outreach pipeline    │     │ • Facebook ads → recruitment funnel │
│ • Gmail inbox + manager UI          │     │ • Zoho / form applications          │
│ • Snov campaign export              │     │ • candidates + case events          │
│ • companies + people + lead_records │     │ • WhatsApp + email + phone timeline │
└──────────────┬──────────────────────┘     └──────────────┬──────────────────────┘
               │                                            │
               │         CONTRACT SIGNED                    │
               └──────────────────┬───────────────────────────┘
                                  ▼
                    ┌─────────────────────────────┐
                    │   PLACEMENT OPERATIONS       │
                    │ • Match candidate → clinic   │
                    │ • Interview coordination     │
                    │ • WhatsApp + email + calls   │
                    └─────────────────────────────┘

Communication channels:
  WhatsApp  → Phone Agent (Android vision automation, port 8791)
  Phone     → Call Bridge (GSM/Dinstar + OpenAI Realtime, port 8792)
  Email     → Sales Brain Gmail sync + manager UI (port 8793)
  Bulk AI   → Telegram/Tasker/ChatGPT + public GitHub task TXT files
```

Shared database at runtime: `var/sales_brain.sqlite` (not in git).

---

### 6. WHAT YOU CANNOT SEE (do not invent)

- Live SQLite databases (`var/sales_brain.sqlite`, funnel DB, call_bridge DB)
- Secrets (`data/private/`, API keys, tokens)
- WhatsApp chat archives (`data/private/imports/whatsapp/`)
- Zoho/Gmail live credentials
- Production VPS shell access

If a path is missing, say so — do not hallucinate implementation details.

---

### 7. YOUR AUDIT OUTPUT — produce all of these

1. **One-page system diagram** — all subsystems and how data flows between them
2. **Subsystem status table** — Built / partial / planned for each area above
3. **Integration map** — Facebook, WhatsApp, phone, email, Telegram/Tasker, Snov, Zoho
4. **Shared data model** — which tables/files connect Sales Brain ↔ Candidate Brain
5. **Production topology** — what runs on VPS, what runs on Android/Mac, what is public
6. **Gaps & risks** — missing pieces, single points of failure, security concerns
7. **Recommended next steps** — prioritized, with references to specific files

Be specific. Cite file paths and doc names. Distinguish what is documented vs what you infer.

---

## END OF PROMPT

---

## How to use this file

| Method | Action |
|--------|--------|
| **Copy/paste** | Select everything under "PROMPT — paste from here" through "END OF PROMPT" |
| **Download from repo** | Save `docs/EXTERNAL_SYSTEM_AUDIT_MAP.md` from GitHub |
| **Public raw URL** (after push to public repo) | See below |

### Public links (no GitHub login required)

After this file is published to the public tasks repo:

- **Raw text (best for pasting into AI):**
  https://raw.githubusercontent.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

- **GitHub view:**
  https://github.com/ukrainebz1-arch/clinic-dispatcher-public-tasks/blob/main/docs/EXTERNAL_SYSTEM_AUDIT_MAP.md

- **Live funnel (only public production UI):**
  https://jobs.bewerbung-pflege.work/f/top5_kliniken_de
