-- Migration 012 Down: Remove Link Preview Support
-- Created: 2026-04-03

-- Drop functions
DROP FUNCTION IF EXISTS cleanup_expired_link_previews();
DROP FUNCTION IF EXISTS invalidate_link_preview(TEXT);
DROP FUNCTION IF EXISTS store_link_preview(TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, JSONB, INTEGER);
DROP FUNCTION IF EXISTS get_or_create_link_preview(TEXT, INTEGER);

-- Drop table
DROP TABLE IF EXISTS link_preview_cache;
