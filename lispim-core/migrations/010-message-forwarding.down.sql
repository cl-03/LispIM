-- Migration 010 Down: Remove Message Forwarding Support
-- Created: 2026-04-03

-- Remove columns from messages table
ALTER TABLE messages DROP COLUMN IF NOT EXISTS is_forwarded;
ALTER TABLE messages DROP COLUMN IF NOT EXISTS forwarded_from_message_id;
ALTER TABLE messages DROP COLUMN IF NOT EXISTS forwarded_from_user_id;
ALTER TABLE messages DROP COLUMN IF NOT EXISTS forward_count;
