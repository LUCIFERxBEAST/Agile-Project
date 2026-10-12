# 05. Guardrails & Remote Incident Remediation

This document provides a detailed breakdown of the multi-layer safety guardrail architecture, remote incident remediation path via AWS Systems Manager (SSM), signal selection mechanics, and cryptographic confirmation token implementation.

---

## 1. Remote Remediation Architecture Overview

Traditional incident remediation often relies on engineers connecting via SSH (port 22) into production servers to inspect and terminate runaway processes. This approach introduces significant security risks:
- Opening inbound port 22 expands the network attack surface.
- Distributing private SSH `.pem` keys creates credential sprawl and management overhead.
- Manual terminal sessions lack centralized, non-repudiable audit logging.

To eliminate these vulnerabilities, this system uses an **Agentless Remote Remediation** pipeline leveraging **AWS Systems Manager (SSM) Run Command** triggered from the mobile dashboard via authenticated AWS Lambda calls.

```
[Flutter Mobile Portal]
         |
         | HTTPS POST /ExecuteCommand (Header: x-api-key)
         v
[Amazon API Gateway (/Prod/ExecuteCommand)]
         |
         v
[AWS Lambda (lambda_function.py)]
         |
         +--> [Layer 1: Blocklist Check] (systemd, sshd, dockerd...)
         +--> [Layer 2: Recent Spike Telemetry Check] (<= 2 min, top_processes)
         +--> [Layer 4: Pre-Execution Audit Log] (INSERT status='authorized')
         |
         +--> [AWS SSM: send_command('AWS-RunShellScript')]
         |         |
         |         | (Outbound TLS Control Channel)
         |         v
         |    [Amazon EC2 Instance (SSM Agent)]
         |         |
         |         +--> Executes: `kill -15 <pid>` or `kill -9 <pid>`
         |
         +--> [Post-Execution Audit Log] (UPDATE status='dispatched' or 'failed_dispatch')
```

---

## 2. The 4-Layer Kill Guardrail

To prevent accidental outages, race conditions, or malicious destruction of system processes, all termination requests must pass through 4 defense layers:

### Layer 1: Protected OS Process Blocklist
- **Location**: [`backend/aws/lambda_function.py:18-30, 110-132, 359-365`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L18-L30)
- **Mechanism**: Evaluates the target executable name and basename against a hardcoded blocklist:
  ```python
  PROTECTED_PROCESS_BLOCKLIST = {
      "systemd", "init", "sshd", "dbus", "dbus-daemon",
      "networkmanager", "dockerd", "containerd", "cron",
      "rsyslogd", "telemetry_agent"
  }
  ```
  Additionally, all Linux kernel threads (commands prefixed with `[`, such as `[kthreadd]` or `[rcu_sched]`) are rejected.
- **HTTP Response**: HTTP `403 Forbidden` (`{"error": "Execution Rejected: Process ... is a protected system service or kernel thread and cannot be terminated."}`).
- **Audit Action**: Logged to `kill_commands` with `allowed = False`, `status = 'rejected'`.

### Layer 2: Scoped 2-Minute Diagnostic Telemetry Verification
- **Location**: [`backend/aws/lambda_function.py:134-177, 368-375`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L134-L177)
- **Mechanism**: Prevents blind termination of arbitrary PIDs. Lambda queries `telemetry_logs`:
  ```sql
  SELECT top_processes 
  FROM telemetry_logs 
  WHERE server_id = %s 
    AND created_at >= NOW() - INTERVAL '2 minutes' 
    AND top_processes IS NOT NULL
  ORDER BY created_at DESC;
  ```
  The requested PID and process command basename must exist in at least one diagnostic snapshot captured for that exact server within the last 2 minutes.
- **HTTP Response**: HTTP `403 Forbidden` (`{"error": "Execution Rejected: Process PID ... was not observed in recent diagnostic telemetry for server ... within the last 2 minutes."}`).
- **Audit Action**: Logged to `kill_commands` with `allowed = False`, `status = 'rejected'`.

