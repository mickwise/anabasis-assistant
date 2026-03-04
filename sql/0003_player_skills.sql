-- =============================================================================
-- 0003_player_skills.sql
--
-- Purpose
--   Store D&D 5e skill modifiers and proficiency flags in Postgres.
--
-- Row semantics
--   One row in player_skills = one complete skill block for a character.
--   This table is designed to be referenced by character_sheet.skills_id.
--
-- Conventions
--   - This table stores the modifiers as written in the skill boxes.
--   - Proficiency is stored as a boolean per skill.
--   - Expertise/double proficiency is not modeled here (add later if needed).
--   - This migration intentionally does not define foreign keys to
--     character_sheet because character_sheet owns only a pointer id.
--
-- Keys & constraints
--   - Primary key: skills_id.
--   - Checks: skill modifiers are constrained to a reasonable bound
--     ([-30, 30]) to catch obvious bad writes.
--
-- Performance
--   - This is typically loaded by primary key; no secondary indexes required.
-- =============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS player_skills (

    -- ===========
    -- Identifiers
    -- ===========

    -- Surrogate primary key for this skill block (UUID).
    skills_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- ======================
    -- Acrobatics (Dexterity)
    -- ======================

    -- Skill modifier.
    acrobatics_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    acrobatics_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =============================
    -- Animal Handling (Wisdom)
    -- =============================

    -- Skill modifier.
    animal_handling_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    animal_handling_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ==================
    -- Arcana (Intelligence)
    -- ==================

    -- Skill modifier.
    arcana_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    arcana_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =====================
    -- Athletics (Strength)
    -- =====================

    -- Skill modifier.
    athletics_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    athletics_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =====================
    -- Deception (Charisma)
    -- =====================

    -- Skill modifier.
    deception_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    deception_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ===================
    -- History (Intelligence)
    -- ===================

    -- Skill modifier.
    history_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    history_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ==================
    -- Insight (Wisdom)
    -- ==================

    -- Skill modifier.
    insight_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    insight_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =======================
    -- Intimidation (Charisma)
    -- =======================

    -- Skill modifier.
    intimidation_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    intimidation_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =========================
    -- Investigation (Intelligence)
    -- =========================

    -- Skill modifier.
    investigation_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    investigation_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ==================
    -- Medicine (Wisdom)
    -- ==================

    -- Skill modifier.
    medicine_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    medicine_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =====================
    -- Nature (Intelligence)
    -- =====================

    -- Skill modifier.
    nature_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    nature_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ====================
    -- Perception (Wisdom)
    -- ====================

    -- Skill modifier.
    perception_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    perception_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =========================
    -- Performance (Charisma)
    -- =========================

    -- Skill modifier.
    performance_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    performance_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =====================
    -- Persuasion (Charisma)
    -- =====================

    -- Skill modifier.
    persuasion_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    persuasion_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ====================
    -- Religion (Intelligence)
    -- ====================

    -- Skill modifier.
    religion_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    religion_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ==========================
    -- Sleight of Hand (Dexterity)
    -- ==========================

    -- Skill modifier.
    sleight_of_hand_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    sleight_of_hand_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- =================
    -- Stealth (Dexterity)
    -- =================

    -- Skill modifier.
    stealth_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    stealth_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ==================
    -- Survival (Wisdom)
    -- ==================

    -- Skill modifier.
    survival_modifier SMALLINT NOT NULL DEFAULT 0,

    -- Proficiency flag.
    survival_proficient BOOLEAN NOT NULL DEFAULT FALSE,

    -- ==============
    -- Constraints
    -- ==============

    CONSTRAINT player_skills_chk_modifiers_reasonable
    CHECK (
        acrobatics_modifier BETWEEN -30 AND 30
        AND animal_handling_modifier BETWEEN -30 AND 30
        AND arcana_modifier BETWEEN -30 AND 30
        AND athletics_modifier BETWEEN -30 AND 30
        AND deception_modifier BETWEEN -30 AND 30
        AND history_modifier BETWEEN -30 AND 30
        AND insight_modifier BETWEEN -30 AND 30
        AND intimidation_modifier BETWEEN -30 AND 30
        AND investigation_modifier BETWEEN -30 AND 30
        AND medicine_modifier BETWEEN -30 AND 30
        AND nature_modifier BETWEEN -30 AND 30
        AND perception_modifier BETWEEN -30 AND 30
        AND performance_modifier BETWEEN -30 AND 30
        AND persuasion_modifier BETWEEN -30 AND 30
        AND religion_modifier BETWEEN -30 AND 30
        AND sleight_of_hand_modifier BETWEEN -30 AND 30
        AND stealth_modifier BETWEEN -30 AND 30
        AND survival_modifier BETWEEN -30 AND 30
    )
);

