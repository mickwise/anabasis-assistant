-- =============================================================================
-- 0015_organization_locations.sql
--
-- Purpose
--   Store temporal relationships between canonical organizations and canonical
--   locations in the world-state schema. This table exists to represent where
--   an organization is headquartered, active, founded, administratively rooted,
--   politically controlling, or otherwise meaningfully tied to a place.
--
-- Row semantics
--   One row represents one directed organization-to-location relationship fact
--   under a specific relationship type, optionally bounded by a start and end
--   era plus year-in-era range.
--
-- Conventions
--   - Relationships are directed from `organization_id` to `location_id`, so
--     the row meaning is determined jointly by the endpoint order and the
--     `relationship_type` value.
--   - Temporal validity is expressed with optional era FKs plus nonnegative
--     year-in-era integers instead of a single absolute date type.
--   - `source_confidence` is a normalized numeric score on `[0.0, 1.0]` for the
--     asserted organization-location fact.
--
-- Keys & constraints
--   - Primary key: `organization_location_id`
--   - Natural keys / uniqueness: none enforced; the schema allows multiple
--     rows for the same organization, location, and relationship type when
--     temporal windows, provenance, or interpretation differ.
--   - Checks: `relationship_type` restricted to the allowed
--     organization-location semantics; `start_year` and `end_year` must be
--     nonnegative when present; `source_confidence` constrained to `[0, 1]`;
--     `notes` must be nonblank when present.
--
-- Relationships
--   - Owns FKs to `organizations(organization_id)` and `locations(location_id)`
--     plus optional FKs to `eras(era_id)` and `events(event_id)` for temporal
--     validity and lifecycle anchoring.
--   - Downstream world-state reasoning, territorial control, geography, event,
--     and political-structure tables should join through this table to connect
--     canonical organizations with canonical places over time.
--
-- Audit & provenance
--   This table records creation time via `created_at` and lightweight
--   confidence and note fields, but it does not store full extraction lineage,
--   adjudication history, or source-document provenance. Detailed provenance
--   should live in higher-level ingestion or event-sourcing tables when needed.
--
-- Performance
--   Secondary indexes on `organization_id`, `location_id`, and
--   `relationship_type` support endpoint-centric traversal and semantic
--   filtering over organization-location facts.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   expanded allowed relationship types over changing the meaning of existing
--   endpoint direction, temporal fields, or confidence semantics.
-- =============================================================================

CREATE TABLE IF NOT EXISTS organization_locations (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this organization-location relation.
    organization_location_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Organization endpoint.
    organization_id UUID NOT NULL REFERENCES organizations (organization_id),

    -- Location endpoint.
    location_id UUID NOT NULL REFERENCES locations (location_id),

    -- Relation semantic.
    relationship_type TEXT NOT NULL DEFAULT 'active_in',

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
    established_by_event_id UUID REFERENCES events (event_id),

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

    CONSTRAINT organization_locations_chk_relationship_type
    CHECK (
        relationship_type IN (
            'headquartered_in',
            'active_in',
            'controls',
            'founded_in',
            'originated_in',
            'holy_site_in',
            'trade_post_in',
            'chapter_in',
            'claims',
            'administers'
        )
    ),

    CONSTRAINT organization_locations_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT organization_locations_chk_source_confidence_range
    CHECK (source_confidence >= 0 AND source_confidence <= 1),

    CONSTRAINT organization_locations_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_organization_locations_organization_id
ON organization_locations (organization_id);

CREATE INDEX IF NOT EXISTS idx_organization_locations_location_id
ON organization_locations (location_id);

CREATE INDEX IF NOT EXISTS idx_organization_locations_relationship_type
ON organization_locations (relationship_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE organization_locations IS
'Temporal organization-to-location relationships,
including political control and operational presence.';

COMMENT ON COLUMN organization_locations.organization_location_id IS
'Primary key for this organization-location relation row (UUID).';

COMMENT ON COLUMN organization_locations.organization_id IS
'Organization endpoint.';

COMMENT ON COLUMN organization_locations.location_id IS
'Location endpoint.';

COMMENT ON COLUMN organization_locations.relationship_type IS
'Relation semantic (controls/headquartered_in/active_in/etc.).';

COMMENT ON COLUMN organization_locations.start_era_id IS
'Optional start era for relation validity.';

COMMENT ON COLUMN organization_locations.start_year IS
'Optional start year-in-era for relation validity.';

COMMENT ON COLUMN organization_locations.start_is_approximate IS
'Whether relation start timing is approximate.';

COMMENT ON COLUMN organization_locations.end_era_id IS
'Optional end era for relation validity.';

COMMENT ON COLUMN organization_locations.end_year IS
'Optional end year-in-era for relation validity.';

COMMENT ON COLUMN organization_locations.end_is_approximate IS
'Whether relation end timing is approximate.';

COMMENT ON COLUMN organization_locations.established_by_event_id IS
'Event that established this relation.';

COMMENT ON COLUMN organization_locations.ended_by_event_id IS
'Event that ended this relation.';

COMMENT ON COLUMN organization_locations.notes IS
'Optional notes for this relation.';

COMMENT ON COLUMN organization_locations.source_confidence IS
'Confidence score in [0.0, 1.0] for this relation assertion.';

COMMENT ON COLUMN organization_locations.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_organization_locations_organization_id IS
'Index to accelerate organization-centric location lookups.';

COMMENT ON INDEX idx_organization_locations_location_id IS
'Index to accelerate location-centric organization lookups.';

COMMENT ON INDEX idx_organization_locations_relationship_type IS
'Index to accelerate filtering by organization-location relationship semantic.';
