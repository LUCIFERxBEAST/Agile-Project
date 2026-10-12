# 03. Testing & Verification Protocols

This document outlines testing methodologies and verification procedures to ensure every layer of the monitoring and remediation pipeline operates correctly, securely, and with fault tolerance.

---

## 1. Local C++ Unit & Metric Accuracy Testing

### 1.1 Validating Kernel Metric Parsing
Compare the telemetry agent's CPU and RAM values with Linux kernel diagnostic utilities:
```bash
# In terminal 1 (baseline host stats):
top

# In terminal 2 (compile & run telemetry agent foreground):
cd backend/src
g++ -O2 -std=c++17 utility.cpp -o telemetry_agent -lcurl
export TELEMETRY_API_KEY="<YOUR_API_KEY>"
export TELEMETRY_API_URL="https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics"
./telemetry_agent
```
- **CPU Check**: Confirm `cpu_percent` corresponds to `100 - %id` in `top`.
- **Memory Check**: Inspect `/proc/meminfo` directly:
  ```bash
  grep -E 'MemTotal|MemAvailable' /proc/meminfo
  ```
  Confirm `ram_used_mb` matches `(MemTotal - MemAvailable) / 1024`.

---

## 2. Testing Offline Disk Queue & Auto-Retry Engine

The agent caches metric payloads locally in `offline_queue.jsonl` if cloud connectivity drops, and automatically flushes them sequentially upon network recovery.

### 2.1 Test Procedure
1. **Simulate Network Failure**:
   Run the agent with an unreachable local port:
   ```bash
   export TELEMETRY_API_URL="http://127.0.0.1:9999/Prod/IngestMetrics"
   export TELEMETRY_API_KEY="<YOUR_API_KEY>"
   ./telemetry_agent
   ```
2. **Observe Caching**:
   After 2 cycles (approx. 10 seconds), observe terminal output:
   ```text
   [ERROR] curl_easy_perform() failed: Couldn't connect to server
   [OFFLINE QUEUE] Saved payload locally to offline_queue.jsonl
   ```
3. **Verify File Contents**:
   Stop the agent and inspect `offline_queue.jsonl`:
   ```bash
   cat offline_queue.jsonl
   ```
   Confirm JSON lines represent un-transmitted telemetry records.

4. **Simulate Connection Recovery**:
   Restore the valid AWS API Gateway endpoint:
   ```bash
   export TELEMETRY_API_URL="https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics"
   export TELEMETRY_API_KEY="<YOUR_API_KEY>"
   ./telemetry_agent
   ```
5. **Observe Auto-Retry Flush**:
   ```text
   [AUTO-RETRY] Attempting to flush 2 queued metric(s)...
   [SUCCESS] Payload sent to https://... (HTTP 200)
   [SUCCESS] Payload sent to https://... (HTTP 200)
   [AUTO-RETRY] Successfully flushed all queued metrics! Queue cleared.
   ```
   Confirm `offline_queue.jsonl` is removed or truncated to 0 bytes once flush completes.

---

## 3. Testing AWS Cloud Ingestion, Query & Remediation Endpoints

All endpoints require the `x-api-key` header and use the `/Prod` stage URL format.

### 3.1 Ingestion Endpoint (`POST /Prod/IngestMetrics`)
```bash
curl -i -X POST "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics" \
  -H "Content-Type: application/json" \
  -H "x-api-key: <YOUR_API_KEY>" \
  -d '{
    "server_id": "i-0abcdef1234567890",
    "cpu_percent": 14.25,
    "ram_percent": 42.85,
    "ram_used_mb": 438,
    "ram_total_mb": 1024,
    "timestamp": 1790982052
  }'
```
**Expected Response**:
```http
HTTP/1.1 200 OK
Content-Type: application/json

{"message": "Metric ingested successfully"}
```

### 3.2 Metrics Retrieval Endpoint (`GET /Prod/GetMetrics`)
```bash
# Query all servers (most recent 20):
curl -i -X GET "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetMetrics" \
  -H "x-api-key: <YOUR_API_KEY>"

# Query specific server:
curl -i -X GET "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetMetrics?server_id=i-0abcdef1234567890" \
  -H "x-api-key: <YOUR_API_KEY>"
```
**Expected Response**:
JSON array of recent telemetry objects with `server_id`, `cpu_percent`, `ram_percent`, `ram_used_mb`, `ram_total_mb`, `created_at`, and `top_processes`.

### 3.3 Server Discovery Endpoint (`GET /Prod/GetServers`)
```bash
curl -i -X GET "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetServers" \
  -H "x-api-key: <YOUR_API_KEY>"
```
**Expected Response**:
JSON array of distinct server strings: `["i-0abcdef1234567890", "cluster-node-02"]`.

### 3.4 Validate Database State via `psql`
```bash
psql -h <YOUR_RDS_ENDPOINT> -U postgres -d postgres -c \
  "SELECT id, server_id, cpu_percent, ram_percent, top_processes, created_at FROM telemetry_logs ORDER BY created_at DESC LIMIT 5;"
```

---

## 4. Security, Guardrails & Negative Test Verification Matrix

Use this matrix to execute and record evidence for every security control and remediation guardrail:

