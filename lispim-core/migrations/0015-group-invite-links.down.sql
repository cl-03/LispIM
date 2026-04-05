-- Drop group invite links feature
-- Rollback: 2026-04-04

-- Drop usage tracking table first (has foreign key dependency)
DROP TABLE IF EXISTS group_invite_link_uses CASCADE;

-- Drop invite links table
DROP TABLE IF EXISTS group_invite_links CASCADE;