### Layer 3: Cryptographic SHA-256 Confirmation Token
- **Location**: [`flutter mobile frontend/lib/main.dart:368-472`](file:///home/beast/Documents/Agile%20Project/flutter%20mobile%20frontend/lib/main.dart#L368-L472)
- **Mechanism**: When an operator taps "Kill" on a high CPU alert banner, Flutter generates an 8-character confirmation code:
  ```dart
  final confirmationCode = sha256
      .convert(utf8.encode('$targetInstanceId:$pid:$cmd'))
      .toString()
      .substring(0, 8);
  ```
  The modal dialog displays this code and disables the "Terminate" button until the operator enters the 8-character code (or process command/basename).
- **Security Assessment & Verified Weaknesses**:
  1. **Client-Side Enforcement Only**: The token is verified entirely inside the Flutter UI (`main.dart:431-435`). It is **not** transmitted to the `/ExecuteCommand` API payload and is **not** verified by AWS Lambda.
  2. **No Expiry or Replay Prevention**: The backend does not maintain token state; any HTTP client possessing a valid `x-api-key` header can call `POST /ExecuteCommand` directly with target PID and instance ID without supplying a token.
  *(See Phase 3 proposal for hardening options).*

### Layer 4: Centralized Database Audit Logging
- **Location**: [`backend/aws/lambda_function.py:56-99, 305-430`](file:///home/beast/Documents/Agile%20Project/backend/aws/lambda_function.py#L56-L99)
- **Mechanism**: Every remediation attempt is permanently tracked in the `kill_commands` PostgreSQL table:
  - `status = 'rejected'`: Logged when request fails input validation, blocklist check, or recent telemetry check.
  - `status = 'authorized'`: Logged immediately before dispatching the SSM Run Command request.
  - `status = 'dispatched'`: Updated once SSM responds with a valid `CommandId`.
  - `status = 'failed_dispatch'`: Updated if SSM returns a `ClientError` (e.g., instance offline, invalid IAM token) or an exception occurs.

---

## 3. Remote Execution Path: AWS SSM Run Command

When all guardrails pass, AWS Lambda dispatches the command to the target instance via the AWS SDK (`boto3`):

```python
ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "ap-southeast-2"))
response = ssm.send_command(
    InstanceIds=[instance_id_str],
    DocumentName="AWS-RunShellScript",
    Parameters={"commands": [f"kill -{signal_num} {pid_int}"]}
)
command_id = response.get("Command", {}).get("CommandId", "")
```

### IAM Role Separation
1. **EC2 Instance Role (`telemetry-ec2-ssm-role`)**:
   - Attached policy: `AmazonSSMManagedInstanceCore`.
   - Allows the local `amazon-ssm-agent` daemon to communicate outbound with the AWS Systems Manager service.
2. **Lambda Execution Role (`telemetry-lambda-role`)**:
   - Policy grants `ssm:SendCommand` restricted to instances and the `AWS-RunShellScript` SSM document:
     ```yaml
     - Effect: Allow
       Action:
         - ssm:SendCommand
       Resource:
         - !Sub "arn:aws:ec2:${AWS::Region}:${AWS::AccountId}:instance/*"
         - !Sub "arn:aws:ssm:${AWS::Region}::document/AWS-RunShellScript"
     ```

---

## 4. Signal Selection: Graceful vs Force Kill

Operators can select the termination signal in the mobile UI:

| Signal | Unix Number | Mobile Toggle | Behavior & Usage |
| :--- | :--- | :--- | :--- |
| **`SIGTERM`** | `15` | Default (Unchecked) | **Graceful Shutdown**: Informs the process to clean up resources, close network sockets, flush file buffers, and terminate cleanly. Recommended for production databases and file writers. |
| **`SIGKILL`** | `9` | "Force Kill" (Checked) | **Immediate Kernel Termination**: Cannot be caught, blocked, or ignored by the target process. Used when a runaway or malicious loop is unresponsive to `SIGTERM`. |

---

## 5. Summary Table of Guardrail Enforcement

| Check Stage | Condition | Outcome | HTTP Code | Audit Status |
| :--- | :--- | :--- | :--- | :--- |
| **Authentication** | Missing or invalid `x-api-key` header | Request rejected | 403 Forbidden | None (blocked at gateway/auth gate) |
| **Schema Validation** | Missing `instance_id`, `pid`, or `process_name` | Request rejected | 403 Forbidden | `rejected` |
| **Blocklist** | `process_name` in blocklist or kernel thread | Request rejected | 403 Forbidden | `rejected` |
| **Telemetry History** | PID not in `top_processes` within last 2 minutes | Request rejected | 403 Forbidden | `rejected` |
| **Pre-Dispatch** | All guardrails valid | Audit row created | — | `authorized` |
| **SSM Dispatch Success** | SSM returns valid `CommandId` | Execution queued | 200 OK | `dispatched` |
| **SSM Dispatch Failure** | Instance offline, invalid IAM token | Dispatch failed | 502 Bad Gateway | `failed_dispatch` |
