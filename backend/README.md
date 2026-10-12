# Cloud-Native Linux Telemetry & Infrastructure Monitoring System

A lightweight, high-frequency infrastructure telemetry engine engineered in C++ that extracts kernel-level metrics directly from the Linux `/proc` virtual filesystem[cite: 1]. The architecture implements a dual-path pipeline separating sub-second real-time streaming (Hot Path) from batched serverless storage (Cold Path) via AWS Lambda and Amazon RDS PostgreSQL, visualized through a cross-platform Flutter dashboard[cite: 1].

---

## Project Roadmap & Task Checklist

### Phase 1: Core Telemetry Engine & Local Systems Programming

- [ ] **1.1 Development Environment & Setup**
  - [ ] Initialize Git repository (`git init`) and set up `.gitignore` (build targets, `.o`, `.env`, binary outputs).
  - [ ] Configure project directory structure (`src/`, `include/`, `scripts/`, `config/`).
  - [ ] Install required build toolchains and dependencies (`g++`, `cmake`, `libcurl`, `nlohmann-json`).

- [ ] **1.2 Kernel `/proc` Parsing Engine (C++)**
  - [ ] Implement file reader for `/proc/stat` to extract CPU tick states (`user`, `nice`, `system`, `idle`, `iowait`, `irq`, `softirq`, `steal`)[cite: 1].
  - [ ] Implement delta computation logic across consecutive intervals to calculate real-time CPU utilization percentage.
  - [ ] Implement line-by-line parser for `/proc/meminfo` to extract `MemTotal`, `MemFree`, `Buffers`, and `Cached`[cite: 1].
  - [ ] Compute exact used memory and percentage utilization.

- [ ] **1.3 Precision Timing & JSON Serialization**
  - [ ] Implement steady sampling loop using `std::chrono::steady_clock` to enforce exact 1000 ms intervals without drift.
  - [ ] Format sampled metrics into structured JSON payloads using `nlohmann/json`.
  - [ ] Validate local agent performance using `g++ -O2 -std=c++17` and compare outputs against `htop`/`top`.

---

### Phase 2: Cloud Infrastructure & Database Setup (AWS)

- [ ] **2.1 Target Instance & Daemonization**
  - [ ] Provision target Amazon EC2 Linux instance (`t2.micro`/`t3.micro`)[cite: 1].
  - [ ] Configure EC2 Security Groups (SSH port 22 inbound, HTTPS outbound).
  - [ ] Write systemd service configuration (`/etc/systemd/system/telemetry-agent.service`) with `Restart=always` for automated crash recovery[cite: 1].
  - [ ] Enable and start the system daemon via `systemctl`[cite: 1].
  - [ ] Verify automated recovery by killing the process (`pkill -9 telemetry_agent`)[cite: 1].

- [ ] **2.2 Cold-Path Relational Storage (Amazon RDS)**
  - [ ] Provision Amazon RDS PostgreSQL instance on Free Tier[cite: 1].
  - [ ] Configure Security Groups to allow inbound PostgreSQL traffic (port 5432) from the ingestion Lambda function.
  - [ ] Initialize schema and time-series indexes:
    ```sql
    CREATE TABLE system_metrics (
        id BIGSERIAL PRIMARY KEY,
        server_id VARCHAR(64) NOT NULL,
        recorded_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
        cpu_avg REAL NOT NULL,
        cpu_max REAL NOT NULL,
        ram_percent REAL NOT NULL,
        ram_used_mb INT NOT NULL
    );
    CREATE INDEX idx_metrics_recorded_at ON system_metrics(recorded_at DESC);
    ```

---

### Phase 3: Dual-Path Ingestion Pipeline (Hot & Cold Path)

