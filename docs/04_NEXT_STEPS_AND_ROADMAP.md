# 04. Next Steps & Implementation Roadmap

This document outlines the exact sequential action plan for **what you need to do next**, followed by the roadmap for implementing the remaining future scope features.

---

## 🎯 Phase 1: Immediate Action Checklist (Getting Everything Live)

Follow this step-by-step checklist to deploy and demonstrate the live AWS pipeline:

### Step 1: Set Up AWS Free Tier Resources
- [ ] Create an AWS Account (if you don't already have one).
- [ ] Launch an **Amazon RDS PostgreSQL** instance on the Free Tier (`db.t3.micro` or `db.t4g.micro`).
- [ ] Ensure the RDS security group allows inbound traffic on port `5432`.
- [ ] Connect with `psql` and execute [`backend/aws/schema.sql`](file:///home/beast/Documents/Software%20Testing/Agile%20Project/backend/aws/schema.sql).

### Step 2: Deploy AWS Serverless Backend
- [ ] Configure AWS CLI on your system:
  ```bash
  aws configure
  ```
- [ ] Deploy via AWS SAM:
  ```bash
  cd "backend/aws"
  sam build
  sam deploy --guided
  ```
- [ ] Provide your RDS credentials when prompted.
- [ ] Copy the generated API Gateway endpoints (`IngestMetricsApiEndpoint` and `GetMetricsApiEndpoint`).

### Step 3: Run the Telemetry Agent
- [ ] On your Linux machine or an Amazon EC2 Linux instance:
  ```bash
  cd "backend/src"
  g++ -O2 -std=c++17 utility.cpp -o telemetry_agent -lcurl
  export TELEMETRY_API_URL="<your-IngestMetricsApiEndpoint>"
  ./telemetry_agent
  ```
- [ ] Set up the `systemd` service (`telemetry-agent.service`) so it runs continuously in the background and recovers automatically on crashes.

### Step 4: Run the Flutter Mobile App
- [ ] Open [`flutter mobile frontend/lib/main.dart`](file:///home/beast/Documents/Software%20Testing/Agile%20Project/flutter%20mobile%20frontend/lib/main.dart#L35).
- [ ] Paste your `GetMetricsApiEndpoint` into line 35.
- [ ] Run the mobile dashboard:
  ```bash
  cd "flutter mobile frontend"
  flutter run
  ```
- [ ] Confirm the live CPU and RAM charts render the metrics sent by the C++ agent.

---

## 🚀 Phase 2: Implementing Remaining Future Scope Features

In Review 1, the end-to-end pipeline was completed, and we have now implemented **Future Scope #1 (Offline Queue & Auto-Retry)**. The remaining future scope features from your proposal document are detailed below:

### 1. Future Scope #2: Process-Level Diagnostics
- **Objective**: Capture top resource-consuming task snapshots for root-cause analysis during performance spikes.
- **How to Implement**:
  - In `backend/src/utility.cpp`, add a trigger condition: when `cpuInUse > 85.0%` for 2 consecutive cycles.
  - Read `/proc` directory entries for numeric PIDs (`/proc/[pid]/stat` and `/proc/[pid]/cmdline`).
  - Sort processes by CPU time consumed.
  - Append the top 3 rogue processes (`pid`, `process_name`, `%cpu`) into the JSON payload:
    ```json
    "top_processes": [
      {"pid": 1284, "cmd": "stress-ng-cpu", "cpu": 78.4},
      {"pid": 941,  "cmd": "node",          "cpu": 12.1}
    ]
    ```
  - Store this diagnostic snapshot in RDS and display a warning banner on the Flutter dashboard.

### 2. Future Scope #3: Remote Incident Orchestration (Two-Way Command Channel)
- **Objective**: Enable remote incident remediation from the mobile dashboard (e.g., kill a rogue process or restart a system service).
- **How to Implement**:
  - Create a new API Gateway endpoint `POST /ExecuteCommand`.
  - Use AWS Systems Manager (SSM) Run Command or an AWS IoT Core MQTT command topic.
  - On the Flutter app, add an action button next to high-CPU processes: **[Kill Process]**.
  - Tapping the button dispatches an authorized command to terminate the rogue PID on the EC2 instance.

### 3. Future Scope #4: Security Hardening
- **Objective**: Add authenticated ingestion, encryption in transit, and least-privilege access controls.
- **How to Implement**:
  - Add AWS API Gateway API Key or Lambda Authorizer to `/IngestMetrics` and `/GetMetrics`.
  - Pass the API Key in the C++ agent HTTP header:
    ```cpp
    headers = curl_slist_append(headers, "x-api-key: YOUR_SECRET_KEY");
    ```
  - Integrate AWS Cognito or Firebase Auth in the Flutter mobile application so only authenticated engineers can view the metrics dashboard.

### 4. Future Scope #5: Scaling to Multiple Monitored Servers
- **Objective**: Extend system design to handle multiple servers concurrently.
- **How to Implement**:
  - Each agent generates or reads its distinct hostname/instance ID (e.g., `ec2-server-prod-01`, `ec2-server-db-02`).
  - In the Flutter dashboard, add a server dropdown selector in the AppBar (`DropdownButton<String>`).
  - Selecting a server filters the line charts to visualize metrics specifically for that server instance.

---

## 🎤 Phase 3: Project Presentation & Viva Defense Tips

When presenting this project for your Agile & DevOps course review:

1. **Highlight the Systems Engineering Depth**:
   - Explain *why* reading `/proc/stat` and `/proc/meminfo` natively in C++ is superior to invoking shell commands (`exec("top")`). C++ eliminates process fork overhead, context switches, and keeps memory footprint under 10 MB.
2. **Demonstrate Fault Tolerance (Future Scope 1)**:
   - Disconnect the network (or point to an invalid URL), show that metrics are safely cached into `offline_queue.jsonl`.
   - Restore the network and show the agent automatically flushing the queued data to AWS without losing a single data point.
3. **Demonstrate Automated Recovery (systemd)**:
   - Run `sudo pkill -9 telemetry_agent` in front of the reviewer and show `systemctl status` immediately displaying an active restarted process.
4. **Demonstrate Real-Time Load Reaction**:
   - Run `stress-ng --cpu 2 --timeout 30s` on the server and watch the Flutter graph spike live.
