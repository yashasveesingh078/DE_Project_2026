-- =====================================================================
-- Duolingo Language Learning Database: schema (Phase 2 / CP1)
-- Team T0097
--
-- Run on an empty database:
--     createdb duolingo
--     psql -d duolingo -v ON_ERROR_STOP=1 -f sql/01_schema.sql
--
-- Rules followed (README 2.2):
--   * every table lives in schema "duolingo"
--   * ONLY constraints are created (PK, FK, UNIQUE, NOT NULL, CHECK, DEFAULT).
--     No extra indexes: the only indexes are the ones PostgreSQL builds
--     automatically for PRIMARY KEY and UNIQUE constraints.
--   * table and column names are exactly the CSV file names and headers.
--   * every constraint accepts all rows of seed_data/.
-- =====================================================================

-- Re-runnable: start from a clean schema.
DROP SCHEMA IF EXISTS duolingo CASCADE;
CREATE SCHEMA duolingo;
SET search_path TO duolingo;

-- All timestamps in the export carry +05:30 (the data team is in India).
-- Queries such as R04 (DATE(started_at)), R20 (started_at::date) and
-- R25 (EXTRACT(HOUR ...)) depend on the session time zone, so we pin the
-- database to India time. This is a correctness setting, not a tuning one.
DO $$
BEGIN
    EXECUTE format('ALTER DATABASE %I SET timezone TO %L', current_database(), 'Asia/Kolkata');
END $$;
SET timezone TO 'Asia/Kolkata';


-- ---------------------------------------------------------------------
-- 1. languages : ISO 639-1 language codes
-- ---------------------------------------------------------------------
CREATE TABLE languages (
    language_code  varchar(2)   NOT NULL,
    language_name  varchar(40)  NOT NULL,
    CONSTRAINT languages_pkey            PRIMARY KEY (language_code),
    CONSTRAINT languages_name_key        UNIQUE (language_name),
    CONSTRAINT languages_code_format_chk CHECK (language_code ~ '^[a-z]{2}$'),
    CONSTRAINT languages_name_not_blank  CHECK (btrim(language_name) <> '')
);


-- ---------------------------------------------------------------------
-- 2. courses : "language you speak" -> "language you learn"
-- ---------------------------------------------------------------------
CREATE TABLE courses (
    course_id      smallint     NOT NULL,
    from_lang      varchar(2)   NOT NULL,
    learning_lang  varchar(2)   NOT NULL,
    title          varchar(80)  NOT NULL,
    launched_on    date         NOT NULL,
    CONSTRAINT courses_pkey            PRIMARY KEY (course_id),
    CONSTRAINT courses_pair_key        UNIQUE (from_lang, learning_lang),   -- one course per language pair
    CONSTRAINT courses_title_key       UNIQUE (title),                      -- R18 groups by title
    CONSTRAINT courses_from_lang_fkey     FOREIGN KEY (from_lang)
        REFERENCES languages (language_code) ON DELETE RESTRICT,
    CONSTRAINT courses_learning_lang_fkey FOREIGN KEY (learning_lang)
        REFERENCES languages (language_code) ON DELETE RESTRICT,
    CONSTRAINT courses_id_positive     CHECK (course_id > 0),
    CONSTRAINT courses_diff_lang_chk   CHECK (from_lang <> learning_lang),
    CONSTRAINT courses_launch_chk      CHECK (launched_on >= DATE '2011-01-01') -- Duolingo did not exist before 2011
);


-- ---------------------------------------------------------------------
-- 3. units : sections of a course, each with a CEFR level
-- ---------------------------------------------------------------------
CREATE TABLE units (
    unit_id     integer      NOT NULL,
    course_id   smallint     NOT NULL,
    unit_no     smallint     NOT NULL,
    title       varchar(80)  NOT NULL,
    cefr_level  varchar(2)   NOT NULL,
    CONSTRAINT units_pkey               PRIMARY KEY (unit_id),
    CONSTRAINT units_course_unit_no_key UNIQUE (course_id, unit_no),        -- position inside a course
    CONSTRAINT units_course_id_fkey     FOREIGN KEY (course_id)
        REFERENCES courses (course_id) ON DELETE CASCADE,
    CONSTRAINT units_unit_no_positive   CHECK (unit_no > 0),
    CONSTRAINT units_cefr_level_chk     CHECK (cefr_level IN ('A1','A2','B1','B2','C1','C2'))
);


