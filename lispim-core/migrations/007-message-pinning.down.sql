-- Migration 007 Down: Remove Message Pinning Support
-- Created: 2026-04-03

-- Drop pinned_messages table
DROP TABLE IF EXISTS pinned_messages;

-- Remove columns from messages table
ALTER TABLE messages DROP COLUMN IF EXISTS is_pinned;
ALTER TABLE messages DROP COLUMN IF EXISTS pinned_at;
ALTER TABLE messages DROP COLUMN IF EXISTS pinned_by;
