-- =====================================================================
-- Duolingo Language Learning Database: load seed data (Phase 2 / CP1)
-- Team T0097
--
-- Run FROM THE PROJECT ROOT (the \copy paths are relative to it),
-- after sql/01_schema.sql:
--     unzip seed_data.zip
--     psql -d duolingo -v ON_ERROR_STOP=1 -f sql/02_load_data.sql
--
-- For the large dataset (Phase 5) replace 'seed_data/' with 'large_data/'.
--
-- CSV mode turns an empty unquoted field into NULL, which is what we want
-- for referred_by, completed_at, final_rank and result.
-- =====================================================================

SET search_path TO duolingo;
SET timezone TO 'Asia/Kolkata';
\timing on

-- Parents before children (FK order):
--   languages -> courses -> units -> lessons
--   achievements
--   learners (self-reference: referred_by is checked at the end of the COPY statement)
--   enrollments, lesson_attempts, daily_activity, league_memberships, learner_achievements
\copy languages            FROM 'seed_data/languages.csv'            WITH (FORMAT csv, HEADER true)
\copy courses              FROM 'seed_data/courses.csv'              WITH (FORMAT csv, HEADER true)
\copy units                FROM 'seed_data/units.csv'                WITH (FORMAT csv, HEADER true)
\copy lessons              FROM 'seed_data/lessons.csv'              WITH (FORMAT csv, HEADER true)
\copy achievements         FROM 'seed_data/achievements.csv'         WITH (FORMAT csv, HEADER true)
\copy learners             FROM 'seed_data/learners.csv'             WITH (FORMAT csv, HEADER true)
\copy enrollments          FROM 'seed_data/enrollments.csv'          WITH (FORMAT csv, HEADER true)
\copy lesson_attempts      FROM 'seed_data/lesson_attempts.csv'      WITH (FORMAT csv, HEADER true)
\copy daily_activity       FROM 'seed_data/daily_activity.csv'       WITH (FORMAT csv, HEADER true)
\copy league_memberships   FROM 'seed_data/league_memberships.csv'   WITH (FORMAT csv, HEADER true)
\copy learner_achievements FROM 'seed_data/learner_achievements.csv' WITH (FORMAT csv, HEADER true)

\timing off
ANALYZE;

-- ---------------------------------------------------------------------
-- 1. Row counts (must match README Phase 2 table)
-- ---------------------------------------------------------------------
SELECT t.table_name, t.expected, t.loaded,
       CASE WHEN t.expected = t.loaded THEN 'OK' ELSE 'MISMATCH' END AS status
FROM (
    SELECT 'languages' AS table_name, 10 AS expected, (SELECT count(*) FROM languages) AS loaded
    UNION ALL SELECT 'courses',              11,     (SELECT count(*) FROM courses)
    UNION ALL SELECT 'units',                220,    (SELECT count(*) FROM units)
    UNION ALL SELECT 'lessons',              1760,   (SELECT count(*) FROM lessons)
    UNION ALL SELECT 'learners',             30000,  (SELECT count(*) FROM learners)
    UNION ALL SELECT 'enrollments',          37500,  (SELECT count(*) FROM enrollments)
    UNION ALL SELECT 'lesson_attempts',      188300, (SELECT count(*) FROM lesson_attempts)
    UNION ALL SELECT 'daily_activity',       189109, (SELECT count(*) FROM daily_activity)
    UNION ALL SELECT 'league_memberships',   28598,  (SELECT count(*) FROM league_memberships)
    UNION ALL SELECT 'achievements',         10,     (SELECT count(*) FROM achievements)
    UNION ALL SELECT 'learner_achievements', 38860,  (SELECT count(*) FROM learner_achievements)
) t;

-- ---------------------------------------------------------------------
-- 2. Integrity checks that constraints cannot express (cross-row / cross-table).
--    "violations" = number of rows breaking the rule; 0 means the rule holds.
-- ---------------------------------------------------------------------

-- IC1: a learner only attempts lessons of courses they are enrolled in
SELECT 'IC1 attempt in a course the learner is not enrolled in' AS check_name, count(*) AS violations
FROM lesson_attempts a
JOIN lessons l ON l.lesson_id = a.lesson_id
JOIN units u   ON u.unit_id = l.unit_id
WHERE NOT EXISTS (SELECT 1 FROM enrollments e
                  WHERE e.learner_id = a.learner_id AND e.course_id = u.course_id);

-- IC2: daily_activity.xp / lessons_completed equal that day's totals from lesson_attempts
WITH att AS (
    SELECT learner_id, started_at::date AS d,
           sum(xp_earned) AS xp, count(*) FILTER (WHERE completed_at IS NOT NULL) AS done
    FROM lesson_attempts GROUP BY 1, 2
)
SELECT 'IC2 daily_activity disagrees with lesson_attempts' AS check_name, count(*) AS violations
FROM daily_activity d
LEFT JOIN att ON att.learner_id = d.learner_id AND att.d = d.activity_date
WHERE coalesce(att.xp, 0) <> d.xp OR coalesce(att.done, 0) <> d.lessons_completed;

-- IC3: every day with an attempt has a daily_activity row
SELECT 'IC3 attempt day without daily_activity row' AS check_name, count(*) AS violations
FROM (SELECT DISTINCT learner_id, started_at::date AS d FROM lesson_attempts) a
WHERE NOT EXISTS (SELECT 1 FROM daily_activity d
                  WHERE d.learner_id = a.learner_id AND d.activity_date = a.d);

