import os
import json
import logging
import boto3
from botocore.exceptions import ClientError

try:
    import psycopg2
except ImportError:
    psycopg2 = None

logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Fail closed: EXPECTED_API_KEY must be explicitly supplied in the environment.
EXPECTED_API_KEY = os.environ.get("EXPECTED_API_KEY")

PROTECTED_PROCESS_BLOCKLIST = {
    "systemd",
    "init",
    "sshd",
    "dbus",
    "dbus-daemon",
    "networkmanager",
    "dockerd",
    "containerd",
    "cron",
    "rsyslogd",
    "telemetry_agent"
}

def get_db_connection():
    if psycopg2 is None:
        raise RuntimeError("psycopg2 module not available")
    return psycopg2.connect(
        host=os.environ.get("DB_HOST"),
        database=os.environ.get("DB_NAME", "postgres"),
        user=os.environ.get("DB_USER"),
        password=os.environ.get("DB_PASSWORD"),
        port=os.environ.get("DB_PORT", "5432"),
        connect_timeout=5
    )

def _get_cors_headers():
    return {
        "Content-Type": "application/json",
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers": "Content-Type,X-Api-Key,x-api-key,Authorization,X-Amz-Date",
        "Access-Control-Allow-Methods": "GET,POST,OPTIONS"
    }

def log_kill_command(instance_id, pid, process_name, requested_signal, allowed, reason, status="rejected"):
    """
    Audit logging for all remote kill command attempts (both allowed and rejected).
    Returns the primary key ID of the inserted audit record.
    """
    audit_id = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            INSERT INTO kill_commands (instance_id, pid, process_name, requested_signal, allowed, status, reason)
            VALUES (%s, %s, %s, %s, %s, %s, %s)
            RETURNING id;
        """, (
            str(instance_id) if instance_id else "unknown",
            pid if isinstance(pid, int) else 0,
            str(process_name) if process_name else "unknown",
            str(requested_signal),
            bool(allowed),
            str(status),
            str(reason)
        ))
        row = cur.fetchone()
        if row:
            audit_id = row[0]
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Failed to record audit log to kill_commands: {e}")
    return audit_id

def update_kill_command(audit_id, status, reason):
    """
    Updates the existing audit row once downstream SSM execution resolves.
    """
    if not audit_id:
        return
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute("""
            UPDATE kill_commands 
            SET status = %s, reason = %s 
            WHERE id = %s;
        """, (str(status), str(reason), audit_id))
        conn.commit()
        cur.close()
        conn.close()
    except Exception as e:
        logger.error(f"Failed to update audit row {audit_id}: {e}")

def is_process_blocked(process_name: str) -> bool:
    if not process_name:
        return True
    trimmed = process_name.strip()
    if trimmed.startswith("["):
        # Kernel threads e.g. [kthreadd], [rcu_sched]
        return True
    first_token = trimmed.split()[0]
    base_name = os.path.basename(first_token).lower()
    if base_name in PROTECTED_PROCESS_BLOCKLIST:
        return True
    if trimmed.lower() in PROTECTED_PROCESS_BLOCKLIST:
        return True
    return False

def verify_process_in_recent_telemetry(server_id: str, pid: int, process_name: str) -> bool:
    """
    Verifies that a telemetry log exists for this exact server_id within the last 2 minutes
    whose top_processes array contains this pid AND process_name.
    """
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        query = """
            SELECT top_processes 
            FROM telemetry_logs 
            WHERE server_id = %s 
              AND created_at >= NOW() - INTERVAL '2 minutes' 
              AND top_processes IS NOT NULL
            ORDER BY created_at DESC;
        """
        cur.execute(query, (server_id,))
        rows = cur.fetchall()
        cur.close()
        conn.close()

        req_proc_base = os.path.basename(process_name.strip().split()[0]).lower() if process_name.strip() else ""

        for row in rows:
            top_procs = row[0]
            if isinstance(top_procs, str):
                try:
                    top_procs = json.loads(top_procs)
                except Exception:
                    continue
            if isinstance(top_procs, list):
                for proc in top_procs:
                    if not isinstance(proc, dict):
                        continue
                    p_pid = proc.get("pid")
                    p_cmd = str(proc.get("cmd", "")).strip()
                    if p_pid == pid:
                        p_cmd_base = os.path.basename(p_cmd.split()[0]).lower() if p_cmd else ""
                        if p_cmd == process_name.strip() or (req_proc_base and p_cmd_base == req_proc_base):
                            return True
        return False
    except Exception as e:
        logger.error(f"Error checking recent telemetry for process verification: {e}")
        if conn:
            conn.close()
        return False

def lambda_handler(event, context):
    path = event.get("rawPath", event.get("path", ""))
    http_method = event.get("requestContext", {}).get("http", {}).get("method", event.get("httpMethod", ""))
    
    logger.info(f"Received request: method={http_method}, path={path}")

    # Handle CORS preflight OPTIONS requests
    if http_method == "OPTIONS":
        return {
            "statusCode": 200,
            "headers": _get_cors_headers(),
            "body": json.dumps({"message": "CORS preflight OK"})
        }

    # API Key Authentication Check (Fail closed if server is misconfigured)
    if not EXPECTED_API_KEY:
        logger.error("CRITICAL CONFIGURATION ERROR: 'EXPECTED_API_KEY' environment variable is not configured.")
        return {
            "statusCode": 500,
            "headers": _get_cors_headers(),
            "body": json.dumps({
                "error": "Server misconfigured: EXPECTED_API_KEY is not set",
                "code": "SERVER_MISCONFIGURED"
            })
        }

    headers = event.get("headers") or {}
    api_key = None
    for k, v in headers.items():
        if k.lower() == "x-api-key":
            api_key = v
            break

    if not api_key or api_key != EXPECTED_API_KEY:
        return {
            "statusCode": 403,
            "headers": _get_cors_headers(),
            "body": json.dumps({
                "error": "Forbidden: Missing or invalid API Key in 'x-api-key' header",
                "code": "INVALID_API_KEY"
            })
        }

    # Route: GET /GetServers (Fetch distinct monitored servers list)
    if "GetServers" in path or (http_method == "GET" and "GetServers" in path):
        return handle_get_servers(event)

    # Route: POST /ExecuteCommand (Remote Process Termination via AWS SSM)
    elif "ExecuteCommand" in path or (http_method == "POST" and "ExecuteCommand" in path):
        return handle_execute_command(event)

    # Route: POST /IngestMetrics (Ingest Telemetry)
    elif "IngestMetrics" in path or (http_method == "POST" and "IngestMetrics" in path):
        return handle_ingest_metrics(event)
    
    # Route: GET /GetMetrics (Fetch Telemetry for Mobile App)
    elif "GetMetrics" in path or (http_method == "GET" and "GetMetrics" in path):
        return handle_get_metrics(event)
    
    else:
        return {
            "statusCode": 404,
            "headers": _get_cors_headers(),
            "body": json.dumps({"error": "Route not found"})
        }

def handle_get_servers(event):
    """
    Fetch distinct server IDs to populate client-side server filter dropdowns.
    """
    conn = None
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            SELECT DISTINCT server_id 
            FROM telemetry_logs 
            WHERE server_id IS NOT NULL AND server_id != '' 
            ORDER BY server_id ASC;
        """)
        rows = cur.fetchall()
        cur.close()
        conn.close()

        servers = [row[0] for row in rows]
        return {
            "statusCode": 200,
            "headers": _get_cors_headers(),
            "body": json.dumps(servers)
        }
    except Exception as e:
        logger.error(f"Error fetching distinct servers: {e}")
        if conn:
            conn.close()
        return {
            "statusCode": 500,
            "headers": _get_cors_headers(),
            "body": json.dumps({"error": str(e)})
        }

