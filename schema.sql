-- =========================================================
-- schema.sql
-- Simulasi database internal IT untuk Text-to-SQL Agent
-- Domain: Monitoring server & insiden IT di berbagai cabang
--         perusahaan Oil & Gas Service
-- Target: PostgreSQL 15+
-- =========================================================

-- ENUM dipakai agar nilai status konsisten di level database,
-- sekaligus bisa dicantumkan eksplisit di system prompt LLM
-- (schema linking) supaya agent tahu nilai valid tanpa menebak.
CREATE TYPE server_status AS ENUM ('online', 'offline', 'maintenance', 'degraded');
CREATE TYPE incident_severity AS ENUM ('low', 'medium', 'high', 'critical');
CREATE TYPE incident_status AS ENUM ('open', 'in_progress', 'resolved');

-- =========================================================
-- Tabel: branches
-- Cabang / site operasional perusahaan, termasuk site offshore
-- =========================================================
CREATE TABLE branches (
    branch_id     SERIAL PRIMARY KEY,
    branch_name   VARCHAR(100) NOT NULL,
    city          VARCHAR(100) NOT NULL,
    region        VARCHAR(100) NOT NULL,
    is_offshore   BOOLEAN NOT NULL DEFAULT FALSE,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE branches IS 'Cabang atau site operasional perusahaan, termasuk site darat dan offshore';

-- =========================================================
-- Tabel: servers
-- Aset server per cabang. Kolom "status" adalah snapshot
-- kondisi TERKINI (cache), histori lengkap ada di status_logs.
-- =========================================================
CREATE TABLE servers (
    server_id     SERIAL PRIMARY KEY,
    branch_id     INTEGER NOT NULL REFERENCES branches(branch_id) ON DELETE CASCADE,
    hostname      VARCHAR(100) NOT NULL UNIQUE,
    ip_address    INET NOT NULL,
    server_role   VARCHAR(50) NOT NULL,  -- contoh: database, scada, file_server, application
    status        server_status NOT NULL DEFAULT 'online',
    last_seen_at  TIMESTAMPTZ,
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE servers IS 'Daftar server/aset IT yang dimonitor di setiap cabang';
COMMENT ON COLUMN servers.status IS 'Status terkini server (cache); histori lengkap ada di tabel status_logs';
COMMENT ON COLUMN servers.server_role IS 'Peran server, contoh: database, scada, file_server, application';

CREATE INDEX idx_servers_branch_id ON servers(branch_id);
CREATE INDEX idx_servers_status ON servers(status);

-- =========================================================
-- Tabel: status_logs
-- Histori time-series hasil health check server.
-- =========================================================
CREATE TABLE status_logs (
    log_id              BIGSERIAL PRIMARY KEY,
    server_id           INTEGER NOT NULL REFERENCES servers(server_id) ON DELETE CASCADE,
    status               server_status NOT NULL,
    cpu_usage_percent    SMALLINT CHECK (cpu_usage_percent BETWEEN 0 AND 100),
    response_time_ms     INTEGER,
    checked_at           TIMESTAMPTZ NOT NULL DEFAULT now()
);

COMMENT ON TABLE status_logs IS 'Riwayat hasil pengecekan status server dari waktu ke waktu';

CREATE INDEX idx_status_logs_server_checked ON status_logs(server_id, checked_at DESC);

-- =========================================================
-- Tabel: incidents
-- Tiket insiden yang tercatat terhadap sebuah server.
-- =========================================================
CREATE TABLE incidents (
    incident_id   SERIAL PRIMARY KEY,
    server_id     INTEGER NOT NULL REFERENCES servers(server_id) ON DELETE CASCADE,
    title         VARCHAR(200) NOT NULL,
    description   TEXT,
    severity      incident_severity NOT NULL DEFAULT 'medium',
    status        incident_status NOT NULL DEFAULT 'open',
    assigned_to   VARCHAR(100),
    created_at    TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at   TIMESTAMPTZ
);

COMMENT ON TABLE incidents IS 'Tiket insiden yang dilaporkan terkait sebuah server';

CREATE INDEX idx_incidents_server_id ON incidents(server_id);
CREATE INDEX idx_incidents_status ON incidents(status);

-- =========================================================
-- Role read-only khusus untuk AI Agent.
-- Ini lapisan guardrail di level database: walau ada bug di
-- validator Python, role ini secara fisik tidak bisa menulis.
-- =========================================================
CREATE ROLE agent_readonly WITH LOGIN PASSWORD 'adminuser';
GRANT CONNECT ON DATABASE postgres TO agent_readonly;
GRANT USAGE ON SCHEMA public TO agent_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO agent_readonly;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO agent_readonly;
ALTER ROLE agent_readonly SET statement_timeout = '5s';

-- =========================================================
-- Seed data — skenario demo, termasuk kasus
-- "Tampilkan server yang offline di cabang Balikpapan"
-- =========================================================
INSERT INTO branches (branch_name, city, region, is_offshore) VALUES
    ('Kantor Cabang Balikpapan', 'Balikpapan', 'Kalimantan Timur', FALSE),
    ('Site Produksi Duri', 'Duri', 'Riau', FALSE),
    ('Kantor Pusat Jakarta', 'Jakarta', 'DKI Jakarta', FALSE),
    ('Platform Offshore Natuna', 'Natuna', 'Kepulauan Riau', TRUE);

INSERT INTO servers (branch_id, hostname, ip_address, server_role, status, last_seen_at) VALUES
    (1, 'SRV-BPN-01', '10.10.1.11', 'application', 'offline', now() - interval '3 hours'),
    (1, 'SRV-BPN-02', '10.10.1.12', 'database', 'online', now()),
    (1, 'SRV-BPN-04', '10.10.1.14', 'file_server', 'offline', now() - interval '6 hours'),
    (2, 'SRV-DUR-01', '10.20.1.11', 'scada', 'online', now()),
    (3, 'SRV-JKT-01', '10.30.1.11', 'application', 'online', now()),
    (4, 'SRV-NTN-01', '10.40.1.11', 'scada', 'degraded', now() - interval '30 minutes');

INSERT INTO incidents (server_id, title, severity, status, assigned_to) VALUES
    (1, 'Server tidak merespon ping', 'high', 'open', 'Andi Wijaya'),
    (3, 'Disk usage mendekati penuh', 'medium', 'in_progress', 'Rina Kartika');