-- IC4: enrollments.total_xp equals the XP earned in that course
WITH att AS (
    SELECT a.learner_id, u.course_id, sum(a.xp_earned) AS xp
    FROM lesson_attempts a JOIN lessons l USING (lesson_id) JOIN units u USING (unit_id)
    GROUP BY 1, 2
)
SELECT 'IC4 enrollments.total_xp disagrees with lesson_attempts' AS check_name, count(*) AS violations
FROM enrollments e
LEFT JOIN att ON att.learner_id = e.learner_id AND att.course_id = e.course_id
WHERE coalesce(att.xp, 0) <> e.total_xp;

-- IC5: league_memberships.weekly_xp equals the week's XP in daily_activity
WITH wk AS (
    SELECT learner_id, date_trunc('week', activity_date)::date AS week_start, sum(xp) AS xp
    FROM daily_activity GROUP BY 1, 2
)
SELECT 'IC5 weekly_xp disagrees with daily_activity' AS check_name, count(*) AS violations
FROM league_memberships lm
LEFT JOIN wk ON wk.learner_id = lm.learner_id AND wk.week_start = lm.week_start
WHERE coalesce(wk.xp, 0) <> lm.weekly_xp;

-- IC6: every league cohort (per week) has at most 30 learners
SELECT 'IC6 cohort with more than 30 learners' AS check_name, count(*) AS violations
FROM (SELECT cohort_id, week_start FROM league_memberships
      GROUP BY 1, 2 HAVING count(*) > 30) x;

-- IC7: ranks in a closed cohort are 1..n with no gaps or duplicates
SELECT 'IC7 closed cohort with gaps/duplicate ranks' AS check_name, count(*) AS violations
FROM (SELECT cohort_id, week_start FROM league_memberships
      WHERE final_rank IS NOT NULL
      GROUP BY 1, 2
      HAVING max(final_rank) <> count(*) OR count(DISTINCT final_rank) <> count(*)) x;

-- IC8: only the current (last) week is still open (final_rank NULL)
SELECT 'IC8 open league week other than 2026-06-29' AS check_name, count(*) AS violations
FROM league_memberships WHERE final_rank IS NULL AND week_start <> DATE '2026-06-29';

-- IC9: a completed attempt earns the lesson XP (+5 bonus when perfect)
SELECT 'IC9 xp_earned <> xp_value (+5 if perfect)' AS check_name, count(*) AS violations
FROM lesson_attempts a JOIN lessons l USING (lesson_id)
WHERE a.completed_at IS NOT NULL
  AND a.xp_earned <> l.xp_value + CASE WHEN a.is_perfect THEN 5 ELSE 0 END;

-- IC10: is_perfect is exactly "completed with 0 mistakes"
SELECT 'IC10 completed, 0 mistakes, but not perfect' AS check_name, count(*) AS violations
FROM lesson_attempts WHERE completed_at IS NOT NULL AND mistakes = 0 AND NOT is_perfect;

-- IC11: only paying learners (SUPER / MAX) use streak freezes
SELECT 'IC11 streak freeze used by a FREE learner' AS check_name, count(*) AS violations
FROM daily_activity d JOIN learners l USING (learner_id)
WHERE d.used_streak_freeze AND l.subscription = 'FREE';

-- IC12: a referrer joined before the learner they referred
SELECT 'IC12 referrer joined after the referred learner' AS check_name, count(*) AS violations
FROM learners l JOIN learners r ON r.learner_id = l.referred_by
WHERE r.joined_at > l.joined_at;

-- ---------------------------------------------------------------------
-- 3. Data problems (rules the business wants but the seed data breaks;
--    explained in docs/02_schema_design.md, section "Data problems found")
-- ---------------------------------------------------------------------
SELECT 'DP1 attempt started before the learner joined' AS problem, count(*) AS rows_affected
FROM lesson_attempts a JOIN learners l USING (learner_id) WHERE a.started_at < l.joined_at
UNION ALL
SELECT 'DP2 badge earned before the learner joined', count(*)
FROM learner_achievements la JOIN learners l USING (learner_id) WHERE la.earned_at < l.joined_at
UNION ALL
SELECT 'DP3 enrollment dated after the export (30 Jun 2026)', count(*)
FROM enrollments WHERE enrolled_at >= TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
UNION ALL
SELECT 'DP4 badge dated after the export (30 Jun 2026)', count(*)
FROM learner_achievements WHERE earned_at >= TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
UNION ALL
SELECT 'DP5 XP earned in a course before enrolling in it', count(*)
FROM enrollments e
WHERE EXISTS (SELECT 1 FROM lesson_attempts a JOIN lessons l USING (lesson_id) JOIN units u USING (unit_id)
              WHERE a.learner_id = e.learner_id AND u.course_id = e.course_id AND a.started_at < e.enrolled_at)
UNION ALL
SELECT 'DP6 league cohort mixing several tiers', count(*)
FROM (SELECT cohort_id FROM league_memberships GROUP BY 1 HAVING count(DISTINCT tier) > 1) x
UNION ALL
SELECT 'DP7 XP_100 badge holder with < 100 XP', count(*)
FROM learner_achievements la JOIN achievements a USING (achievement_id)
WHERE a.code = 'XP_100'
  AND (SELECT coalesce(sum(total_xp), 0) FROM enrollments e WHERE e.learner_id = la.learner_id) < 100
UNION ALL
SELECT 'DP8 learner with 100+ XP but no XP_100 badge', count(*)
FROM (SELECT learner_id FROM enrollments GROUP BY 1 HAVING sum(total_xp) >= 100) x
WHERE NOT EXISTS (SELECT 1 FROM learner_achievements la JOIN achievements a USING (achievement_id)
                  WHERE a.code = 'XP_100' AND la.learner_id = x.learner_id);