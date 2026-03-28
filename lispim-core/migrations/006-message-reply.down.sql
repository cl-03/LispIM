-- Rollback Migration 006: Message Reply/Quote/Thread Support

-- Drop indexes
DROP INDEX IF EXISTS idx_message_replies_reply_to;
DROP INDEX IF EXISTS idx_message_replies_conversation;
DROP INDEX IF EXISTS idx_message_replies_sender;
DROP INDEX IF EXISTS idx_message_replies_depth;
DROP INDEX IF EXISTS idx_message_replies_created;

DROP INDEX IF EXISTS idx_notifications_user;
DROP INDEX IF EXISTS idx_notifications_type;
DROP INDEX IF EXISTS idx_notifications_read;
DROP INDEX IF EXISTS idx_notifications_created;

DROP INDEX IF EXISTS idx_messages_reply_count;

-- Drop tables
DROP TABLE IF EXISTS message_replies;
DROP TABLE IF EXISTS notifications;

-- Remove column from messages
ALTER TABLE messages DROP COLUMN IF EXISTS reply_count;
