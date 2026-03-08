-- =============================================================================
-- 0019_character_organizations.sql
--
-- Purpose
--   Store temporal relationships between canonical characters and canonical
--   organizations in the world-state schema. This table exists to represent
--   memberships, offices, rulership roles, patronage ties, religious roles,
--   succession positions, and other meaningful character-to-organization
--   connections.
--
-- Row semantics
--   One row represents one directed character-to-organization relationship fact
--   under a specific relationship type, optionally bounded by a start and end
--   era plus year-in-era range.
--
-- Conventions
--   - Relationships are directed from `character_id` to `organization_id`, so
--     row meaning is determined jointly by the endpoint order and the
--     `relationship_type` value.
--   - Temporal validity is expressed with optional era FKs plus nonnegative
--     year-in-era integers instead of a single absolute date type.
--   - `source_confidence` is a normalized numeric score on `[0.0, 1.0]` for the
--     asserted character-organization fact, and `title_label` is optional free
--     text that captures the specific office or role name used in context.
--
-- Keys & constraints
--   - Primary key: `character_organization_id`
--   - Natural keys / uniqueness: none enforced; the schema allows multiple rows
--     for the same character, organization, and relationship type when
--     temporal windows, titles, provenance, or interpretation differ.
--   - Checks: `relationship_type` restricted to the allowed
--     character-organization semantics; `title_label` must be nonblank when
--     present; `start_year` and `end_year` must be nonnegative when present;
--     `source_confidence` constrained to `[0, 1]`; `notes` must be nonblank
--     when present.
--
-- Relationships
--   - Owns FKs to `characters(character_id)` and
--     `organizations(organization_id)`, plus optional FKs to `eras(era_id)` and
--     `events(event_id)` for temporal validity and lifecycle anchoring.
--   - Downstream membership, leadership, succession, religion, politics, and
--     event interpretation logic should join through this table to connect
--     canonical characters with canonical organizations over time.
--
-- Audit & provenance
--   This table records creation time via `created_at` and lightweight
--   confidence and note fields, but it does not store full extraction lineage,
--   adjudication history, or source-document provenance. Detailed provenance
--   should live in higher-level ingestion or event-sourcing tables when needed.
--
-- Performance
--   Secondary indexes on `character_id`, `organization_id`, and
--   `relationship_type` support endpoint-centric traversal and semantic
--   filtering over character-organization facts.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   expanded allowed relationship types over changing the meaning of existing
--   endpoint direction, temporal fields, or confidence semantics.
-- =============================================================================

CREATE TABLE IF NOT EXISTS character_organizations (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this character-organization relation.
    character_organization_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Character endpoint.
    character_id UUID NOT NULL REFERENCES characters (character_id),

    -- Organization endpoint.
    organization_id UUID NOT NULL REFERENCES organizations (organization_id),

    -- Relation semantic.
    relationship_type TEXT NOT NULL,

    -- Optional title label used in this role (free-text).
    title_label TEXT,

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

    -- Event that established this relation.
    appointed_by_event_id UUID REFERENCES events (event_id),

    -- Event that ended this relation.
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

    CONSTRAINT character_organizations_chk_relationship_type
    CHECK (
        relationship_type IN (
            'founder_of',
            'member_of',
            'leader_of',
            'ruler_of',
            'officer_of',
            'advisor_to',
            'acolyte_of',
            'priest_of',
            'scout_of',
            'mercenary_of',
            'patron_of',
            'heir_of'
        )
    ),

    CONSTRAINT character_organizations_chk_title_label_nonempty
    CHECK (title_label IS NULL OR length(btrim(title_label)) > 0),

    CONSTRAINT character_organizations_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT character_organizations_chk_source_confidence_range
    CHECK (source_confidence >= 0 AND source_confidence <= 1),

    CONSTRAINT character_organizations_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_character_organizations_character_id
ON character_organizations (character_id);

CREATE INDEX IF NOT EXISTS idx_character_organizations_organization_id
ON character_organizations (organization_id);

CREATE INDEX IF NOT EXISTS idx_character_organizations_relationship_type
ON character_organizations (relationship_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE character_organizations IS
'Temporal character-to-organization roles for membership,
rulership, advisory, military, and religious ties.';

COMMENT ON COLUMN character_organizations.character_organization_id IS
'Primary key for this character-organization relation row (UUID).';

COMMENT ON COLUMN character_organizations.character_id IS
'Character endpoint.';

COMMENT ON COLUMN character_organizations.organization_id IS
'Organization endpoint.';

COMMENT ON COLUMN character_organizations.relationship_type IS
'Relation semantic (member_of/ruler_of/founder_of/etc.).';

COMMENT ON COLUMN character_organizations.title_label IS
'Optional title/office label as free text for this relation.';

COMMENT ON COLUMN character_organizations.start_era_id IS
'Optional start era for relation validity.';

COMMENT ON COLUMN character_organizations.start_year IS
'Optional start year-in-era for relation validity.';

COMMENT ON COLUMN character_organizations.start_is_approximate IS
'Whether relation start timing is approximate.';

COMMENT ON COLUMN character_organizations.end_era_id IS
'Optional end era for relation validity.';

COMMENT ON COLUMN character_organizations.end_year IS
'Optional end year-in-era for relation validity.';

COMMENT ON COLUMN character_organizations.end_is_approximate IS
'Whether relation end timing is approximate.';

COMMENT ON COLUMN character_organizations.appointed_by_event_id IS
'Event that established this relation.';

COMMENT ON COLUMN character_organizations.ended_by_event_id IS
'Event that ended this relation.';

COMMENT ON COLUMN character_organizations.notes IS
'Optional notes for this relation.';

COMMENT ON COLUMN character_organizations.source_confidence IS
'Confidence score in [0.0, 1.0] for this relation assertion.';

COMMENT ON COLUMN character_organizations.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_character_organizations_character_id IS
'Index to accelerate character-centric organization role lookups.';

COMMENT ON INDEX idx_character_organizations_organization_id IS
'Index to accelerate organization-centric character role lookups.';

COMMENT ON INDEX idx_character_organizations_relationship_type IS
'Index to accelerate filtering by character-organization relationship
semantic.';
