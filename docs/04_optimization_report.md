# Duolingo Language Learning Database
## CP3 – Phase 4: Query Optimization Report

## 1. Objective

The objective of Phase 4 was to improve the performance of the Duolingo Language Learning database workload through indexing and SQL query optimization.

The optimization work focused on:

- Identifying expensive operations using `EXPLAIN ANALYZE`.
- Creating indexes for frequently filtered and joined columns.
- Rewriting queries to make filtering more efficient.
- Reducing unnecessary sequential scans and repeated table scans.
- Verifying that optimized queries preserve the original results.
- Measuring read performance, write overhead, and index storage.

The original workload in `queries/workload_30.sql` was preserved. Optimized queries are maintained separately in `sql/06_optimized_queries.sql`.

## 2. Indexes Created

Seven indexes were created in `sql/05_indexes.sql`.

| Index | Table | Purpose |
|---|---|---|
| `idx_attempts_learner_started` | lesson_attempts | Supports learner-specific timestamp range filtering and includes XP for covering scans. |
| `idx_attempts_completed_learner_lesson` | lesson_attempts | Partial index for completed attempts, supporting learner and lesson lookups. |
| `idx_activity_positive_date` | daily_activity | Partial index for positive-XP activity date filtering. |
| `idx_activity_freeze_date` | daily_activity | Partial index for rows where a streak freeze was used. |
| `idx_learners_lower_username` | learners | Expression index for case-insensitive username prefix searches. |
| `idx_attempts_started_desc` | lesson_attempts | Supports timestamp range filtering and newest-first attempt retrieval. |
| `idx_league_week_cohort_rank` | league_memberships | Supports weekly cohort filtering and ranking by XP. |

### Index design decisions

- **B-tree indexes** were used for equality filters, date ranges, and ordering.
- **Partial indexes** were used where queries only need a subset of rows.
- **INCLUDE columns** were used where additional selected columns could be retrieved through an index-only scan.
- The username index uses `lower(username)` with `text_pattern_ops` to support case-insensitive prefix matching.

All indexes were created with `IF NOT EXISTS` to avoid duplicate creation.

## 3. Benchmark Methodology

The original and optimized workloads were benchmarked using the provided benchmark script.

```bash
./benchmarks/run_benchmark.sh "<DATABASE_URL>" baseline 5 queries/workload_30.sql

./benchmarks/run_benchmark.sh "<DATABASE_URL>" optimized 5 sql/06_optimized_queries.sql
```

Each workload was executed five times. The reported values are the average execution times in milliseconds from the generated `summary.csv` files.

The benchmark includes:

- 25 read queries: R01–R25
- 5 write queries: W01–W05

The original and optimized results were stored separately in:

- `benchmarks/results/baseline/`
- `benchmarks/results/optimized/`

Improvement was calculated using:

\[
\text{Improvement (\%)} =
\frac{\text{Before} - \text{After}}{\text{Before}} \times 100
\]

A positive value indicates faster execution. A negative value indicates slower execution.

## 4. Query Performance Comparison

The table below compares the average execution time of all 30 workload queries before and after optimization. The problem and optimization columns summarize the relevant query plan observations and changes.

