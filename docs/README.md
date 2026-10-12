# Cloud-Native Linux Telemetry & Infrastructure Monitoring System
## Comprehensive Project Documentation & Operation Manual

Welcome to the central documentation hub for the **Cloud-Native Linux Telemetry & Infrastructure Monitoring System**. This project is an end-to-end DevOps and cloud-native systems monitoring solution engineered with a native C++ telemetry agent, an AWS serverless ingestion & persistence pipeline, and a Flutter mobile dashboard.

---

## 📑 Documentation Index

| Document | Description |
| :--- | :--- |
| **[01. Architecture & System Design](./01_ARCHITECTURE_AND_SYSTEM_DESIGN.md)** | Full technical breakdown of all layers: C++ Agent, AWS Lambda, API Gateway, Amazon RDS PostgreSQL, and Flutter Mobile Dashboard. |
| **[02. Setup & Deployment Guide](./02_SETUP_AND_DEPLOYMENT_GUIDE.md)** | Step-by-step instructions to provision Amazon RDS, deploy AWS Lambda via AWS SAM, configure systemd on Linux/EC2, and launch the mobile app. |
| **[03. Testing & Verification](./03_TESTING_AND_VERIFICATION.md)** | Verification protocols for unit tests, offline queue caching, auto-retry flush tests, crash recovery validation, and synthetic load testing (`stress-ng`). |
| **[04. Next Steps & Action Roadmap](./04_NEXT_STEPS_AND_ROADMAP.md)** | Current production status and future enhancement roadmap (ML anomaly detection, auto-scaling, automated auto-kill policies). |
| **[05. Guardrails & Remote Remediation](./05_GUARDRAILS_AND_REMEDIATION.md)** | Detailed specification of the 4-layer kill guardrail (blocklist, recent-spike verification, SHA-256 token, audit logging) and AWS SSM Run Command execution path. |
| **[Verified Implementation Facts](./VERIFIED_FACTS.md)** | Code-verified architectural values, exact line references, parameters, and schema details. |

---

## 🏗️ High-Level System Architecture

![Cloud-Native Linux Telemetry Architecture](images/architecture.png)

### Architectural Flow & Control Plane
1. **Telemetry Telemetry Path**:
   - The native C++17 telemetry agent runs as a system daemon on monitored Linux/EC2 hosts (`t3.micro`, `ap-southeast-2`), differential-parsing kernel `/proc/stat` and `/proc/meminfo` every 5 seconds.
   - When CPU usage reaches `>= 85.0%` for `>= 2 consecutive cycles`, top 3 processes are captured.
   - Metrics are dispatched via HTTPS POST with header `x-api-key` to Amazon API Gateway (`/Prod/IngestMetrics`).
   - If the network or API is unavailable, payloads cache locally in `offline_queue.jsonl` and auto-flush sequentially upon restoration.
2. **Serverless Ingestion & Querying**:
   - API Gateway forwards authenticated requests to AWS Lambda (Python 3.12).
   - Lambda validates API keys in a fail-closed model, logs to Amazon CloudWatch, and inserts time-series logs into Amazon RDS PostgreSQL (`db.t4g.micro`, `ap-southeast-2`).
3. **Mobile Observability & Remediation**:
   - Flutter mobile portal polls `GET /Prod/GetMetrics` and `GET /Prod/GetServers` every 3 seconds with header `x-api-key`.
   - Operators can filter telemetry by server or initiate remote process termination (`POST /Prod/ExecuteCommand`).
4. **Remote Remediation via AWS Systems Manager (SSM)**:
   - Remote termination requests are evaluated against 4 guardrail layers (protected process blocklist, recent 2-minute diagnostic check, client-side confirmation token, and database audit trail).
   - Upon authorization, Lambda calls AWS Systems Manager Run Command (`AWS-RunShellScript`) via outbound TLS to execute `kill -15 <pid>` or `kill -9 <pid>` on the EC2 instance.
5. **IAM Security Model**:
   - **`telemetry-ec2-ssm-role`**: Grants monitored EC2 instances `AmazonSSMManagedInstanceCore` permissions without open inbound SSH ports (port 22).
   - **`telemetry-lambda-role`**: Grants AWS Lambda least-privilege `ssm:SendCommand` access to target instances.

---

## 🚦 Project Status Summary

### Completed Milestones
- [x] **Core Pipeline**: Native C++ agent parsing `/proc`, metric aggregation, serverless ingestion, database persistence, and mobile graph visualization.
- [x] **Delivered Future Scope 1 (Offline Queue & Auto-Retry)**: Persistent disk caching in `offline_queue.jsonl` when connection drops, automatic sequential flush upon network recovery.
- [x] **Delivered Future Scope 2 (Process Diagnostics)**: Adaptive capture of top 3 CPU processes during sustained spikes (`>= 85.0%` for `>= 2 cycles`), stored in `top_processes JSONB`.
- [x] **Delivered Future Scope 3 (Remote Remediation via AWS SSM)**: Agentless process termination through AWS Systems Manager Run Command (`POST /Prod/ExecuteCommand`) with full audit logging in `kill_commands`.
- [x] **Delivered Future Scope 4 (Security Hardening)**: Fail-closed `x-api-key` header verification in AWS Lambda, API Gateway usage plan and throttling, and non-root systemd configuration with `mode 600` environment files.
- [x] **Delivered Future Scope 5 (Multi-Server Dropdown)**: Distinct server ID discovery (`GET /Prod/GetServers`) and dynamic filtering in mobile UI.

### Remaining Future Roadmap
1. **Machine Learning Anomaly Detection**: Unsupervised clustering (e.g., Isolation Forests) for subtle memory leaks and erratic CPU trends.
2. **Automated Auto-Kill Remediation Policies**: Rule-based automatic termination of unapproved miner/crypto binaries during sustained spikes.
3. **Fleet Auto-Scaling Integrations**: CloudWatch metric alarms dynamically triggering AWS Auto Scaling groups.
