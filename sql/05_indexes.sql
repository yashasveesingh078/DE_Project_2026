-- ============================================================
-- Duolingo DBMS Project - CP3: Phase 4 Optimization
-- File: 05_indexes.sql
-- ============================================================

-- R04: Daily goal ring
-- Supports lookup by learner and date range.
-- INCLUDE avoids fetching xp_earned separately when an
-- index-only scan is possible.
CREATE INDEX IF NOT EXISTS idx_attempts_learner_started
ON duolingo.lesson_attempts (learner_id, started_at)
INCLUDE (xp_earned);


-- R06: First lesson not completed by learner 1042
-- Partial index stores only completed attempts.
-- Column order supports learner_id and lesson_id filtering.
CREATE INDEX IF NOT EXISTS idx_attempts_completed_learner_lesson
ON duolingo.lesson_attempts (learner_id, lesson_id)
WHERE completed_at IS NOT NULL;


-- R09: Daily active learners in June 2026
-- Partial index excludes rows where xp is zero or negative.
CREATE INDEX IF NOT EXISTS idx_activity_positive_date
ON duolingo.daily_activity (activity_date)
WHERE xp > 0;


-- R10: Streak freezes used per subscription tier
-- Partial index contains only rows where a freeze was used.
CREATE INDEX IF NOT EXISTS idx_activity_freeze_date
ON duolingo.daily_activity (activity_date)
INCLUDE (learner_id)
WHERE used_streak_freeze = TRUE;


-- R16: Case-insensitive username prefix search
-- Supports lower(username) LIKE 'karan%' after query rewrite.
-- text_pattern_ops supports prefix matching.
CREATE INDEX IF NOT EXISTS idx_learners_lower_username
ON duolingo.learners (lower(username) text_pattern_ops);


-- R20 and R22: Date-range filtering and newest-first attempts
-- started_at supports range filtering and DESC ordering.
-- Included columns can help cover R22.
CREATE INDEX IF NOT EXISTS idx_attempts_started_desc
ON duolingo.lesson_attempts (started_at DESC)
INCLUDE (attempt_id, learner_id, lesson_id, xp_earned);


-- W04: Weekly league ranking
-- week_start filters the target week.
-- cohort_id groups members; weekly_xp and learner_id
-- support the ranking order within each cohort.
CREATE INDEX IF NOT EXISTS idx_league_week_cohort_rank
ON duolingo.league_memberships
    (week_start, cohort_id, weekly_xp DESC, learner_id);
