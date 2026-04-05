-- Migration 009: Group Chat DND (Do Not Disturb) Support
-- Created: 2026-04-03
-- Description: Add per-group do not disturb settings

-- Add group mute settings to conversation_participants table
ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS is_muted BOOLEAN DEFAULT FALSE;
ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS mute_until TIMESTAMP WITH TIME ZONE;
ALTER TABLE conversation_participants ADD COLUMN IF NOT EXISTS message_notify BOOLEAN DEFAULT TRUE;

-- Create index for muted participants
CREATE INDEX IF NOT EXISTS idx_conversation_participants_muted
    ON conversation_participants(conversation_id, is_muted)
    WHERE is_muted = TRUE;

-- Function to check if user has muted a conversation
CREATE OR REPLACE FUNCTION is_conversation_muted(conv_id BIGINT, user_id BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
    muted BOOLEAN;
    mute_until_time TIMESTAMPTZ;
BEGIN
    SELECT is_muted, mute_until INTO muted, mute_until_time
    FROM conversation_participants
    WHERE conversation_id = conv_id AND user_id = user_id AND is_deleted = FALSE;

    IF muted IS NULL THEN
        RETURN FALSE;
    END IF;

    -- If muted permanently
    IF muted = TRUE AND mute_until_time IS NULL THEN
        RETURN TRUE;
    END IF;

    -- If muted temporarily, check if still in effect
    IF muted = TRUE AND mute_until_time IS NOT NULL AND mute_until_time > CURRENT_TIMESTAMP THEN
        RETURN TRUE;
    END IF;

    -- Mute period expired
    RETURN FALSE;
END;
$$ LANGUAGE plpgsql;

-- Function to mute/unmute conversation
CREATE OR REPLACE FUNCTION set_conversation_mute(
    conv_id BIGINT,
    user_id BIGINT,
    should_mute BOOLEAN,
    duration_minutes INTEGER DEFAULT NULL
)
RETURNS BOOLEAN AS $$
BEGIN
    IF should_mute THEN
        UPDATE conversation_participants
        SET is_muted = TRUE,
            mute_until = CASE
                WHEN duration_minutes IS NOT NULL
                THEN CURRENT_TIMESTAMP + (duration_minutes || ' minutes')::INTERVAL
                ELSE NULL
            END,
            message_notify = FALSE
        WHERE conversation_id = conv_id AND user_id = user_id;
    ELSE
        UPDATE conversation_participants
        SET is_muted = FALSE,
            mute_until = NULL,
            message_notify = TRUE
        WHERE conversation_id = conv_id AND user_id = user_id;
    END IF;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

COMMENT ON COLUMN conversation_participants.is_muted IS 'Whether user has muted the conversation';
COMMENT ON COLUMN conversation_participants.mute_until IS 'Mute expiration time (NULL for permanent)';
COMMENT ON COLUMN conversation_participants.message_notify IS 'Whether to show message notifications';
