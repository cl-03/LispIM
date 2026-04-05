-- Migration 009 Down: Remove Group Chat DND Support
-- Created: 2026-04-03

-- Remove columns from conversation_participants table
ALTER TABLE conversation_participants DROP COLUMN IF NOT EXISTS is_muted;
ALTER TABLE conversation_participants DROP COLUMN IF NOT EXISTS mute_until;
ALTER TABLE conversation_participants DROP COLUMN IF NOT EXISTS message_notify;
