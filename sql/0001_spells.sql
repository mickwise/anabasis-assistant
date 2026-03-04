-- =============================================================================
-- 0001_spells.sql
--
-- Purpose
--   Store D&D 5e spell definitions in Postgres.
--
-- Row semantics
--   One row in spells = one spell definition (static rules text + key
--   mechanical fields such as level, timing, range, duration, components,
--   damage, and save).
--
-- Conventions
--   - Store raw, human-readable text for timing/range/duration because official
--     spell formatting is not fully normalized
--     (e.g., "1 action", "bonus action", "Self (15-foot cone)").
--   - Use structured flags for components (V/S/M) and ritual.
--   - damage is stored as a single text field (e.g., "3d8", "1d6+MOD").
--     Upcasting effects belong in the rules text (details).
--
-- Keys & constraints
--   - Primary key: spell_id.
--   - Uniqueness: spell_name is unique.
--   - Checks:
--       * level ∈ [0, 9]
--       * non-empty strings for required text fields
--       * if save_ability is set, it must be one of STR/DEX/CON/INT/WIS/CHA
--       * if is_elemental is true, damage_type must be one of the elemental set
--         (acid, cold, fire, lightning, poison, thunder)
--       * at least one component flag must be true
--
-- Performance
--   - Index on (level) supports browsing/filtering by spell level.
--   - Index on (damage_type) supports damage-type filtering.
-- =============================================================================

CREATE TABLE IF NOT EXISTS spells (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for the spell.
    -- Uses UUID to support external references and offline creation.
    spell_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Spell name (unique).
    spell_name TEXT NOT NULL,

    -- =================
    -- Core spell fields
    -- =================

    -- Spell level: 0 = cantrip, 1..9 = leveled spell.
    level SMALLINT NOT NULL,

    -- Casting time (e.g., "1 action", "1 bonus action", "1 reaction").
    cast_time TEXT NOT NULL,

    -- Range (e.g., "Self", "Touch", "60 feet", "Self (15-foot cone)").
    range TEXT NOT NULL,

    -- Duration (e.g., "Instantaneous", "1 minute",
    -- "Concentration, up to 1 hour").
    duration TEXT NOT NULL,

    -- =========================
    -- Damage / type / saving throw
    -- =========================

    -- Damage expression as written (e.g., "3d8", "1d6+MOD").
    -- Nullable because not all spells deal damage.
    damage TEXT,

    -- Damage type (e.g., "fire", "cold", "force"). Nullable if no damage.
    damage_type TEXT,

    -- Flag for whether this spell's damage type is one of the elemental set.
    -- (Useful for quick filtering; enforced against damage_type when true.)
    is_elemental BOOLEAN NOT NULL DEFAULT FALSE,

    -- Saving throw ability required by the spell (STR/DEX/CON/INT/WIS/CHA),
    -- or NULL if none / not applicable.
    save_ability TEXT,

    -- ==================
    -- Components / ritual
    -- ==================

    -- Verbal component (V).
    component_verbal BOOLEAN NOT NULL DEFAULT FALSE,

    -- Somatic component (S).
    component_somatic BOOLEAN NOT NULL DEFAULT FALSE,

    -- Material component (M).
    component_material BOOLEAN NOT NULL DEFAULT FALSE,

    -- Material components text (if component_material is true).
    material_components TEXT,

    -- Ritual flag.
    is_ritual BOOLEAN NOT NULL DEFAULT FALSE,

    -- =================
    -- Rules text / notes
    -- =================

    -- Rules text / details.
    details TEXT NOT NULL,

    -- ==============
    -- Audit metadata
    -- ==============

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT spells_uq_spell_name UNIQUE (spell_name),

    CONSTRAINT spells_chk_level
    CHECK (level BETWEEN 0 AND 9),

    CONSTRAINT spells_chk_spell_name_nonempty
    CHECK (length(btrim(spell_name)) > 0),

    CONSTRAINT spells_chk_cast_time_nonempty
    CHECK (length(btrim(cast_time)) > 0),

    CONSTRAINT spells_chk_range_nonempty
    CHECK (length(btrim(range)) > 0),

    CONSTRAINT spells_chk_duration_nonempty
    CHECK (length(btrim(duration)) > 0),

    CONSTRAINT spells_chk_details_nonempty
    CHECK (length(btrim(details)) > 0),

    CONSTRAINT spells_chk_save_ability
    CHECK (
        save_ability IS NULL
        OR save_ability IN ('STR', 'DEX', 'CON', 'INT', 'WIS', 'CHA')
    ),

    CONSTRAINT spells_chk_damage_type_when_present
    CHECK (
        damage_type IS NULL
        OR damage_type IN (
            'acid',
            'bludgeoning',
            'cold',
            'fire',
            'force',
            'lightning',
            'necrotic',
            'piercing',
            'poison',
            'psychic',
            'radiant',
            'slashing',
            'thunder'
        )
    ),

    CONSTRAINT spells_chk_elemental_consistency
    CHECK (
        is_elemental = FALSE
        OR damage_type IN (
            'acid', 'cold', 'fire', 'lightning', 'poison', 'thunder'
        )
    ),

    CONSTRAINT spells_chk_components_at_least_one
    CHECK (
        component_verbal = TRUE
        OR component_somatic = TRUE
        OR component_material = TRUE
    ),

    CONSTRAINT spells_chk_material_components_when_m
    CHECK (
        component_material = FALSE
        OR material_components IS NULL
        OR length(btrim(material_components)) > 0
    )
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_spells_level
ON spells (level);

CREATE INDEX IF NOT EXISTS idx_spells_damage_type
ON spells (damage_type);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE spells IS
'One row per D&D 5e spell definition, storing level/timing/range/duration,
damage + type, save ability, components (V/S/M), ritual flag, and full rules text.';

COMMENT ON COLUMN spells.spell_id IS
'Primary key for the spell definition (UUID).';

COMMENT ON COLUMN spells.spell_name IS
'Unique spell name.';

COMMENT ON COLUMN spells.level IS
'Spell level: 0 = cantrip, 1..9 = leveled spell.';

COMMENT ON COLUMN spells.cast_time IS
'Casting time as written (e.g., "1 action", "1 bonus action", "1 reaction").';

COMMENT ON COLUMN spells.range IS
'Range as written (e.g., "Self", "Touch", "60 feet", "Self (15-foot cone)").';

COMMENT ON COLUMN spells.duration IS
'Duration as written (e.g., "Instantaneous",
"1 minute", "Concentration, up to 1 hour").';

