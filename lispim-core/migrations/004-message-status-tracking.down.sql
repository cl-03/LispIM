-- Rollback Migration 004: Message Status Tracking
-- Created: 2026-03-26

-- Drop views
DROP VIEW IF EXISTS message_delivery_stats;

-- Drop functions
DROP FUNCTION IF EXISTS get_failed_messages_for_retry(INTEGER);
DROP FUNCTION IF EXISTS get_messages_by_status(BIGINT, INTEGER, INTEGER);

-- Drop indexes
DROP INDEX IF EXISTS idx_messages_status;
DROP INDEX IF EXISTS idx_messages_retry_count;
DROP INDEX IF EXISTS idx_messages_delivered_to;

-- Drop columns
ALTER TABLE messages
DROP COLUMN IF EXISTS status,
DROP COLUMN IF EXISTS retry_count,
DROP COLUMN IF EXISTS last_error,
DROP COLUMN IF EXISTS delivered_to;
