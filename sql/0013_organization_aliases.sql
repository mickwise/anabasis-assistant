-- =============================================================================
-- 0013_organization_aliases.sql
--
-- Purpose
--   Store alternate, former, local, translated, honorific, and acronym-style
--   names for canonical organizations in the world-state schema. This table
--   exists so the system can resolve multiple surface names back to a single
--   organization entity, optionally scoped to a historical validity window.
--
-- Row semantics
--   One row represents one alias fact for one canonical organization,
--   optionally bounded by a start and end era plus year-in-era range.
--
-- Conventions
--   - `alias_name` is stored as free text but must be nonblank after trimming.
--   - Temporal validity is modeled with optional era FKs plus nonnegative
--     year-in-era integers, rather than a single absolute date type.
--   - Rows are append-oriented historical facts; prefer inserting a new row for
--     a distinct alias period or alias type rather than overwriting prior
--     meaning.
--
-- Keys & constraints
--   - Primary key: `organization_alias_id`
--   - Natural keys / uniqueness: `(organization_id, alias_name)` is unique so
--     the same canonical organization cannot carry the same alias text twice.
--   - Checks: nonblank trimmed `alias_name`; `alias_type` restricted to the
--     allowed alias categories; `start_year` and `end_year` must be
--     nonnegative when present; `notes` must be nonblank when present.
--
-- Relationships
--   - Owns FKs to `organizations(organization_id)` and optionally to
--     `eras(era_id)` through `start_era_id` and `end_era_id`.
--   - Downstream name-resolution, search, and ingestion logic should join this
--     table to `organizations` on `organization_id` to map observed alias
--     strings back to the canonical organization entity.
--
-- Audit & provenance
--   This table records creation time via `created_at` but does not store
--   source-document lineage, adjudication metadata, or extraction provenance.
--   Full provenance for alias assignment should live in higher-level ingestion
--   or event-sourcing tables if required.
--
-- Performance
--   A secondary index on `alias_name` supports alias-to-organization lookup
--   during parsing, normalization, and user-facing search flows.
--
-- Change management
--   Extend alias semantics additively: prefer adding new nullable metadata
--   columns or widening the allowed `alias_type` domain without changing row
--   meaning or reinterpreting existing temporal fields.
-- =============================================================================

CREATE TABLE IF NOT EXISTS organization_aliases (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this organization alias.
    organization_alias_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Owning organization.
    organization_id UUID NOT NULL REFERENCES organizations (organization_id),

    -- Alias text.
    alias_name TEXT NOT NULL,

    -- Alias classification.
    alias_type TEXT NOT NULL DEFAULT 'alternate_name',

    -- Optional temporal start era.
    start_era_id UUID REFERENCES eras (era_id),

    -- Optional temporal start year-in-era.
    start_year INTEGER,

    -- Optional temporal end era.
    end_era_id UUID REFERENCES eras (era_id),

    -- Optional temporal end year-in-era.
    end_year INTEGER,

    -- Optional notes.
    notes TEXT,

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT organization_aliases_uq_org_alias
    UNIQUE (organization_id, alias_name),

    CONSTRAINT organization_aliases_chk_alias_name_nonempty
    CHECK (length(btrim(alias_name)) > 0),

    CONSTRAINT organization_aliases_chk_alias_type
    CHECK (
        alias_type IN (
            'alternate_name',
            'former_name',
            'local_name',
            'translated_name',
            'honorific_name',
            'acronym'
        )
    ),

    CONSTRAINT organization_aliases_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT organization_aliases_chk_notes_nonempty
    CHECK (notes IS NULL OR length(btrim(notes)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_organization_aliases_alias_name
ON organization_aliases (alias_name);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE organization_aliases IS
'One row per alternate or former organization name, optionally time-bounded.';

COMMENT ON COLUMN organization_aliases.organization_alias_id IS
'Primary key for this organization alias row (UUID).';

COMMENT ON COLUMN organization_aliases.organization_id IS
'Owning organization.';

COMMENT ON COLUMN organization_aliases.alias_name IS
'Alias text for the organization.';

COMMENT ON COLUMN organization_aliases.alias_type IS
'Alias category (former_name/acronym/etc.).';

COMMENT ON COLUMN organization_aliases.start_era_id IS
'Optional start era for alias validity.';

COMMENT ON COLUMN organization_aliases.start_year IS
'Optional start year-in-era for alias validity.';

COMMENT ON COLUMN organization_aliases.end_era_id IS
'Optional end era for alias validity.';

COMMENT ON COLUMN organization_aliases.end_year IS
'Optional end year-in-era for alias validity.';

COMMENT ON COLUMN organization_aliases.notes IS
'Optional notes for this alias record.';

COMMENT ON COLUMN organization_aliases.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_organization_aliases_alias_name IS
'Index to accelerate alias-based organization lookup.';