| Query | Before (ms) | Problem found in plan | Optimization applied | After (ms) | Improvement | Same result? |
|---|---:|---|---|---:|---:|---|
| R01 | 0.718 | Small-table sequential scans; no major bottleneck | No query rewrite; retained original query | 1.696 | -136.2% | Yes |
| R02 | 0.950 | Course lookup used sequential scan | No query rewrite; retained original query | 0.541 | 43.1% | Yes |
| R03 | 0.959 | Existing primary-key index already used | No query rewrite | 0.720 | 24.9% | Yes |
| R04 | 40.978 | Function on timestamp prevented efficient index range filtering; sequential scan of attempts | Replaced date extraction with timestamp range and added covering index | 0.426 | 99.0% | Yes |
| R05 | 8.236 | Sequential scan filtered league memberships by week and cohort | Added composite index on week, cohort and ranking columns | 0.450 | 94.5% | Yes |
| R06 | 10.665 | Sequential scan searched completed attempts for one learner | Added partial composite index for completed attempts | 0.485 | 95.5% | Yes |
| R07 | 44.647 | Large sequential scan of lesson attempts | No query rewrite; retained original query | 49.329 | -10.5% | Yes |
| R08 | 95.821 | Large sequential scan of lesson attempts | No query rewrite; retained original query | 96.208 | -0.4% | Yes |
| R09 | 32.911 | Sequential scan filtered daily activity by positive XP and date | Added partial index on activity date where XP is positive | 2.359 | 92.8% | Yes |
| R10 | 21.726 | Year extraction on date column prevented direct index filtering | Replaced year extraction with a date range and added a partial index for freeze usage | 9.246 | 57.4% | Yes |
| R11 | 0.530 | Existing username index already used | No query rewrite | 0.411 | 22.5% | Yes |
| R12 | 0.619 | Existing primary-key index used; small achievements table scanned | No query rewrite | 0.443 | 28.4% | Yes |
| R13 | 13.904 | NOT IN returned no rows because the subquery contained NULL values | Replaced NOT IN with NOT EXISTS to correct NULL handling | 18.720 | -34.6%* | No — intentional correctness correction |
| R14 | 4.801 | Sequential scan filtered league memberships | Added composite league index; planner used a bitmap index scan | 4.185 | 12.8% | Yes |
| R15 | 3.985 | Learners table scanned; daily activity used existing index | No query rewrite; retained original query | 3.545 | 11.0% | Yes |
| R16 | 14.654 | Case-insensitive prefix search was not using the new expression index | Rewrote ILIKE as lower(username) LIKE and added expression index | 11.954 | 18.4% | Yes |
| R17 | 71.447 | Sequential scan of lesson attempts with year extraction | Replaced year extraction with timestamp range and added timestamp index | 32.072 | 55.1% | Yes |
| R18 | 21.531 | Sequential scans on enrollments and courses | No query rewrite; retained original query | 22.021 | -2.3% | Yes |
| R19 | 3039.674 | Two correlated subqueries repeatedly scanned lesson_attempts for every lesson | Replaced correlated subqueries with one grouped aggregation and LEFT JOIN | 54.191 | 98.2% | Yes |
| R20 | 36.987 | Date conversion in filter prevented efficient timestamp range scan | Replaced date conversion filter with timestamp range; used timestamp index | 7.969 | 78.5% | Yes |
| R21 | 30.527 | Existing daily activity index used; execution time varied | No query rewrite | 19.903 | 34.8% | Yes |
| R22 | 84.198 | Sequential scan of lesson attempts | No query rewrite; planner used the new timestamp index | 17.081 | 79.7% | Yes |
| R23 | 23.943 | Sequential scans on daily activity and learners | No query rewrite; planner used the positive-XP partial index | 6.531 | 72.7% | Yes |
| R24 | 131.159 | Large sequential scan of lesson attempts with joins | No query rewrite; retained original query | 131.997 | -0.6% | Yes |
| R25 | 292.139 | Sequential scans on lesson attempts and learners | No query rewrite; retained original query | 303.162 | -3.8% | Yes |
| W01 | 2.554 | Write operation; no major scan bottleneck | No query rewrite | 2.170 | 15.0% | Yes |
| W02 | 6.933 | Existing primary-key lookup required for write | No query rewrite; additional index maintenance did not prevent improvement | 1.592 | 77.0% | Yes |
| W03 | 1.323 | Write operation; no major scan bottleneck | No query rewrite | 1.257 | 5.0% | Yes |
| W04 | 17.923 | Sequential scan of league memberships during write | Composite league index also adds write-maintenance overhead | 19.208 | -7.2% | Yes |
| W05 | 169.760 | Sequential scans on achievements and enrollments | No query rewrite | 163.505 | 3.7% | Yes |
| **Total** | **4226.202** | **Includes all 30 workload queries** | **Combined effect of query rewrites and indexes** | **983.377** | **76.73%** | **See note below** |

*R13 is an intentional correctness correction, not an equivalent performance comparison. The original NOT IN query returned zero rows because its subquery contained NULL values. The corrected NOT EXISTS query returns 24,268 learners. Therefore, the Total row is a sum of benchmark averages and is not a strict like-for-like comparison.*

### 4.1 Observations

The largest read-query improvements were observed in:

- R04: 99.0%
- R19: 98.2%
- R06: 95.5%
- R05: 94.5%
- R09: 92.8%

R07, R08, R18, R24 and R25 did not show meaningful improvements. Their plans continued to use sequential scans, and the existing indexes were not beneficial enough for those query patterns.

The expression index created for R16 was not selected in the captured execution plan; PostgreSQL used the existing username index instead.

### 4.2 Write-query observations

