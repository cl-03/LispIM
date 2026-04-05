-- Migration 0013: Anonymous Users Support
-- Add is_anonymous column to users table
-- Enables anonymous registration (no phone/email required)
-- Reference: Session, Threema anonymous registration

-- Add is_anonymous column to users table
ALTER TABLE users ADD COLUMN IF NOT EXISTS is_anonymous BOOLEAN DEFAULT FALSE;

-- Add index for querying anonymous users (if needed for privacy controls)
CREATE INDEX IF NOT EXISTS idx_users_is_anonymous ON users(is_anonymous);

-- Add created_at index for user cleanup (optional)
CREATE INDEX IF NOT EXISTS idx_users_created_at ON users(created_at);

-- Comment
COMMENT ON COLUMN users.is_anonymous IS 'Indicates if user was registered anonymously (no phone/email)';
