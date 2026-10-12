# 01. Architecture & System Design

This document details the internal design, algorithms, data flows, and component responsibilities of the Cloud-Native Linux Telemetry & Remote Diagnostics System.

---

## 1. Component Overview & Technology Stack

| Layer | Technology | Primary Function |
| :--- | :--- | :--- |
| **Telemetry Agent** | C++17, libcurl, nlohmann/json | Low-overhead metric extraction directly from Linux kernel virtual filesystem (`/proc`), JSON formatting, HTTP transport, and persistent offline queue. |
| **Cloud Compute Host** | Amazon EC2 (`t3.micro`, `ap-southeast-2`) | Monitored Linux host running the telemetry agent as a persistent system daemon. |
| **Process Manager** | Linux `systemd` | Manages daemon life-cycle, automatic boot startup, and instant crash recovery (`Restart=always`, `RestartSec=3`). |
| **API Ingestion** | Amazon API Gateway REST API (`/Prod` Stage) | Managed entry point providing low-latency routing, throttling, usage plan enforcement, and CORS support. |
| **Serverless Compute**| AWS Lambda (Python 3.12) | Stateless event handler enforcing fail-closed `x-api-key` authentication, database persistence, query serving, and SSM command dispatch. |
| **Remote Remediation**| AWS Systems Manager (SSM Run Command) | Secure, agentless remote process termination via outbound TLS without open inbound SSH ports (port 22). |
| **Storage Engine** | Amazon RDS PostgreSQL 16 (as deployed) / PostgreSQL 15 local (`db.t4g.micro`, `ap-southeast-2`) | Managed relational time-series storage preserving system metrics, process snapshots, and remediation audit records. |
| **Client Frontend** | Flutter (Dart), `fl_chart`, `http`, `crypto` | Cross-platform mobile portal rendering dual-line graphs (CPU & RAM), server filtering, spike alert banners, and guarded kill dialogs. |

---

## 2. Layer 1: C++ Telemetry Agent

The telemetry agent is implemented in `backend/src/utility.cpp`. It queries kernel state directly through `/proc` rather than spawning external processes (`top`, `ps`, `vmstat`), eliminating fork overhead and execution jitter.

### 2.1 Kernel `/proc` Parsing Engine
- **CPU Metrics (`/proc/stat`)**:
  - The first line of `/proc/stat` starts with `cpu` followed by 10 integer tick counters:
    `user`, `nice`, `system`, `idle`, `iowait`, `irq`, `softirq`, `steal`, `guest`, `guest_nice`.
  - Ticks are accumulated across all cores:
    $$\text{Total Ticks} = \sum_{i=0}^{9} \text{tempValue}_i$$
    $$\text{Idle Ticks} = \text{tempValue}_3 (\text{idle}) + \text{tempValue}_4 (\text{iowait})$$
  - Delta calculation across sampling intervals (default: 5 seconds):
    $$\Delta \text{Total} = \text{currTotal} - \text{prevTotal}$$
    $$\Delta \text{Idle} = \text{currIdle} - \text{prevIdle}$$
    $$\text{CPU In Use \%} = \frac{\Delta \text{Total} - \Delta \text{Idle}}{\Delta \text{Total}} \times 100$$

- **Memory Metrics (`/proc/meminfo`)**:
  - Scans key-value pairs line by line looking for:
    - `MemTotal`: Total physical RAM installed in kB.
    - `MemAvailable`: Estimated memory available for new applications without swapping.
  - Utilization calculations:
    $$\text{RAM Used (MB)} = \frac{\text{MemTotal} - \text{MemAvailable}}{1024}$$
    $$\text{RAM In Use \%} = \frac{\text{MemTotal} - \text{MemAvailable}}{\text{MemTotal}} \times 100$$

### 2.2 Process Diagnostics (Spike Burst Capture)
- **Spike Trigger Condition**: CPU utilization `>= 85.0%` for `>= 2 consecutive cycles` (10 seconds minimum sustained load).
- **Process Scanner (`getTopProcesses`)**:
  - Iterates `/proc/[pid]/stat` to compute process CPU deltas against the baseline interval:
    $$\text{Process Total Ticks} = \text{utime} + \text{stime}$$
    $$\text{Process CPU \%} = \frac{\Delta \text{Process Ticks}}{\Delta \text{Total Ticks}} \times 100$$
  - Reads `/proc/[pid]/cmdline` to extract the full command line and executable name.
  - Sorts all active processes descending by CPU utilization and retains the **top 3 processes**.
  - Attaches the diagnostic snapshot array to the JSON payload: `[{"pid": int, "cmd": string, "cpu": double}, ...]`.

### 2.3 JSON Serialization & Payload Footprint
Payloads are serialized using `nlohmann/json` without extraneous whitespace:
```json
{"cpu_percent":14.25,"ram_percent":42.85,"ram_total_mb":1024,"ram_used_mb":438,"server_id":"i-0abcdef1234567890","timestamp":1790982052}
```
- **Normal (Non-Spike) Payload Size**: Exactly **136 bytes** (compact JSON serialization using a realistic 19-character EC2 instance ID).
- **Spike Payload Size**: Typically ~250–320 bytes depending on process command-line lengths.

### 2.4 Offline Disk Queue & Auto-Retry Engine
When network connectivity is unavailable or the API Gateway endpoint returns non-200 responses:
1. **Detection**: `sendTelemetry` tracks libcurl result codes (`CURLE_OK`) and verifies HTTP status codes (`200 <= status < 300`).
2. **Persistence**: `saveToOfflineQueue(jsonString)` appends the failed payload to `offline_queue.jsonl` (one JSON object per line).
3. **Flushing & Recovery**:
   - At the beginning of each 5-second cycle, `flushOfflineQueue(apiUrl, apiKey)` checks `offline_queue.jsonl`.
   - If records exist, it sequentially retries transmitting each queued record with the `x-api-key` header.
   - If transmission succeeds, flushed records are removed from the file.
   - If a failure occurs mid-flush, transmission pauses and remaining items are preserved on disk to prevent telemetry loss.

