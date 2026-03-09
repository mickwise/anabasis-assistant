-- =============================================================================
-- 0030_agreement_locations.sql
--
-- Purpose
--   Define the join table that records which canonical locations are tied to an
--   agreement and in what role. This exists so agreements can reference places
--   such as signing sites, affected regions, borders, trade zones, and covered
--   holy sites without overloading the core agreements table.
--
-- Row semantics
--   One row represents one agreement-to-location participation fact for a
--   specific role_type. This is a relational fact table rather than a location
--   entity table: one agreement may reference multiple locations, and one
--   location may participate in many agreements under different roles.
--
-- Conventions
--   - agreement_id and location_id are UUID foreign keys and follow the
--     repository's standard surrogate-key conventions.
--   - role_type is stored as lowercase TEXT and constrained to a closed
--     enum-like domain via CHECK rather than a dedicated Postgres ENUM type.
--   - notes is optional free text but, when present, must be non-blank after
--     trimming.
--
-- Keys & constraints
--   - Primary key: (agreement_id, location_id, role_type)
--   - Natural keys / uniqueness: The same location may be attached to the same
--     agreement more than once only when the role_type differs.
--   - Checks: role_type must be one of signed_in, affected_region,
--     demarcated_border, trade_zone, or holy_site_covered; notes must be NULL
--     or trimmed non-empty text.
--
-- Relationships
--   - Owns foreign keys to agreements(agreement_id) and
--     locations(location_id).
--   - Downstream joins should typically enter from agreements via agreement_id
--     to recover all linked locations, or from locations via location_id to
--     recover all agreements that reference a place.
--
-- Audit & provenance
--   This table stores only the current agreement-location relationship and an
--   optional local note. Source-document lineage, extraction metadata, and
--   ingestion provenance are expected to live in upstream pipeline artifacts or
--   dedicated provenance tables rather than here.
--
-- Performance
--   - The composite primary key supports uniqueness enforcement and agreement-
--     anchored lookups.
--   - Secondary index idx_agreement_locations_location_id supports reverse
--     lookups from a location to all linked agreements.
--
-- Change management
--   Extend role semantics additively by widening the CHECK constraint while
--   keeping existing role labels stable. Prefer nullable column additions and
--   new indexes over key-shape changes so downstream joins and loaders remain
--   compatible.
-- =============================================================================

CREATE TABLE IF NOT EXISTS agreement_locations (

    -- ===========
    -- Identifiers
    -- ===========

    -- Agreement endpoint.
    agreement_id UUID NOT NULL REFERENCES agreements (agreement_id),

    -- Location endpoint.
    location_id UUID NOT NULL REFERENCES locations (location_id),

    -- Location role in the agreement.
    role_type TEXT NOT NULL,

    -- Optional notes.
    notes TEXT,

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT agreement_locations_pk
    PRIMARY KEY (agreement_id, location_id, role_type),

    CONSTRAINT agreement_locations_chk_role_type
    CHECK (
        role_type IN (
            'signed_in',
            'affected_region',
            'demarcated_border',
            'trade_zone',
            'holy_site_covered'
        )
    ),

    CONSTRAINT agreement_locations_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_agreement_locations_location_id
ON agreement_locations (location_id);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE agreement_locations IS
'Location involvement in agreements with explicit role labels.';

COMMENT ON COLUMN agreement_locations.agreement_id IS
'Agreement endpoint.';

COMMENT ON COLUMN agreement_locations.location_id IS
'Location endpoint.';

COMMENT ON COLUMN agreement_locations.role_type IS
'Location role in the agreement (signed_in/affected_region/etc.).';

COMMENT ON COLUMN agreement_locations.notes IS
'Optional notes for this location relation.';

COMMENT ON INDEX idx_agreement_locations_location_id IS
'Index to accelerate agreement lookups by affected/signed location.';
