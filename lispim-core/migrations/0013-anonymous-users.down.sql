-- Migration 0013: Anonymous Users Support (Rollback)
-- Remove is_anonymous column from users table

-- Drop indexes
DROP INDEX IF EXISTS idx_users_is_anonymous;
DROP INDEX IF EXISTS idx_users_created_at;

-- Remove column
ALTER TABLE users DROP COLUMN IF EXISTS is_anonymous;