-- ==================
-- Comments (catalog)
-- ==================

COMMENT ON TABLE player_skills IS
'One row per character skill block: the 18 D&D 5e skill modifiers plus
per-skill proficiency flags.Designed to be referenced by character_sheet.skills_id.';

COMMENT ON COLUMN player_skills.skills_id IS
'Primary key for this skill block (UUID); character_sheet.skills_id can '
'point here.';

COMMENT ON COLUMN player_skills.acrobatics_modifier IS
'Acrobatics modifier (Dexterity) as written in the skill box.';

COMMENT ON COLUMN player_skills.acrobatics_proficient IS
'Acrobatics proficiency flag.';

COMMENT ON COLUMN player_skills.animal_handling_modifier IS
'Animal Handling modifier (Wisdom) as written in the skill box.';

COMMENT ON COLUMN player_skills.animal_handling_proficient IS
'Animal Handling proficiency flag.';

COMMENT ON COLUMN player_skills.arcana_modifier IS
'Arcana modifier (Intelligence) as written in the skill box.';

COMMENT ON COLUMN player_skills.arcana_proficient IS
'Arcana proficiency flag.';

COMMENT ON COLUMN player_skills.athletics_modifier IS
'Athletics modifier (Strength) as written in the skill box.';

COMMENT ON COLUMN player_skills.athletics_proficient IS
'Athletics proficiency flag.';

COMMENT ON COLUMN player_skills.deception_modifier IS
'Deception modifier (Charisma) as written in the skill box.';

COMMENT ON COLUMN player_skills.deception_proficient IS
'Deception proficiency flag.';

COMMENT ON COLUMN player_skills.history_modifier IS
'History modifier (Intelligence) as written in the skill box.';

COMMENT ON COLUMN player_skills.history_proficient IS
'History proficiency flag.';

COMMENT ON COLUMN player_skills.insight_modifier IS
'Insight modifier (Wisdom) as written in the skill box.';

COMMENT ON COLUMN player_skills.insight_proficient IS
'Insight proficiency flag.';

COMMENT ON COLUMN player_skills.intimidation_modifier IS
'Intimidation modifier (Charisma) as written in the skill box.';

COMMENT ON COLUMN player_skills.intimidation_proficient IS
'Intimidation proficiency flag.';

COMMENT ON COLUMN player_skills.investigation_modifier IS
'Investigation modifier (Intelligence) as written in the skill box.';

COMMENT ON COLUMN player_skills.investigation_proficient IS
'Investigation proficiency flag.';

COMMENT ON COLUMN player_skills.medicine_modifier IS
'Education/Medicine modifier (Wisdom) as written in the skill box.';

COMMENT ON COLUMN player_skills.medicine_proficient IS
'Medicine proficiency flag.';

COMMENT ON COLUMN player_skills.nature_modifier IS
'Nature modifier (Intelligence) as written in the skill box.';

COMMENT ON COLUMN player_skills.nature_proficient IS
'Nature proficiency flag.';

COMMENT ON COLUMN player_skills.perception_modifier IS
'Perception modifier (Wisdom) as written in the skill box.';

COMMENT ON COLUMN player_skills.perception_proficient IS
'Perception proficiency flag.';

COMMENT ON COLUMN player_skills.performance_modifier IS
'Performance modifier (Charisma) as written in the skill box.';

COMMENT ON COLUMN player_skills.performance_proficient IS
'Performance proficiency flag.';

COMMENT ON COLUMN player_skills.persuasion_modifier IS
'Persuasion modifier (Charisma) as written in the skill box.';

COMMENT ON COLUMN player_skills.persuasion_proficient IS
'Persuasion proficiency flag.';

COMMENT ON COLUMN player_skills.religion_modifier IS
'Religion modifier (Intelligence) as written in the skill box.';

COMMENT ON COLUMN player_skills.religion_proficient IS
'Religion proficiency flag.';

COMMENT ON COLUMN player_skills.sleight_of_hand_modifier IS
'Sleight of Hand modifier (Dexterity) as written in the skill box.';

COMMENT ON COLUMN player_skills.sleight_of_hand_proficient IS
'Sleight of Hand proficiency flag.';

COMMENT ON COLUMN player_skills.stealth_modifier IS
' Stealth modifier (Dexterity) as written in the skill box.';

COMMENT ON COLUMN player_skills.stealth_proficient IS
'Stealth proficiency flag.';

COMMENT ON COLUMN player_skills.survival_modifier IS
'Survival modifier (Wisdom) as written in the skill box.';

COMMENT ON COLUMN player_skills.survival_proficient IS
'Survival proficiency flag.';
