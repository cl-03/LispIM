-- Migration 008 Down: Remove Group Polls Support
-- Created: 2026-04-03

-- Drop tables
DROP TABLE IF EXISTS poll_votes;
DROP TABLE IF EXISTS poll_options;
DROP TABLE IF EXISTS group_polls;