def handle_execute_command(event):
    """
    Architecture Decision: Remote Process Termination via AWS Systems Manager (SSM) Run Command.
    Why SSM Run Command instead of a custom socket/HTTP command listener on the C++ agent:
    1. Zero Inbound Attack Surface: The EC2 instance requires NO open inbound ports or public IP;
       the SSM Agent maintains an outbound TLS control plane to AWS.
    2. Enterprise Auditability & Traceability: Every command execution is automatically logged
       in AWS CloudTrail and SSM Run Command history with full execution output, exit codes,
       timestamps, and IAM caller identity.
    3. Fine-Grained Access Control: Authorization is enforced via AWS IAM policies rather than
       custom ad-hoc authentication tokens.
    4. Guardrails & Pre-Execution Audit Logging: Remote process termination is strictly constrained
       to observed runaway processes in recent diagnostic snapshots and logged to kill_commands table
       before any dispatch.
    """
    try:
        body = event.get("body", "{}")
        if event.get("isBase64Encoded", False):
            import base64
            body = base64.b64decode(body).decode("utf-8")

        if isinstance(body, str):
            try:
                payload = json.loads(body)
            except Exception:
                return {
                    "statusCode": 400,
                    "headers": _get_cors_headers(),
                    "body": json.dumps({"error": "Invalid JSON in request body"})
                }
        elif isinstance(body, dict):
            payload = body
        else:
            payload = {}

        instance_id = payload.get("instance_id")
        pid = payload.get("pid")
        process_name = payload.get("process_name")
        force_kill = payload.get("force_kill", False)

        is_force_kill = force_kill is True or str(force_kill).lower() == "true"
        requested_signal = "SIGKILL" if is_force_kill else "SIGTERM"
        signal_num = 9 if is_force_kill else 15

        # Check 1: instance_id validation
        if not instance_id or not isinstance(instance_id, str) or not instance_id.strip():
            reason = "Missing or invalid 'instance_id'"
            log_kill_command(instance_id, 0, process_name or "unknown", requested_signal, False, reason, status="rejected")
            return {
                "statusCode": 403,
                "headers": _get_cors_headers(),
                "body": json.dumps({"error": reason})
            }

        instance_id_str = instance_id.strip()

        # Check 2: pid validation
        if pid is None or isinstance(pid, bool):
            reason = "Missing or invalid 'pid'. Must be a positive integer."
            log_kill_command(instance_id_str, 0, process_name or "unknown", requested_signal, False, reason, status="rejected")
            return {
                "statusCode": 403,
                "headers": _get_cors_headers(),
                "body": json.dumps({"error": reason})
            }

        try:
            pid_int = int(pid)
            if pid_int <= 0 or str(pid).strip() != str(pid_int):
                raise ValueError()
        except (ValueError, TypeError):
            reason = "Invalid 'pid'. Must be a positive integer."
            log_kill_command(instance_id_str, 0, process_name or "unknown", requested_signal, False, reason, status="rejected")
            return {
                "statusCode": 403,
                "headers": _get_cors_headers(),
                "body": json.dumps({"error": reason})
            }

        # Check 3a: process_name validation
        if not process_name or not isinstance(process_name, str) or not process_name.strip():
            reason = "Missing or invalid 'process_name'. Process name is required for safety verification."
            log_kill_command(instance_id_str, pid_int, "unknown", requested_signal, False, reason, status="rejected")
            return {
                "statusCode": 403,
                "headers": _get_cors_headers(),
                "body": json.dumps({"error": reason})
            }

        process_name_str = process_name.strip()

        # Check 3b: Blocklist check
        if is_process_blocked(process_name_str):
            reason = f"Execution Rejected: Process '{process_name_str}' is a protected system service or kernel thread and cannot be terminated."
            log_kill_command(instance_id_str, pid_int, process_name_str, requested_signal, False, reason, status="rejected")
            return {
                "statusCode": 403,
                "headers": _get_cors_headers(),
                "body": json.dumps({"error": reason})
            }

        # Check 3c: Scoped 2-minute telemetry verification
        if not verify_process_in_recent_telemetry(instance_id_str, pid_int, process_name_str):
            reason = f"Execution Rejected: Process PID {pid_int} ('{process_name_str}') was not observed in recent diagnostic telemetry for server '{instance_id_str}' within the last 2 minutes."
            log_kill_command(instance_id_str, pid_int, process_name_str, requested_signal, False, reason, status="rejected")
            return {
                "statusCode": 403,
                "headers": _get_cors_headers(),
                "body": json.dumps({"error": reason})
            }

        # Check 3e: Pre-execution audit logging BEFORE dispatching AWS SSM
        audit_reason = f"Guardrail checks passed; dispatching {requested_signal} via AWS SSM Run Command"
        audit_id = log_kill_command(
            instance_id=instance_id_str,
            pid=pid_int,
            process_name=process_name_str,
            requested_signal=requested_signal,
            allowed=True,
            reason=audit_reason,
            status="authorized"
        )

        # Dispatch SSM Run Command with dedicated try/except and row update
        try:
            ssm = boto3.client("ssm", region_name=os.environ.get("AWS_REGION", "us-east-1"))
            response = ssm.send_command(
                InstanceIds=[instance_id_str],
                DocumentName="AWS-RunShellScript",
                Parameters={"commands": [f"kill -{signal_num} {pid_int}"]}
            )
            command_id = response.get("Command", {}).get("CommandId", "")
            success_reason = f"Command successfully dispatched via AWS SSM Run Command (CommandId: {command_id}, Signal: {requested_signal})"
            update_kill_command(audit_id, status="dispatched", reason=success_reason)

            return {
                "statusCode": 200,
                "headers": _get_cors_headers(),
                "body": json.dumps({
                    "message": "Command sent successfully",
                    "command_id": command_id,
                    "instance_id": instance_id_str,
                    "pid": pid_int,
                    "process_name": process_name_str,
                    "signal": requested_signal,
                    "force_kill": is_force_kill,
                    "allowed": True,
                    "status": "dispatched"
                })
            }
        except ClientError as e:
            error_msg = e.response.get("Error", {}).get("Message", str(e))
            logger.error(f"AWS SSM ClientError: {error_msg}")
            update_kill_command(audit_id, status="failed_dispatch", reason=f"AWS SSM dispatch failed: {error_msg}")
            return {
                "statusCode": 502,
                "headers": _get_cors_headers(),
                "body": json.dumps({
                    "error": f"AWS SSM dispatch failed: {error_msg}",
                    "allowed": True,
                    "instance_id": instance_id_str,
                    "pid": pid_int,
                    "process_name": process_name_str,
                    "signal": requested_signal,
                    "status": "failed_dispatch"
                })
            }
        except Exception as e:
            logger.error(f"AWS SSM execution error: {e}")
            update_kill_command(audit_id, status="failed_dispatch", reason=f"AWS SSM dispatch failed: {str(e)}")
            return {
                "statusCode": 502,
                "headers": _get_cors_headers(),
                "body": json.dumps({
                    "error": f"AWS SSM dispatch failed: {str(e)}",
                    "allowed": True,
                    "instance_id": instance_id_str,
                    "pid": pid_int,
                    "process_name": process_name_str,
                    "signal": requested_signal,
                    "status": "failed_dispatch"
                })
            }

    except Exception as e:
        logger.error(f"Error handling execute command: {e}")
        return {
            "statusCode": 500,
            "headers": _get_cors_headers(),
            "body": json.dumps({"error": str(e)})
        }

