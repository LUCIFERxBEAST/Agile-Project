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
| **[04. Next Steps & Action Roadmap](./04_NEXT_STEPS_AND_ROADMAP.md)** | Complete sequential roadmap of what you need to do next, from cloud deployment to Review 2 stretch features (Process Diagnostics, Remote Incident Orchestration). |

---

## 🏗️ High-Level System Architecture

```
+-------------------------------------------------------------+
|                  Linux Host / Amazon EC2                    |
|                                                             |
|   +-------------------+          +----------------------+   |
|   |  Linux Kernel     |          |   systemd Daemon     |   |
|   |  /proc/stat       |          |   (Auto-Restart)     |   |
|   |  /proc/meminfo    |          +----------+-----------+   |
|   +---------+---------+                     |               |
|             | (read ticks & memory)         | (manages)     |
|             v                               v               |
|   +-----------------------------------------------------+   |
|   |            C++ Telemetry Agent (utility.cpp)        |   |
|   |  - Parses CPU & Memory utilization                  |   |
|   |  - JSON Serialization via nlohmann/json             |   |
|   |  - HTTP POST via libcurl                            |   |
|   |  - [Future Scope 1] Offline Disk Queue & Auto-Retry |   |
|   |    (offline_queue.jsonl caching when network down)  |   |
|   +--------------------------+--------------------------+   |
+------------------------------|------------------------------+
                               |
                   HTTPS POST  | (Network / Internet)
                   (or fallback to local disk)
                               v
+-------------------------------------------------------------+
|                        AWS Cloud                            |
|                                                             |
|   +-----------------------------------------------------+   |
|   |                Amazon API Gateway                   |   |
|   |     - POST /IngestMetrics                           |   |
|   |     - GET  /GetMetrics                              |   |
|   +--------------------------+--------------------------+   |
|                              |                              |
|                              v                              |
|   +-----------------------------------------------------+   |
|   |          AWS Lambda (lambda_function.py)            |   |
|   |     - Ingestion Handler (SQL INSERT)                |   |
|   |     - Query Handler (SQL SELECT recent 20)          |   |
|   +--------------------------+--------------------------+   |
|                              |                              |
|                              v (psycopg2-binary)            |
|   +-----------------------------------------------------+   |
|   |          Amazon RDS (PostgreSQL Database)           |   |
|   |     - Table: telemetry_logs                         |   |
|   |     - Index: idx_telemetry_created_at               |   |
|   +-----------------------------------------------------+   |
+-------------------------------------------------------------+
                               ^
                               | HTTPS GET
                               |
+-------------------------------------------------------------+
|                Flutter Mobile Dashboard                     |
|  - Real-time CPU & RAM utilization chart (fl_chart)         |
|  - Recent log timeline view                                 |
|  - Pull-to-refresh & auto-reload mechanism                  |
+-------------------------------------------------------------+
```

---

## 🚦 Project Status Summary

### Completed Milestones
- [x] **Review 1 Scope (End-to-End Pipeline)**: Native C++ agent parsing `/proc`, metric aggregation, serverless ingestion, database persistence, and mobile graph visualization.
- [x] **Future Scope #1 (Offline Queue & Auto-Retry)**: Persistent disk caching in `offline_queue.jsonl` when connection drops, automatic sequential flush upon network recovery.
- [x] **Cloud Migration (Azure to AWS)**:
  - Cleaned all legacy Azure Functions files (`tel-func/`).
  - Created AWS Lambda multi-route handler (`backend/aws/lambda_function.py`).
  - Created AWS SAM Infrastructure-as-Code (`backend/aws/template.yaml`).
  - Created PostgreSQL schema script (`backend/aws/schema.sql`).
  - Created packaging & deployment script (`backend/aws/deploy_aws.sh`).
  - Configured C++ agent to read endpoint from `TELEMETRY_API_URL` environment variable.
  - Updated Flutter app API endpoint structure in `main.dart`.

### Up Next
1. Provision live AWS resources (Amazon RDS PostgreSQL & deploy AWS Lambda with SAM).
2. Run database migration `schema.sql`.
3. Test end-to-end data flow from EC2 / local host to RDS.
4. Connect Flutter mobile dashboard to live AWS API Gateway.