-- ---------------------------------------------------------------------
-- 4. lessons : lessons inside a unit
-- ---------------------------------------------------------------------
CREATE TABLE lessons (
    lesson_id    integer      NOT NULL,
    unit_id      integer      NOT NULL,
    lesson_no    smallint     NOT NULL,
    lesson_type  varchar(10)  NOT NULL,
    xp_value     smallint     NOT NULL,
    CONSTRAINT lessons_pkey                PRIMARY KEY (lesson_id),
    CONSTRAINT lessons_unit_lesson_no_key  UNIQUE (unit_id, lesson_no),     -- position inside a unit
    CONSTRAINT lessons_unit_id_fkey        FOREIGN KEY (unit_id)
        REFERENCES units (unit_id) ON DELETE CASCADE,
    CONSTRAINT lessons_lesson_no_positive  CHECK (lesson_no > 0),
    CONSTRAINT lessons_type_chk            CHECK (lesson_type IN ('LEARN','PRACTICE','STORY','LEGENDARY')),
    CONSTRAINT lessons_xp_value_chk        CHECK (xp_value > 0 AND xp_value <= 100 AND xp_value % 5 = 0)
);


-- ---------------------------------------------------------------------
-- 5. achievements : badge catalogue
-- ---------------------------------------------------------------------
CREATE TABLE achievements (
    achievement_id  smallint     NOT NULL,
    code            varchar(30)  NOT NULL,
    name            varchar(60)  NOT NULL,
    CONSTRAINT achievements_pkey        PRIMARY KEY (achievement_id),
    CONSTRAINT achievements_code_key    UNIQUE (code),                      -- W05 looks a badge up by code
    CONSTRAINT achievements_name_key    UNIQUE (name),
    CONSTRAINT achievements_code_format CHECK (code ~ '^[A-Z][A-Z0-9_]*$')
);


-- ---------------------------------------------------------------------
-- 6. learners : Duolingo users (self-reference = referrals)
-- ---------------------------------------------------------------------
CREATE TABLE learners (
    learner_id     integer       NOT NULL,
    username       varchar(30)   NOT NULL,
    email          varchar(254)  NOT NULL,
    country_code   varchar(2)    NOT NULL,
    daily_goal_xp  smallint      NOT NULL DEFAULT 10,
    subscription   varchar(5)    NOT NULL DEFAULT 'FREE',
    referred_by    integer,                 -- NULL = signed up without a referral (most learners)
    joined_at      timestamptz   NOT NULL DEFAULT now(),
    CONSTRAINT learners_pkey              PRIMARY KEY (learner_id),
    CONSTRAINT learners_username_key      UNIQUE (username),                -- sign-in handle (R11)
    CONSTRAINT learners_email_key         UNIQUE (email),
    CONSTRAINT learners_referred_by_fkey  FOREIGN KEY (referred_by)
        REFERENCES learners (learner_id) ON DELETE SET NULL,
    CONSTRAINT learners_username_format   CHECK (username ~ '^[A-Za-z][A-Za-z0-9_]{2,29}$'),
    CONSTRAINT learners_email_format      CHECK (email ~ '^[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}$'), -- also forces lower case
    CONSTRAINT learners_country_format    CHECK (country_code ~ '^[A-Z]{2}$'),
    CONSTRAINT learners_daily_goal_chk    CHECK (daily_goal_xp IN (10, 20, 30, 50)), -- Casual/Regular/Serious/Intense
    CONSTRAINT learners_subscription_chk  CHECK (subscription IN ('FREE','SUPER','MAX')),
    CONSTRAINT learners_no_self_referral  CHECK (referred_by IS NULL OR referred_by <> learner_id)
);