| Test ID | Test Scenario | Exact Execution Command | Expected Result | Evidence Captured? (yes/no) |
| :--- | :--- | :--- | :--- | :---: |
| **SEC-01** | Missing `x-api-key` header rejected on every route | `curl -i -X GET "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetMetrics"`<br>`curl -i -X GET "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetServers"`<br>`curl -i -X POST "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics" -d '{}'`<br>`curl -i -X POST "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/ExecuteCommand" -d '{}'` | HTTP `403 Forbidden`<br>`{"error": "Forbidden: Missing or invalid API Key in 'x-api-key' header", "code": "INVALID_API_KEY"}` | [ ] |
| **SEC-02** | Wrong `x-api-key` header rejected | `curl -i -X GET "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetMetrics" -H "x-api-key: bad-key-1234"` | HTTP `403 Forbidden`<br>`{"error": "Forbidden: Missing or invalid API Key in 'x-api-key' header", "code": "INVALID_API_KEY"}` | [ ] |
| **SEC-03** | `ExecuteCommand` on protected process (`PID 1 / systemd`) | `curl -i -X POST "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/ExecuteCommand" -H "Content-Type: application/json" -H "x-api-key: <YOUR_API_KEY>" -d '{"instance_id": "i-0abcdef1234567890", "pid": 1, "process_name": "systemd"}'` | HTTP `403 Forbidden` *(or 400 Bad Request in specification tests)*;<br>`{"error": "Execution Rejected: Process 'systemd' is a protected system service or kernel thread and cannot be terminated."}` | [ ] |
| **SEC-04** | `ExecuteCommand` on protected process (`sshd`) | `curl -i -X POST "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/ExecuteCommand" -H "Content-Type: application/json" -H "x-api-key: <YOUR_API_KEY>" -d '{"instance_id": "i-0abcdef1234567890", "pid": 842, "process_name": "sshd"}'` | HTTP `403 Forbidden`<br>`{"error": "Execution Rejected: Process 'sshd' is a protected system service or kernel thread and cannot be terminated."}` | [ ] |
| **SEC-05** | `ExecuteCommand` on unobserved PID not in recent spike | `curl -i -X POST "https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/ExecuteCommand" -H "Content-Type: application/json" -H "x-api-key: <YOUR_API_KEY>" -d '{"instance_id": "i-0abcdef1234567890", "pid": 43210, "process_name": "unknown_daemon"}'` | HTTP `403 Forbidden`<br>`{"error": "Execution Rejected: Process PID 43210 ('unknown_daemon') was not observed in recent diagnostic telemetry for server 'i-0abcdef1234567890' within the last 2 minutes."}` | [ ] |
| **SEC-06** | Wrong confirmation code keeps Terminate locked (portal UI) | In Mobile Portal Kill Dialog, input `wrong-token-99` for target PID | Confirmation text box displays `Code or name does not match`; the Terminate button remains disabled and greyed out. | [ ] |
| **SEC-07** | 1-cycle CPU spike does not attach process detail | Run `stress-ng --cpu 2 --timeout 4s` (spanning only a single 5s sampling interval) | Telemetry payload contains `cpu_percent >= 85.0`, but `top_processes` field is omitted because threshold requires `>= 2 consecutive cycles`. | [ ] |
| **SEC-08** | Audit trail shows authorized -> dispatched lifecycle | Ingest 2-cycle spike for `stress-ng`, then dispatch authorized kill command; inspect database via `psql`: `SELECT id, instance_id, pid, process_name, requested_signal, status, reason FROM kill_commands ORDER BY created_at DESC LIMIT 5;` | Table displays initial row with `status = 'authorized'`, followed immediately by updated `status = 'dispatched'` with valid `CommandId`. | [ ] |
| **SEC-09** | SSM service unavailable results in `failed_dispatch` | Dispatch `ExecuteCommand` targeting an offline/invalid instance ID: `curl -i -X POST ".../Prod/ExecuteCommand" -H "x-api-key: <YOUR_API_KEY>" -d '{"instance_id": "i-nonexistent-node", "pid": 19924, "process_name": "stress-ng"}'` | HTTP `502 Bad Gateway`<br>`{"error": "AWS SSM dispatch failed...", "status": "failed_dispatch"}`<br>Audit row updated to `status = 'failed_dispatch'`. | [ ] |

---

## 5. Testing `systemd` Crash Recovery & Fault Tolerance

1. Check active status of the non-root daemon:
   ```bash
   sudo systemctl status telemetry-agent
   ```
   Note the main Process ID (PID).
2. Simulate sudden process termination:
   ```bash
   sudo pkill -9 -f telemetry_agent
   ```
3. Check status immediately:
   ```bash
   sudo systemctl status telemetry-agent
   ```
   **Expected Result**: `systemd` detected unexpected process death, restarted the daemon under a new PID within 3 seconds (`RestartSec=3`), and resumed streaming to API Gateway without administrator intervention.

---

## 6. Synthetic Load Testing with `stress-ng`

1. Install `stress-ng` on the monitored host:
   ```bash
   sudo apt-get install -y stress-ng
   ```
2. Trigger sustained 20-second dual-core load:
   ```bash
   stress-ng --cpu 2 --timeout 20s
   ```
3. **Verification**:
   - Agent console outputs:
     ```text
     [DIAGNOSTICS] High CPU detected (98.45%). Consecutive count: 1/2
     [DIAGNOSTICS] High CPU detected (99.12%). Consecutive count: 2/2
     [DIAGNOSTICS] Spike threshold met! Attached top 3 processes to payload.
     ```
   - Mobile app displays red alert banner: `"High CPU detected — top process: stress-ng (99.12%)"` with an interactive "Kill" action button.
