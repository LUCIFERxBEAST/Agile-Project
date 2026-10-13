# Backend: C++ Telemetry Agent & AWS Serverless Infrastructure

This directory houses the systems-level C++ telemetry agent, AWS Lambda serverless handler, PostgreSQL database schema, and AWS SAM deployment templates.

---

## 📂 Directory Structure

```
backend/
├── src/
│   ├── utility.cpp        # Native C++17 telemetry agent (/proc parser, offline queue, curl)
│   └── Dockerfile         # Multi-stage Docker container build for the agent
├── aws/
│   ├── lambda_function.py # Serverless handler (API key auth, guardrails, RDS, SSM dispatch)
│   ├── template.yaml      # AWS SAM infrastructure-as-code template
│   ├── schema.sql         # PostgreSQL schema (telemetry_logs JSONB & kill_commands audit)
│   ├── test_lambda_function.py # 16/16 Unit testing suite
│   ├── deploy_aws.sh      # Automated packaging and deployment script
│   └── env.local.json     # SAM local test environment configuration
└── README.md
```

---

## 🚦 Implementation Status Matrix

- [x] **1. Kernel `/proc` Parsing Engine (C++17)**: High-frequency parsing of `/proc/stat` and `/proc/meminfo` (<0.5% CPU overhead).
- [x] **2. Adaptive Diagnostic Burst Mode**: Attaches top-3 processes dynamically when CPU exceeds 85.0% for >= 2 consecutive cycles.
- [x] **3. Edge Offline Queue & Auto-Retry**: Persistent local disk caching (`offline_queue.jsonl`) with automatic FIFO queue flush upon network restoration.
- [x] **4. Linux Daemonization**: Production `systemd` service (`telemetry-agent.service`) with `Restart=always` on Amazon EC2 (`i-0e29cd982f920c54c`).
- [x] **5. Serverless AWS Lambda Backend**: Python 3.12 handler with fail-closed `x-api-key` authentication and psycopg2 binary layer.
- [x] **6. Relational Database with JSONB**: Amazon RDS PostgreSQL 16 (`telemetry-db`) with composite B-Tree indexes on `(server_id, created_at DESC)`.
- [x] **7. Multi-Layer Remote Kill Guardrails**: OS binary blocklist, 2-minute diagnostic history check, and immutable `kill_commands` audit trail.
- [x] **8. Agentless Remote Remediation**: Dispatches surgical `kill -15` / `kill -9` via AWS Systems Manager (SSM) Run Command without open SSH ports.

---

## 🛠️ Build & Execution Instructions

### 1. Compile & Run C++ Agent Locally
```bash
cd src
g++ -O2 -std=c++17 utility.cpp -o telemetry_agent -lcurl
export TELEMETRY_API_KEY="<YOUR_API_KEY>"
export TELEMETRY_API_URL="https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/IngestMetrics"
export TELEMETRY_SERVER_ID="i-0e29cd982f920c54c"
./telemetry_agent
```

### 2. Run Backend Unit Tests
```bash
cd aws
python3 -m unittest test_lambda_function.py -v
```
*(16/16 Unit Tests Passed)*

For complete architectural details, see [docs/01_ARCHITECTURE_AND_SYSTEM_DESIGN.md](../docs/01_ARCHITECTURE_AND_SYSTEM_DESIGN.md).
