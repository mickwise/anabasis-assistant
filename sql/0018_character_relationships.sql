-- =============================================================================
-- 0018_character_relationships.sql
--
-- Purpose
--   Store directed temporal relationships between canonical characters in the
--   world-state schema. This table exists to represent non-alias,
--   non-membership, non-event interpersonal facts such as kinship, marriage,
--   rivalry, allegiance, mentorship, betrayal, and feudal ties between
--   character entities.
--
-- Row semantics
--   One row represents one directed relationship assertion from a left
--   character to a right character under a specific relationship type,
--   optionally bounded by a start and end era plus year-in-era range.
--
-- Conventions
--   - Relationships are stored as directed edges from `left_character_id` to
--     `right_character_id`; `is_bidirectional` indicates symmetric
--     interpretation but does not create an automatic inverse row.
--   - Temporal validity is expressed with optional era FKs plus nonnegative
--     year-in-era integers instead of a single absolute date type.
--   - `source_confidence` is a normalized numeric score on `[0.0, 1.0]` for the
--     asserted interpersonal fact.
--
-- Keys & constraints
--   - Primary key: `character_relationship_id`
--   - Natural keys / uniqueness: none enforced; the schema allows multiple rows
--     for the same character pair and relationship type when temporal windows,
--     provenance, or interpretation differ.
--   - Checks: no self-loops; `relationship_type` restricted to the allowed
--     character relationship categories; `start_year` and `end_year` must be
--     nonnegative when present; `source_confidence` constrained to `[0, 1]`;
--     `notes` must be nonblank when present.
--
-- Relationships
--   - Owns FKs to `characters(character_id)` twice, through
--     `left_character_id` and `right_character_id`, plus optional FKs to
--     `eras(era_id)` and `events(event_id)` for temporal validity and
--     lifecycle anchoring.
--   - Downstream genealogy, politics, alliance, conflict, succession, and
--     world-state reasoning logic should join through the two character
--     endpoints to interpret the directed character graph.
--
-- Audit & provenance
--   This table records creation time via `created_at` and lightweight
--   confidence and note fields, but it does not store full extraction lineage,
--   adjudication history, or source-document provenance. Detailed provenance
--   should live in higher-level ingestion or event-sourcing tables when needed.
--
-- Performance
--   Secondary indexes on `left_character_id`, `right_character_id`, and
--   `relationship_type` support endpoint-centric traversal and semantic
--   filtering over character relationship facts.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   expanded allowed relationship types over changing the meaning of existing
--   edge direction, temporal fields, or bidirectionality semantics.
-- =============================================================================

CREATE TABLE IF NOT EXISTS character_relationships (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this character-character relation.
    character_relationship_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Left endpoint in this directed relation.
    left_character_id UUID NOT NULL REFERENCES characters (character_id),

    -- Right endpoint in this directed relation.
    right_character_id UUID NOT NULL REFERENCES characters (character_id),

    -- Relation semantic.
    relationship_type TEXT NOT NULL,

    -- Whether relation should be interpreted as bidirectional.
    is_bidirectional BOOLEAN NOT NULL DEFAULT FALSE,

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

    CONSTRAINT character_relationships_chk_no_self_loop
    CHECK (left_character_id <> right_character_id),

    CONSTRAINT character_relationships_chk_relationship_type
    CHECK (
        relationship_type IN (
            'parent_of',
            'child_of',
            'sibling_of',
            'married_to',
            'allied_with',
            'rival_of',
            'betrayed',
            'sworn_to',
            'mentor_of',
            'descendant_of',
            'liege_of',
            'vassal_of'
        )
    ),

    CONSTRAINT character_relationships_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT character_relationships_chk_source_confidence_range
    CHECK (source_confidence >= 0 AND source_confidence <= 1),

    CONSTRAINT character_relationships_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_character_relationships_left_character_id
ON character_relationships (left_character_id);

CREATE INDEX IF NOT EXISTS idx_character_relationships_right_character_id
ON character_relationships (right_character_id);

CREATE INDEX IF NOT EXISTS idx_character_relationships_relationship_type
ON character_relationships (relationship_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE character_relationships IS
'Temporal character-to-character relationships,
including family, political, and sworn ties.';

COMMENT ON COLUMN character_relationships.character_relationship_id IS
'Primary key for this character-character relation row (UUID).';

COMMENT ON COLUMN character_relationships.left_character_id IS
'Left endpoint in this directed relation.';

COMMENT ON COLUMN character_relationships.right_character_id IS
'Right endpoint in this directed relation.';

COMMENT ON COLUMN character_relationships.relationship_type IS
'Relation semantic for this character pair.';

COMMENT ON COLUMN character_relationships.is_bidirectional IS
'Whether this relation should be interpreted as bidirectional.';

COMMENT ON COLUMN character_relationships.start_era_id IS
'Optional start era for relation validity.';

COMMENT ON COLUMN character_relationships.start_year IS
'Optional start year-in-era for relation validity.';

COMMENT ON COLUMN character_relationships.start_is_approximate IS
'Whether relation start timing is approximate.';

COMMENT ON COLUMN character_relationships.end_era_id IS
'Optional end era for relation validity.';

COMMENT ON COLUMN character_relationships.end_year IS
'Optional end year-in-era for relation validity.';

COMMENT ON COLUMN character_relationships.end_is_approximate IS
'Whether relation end timing is approximate.';

COMMENT ON COLUMN character_relationships.established_by_event_id IS
'Event that established this relation.';

COMMENT ON COLUMN character_relationships.ended_by_event_id IS
'Event that ended this relation.';

COMMENT ON COLUMN character_relationships.notes IS
'Optional notes for this relation.';

COMMENT ON COLUMN character_relationships.source_confidence IS
'Confidence score in [0.0, 1.0] for this relation assertion.';

COMMENT ON COLUMN character_relationships.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_character_relationships_left_character_id IS
'Index to accelerate left-endpoint traversal of character relationships.';

COMMENT ON INDEX idx_character_relationships_right_character_id IS
'Index to accelerate right-endpoint traversal of character relationships.';

COMMENT ON INDEX idx_character_relationships_relationship_type IS
'Index to accelerate filtering by character relationship semantic.';
