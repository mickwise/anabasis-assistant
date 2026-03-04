-- =============================================================================
-- 0004_player_spells.sql
--
-- Purpose
--   Store a D&D 5e "spellcasting page" block in Postgres.
--
-- Row semantics
--   One row in player_spells = one complete spellcasting block as laid out on
--   the standard 5e character sheet spellcasting page:
--   - Spellcasting header fields (class, ability, DC, attack bonus, known).
--   - Spell slots totals/expended for levels 1..9.
--   - Per-level spell entries (including cantrips) stored as JSON arrays.
--
-- Conventions
--   - Intended to be referenced by character_sheet.spells_id.
--   - Per-level spells are stored as JSONB arrays; each element includes a
--     spell id (or name) and a prepared flag.
--   - This migration omits FKs because the owning table stores only pointer
--     ids.
--
-- Keys & constraints
--   - Primary key: spells_id (UUID).
--   - Checks:
--       * spellcasting_ability is NULL or one of STR/DEX/CON/INT/WIS/CHA
--       * slot totals/expended are nonnegative; expended <= total
--       * per-level spells JSONB columns are arrays with length-bounded (<= 30)
--
-- Notes
--   - The sheet has a fixed number of visible entries per level. We enforce a
--     conservative upper bound (30) instead of hard-coding the exact count.
-- =============================================================================

