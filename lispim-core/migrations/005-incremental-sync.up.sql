-- Migration 005: Client Incremental Sync Support
-- Creates tables for sync anchor tracking and conversation changes

-- Sync anchors table for tracking per-user sync position
CREATE TABLE IF NOT EXISTS sync_anchors (
    id SERIAL PRIMARY KEY,
    user_id VARCHAR(255) NOT NULL,
    device_id VARCHAR(255) NOT NULL DEFAULT 'default',
    message_seq BIGINT NOT NULL DEFAULT 0,
    conversation_seq BIGINT NOT NULL DEFAULT 0,
    last_sync_at BIGINT NOT NULL DEFAULT 0,
    updated_at BIGINT NOT NULL DEFAULT 0,
    CONSTRAINT unique_user_device UNIQUE (user_id, device_id)
);

-- Index for fast anchor lookup
CREATE INDEX IF NOT EXISTS idx_sync_anchors_user ON sync_anchors(user_id);
CREATE INDEX IF NOT EXISTS idx_sync_anchors_device ON sync_anchors(device_id);

-- Conversation changes tracking for incremental sync
CREATE TABLE IF NOT EXISTS conversation_changes (
    id SERIAL PRIMARY KEY,
    conversation_id BIGINT NOT NULL,
    user_id VARCHAR(255) NOT NULL,
    seq BIGINT NOT NULL,
    change_type VARCHAR(50) NOT NULL, -- 'create', 'update', 'delete', 'participant_add', 'participant_remove'
    changed_at BIGINT NOT NULL,
    changed_by VARCHAR(255) NOT NULL
);

-- Index for incremental sync queries
CREATE INDEX IF NOT EXISTS idx_conv_changes_user_seq ON conversation_changes(user_id, seq);
CREATE INDEX IF NOT EXISTS idx_conv_changes_conv ON conversation_changes(conversation_id);

-- Message conversations junction table with sequence for sync
CREATE TABLE IF NOT EXISTS message_conversations (
    id SERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL,
    conversation_id BIGINT NOT NULL,
    seq BIGINT NOT NULL,
    UNIQUE (message_id, conversation_id)
);

-- Index for message sync queries
CREATE INDEX IF NOT EXISTS idx_msg_conv_seq ON message_conversations(seq);
CREATE INDEX IF NOT EXISTS idx_msg_conv_message ON message_conversations(message_id);
CREATE INDEX IF NOT EXISTS idx_msg_conv_conversation ON message_conversations(conversation_id);

-- Add sync-related columns to messages if not exist
ALTER TABLE messages ADD COLUMN IF NOT EXISTS sync_seq BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_messages_sync_seq ON messages(sync_seq);

-- Add sync-related columns to conversations if not exist
ALTER TABLE conversations ADD COLUMN IF NOT EXISTS sync_seq BIGINT DEFAULT 0;
CREATE INDEX IF NOT EXISTS idx_conversations_sync_seq ON conversations(sync_seq);

-- Function to update conversation change tracking
CREATE OR REPLACE FUNCTION track_conversation_change()
RETURNS TRIGGER AS $$
DECLARE
    next_seq BIGINT;
BEGIN
    -- Get next sequence number
    SELECT COALESCE(MAX(seq), 0) + 1 INTO next_seq
    FROM conversation_changes
    WHERE conversation_id = NEW.id;

    -- Record the change
    INSERT INTO conversation_changes (conversation_id, user_id, seq, change_type, changed_at, changed_by)
    VALUES (NEW.id, NEW.owner_id, next_seq, 'update', EXTRACT(EPOCH FROM NOW()), NEW.updated_by);

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Trigger for tracking conversation changes
DROP TRIGGER IF EXISTS trg_track_conversation_change ON conversations;
CREATE TRIGGER trg_track_conversation_change
    AFTER UPDATE ON conversations
    FOR EACH ROW
    EXECUTE FUNCTION track_conversation_change();
