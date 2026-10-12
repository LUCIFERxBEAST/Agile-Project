# 01. Architecture & System Design

This document details the internal design, algorithms, data flows, and component responsibilities of the Cloud-Native Linux Telemetry System.

---

## 1. Component Overview & Technology Stack

| Layer | Technology | Primary Function |
| :--- | :--- | :--- |
| **Telemetry Agent** | C++17, libcurl, nlohmann/json | Low-overhead metric extraction directly from Linux kernel virtual filesystem (`/proc`), JSON formatting, HTTP transport, and persistent offline queue. |
| **Cloud Compute Host** | Linux / Amazon EC2 (`t2.micro` or `t3.micro`) | Dedicated host running the telemetry agent as a persistent system daemon. |
| **Process Manager** | Linux `systemd` | Manages daemon life-cycle, automatic boot startup, and instant crash recovery (`Restart=always`). |
| **API Ingestion** | AWS API Gateway (HTTP API) | Managed entry point providing low-latency, scalable routing for incoming POST and outgoing GET requests. |
| **Serverless Compute**| AWS Lambda (Python 3.12) | Stateless event handler parsing telemetry payloads, inserting records into PostgreSQL, and serving queries. |
| **Storage Engine** | Amazon RDS (PostgreSQL 15+) | Managed relational time-series storage preserving historical system utilization logs. |
| **Client Frontend** | Flutter (Dart), `fl_chart`, `http` | Cross-platform mobile dashboard rendering real-time dual-line graphs (CPU & RAM) and historical logs. |

---

## 2. Layer 1: C++ Telemetry Agent

The agent is located in `backend/src/utility.cpp`. It avoids shell command execution (such as `top` or `vmstat`) to eliminate process spawning overhead and memory bloat.

### 2.1 Kernel `/proc` Parsing Engine
- **CPU Metrics (`/proc/stat`)**:
  - The first line of `/proc/stat` starts with `cpu` followed by 10 integer tick counts representing time spent in various states:
    `user`, `nice`, `system`, `idle`, `iowait`, `irq`, `softirq`, `steal`, `guest`, `guest_nice`.
  - Ticks are accumulated:
    $$\text{Total Ticks} = \sum_{i=0}^{9} \text{tempValue}_i$$
    $$\text{Idle Ticks} = \text{tempValue}_3 (\text{idle}) + \text{tempValue}_4 (\text{iowait})$$
  - Delta calculation across sampling intervals:
    $$\Delta \text{Total} = \text{currTotal} - \text{prevTotal}$$
    $$\Delta \text{Idle} = \text{currIdle} - \text{prevIdle}$$
    $$\text{CPU In Use \%} = \frac{\Delta \text{Total} - \Delta \text{Idle}}{\Delta \text{Total}} \times 100$$

- **Memory Metrics (`/proc/meminfo`)**:
  - Scans key-value pairs line by line looking for:
    - `MemTotal`: Total physical RAM installed in kB.
    - `MemAvailable`: Estimated amount of memory available for starting new applications without swapping.
  - Utilization calculations:
    $$\text{RAM Used (MB)} = \frac{\text{MemTotal} - \text{MemAvailable}}{1024}$$
    $$\text{RAM In Use \%} = \frac{\text{MemTotal} - \text{MemAvailable}}{\text{MemTotal}} \times 100$$

### 2.2 JSON Serialization
Metrics are packed into standard JSON format using `nlohmann/json`:
```json
{
  "server_id": "beast",
  "timestamp": 1788748874,
  "cpu_percent": 4.56,
  "ram_percent": 70.08,
  "ram_used_mb": 21691,
  "ram_total_mb": 30953
}
```

### 2.3 [Future Scope 1] Offline Disk Queue & Auto-Retry Engine
When network connectivity is lost or the cloud server returns non-200 responses:
1. **Detection**: `sendTelemetry` tracks `CURLE_OK` and verifies HTTP status codes (`200 <= status < 300`).
2. **Caching**: If sending fails, `saveToOfflineQueue(jsonString)` appends the payload to `offline_queue.jsonl` (one JSON object per line).
3. **Flushing & Recovery**:
   - At the beginning of each interval, `flushOfflineQueue(apiUrl)` inspects `offline_queue.jsonl`.
   - If records exist, it sequentially retries transmitting each queued record.
   - If successful, it removes sent items from the file.
   - If a failure occurs mid-flush, transmission is paused and remaining items are retained on disk to preserve data ordering without loss.

---

## 3. Layer 2: AWS Serverless Ingestion & Query Layer

The serverless backend is located in `backend/aws/`.

### 3.1 AWS API Gateway HTTP API
- Managed API Gateway providing two routes:
  - `POST /IngestMetrics`: Ingestion endpoint called by C++ agent.
  - `GET /GetMetrics`: Retrieval endpoint called by Flutter mobile dashboard.
- Configured with CORS enabled (`AllowOrigins: *`) for cross-platform access.

### 3.2 AWS Lambda Handler (`lambda_function.py`)
- Python 3.12 runtime with `psycopg2-binary` connection pooling.
- **`handle_ingest_metrics`**:
  - Parses event JSON payload.
  - Executes parameterized SQL `INSERT`:
    ```sql
    INSERT INTO telemetry_logs (server_id, cpu_percent, ram_percent, ram_used_mb, ram_total_mb, timestamp)
    VALUES (%s, %s, %s, %s, %s, %s);
    ```
  - Returns HTTP 200 with confirmation message.
- **`handle_get_metrics`**:
  - Fetches the most recent 20 metric rows ordered by `created_at DESC`.
  - Serializes rows into a clean JSON list for the mobile app graph.

---

## 4. Layer 3: Database & Storage Engine

### 4.1 Schema (`schema.sql`)
The PostgreSQL database table stores time-series telemetry records:
```sql
CREATE TABLE IF NOT EXISTS telemetry_logs (
    id SERIAL PRIMARY KEY,
    server_id VARCHAR(64) NOT NULL,
    cpu_percent NUMERIC(5, 2) NOT NULL,
    ram_percent NUMERIC(5, 2) NOT NULL,
    ram_used_mb BIGINT NOT NULL,
    ram_total_mb BIGINT NOT NULL,
    timestamp BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_telemetry_created_at ON telemetry_logs (created_at DESC);
```
- **Index Optimization**: `idx_telemetry_created_at` provides instantaneous retrieval of the latest telemetry points for real-time dashboard plotting.

---

## 5. Layer 4: Flutter Mobile Dashboard

The client application is located in `flutter mobile frontend/lib/main.dart`.

### 5.1 Architecture & UI Components
- **Line Chart View (`fl_chart`)**:
  - Renders dual curved trendlines: **Cyan** for CPU % and **Orange** for RAM %.
  - X-axis represents chronological index; Y-axis is scaled from 0% to 100%.
- **Recent Logs Feed**:
  - Scrollable `ListView.builder` displaying server ID, exact CPU %, RAM %, and RAM consumed in megabytes.
- **Refresh & Auto-Reload**:
  - Floating action button to manually trigger immediate metric reload.
  - Automatically reverses the data list (`json.decode(response.body).reversed`) so the visual graph flows chronologically left-to-right (oldest to newest).
