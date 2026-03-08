-- =============================================================================
-- 0008_event_edges.sql
--
-- Purpose
--   Define the directed relationship table that links canonical events
--   to one another inside the world-state graph. This
--   table stores causal, temporal, dependency, escalation, and
--   composition-style edges so downstream logic can traverse the event
--   graph instead of inferring structure from free text.
--
-- Row semantics
--   One row represents one directed assertion from one event to another
--   under a specific edge semantic, such as `preceded`, `caused_by`, or
--   `part_of`. It is a relationship fact between two event entities, not
--   an event record in its own right.
--
-- Conventions
--   - Event endpoints are always stored as canonical `events.event_id`
--     references rather than duplicated names or timeline labels.
--   - `edge_type` is constrained to a controlled vocabulary so graph
--     traversal and downstream reasoning can rely on stable semantics.
--   - `created_at` is recorded as a UTC `TIMESTAMPTZ` using `NOW()` per
--     repository audit conventions.
--   - Edges are intended to be durable world-state assertions; if the
--     meaning changes, prefer a data migration or replacement row over
--     silently repurposing an existing semantic.
--
-- Keys & constraints
--   - Primary key: (`from_event_id`, `to_event_id`, `edge_type`)
--   - Natural keys / uniqueness: the composite primary key prevents the
--     same directed semantic edge from being recorded twice between the
--     same two events, while still allowing multiple semantic edge types
--     between one pair of events.
--   - Checks: self loops are forbidden; `edge_type` must come from the
--     approved vocabulary; `edge_confidence` must stay in [0, 1]; and
--     `rationale`, when present, must be non-blank after trimming.
--
-- Relationships
--   - This table owns foreign keys to `events` through `from_event_id`,
--     `to_event_id`, and optional `established_by_event_id`.
--   - Other graph-oriented queries should join from `event_edges` to
--     `events` on the endpoint IDs to recover the source event, target
--     event, and optionally the event that established the edge.
--
-- Audit & provenance
--   This table stores only lightweight provenance: creation time plus an
--   optional `established_by_event_id` pointing to the event that gave
--   rise to the edge assertion. It does not store full parser lineage,
--   adjudication traces, or source-document evidence; richer provenance
--   should live in ingestion logs or dedicated source-link tables.
--
-- Performance
--   The composite primary key supports forward edge lookups from a known
--   source event. Secondary indexes on `to_event_id` and `edge_type`
--   accelerate reverse traversal, inbound-neighbor queries, and filters
--   by relationship semantic.
--
-- Change management
--   Extend this schema additively where possible so downstream graph
--   queries remain stable. New edge semantics should be introduced by a
--   coordinated migration that updates the `edge_type` check and any
--   downstream logic that interprets relationship direction or meaning.
-- =============================================================================

CREATE TABLE IF NOT EXISTS event_edges (

    -- =========
    -- Endpoints
    -- =========

    -- Source event in this directed edge.
    from_event_id UUID NOT NULL REFERENCES events (event_id),

    -- Target event in this directed edge.
    to_event_id UUID NOT NULL REFERENCES events (event_id),

    -- Edge semantic.
    edge_type TEXT NOT NULL,

    -- Optional rationale/notes for this relation.
    rationale TEXT,

    -- Confidence score in [0.0, 1.0].
    edge_confidence NUMERIC(4, 3) NOT NULL DEFAULT 0.500,

    -- Optional event that established this edge assertion.
    established_by_event_id UUID REFERENCES events (event_id),

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT event_edges_pk PRIMARY KEY (
        from_event_id, to_event_id, edge_type
    ),

    CONSTRAINT event_edges_chk_no_self_loop
    CHECK (from_event_id <> to_event_id),

    CONSTRAINT event_edges_chk_edge_type
    CHECK (
        edge_type IN (
            'caused_by',
            'enabled',
            'preceded',
            'triggered',
            'retaliated_for',
            'culminated_in',
            'part_of',
            'followed_by',
            'founded_after',
            'escalated_into',
            'superseded_by'
        )
    ),

    CONSTRAINT event_edges_chk_edge_confidence_range
    CHECK (edge_confidence >= 0 AND edge_confidence <= 1),

    CONSTRAINT event_edges_chk_rationale_nonempty
    CHECK (rationale IS NULL OR length(btrim(rationale)) > 0)
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_event_edges_to_event_id
ON event_edges (to_event_id);

CREATE INDEX IF NOT EXISTS idx_event_edges_edge_type
ON event_edges (edge_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE event_edges IS
'Directed causal/temporal/dependency edges between events.';

COMMENT ON COLUMN event_edges.from_event_id IS
'Source event in this directed edge.';

COMMENT ON COLUMN event_edges.to_event_id IS
'Target event in this directed edge.';

COMMENT ON COLUMN event_edges.edge_type IS
'Edge semantic (caused_by/preceded/part_of/etc.).';

COMMENT ON COLUMN event_edges.rationale IS
'Optional rationale or annotation for the edge assertion.';

COMMENT ON COLUMN event_edges.edge_confidence IS
'Confidence score in [0.0, 1.0] for this edge assertion.';

COMMENT ON COLUMN event_edges.established_by_event_id IS
'Optional event that established this edge record.';

COMMENT ON COLUMN event_edges.created_at IS
'UTC timestamp recording row creation.';

COMMENT ON INDEX idx_event_edges_to_event_id IS
'Index to accelerate reverse traversal of event edges.';

COMMENT ON INDEX idx_event_edges_edge_type IS
'Index to accelerate filtering by event edge semantic.';
