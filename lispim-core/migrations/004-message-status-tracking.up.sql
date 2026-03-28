-- Migration 004: Message Status Tracking
-- Created: 2026-03-26
-- Description: Add message status tracking columns for reliable delivery (WhatsApp-style state machine)

-- Add status column to messages table
-- Status codes: 0=pending, 1=sending, 2=sent, 3=delivered, 4=read, 5=failed
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS status INTEGER DEFAULT 1;

-- Add retry_count column for failed message retry tracking
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS retry_count INTEGER DEFAULT 0;

-- Add last_error column for storing error messages
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS last_error TEXT;

-- Add delivered_to column for tracking which users received the message
-- This is an array of user IDs (text format to match sender_id)
ALTER TABLE messages
ADD COLUMN IF NOT EXISTS delivered_to TEXT[] DEFAULT '{}';

-- Create index on status for efficient querying
CREATE INDEX IF NOT EXISTS idx_messages_status ON messages(status);

-- Create index on retry_count for finding messages that need retry
CREATE INDEX IF NOT EXISTS idx_messages_retry_count ON messages(retry_count) WHERE status = 5;

-- Create index on delivered_to for checking delivery status
CREATE INDEX IF NOT EXISTS idx_messages_delivered_to ON messages USING GIN (delivered_to);

-- Comments for documentation
COMMENT ON COLUMN messages.status IS 'Message delivery status: 0=pending, 1=sending, 2=sent, 3=delivered, 4=read, 5=failed';
COMMENT ON COLUMN messages.retry_count IS 'Number of retry attempts for failed messages';
COMMENT ON COLUMN messages.last_error IS 'Last error message for failed delivery';
COMMENT ON COLUMN messages.delivered_to IS 'Array of user IDs to which message was delivered';

-- Create function to get messages by status
CREATE OR REPLACE FUNCTION get_messages_by_status(p_conversation_id BIGINT, p_status INTEGER, p_limit INTEGER DEFAULT 50)
RETURNS TABLE (
    id BIGINT,
    conversation_id BIGINT,
    sender_id BIGINT,
    sequence BIGINT,
    type VARCHAR,
    content TEXT,
    status INTEGER,
    retry_count INTEGER,
    last_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.conversation_id,
        m.sender_id,
        m.sequence,
        m.type,
        m.content,
        m.status,
        m.retry_count,
        m.last_error,
        m.created_at
    FROM messages m
    WHERE m.conversation_id = p_conversation_id
      AND m.status = p_status
    ORDER BY m.sequence DESC
    LIMIT p_limit;
END;
$$ LANGUAGE plpgsql;

-- Create function to get failed messages for retry
CREATE OR REPLACE FUNCTION get_failed_messages_for_retry(p_retry_count_max INTEGER DEFAULT 3)
RETURNS TABLE (
    id BIGINT,
    conversation_id BIGINT,
    sender_id BIGINT,
    sequence BIGINT,
    type VARCHAR,
    content TEXT,
    retry_count INTEGER,
    last_error TEXT,
    created_at TIMESTAMP WITH TIME ZONE
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        m.id,
        m.conversation_id,
        m.sender_id,
        m.sequence,
        m.type,
        m.content,
        m.retry_count,
        m.last_error,
        m.created_at
    FROM messages m
    WHERE m.status = 5  -- failed
      AND m.retry_count < p_retry_count_max
    ORDER BY m.created_at ASC;
END;
$$ LANGUAGE plpgsql;

-- Create stats view for message delivery monitoring
CREATE OR REPLACE VIEW message_delivery_stats AS
SELECT
    status,
    CASE status
        WHEN 0 THEN 'pending'
        WHEN 1 THEN 'sending'
        WHEN 2 THEN 'sent'
        WHEN 3 THEN 'delivered'
        WHEN 4 THEN 'read'
        WHEN 5 THEN 'failed'
    END AS status_name,
    COUNT(*) AS message_count,
    COUNT(DISTINCT conversation_id) AS conversation_count,
    AVG(retry_count) AS avg_retry_count
FROM messages
GROUP BY status
ORDER BY status;

COMMENT ON VIEW message_delivery_stats IS 'Real-time message delivery statistics by status';
