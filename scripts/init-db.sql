-- LispIM Database Initialization Script
-- PostgreSQL schema for event sourcing IM system

-- Enable extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pg_trgm";

-- Users table
CREATE TABLE IF NOT EXISTS users (
    id BIGINT PRIMARY KEY,
    username VARCHAR(255) UNIQUE NOT NULL,
    email VARCHAR(255) UNIQUE,
    password_hash VARCHAR(255) NOT NULL,
    public_key TEXT,
    avatar_url VARCHAR(512),
    status VARCHAR(50) DEFAULT 'active',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_seen_at TIMESTAMP
);

-- Create index for username lookup
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);

-- Conversations table
CREATE TABLE IF NOT EXISTS conversations (
    id BIGINT PRIMARY KEY,
    type VARCHAR(50) NOT NULL CHECK (type IN ('direct', 'group')),
    name VARCHAR(255),
    avatar_url VARCHAR(512),
    creator_id BIGINT REFERENCES users(id),
    metadata JSONB DEFAULT '{}',
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Conversation participants (many-to-many)
CREATE TABLE IF NOT EXISTS conversation_participants (
    conversation_id BIGINT REFERENCES conversations(id) ON DELETE CASCADE,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    role VARCHAR(50) DEFAULT 'member' CHECK (role IN ('admin', 'moderator', 'member')),
    joined_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (conversation_id, user_id)
);

CREATE INDEX idx_conv_participants_user ON conversation_participants(user_id);

-- Messages table (event store)
CREATE TABLE IF NOT EXISTS messages (
    id BIGINT PRIMARY KEY,
    conversation_id BIGINT REFERENCES conversations(id) ON DELETE CASCADE,
    sender_id BIGINT REFERENCES users(id),
    sequence BIGINT NOT NULL,
    type VARCHAR(50) NOT NULL,
    content TEXT,
    attachments JSONB DEFAULT '[]',
    mentions BIGINT[] DEFAULT '{}',
    reply_to BIGINT REFERENCES messages(id),
    recalled BOOLEAN DEFAULT FALSE,
    edited_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (conversation_id, sequence)
);

-- Indexes for message queries
CREATE INDEX idx_messages_conv_seq ON messages(conversation_id, sequence DESC);
CREATE INDEX idx_messages_sender ON messages(sender_id);
CREATE INDEX idx_messages_created ON messages(created_at DESC);
CREATE INDEX idx_messages_type ON messages(type);

-- Message reads (read receipts)
CREATE TABLE IF NOT EXISTS message_reads (
    message_id BIGINT REFERENCES messages(id) ON DELETE CASCADE,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    read_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (message_id, user_id)
);

CREATE INDEX idx_message_reads_user ON message_reads(user_id);

-- Audit log (immutable)
CREATE TABLE IF NOT EXISTS audit_log (
    id BIGINT PRIMARY KEY DEFAULT EXTRACT(EPOCH FROM CURRENT_TIMESTAMP)::BIGINT * 1000 + EXTRACT(MILLISECONDS FROM CURRENT_TIMESTAMP)::INTEGER,
    user_id BIGINT REFERENCES users(id),
    action VARCHAR(255) NOT NULL,
    resource_type VARCHAR(100),
    resource_id BIGINT,
    old_value JSONB,
    new_value JSONB,
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for audit queries
CREATE INDEX idx_audit_user ON audit_log(user_id);
CREATE INDEX idx_audit_action ON audit_log(action);
CREATE INDEX idx_audit_created ON audit_log(created_at DESC);
CREATE INDEX idx_audit_resource ON audit_log(resource_type, resource_id);

-- E2EE keys
CREATE TABLE IF NOT EXISTS e2ee_keys (
    id BIGINT PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    key_type VARCHAR(50) NOT NULL,
    key_data TEXT NOT NULL,
    key_version INTEGER NOT NULL,
    is_active BOOLEAN DEFAULT TRUE,
    expires_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, key_type, key_version)
);

CREATE INDEX idx_e2ee_keys_user ON e2ee_keys(user_id);
CREATE INDEX idx_e2ee_keys_active ON e2ee_keys(user_id, is_active);

-- Sessions
CREATE TABLE IF NOT EXISTS sessions (
    id VARCHAR(255) PRIMARY KEY,
    user_id BIGINT REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255),
    ip_address INET,
    user_agent TEXT,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP,
    last_activity TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX idx_sessions_user ON sessions(user_id);
CREATE INDEX idx_sessions_expires ON sessions(expires_at);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for users table
CREATE TRIGGER update_users_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Trigger for conversations table
CREATE TRIGGER update_conversations_updated_at
    BEFORE UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to generate snowflake-like ID
CREATE OR REPLACE FUNCTION generate_snowflake_id(
    datacenter_id INTEGER DEFAULT 0,
    worker_id INTEGER DEFAULT 0
) RETURNS BIGINT AS $$
DECLARE
    epoch BIGINT := 1735689600000;  -- 2025-01-01 00:00:00 UTC in milliseconds
    timestamp BIGINT;
    sequence INTEGER;
    id BIGINT;
BEGIN
    timestamp := EXTRACT(EPOCH FROM CURRENT_TIMESTAMP) * 1000;
    sequence := (random() * 4095)::INTEGER;

    id := ((timestamp - epoch) << 22) |
          ((datacenter_id & 31) << 17) |
          ((worker_id & 31) << 12) |
          sequence;

    RETURN id;
END;
$$ LANGUAGE plpgsql;

-- Insert default admin user (password: admin123)
INSERT INTO users (id, username, email, password_hash, status)
VALUES (1, 'admin', 'admin@lispim.local',
        '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS3MebAJu',
        'active')
ON CONFLICT (id) DO NOTHING;

-- Insert system administrator user (not loginable, system only)
INSERT INTO users (id, username, email, password_hash, display_name, status)
VALUES (2, 'system_admin', 'system@lispim.local',
        '$2b$12$LQv3c1yqBWVHxkd0LHAkCOYz6TtxMQJqhN8/LewY5GyYzS3MebAJu',
        '系统管理员', 'active')
ON CONFLICT (id) DO NOTHING;

-- Create read-only user for monitoring
CREATE ROLE lispim_monitor WITH LOGIN PASSWORD 'monitor_password';
GRANT SELECT ON ALL TABLES IN SCHEMA public TO lispim_monitor;

-- Vacuum and analyze
VACUUM ANALYZE;