W04 became approximately 7.2% slower after adding the league index. This is an acceptable trade-off for the improvements to league-related read queries, although index maintenance adds some write overhead. The other write queries did not show a meaningful slowdown in the measured averages.


## 5. EXPLAIN ANALYZE: Before and After

The following comparisons use the actual execution plans collected from the baseline and optimized result files.

### 5.1 R04 – Daily goal ring

**Baseline plan:**

- Used a nested-loop left join.
- Performed a Parallel Sequential Scan on `lesson_attempts`.
- Applied a date conversion in the filter using `date(started_at)`.
- Examined the attempts table instead of directly using the learner and timestamp conditions.

**Optimized plan:**

- Used `idx_attempts_learner_started`.
- Performed an Index Only Scan on `lesson_attempts`.
- Applied the learner ID and timestamp range as index conditions.
- Reported zero heap fetches in the optimized runs.

| Metric | Baseline | Optimized |
|---|---:|---:|
| Average execution time | 40.978 ms | 0.426 ms |
| Execution time in representative plan | 86.451 ms | 0.211 ms |

**Optimization:** Replaced date extraction with a timestamp range and added a composite index on `(learner_id, started_at)` with `xp_earned` included.

The timestamp boundaries use the `Asia/Kolkata` timezone offset to preserve the original date semantics.

### 5.2 R05 – Weekly league ranking

**Baseline plan:**

- Used a Sequential Scan on `league_memberships`.
- Examined 28,598 rows and removed 28,568 rows through filtering.
- Used the learner primary-key index to retrieve learner details.

**Optimized plan:**

- Used `idx_league_week_cohort_rank`.
- Applied `week_start` and `cohort_id` as index conditions.
- Retrieved the required 30 league rows through an Index Only Scan.
- Continued using the existing primary-key index for learner details.

| Metric | Baseline | Optimized |
|---|---:|---:|
| Average execution time | 8.236 ms | 0.450 ms |
| Execution time in representative plan | 21.243 ms | 0.312 ms |

**Optimization:** Created a composite index on `(week_start, cohort_id, weekly_xp DESC, learner_id)`.

### 5.3 R06 – First lesson not completed

**Baseline plan:**

- Used a Nested Loop Anti Join.
- Performed a Sequential Scan on `lesson_attempts`.
- Examined the attempts table while filtering by learner and completion status.

**Optimized plan:**

- Used `idx_attempts_completed_learner_lesson`.
- Performed an Index Only Scan.
- Retrieved the relevant completed attempts using the learner ID condition.
- The partial index excludes incomplete attempts.

| Metric | Baseline | Optimized |
|---|---:|---:|
| Average execution time | 10.665 ms | 0.485 ms |
| Execution time in representative plan | 10.985 ms | 0.285 ms |

**Optimization:** Created a partial composite index on `(learner_id, lesson_id)` where `completed_at IS NOT NULL`.

### 5.4 R09 – Daily active learners in June 2026

**Baseline plan:**

- Used a Parallel Sequential Scan on `daily_activity`.
- Checked the positive-XP and date conditions across the table.
- Used partial aggregation followed by final grouping.

**Optimized plan:**

- Used `idx_activity_positive_date`.
- Performed an Index Only Scan.
- Applied the date range directly as an index condition.
- Read significantly fewer buffers.

| Metric | Baseline | Optimized |
|---|---:|---:|
| Average execution time | 32.911 ms | 2.359 ms |
| Execution time in representative plan | 19.062 ms | 2.197 ms |

**Optimization:** Created a partial index on `activity_date` where `xp > 0`.

### 5.5 R19 – Lesson completion statistics

**Baseline plan:**

- Used an Incremental Sort and Nested Loop.
- Executed two correlated subqueries for each lesson.
- Each subquery performed a Sequential Scan of `lesson_attempts`.
- Repeated scans caused a large amount of unnecessary work.

**Optimized plan:**

- Aggregated `lesson_attempts` once using a HashAggregate.
- Joined the aggregated result with lessons and units.
- Used a LEFT JOIN to preserve lessons without attempts.
- Used `COALESCE` to return zero completions where appropriate.

| Metric | Baseline | Optimized |
|---|---:|---:|
| Average execution time | 3039.674 ms | 54.191 ms |
| Execution time in representative plan | 3032.853 ms | 53.824 ms |

**Optimization:** Replaced repeated correlated subqueries with one grouped aggregation and a LEFT JOIN.

This was the largest absolute performance improvement in the workload.

