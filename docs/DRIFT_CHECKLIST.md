# AWS Infrastructure Drift Checklist (Read-Only)

Because several cloud resources were provisioned or configured directly in the AWS Management Console during development iterations, this read-only runbook provides exact AWS CLI commands and AWS Console steps to inspect deployed infrastructure for drift against repository definitions in `backend/aws/`.

> [!IMPORTANT]
> **Safety Rule**: Do not modify live AWS resources while executing this checklist. All commands are purely inspectable (`get-*`, `describe-*`, `\d+`). Never paste credentials or secret values into terminal outputs or logs.

---

## 1. Check 1: Deployed Lambda Code vs `backend/aws/lambda_function.py`

Verify that the live Lambda function execution package matches the local source code in `backend/aws/lambda_function.py`.

### Option A: AWS CLI Inspection
```bash
# 1. Fetch pre-signed S3 download URL for the active function code
FUNCTION_CODE_URL=$(aws lambda get-function \
  --function-name TelemetryIngestFunc \
  --region ap-southeast-2 \
  --query 'Code.Location' \
  --output text)

# 2. Download and unpack into a temporary directory
mkdir -p /tmp/deployed_lambda
curl -s "$FUNCTION_CODE_URL" -o /tmp/deployed_lambda/package.zip
unzip -q /tmp/deployed_lambda/package.zip -d /tmp/deployed_lambda/

# 3. Diff deployed lambda_function.py against local repository
diff -u backend/aws/lambda_function.py /tmp/deployed_lambda/lambda_function.py
```
- **Expected Outcome**: Zero diff (or only whitespace/formatting variations).
- **Cleanup**: `rm -rf /tmp/deployed_lambda`

### Option B: AWS Management Console
1. Navigate to **AWS Lambda** in region `ap-southeast-2`.
2. Open the function (e.g., `telemetry-stack-TelemetryFunction-...` or `TelemetryIngestFunc`).
3. Under the **Code** tab, click **Actions** -> **Download function code**.
4. Unpack the zip archive on your workstation and compare `lambda_function.py` with `backend/aws/lambda_function.py` using your local diff tool.

---

## 2. Check 2: API Gateway Routes & Stage vs `backend/aws/template.yaml`

Verify that API Gateway has all 4 routes deployed under the `/Prod` stage with API Key requirements enabled.

### Option A: AWS CLI Inspection
```bash
# 1. List REST APIs and locate the API ID
aws apigateway get-rest-apis \
  --region ap-southeast-2 \
  --query "items[?name=='TelemetryApi' || contains(name, 'telemetry')].[id, name]" \
  --output table

# 2. Inspect configured resources and HTTP methods
aws apigateway get-resources \
  --rest-api-id <YOUR_REST_API_ID> \
  --region ap-southeast-2 \
  --query "items[].[path, resourceMethods]" \
  --output table

# 3. Verify deployed stages
aws apigateway get-stages \
  --rest-api-id <YOUR_REST_API_ID> \
  --region ap-southeast-2 \
  --query "item[].[stageName, methodSettings]" \
  --output table
```
- **Expected Resources**:
  - `/IngestMetrics` -> `POST` (ApiKeyRequired: true)
  - `/GetMetrics` -> `GET` (ApiKeyRequired: true)
  - `/GetServers` -> `GET` (ApiKeyRequired: true)
  - `/ExecuteCommand` -> `POST` (ApiKeyRequired: true)
- **Expected Stage Name**: `Prod`

### Option B: AWS Management Console
1. Navigate to **Amazon API Gateway** in region `ap-southeast-2`.
2. Select your REST API (`TelemetryApi` or `telemetry-stack`).
3. In the left navigation, click **Resources**:
   - Verify the 4 routes exist: `/IngestMetrics`, `/GetMetrics`, `/GetServers`, `/ExecuteCommand`.
   - Click each method and confirm **API Key Required** is set to `true`.
