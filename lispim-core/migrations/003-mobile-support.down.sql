-- Migration 003: Mobile Support (Rollback)
-- Created: 2026-03-23

-- Drop push notifications log table
DROP TABLE IF EXISTS push_notifications;

-- Drop device_sessions table
DROP TABLE IF EXISTS device_sessions;

-- Remove FCM columns from users table
ALTER TABLE users
DROP COLUMN IF EXISTS fcm_token,
DROP COLUMN IF EXISTS device_id,
DROP COLUMN IF EXISTS platform,
DROP COLUMN IF EXISTS push_enabled;