## 6. Index Storage Analysis

Index storage was measured using PostgreSQL's `pg_relation_size()`.

| Index | Index size | Table size | Index as % of table |
|---|---:|---:|---:|
| `idx_activity_freeze_date` | 64 kB | 8256 kB | 0.78% |
| `idx_activity_positive_date` | 1168 kB | 8256 kB | 14.15% |
| `idx_attempts_completed_learner_lesson` | 3584 kB | 14 MB | 25.24% |
| `idx_attempts_learner_started` | 7480 kB | 14 MB | 52.68% |
| `idx_attempts_started_desc` | 9136 kB | 14 MB | 64.34% |
| `idx_league_week_cohort_rank` | 920 kB | 1904 kB | 48.32% |
| `idx_learners_lower_username` | 1096 kB | 3008 kB | 36.44% |

The combined size of the seven indexes is approximately 22.9 MiB.

### Storage observations

- `idx_attempts_started_desc` is the largest index at 9136 kB.
- `idx_attempts_learner_started` also occupies a considerable amount of storage.
- `idx_activity_freeze_date` is small because it is a partial index.
- The indexes introduce additional storage requirements in exchange for faster read operations.

The measured index sizes are specific to the database at the time of measurement.

## 7. Result Correctness and Equivalence

The optimized queries were checked against their original versions.

For the performance rewrites, `EXCEPT ALL` comparisons were used to detect differences while preserving duplicate-row semantics.

| Query | Verification |
|---|---|
| R04 | 0 mismatched rows |
| R10 | 0 mismatched rows |
| R16 | 0 mismatched rows |
| R17 | 0 mismatched rows |
| R19 | 0 mismatched rows |
| R20 | 0 mismatched rows |

All six verified performance rewrites returned equivalent results.

### R13 – Intentional correctness correction

R13 required a correctness fix rather than an equivalent performance rewrite.

The original query used `NOT IN`. Its subquery contained NULL values in `referred_by`, causing SQL's NULL comparison behaviour to make the original query return zero rows.

The query was rewritten using `NOT EXISTS`:

```sql
SELECT l.learner_id, l.username
FROM learners l
WHERE NOT EXISTS (
    SELECT 1
    FROM learners r
    WHERE r.referred_by = l.learner_id
);
```

Observed results:

- Total learners: 30,000
- NULL values in `referred_by`: 21,102
- Original `NOT IN` query result: 0 rows
- Corrected `NOT EXISTS` query result: 24,268 rows

The new query provides the intended result by correctly handling NULL values.

Therefore, R13 is not marked as result-equivalent to the original query.

## 8. Write Overhead

Indexes can increase the cost of INSERT, UPDATE, and DELETE operations because PostgreSQL may need to maintain additional index entries.

The write benchmark results were:

| Query | Before (ms) | After (ms) | Change |
|---|---:|---:|---|
| W01 | 2.554 | 2.170 | 15.0% faster |
| W02 | 6.933 | 1.592 | 77.0% faster |
| W03 | 1.323 | 1.257 | 5.0% faster |
| W04 | 17.923 | 19.208 | 7.2% slower |
| W05 | 169.760 | 163.505 | 3.7% faster |

Only W04 became slower in the optimized benchmark.

The additional index on `league_memberships` may contribute to write-maintenance overhead, although the benchmark alone cannot establish that it caused the entire difference.

The observed 7.2% increase is considered an acceptable trade-off for the read improvements to weekly league ranking and related league queries.

The other four write queries were faster in the measured optimized run.

## 9. Queries That Did Not Improve

Not every query benefited from the optimization changes.

Examples include:

- **R01:** Execution time increased from 0.718 ms to 1.696 ms. The query was already very fast, so additional optimization was not a priority.
- **R07 and R08:** Both continued to use Sequential Scans on `lesson_attempts`. The available indexes did not produce a better plan for these queries.
- **R13:** The corrected query takes longer, but it returns the intended results instead of the incorrect empty result.
- **R18:** The execution plan continued to use Sequential Scans on `enrollments` and `courses`.
- **R24 and R25:** The plans continued to process large portions of the attempts data, and the measured improvements were negligible or negative.

R16 also deserves attention: although the expression index `idx_learners_lower_username` was created, the captured optimized plan selected the existing `learners_username_key` index instead. Therefore, the benchmark does not establish that the new expression index improved R16.

These cases show that adding indexes does not automatically make every query faster. The PostgreSQL