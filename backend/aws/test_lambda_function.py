import os
import json
import unittest
from unittest.mock import patch, MagicMock
from botocore.exceptions import ClientError

# Set test environment
os.environ["EXPECTED_API_KEY"] = "mock-test-api-key-xyz"
os.environ["AWS_REGION"] = "us-east-1"
os.environ["DB_HOST"] = "localhost"
os.environ["DB_NAME"] = "postgres"
os.environ["DB_USER"] = "postgres"
os.environ["DB_PASSWORD"] = "postgres"
os.environ["DB_PORT"] = "5432"

import lambda_function

VALID_HEADERS = {
    "x-api-key": "mock-test-api-key-xyz",
    "Content-Type": "application/json"
}

class TestLambdaSafetyGuardrails(unittest.TestCase):

    def test_missing_expected_api_key_fails_closed_500(self):
        with patch.object(lambda_function, "EXPECTED_API_KEY", None):
            event = {
                "rawPath": "/GetMetrics",
                "requestContext": {"http": {"method": "GET"}},
                "headers": {"x-api-key": "some-key"},
            }
            response = lambda_function.lambda_handler(event, None)
            self.assertEqual(response["statusCode"], 500)
            body = json.loads(response["body"])
            self.assertEqual(body["code"], "SERVER_MISCONFIGURED")
            self.assertIn("Server misconfigured", body["error"])

    def test_missing_api_key_header_returns_403(self):
        event = {
            "rawPath": "/IngestMetrics",
            "requestContext": {"http": {"method": "POST"}},
            "headers": {},
            "body": json.dumps({"server_id": "test"})
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        self.assertEqual(response["headers"]["Access-Control-Allow-Origin"], "*")
        body = json.loads(response["body"])
        self.assertEqual(body["code"], "INVALID_API_KEY")

    def test_invalid_api_key_header_returns_403(self):
        event = {
            "rawPath": "/GetMetrics",
            "requestContext": {"http": {"method": "GET"}},
            "headers": {"x-api-key": "wrong-key"},
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertEqual(body["code"], "INVALID_API_KEY")

    @patch("lambda_function.update_kill_command")
    @patch("lambda_function.log_kill_command")
    @patch("lambda_function.verify_process_in_recent_telemetry")
    @patch("boto3.client")
    def test_execute_command_success_default_sigterm(self, mock_boto_client, mock_verify, mock_audit, mock_update):
        mock_verify.return_value = True
        mock_audit.return_value = 101
        mock_ssm = MagicMock()
        mock_ssm.send_command.return_value = {
            "Command": {
                "CommandId": "cmd-0a1b2c3d4e5f67890"
            }
        }
        mock_boto_client.return_value = mock_ssm

        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0abcdef1234567890",
                "pid": 4512,
                "process_name": "python3 stress.py"
            })
        }

        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)

        body = json.loads(response["body"])
        self.assertEqual(body["command_id"], "cmd-0a1b2c3d4e5f67890")
        self.assertEqual(body["instance_id"], "i-0abcdef1234567890")
        self.assertEqual(body["pid"], 4512)
        self.assertEqual(body["process_name"], "python3 stress.py")
        self.assertEqual(body["signal"], "SIGTERM")
        self.assertFalse(body["force_kill"])

        mock_ssm.send_command.assert_called_once_with(
            InstanceIds=["i-0abcdef1234567890"],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": ["kill -15 4512"]}
        )
        mock_audit.assert_called_once_with(
            instance_id="i-0abcdef1234567890",
            pid=4512,
            process_name="python3 stress.py",
            requested_signal="SIGTERM",
            allowed=True,
            reason=unittest.mock.ANY,
            status="authorized"
        )
        mock_update.assert_called_once_with(101, status="dispatched", reason=unittest.mock.ANY)

    @patch("lambda_function.update_kill_command")
    @patch("lambda_function.log_kill_command")
    @patch("lambda_function.verify_process_in_recent_telemetry")
    @patch("boto3.client")
    def test_execute_command_force_kill_explicit_sigkill(self, mock_boto_client, mock_verify, mock_audit, mock_update):
        mock_verify.return_value = True
        mock_audit.return_value = 102
        mock_ssm = MagicMock()
        mock_ssm.send_command.return_value = {
            "Command": {
                "CommandId": "cmd-force-999"
            }
        }
        mock_boto_client.return_value = mock_ssm

        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0abcdef1234567890",
                "pid": 4512,
                "process_name": "stress-ng",
                "force_kill": True
            })
        }

        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)

        body = json.loads(response["body"])
        self.assertEqual(body["signal"], "SIGKILL")
        self.assertTrue(body["force_kill"])

        # Explicit assertion: force_kill=true results in SIGKILL signal command sent
        mock_ssm.send_command.assert_called_once_with(
            InstanceIds=["i-0abcdef1234567890"],
            DocumentName="AWS-RunShellScript",
            Parameters={"commands": ["kill -9 4512"]}
        )
        mock_audit.assert_called_once_with(
            instance_id="i-0abcdef1234567890",
            pid=4512,
            process_name="stress-ng",
            requested_signal="SIGKILL",
            allowed=True,
            reason=unittest.mock.ANY,
            status="authorized"
        )
        mock_update.assert_called_once_with(102, status="dispatched", reason=unittest.mock.ANY)

    @patch("lambda_function.update_kill_command")
    @patch("lambda_function.log_kill_command")
    @patch("lambda_function.verify_process_in_recent_telemetry")
    @patch("boto3.client")
    def test_execute_command_ssm_failure_returns_clean_502_and_updates_audit_row(self, mock_boto_client, mock_verify, mock_audit, mock_update):
        mock_verify.return_value = True
        mock_audit.return_value = 103
        mock_ssm = MagicMock()
        mock_ssm.send_command.side_effect = ClientError(
            {"Error": {"Code": "InvalidInstanceId", "Message": "Instance not found in region"}},
            "SendCommand"
        )
        mock_boto_client.return_value = mock_ssm

        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-notfound",
                "pid": 8888,
                "process_name": "rogue_task"
            })
        }

        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 502)
        body = json.loads(response["body"])
        self.assertIn("AWS SSM dispatch failed: Instance not found in region", body["error"])
        self.assertTrue(body["allowed"])
        self.assertEqual(body["status"], "failed_dispatch")

        mock_audit.assert_called_once_with(
            instance_id="i-notfound",
            pid=8888,
            process_name="rogue_task",
            requested_signal="SIGTERM",
            allowed=True,
            reason=unittest.mock.ANY,
            status="authorized"
        )
        mock_update.assert_called_once_with(
            103,
            status="failed_dispatch",
            reason="AWS SSM dispatch failed: Instance not found in region"
        )

    @patch("lambda_function.log_kill_command")
    def test_execute_command_missing_process_name_rejected_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0123456789",
                "pid": 1234
            })
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("process_name", body["error"])
        mock_audit.assert_called_once()

    @patch("lambda_function.log_kill_command")
    def test_execute_command_blocked_systemd_rejected_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0123456789",
                "pid": 1,
                "process_name": "systemd"
            })
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("protected system service", body["error"])
        mock_audit.assert_called_once()

    @patch("lambda_function.log_kill_command")
    def test_execute_command_blocked_sshd_rejected_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0123456789",
                "pid": 900,
                "process_name": "/usr/sbin/sshd -D"
            })
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("protected system service", body["error"])
        mock_audit.assert_called_once()

    @patch("lambda_function.log_kill_command")
    def test_execute_command_blocked_kernel_thread_rejected_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0123456789",
                "pid": 2,
                "process_name": "[kthreadd]"
            })
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("protected system service or kernel thread", body["error"])
        mock_audit.assert_called_once()

    @patch("lambda_function.log_kill_command")
    def test_execute_command_blocked_telemetry_agent_rejected_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "i-0123456789",
                "pid": 789,
                "process_name": "./telemetry_agent"
            })
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("protected system service", body["error"])
        mock_audit.assert_called_once()

    @patch("lambda_function.log_kill_command")
    @patch("lambda_function.verify_process_in_recent_telemetry")
    def test_execute_command_unverified_in_recent_telemetry_rejected_403(self, mock_verify, mock_audit):
        mock_verify.return_value = False
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({
                "instance_id": "worker-node-alpha",
                "pid": 3333,
                "process_name": "unknown_binary"
            })
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("not observed in recent diagnostic telemetry", body["error"])
        mock_audit.assert_called_once()

    @patch("lambda_function.log_kill_command")
    def test_execute_command_missing_instance_id_returns_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({"pid": 1234, "process_name": "sleep 100"})
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("Missing or invalid 'instance_id'", body["error"])

    @patch("lambda_function.log_kill_command")
    def test_execute_command_invalid_pid_returns_403(self, mock_audit):
        event = {
            "rawPath": "/ExecuteCommand",
            "requestContext": {"http": {"method": "POST"}},
            "headers": VALID_HEADERS,
            "body": json.dumps({"instance_id": "i-0123456789", "pid": -10, "process_name": "sleep"})
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 403)
        body = json.loads(response["body"])
        self.assertIn("Invalid 'pid'", body["error"])

    @patch("lambda_function.get_db_connection")
    def test_get_servers_success(self, mock_get_db):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_cur.fetchall.return_value = [("beast",), ("ec2-node-01",), ("ec2-node-02",)]
        mock_conn.cursor.return_value = mock_cur
        mock_get_db.return_value = mock_conn

        event = {
            "rawPath": "/GetServers",
            "requestContext": {"http": {"method": "GET"}},
            "headers": VALID_HEADERS
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)
        servers = json.loads(response["body"])
        self.assertEqual(servers, ["beast", "ec2-node-01", "ec2-node-02"])

    @patch("lambda_function.get_db_connection")
    def test_get_metrics_with_server_id_filter(self, mock_get_db):
        mock_conn = MagicMock()
        mock_cur = MagicMock()
        mock_cur.fetchall.return_value = [
            ("ec2-node-01", 15.5, 45.0, 4500, 10000, "2026-10-02 12:00:00+00", None)
        ]
        mock_conn.cursor.return_value = mock_cur
        mock_get_db.return_value = mock_conn

        event = {
            "rawPath": "/GetMetrics",
            "requestContext": {"http": {"method": "GET"}},
            "queryStringParameters": {"server_id": "ec2-node-01"},
            "headers": VALID_HEADERS
        }
        response = lambda_function.lambda_handler(event, None)
        self.assertEqual(response["statusCode"], 200)
        metrics = json.loads(response["body"])
        self.assertEqual(len(metrics), 1)
        self.assertEqual(metrics[0]["server_id"], "ec2-node-01")

        executed_query, params = mock_cur.execute.call_args[0]
        self.assertIn("WHERE server_id = %s", executed_query)
        self.assertEqual(params, ("ec2-node-01",))

if __name__ == "__main__":
    unittest.main()
