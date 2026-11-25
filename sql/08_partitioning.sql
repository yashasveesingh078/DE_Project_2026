-- EXECUTION STATUS: NOT EXECUTED
-- Reason: Neon project storage limit (1024 MB) exceeded.
-- This file documents the proposed monthly partitioning design.
-- The existing duolingo.lesson_attempts table remains unchanged.

-- ============================================================
-- CP4: Partitioning demonstration for lesson_attempts
-- Original table remains unchanged.
-- Partition key: started_at (monthly RANGE partitions)
-- Data range: January 2025 to June 2026
-- ============================================================

CREATE TABLE IF NOT EXISTS duolingo.lesson_attempts_partitioned (
    attempt_id    bigint       NOT NULL,
    learner_id    integer      NOT NULL,
    lesson_id     integer      NOT NULL,
    started_at    timestamptz  NOT NULL,
    completed_at  timestamptz,
    mistakes      smallint     NOT NULL DEFAULT 0,
    hearts_lost   smallint     NOT NULL DEFAULT 0,
    xp_earned     smallint     NOT NULL DEFAULT 0,
    is_perfect    boolean      NOT NULL DEFAULT false,
    device        varchar(7)   NOT NULL,

    CONSTRAINT lesson_attempts_partitioned_pkey
        PRIMARY KEY (attempt_id, started_at),

    CONSTRAINT lap_learner_fkey
        FOREIGN KEY (learner_id)
        REFERENCES duolingo.learners (learner_id)
        ON DELETE CASCADE,

    CONSTRAINT lap_lesson_fkey
        FOREIGN KEY (lesson_id)
        REFERENCES duolingo.lessons (lesson_id)
        ON DELETE RESTRICT,

    CONSTRAINT lap_device_chk
        CHECK (device IN ('ANDROID', 'IOS', 'WEB')),

    CONSTRAINT lap_mistakes_chk
        CHECK (mistakes >= 0),

    CONSTRAINT lap_hearts_range
        CHECK (hearts_lost BETWEEN 0 AND 5),

    CONSTRAINT lap_hearts_le_mistakes
        CHECK (hearts_lost <= mistakes),

    CONSTRAINT lap_xp_chk
        CHECK (xp_earned >= 0),

    CONSTRAINT lap_time_order
        CHECK (completed_at IS NULL OR completed_at > started_at),

    CONSTRAINT lap_quit_no_xp
        CHECK (completed_at IS NOT NULL OR xp_earned = 0),

    CONSTRAINT lap_done_has_xp
        CHECK (completed_at IS NULL OR xp_earned > 0),

    CONSTRAINT lap_perfect_chk
        CHECK (
            NOT is_perfect
            OR (mistakes = 0 AND completed_at IS NOT NULL)
        )
)
PARTITION BY RANGE (started_at);


-- Create one monthly partition from January 2025 through June 2026.
DO $$
DECLARE
    partition_start date;
    partition_end   date;
    partition_name  text;
BEGIN
    FOR partition_start IN
        SELECT generate_series(
            DATE '2025-01-01',
            DATE '2026-06-01',
            INTERVAL '1 month'
        )::date
    LOOP
        partition_end := (partition_start + INTERVAL '1 month')::date;
        partition_name :=
            'lesson_attempts_p_' || to_char(partition_start, 'YYYY_MM');

        EXECUTE format(
            'CREATE TABLE IF NOT EXISTS duolingo.%I
             PARTITION OF duolingo.lesson_attempts_partitioned
             FOR VALUES FROM (%L) TO (%L)',
            partition_name,
            partition_start::text || ' 00:00:00+05:30',
            partition_end::text || ' 00:00:00+05:30'
        );
    END LOOP;
END $$;


-- Catch dates outside the explicitly created monthly ranges.
CREATE TABLE IF NOT EXISTS duolingo.lesson_attempts_p_default
PARTITION OF duolingo.lesson_attempts_partitioned
DEFAULT;


-- Supports recent-attempt queries and descending date ordering.
CREATE INDEX IF NOT EXISTS idx_lap_started_desc
ON duolingo.lesson_attempts_partitioned
    (started_at DESC, attempt_id DESC);


-- Example query: PostgreSQL can prune partitions outside this date range.
EXPLAIN
SELECT attempt_id, learner_id, started_at
FROM duolingo.lesson_attempts_partitioned
WHERE started_at >= TIMESTAMPTZ '2026-06-01 00:00:00+05:30'
  AND started_at <  TIMESTAMPTZ '2026-07-01 00:00:00+05:30'
ORDER BY started_at DESC
LIMIT 25;