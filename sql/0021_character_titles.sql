-- =============================================================================
-- 0021_character_titles.sql
--
-- Purpose
--   Store temporal title-tenure facts connecting canonical characters to
--   canonical titles in the world-state schema. This table exists to represent
--   when a character held a specific title, optionally scoped to an
--   organization or location and optionally anchored to assumption and ending
--   events.
--
-- Row semantics
--   One row represents one title-holding tenure fact for one canonical
--   character and one canonical title, optionally bounded by start and end era
--   plus year-in-era values.
--
-- Conventions
--   - Tenure rows are directed from `character_id` to `title_id`, with
--     optional `organization_id` and `location_id` used to scope the office or
--     rank in context rather than define a separate title entity.
--   - Temporal validity is expressed with optional era FKs plus nonnegative
--     year-in-era integers, and `start_is_approximate` or
--     `end_is_approximate` mark uncertain dating without requiring separate
--     fuzzy-date fields.
--   - `source_confidence` is a normalized numeric score on `[0.0, 1.0]` for the
--     asserted tenure fact.
--
-- Keys & constraints
--   - Primary key: `character_title_id`
--   - Natural keys / uniqueness: none enforced; the schema allows multiple rows
--     for the same character, title, organization, and location combination
--     when temporal windows, provenance, or interpretation differ.
--   - Checks: `start_year` and `end_year` must be nonnegative when present;
--     `source_confidence` constrained to `[0, 1]`; `notes` must be nonblank
--     when present.
--
-- Relationships
--   - Owns FKs to `characters(character_id)`, `titles(title_id)`, and optional
--     FKs to `organizations(organization_id)`, `locations(location_id)`,
--     `eras(era_id)`, and `events(event_id)` for scope, temporal validity, and
--     lifecycle anchoring.
--   - Downstream succession, rulership, office-history, and event
--     interpretation logic should join through this table to determine which
--     character held which title, where, and when.
--
-- Audit & provenance
--   This table records creation time via `created_at` and lightweight
--   confidence and note fields, but it does not store full extraction lineage,
--   adjudication history, or source-document provenance. Detailed provenance
--   should live in higher-level ingestion or event-sourcing tables when needed.
--
-- Performance
--   Secondary indexes on `character_id`, `title_id`, `organization_id`,
--   `location_id`, and `(start_era_id, start_year)` support endpoint-centric
--   lookup and temporal tenure queries.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   companion relationship tables over changing the meaning of existing tenure
--   endpoints, scope fields, or approximate-date semantics.
-- =============================================================================

CREATE TABLE IF NOT EXISTS character_titles (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this title tenure row.
    character_title_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Character who held the title.
    character_id UUID NOT NULL REFERENCES characters (character_id),

    -- Title being held.
    title_id UUID NOT NULL REFERENCES titles (title_id),

    -- Optional organization scope for this office.
    organization_id UUID REFERENCES organizations (organization_id),

    -- Optional location scope for this office.
    location_id UUID REFERENCES locations (location_id),

    -- Optional temporal start era.
    start_era_id UUID REFERENCES eras (era_id),

    -- Optional temporal start year-in-era.
    start_year INTEGER,

    -- Whether start timing is approximate.
    start_is_approximate BOOLEAN NOT NULL DEFAULT FALSE,

    -- Optional temporal end era.
    end_era_id UUID REFERENCES eras (era_id),

    -- Optional temporal end year-in-era.
    end_year INTEGER,

    -- Whether end timing is approximate.
    end_is_approximate BOOLEAN NOT NULL DEFAULT FALSE,

    -- Event where this title tenure began.
    assumed_by_event_id UUID REFERENCES events (event_id),

    -- Event where this title tenure ended.
    ended_by_event_id UUID REFERENCES events (event_id),

    -- Optional notes.
    notes TEXT,

    -- Confidence score in [0.0, 1.0].
    source_confidence NUMERIC(4, 3) NOT NULL DEFAULT 0.500,

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT character_titles_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT character_titles_chk_source_confidence_range
    CHECK (source_confidence >= 0 AND source_confidence <= 1),

    CONSTRAINT character_titles_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_character_titles_character_id
ON character_titles (character_id);

CREATE INDEX IF NOT EXISTS idx_character_titles_title_id
ON character_titles (title_id);

CREATE INDEX IF NOT EXISTS idx_character_titles_organization_id
ON character_titles (organization_id);

CREATE INDEX IF NOT EXISTS idx_character_titles_location_id
ON character_titles (location_id);

CREATE INDEX IF NOT EXISTS idx_character_titles_start_era_year
ON character_titles (start_era_id, start_year);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE character_titles IS
'Temporal title tenures held by characters,
with optional organization/location scope.';

COMMENT ON COLUMN character_titles.character_title_id IS
'Primary key for this character title tenure row (UUID).';

COMMENT ON COLUMN character_titles.character_id IS
'Character who held the title.';

COMMENT ON COLUMN character_titles.title_id IS
'Title being held.';

COMMENT ON COLUMN character_titles.organization_id IS
'Optional organization scope for this office.';

COMMENT ON COLUMN character_titles.location_id IS
'Optional location scope for this office.';

COMMENT ON COLUMN character_titles.start_era_id IS
'Optional start era for title tenure.';

COMMENT ON COLUMN character_titles.start_year IS
'Optional start year-in-era for title tenure.';

COMMENT ON COLUMN character_titles.start_is_approximate IS
'Whether title tenure start timing is approximate.';

COMMENT ON COLUMN character_titles.end_era_id IS
'Optional end era for title tenure.';

COMMENT ON COLUMN character_titles.end_year IS
'Optional end year-in-era for title tenure.';

COMMENT ON COLUMN character_titles.end_is_approximate IS
'Whether title tenure end timing is approximate.';

COMMENT ON COLUMN character_titles.assumed_by_event_id IS
'Event where this title tenure began.';

COMMENT ON COLUMN character_titles.ended_by_event_id IS
'Event where this title tenure ended.';

COMMENT ON COLUMN character_titles.notes IS
'Optional notes for this title tenure.';

COMMENT ON COLUMN character_titles.source_confidence IS
'Confidence score in [0.0, 1.0] for this tenure assertion.';

COMMENT ON COLUMN character_titles.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_character_titles_character_id IS
'Index to accelerate character-centric title tenure lookups.';

COMMENT ON INDEX idx_character_titles_title_id IS
'Index to accelerate title-centric holder lookups.';

COMMENT ON INDEX idx_character_titles_organization_id IS
'Index to accelerate office-holder lookup by organization scope.';

COMMENT ON INDEX idx_character_titles_location_id IS
'Index to accelerate office-holder lookup by location scope.';

COMMENT ON INDEX idx_character_titles_start_era_year IS
'Index to accelerate temporal title-holder queries by era/year.';
