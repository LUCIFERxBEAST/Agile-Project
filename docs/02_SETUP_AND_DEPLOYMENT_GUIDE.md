# 02. Setup & Deployment Guide

This guide provides step-by-step instructions to configure, deploy, and execute the entire monitoring system across AWS, the monitored Linux EC2 host, and the Flutter mobile client.

---

## 1. Prerequisites

Ensure you have the following installed on your administrative workstation and agent host:
- **C++ Compiler & Libs**: `g++` (C++17 support), `libcurl4-openssl-dev`, `nlohmann-json3-dev`
- **AWS Tools**: AWS CLI (`aws configure`) and AWS SAM CLI (`sam --version`)
- **Database Tools**: PostgreSQL client (`psql`)
- **Mobile Development**: Flutter SDK (3.x+), Android Studio, or Linux desktop dev tools (`clang`, `cmake`, `gtk+-3.0`)

```bash
# On Ubuntu / Debian / EC2 Amazon Linux:
sudo apt-get update
sudo apt-get install -y build-essential libcurl4-openssl-dev nlohmann-json3-dev postgresql-client
```

---

## 2. Step 1: Provision Amazon RDS (PostgreSQL Database)

1. **Log in to AWS Console** and navigate to **Amazon RDS** in region **`ap-southeast-2`** (Sydney).
2. Click **Create database**:
   - Choose a database creation method: **Standard create**
   - Engine type: **PostgreSQL**
   - Engine version: **PostgreSQL 16 (as deployed)**
   - Template: **Free tier**
   - DB instance identifier: `telemetry-db`
   - Master username: `postgres`
   - Master password: `<YOUR_DB_PASSWORD>` (generate a strong password and record it safely in a secrets manager)
   - Instance configuration: **`db.t4g.micro`** (or `db.t3.micro` if Graviton is unavailable in your AZ)
   - Storage: 20 GiB General Purpose SSD (gp2/gp3)
3. **VPC & Network Security Architecture**:
   - **Publicly Accessible**: **No** (Do NOT expose RDS port 5432 to `0.0.0.0/0`).
   - Place RDS in private database subnets within your VPC.
   - Attach an RDS Security Group (`telemetry-rds-sg`) with an **Inbound Rule**:
     - Type: `PostgreSQL`
     - Port: `5432`
     - Source: Restricted to the **Lambda Security Group ID** (`telemetry-lambda-sg`).
   - *VPC Note for Lambda*: To communicate directly with a private RDS instance, the AWS Lambda function must be configured with VPC Access (attached to private subnets with execution policy `AWSLambdaVPCAccessExecutionRole`). Ensure a VPC Endpoint or NAT Gateway is configured if Lambda requires outbound access to AWS SSM and CloudWatch APIs.
4. **Initialize Table Schema**:
   From a bastion host or an authorized management instance within the VPC:
   ```bash
   psql -h <YOUR_RDS_ENDPOINT> -U postgres -d postgres -f "backend/aws/schema.sql"
   ```

---

## 3. Step 2: Deploy AWS Lambda & API Gateway

All deployment files reside in `backend/aws/`.

### Option A: Automated Deployment via AWS SAM (Recommended)

1. Build and package dependencies:
   ```bash
   cd "backend/aws"
   sam build
   ```

2. Deploy the serverless stack:
   ```bash
   sam deploy --guided
   ```
   During guided prompts, provide:
   - **Stack Name**: `telemetry-stack`
   - **AWS Region**: `ap-southeast-2`
   - **Parameter DBHost**: `<YOUR_RDS_ENDPOINT>`
   - **Parameter DBName**: `postgres`
   - **Parameter DBUser**: `postgres`
   - **Parameter DBPassword**: `<YOUR_DB_PASSWORD>`
   - **Parameter DBPort**: `5432`
   - **Parameter ExpectedApiKey**: `<YOUR_API_KEY>`
   - Allow SAM CLI to create IAM roles: `Y`

3. Once deployed, SAM CLI outputs the live `/Prod` endpoints and API Key ID:
   ```text
   Outputs:
   IngestMetricsApiEndpoint:  https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics
   GetMetricsApiEndpoint:     https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/GetMetrics
   ExecuteCommandApiEndpoint: https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/ExecuteCommand
   ApiKeyId:                  <api-key-id>
   ```

---

## 4. Step 3: Configure & Run C++ Telemetry Agent

