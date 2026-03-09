-- =============================================================================
-- 0024_artifact_locations.sql
--
-- Purpose
--   Store temporal relationships between canonical artifacts and canonical
--   locations in the world-state schema. This table exists to represent where
--   an artifact is stored, hidden, found, lost, displayed, transported, or last
--   known to have been located over time.
--
-- Row semantics
--   One row represents one directed artifact-to-location relationship fact
--   under a specific relationship type, optionally bounded by a start and end
--   era plus year-in-era range.
--
-- Conventions
--   - Relationships are directed from `artifact_id` to `location_id`, so row
--     meaning is determined jointly by the endpoint order and the
--     `relationship_type` value.
--   - Temporal validity is expressed with optional era FKs plus nonnegative
--     year-in-era integers, and `start_is_approximate` or
--     `end_is_approximate` mark uncertain dating without requiring separate
--     fuzzy-date fields.
--   - `source_confidence` is a normalized numeric score on `[0.0, 1.0]` for the
--     asserted artifact-location fact.
--
-- Keys & constraints
--   - Primary key: `artifact_location_id`
--   - Natural keys / uniqueness: none enforced; the schema allows multiple rows
--     for the same artifact, location, and relationship type when temporal
--     windows, provenance, or interpretation differ.
--   - Checks: `relationship_type` restricted to the allowed
--     artifact-location semantics; `start_year` and `end_year` must be
--     nonnegative when present; `source_confidence` constrained to `[0, 1]`;
--     `notes` must be nonblank when present.
--
-- Relationships
--   - Owns FKs to `artifacts(artifact_id)` and `locations(location_id)`, plus
--     optional FKs to `eras(era_id)` and `events(event_id)` for temporal
--     validity and lifecycle anchoring.
--   - Downstream inventory, provenance, search, quest, and event
--     interpretation logic should join through this table to connect canonical
--     artifacts with canonical places over time.
--
-- Audit & provenance
--   This table records creation time via `created_at` and a lightweight
--   confidence score, but it does not store full extraction lineage,
--   adjudication history, or complete provenance chains. Detailed provenance
--   should live in higher-level ingestion or event-sourcing tables when needed.
--
-- Performance
--   Secondary indexes on `artifact_id`, `location_id`, and `relationship_type`
--   support endpoint-centric traversal and semantic filtering over
--   artifact-location facts.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   companion history tables over changing the meaning of existing endpoint
--   direction, temporal fields, or confidence semantics.
-- =============================================================================

CREATE TABLE IF NOT EXISTS artifact_locations (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this artifact-location relation.
    artifact_location_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Artifact endpoint.
    artifact_id UUID NOT NULL REFERENCES artifacts (artifact_id),

    -- Location endpoint.
    location_id UUID NOT NULL REFERENCES locations (location_id),

    -- Relation semantic.
    relationship_type TEXT NOT NULL DEFAULT 'stored_in',

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

    CONSTRAINT artifact_locations_chk_relationship_type
    CHECK (
        relationship_type IN (
            'stored_in',
            'hidden_in',
            'found_in',
            'lost_in',
            'displayed_in',
            'transported_through',
            'last_known_in'
        )
    ),

    CONSTRAINT artifact_locations_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT artifact_locations_chk_source_confidence_range
    CHECK (source_confidence >= 0 AND source_confidence <= 1),

    CONSTRAINT artifact_locations_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_artifact_locations_artifact_id
ON artifact_locations (artifact_id);

CREATE INDEX IF NOT EXISTS idx_artifact_locations_location_id
ON artifact_locations (location_id);

CREATE INDEX IF NOT EXISTS idx_artifact_locations_relationship_type
ON artifact_locations (relationship_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE artifact_locations IS
'Temporal artifact-to-location relations for storage,
discovery, loss, movement, and last-known position.';

COMMENT ON COLUMN artifact_locations.artifact_location_id IS
'Primary key for this artifact-location relation row (UUID).';

COMMENT ON COLUMN artifact_locations.artifact_id IS
'Artifact endpoint.';

COMMENT ON COLUMN artifact_locations.location_id IS
'Location endpoint.';

COMMENT ON COLUMN artifact_locations.relationship_type IS
'Relation semantic (stored_in/hidden_in/found_in/etc.).';

COMMENT ON COLUMN artifact_locations.start_era_id IS
'Optional start era for relation validity.';

COMMENT ON COLUMN artifact_locations.start_year IS
'Optional start year-in-era for relation validity.';

COMMENT ON COLUMN artifact_locations.start_is_approximate IS
'Whether relation start timing is approximate.';

COMMENT ON COLUMN artifact_locations.end_era_id IS
'Optional end era for relation validity.';

COMMENT ON COLUMN artifact_locations.end_year IS
'Optional end year-in-era for relation validity.';

COMMENT ON COLUMN artifact_locations.end_is_approximate IS
'Whether relation end timing is approximate.';

COMMENT ON COLUMN artifact_locations.established_by_event_id IS
'Event that established this relation.';

COMMENT ON COLUMN artifact_locations.ended_by_event_id IS
'Event that ended this relation.';

COMMENT ON COLUMN artifact_locations.notes IS
'Optional notes for this relation.';

COMMENT ON COLUMN artifact_locations.source_confidence IS
'Confidence score in [0.0, 1.0] for this relation assertion.';

COMMENT ON COLUMN artifact_locations.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_artifact_locations_artifact_id IS
'Index to accelerate artifact-centric provenance lookups.';

COMMENT ON INDEX idx_artifact_locations_location_id IS
'Index to accelerate location-centric artifact provenance lookups.';

COMMENT ON INDEX idx_artifact_locations_relationship_type IS
'Index to accelerate filtering by artifact-location relationship semantic.';
