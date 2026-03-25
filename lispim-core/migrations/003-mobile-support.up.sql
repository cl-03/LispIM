-- Migration 003: Mobile Support
-- Created: 2026-03-23
-- Description: FCM token storage and mobile device support

-- Add FCM token column to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS fcm_token VARCHAR(255),
ADD COLUMN IF NOT EXISTS device_id VARCHAR(255),
ADD COLUMN IF NOT EXISTS platform VARCHAR(50) CHECK (platform IN ('android', 'ios', 'web', 'desktop')),
ADD COLUMN IF NOT EXISTS push_enabled BOOLEAN DEFAULT TRUE;

-- Create index for FCM token lookup
CREATE INDEX IF NOT EXISTS idx_users_fcm_token ON users(fcm_token);
CREATE INDEX IF NOT EXISTS idx_users_platform ON users(platform);

-- Device sessions table - tracks user devices for targeted push
CREATE TABLE IF NOT EXISTS device_sessions (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id VARCHAR(255) NOT NULL,
    platform VARCHAR(50) NOT NULL CHECK (platform IN ('android', 'ios', 'web', 'desktop')),
    fcm_token VARCHAR(255),
    push_enabled BOOLEAN DEFAULT TRUE,
    device_name VARCHAR(255),
    app_version VARCHAR(50),
    os_version VARCHAR(50),
    last_seen_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, device_id, platform)
);

-- Create indexes for device_sessions
CREATE INDEX IF NOT EXISTS idx_device_sessions_user ON device_sessions(user_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_device ON device_sessions(device_id);
CREATE INDEX IF NOT EXISTS idx_device_sessions_platform ON device_sessions(platform);
CREATE INDEX IF NOT EXISTS idx_device_sessions_fcm ON device_sessions(fcm_token) WHERE fcm_token IS NOT NULL;

-- Push notifications log table
CREATE TABLE IF NOT EXISTS push_notifications (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id BIGINT REFERENCES device_sessions(id) ON DELETE CASCADE,
    title VARCHAR(255) NOT NULL,
    body TEXT NOT NULL,
    data JSONB DEFAULT '{}',
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'sent', 'failed', 'delivered')),
    sent_at TIMESTAMP WITH TIME ZONE,
    delivered_at TIMESTAMP WITH TIME ZONE,
    error_message TEXT,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for push_notifications
CREATE INDEX IF NOT EXISTS idx_push_notifications_user ON push_notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_push_notifications_status ON push_notifications(status);
CREATE INDEX IF NOT EXISTS idx_push_notifications_created ON push_notifications(created_at DESC);

-- Add trigger for device_sessions updated_at
DROP TRIGGER IF EXISTS update_device_sessions_last_seen ON device_sessions;
CREATE TRIGGER update_device_sessions_last_seen
    BEFORE UPDATE ON device_sessions
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Comments
COMMENT ON COLUMN users.fcm_token IS 'Firebase Cloud Messaging token for push notifications';
COMMENT ON COLUMN users.device_id IS 'Current device identifier';
COMMENT ON COLUMN users.platform IS 'Platform type: android, ios, web, desktop';
COMMENT ON COLUMN users.push_enabled IS 'Whether push notifications are enabled for this user';
COMMENT ON TABLE device_sessions IS 'Track user devices for targeted push notifications';
COMMENT ON TABLE push_notifications IS 'Log of sent push notifications';
