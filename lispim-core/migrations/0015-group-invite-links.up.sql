-- Group invite links feature
-- Created: 2026-04-04

-- Group invite links table
CREATE TABLE IF NOT EXISTS group_invite_links (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT REFERENCES groups(id) ON DELETE CASCADE,
    code VARCHAR(50) UNIQUE NOT NULL,
    created_by VARCHAR(255) NOT NULL,
    max_uses INTEGER DEFAULT 0,
    used_count INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ DEFAULT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE(code)
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_group_invite_links_code ON group_invite_links(code);
CREATE INDEX IF NOT EXISTS idx_group_invite_links_group ON group_invite_links(group_id);

-- Group invite link usage tracking table
CREATE TABLE IF NOT EXISTS group_invite_link_uses (
    id BIGSERIAL PRIMARY KEY,
    link_id BIGINT REFERENCES group_invite_links(id) ON DELETE CASCADE,
    user_id VARCHAR(255) NOT NULL,
    joined_at TIMESTAMPTZ DEFAULT NOW()
);

-- Index for usage lookups
CREATE INDEX IF NOT EXISTS idx_group_invite_uses_link ON group_invite_link_uses(link_id);

-- Comments
COMMENT ON TABLE group_invite_links IS 'Stores group invite link metadata';
COMMENT ON TABLE group_invite_link_uses IS 'Tracks user joins via invite links';
COMMENT ON COLUMN group_invite_links.max_uses IS 'Maximum number of times this link can be used (0 = unlimited)';
COMMENT ON COLUMN group_invite_links.expires_at IS 'Expiration timestamp (NULL = never expires)';
COMMENT ON COLUMN group_invite_links.revoked_at IS 'Revocation timestamp (NULL = still valid)';