4. Click **Stages**:
   - Confirm the active stage name is `Prod`.
5. Click **Usage Plans**:
   - Confirm `TelemetryUsagePlan` is associated with stage `Prod` and has an active API Key linked.

---

## 3. Check 3: Lambda Environment Variable Names vs Code

Verify that all required environment variable keys exist in Lambda configuration without logging secret values.

### Option A: AWS CLI Inspection (Keys Only)
```bash
aws lambda get-function-configuration \
  --function-name TelemetryIngestFunc \
  --region ap-southeast-2 \
  --query 'Environment.Variables' \
  --output json | jq 'keys'
```
- **Expected Keys**:
  ```json
  [
    "AWS_REGION",
    "DB_HOST",
    "DB_NAME",
    "DB_PASSWORD",
    "DB_PORT",
    "DB_USER",
    "EXPECTED_API_KEY"
  ]
  ```
  *(Note: `EXPECTED_API_KEY` is mandatory for fail-closed authentication. If missing, Lambda returns HTTP 500).*

### Option B: AWS Management Console
1. Open the Lambda function in the **AWS Console**.
2. Select the **Configuration** tab -> **Environment variables**.
3. Confirm that the list of variable names exactly matches the list above.

---

## 4. Check 4: Amazon RDS PostgreSQL Schema vs `backend/aws/schema.sql`

Verify that the live database schema contains all columns, JSONB process types, and composite indexes.

### Execution via `psql`
Connect to the database from an authorized host within the VPC:
```bash
psql -h <YOUR_RDS_ENDPOINT> -U postgres -d postgres
```

Run the following metadata commands inside the `psql` session:

```sql
-- 1. Inspect table columns and data types for telemetry_logs
\d+ telemetry_logs

-- Expected:
--   id              | integer                     | not null default nextval(...)
--   server_id       | character varying(64)       | not null
--   cpu_percent     | numeric(5,2)                | not null
--   ram_percent     | numeric(5,2)                | not null
--   ram_used_mb     | bigint                      | not null
--   ram_total_mb    | bigint                      | not null
--   timestamp       | bigint                      | 
--   created_at      | timestamp with time zone    | default CURRENT_TIMESTAMP
--   top_processes   | jsonb                       | 

-- 2. Inspect table columns for kill_commands
\d+ kill_commands

-- Expected:
--   id               | integer                     | not null default nextval(...)
--   instance_id      | character varying(64)       | not null
--   pid              | integer                     | not null
--   process_name     | text                        | not null
--   requested_signal | character varying(16)       | not null
--   allowed          | boolean                     | not null
--   status           | character varying(32)       | default 'requested'
--   reason           | text                        | 
--   created_at       | timestamp with time zone    | default CURRENT_TIMESTAMP

-- 3. Verify all performance & audit indexes
\di+ idx_*

-- Expected Indexes:
--   idx_telemetry_server_created    ON telemetry_logs (server_id, created_at DESC)
--   idx_telemetry_created_at        ON telemetry_logs (created_at DESC)
--   idx_kill_commands_server_created ON kill_commands (instance_id, created_at DESC)
--   idx_kill_commands_created_at    ON kill_commands (created_at DESC)
```

---

## 5. Drift Reconciliation Protocol

If drift is detected during any check above:
1. **Lambda Code Drift**: Re-package using `backend/aws/deploy_aws.sh` or `sam build && sam deploy` to synchronize the deployed package with git.
2. **Missing Schema Elements**: If `top_processes JSONB` or composite index `idx_telemetry_server_created` is absent, execute `backend/aws/schema.sql` idempotently against the database:
   ```bash
   psql -h <YOUR_RDS_ENDPOINT> -U postgres -d postgres -f backend/aws/schema.sql
   ```
3. **Missing Environment Variables**: Add missing key names via the Lambda Configuration console or AWS CLI without storing secrets in plaintext scripts.
