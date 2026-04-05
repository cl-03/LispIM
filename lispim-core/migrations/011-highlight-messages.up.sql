-- Migration 011: Highlight Messages (群精华消息)
-- Created: 2026-04-03
-- Description: Add highlighted/featured messages for groups

-- Create highlighted messages table
CREATE TABLE IF NOT EXISTS highlighted_messages (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL REFERENCES messages(id) ON DELETE CASCADE,
    conversation_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    added_by BIGINT NOT NULL REFERENCES users(id),
    added_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    note TEXT,
    is_removed BOOLEAN DEFAULT FALSE,
    removed_by BIGINT REFERENCES users(id),
    removed_at TIMESTAMP WITH TIME ZONE,
    display_order INTEGER DEFAULT 0,
    UNIQUE (message_id, conversation_id)
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_highlighted_messages_conversation
    ON highlighted_messages(conversation_id, display_order, added_at);
CREATE INDEX IF NOT EXISTS idx_highlighted_messages_message
    ON highlighted_messages(message_id);

-- Function to add highlight message
CREATE OR REPLACE FUNCTION add_highlighted_message(
    msg_id BIGINT,
    conv_id BIGINT,
    adder_user_id BIGINT,
    note_text TEXT DEFAULT NULL
)
RETURNS BIGINT AS $$
DECLARE
    highlight_id BIGINT;
BEGIN
    -- Check if already highlighted
    IF EXISTS (
        SELECT 1 FROM highlighted_messages
        WHERE message_id = msg_id AND is_removed = FALSE
    ) THEN
        RAISE EXCEPTION 'Message already highlighted';
    END IF;

    -- Insert highlight record
    INSERT INTO highlighted_messages (message_id, conversation_id, added_by, note, display_order)
    VALUES (msg_id, conv_id, adder_user_id, note_text,
            (SELECT COALESCE(MAX(display_order), 0) + 1 FROM highlighted_messages WHERE conversation_id = conv_id AND is_removed = FALSE))
    RETURNING id INTO highlight_id;

    RETURN highlight_id;
END;
$$ LANGUAGE plpgsql;

-- Function to remove highlight message
CREATE OR REPLACE FUNCTION remove_highlighted_message(
    highlight_id BIGINT,
    remover_user_id BIGINT
)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE highlighted_messages
    SET is_removed = TRUE,
        removed_by = remover_user_id,
        removed_at = CURRENT_TIMESTAMP
    WHERE id = highlight_id AND is_removed = FALSE;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to get highlighted messages
CREATE OR REPLACE FUNCTION get_highlighted_messages(conv_id BIGINT)
RETURNS TABLE (
    highlight_id BIGINT,
    message_id BIGINT,
    content TEXT,
    sender_id BIGINT,
    sender_name VARCHAR,
    type VARCHAR,
    added_at TIMESTAMPTZ,
    added_by BIGINT,
    added_by_name VARCHAR,
    note TEXT,
    display_order INTEGER
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        hm.id,
        hm.message_id,
        m.content,
        m.sender_id,
        sender.username,
        m.type,
        hm.added_at,
        hm.added_by,
        adder.username,
        hm.note,
        hm.display_order
    FROM highlighted_messages hm
    JOIN messages m ON hm.message_id = m.id
    JOIN users sender ON m.sender_id = sender.id
    JOIN users adder ON hm.added_by = adder.id
    WHERE hm.conversation_id = conv_id
      AND hm.is_removed = FALSE
    ORDER BY hm.display_order ASC, hm.added_at ASC;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE highlighted_messages IS 'Highlighted/featured messages in groups';
COMMENT ON COLUMN highlighted_messages.note IS 'Optional note explaining why highlighted';
COMMENT ON COLUMN highlighted_messages.display_order IS 'Custom display order';
