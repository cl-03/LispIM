-- Migration 005 Down: Rollback Incremental Sync Support

-- Drop triggers
DROP TRIGGER IF EXISTS trg_track_conversation_change ON conversations;

-- Drop function
DROP FUNCTION IF EXISTS track_conversation_change();

-- Drop tables
DROP TABLE IF EXISTS message_conversations;
DROP TABLE IF EXISTS conversation_changes;
DROP TABLE IF EXISTS sync_anchors;

-- Remove sync-related columns
ALTER TABLE messages DROP COLUMN IF EXISTS sync_seq;
ALTER TABLE conversations DROP COLUMN IF EXISTS sync_seq;

-- Drop indexes
DROP INDEX IF EXISTS idx_sync_anchors_user;
DROP INDEX IF EXISTS idx_sync_anchors_device;
DROP INDEX IF EXISTS idx_conv_changes_user_seq;
DROP INDEX IF EXISTS idx_conv_changes_conv;
DROP INDEX IF EXISTS idx_msg_conv_seq;
DROP INDEX IF EXISTS idx_msg_conv_message;
DROP INDEX IF EXISTS idx_msg_conv_conversation;
DROP INDEX IF EXISTS idx_messages_sync_seq;
DROP INDEX IF EXISTS idx_conversations_sync_seq;