COMMENT ON COLUMN spells.damage IS
'Damage expression as written (e.g., "3d8", "1d6+MOD");
nullable for non-damaging spells.';

COMMENT ON COLUMN spells.damage_type IS
'Damage type (fire/cold/etc.);nullable for non-damaging spells.';

COMMENT ON COLUMN spells.is_elemental IS
'Whether damage_type is one of the elemental set
(acid/cold/fire/lightning/poison/thunder).';

COMMENT ON COLUMN spells.save_ability IS
'Saving throw ability required by the spell
(STR/DEX/CON/INT/WIS/CHA), or NULL if not applicable.';

COMMENT ON COLUMN spells.component_verbal IS
'Verbal component (V).';

COMMENT ON COLUMN spells.component_somatic IS
'Somatic component (S).';

COMMENT ON COLUMN spells.component_material IS
'Material component (M).';

COMMENT ON COLUMN spells.material_components IS
'Material component text (if M is required), stored as player-facing text.';

COMMENT ON COLUMN spells.is_ritual IS
'Ritual flag.';

COMMENT ON COLUMN spells.details IS
'Full rules text / details for the spell.';

COMMENT ON COLUMN spells.created_at IS
'UTC timestamp recording when this spell definition row was created.';

COMMENT ON INDEX idx_spells_level IS
'Index to accelerate filtering and browsing by spell level.';

COMMENT ON INDEX idx_spells_damage_type IS
'Index to accelerate filtering by damage_type.';
