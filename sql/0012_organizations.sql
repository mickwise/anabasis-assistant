-- =============================================================================
-- 0012_organizations.sql
--
-- Purpose
--   Store canonical organizations in the world-state schema. This table exists
--   to model persistent named groups such as kingdoms, guilds, councils,
--   religious orders, dynasties, factions, and other organized entities that
--   can participate in events and world structure.
--
-- Row semantics
--   One row represents one canonical organization entity, not a membership
--   episode, political office, or event occurrence.
--
-- Conventions
--   - `organization_name` is stored as free text but must be nonblank after
--     trimming.
--   - Hierarchy is modeled with an optional self-FK through
--     `parent_organization_id`; parent-child meaning is structural and does not
--     by itself encode temporal succession.
--   - `created_at` and `updated_at` are UTC `TIMESTAMPTZ` audit fields, and the
--     boolean status flags are current-state summaries rather than versioned
--     historical facts.
--
-- Keys & constraints
--   - Primary key: `organization_id`
--   - Natural keys / uniqueness: `organization_name` is unique across canonical
--     organizations.
--   - Checks: nonblank trimmed `organization_name` and `organization_summary`;
--     `organization_type` restricted to the allowed organization categories;
--     `member_count` must be nonnegative when present; no self-parent
--     relationships.
--
-- Relationships
--   - Owns an optional self-FK to `organizations(organization_id)` through
--     `parent_organization_id`, plus optional FKs to `events(event_id)` through
--     `founding_event_id` and `dissolution_event_id`.
--   - Downstream event, membership, alliance, conflict, and political-structure
--     tables should join to this table on `organization_id` to reference the
--     canonical organization entity.
--
-- Audit & provenance
--   This table records row creation and update timestamps but does not store
--   source-document lineage, extraction metadata, or adjudication history.
--   Detailed provenance for organization facts should live in higher-level
--   ingestion or event-sourcing tables when needed.
--
-- Performance
--   Secondary indexes on `organization_type`, `parent_organization_id`, and
--   `is_active` support category filtering,
--   hierarchy traversal, and active-only organization queries.
--
-- Change management
--   Extend this schema additively: prefer new nullable metadata columns or
--   expanded allowed `organization_type` values over changing the meaning of
--   existing flags, hierarchy semantics, or lifecycle event references.
-- =============================================================================

CREATE TABLE IF NOT EXISTS organizations (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for the organization.
    organization_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Canonical organization name.
    organization_name TEXT UNIQUE NOT NULL,

    -- Organization class/category.
    organization_type TEXT NOT NULL DEFAULT 'other',

    -- Optional parent organization pointer.
    parent_organization_id UUID REFERENCES organizations (organization_id),

    -- Short organization summary.
    organization_summary TEXT NOT NULL,

    -- Optional internal-structure notes.
    structure_notes TEXT,

    -- Optional ideology/belief notes.
    ideology_notes TEXT,

    -- Optional notes describing active regions.
    active_region_notes TEXT,

    -- Optional current member estimate.
    member_count INTEGER,

    -- Event where organization was founded.
    founding_event_id UUID REFERENCES events (event_id),

    -- Event where organization dissolved/collapsed.
    dissolution_event_id UUID REFERENCES events (event_id),

    -- Whether this organization is a polity/state.
    is_polity BOOLEAN NOT NULL DEFAULT FALSE,

    -- Whether this organization is primarily legendary.
    is_legendary BOOLEAN NOT NULL DEFAULT FALSE,

    -- Whether this organization is disputed.
    is_disputed BOOLEAN NOT NULL DEFAULT FALSE,

    -- Whether this organization is currently active.
    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- UTC timestamp recording row update.
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT organizations_chk_organization_name_nonempty
    CHECK (length(btrim(organization_name)) > 0),

    CONSTRAINT organizations_chk_organization_summary_nonempty
    CHECK (length(btrim(organization_summary)) > 0),

    CONSTRAINT organizations_chk_organization_type
    CHECK (
        organization_type IN (
            'kingdom',
            'empire',
            'city_state',
            'tribe',
            'clan',
            'dynasty',
            'council',
            'merchant_company',
            'mercenary_company',
            'religious_order',
            'cult',
            'military_order',
            'guild',
            'college',
            'monastery_order',
            'church',
            'state',
            'faction',
            'other'
        )
    ),

    CONSTRAINT organizations_chk_member_count_nonnegative
    CHECK (member_count IS NULL OR member_count >= 0),

    CONSTRAINT organizations_chk_parent_not_self
    CHECK (
        parent_organization_id IS NULL
        OR parent_organization_id <> organization_id
    )
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_organizations_organization_type
ON organizations (organization_type);

CREATE INDEX IF NOT EXISTS idx_organizations_parent_organization_id
ON organizations (parent_organization_id);

CREATE INDEX IF NOT EXISTS idx_organizations_is_active
ON organizations (is_active);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE organizations IS
'One row per organized group, including polities/states,
orders, companies, councils, and factions.';

COMMENT ON COLUMN organizations.organization_id IS
'Primary key for the organization row (UUID).';

COMMENT ON COLUMN organizations.organization_name IS
'Canonical organization name.';

COMMENT ON COLUMN organizations.organization_type IS
'Organization class/category.';

COMMENT ON COLUMN organizations.parent_organization_id IS
'Optional parent organization pointer.';

COMMENT ON COLUMN organizations.organization_summary IS
'Short organization summary.';

COMMENT ON COLUMN organizations.structure_notes IS
'Optional notes describing internal structure.';

COMMENT ON COLUMN organizations.ideology_notes IS
'Optional notes describing ideology/beliefs.';

COMMENT ON COLUMN organizations.active_region_notes IS
'Optional notes describing regions of operation.';

COMMENT ON COLUMN organizations.member_count IS
'Optional current member estimate.';

COMMENT ON COLUMN organizations.founding_event_id IS
'Event that founded this organization.';

COMMENT ON COLUMN organizations.dissolution_event_id IS
'Event that dissolved/collapsed this organization.';

COMMENT ON COLUMN organizations.is_polity IS
'Whether this organization is a polity/state.';

COMMENT ON COLUMN organizations.is_legendary IS
'Whether this organization is primarily legendary.';

COMMENT ON COLUMN organizations.is_disputed IS
'Whether this organization is disputed.';

COMMENT ON COLUMN organizations.is_active IS
'Whether this organization is currently active.';

COMMENT ON COLUMN organizations.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON COLUMN organizations.updated_at IS
'UTC timestamp recording row update.';

COMMENT ON INDEX idx_organizations_organization_type IS
'Index to accelerate filtering and browsing by organization type.';

COMMENT ON INDEX idx_organizations_parent_organization_id IS
'Index to accelerate hierarchical traversal of organizations.';

COMMENT ON INDEX idx_organizations_is_active IS
'Index to accelerate filtering by active organization status.';
