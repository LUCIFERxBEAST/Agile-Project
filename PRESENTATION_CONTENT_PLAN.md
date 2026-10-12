# Cloud-Native Telemetry & Remote Diagnostics Platform
## Comprehensive Presentation Deck Content & Slide Blueprint

---

### Slide 1: Title Slide (Cover)
* **Title**: Cloud-Native Telemetry & Remote Diagnostics Platform
* **Subtitle**: High-Performance C++ Agent, Serverless AWS Backend & Flutter Incident Remediation Portal
* **Course**: Agile Development and DevOps Lab (ISWE 406P)
* **Cloud Architecture**: Amazon Web Services (EC2, Lambda, API Gateway, RDS PostgreSQL, SSM, IAM)

---

### Slide 2: Executive Agenda
1. **Problem Statement & Motivation**: The cost of blind polling & danger of manual SSH incident response.
2. **System Architecture & Flow**: Ingestion path and remote AWS SSM remediation pipeline.
3. **Low-Overhead C++ Agent**: Differential /proc parsing, adaptive spike bursts & systemd daemon.
4. **Serverless Backend & Database**: Fail-closed API auth, JSONB telemetry logs, and RDS composite indexing.
5. **Multi-Layer Safety Guardrails**: OS process blocklist, 2-minute spike verification & 8-char SHA-256 tokens.
6. **Cross-Platform Operator UI**: Live dual-axis charts, spike alert banners & human-in-the-loop modal.
7. **DevOps Challenges & Resolutions**: SCP permissions, terminal concurrency & local-to-cloud verification.
8. **Live Verification & Metrics**: 16/16 unit tests, live AWS EC2 deployment & SSM process termination.

---

### Slide 3: Problem Statement & Engineering Motivation
* **Bandwidth & Storage Bloat**: Traditional monitoring agents stream full process tables continuously, consuming gigabytes of network throughput and database disk space even during normal idle CPU load.
* **Dangerous SSH Incident Response**: Granting engineers broad SSH access to production EC2 instances creates security vulnerabilities, compliance violations, and risks catastrophic accidental command execution.
* **Delayed Metric Latency**: CloudWatch standard metric aggregation operates on 1-5 minute intervals, leaving engineering teams blind during rapid micro-spikes and runaway infinite loops.

---

### Slide 4: System Architecture & Data Flow
* **Monitored Server (EC2)**: C++ Telemetry Agent running as systemd daemon, parsing /proc every 3s, attaching top processes during spikes, AWS SSM Agent.
* **AWS Serverless Backend**: Amazon API Gateway (HTTP API), AWS Lambda (Python 3.12), Amazon RDS PostgreSQL (JSONB telemetry_logs), Fail-closed API key auth.
* **Remediation & Frontend**: Cross-platform Flutter Operator Portal, real-time fl_chart CPU/RAM gauges, 8-character SHA-256 confirmation guardrail, AWS SSM remote process termination.

---

### Slide 5: Low-Overhead C++17 Telemetry Agent
* **Zero-Allocation /proc Parsing**: Reads aggregate jiffies from /proc/stat and memory from /proc/meminfo. Measures differential tick delta: CPU% = (TotalDiff - IdleDiff) / TotalDiff * 100.
* **Adaptive Diagnostic Burst Mode**: Under normal load (<80% CPU): streams minimal lightweight JSON. Under spike load (>=80% for 2 cycles): scans /proc/[pid]/stat and attaches top 3 offending processes.
* **Offline Resilience Queue**: If network connection drops, payloads are appended to offline_telemetry_queue.jsonl and automatically flushed upon reconnection.
* **Production systemd Daemon**: Packaged as telemetry-agent.service with Restart=always, auto-booting on EC2 power-up without manual intervention.

---

### Slide 6: Serverless AWS Backend & Relational Schema
* **Amazon API Gateway (HTTP API)**: 4 REST Routes (/IngestMetrics, /GetMetrics, /GetServers, /ExecuteCommand), Sub-20ms routing latency with full CORS header negotiation.
* **AWS Lambda (Python 3.12)**: Fail-closed API key verification (x-api-key), auto-scaling from zero to thousands of concurrent streams, comprehensive audit logging.
* **Amazon RDS PostgreSQL Schema**: telemetry_logs storing server_id, cpu_percent, ram_percent, top_processes (JSONB); composite indexing on (server_id, created_at DESC).

