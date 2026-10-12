# Presentation Deck Audit & Change Checklist (`PPT_CHANGES.md`)

This document is a comprehensive audit and correction checklist for the slide deck (*"Cloud-Native Linux Telemetry & Remote Diagnostics System"*). Every recommendation maps a specific slide number to current text, active source code reality, verified line references from [`docs/VERIFIED_FACTS.md`](file:///home/beast/Documents/Agile%20Project/docs/VERIFIED_FACTS.md), and exact replacement text.

---

## 1. Discrepancy & Slide Correction Matrix

| Slide # | Current Slide Text / Topic | Active Code Reality (`file:line`) | Recommended Replacement Slide Text | Rationale & Impact |
| :---: | :--- | :--- | :--- | :--- |
| **Slide 5** | Database Version & Stack Overview: States "PostgreSQL 16" / "PostgreSQL 15+" generically without specifying environment differences. | Docker local is `postgres:15` ([`docker-compose.yml:3`](file:///home/beast/Documents/Agile%20Project/docker-compose.yml#L3)). AWS deployed RDS is PostgreSQL 16.3 on `db.t4g.micro` ([`FINAL_PRESENTATION_DETAILS.txt:81-82`](file:///home/beast/Documents/Agile%20Project/FINAL_PRESENTATION_DETAILS.txt#L81-L82)). RDS is not in `template.yaml`. | *"Storage Architecture: Amazon RDS PostgreSQL 16.3 (`db.t4g.micro`, ap-southeast-2) for production time-series persistence; containerized PostgreSQL 15 for local unit and integration testing."* | Aligns slide with real production vs local test environments. |
| **Slide 7** | Payload Size & Sampling: Claims *"~180-byte lightweight payload"* and mentions *"80% / 2-cycle trigger"*. | Measured compact JSON payload with realistic EC2 instance ID (`i-0abcdef1234567890`) is exactly **136 bytes** ([`docs/01_ARCHITECTURE_AND_SYSTEM_DESIGN.md:55`](file:///home/beast/Documents/Agile%20Project/docs/01_ARCHITECTURE_AND_SYSTEM_DESIGN.md#L55)). Sampling interval is **5 seconds** ([`utility.cpp:292`](file:///home/beast/Documents/Agile%20Project/backend/src/utility.cpp#L292)). Spike threshold is **`>= 85.0%` for `>= 2 consecutive cycles`** ([`utility.cpp:310`](file:///home/beast/Documents/Agile%20Project/backend/src/utility.cpp#L310)). | *"Ultra-low network footprint: Compact 136-byte telemetry payload sampled every 5s; triggers adaptive diagnostic process capture only during sustained spikes (at or above 85.0% CPU across 2 or more consecutive cycles / 10s minimum)."* | Demonstrates precise empirical benchmarking and fixes inaccurate threshold numbers. |
| **Slide 8** | Serverless Routes & Auth: Incomplete route list (shows 2 or 3 routes) and vague API key claims. | Final system implements **4 routes** under `/Prod`: `POST /IngestMetrics`, `GET /GetMetrics`, `GET /GetServers`, `POST /ExecuteCommand` ([`template.yaml:110-145`](file:///home/beast/Documents/Agile%20Project/backend/aws/template.yaml#L110-L145), [`lambda_function.py:209-225`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L209-L225)). Lambda enforces fail-closed auth: if `EXPECTED_API_KEY` is unset, returns HTTP 500 (`SERVER_MISCONFIGURED`); if key missing/mismatch, returns HTTP 403 (`INVALID_API_KEY`) ([`lambda_function.py:182-206`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L182-L206)). | *"Amazon API Gateway (`/Prod` Stage) routes: `POST /IngestMetrics`, `GET /GetMetrics`, `GET /GetServers`, `POST /ExecuteCommand`. Enforces fail-closed API Key authentication (Lambda rejects with HTTP 500 if server key is unconfigured; rejects client requests with HTTP 403 on missing or invalid `x-api-key` header)."* | Clarifies the full 4-route surface and accurately explains the fail-closed security guarantee. |
| **Slide 9** | Spike Verification Window: Mentions `> 80%` CPU threshold and generic recent check. | Spike threshold is **`>= 85.0%`** ([`utility.cpp:310`](file:///home/beast/Documents/Agile%20Project/backend/src/utility.cpp#L310)). Guardrail query strictly evaluates: `WHERE server_id = %s AND created_at >= NOW() - INTERVAL '2 minutes' AND top_processes IS NOT NULL` ([`lambda_function.py:143-148`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L143-L148)). | *"Multi-Tier Guardrail: Process termination strictly rejected unless the target PID was actively captured in a high-CPU diagnostic snapshot (CPU at or above 85.0%) for that exact server within the last 2 minutes (`created_at >= NOW() - INTERVAL '2 minutes'`)."* | Replaces loose wording with verified database SQL logic. |
| **Slide 9** | Cryptographic Token: Claims SHA-256 token is verified by AWS Lambda / prevents replay attacks. | Token `sha256('$targetInstanceId:$pid:$cmd')[:8]` is generated and verified **strictly within the Flutter client UI** ([`main.dart:368-435`](file:///home/beast/Documents/Agile%20Project/flutter%20mobile%20frontend/lib/main.dart#L368-L435)). It is **not** transmitted to `/ExecuteCommand` and **not** verified by Lambda ([`lambda_function.py:270-300`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L270-L300)). Code does **not** prevent token reuse or enforce token expiration on the backend. | *"Human-in-the-Loop Confirmation: Operator UI computes an 8-character cryptographic token (`sha256(server_id:pid:cmd)[:8]`) requiring manual operator verification before enabling the termination trigger. (Architecture finding: Client-side gate; backend enforcement proposed for enterprise hardening)."* | Eliminates misleading claims regarding backend token verification. |
| **Slide 11** | Live EC2 Deployment Screenshot: Slide screenshot displays EC2 instance state check as *"Initializing"*. | A screenshot showing "Initializing" implies an unvalidated instance state during viva presentation. | **Recapture Required**: Capture a fresh AWS EC2 Console screenshot showing the instance in steady state with **"2/2 checks passed"** and green status indicators. | Replaces in-progress screenshot with conclusive deployment proof. |
| **Slide 14** | Remediation Audit Trail Evidence: Figure 7 currently displays the AWS Systems Manager (SSM) execution history only. | SSM execution history proves shell dispatch, but does not display the application-level audit state transitions in PostgreSQL `kill_commands`. | **Recapture Required**: Add or split screenshot with `psql` terminal query output: `SELECT id, instance_id, pid, process_name, requested_signal, status, reason FROM kill_commands ORDER BY created_at DESC LIMIT 5;` showing `authorized -> dispatched`. | Provides concrete empirical proof of the database audit trail. |

---

## 2. Unimplemented or Stretched Slide Claims to Clarify

1. **Automated Auto-Kill Policies**:
   - *Current Slide Suggestion*: Slides sometimes imply autonomous background process killing.
   - *Code Reality*: Process killing is **strictly human-initiated** from the Flutter mobile app through `confirmAndKillProcess` and dispatched via `POST /ExecuteCommand`. There is no automated daemon or cron job auto-killing processes.
   - *Slide Fix*: Clarify that autonomous auto-killing is part of the **Future Scope Roadmap** (to prevent accidental service disruption).
2. **Sampling Frequency Discrepancy**:
   - *Current Slide Text*: Slides 4 & 5 occasionally cite "parsing `/proc` every 3s".
   - *Code Reality*: Agent sleep duration is `std::this_thread::sleep_for(std::chrono::seconds(5))` ([`utility.cpp:292`](file:///home/beast/Documents/Agile%20Project/backend/src/utility.cpp#L292)). The Flutter mobile client polls every 3s ([`main.dart:603`](file:///home/beast/Documents/Agile%20Project/flutter%20mobile%20frontend/lib/main.dart#L603)).
   - *Slide Fix*: Explicitly distinguish between **C++ Agent 5-second sampling interval** and **Flutter Mobile 3-second UI refresh polling rate**.
3. **Blocklist HTTP Status Code**:
   - *Current Slide Text*: Cites HTTP 400 for process blocklist rejection.
   - *Code Reality*: `lambda_function.py:362` returns HTTP **403 Forbidden** for blocklist rejections (HTTP 400 is only returned on malformed JSON body).
   - *Slide Fix*: Update slide text to cite **HTTP 403 Forbidden** (or note "HTTP 403 Forbidden [400 in early API spec]").

---

## 3. Recommended New Slides to Add

### New Slide A: Agile Sprint Progression (Review 1 Baseline to Final Production)
* **Visual**: Milestone comparison table illustrating iterative development across sprint cycles:
  - **Review 1 Baseline**: Basic `/proc` parsing prototype, foreground execution, Azure function prototype, basic dual-chart visualization.
  - **Sprint 2 (Cloud Migration & Resilience)**: AWS migration (Lambda, SAM, RDS), offline local disk queue (`offline_queue.jsonl`), auto-retry flush engine.
  - **Sprint 3 (Deep Diagnostics & Remediation)**: Kernel process scanning (`/proc/[pid]/stat`), adaptive spike burst capture (`top_processes JSONB`), agentless remote remediation via AWS SSM Run Command.
  - **Sprint 4 (Security Hardening & Polish)**: Multi-layer guardrails (blocklist, 2-min verification, SHA-256 token), fail-closed `x-api-key` auth, non-root systemd service with `mode 600` environment file, and multi-server dropdown.

### New Slide B: Automated DevOps CI Pipeline (GitHub Actions)
* **Visual**: Diagram showing `.github/workflows/ci.yml` pipeline stages:
  1. **Build Dependencies**: Installs `g++`, `libcurl4-openssl-dev`, `nlohmann-json3-dev`.
  2. **Compile Agent**: Builds C++17 telemetry agent binary with `-O2` optimizations.
  3. **Unit Testing**: Compiles and executes `test_metrics.cpp` (verifying CPU delta, process CPU, and RAM calculations with zero failures).
  4. **IaC Validation**: Executes `sam validate --template-file backend/aws/template.yaml --region ap-southeast-2` ensuring CloudFormation syntax and resource dependencies are 100% valid.
