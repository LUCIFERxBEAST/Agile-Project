# Cloud-Native Linux Telemetry & Remote Diagnostics System

An enterprise-grade, low-overhead Linux infrastructure observability and agentless remote incident remediation platform built with **C++17**, **Amazon Web Services (AWS)** serverless infrastructure, and a **Flutter (Dart)** cross-platform operator portal.

---

## 📑 Documentation Hub

Comprehensive documentation is available in the [`docs/`](./docs/README.md) directory:

| Document | Description |
| :--- | :--- |
| **[01. Architecture & System Design](./docs/01_ARCHITECTURE_AND_SYSTEM_DESIGN.md)** | Full technical breakdown of all layers: C++ Agent, AWS Lambda, API Gateway, Amazon RDS PostgreSQL, and Flutter Mobile Dashboard. |
| **[02. Setup & Deployment Guide](./docs/02_SETUP_AND_DEPLOYMENT_GUIDE.md)** | Step-by-step instructions to provision Amazon RDS, deploy AWS Lambda, configure systemd daemon, and launch Flutter app. |
| **[03. Testing & Verification](./docs/03_TESTING_AND_VERIFICATION.md)** | Complete testing protocols, unit test suites, synthetic load tests (`stress-ng`), and local sandbox verification. |
| **[04. Roadmap & Status](./docs/04_NEXT_STEPS_AND_ROADMAP.md)** | Delivery matrix across all review milestones and future enhancements (ML anomaly detection, auto-kill policies). |
| **[05. Guardrails & Remote Remediation](./docs/05_GUARDRAILS_AND_REMEDIATION.md)** | Deep dive into the 4-layer kill guardrail (blocklist, recent telemetry verification, SHA-256 tokens, audit trail) and AWS SSM. |
| **[Verified Facts & Line References](./docs/VERIFIED_FACTS.md)** | Single source of truth with verbatim line numbers, parameter names, and schema definitions. |
| **[AWS Infrastructure Drift Checklist](./docs/DRIFT_CHECKLIST.md)** | Read-only commands to verify live cloud deployment against repository definitions. |
| **[Presentation Content & Speaking Notes](./FINAL_PRESENTATION_DETAILS.txt)** | Comprehensive slide blueprints, talking points, architecture matrices, and viva defense notes. |
| **[Presentation Deck Audit Checklist](./PPT_CHANGES.md)** | Review-aligned delta audit detailing slide corrections and code alignments. |
| **[Verification & Test Report](./TEST_REPORT.md)** | Empirical test outputs across security, edge queue, and serverless infrastructure. |

---

## 🏗️ High-Level System Architecture

```
[Monitored Linux Host / EC2 (i-0e29cd982f920c54c)]
   |
   +--> /proc Kernel Filesystem (/proc/stat, /proc/meminfo)
   |       |
   |       v
   +--> C++17 Telemetry Agent (systemd: telemetry-agent.service, <0.5% CPU)
   |       |
   |       +-- (Normal <85% CPU): Lightweight Telemetry (136 bytes)
   |       +-- (Spike >=85% CPU): Adaptive Top-3 Process Diagnostic Burst
   |       +-- (Network Drop): Local Disk FIFO Queue (offline_queue.jsonl)
   |
   | HTTPS POST /IngestMetrics (Header: x-api-key)
   v
[Amazon API Gateway (REST API /Prod Stage)]
   |
   v
[AWS Lambda (telemetry-backend, Python 3.12)]
   |
   +--> [Fail-Closed API Key Authentication]
   +--> [Time-Series Ingestion & Pruning]
   |       |
   |       v
   |    [Amazon RDS PostgreSQL (telemetry-db, PostgreSQL 16)]
   |       * telemetry_logs (top_processes JSONB, composite indexes)
   |       * kill_commands (immutable pre/post audit trail)
   |
   +--> [Remote Incident Remediation Guardrails]
           |
           +-- Layer 1: OS Protected Process Blocklist (systemd, sshd, dbus, cron...)
           +-- Layer 2: 2-Minute Diagnostic Telemetry Verification
           +-- Layer 3: Client-side 8-character SHA-256 Confirmation Token
           +-- Layer 4: Pre & Post Database Audit Trail
           |
           v (Outbound TLS / Zero Open Inbound Ports)
        [AWS Systems Manager (SSM Run Command: AWS-RunShellScript)]
           |
           v
        [EC2 Instance SSM Agent] executes: `kill -15 <pid>` or `kill -9 <pid>`

                ^                                   |
                | HTTPS POST /ExecuteCommand        | HTTPS GET /GetMetrics (every 3s)
                |                                   v
[Flutter Operator Portal (Linux Desktop, Web, Android APK)]
   * Live Dual-Axis Line Charts (fl_chart: Cyan CPU %, Orange RAM %)
   * Server Fleet Dropdown Filter (GET /GetServers)
   * Dynamic Red Spike Alert Banner (offending PID and command)
   * Guardrail Confirmation Modal (8-character SHA-256 verification code)
```

---

## ⚡ Key Highlights & Innovations

1. **Zero-Overhead Linux Kernel Polling**: Directly reads `/proc/stat` and `/proc/meminfo` without subprocessing shell tools (`top`, `ps`).
2. **Adaptive Diagnostic Bursts**: Emits lightweight telemetry during idle states; captures and attaches top-3 process command lines only during sustained spikes (>=85% CPU for 2 cycles).
3. **Agentless Zero-SSH Remote Remediation**: Dispatches surgical process termination commands via AWS Systems Manager without open inbound SSH ports (port 22).
4. **Multi-Layer Safety Defense**: Enforces OS binary blocklists, recent-spike verification in PostgreSQL, client-side SHA-256 tokens, and complete audit logging.
5. **Cross-Platform Operator Portal**: Real-time Flutter dashboard available for Linux Desktop and Android (`Cloud_Native_Telemetry_App.apk`).

---

## 🧪 Verification & Test Results

- **Backend Unit Tests**: **16 / 16 passed** (`python3 -m unittest backend/aws/test_lambda_function.py`)
- **Frontend Widget Tests**: **4 / 4 passed** (`flutter test`)
- **Static Analysis**: **0 issues found** (`flutter analyze`)
- **Full Verification Report**: See [`TEST_REPORT.md`](./TEST_REPORT.md)

---

## 👥 Academic Information

- **Student Name**: Abhay Rawat (24MIS0106)
- **Course**: Agile Development and DevOps Lab (ISWE 406P)
- **Professor / Evaluator**: Dr. Arunkumar A
- **Cloud Provider**: Amazon Web Services (AWS)
