-- =============================================================================
-- 0007_events.sql
--
-- Purpose
--   Define the canonical event table for Project Anabasis world-state
--   memory. This table stores the atomic historical or narrative units
--   that drive timeline reconstruction, causal linking, campaign arc
--   grouping, and downstream joins to participants, locations, and other
--   event-adjacent facts.
--
-- Row semantics
--   One row represents one event assertion in the campaign world: a
--   battle, founding, coronation, betrayal, discovery, or similar
--   episode. It is an event-level entity, not a character, location, or
--   derived relationship edge.
--
-- Conventions
--   - `event_name` and `event_summary` must be non-blank after trimming;
--     optional time labels must also be meaningful when present.
--   - Temporal fields use era plus year-in-era plus optional loose text
--     labels so the schema can represent both precise and fuzzy dates.
--   - `created_at` and `updated_at` are stored as UTC `TIMESTAMPTZ`
--     values using `NOW()` per repository audit conventions.
--   - This table is intended to hold durable canonical event records;
--     downstream tables should extend events rather than duplicating core
--     event identity and timing fields.
--
-- Keys & constraints
--   - Primary key: `event_id`
--   - Natural keys / uniqueness: none enforced, because distinct events
--     may legitimately share names, years, types, or summaries.
--   - Checks: event names and summaries must be non-empty; `event_type`
--     and `event_status` must come from controlled vocabularies;
--     `source_confidence` must stay in [0, 1]; years must be
--     non-negative; end timing cannot exist without some start timing;
--     and `parent_event_id` cannot self-reference the same row.
--
-- Relationships
--   - This table owns nullable foreign keys to `eras` via `start_era_id`
--     and `end_era_id`, plus a self-referential foreign key via
--     `parent_event_id` for campaign arcs, parent incidents, or grouped
--     narrative structures.
--   - Downstream tables should join to `events.event_id` when attaching
--     characters, factions, items, spells, locations, or causal edges to
--     a specific event record.
--
-- Audit & provenance
--   This table stores lightweight audit metadata and an in-row
--   confidence score, but it does not capture full source-document
--   lineage, parser outputs, or adjudication history. Richer provenance
--   should live in ingestion logs, source-link tables, or higher-level
--   ETL artifacts.
--
-- Performance
--   Secondary indexes support common filtering and traversal paths:
--   `event_type` for category queries, `event_status` for lifecycle
--   slices, `(start_era_id, start_year)` for chronological retrieval,
--   and `parent_event_id` for arc or hierarchy expansion.
--
-- Change management
--   Prefer additive schema evolution so downstream event-linked tables do
--   not break. New event categories or statuses should be introduced by
--   updating the relevant checks in a coordinated migration, and any
--   change to temporal semantics should preserve backward compatibility
--   for existing era/year-based queries.
-- =============================================================================