-- ---------------------------------------------------------------------
-- 7. enrollments : learner <-> course (M:N)
-- ---------------------------------------------------------------------
CREATE TABLE enrollments (
    learner_id   integer      NOT NULL,
    course_id    smallint     NOT NULL,
    enrolled_at  timestamptz  NOT NULL DEFAULT now(),
    total_xp     integer      NOT NULL DEFAULT 0,  -- derived (sum of xp_earned in this course), kept for the home screen
    is_active    boolean      NOT NULL DEFAULT true,
    CONSTRAINT enrollments_pkey             PRIMARY KEY (learner_id, course_id),
    CONSTRAINT enrollments_learner_id_fkey  FOREIGN KEY (learner_id)
        REFERENCES learners (learner_id) ON DELETE CASCADE,
    CONSTRAINT enrollments_course_id_fkey   FOREIGN KEY (course_id)
        REFERENCES courses (course_id) ON DELETE RESTRICT,
    CONSTRAINT enrollments_total_xp_chk     CHECK (total_xp >= 0)
);


-- ---------------------------------------------------------------------
-- 8. lesson_attempts : every start of a lesson (finished or quit)
-- ---------------------------------------------------------------------
CREATE TABLE lesson_attempts (
    attempt_id    bigint       NOT NULL,
    learner_id    integer      NOT NULL,
    lesson_id     integer      NOT NULL,
    started_at    timestamptz  NOT NULL,
    completed_at  timestamptz,              -- NULL = lesson in progress or abandoned (quit)
    mistakes      smallint     NOT NULL DEFAULT 0,
    hearts_lost   smallint     NOT NULL DEFAULT 0,
    xp_earned     smallint     NOT NULL DEFAULT 0,
    is_perfect    boolean      NOT NULL DEFAULT false, -- derived from mistakes = 0 on a completed attempt
    device        varchar(7)   NOT NULL,
    CONSTRAINT lesson_attempts_pkey              PRIMARY KEY (attempt_id),
    CONSTRAINT lesson_attempts_learner_id_fkey   FOREIGN KEY (learner_id)
        REFERENCES learners (learner_id) ON DELETE CASCADE,
    CONSTRAINT lesson_attempts_lesson_id_fkey    FOREIGN KEY (lesson_id)
        REFERENCES lessons (lesson_id) ON DELETE RESTRICT,
    CONSTRAINT lesson_attempts_device_chk        CHECK (device IN ('ANDROID','IOS','WEB')),
    CONSTRAINT lesson_attempts_mistakes_chk      CHECK (mistakes >= 0),
    CONSTRAINT lesson_attempts_hearts_range      CHECK (hearts_lost BETWEEN 0 AND 5),   -- a learner has at most 5 hearts
    CONSTRAINT lesson_attempts_hearts_le_mistakes CHECK (hearts_lost <= mistakes),      -- a heart is lost only on a mistake
    CONSTRAINT lesson_attempts_xp_chk            CHECK (xp_earned >= 0),
    CONSTRAINT lesson_attempts_time_order        CHECK (completed_at IS NULL OR completed_at > started_at),
    CONSTRAINT lesson_attempts_quit_no_xp        CHECK (completed_at IS NOT NULL OR xp_earned = 0),   -- a quit attempt earns no XP
    CONSTRAINT lesson_attempts_done_has_xp       CHECK (completed_at IS NULL OR xp_earned > 0),       -- finishing always earns XP
    CONSTRAINT lesson_attempts_perfect_chk       CHECK (NOT is_perfect OR (mistakes = 0 AND completed_at IS NOT NULL))
);


