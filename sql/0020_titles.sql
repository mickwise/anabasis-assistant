-- =============================================================================
-- 0020_titles.sql
--
-- Purpose
--   Store canonical titles and offices in the world-state schema. This table
--   exists to define reusable title entities such as king, archmage, high
--   priest, lord admiral, or council seat so downstream tables can reference
--   stable title definitions rather than repeating free-text office names.
--
-- Row semantics
--   One row represents one canonical title or office definition, not a tenure
--   episode, succession event, or character-to-organization appointment.
--
-- Conventions
--   - `title_name` is stored as free text but must be nonblank after trimming.
--   - `title_type` is a constrained semantic category for broad classification,
--     not a full replacement for the specific title meaning captured in
--     `title_name` and `title_summary`.
--   - `is_inheritable` records whether the title is generally inheritable as a
--     title-level attribute, not whether any specific holder inherited it in a
--     particular historical case.
--
-- Keys & constraints
--   - Primary key: `title_id`
--   - Natural keys / uniqueness: `title_name` is unique across canonical title
--     definitions.
--   - Checks: nonblank trimmed `title_name` and `title_summary`;
--     `title_type` restricted to the allowed title categories.
--
-- Relationships
--   - This table does not own outbound foreign keys.
--   - Downstream title-tenure, succession, appointment, rulership, and
--     organization-role tables should join to this table on `title_id` to
--     reference the canonical title or office being held.
--
-- Audit & provenance
--   This table records row creation time via `created_at` but does not store
--   source-document lineage, extraction metadata, or adjudication history.
--   Detailed provenance for title definitions should live in higher-level
--   ingestion or event-sourcing tables when needed.
--
-- Performance
--   A secondary index on `title_type` supports filtering, browsing, and lookup
--   by broad title category.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   expanded allowed `title_type` values over changing the meaning of existing
--   title names, inheritable semantics, or canonical title identity.
-- =============================================================================

CREATE TABLE IF NOT EXISTS titles (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this title definition.
    title_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Canonical title name (e.g., "King", "Archmage", "Lord Admiral").
    title_name TEXT UNIQUE NOT NULL,

    -- Title category.
    title_type TEXT NOT NULL DEFAULT 'other',

    -- Short summary for this title/office.
    title_summary TEXT NOT NULL,

    -- Whether this title is generally inheritable.
    is_inheritable BOOLEAN NOT NULL DEFAULT FALSE,

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT titles_chk_title_name_nonempty
    CHECK (length(btrim(title_name)) > 0),

    CONSTRAINT titles_chk_title_summary_nonempty
    CHECK (length(btrim(title_summary)) > 0),

    CONSTRAINT titles_chk_title_type
    CHECK (
        title_type IN (
            'royal',
            'noble',
            'military',
            'religious',
            'civic',
            'scholarly',
            'administrative',
            'other'
        )
    )
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_titles_title_type
ON titles (title_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE titles IS
'One row per office/title definition used for
world-state office tenure queries.';

COMMENT ON COLUMN titles.title_id IS
'Primary key for this title definition (UUID).';

COMMENT ON COLUMN titles.title_name IS
'Canonical title name (e.g., King, Archmage, Lord Admiral).';

COMMENT ON COLUMN titles.title_type IS
'Title category (royal/military/religious/etc.).';

COMMENT ON COLUMN titles.title_summary IS
'Short summary of what this title/office means.';

COMMENT ON COLUMN titles.is_inheritable IS
'Whether this title is generally inheritable.';

COMMENT ON COLUMN titles.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_titles_title_type IS
'Index to accelerate filtering and browsing by title category.';