CREATE TABLE IF NOT EXISTS player_spells (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this spellcasting block (UUID).
    spells_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- =========================
    -- Spellcasting header fields
    -- =========================

    -- Spellcasting class (as written on the sheet).
    spellcasting_class TEXT,

    -- Spellcasting ability (STR/DEX/CON/INT/WIS/CHA).
    spellcasting_ability TEXT,

    -- Spell save DC.
    spell_save_dc SMALLINT,

    -- Spell attack bonus.
    spell_attack_bonus SMALLINT,

    -- Spells known (or a similar count field).
    spells_known SMALLINT,

    -- ==================
    -- Spell slots (1..9)
    -- ==================

    -- Level 1 slots.
    slots_1_total SMALLINT,
    slots_1_expended SMALLINT,

    -- Level 2 slots.
    slots_2_total SMALLINT,
    slots_2_expended SMALLINT,

    -- Level 3 slots.
    slots_3_total SMALLINT,
    slots_3_expended SMALLINT,

    -- Level 4 slots.
    slots_4_total SMALLINT,
    slots_4_expended SMALLINT,

    -- Level 5 slots.
    slots_5_total SMALLINT,
    slots_5_expended SMALLINT,

    -- Level 6 slots.
    slots_6_total SMALLINT,
    slots_6_expended SMALLINT,

    -- Level 7 slots.
    slots_7_total SMALLINT,
    slots_7_expended SMALLINT,

    -- Level 8 slots.
    slots_8_total SMALLINT,
    slots_8_expended SMALLINT,

    -- Level 9 slots.
    slots_9_total SMALLINT,
    slots_9_expended SMALLINT,

    -- =====================
    -- Spell lists (level 0)
    -- =====================

    -- Cantrip spell entries (name/id + prepared flag).
    spells_0 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 1)
    -- =====================

    -- Level 1 spell entries (name/id + prepared flag).
    spells_1 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 2)
    -- =====================

    -- Level 2 spell entries (name/id + prepared flag).
    spells_2 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 3)
    -- =====================

    -- Level 3 spell entries (name/id + prepared flag).
    spells_3 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 4)
    -- =====================

    -- Level 4 spell entries (name/id + prepared flag).
    spells_4 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 5)
    -- =====================

    -- Level 5 spell entries (name/id + prepared flag).
    spells_5 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 6)
    -- =====================

    -- Level 6 spell entries (name/id + prepared flag).
    spells_6 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 7)
    -- =====================

    -- Level 7 spell entries (name/id + prepared flag).
    spells_7 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 8)
    -- =====================

    -- Level 8 spell entries (name/id + prepared flag).
    spells_8 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- =====================
    -- Spell lists (level 9)
    -- =====================

    -- Level 9 spell entries (name/id + prepared flag).
    spells_9 JSONB NOT NULL DEFAULT '[]'::JSONB,

    -- ==============
    -- Audit metadata
    -- ==============

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT player_spells_chk_spellcasting_ability
    CHECK (
        spellcasting_ability IS NULL
        OR spellcasting_ability IN (
            'STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA'
        )
    ),

    CONSTRAINT player_spells_chk_slots_nonnegative
    CHECK (
        (slots_1_total IS NULL OR slots_1_total >= 0)
        AND (slots_1_expended IS NULL OR slots_1_expended >= 0)
        AND (slots_2_total IS NULL OR slots_2_total >= 0)
        AND (slots_2_expended IS NULL OR slots_2_expended >= 0)
        AND (slots_3_total IS NULL OR slots_3_total >= 0)
        AND (slots_3_expended IS NULL OR slots_3_expended >= 0)
        AND (slots_4_total IS NULL OR slots_4_total >= 0)
        AND (slots_4_expended IS NULL OR slots_4_expended >= 0)
        AND (slots_5_total IS NULL OR slots_5_total >= 0)
        AND (slots_5_expended IS NULL OR slots_5_expended >= 0)
        AND (slots_6_total IS NULL OR slots_6_total >= 0)
        AND (slots_6_expended IS NULL OR slots_6_expended >= 0)
        AND (slots_7_total IS NULL OR slots_7_total >= 0)
        AND (slots_7_expended IS NULL OR slots_7_expended >= 0)
        AND (slots_8_total IS NULL OR slots_8_total >= 0)
        AND (slots_8_expended IS NULL OR slots_8_expended >= 0)
        AND (slots_9_total IS NULL OR slots_9_total >= 0)
        AND (slots_9_expended IS NULL OR slots_9_expended >= 0)
    ),

    CONSTRAINT player_spells_chk_slots_expended_le_total
    CHECK (
        (
            slots_1_total IS NULL OR slots_1_expended IS NULL
            OR slots_1_expended <= slots_1_total
        )
        AND
        (
            slots_2_total IS NULL OR slots_2_expended IS NULL
            OR slots_2_expended <= slots_2_total
        )
        AND (
            slots_3_total IS NULL OR slots_3_expended IS NULL
            OR slots_3_expended <= slots_3_total
        )
        AND (
            slots_4_total IS NULL OR slots_4_expended IS NULL
            OR slots_4_expended <= slots_4_total
        )
        AND (
            slots_5_total IS NULL OR slots_5_expended IS NULL
            OR slots_5_expended <= slots_5_total
        )
        AND (
            slots_6_total IS NULL OR slots_6_expended IS NULL
            OR slots_6_expended <= slots_6_total
        )
        AND (
            slots_7_total IS NULL OR slots_7_expended IS NULL
            OR slots_7_expended <= slots_7_total
        )
        AND (
            slots_8_total IS NULL OR slots_8_expended IS NULL
            OR slots_8_expended <= slots_8_total
        )
        AND (
            slots_9_total IS NULL OR slots_9_expended IS NULL
            OR slots_9_expended <= slots_9_total
        )
    ),

    CONSTRAINT player_spells_chk_spells_json_valid
    CHECK (
        (
            jsonb_typeof(spells_0) = 'array'
            AND jsonb_array_length(spells_0) <= 30
        )
        AND (
            jsonb_typeof(spells_1) = 'array'
            AND jsonb_array_length(spells_1) <= 30
        )
        AND (
            jsonb_typeof(spells_2) = 'array'
            AND jsonb_array_length(spells_2) <= 30
        )
        AND (
            jsonb_typeof(spells_3) = 'array'
            AND jsonb_array_length(spells_3) <= 30
        )
        AND (
            jsonb_typeof(spells_4) = 'array'
            AND jsonb_array_length(spells_4) <= 30
        )
        AND (
            jsonb_typeof(spells_5) = 'array'
            AND jsonb_array_length(spells_5) <= 30
        )
        AND (
            jsonb_typeof(spells_6) = 'array'
            AND jsonb_array_length(spells_6) <= 30
        )
        AND (
            jsonb_typeof(spells_7) = 'array'
            AND jsonb_array_length(spells_7) <= 30
        )
        AND (
            jsonb_typeof(spells_8) = 'array'
            AND jsonb_array_length(spells_8) <= 30
        )
        AND (
            jsonb_typeof(spells_9) = 'array'
            AND jsonb_array_length(spells_9) <= 30
        )
    )
);

