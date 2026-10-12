# 03. Testing & Verification Protocols

This document outlines testing methodologies and verification procedures to ensure every layer of the monitoring pipeline operates correctly, reliably, and with fault tolerance.

---

## 1. Local C++ Unit & Metric Accuracy Testing

### 1.1 Validating Kernel Metric Parsing
Compare the telemetry agent's CPU and RAM values with Linux kernel diagnostic utilities:
```bash
# Run top or htop in one terminal:
top

# Run telemetry agent in another terminal:
./telemetry_agent
```
- **CPU Check**: Confirm that `cpu_percent` corresponds to `100 - %id` in `top`.
- **Memory Check**: Inspect `/proc/meminfo` directly:
  ```bash
  grep -E 'MemTotal|MemAvailable' /proc/meminfo
  ```
  Confirm `ram_used_mb` matches `(MemTotal - MemAvailable) / 1024`.

---

## 2. Testing Future Scope #1: Offline Queue & Auto-Retry

The agent is designed to cache metric payloads locally in `offline_queue.jsonl` if cloud connectivity drops, and automatically flush them when connection recovers.

### 2.1 Test Procedure
1. **Simulate Network Failure**:
   Run the agent with an unreachable endpoint:
   ```bash
   export TELEMETRY_API_URL="http://127.0.0.1:9999/IngestMetrics"
   ./telemetry_agent
   ```
2. **Observe Caching**:
   After 2 cycles (approx. 10 seconds), notice console messages:
   ```text
   [ERROR] curl_easy_perform() failed: Couldn't connect to server
   [OFFLINE QUEUE] Saved payload locally to offline_queue.jsonl
   ```
3. **Verify File Contents**:
   Stop the agent and inspect `offline_queue.jsonl`:
   ```bash
   cat offline_queue.jsonl
   ```
   You will see persistent JSON lines for every failed metric transmission.

4. **Simulate Connection Recovery**:
   Set `TELEMETRY_API_URL` back to your valid AWS endpoint (or a mock HTTP receiver):
   ```bash
   export TELEMETRY_API_URL="https://<api-id>.execute-api.<region>.amazonaws.com/IngestMetrics"
   ./telemetry_agent
   ```
5. **Observe Auto-Retry Flush**:
   ```text
   [AUTO-RETRY] Attempting to flush 2 queued metric(s)...
   [SUCCESS] Payload sent to https://... (HTTP 200)
   [SUCCESS] Payload sent to https://... (HTTP 200)
   [AUTO-RETRY] Successfully flushed all queued metrics! Queue cleared.
   ```
   Confirm that `offline_queue.jsonl` is emptied/deleted once all queued payloads are delivered.

---

## 3. Testing AWS Cloud Ingestion & Query Endpoints

You can validate the AWS API Gateway endpoints using standard `curl` commands.

### 3.1 Test Ingestion Endpoint (`POST /IngestMetrics`)
```bash
curl -X POST "https://<api-id>.execute-api.<region>.amazonaws.com/IngestMetrics" \
  -H "Content-Type: application/json" \
  -d '{
    "server_id": "test-ec2",
    "cpu_percent": 12.5,
    "ram_percent": 45.2,
    "ram_used_mb": 4096,
    "ram_total_mb": 8192,
    "timestamp": 1788749100
  }'
```
**Expected Response**:
```json
{"message": "Metric ingested successfully"}
```

### 3.2 Test Retrieval Endpoint (`GET /GetMetrics`)
```bash
curl -X GET "https://<api-id>.execute-api.<region>.amazonaws.com/GetMetrics"
```
**Expected Response**:
A JSON array containing the most recent 20 telemetry records:
```json
[
  {
    "server_id": "test-ec2",
    "cpu_percent": 12.5,
    "ram_percent": 45.2,
    "ram_used_mb": 4096,
    "ram_total_mb": 8192,
    "created_at": "2026-09-16 11:20:00+00"
  }
]
```

### 3.3 Validate Database Records (SQL Query)
Connect to Amazon RDS via `psql` to verify row insertion:
```bash
psql -h <rds-endpoint> -U postgres -d postgres -c "SELECT * FROM telemetry_logs ORDER BY created_at DESC LIMIT 5;"
```

---

## 4. Testing systemd Crash Recovery & Fault Tolerance

The system requirement states the agent must be managed as a system service that auto-recovers from crashes.

1. Verify the service is running:
   ```bash
   sudo systemctl status telemetry-agent
   ```
   Note the Process ID (PID).
2. Deliberately simulate a crash:
   ```bash
   sudo pkill -9 -f telemetry_agent
   ```
3. Check status immediately:
   ```bash
   sudo systemctl status telemetry-agent
   ```
   **Expected Result**: `systemd` detected the kill signal, immediately restarted the binary under a new PID within 3 seconds (`RestartSec=3`), and resumed streaming without human intervention.

---

## 5. Synthetic Load Testing with `stress-ng`

To demonstrate dynamic real-time visualization on the Flutter mobile dashboard during a performance spike:

1. Install `stress-ng`:
   ```bash
   sudo apt-get install -y stress-ng
   ```
2. Run a 30-second CPU spike:
   ```bash
   stress-ng --cpu 2 --timeout 30s
   ```
3. **Observe Mobile Dashboard**:
   Watch the CPU utilization curve (Cyan line) dynamically climb from baseline (~5%) to near 100% on the chart, and settle back down after 30 seconds.