def handle_ingest_metrics(event):
    conn = None
    try:
        body = event.get("body", "{}")
        if event.get("isBase64Encoded", False):
            import base64
            body = base64.b64decode(body).decode("utf-8")
            
        payload = json.loads(body)
        
        server_id = payload.get("server_id")
        cpu_percent = payload.get("cpu_percent")
        ram_percent = payload.get("ram_percent")
        ram_used_mb = payload.get("ram_used_mb")
        ram_total_mb = payload.get("ram_total_mb")
        timestamp = payload.get("timestamp")
        top_processes = payload.get("top_processes")
        top_processes_json = json.dumps(top_processes) if top_processes is not None else None

        conn = get_db_connection()
        cur = conn.cursor()
        
        cur.execute("""
            INSERT INTO telemetry_logs (server_id, cpu_percent, ram_percent, ram_used_mb, ram_total_mb, timestamp, top_processes)
            VALUES (%s, %s, %s, %s, %s, %s, %s);
        """, (server_id, cpu_percent, ram_percent, ram_used_mb, ram_total_mb, timestamp, top_processes_json))
        
        conn.commit()
        cur.close()
        conn.close()

        return {
            "statusCode": 200,
            "headers": _get_cors_headers(),
            "body": json.dumps({"message": "Metric ingested successfully"})
        }
    except Exception as e:
        logger.error(f"Error ingesting metrics: {e}")
        if conn:
            conn.close()
        return {
            "statusCode": 500,
            "headers": _get_cors_headers(),
            "body": json.dumps({"error": str(e)})
        }

