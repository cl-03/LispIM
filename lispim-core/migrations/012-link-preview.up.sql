-- Migration 012: Link Preview (链接预览)
-- Created: 2026-04-03
-- Description: Add automatic link preview generation and caching

-- Create link preview cache table
CREATE TABLE IF NOT EXISTS link_preview_cache (
    id BIGSERIAL PRIMARY KEY,
    url TEXT NOT NULL UNIQUE,
    title TEXT,
    description TEXT,
    image_url TEXT,
    site_name TEXT,
    favicon_url TEXT,
    domain TEXT,
    content_type TEXT,
    fetched_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP WITH TIME ZONE,
    is_valid BOOLEAN DEFAULT TRUE,
    error_message TEXT,
    metadata JSONB DEFAULT '{}'::jsonb
);

-- Create indexes
CREATE INDEX IF NOT EXISTS idx_link_preview_cache_url
    ON link_preview_cache(url);
CREATE INDEX IF NOT EXISTS idx_link_preview_cache_domain
    ON link_preview_cache(domain);
CREATE INDEX IF NOT EXISTS idx_link_preview_cache_expires
    ON link_preview_cache(expires_at) WHERE expires_at IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_link_preview_cache_valid
    ON link_preview_cache(is_valid) WHERE is_valid = TRUE;

-- Function to get or create link preview
CREATE OR REPLACE FUNCTION get_or_create_link_preview(
    preview_url TEXT,
    cache_duration_hours INTEGER DEFAULT 24
)
RETURNS TABLE (
    preview_id BIGINT,
    url TEXT,
    title TEXT,
    description TEXT,
    image_url TEXT,
    site_name TEXT,
    favicon_url TEXT,
    domain TEXT,
    is_valid BOOLEAN,
    fetched_at TIMESTAMPTZ
) AS $$
DECLARE
    cached_record RECORD;
BEGIN
    -- Try to find valid cached preview
    SELECT * INTO cached_record
    FROM link_preview_cache
    WHERE url = preview_url
      AND is_valid = TRUE
      AND (expires_at IS NULL OR expires_at > CURRENT_TIMESTAMP);

    IF FOUND THEN
        RETURN QUERY SELECT
            cached_record.id,
            cached_record.url,
            cached_record.title,
            cached_record.description,
            cached_record.image_url,
            cached_record.site_name,
            cached_record.favicon_url,
            cached_record.domain,
            cached_record.is_valid,
            cached_record.fetched_at;
        RETURN;
    END IF;

    -- Return NULL for caller to fetch
    RETURN QUERY SELECT
        NULL::BIGINT,
        preview_url,
        NULL::TEXT,
        NULL::TEXT,
        NULL::TEXT,
        NULL::TEXT,
        NULL::TEXT,
        NULL::TEXT,
        TRUE,
        CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Function to store link preview
CREATE OR REPLACE FUNCTION store_link_preview(
    preview_url TEXT,
    preview_title TEXT DEFAULT NULL,
    preview_description TEXT DEFAULT NULL,
    preview_image_url TEXT DEFAULT NULL,
    preview_site_name TEXT DEFAULT NULL,
    preview_favicon_url TEXT DEFAULT NULL,
    preview_domain TEXT DEFAULT NULL,
    preview_content_type TEXT DEFAULT NULL,
    preview_metadata JSONB DEFAULT '{}'::jsonb,
    cache_duration_hours INTEGER DEFAULT 24
)
RETURNS BIGINT AS $$
DECLARE
    preview_id BIGINT;
    expire_time TIMESTAMP WITH TIME ZONE;
BEGIN
    -- Calculate expiration time
    expire_time := CURRENT_TIMESTAMP + (cache_duration_hours || ' hours')::INTERVAL;

    -- Upsert logic
    INSERT INTO link_preview_cache (
        url, title, description, image_url, site_name,
        favicon_url, domain, content_type, metadata, expires_at, is_valid, fetched_at
    ) VALUES (
        preview_url, preview_title, preview_description, preview_image_url,
        preview_site_name, preview_favicon_url, preview_domain, preview_content_type,
        preview_metadata, expire_time, TRUE, CURRENT_TIMESTAMP
    )
    ON CONFLICT (url) DO UPDATE SET
        title = EXCLUDED.title,
        description = EXCLUDED.description,
        image_url = EXCLUDED.image_url,
        site_name = EXCLUDED.site_name,
        favicon_url = EXCLUDED.favicon_url,
        domain = EXCLUDED.domain,
        content_type = EXCLUDED.content_type,
        metadata = EXCLUDED.metadata,
        expires_at = EXCLUDED.expires_at,
        fetched_at = CURRENT_TIMESTAMP,
        is_valid = TRUE,
        error_message = NULL
    RETURNING id INTO preview_id;

    RETURN preview_id;
END;
$$ LANGUAGE plpgsql;

-- Function to invalidate link preview cache
CREATE OR REPLACE FUNCTION invalidate_link_preview(preview_url TEXT)
RETURNS BOOLEAN AS $$
BEGIN
    UPDATE link_preview_cache
    SET is_valid = FALSE,
        expires_at = CURRENT_TIMESTAMP
    WHERE url = preview_url;

    RETURN FOUND;
END;
$$ LANGUAGE plpgsql;

-- Function to cleanup expired cache entries
CREATE OR REPLACE FUNCTION cleanup_expired_link_previews()
RETURNS INTEGER AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    DELETE FROM link_preview_cache
    WHERE expires_at IS NOT NULL
      AND expires_at < CURRENT_TIMESTAMP;

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$ LANGUAGE plpgsql;

COMMENT ON TABLE link_preview_cache IS 'Cache for link preview metadata (Open Graph, etc.)';
COMMENT ON COLUMN link_preview_cache.title IS 'Page title from Open Graph or <title> tag';
COMMENT ON COLUMN link_preview_cache.description IS 'Page description from Open Graph or meta description';
COMMENT ON COLUMN link_preview_cache.image_url IS 'Preview image from Open Graph og:image';
COMMENT ON COLUMN link_preview_cache.site_name IS 'Site name from og:site_name';
COMMENT ON COLUMN link_preview_cache.favicon_url IS 'Favicon URL for the domain';
COMMENT ON COLUMN link_preview_cache.domain IS 'Extracted domain from URL';
COMMENT ON COLUMN link_preview_cache.metadata IS 'Additional metadata as JSONB';
COMMENT ON COLUMN link_preview_cache.expires_at IS 'Cache expiration timestamp';
