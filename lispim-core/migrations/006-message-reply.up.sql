-- Migration 006: Message Reply/Quote/Thread Support
-- Creates tables for message replies, quotes, and thread management

-- Message replies table
CREATE TABLE IF NOT EXISTS message_replies (
    id BIGSERIAL PRIMARY KEY,
    message_id BIGINT NOT NULL UNIQUE,
    reply_to_id BIGINT NOT NULL,
    conversation_id BIGINT NOT NULL,
    sender_id BIGINT NOT NULL,
    quote_content TEXT,
    quote_type VARCHAR(32) DEFAULT 'text',
    depth INTEGER NOT NULL DEFAULT 0,
    created_at INTEGER NOT NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (reply_to_id) REFERENCES messages(id) ON DELETE CASCADE,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE,
    FOREIGN KEY (sender_id) REFERENCES users(id) ON DELETE CASCADE
);

-- Indexes for efficient reply queries
CREATE INDEX IF NOT EXISTS idx_message_replies_reply_to ON message_replies(reply_to_id);
CREATE INDEX IF NOT EXISTS idx_message_replies_conversation ON message_replies(conversation_id);
CREATE INDEX IF NOT EXISTS idx_message_replies_sender ON message_replies(sender_id);
CREATE INDEX IF NOT EXISTS idx_message_replies_depth ON message_replies(depth);
CREATE INDEX IF NOT EXISTS idx_message_replies_created ON message_replies(created_at);

-- Notifications table (if not exists, extend for reply notifications)
CREATE TABLE IF NOT EXISTS notifications (
    id VARCHAR(64) PRIMARY KEY,
    user_id BIGINT NOT NULL,
    type VARCHAR(32) NOT NULL,
    related_user_id BIGINT,
    message_id BIGINT,
    conversation_id BIGINT,
    created_at INTEGER NOT NULL,
    is_read BOOLEAN NOT NULL DEFAULT FALSE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (related_user_id) REFERENCES users(id) ON DELETE SET NULL,
    FOREIGN KEY (message_id) REFERENCES messages(id) ON DELETE SET NULL,
    FOREIGN KEY (conversation_id) REFERENCES conversations(id) ON DELETE CASCADE
);

-- Indexes for notifications
CREATE INDEX IF NOT EXISTS idx_notifications_user ON notifications(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_type ON notifications(type);
CREATE INDEX IF NOT EXISTS idx_notifications_read ON notifications(is_read);
CREATE INDEX IF NOT EXISTS idx_notifications_created ON notifications(created_at);

-- Add reply_count to messages for caching
ALTER TABLE messages ADD COLUMN IF NOT EXISTS reply_count INTEGER NOT NULL DEFAULT 0;

-- Create index if not exists (using DO block for conditional creation)
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_indexes WHERE indexname = 'idx_messages_reply_count') THEN
        CREATE INDEX idx_messages_reply_count ON messages(reply_count);
    END IF;
END $$;

COMMENT ON TABLE message_replies IS '消息回复关系表 - 存储回复/引用关系';
COMMENT ON COLUMN message_replies.message_id IS '回复消息 ID';
COMMENT ON COLUMN message_replies.reply_to_id IS '被回复的消息 ID';
COMMENT ON COLUMN message_replies.conversation_id IS '会话 ID';
COMMENT ON COLUMN message_replies.sender_id IS '回复者用户 ID';
COMMENT ON COLUMN message_replies.quote_content IS '引用内容预览';
COMMENT ON COLUMN message_replies.quote_type IS '引用内容类型 (text/image/file)';
COMMENT ON COLUMN message_replies.depth IS '回复深度 (用于嵌套回复)';
COMMENT ON TABLE notifications IS '通知表 - 支持回复通知等多种类型';