- [ ] **3.1 Cold Path: Micro-Batching & Serverless Ingestion**
  - [ ] Implement in-memory metric buffer in C++ to accumulate 30–60 one-second samples.
  - [ ] Compute statistical aggregates (average CPU, max CPU spike, current RAM) per batch.
  - [ ] Integrate `libcurl` to dispatch HTTPS POST payloads to API Gateway.
  - [ ] Author AWS Lambda ingestion function (Python/Node.js) to parse incoming JSON payloads[cite: 1].
  - [ ] Implement parameterized SQL write operations to persist batch records into RDS PostgreSQL[cite: 1].
  - [ ] Deploy Amazon API Gateway HTTP REST endpoint (`POST /telemetry/metrics`) integrated with the ingestion Lambda[cite: 1].
  - [ ] Deploy query endpoint (`GET /telemetry/history?range=1h`) for on-demand historical queries from the mobile app.

- [ ] **3.2 Hot Path: Sub-Second Live Streaming**
  - [ ] Configure streaming protocol layer (AWS IoT Core MQTT broker or a lightweight WebSocket server on EC2).
  - [ ] Hook C++ engine to publish instantaneous 1-second metric frames to the real-time channel.

---

### Phase 4: Cross-Platform Mobile Dashboard (Flutter)

- [ ] **4.1 Architecture & Interface Design**
  - [ ] Initialize Flutter mobile application repository (`flutter create telemetry_dashboard`)[cite: 1].
  - [ ] Add visualization dependencies (`fl_chart`, `web_socket_channel`/`mqtt_client`, `http`, `intl`).
  - [ ] Build core UI views:
    - [ ] **System Status Card:** Hostname, uptime indicator, heartbeat status.
    - [ ] **Live Gauges:** Real-time radial CPU and RAM utilization meters.
    - [ ] **Rolling Window Line Chart:** 60-second sliding real-time performance graph.
    - [ ] **Historical Analytics:** Historical line chart with multi-range toggle (1h / 6h / 24h).

- [ ] **4.2 Data Layer & State Management**
  - [ ] Implement persistent stream listener to ingest live Hot Path metrics directly into UI state.
  - [ ] Implement REST client to fetch initial historical trend records from API Gateway on application startup.
  - [ ] Add automated reconnect and network loss indicator badges.

---

### Phase 5: Incident Orchestration & Diagnostics (Stretch Goals)

- [ ] **5.1 Edge Caching & Auto-Retry**
  - [ ] Implement local disk queue (SQLite / append-only write log) on the EC2 instance[cite: 1].
  - [ ] Buffer metric payloads to local disk during network interruptions[cite: 1].
  - [ ] Build background retry thread to automatically flush offline data to API Gateway once connection restores[cite: 1].

- [ ] **5.2 Process-Level Diagnostic Engine**
  - [ ] Implement `/proc/[pid]/stat` and `/proc/[pid]/cmdline` scanner in C++[cite: 1].
  - [ ] Configure automatic anomaly trigger: capture top resource-consuming PIDs when CPU utilization exceeds 85% for 3 consecutive samples[cite: 1].
  - [ ] Attach process diagnostic snapshots to metric payloads for root-cause inspection[cite: 1].

- [ ] **5.3 Two-Way Remote Command Channel**
  - [ ] Build command execution pathway via AWS Systems Manager (SSM) or bidirectional socket connection[cite: 1].
  - [ ] Add interactive management controls to Flutter UI (Kill Rogue Process / Restart System Service)[cite: 1].
  - [ ] Connect mobile actions to dispatch remote management signals to the EC2 target instance[cite: 1].

---

### Phase 6: System Validation & Benchmarking

- [ ] Execute synthetic CPU load testing on EC2 using `stress-ng` (`stress-ng --cpu 2 --timeout 30s`).
- [ ] Measure and record sub-second telemetry propagation delay on the Flutter live graph.
- [ ] Confirm long-term aggregate persistence in Amazon RDS PostgreSQL.
- [ ] Profile the C++ agent binary to confirm resident memory footprint remains under 10MB.