-- Migration 007: Message Pinning Support
-- Created: 2026-04-03
-- Description: Add message pinning functionality for conversations

-- Add pinned column to messages table
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_pinned BOOLEAN DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_at TIMESTAMP WITH TIME ZONE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS pinned_by BIGINT REFERENCES users(id);

-- Create index for pinned messages
CREATE INDEX IF NOT EXISTS idx_messages_pinned ON messages(conversation_id, is_pinned) WHERE is_pinned = TRUE;

-- Create pinned_messages tracking table (for pin history and order)
CREATE TABLE IF NOT EXISTS pinned_messages (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    pinned_by BIGINT NOT NULL REFERENCES users(id),
    pinned_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    unpinned_at TIMESTAMP WITH TIME ZONE,
    unpinned_by BIGINT REFERENCES users(id),
    pin_order INTEGER DEFAULT 0,
    UNIQUE (message_id, conversation_id)
);

-- Index for quick lookup of pinned messages
CREATE INDEX IF NOT EXISTS idx_pinned_messages_conversation ON pinned_messages(conversation_id, pin_order);
CREATE INDEX IF NOT EXISTS idx_pinned_messages_message ON pinned_messages(message_id);

-- Function to get pinned messages for a conversation
CREATE OR REPLACE FUNCTION get_pinned_messages(conv_id BIGINT)
RETURNS TABLE (
    message_id BIGINT,
    content TEXT,
    sender_id BIGINT,
    pinned_at TIMESTAMPTZ,
    pinned_by BIGINT
) AS $$
BEGIN
    RETURN QUERY
    SELECT m.id, m.content, m.sender_id, pm.pinned_at, pm.pinned_by
    FROM messages m
    JOIN pinned_messages pm ON m.id = pm.message_id
    WHERE m.conversation_id = conv_id
      AND m.is_pinned = TRUE
      AND pm.unpinned_at IS NULL
    ORDER BY pm.pin_order ASC, pm.pinned_at ASC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON COLUMN messages.is_pinned IS 'Whether message is pinned';
COMMENT ON COLUMN messages.pinned_at IS 'When message was pinned';
COMMENT ON COLUMN messages.pinned_by IS 'User who pinned the message';
COMMENT ON TABLE pinned_messages IS 'Message pin history and ordering';
