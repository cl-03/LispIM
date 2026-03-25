-- Migration 002: Friend System
-- Created: 2026-03-23
-- Description: Friend management tables for social features

-- Friends table - stores bidirectional friend relationships
CREATE TABLE IF NOT EXISTS friends (
    id BIGSERIAL PRIMARY KEY,
    user_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    friend_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'blocked', 'deleted')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (user_id, friend_id)
);

-- Friend requests table - stores incoming and outgoing friend requests
CREATE TABLE IF NOT EXISTS friend_requests (
    id BIGSERIAL PRIMARY KEY,
    sender_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    receiver_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    message TEXT,
    status VARCHAR(50) DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'rejected', 'cancelled')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    responded_at TIMESTAMP WITH TIME ZONE
);

-- File uploads table - stores uploaded file metadata
CREATE TABLE IF NOT EXISTS file_uploads (
    id BIGSERIAL PRIMARY KEY,
    file_id UUID DEFAULT uuid_generate_v4() UNIQUE NOT NULL,
    original_filename VARCHAR(255) NOT NULL,
    stored_filename VARCHAR(255) NOT NULL,
    file_path VARCHAR(500) NOT NULL,
    file_size BIGINT NOT NULL,
    mime_type VARCHAR(100) NOT NULL,
    uploader_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    download_count INTEGER DEFAULT 0,
    is_public BOOLEAN DEFAULT FALSE,
    expires_at TIMESTAMP WITH TIME ZONE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_friends_user_id ON friends(user_id);
CREATE INDEX IF NOT EXISTS idx_friends_friend_id ON friends(friend_id);
CREATE INDEX IF NOT EXISTS idx_friends_status ON friends(status);
CREATE INDEX IF NOT EXISTS idx_friends_user_status ON friends(user_id, status);

CREATE INDEX IF NOT EXISTS idx_friend_requests_sender ON friend_requests(sender_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_receiver ON friend_requests(receiver_id);
CREATE INDEX IF NOT EXISTS idx_friend_requests_status ON friend_requests(status);
CREATE INDEX IF NOT EXISTS idx_friend_requests_created ON friend_requests(created_at DESC);

CREATE INDEX IF NOT EXISTS idx_file_uploads_file_id ON file_uploads(file_id);
CREATE INDEX IF NOT EXISTS idx_file_uploads_uploader_id ON file_uploads(uploader_id);
CREATE INDEX IF NOT EXISTS idx_file_uploads_is_public ON file_uploads(is_public);

-- Add triggers for updated_at
DROP TRIGGER IF EXISTS update_friends_updated_at ON friends;
CREATE TRIGGER update_friends_updated_at
    BEFORE UPDATE ON friends
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

DROP TRIGGER IF EXISTS update_friend_requests_updated_at ON friend_requests;
CREATE TRIGGER update_friend_requests_updated_at
    BEFORE UPDATE ON friend_requests
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

-- Function to get friend count for a user
CREATE OR REPLACE FUNCTION get_friend_count(p_user_id BIGINT)
RETURNS INTEGER AS $$
DECLARE
    count INTEGER;
BEGIN
    SELECT COUNT(*) INTO count
    FROM friends
    WHERE (user_id = p_user_id OR friend_id = p_user_id)
      AND status = 'accepted';
    RETURN count;
END;
$$ LANGUAGE plpgsql;

-- Function to check if two users are friends
CREATE OR REPLACE FUNCTION are_friends(p_user1_id BIGINT, p_user2_id BIGINT)
RETURNS BOOLEAN AS $$
DECLARE
    result BOOLEAN;
BEGIN
    SELECT EXISTS (
        SELECT 1 FROM friends
        WHERE ((user_id = p_user1_id AND friend_id = p_user2_id)
           OR (user_id = p_user2_id AND friend_id = p_user1_id))
          AND status = 'accepted'
    ) INTO result;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Comments
COMMENT ON TABLE friends IS 'Friend relationships between users';
COMMENT ON TABLE friend_requests IS 'Friend requests sent and received';
COMMENT ON TABLE file_uploads IS 'Uploaded file metadata and storage info';
COMMENT ON COLUMN friends.status IS 'pending: waiting for acceptance, accepted: friends, blocked: blocked, deleted: removed';
COMMENT ON COLUMN friend_requests.status IS 'pending: waiting for response, accepted: request accepted, rejected: request rejected, cancelled: request cancelled';
