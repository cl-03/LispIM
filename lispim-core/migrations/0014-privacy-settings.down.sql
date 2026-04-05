-- Rollback privacy settings enhancement
DROP INDEX IF EXISTS idx_users_privacy;

ALTER TABLE users
DROP COLUMN IF EXISTS hide_online_status,
DROP COLUMN IF EXISTS hide_read_receipt,
DROP COLUMN IF EXISTS privacy_settings;