---

### Slide 7: Multi-Layer Security & Remote Kill Guardrails
1. **Protected Process Blocklist**: Hardcoded protection rejecting termination of critical OS binaries: systemd, init, sshd, dbus, dockerd, cron, telemetry_agent (HTTP 400).
2. **2-Minute Diagnostic Verification**: Lambda verifies against RDS that the target PID was actively observed in a high-CPU spike on that specific server_id in the last 120s (HTTP 403).
3. **Cryptographic SHA-256 Token**: Operator UI calculates sha256(server_id:pid:cmd)[:8] and requires typing the 8-char verification code before enabling the Terminate trigger.
4. **Immutable Audit Trail**: Every attempt (authorized, blocked, dispatched, failed) is recorded in kill_commands table with timestamps, caller API key, and SSM execution ID.

---

### Slide 8: Flutter Cross-Platform Incident Portal
* **Live Dual-Axis Visualizations**: Real-time fl_chart line chart streaming live CPU% (Cyan) and RAM% (Orange), server dropdown dynamically populated via GET /GetServers.
* **Human-in-the-Loop Remediation Modal**: Dynamic Red Alert Banner triggers only when high CPU spike occurs; type-to-confirm modal with 🔑 8-character SHA-256 code badge; Force Kill toggle (SIGTERM -15 vs SIGKILL -9).

---

### Slide 9: DevOps Challenges & Technical Resolutions
* **AWS Organization SCP Restrictions**: Account locked down by SCP due to KYC name mismatch ➔ Updated contact information in AWS Billing and completed DigiLocker Aadhaar KYC.
* **Foreground Log Concurrency in C++**: Agent stdout logs mixed with interactive shell commands ➔ Daemonized the C++ agent as a background systemd service logging to journald with auto-restart.
* **Human-Error Risk on Long Commands**: Typing 100-character shell script arguments caused UX friction ➔ Implemented 8-character SHA-256 token verification and executable basename matching in Flutter guardrail.
* **RDS Security Group Isolation**: RDS PostgreSQL database timed out on port 5432 by default ➔ Configured Security Group Inbound rules for PostgreSQL port 5432.

---

### Slide 10: Verification, Unit Testing & Live Cloud Parity
* **16/16 Backend Unit Tests Passed**: test_api_key_auth_success / fails_closed, test_protected_process_blocklist_systemd / sshd, test_diagnostic_verification_expired (403), test_execute_command_dispatched_audit_update, test_force_kill_sigkill_dispatch (100% Passed).
* **Live AWS Cloud Deployment**: Amazon EC2 i-0e29cd982f920c54c (Ubuntu 24.04 LTS), Ingest Endpoint: https://7qw0khxma2.execute-api.ap-southeast-2.amazonaws.com, RDS PostgreSQL: telemetry-db (ap-southeast-2), 4/4 Flutter Widget Tests Passed (0 lint warnings).

---

### Slide 11: Conclusion & Future Engineering Scope
* **Key Deliverables Met**: Low-overhead C++ Agent (<0.5% CPU overhead), Serverless Ingestion on AWS Lambda & API Gateway, Relational Time-Series & JSONB Audit Storage on RDS PostgreSQL, Zero-SSH Guardrailed Remediation via AWS SSM, Cross-Platform Operator Portal in Flutter.
* **Future Scope**: ML Anomaly Detection using Amazon SageMaker / Kinesis; Fleet Auto-Scaling for thousands of EC2 and Kubernetes nodes; Configurable Auto-Kill Policies for approved worker scripts.

---

### Slide 12: Thank You / Q&A
* **Title**: THANK YOU!
* **Subtitle**: Questions, Discussion & Live System Demonstration
* **Course**: Agile Development and DevOps Lab (ISWE 406P)