COMMENT ON TABLE player_spells IS
'One row per spellcasting-page block: header fields, slot totals/expended,
and per-level spell entries (0..9) as JSON arrays with prepared flags.';

COMMENT ON COLUMN player_spells.spells_id IS
'Primary key for this spellcasting block (UUID).
character_sheet.spells_id can point here.';

COMMENT ON COLUMN player_spells.spellcasting_class IS
'Spellcasting class as written on the sheet.';

COMMENT ON COLUMN player_spells.spellcasting_ability IS
'Spellcasting ability (STR/DEX/CON/INT/WIS/CHA) as written on the sheet.';

COMMENT ON COLUMN player_spells.spell_save_dc IS
'Spell save DC as written on the sheet.';

COMMENT ON COLUMN player_spells.spell_attack_bonus IS
'Spell attack bonus as written on the sheet.';

COMMENT ON COLUMN player_spells.spells_known IS
'Number of spells known (or similar count) as written on the sheet.';

COMMENT ON COLUMN player_spells.slots_1_total IS
'Level 1 slots total.';

COMMENT ON COLUMN player_spells.slots_1_expended IS
'Level 1 slots expended.';

COMMENT ON COLUMN player_spells.slots_2_total IS
'Level 2 slots total.';

COMMENT ON COLUMN player_spells.slots_2_expended IS
'Level 2 slots expended.';

COMMENT ON COLUMN player_spells.slots_3_total IS
'Level 3 slots total.';

COMMENT ON COLUMN player_spells.slots_3_expended IS
'Level 3 slots expended.';

COMMENT ON COLUMN player_spells.slots_4_total IS
'Level 4 slots total.';

COMMENT ON COLUMN player_spells.slots_4_expended IS
'Level 4 slots expended.';

COMMENT ON COLUMN player_spells.slots_5_total IS
'Level 5 slots total.';

COMMENT ON COLUMN player_spells.slots_5_expended IS
'Level 5 slots expended.';

COMMENT ON COLUMN player_spells.slots_6_total IS
'Level 6 slots total.';

COMMENT ON COLUMN player_spells.slots_6_expended IS
'Level 6 slots expended.';

COMMENT ON COLUMN player_spells.slots_7_total IS
'Level 7 slots total.';

COMMENT ON COLUMN player_spells.slots_7_expended IS
'Level 7 slots expended.';

COMMENT ON COLUMN player_spells.slots_8_total IS
'Level 8 slots total.';

COMMENT ON COLUMN player_spells.slots_8_expended IS
'Level 8 slots expended.';

COMMENT ON COLUMN player_spells.slots_9_total IS
'Level 9 slots total.';

COMMENT ON COLUMN player_spells.slots_9_expended IS
'Level 9 slots expended.';

COMMENT ON COLUMN player_spells.spells_0 IS
'Cantrip spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_1 IS
'Level 1 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_2 IS
'Level 2 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_3 IS
'Level 3 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_4 IS
'Level 4 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_5 IS
'Level 5 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_6 IS
'Level 6 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_7 IS
'Level 7 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_8 IS
'Level 8 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.spells_9 IS
'Level 9 spell entries (JSON array); each element should include spell id
and prepared flag.';

COMMENT ON COLUMN player_spells.created_at IS
'UTC timestamp recording when this spellcasting block row was created.';
