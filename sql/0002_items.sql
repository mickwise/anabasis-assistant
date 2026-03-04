-- =============================================================================
-- 0002_items.sql
--
-- Purpose
--   Store D&D 5e item definitions in Postgres.
--
-- Row semantics
--   One row in items = one item definition (equipment, weapon, armor, tool,
--   consumable, wondrous item, etc.). Items store player-facing text plus a few
--   structured fields that support filtering and downstream mechanics.
--
-- Conventions
--   - item_value_gp stores market value in gold pieces (GP) as a numeric.
--   - Weapons and armor are indicated via boolean flags.
--   - Weapon damage is stored as a single text field (e.g., "1d8 slashing",
--     "2d6 fire"); this table does not attempt to fully normalize damage.
--   - Armor class bonus is stored as an integer (e.g., +1 for a shield).
--   - Extra mechanical detail belongs in the summary text.
--
-- Keys & constraints
--   - Primary key: item_id.
--   - Uniqueness: item_name is unique.
--   - Checks:
--       * item_name is non-empty
--       * item_value_gp ≥ 0
--       * rarity is one of: common, uncommon, rare, epic, legendary
--       * if is_weapon is true, weapon_damage must be non-empty
--       * if is_armor is true, armor_class_bonus must be non-null
--       * armor_class_bonus must be >= 0 when present
--
-- Performance
--   - Index on (rarity) supports shop/loot filtering.
--   - Index on (is_weapon, is_armor) supports category browsing.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS items (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for the item (UUID).
    item_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- Item name / label (unique).
    item_name TEXT NOT NULL,

    -- ==================
    -- Economics / rarity
    -- ==================

    -- Item value in gold pieces (GP).
    item_value_gp NUMERIC(12, 2) NOT NULL DEFAULT 0,

    -- Rarity tier.
    rarity TEXT NOT NULL DEFAULT 'common',

    -- ==================
    -- Category / mechanics
    -- ==================

    -- Whether the item is a weapon.
    is_weapon BOOLEAN NOT NULL DEFAULT FALSE,

    -- Weapon damage as written (e.g., "1d8 slashing"). Required if is_weapon.
    weapon_damage TEXT,

    -- Whether the item is armor (including shields).
    is_armor BOOLEAN NOT NULL DEFAULT FALSE,

    -- Armor Class bonus (e.g., +2 for a shield, +1 for magical armor).
    -- Required if is_armor.
    armor_class_bonus SMALLINT,

    -- Whether the item is consumable (potions, scrolls, etc.).
    is_consumable BOOLEAN NOT NULL DEFAULT FALSE,

    -- Approximate weight in pounds (nullable for unknown / not applicable).
    weight_lbs NUMERIC(8, 2),

    -- =================
    -- Rules text / notes
    -- =================

    -- Short player-facing description / summary.
    summary TEXT NOT NULL,

    -- Full details / special rules text.
    details TEXT,

    -- ==============
    -- Audit metadata
    -- ==============

    -- UTC timestamp recording row creation.
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    -- ===========
    -- Constraints
    -- ===========

    CONSTRAINT items_uq_item_name UNIQUE (item_name),

    CONSTRAINT items_chk_item_name_nonempty
    CHECK (length(btrim(item_name)) > 0),

    CONSTRAINT items_chk_item_value_nonnegative
    CHECK (item_value_gp >= 0),

    CONSTRAINT items_chk_rarity
    CHECK (rarity IN ('common', 'uncommon', 'rare', 'epic', 'legendary')),

    CONSTRAINT items_chk_summary_nonempty
    CHECK (length(btrim(summary)) > 0),

    CONSTRAINT items_chk_weapon_damage_when_weapon
    CHECK (
        is_weapon = FALSE
        OR (weapon_damage IS NOT NULL AND length(btrim(weapon_damage)) > 0)
    ),

    CONSTRAINT items_chk_armor_bonus_when_armor
    CHECK (
        is_armor = FALSE
        OR armor_class_bonus IS NOT NULL
    ),

    CONSTRAINT items_chk_armor_bonus_nonnegative
    CHECK (
        armor_class_bonus IS NULL
        OR armor_class_bonus >= 0
    ),

    CONSTRAINT items_chk_weight_nonnegative
    CHECK (
        weight_lbs IS NULL
        OR weight_lbs >= 0
    )
);

-- =======
-- Indexes
-- =======

CREATE INDEX IF NOT EXISTS idx_items_rarity
ON items (rarity);

CREATE INDEX IF NOT EXISTS idx_items_weapon_armor
ON items (is_weapon, is_armor);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE items IS
'One row per D&D 5e item definition, including economic value, rarity,
and light structured mechanics for weapons/armor plus player-facing summary text.';

COMMENT ON COLUMN items.item_id IS
'Primary key for the item definition.';

COMMENT ON COLUMN items.item_name IS
'Unique item name / label.';

COMMENT ON COLUMN items.item_value_gp IS
'Item value in gold pieces (GP), stored as numeric with two decimals;
constrained to be nonnegative.';

COMMENT ON COLUMN items.rarity IS
'Rarity tier (common/uncommon/rare/epic/legendary).';

COMMENT ON COLUMN items.is_weapon IS
'Whether the item is a weapon.';

COMMENT ON COLUMN items.weapon_damage IS
'Weapon damage as written (e.g., "1d8 slashing");
required when is_weapon is true.';

COMMENT ON COLUMN items.is_armor IS
'Whether the item is armor (including shields).';

COMMENT ON COLUMN items.armor_class_bonus IS
'Armor Class bonus for the item
(e.g., +2 for a shield); required when is_armor is true.';

COMMENT ON COLUMN items.is_consumable IS
'Whether the item is consumable (potions, scrolls, and similar one-use items).';

COMMENT ON COLUMN items.weight_lbs IS
'Approximate weight in pounds; nullable for unknown or not applicable.';

COMMENT ON COLUMN items.summary IS
'Short player-facing description / summary; required and non-empty.';

COMMENT ON COLUMN items.details IS
'Optional extended rules text / special notes.';

COMMENT ON COLUMN items.created_at IS
'UTC timestamp recording when this item definition row was created.';

COMMENT ON INDEX idx_items_rarity IS
'Index to accelerate filtering by rarity (shop/loot selection).';

COMMENT ON INDEX idx_items_weapon_armor IS
'Index to accelerate browsing by weapon/armor category flags.';