-- ---------------------------------------------------------------------
-- 9. daily_activity : one row per learner per active day
-- ---------------------------------------------------------------------
CREATE TABLE daily_activity (
    learner_id          integer   NOT NULL,
    activity_date       date      NOT NULL,
    xp                  integer   NOT NULL DEFAULT 0,      -- derived (sum of that day's xp_earned)
    lessons_completed   smallint  NOT NULL DEFAULT 0,      -- derived (count of that day's completed attempts)
    used_streak_freeze  boolean   NOT NULL DEFAULT false,  -- W03 does not supply it -> default needed
    CONSTRAINT daily_activity_pkey             PRIMARY KEY (learner_id, activity_date), -- W03 ON CONFLICT target
    CONSTRAINT daily_activity_learner_id_fkey  FOREIGN KEY (learner_id)
        REFERENCES learners (learner_id) ON DELETE CASCADE,
    CONSTRAINT daily_activity_xp_chk           CHECK (xp >= 0),
    CONSTRAINT daily_activity_lessons_chk      CHECK (lessons_completed >= 0),
    CONSTRAINT daily_activity_xp_needs_lesson  CHECK (xp = 0 OR lessons_completed > 0),
    CONSTRAINT daily_activity_freeze_chk       CHECK (NOT used_streak_freeze OR (xp = 0 AND lessons_completed = 0)) -- a freeze day has 0 XP
);


-- ---------------------------------------------------------------------
-- 10. league_memberships : weekly league placement of a learner
-- ---------------------------------------------------------------------
CREATE TABLE league_memberships (
    learner_id  integer      NOT NULL,
    week_start  date         NOT NULL,
    tier        varchar(8)   NOT NULL,
    cohort_id   integer      NOT NULL,
    weekly_xp   integer      NOT NULL DEFAULT 0,   -- derived (sum of daily_activity.xp for the week)
    final_rank  smallint,                          -- NULL until the week is closed (W04)
    result      varchar(8),                        -- NULL until the week is closed (W04)
    CONSTRAINT league_memberships_pkey             PRIMARY KEY (learner_id, week_start), -- one league per learner per week
    CONSTRAINT league_memberships_learner_id_fkey  FOREIGN KEY (learner_id)
        REFERENCES learners (learner_id) ON DELETE CASCADE,
    CONSTRAINT league_memberships_tier_chk         CHECK (tier IN ('BRONZE','SILVER','GOLD','SAPPHIRE','RUBY',
                                                                  'EMERALD','AMETHYST','PEARL','OBSIDIAN','DIAMOND')),
    CONSTRAINT league_memberships_result_chk       CHECK (result IN ('PROMOTED','STAYED','DEMOTED')),
    CONSTRAINT league_memberships_monday_chk       CHECK (EXTRACT(ISODOW FROM week_start) = 1), -- weeks start on Monday
    CONSTRAINT league_memberships_cohort_chk       CHECK (cohort_id > 0),
    CONSTRAINT league_memberships_weekly_xp_chk    CHECK (weekly_xp >= 0),
    CONSTRAINT league_memberships_rank_range       CHECK (final_rank BETWEEN 1 AND 30),         -- a league holds about 30
    CONSTRAINT league_memberships_rank_result_pair CHECK ((final_rank IS NULL) = (result IS NULL)),
    CONSTRAINT league_memberships_result_rule      CHECK (result IS NULL
                                                          OR (result = 'PROMOTED' AND final_rank <= 7)
                                                          OR (result = 'DEMOTED'  AND final_rank >= 26)
                                                          OR (result = 'STAYED'   AND final_rank BETWEEN 8 AND 25))
);


-- ---------------------------------------------------------------------
-- 11. learner_achievements : badges earned (M:N learners <-> achievements)
-- ---------------------------------------------------------------------
CREATE TABLE learner_achievements (
    learner_id      integer      NOT NULL,
    achievement_id  smallint     NOT NULL,
    earned_at       timestamptz  NOT NULL DEFAULT now(),
    CONSTRAINT learner_achievements_pkey PRIMARY KEY (learner_id, achievement_id), -- a badge is earned once (W05 ON CONFLICT)
    CONSTRAINT learner_achievements_learner_id_fkey FOREIGN KEY (learner_id)
        REFERENCES learners (learner_id) ON DELETE CASCADE,
    CONSTRAINT learner_achievements_achievement_id_fkey FOREIGN KEY (achievement_id)
        REFERENCES achievements (achievement_id) ON DELETE RESTRICT
);


-- ---------------------------------------------------------------------
-- Indexes that exist now (all created automatically by PK / UNIQUE):
--   SELECT tablename, indexname, indexdef FROM pg_indexes
--   WHERE schemaname = 'duolingo' ORDER BY tablename, indexname;
-- ---------------------------------------------------------------------