CREATE TABLE IF NOT EXISTS events (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for the event.
    event_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Canonical event label.
    event_name TEXT NOT NULL,

    -- Short event summary for fast scanning.
    event_summary TEXT NOT NULL,

    -- Optional long-form notes/details.
    event_details TEXT,

    -- High-level event category.
    event_type TEXT NOT NULL DEFAULT 'other',

    -- Lifecycle/state of this event record.
    event_status TEXT NOT NULL DEFAULT 'recorded',

    -- Whether this event is treated as legendary tradition.
    is_legendary BOOLEAN NOT NULL DEFAULT FALSE,

    -- Whether historians dispute the event.
    is_disputed BOOLEAN NOT NULL DEFAULT FALSE,

    -- Whether event details/timing are uncertain.
    is_uncertain BOOLEAN NOT NULL DEFAULT FALSE,

    -- Confidence score in [0.0, 1.0].
    source_confidence NUMERIC(4, 3) NOT NULL DEFAULT 0.500,

    -- ==============
    -- Temporal fields
    -- ==============

    -- Era in which the event begins.
    start_era_id UUID REFERENCES eras (era_id),

    -- Year-in-era in which the event begins.
    start_year INTEGER,

    -- Optional loose temporal phrase (e.g., "early", "winter", "unknown").
    start_time_label TEXT,

    -- Whether start timing is approximate.
    start_is_approximate BOOLEAN NOT NULL DEFAULT FALSE,

    -- Era in which the event ends (for interval events).
    end_era_id UUID REFERENCES eras (era_id),

    -- Year-in-era in which the event ends.
    end_year INTEGER,

    -- Optional loose end-time phrase.
    end_time_label TEXT,

    -- Whether end timing is approximate.
    end_is_approximate BOOLEAN NOT NULL DEFAULT FALSE,

    -- Parent event/campaign/arc pointer.
    parent_event_id UUID REFERENCES events (event_id),

    -- ==============
    -- Audit metadata
    -- ==============

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- UTC timestamp recording row update.
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT events_chk_event_name_nonempty
    CHECK (length(btrim(event_name)) > 0),

    CONSTRAINT events_chk_event_summary_nonempty
    CHECK (length(btrim(event_summary)) > 0),

    CONSTRAINT events_chk_event_type
    CHECK (
        event_type IN (
            'battle',
            'migration',
            'founding',
            'coronation',
            'betrayal',
            'treaty_signing',
            'assassination',
            'conquest',
            'plague_outbreak',
            'trade_mission',
            'city_surrender',
            'succession_dispute',
            'religious_schism',
            'discovery',
            'disappearance',
            'death',
            'birth',
            'appointment',
            'realm_collapse',
            'settlement',
            'other'
        )
    ),

    CONSTRAINT events_chk_event_status
    CHECK (
        event_status IN (
            'recorded',
            'ongoing',
            'completed',
            'abandoned',
            'rumored',
            'legendary'
        )
    ),

    CONSTRAINT events_chk_source_confidence_range
    CHECK (source_confidence >= 0 AND source_confidence <= 1),

    CONSTRAINT events_chk_year_nonnegative
    CHECK (
        (start_year IS NULL OR start_year >= 0)
        AND (end_year IS NULL OR end_year >= 0)
    ),

    CONSTRAINT events_chk_time_labels_nonempty
    CHECK (
        (start_time_label IS NULL OR length(btrim(start_time_label)) > 0)
        AND (end_time_label IS NULL OR length(btrim(end_time_label)) > 0)
    ),

    CONSTRAINT events_chk_end_requires_some_start
    CHECK (
        (
            end_era_id IS NULL
            AND end_year IS NULL
            AND end_time_label IS NULL
        )
        OR (
            start_era_id IS NOT NULL
            OR start_year IS NOT NULL
            OR start_time_label IS NOT NULL
        )
    ),

    CONSTRAINT events_chk_parent_not_self
    CHECK (parent_event_id IS NULL OR parent_event_id <> event_id)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_events_event_type
ON events (event_type);

CREATE INDEX IF NOT EXISTS idx_events_event_status
ON events (event_status);

CREATE INDEX IF NOT EXISTS idx_events_start_era_year
ON events (start_era_id, start_year);

CREATE INDEX IF NOT EXISTS idx_events_parent_event_id
ON events (parent_event_id);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE events IS
'One row per atomic world-state event with typed category,
uncertainty flags, temporal bounds, and optional campaign parent.';

COMMENT ON COLUMN events.event_id IS
'Primary key for the event row (UUID).';

COMMENT ON COLUMN events.event_name IS
'Canonical event label.';

COMMENT ON COLUMN events.event_summary IS
'Short summary for quick scanning and indexing.';

COMMENT ON COLUMN events.event_details IS
'Optional long-form details or notes for the event.';

COMMENT ON COLUMN events.event_type IS
'Event category (battle/founding/treaty_signing/etc.).';

COMMENT ON COLUMN events.event_status IS
'Lifecycle/state of this event record (recorded/ongoing/etc.).';

COMMENT ON COLUMN events.is_legendary IS
'Whether this event is treated as legendary tradition.';

COMMENT ON COLUMN events.is_disputed IS
'Whether historians dispute this event.';

COMMENT ON COLUMN events.is_uncertain IS
'Whether event details or timing are uncertain.';

COMMENT ON COLUMN events.source_confidence IS
'Confidence score in [0.0, 1.0] for this event assertion.';

COMMENT ON COLUMN events.start_era_id IS
'Foreign key to eras for event start.';

COMMENT ON COLUMN events.start_year IS
'Year-in-era for event start.';

COMMENT ON COLUMN events.start_time_label IS
'Loose start-time phrase when exact timing is unavailable.';

COMMENT ON COLUMN events.start_is_approximate IS
'Whether the event start timing is approximate.';

COMMENT ON COLUMN events.end_era_id IS
'Foreign key to eras for event end (interval events).';

COMMENT ON COLUMN events.end_year IS
'Year-in-era for event end.';

COMMENT ON COLUMN events.end_time_label IS
'Loose end-time phrase when exact timing is unavailable.';

COMMENT ON COLUMN events.end_is_approximate IS
'Whether the event end timing is approximate.';

COMMENT ON COLUMN events.parent_event_id IS
'Optional parent event/campaign/arc pointer.';

COMMENT ON COLUMN events.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON COLUMN events.updated_at IS
'UTC timestamp recording row update.';

COMMENT ON INDEX idx_events_event_type IS
'Index to accelerate filtering by event type.';

COMMENT ON INDEX idx_events_event_status IS
'Index to accelerate filtering by event status.';

COMMENT ON INDEX idx_events_start_era_year IS
'Index to accelerate temporal event range queries by era/year start.';

COMMENT ON INDEX idx_events_parent_event_id IS
'Index to accelerate campaign/arc traversal through parent_event_id.';
