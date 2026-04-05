-- Migration 008: Group Polls/Voting Support
-- Created: 2026-04-03
-- Description: Add group polls and voting functionality

-- Create polls table
CREATE TABLE IF NOT EXISTS group_polls (
    id BIGSERIAL PRIMARY KEY,
    group_id BIGINT NOT NULL REFERENCES conversations(id) ON DELETE CASCADE,
    created_by BIGINT NOT NULL REFERENCES users(id),
    title VARCHAR(255) NOT NULL,
    description TEXT,
    multiple_choice BOOLEAN DEFAULT FALSE,
    allow_suggestions BOOLEAN DEFAULT FALSE,
    anonymous_voting BOOLEAN DEFAULT FALSE,
    end_at TIMESTAMP WITH TIME ZONE,
    status VARCHAR(20) DEFAULT 'active' CHECK (status IN ('active', 'ended', 'archived')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    ended_at TIMESTAMP WITH TIME ZONE,
    ended_by BIGINT REFERENCES users(id)
);

-- Create poll options table
CREATE TABLE IF NOT EXISTS poll_options (
    id BIGSERIAL PRIMARY KEY,
    poll_id BIGINT NOT NULL REFERENCES group_polls(id) ON DELETE CASCADE,
    text VARCHAR(255) NOT NULL,
    vote_count INTEGER DEFAULT 0,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Create poll votes table
CREATE TABLE IF NOT EXISTS poll_votes (
    id BIGSERIAL PRIMARY KEY,
    poll_id BIGINT NOT NULL REFERENCES group_polls(id) ON DELETE CASCADE,
    option_id BIGINT NOT NULL REFERENCES poll_options(id) ON DELETE CASCADE,
    voter_id BIGINT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (poll_id, voter_id, option_id)
);

-- Create index for poll lookups
CREATE INDEX IF NOT EXISTS idx_group_polls_group_id ON group_polls(group_id);
CREATE INDEX IF NOT EXISTS idx_group_polls_status ON group_polls(status);
CREATE INDEX IF NOT EXISTS idx_poll_options_poll_id ON poll_options(poll_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_poll_id ON poll_votes(poll_id);
CREATE INDEX IF NOT EXISTS idx_poll_votes_voter ON poll_votes(voter_id);

-- Function to get poll results
CREATE OR REPLACE FUNCTION get_poll_results(poll_id BIGINT)
RETURNS TABLE (
    option_id BIGINT,
    option_text VARCHAR,
    vote_count BIGINT,
    percentage NUMERIC,
    voters JSONB
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        po.id,
        po.text,
        COUNT(pv.id)::BIGINT,
        CASE
            WHEN COUNT(pv.id) = 0 THEN 0
            ELSE ROUND((COUNT(pv.id)::NUMERIC / (SELECT SUM(vote_count) FROM poll_options WHERE poll_id = poll_id)) * 100, 2)
        END,
        COALESCE(
            (SELECT json_agg(json_build_object('userId', pv2.voter_id, 'username', u.username))
             FROM poll_votes pv2
             JOIN users u ON pv2.voter_id = u.id
             WHERE pv2.option_id = po.id),
            '[]'::jsonb
        )
    FROM poll_options po
    LEFT JOIN poll_votes pv ON po.id = pv.option_id
    WHERE po.poll_id = poll_id
    GROUP BY po.id, po.text
    ORDER BY po.id;
END;
$$ LANGUAGE plpgsql;

-- Function to end a poll
CREATE OR REPLACE FUNCTION end_poll(poll_id BIGINT, end_user_id BIGINT)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE group_polls
    SET status = 'ended',
        ended_at = CURRENT_TIMESTAMP,
        ended_by = end_user_id,
        updated_at = CURRENT_TIMESTAMP
    WHERE id = poll_id AND status = 'active';
    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Triggers for updated_at
DROP TRIGGER IF EXISTS update_group_polls_updated_at ON group_polls;
CREATE TRIGGER update_group_polls_updated_at
    BEFORE UPDATE ON group_polls
    FOR EACH ROW
    EXECUTE FUNCTION update_updated_at_column();

COMMENT ON TABLE group_polls IS 'Group polls for voting';
COMMENT ON TABLE poll_options IS 'Poll options';
COMMENT ON TABLE poll_votes IS 'Poll votes';
COMMENT ON COLUMN group_polls.multiple_choice IS 'Allow multiple choices per voter';
COMMENT ON COLUMN group_polls.allow_suggestions IS 'Allow members to suggest new options';
COMMENT ON COLUMN group_polls.anonymous_voting IS 'Hide voter identities';