def handle_get_metrics(event):
    conn = None
    try:
        # Check for optional ?server_id=<id> query parameter
        params = event.get("queryStringParameters") or {}
        server_id_filter = params.get("server_id") if isinstance(params, dict) else None

        conn = get_db_connection()
        cur = conn.cursor()
        
        if server_id_filter and server_id_filter.strip():
            # Parameterized SQL query filtering by specific server_id
            query = """
                SELECT server_id, cpu_percent, ram_percent, ram_used_mb, ram_total_mb, created_at, top_processes 
                FROM telemetry_logs 
                WHERE server_id = %s
                ORDER BY created_at DESC 
                LIMIT 20;
            """
            cur.execute(query, (server_id_filter.strip(),))
        else:
            # Default: most recent 20 across all servers
            query = """
                SELECT server_id, cpu_percent, ram_percent, ram_used_mb, ram_total_mb, created_at, top_processes 
                FROM telemetry_logs 
                ORDER BY created_at DESC 
                LIMIT 20;
            """
            cur.execute(query)
            
        rows = cur.fetchall()
        
        results = []
        for row in rows:
            top_procs = row[6]
            if isinstance(top_procs, str):
                try:
                    top_procs = json.loads(top_procs)
                except Exception:
                    pass

            results.append({
                "server_id": row[0],
                "cpu_percent": float(row[1]) if row[1] is not None else None,
                "ram_percent": float(row[2]) if row[2] is not None else None,
                "ram_used_mb": row[3],
                "ram_total_mb": row[4],
                "created_at": str(row[5]),
                "top_processes": top_procs
            })
            
        cur.close()
        conn.close()

        return {
            "statusCode": 200,
            "headers": _get_cors_headers(),
            "body": json.dumps(results)
        }
    except Exception as e:
        logger.error(f"Error fetching metrics: {e}")
        if conn:
            conn.close()
        return {
            "statusCode": 500,
            "headers": _get_cors_headers(),
            "body": json.dumps({"error": str(e)})
        }
