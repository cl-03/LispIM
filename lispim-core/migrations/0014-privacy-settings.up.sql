-- Privacy Settings Enhancement
-- Add user privacy settings for hiding online status and read receipts

-- Add privacy settings columns to users table
ALTER TABLE users
ADD COLUMN IF NOT EXISTS hide_online_status BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS hide_read_receipt BOOLEAN DEFAULT FALSE,
ADD COLUMN IF NOT EXISTS privacy_settings JSONB DEFAULT '{"hide_online_status": false, "hide_read_receipt": false, "show_profile_photo": true, "show_last_seen": true}'::jsonb;

-- Create index for privacy settings lookup
CREATE INDEX IF NOT EXISTS idx_users_privacy ON users(id) INCLUDE (hide_online_status, hide_read_receipt);

-- Comment
COMMENT ON COLUMN users.hide_online_status IS 'Hide user online status from others';
COMMENT ON COLUMN users.hide_read_receipt IS 'Hide read receipts when user reads messages';
COMMENT ON COLUMN users.privacy_settings IS 'User privacy preferences in JSON format';
