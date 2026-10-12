-- Telemetry Log Table Schema for Amazon RDS (PostgreSQL)

CREATE TABLE IF NOT EXISTS telemetry_logs (
    id SERIAL PRIMARY KEY,
    server_id VARCHAR(64) NOT NULL,
    cpu_percent NUMERIC(5, 2) NOT NULL,
    ram_percent NUMERIC(5, 2) NOT NULL,
    ram_used_mb BIGINT NOT NULL,
    ram_total_mb BIGINT NOT NULL,
    timestamp BIGINT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Future Scope #2: Diagnostic Snapshot column for process-level telemetry
ALTER TABLE telemetry_logs ADD COLUMN IF NOT EXISTS top_processes JSONB;

CREATE INDEX IF NOT EXISTS idx_telemetry_created_at ON telemetry_logs (created_at DESC);

-- Future Scope #3: Remote Process Termination Audit Table
CREATE TABLE IF NOT EXISTS kill_commands (
    id SERIAL PRIMARY KEY,
    instance_id VARCHAR(64) NOT NULL,
    pid INTEGER NOT NULL,
    process_name TEXT NOT NULL,
    requested_signal VARCHAR(16) NOT NULL,
    allowed BOOLEAN NOT NULL,
    status VARCHAR(32) DEFAULT 'requested',
    reason TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

ALTER TABLE kill_commands ADD COLUMN IF NOT EXISTS status VARCHAR(32) DEFAULT 'requested';

CREATE INDEX IF NOT EXISTS idx_kill_commands_created_at ON kill_commands (created_at DESC);
