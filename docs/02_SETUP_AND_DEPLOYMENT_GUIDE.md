# 02. Setup & Deployment Guide

This guide provides step-by-step instructions to configure, deploy, and execute the entire monitoring system across AWS, the Linux agent host, and the Flutter mobile client.

---

## 1. Prerequisites

Make sure you have the following installed on your machine / server:
- **C++ Compiler & Libs**: `g++` (C++17 support), `libcurl4-openssl-dev`, `nlohmann-json3-dev`
- **AWS Tools**: AWS CLI (`aws configure`) and AWS SAM CLI (`sam --version`)
- **Database Tools**: PostgreSQL client (`psql`)
- **Mobile Development**: Flutter SDK (3.x+), Android Studio or Xcode (if targeting iOS)

```bash
# On Ubuntu / Debian / EC2 Amazon Linux:
sudo apt-get update
sudo apt-get install -y build-essential libcurl4-openssl-dev nlohmann-json3-dev postgresql-client
```

---

## 2. Step 1: Provision Amazon RDS (PostgreSQL Database)

1. **Log in to the AWS Management Console** and navigate to **Amazon RDS**.
2. Click **Create database**:
   - Choose a database creation method: **Standard create**
   - Engine type: **PostgreSQL**
   - Template: **Free tier**
   - DB instance identifier: `telemetry-db`
   - Master username: `postgres`
   - Master password: `<YOUR_DB_PASSWORD>` (record this safely)
   - Instance configuration: `db.t3.micro` or `db.t4g.micro`
   - Public access: **Yes** (or place inside the same VPC / Security Group as your Lambda)
3. **Configure Security Group**:
   - Under VPC Security Groups, add an **Inbound Rule**:
     - Type: `PostgreSQL`
     - Port Range: `5432`
     - Source: `0.0.0.0/0` (or restricted to your Lambda Security Group IP range for production)
4. **Initialize Table Schema**:
   Once the database status turns to **Available**, obtain the **Endpoint** address and initialize the schema:
   ```bash
   psql -h <your-rds-endpoint>.amazonaws.com -U postgres -d postgres -f "backend/aws/schema.sql"
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
   During guided prompts, enter:
   - **Stack Name**: `telemetry-stack`
   - **AWS Region**: your preferred region (e.g. `ap-south-1` or `us-east-1`)
   - **Parameter DBHost**: `<your-rds-endpoint>.amazonaws.com`
   - **Parameter DBName**: `postgres`
   - **Parameter DBUser**: `postgres`
   - **Parameter DBPassword**: `<your-rds-password>`
   - **Parameter DBPort**: `5432`
   - Allow SAM CLI to create IAM roles: `Y`

3. Once deployed, SAM CLI will display the **Outputs**:
   ```
   Outputs:
   IngestMetricsApiEndpoint: https://<api-id>.execute-api.<region>.amazonaws.com/IngestMetrics
   GetMetricsApiEndpoint:    https://<api-id>.execute-api.<region>.amazonaws.com/GetMetrics
   ```
   Save these two URLs!

### Option B: Manual Packaging & Deployment Script

If you prefer deploying the Lambda zip manually via the AWS Console:
```bash
cd "backend/aws"
chmod +x deploy_aws.sh
./deploy_aws.sh
```
This script creates `deployment_package.zip` with `psycopg2-binary` bundled. You can upload it to your AWS Lambda function in the console and set your Environment Variables (`DB_HOST`, `DB_NAME`, `DB_USER`, `DB_PASSWORD`, `DB_PORT`).

---

## 4. Step 3: Configure & Run C++ Telemetry Agent

The C++ agent can run on any Linux host (Amazon EC2 instance or local Linux environment).

### 4.1 Compile the Binary
```bash
cd "backend/src"
g++ -O2 -std=c++17 utility.cpp -o telemetry_agent -lcurl
```

### 4.2 Test Run in Foreground
Pass your AWS API Gateway Ingest URL via the environment variable:
```bash
export TELEMETRY_API_URL="https://<api-id>.execute-api.<region>.amazonaws.com/Prod/IngestMetrics"
export TELEMETRY_API_KEY="your_telemetry_api_key_here"
./telemetry_agent
```
You will see output indicating metrics sampled and transmitted:
```text
[INIT] Telemetry Agent targeting endpoint: https://.../IngestMetrics
Generated Payload: {"cpu_percent":4.21,"ram_percent":68.4,"ram_total_mb":15598,"ram_used_mb":10669,"server_id":"beast","timestamp":1788749000}
[SUCCESS] Payload sent to https://... (HTTP 200)
```

### 4.3 Configure Persistent `systemd` Service (Daemon with Auto-Recovery)

To ensure the agent runs permanently in the background and restarts automatically if it crashes or the server reboots:

1. Create a service unit file `/etc/systemd/system/telemetry-agent.service`:
   ```ini
   [Unit]
   Description=Cloud-Native C++ Telemetry Agent
   After=network.target

   [Service]
   Type=simple
   User=root
   WorkingDirectory=/home/ubuntu/telemetry_agent_dir
   Environment="TELEMETRY_API_URL=https://<api-id>.execute-api.<region>.amazonaws.com/Prod/IngestMetrics"
   Environment="TELEMETRY_API_KEY=your_telemetry_api_key_here"
   ExecStart=/home/ubuntu/telemetry_agent_dir/telemetry_agent
   Restart=always
   RestartSec=3

   [Install]
   WantedBy=multi-user.target
   ```

2. Reload systemd and enable the service:
   ```bash
   sudo systemctl daemon-reload
   sudo systemctl enable telemetry-agent
   sudo systemctl start telemetry-agent
   ```

3. Check status:
   ```bash
   sudo systemctl status telemetry-agent
   ```

---

## 5. Step 4: Configure & Run Flutter Mobile App

1. Open `flutter mobile frontend/lib/main.dart`.
2. Locate line 35 and replace `apiUrl` with your live AWS `GetMetrics` endpoint:
   ```dart
   final String apiUrl =
       "https://<your-api-id>.execute-api.<your-region>.amazonaws.com/GetMetrics";
   ```

3. Run the application:
   ```bash
   cd "flutter mobile frontend"
   flutter pub get
   flutter run
   ```
   (You can run on an Android emulator, connected phone, or Linux desktop via `flutter run -d linux`).
