-- Migration 010: Message Forwarding Support
-- Created: 2026-04-03
-- Description: Add message forwarding functionality

-- Add forwarded flag and reference to messages table
ALTER TABLE messages ADD COLUMN IF NOT EXISTS is_forwarded BOOLEAN DEFAULT FALSE;
ALTER TABLE messages ADD COLUMN IF NOT EXISTS forwarded_from_message_id BIGINT REFERENCES messages(id);
ALTER TABLE messages ADD COLUMN IF NOT EXISTS forwarded_from_user_id BIGINT REFERENCES users(id);
ALTER TABLE messages ADD COLUMN IF NOT EXISTS forward_count INTEGER DEFAULT 0;

-- Create index for forwarded messages
CREATE INDEX IF NOT EXISTS idx_messages_forwarded ON messages(is_forwarded) WHERE is_forwarded = TRUE;
CREATE INDEX IF NOT EXISTS idx_messages_forwarded_from ON messages(forwarded_from_message_id);

-- Function to forward a message
CREATE OR REPLACE FUNCTION forward_message(
    src_message_id BIGINT,
    target_conversation_id BIGINT,
    forwarder_user_id BIGINT,
    forward_comment TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    new_message_id BIGINT;
    new_sequence BIGINT;
    src_message RECORD;
BEGIN
    -- Get source message
    SELECT * INTO src_message
    FROM messages
    WHERE id = src_message_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Source message not found';
    END IF;

    -- Get next sequence for target conversation
    SELECT COALESCE(MAX(sequence), 0) + 1 INTO new_sequence
    FROM messages
    WHERE conversation_id = target_conversation_id;

    -- Create forwarded message
    INSERT INTO messages (
        id, conversation_id, sender_id, sequence, type, content,
        attachments, mentions, reply_to, is_forwarded,
        forwarded_from_message_id, forwarded_from_user_id, forward_count,
        created_at
    ) VALUES (
        NEXTVAL('messages_id_seq'),
        target_conversation_id,
        forwarder_user_id,
        new_sequence,
        src_message.type,
        COALESCE(forward_comment, src_message.content),
        src_message.attachments,
        src_message.mentions,
        NULL,
        TRUE,
        src_message_id,
        src_message.sender_id,
        1,
        CURRENT_TIMESTAMP
    ) RETURNING id INTO new_message_id;

    -- Increment forward count on source message
    UPDATE messages
    SET forward_count = forward_count + 1
    WHERE id = src_message_id;

    RETURN new_message_id;
END;
$$ LANGUAGE plpgsql;

COMMENT ON COLUMN messages.is_forwarded IS 'Whether message was forwarded';
COMMENT ON COLUMN messages.forwarded_from_message_id IS 'Original message ID if forwarded';
COMMENT ON COLUMN messages.forwarded_from_user_id IS 'Original sender ID if forwarded';
COMMENT ON COLUMN messages.forward_count IS 'Number of times message has been forwarded';