The C++ agent runs on Amazon EC2 (`t3.micro`, `ap-southeast-2`) running Ubuntu 24.04 LTS or Amazon Linux 2023.

### 4.1 Compile the Binary
```bash
cd "backend/src"
g++ -O2 -std=c++17 utility.cpp -o telemetry_agent -lcurl
```

### 4.2 Foreground Test Run
Test connectivity by setting the required environment variables:
```bash
export TELEMETRY_API_URL="https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics"
export TELEMETRY_API_KEY="<YOUR_API_KEY>"
./telemetry_agent
```
Output:
```text
[INIT] Server Identity (server_id): i-0abcdef1234567890
[INIT] Telemetry Agent targeting endpoint: https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics
[AUTH] API Key loaded from TELEMETRY_API_KEY (x-api-key header enabled).
Generated Payload: {"cpu_percent":4.21,"ram_percent":68.4,"ram_total_mb":1024,"ram_used_mb":438,"server_id":"i-0abcdef1234567890","timestamp":1790982052}
[SUCCESS] Payload sent to https://... (HTTP 200)
```

### 4.3 Configure Persistent `systemd` Service (Hardened Non-Root Daemon)

The agent does **not** require `root` privileges. On standard Linux systems without `hidepid` mount restrictions, `/proc/stat`, `/proc/meminfo`, and `/proc/[pid]/cmdline` are world-readable (`0444`). Running under a dedicated, unprivileged service account adheres to the principle of least privilege.

1. **Create dedicated service user**:
   ```bash
   sudo useradd -r -s /bin/false telemetry
   ```

2. **Prepare directory & copy binary**:
   ```bash
   sudo mkdir -p /opt/telemetry-agent
   sudo cp backend/src/telemetry_agent /opt/telemetry-agent/
   sudo chown -R telemetry:telemetry /opt/telemetry-agent
   sudo chmod 750 /opt/telemetry-agent/telemetry_agent
   ```

3. **Secure Environment File (`mode 600`)**:
   Store sensitive API credentials in `/etc/telemetry-agent/telemetry-agent.env`:
   ```bash
   sudo mkdir -p /etc/telemetry-agent
   sudo tee /etc/telemetry-agent/telemetry-agent.env > /dev/null << 'EOF'
   TELEMETRY_API_URL=https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod/IngestMetrics
   TELEMETRY_API_KEY=<YOUR_API_KEY>
   EOF
   sudo chown root:telemetry /etc/telemetry-agent/telemetry-agent.env
   sudo chmod 600 /etc/telemetry-agent/telemetry-agent.env
   ```

4. **Install Unit File**:
   Copy template from `backend/deploy/telemetry-agent.service` to `/etc/systemd/system/telemetry-agent.service`:
   ```ini
   [Unit]
   Description=Cloud-Native C++ Telemetry Agent Daemon
   After=network.target

   [Service]
   Type=simple
   User=telemetry
   Group=telemetry
   WorkingDirectory=/opt/telemetry-agent
   EnvironmentFile=/etc/telemetry-agent/telemetry-agent.env
   ExecStart=/opt/telemetry-agent/telemetry_agent
   Restart=always
   RestartSec=3

   # Linux Process & Filesystem Security Sandbox
   ProtectSystem=strict
   ProtectHome=read-only
   ReadWritePaths=/opt/telemetry-agent
   PrivateTmp=true
   NoNewPrivileges=true

   [Install]
   WantedBy=multi-user.target
   ```

5. **Enable and start the service**:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable --now telemetry-agent
   sudo systemctl status telemetry-agent
   ```

---

## 5. Step 4: Configure & Run Flutter Mobile Portal

The mobile portal connects to API Gateway using compile-time environment flags or through an in-memory credential gate on launch.

### 5.1 Build Configuration (`--dart-define`)
You do not need to hardcode URLs in source code. Pass the base API Gateway URL (`/Prod` included) and optional build-time key:
```bash
cd "flutter mobile frontend"
flutter pub get

# Run with custom parameters:
flutter run \
  --dart-define=API_BASE_URL="https://<api-id>.execute-api.ap-southeast-2.amazonaws.com/Prod" \
  --dart-define=API_KEY="<YOUR_API_KEY>"
```

### 5.2 Interactive Login Gate
If launched without `--dart-define=API_KEY`, the mobile app displays the `LoginScreen`. Enter your API Key into the secured input field. The key is retained strictly in-memory during the session (never cached to plaintext storage) and transmitted in the `x-api-key` header on all telemetry and remediation requests.
