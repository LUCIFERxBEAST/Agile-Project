# 04. Current Status & Future Engineering Roadmap

This document outlines the delivered production architecture across all project iterations and defines the engineering roadmap for future enhancements.

---

## 🚦 System Delivery Status Summary

All core deliverables and previously scoped extensions (Future Scopes 1 through 5) have been fully developed, integrated, verified, and hardened:

| Feature Area | Original Scope | Current Delivery Status | Implementation Details |
| :--- | :--- | :--- | :--- |
| **Core End-to-End Pipeline** | Review 1 Baseline | **Delivered** | C++17 agent parsing `/proc`, API Gateway, AWS Lambda (Python 3.12), Amazon RDS PostgreSQL, and Flutter graph UI. |
| **Future Scope #1: Offline Disk Queue & Auto-Retry** | Network fault tolerance | **Delivered** | Local disk caching in `offline_queue.jsonl` upon network failure; automatic sequential queue flush upon network restoration. |
| **Future Scope #2: Process-Level Diagnostics** | Spike root-cause capture | **Delivered** | Adaptive diagnostic snapshot triggered when CPU utilization is `>= 85.0%` for `>= 2 consecutive cycles` (10s sustained load); captures top 3 processes (`pid`, `cmd`, `cpu`). |
| **Future Scope #3: Remote Incident Orchestration** | Remote remediation | **Delivered** | Agentless process termination via AWS Systems Manager (SSM) Run Command (`POST /Prod/ExecuteCommand`) with full audit logging in `kill_commands`. |
| **Future Scope #4: Security Hardening** | Ingestion & UI security | **Delivered** | Fail-closed `x-api-key` header verification in AWS Lambda; API Gateway Usage Plans; hardened non-root systemd service with `mode 600` environment file. |
| **Future Scope #5: Multi-Server Monitoring** | Fleet observability | **Delivered** | Server identity discovery (`GET /Prod/GetServers`); AppBar dropdown filter and parameterized queries (`?server_id=<id>`) in Flutter portal. |

---

## 🛡️ Delivered Architectural Guardrails

For complete details on the remote incident remediation pipeline and 4-layer defense architecture, see [05. Guardrails & Remote Remediation](./05_GUARDRAILS_AND_REMEDIATION.md):
1. **OS Process Blocklist**: Hardcoded rejection of core system binaries (`systemd`, `init`, `sshd`, `dbus`, `dockerd`, `cron`, `telemetry_agent`, and kernel threads `[...]`), returning HTTP 403.
2. **2-Minute Spike Telemetry Verification**: Strict database check ensuring requested PID was observed in a recent diagnostic snapshot for that specific host (`created_at >= NOW() - INTERVAL '2 minutes'` with comparison `>=`).
3. **Cryptographic SHA-256 Confirmation Token**: 8-character token (`sha256('$targetInstanceId:$pid:$cmd')[:8]`) generated and verified in the Flutter UI before unlocking the Terminate button.
4. **Comprehensive Audit Trail**: Every execution attempt tracked in PostgreSQL `kill_commands` transitioning from `authorized` to `dispatched` or `failed_dispatch`.

---

## 🔮 Future Scope & Extension Roadmap

With the primary monitoring and remediation systems fully operational, remaining long-term enhancements include:

### 1. Machine Learning Anomaly Detection
- **Objective**: Identify subtle resource degradation, memory leaks, and anomalous spikes before hard thresholds are crossed.
- **Approach**:
  - Deploy lightweight unsupervised models (e.g., Isolation Forests or One-Class SVM) in AWS Lambda or a containerized worker.
  - Evaluate rolling metric trends (Z-score analysis on CPU derivative and RAM consumption rate).
  - Surface proactive anomaly warnings on the Flutter dashboard before systems experience service degradation.

### 2. Automated Auto-Kill Remediation Policies
- **Objective**: Enable zero-touch autonomous mitigation of known unapproved workloads.
- **Approach**:
  - Define declarative auto-remediation policies (e.g., automatically dispatch `SIGKILL` if an unapproved binary like a cryptocurrency miner or rogue test runner sustains `>= 95%` CPU for > 60 seconds).
  - Maintain rigorous safety exemptions for critical production databases and system services.
  - Broadcast automated remediation events to administrative channels (Slack/PagerDuty via Amazon SNS).

### 3. AWS Fleet Auto-Scaling Integration
- **Objective**: Bridge host-level telemetry with cloud orchestration.
- **Approach**:
  - Export real-time aggregated agent telemetry to custom Amazon CloudWatch Metrics.
  - Configure CloudWatch Alarms to dynamically adjust AWS Auto Scaling Group capacity (scale-out during high demand, scale-in during idle periods).

---

## 🎤 Presentation & Viva Defense Talking Points

1. **Native C++ Performance vs Scripting Agents**:
   - Reading `/proc/stat` and `/proc/meminfo` natively eliminates the overhead of subprocessing shell commands (`top`, `ps`). The binary maintains a tiny memory footprint (< 10 MB RAM) and zero baseline CPU load.
2. **Network Resilience**:
   - The disk-backed offline queue (`offline_queue.jsonl`) guarantees that intermittent network drops do not result in telemetry blind spots or data loss.
3. **Defense-in-Depth Remote Remediation**:
   - Leveraging AWS SSM Run Command provides agentless remediation with zero open inbound ports (port 22 closed), enforced by strict multi-layer guardrails and database audit logging.