---

## 3. Layer 2: AWS Serverless Ingestion, Query & Remediation Layer

The backend is implemented in `backend/aws/lambda_function.py` and defined via AWS SAM in `backend/aws/template.yaml`.

### 3.1 AWS API Gateway REST API (`/Prod` Stage)
The system provisions an `AWS::Serverless::Api` with stage `Prod`, exposing 4 core endpoints:
- `POST /Prod/IngestMetrics`: Ingestion endpoint called by C++ telemetry agents.
- `GET /Prod/GetMetrics`: Telemetry retrieval endpoint called by Flutter mobile clients (supports optional `?server_id=<id>` filter).
- `GET /Prod/GetServers`: Distinct server discovery endpoint for client-side dropdown population.
- `POST /Prod/ExecuteCommand`: Remote incident orchestration endpoint for process termination via AWS SSM Run Command.

All routes enforce API Key validation via API Gateway Usage Plans and custom Lambda header verification.

### 3.2 Fail-Closed Authentication Model
- Every request must include the HTTP header `x-api-key: <YOUR_API_KEY>`.
- **Fail-Closed Guarantee**: Lambda compares the header against the `EXPECTED_API_KEY` environment variable. If `EXPECTED_API_KEY` is unset or empty, Lambda immediately rejects the request with HTTP `500` (`SERVER_MISCONFIGURED`).
- If the header is missing or mismatching, Lambda returns HTTP `403` (`INVALID_API_KEY`).

### 3.3 Remote Remediation via AWS Systems Manager (SSM)
- Eliminates inbound SSH port 22 access on monitored nodes.
- Dispatches shell commands (`kill -15 <pid>` or `kill -9 <pid>`) through SSM Run Command document `AWS-RunShellScript`.
- Enforces pre-execution audit logging to the `kill_commands` table before command dispatch.

---

## 4. Layer 3: Database & Storage Engine

The storage engine runs on Amazon RDS PostgreSQL (`db.t4g.micro`, `ap-southeast-2`).

### 4.1 Schema Definition (`schema.sql`)
```sql
CREATE TABLE IF NOT EXISTS telemetry_logs (
    id SERIAL PRIMARY KEY,
    server_id VARCHAR(64) NOT NULL,
    cpu_percent NUMERIC(5, 2) NOT NULL,
    ram_percent NUMERIC(5, 2) NOT NULL,
    ram_used_mb BIGINT NOT NULL,
    ram_total_mb BIGINT NOT NULL,
    timestamp BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    top_processes JSONB
);

-- Primary composite query index for ?server_id=<id> ORDER BY created_at DESC LIMIT 20
CREATE INDEX IF NOT EXISTS idx_telemetry_server_created ON telemetry_logs (server_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_telemetry_created_at ON telemetry_logs (created_at DESC);

-- Remote Remediation Audit Table
CREATE TABLE IF NOT EXISTS kill_commands (
    id SERIAL PRIMARY KEY,
    instance_id VARCHAR(64) NOT NULL,
    pid INTEGER NOT NULL,
    process_name TEXT NOT NULL,
    requested_signal VARCHAR(16) NOT NULL,
    allowed BOOLEAN NOT NULL,
    status VARCHAR(32) DEFAULT 'requested',
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_kill_commands_server_created ON kill_commands (instance_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_kill_commands_created_at ON kill_commands (created_at DESC);
```

---

## 5. Layer 4: Flutter Mobile Portal

The mobile portal is implemented in `flutter mobile frontend/lib/main.dart`.

### 5.1 Architecture & UI Components
- **Server Filter Dropdown (`AppBar`)**:
  - Automatically queries `GET /Prod/GetServers` and populates a dropdown with available server IDs and an `'All servers'` option.
  - Selecting a server filters the telemetry graph and logs via `?server_id=<id>`.
- **Dual-Metric Real-Time Line Graph (`fl_chart`)**:
  - Renders real-time curved trendlines: **Cyan** for CPU % and **Orange** for RAM %.
  - X-axis displays chronological timeline; Y-axis is fixed from 0% to 100%.
- **Dismissible High CPU Spike Alert Banner**:
  - Automatically detects when `latestRecord['top_processes']` contains high-CPU diagnostics.
  - Displays banner: `"High CPU detected — top process: <cmd> (<cpu>%)"`.
  - Provides a "Kill" button and a dismiss button; resets automatically when load normalizes or a new spike occurs.
- **Kill Process Guardrail Dialog**:
  - Computes an 8-character cryptographic confirmation code: `sha256('$targetInstanceId:$pid:$cmd')[:8]`.
  - Requires the operator to enter the 8-character code (or process command) before unlocking the termination button.
  - Includes a "Force Kill (SIGKILL -9)" checkbox toggle (defaults to graceful `SIGTERM -15`).
- **Polling & Refresh Timers**:
  - Telemetry metrics polled every 3 seconds (`Timer.periodic(Duration(seconds: 3))`).
  - Available servers list refreshed every 12 seconds.
- **Client Configuration**:
  - Configurable at build time via `--dart-define=API_BASE_URL=...` (defaulting to live API Gateway endpoint) and `--dart-define=API_KEY=...`.
  - Includes interactive `LoginScreen` for in-memory API key entry.
