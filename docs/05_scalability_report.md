# CP4: Scalability and Performance Report

## 1. Objective

The objective of this phase was to evaluate the Duolingo Language Learning database under a larger workload, compare query performance against the seed dataset, identify bottlenecks, and propose improvements for future scalability.

The experiment used a separate Neon database named `duolingo_large`. The original seed database was not modified.

## 2. Dataset Overview

The large dataset was loaded into 11 tables.

| Table | Rows loaded |
|---|---:|
| languages | 10 |
| courses | 11 |
| units | 220 |
| lessons | 1,760 |
| achievements | 10 |
| learners | 600,000 |
| enrollments | 750,000 |
| lesson_attempts | 3,608,300 |
| daily_activity | 3,626,847 |
| league_memberships | 546,036 |
| learner_achievements | 773,472 |
| **Total** | **9,906,666** |

The dataset contains approximately 9.91 million records.

The `lesson_attempts` data covers 1 January 2025 through 30 June 2026.

All 11 CSV files were loaded successfully. The 12 integrity checks (IC1–IC12) reported zero violations.

The loader's seed-count comparison showed mismatches for larger tables because its expected values represented the seed dataset, not the large dataset. The actual loaded counts are reported above.

## 3. Storage Analysis

The large dataset approached the Neon project's 1,024 MB storage limit. The database size query reported approximately 1,026 MB.

### 3.1 Table sizes

| Table | Approximate size |
|---|---:|
| lesson_attempts | 481 MB |
| daily_activity | 231 MB |
| learners | 156 MB |
| enrollments | 54 MB |
| learner_achievements | 49 MB |
| league_memberships | 47 MB |
| lessons | 256 KB |
| units | 72 KB |
| courses | 56 KB |
| achievements | 56 KB |
| languages | 40 KB |

The largest storage consumers were `lesson_attempts`, `daily_activity`, and `learners`.

### 3.2 Index sizes

Some of the larger indexes were:

| Index | Approximate size |
|---|---:|
| idx_attempts_learner_started | 140 MB |
| daily_activity_pkey | 78 MB |
| lesson_attempts_pkey | 77 MB |
| learners_email_key | 47 MB |
| learners_username_key | 37 MB |
| learner_achievements_pkey | 17 MB |
| enrollments_pkey | 16 MB |
| learners_pkey | 13 MB |
| league_memberships_pkey | 12 MB |

The primary-key and unique indexes were retained.

## 4. Indexing and Database Preparation

The database was analyzed using:

```sql
ANALYZE VERBOSE;
```

This refreshed PostgreSQL's table and index statistics before benchmarking.

The first custom index in `sql/05_indexes.sql` was successfully created:

```sql
CREATE INDEX idx_attempts_learner_started
ON lesson_attempts (learner_id, started_at)
INCLUDE (xp_earned);
```

However, execution of the remaining index statements stopped when Neon reported that the project storage limit of 1,024 MB had been exceeded.

The following six planned indexes could not be created:

- `idx_attempts_completed_learner_lesson`
- `idx_activity_positive_date`
- `idx_activity_freeze_date`
- `idx_learners_lower_username`
- `idx_attempts_started_desc`
- `idx_league_week_cohort_rank`

This limitation was imposed by the Neon storage quota. It was not a SQL syntax error.

## 5. Benchmark Methodology

The optimized workload was executed using:

```bash
./benchmarks/run_benchmark.sh "$DBURL" large 3 sql/06_optimized_queries.sql
```

The benchmark used:

- Three runs per query on the large dataset.
- `EXPLAIN (ANALYZE, BUFFERS)` to inspect execution plans.
- Average execution time for performance comparison.
- Transaction rollback for write-query testing, preventing benchmark writes from permanently changing the data.

The seed optimized workload used five runs per query, while the large workload used three. Therefore, the comparison is indicative rather than a perfectly controlled comparison.

The benchmark completed R01–R25 and W01–W03. W04 failed because the storage limit was reached, and W05 was not executed.

The generated large-dataset summary is stored in:

`benchmarks/results/large/summary.csv`

Raw query plans are stored in `benchmarks/results/large/`.

## 6. Seed vs Large Dataset Performance

All times are average execution times in milliseconds.

| Query | Seed avg (ms) | Large avg (ms) |
|---|---:|---:|
| R01 | 1.696 | 0.866 |
| R02 | 0.541 | 1.095 |
| R03 | 0.720 | 1.161 |
| R04 | 0.426 | 1.687 |
| R05 | 0.450 | 109.993 |
| R06 | 0.485 | 1.896 |
| R07 | 49.329 | 1286.890 |
| R08 | 96.208 | 1844.568 |
| R09 | 2.359 | 524.848 |
| R10 | 9.246 | 459.042 |
| R11 | 0.411 | 0.833 |
| R12 | 0.443 | 0.900 |
| R13 | 18.720 | 568.959 |
| R14 | 4.185 | 101.602 |
| R15 | 3.545 | 96.318 |
| R16 | 11.954 | 503.259 |
| R17 | 32.072 | 567.722 |
| R18 | 22.021 | 450.650 |
| R19 | 54.191 | 1216.451 |
| R20 | 7.969 | 409.583 |
| R21 | 19.903 | 279.918 |
| R22 | 17.081 | 1186.436 |
| R23 | 6.531 | 296.188 |
| R24 | 131.997 | 1724.054 |
| R25 | 303.162 | 4553.919 |
| W01 | 2.170 | 2.512 |
| W02 | 1.592 | 7.488 |
| W03 | 1.257 | 1.599 |
| W04 | 19.208 | Not completed |
| W05 | 163.505 | Not executed |

The large dataset increased execution time for many queries, especially queries involving full-table scans, aggregations, joins, sorting, and window functions.

R01 was faster in the large run than in the seed run. This is an observed result and should not be interpreted as proof that larger datasets generally improve performance.

## 7. Performance Target Evaluation

The targets specified for this project were:

- Learner-facing queries and writes: below 5 ms.
- Interactive queries: below 250 ms.
- Reports and analytics: below 5,000 ms.
- Batch jobs: below 1,000 ms.

The evaluation below uses the measured average execution time.

### 7.1 Learner-facing queries

Target: below 5 ms.

| Query | Average (ms) | Result |
|---|---:|---|
| R02 | 1.095 | Pass |
| R03 | 1.161 | Pass |
| R04 | 1.687 | Pass |
| R05 | 109.993 | Fail |
| R06 | 1.896 | Pass |
| R11 | 0.833 | Pass |
| R12 | 0.900 | Pass |
| W01 | 2.512 | Pass |
| W02 | 7.488 | Fail |
| W03 | 1.599 | Pass |

**Result: 8 out of 10 completed queries met the target.**

R05 was affected by a sequential scan of `league_memberships`. W02 used the primary-key index but filtered many rows before finding the target attempt.

### 7.2 Interactive queries

Target: below 250 ms.

| Query | Average (ms) | Result |
|---|---:|---|
| R01 | 0.866 | Pass |
| R13 | 568.959 | Fail |
| R16 | 503.259 | Fail |
| R21 | 279.918 | Fail |
| R22 | 1186.436 | Fail |
| R23 | 296.188 | Fail |

**Result: 1 out of 6 queries met the target.**

R13, R16, and R22 showed particularly clear opportunities for optimization.

### 7.3 Reports and analytics

Target: below 5,000 ms.

| Query | Average (ms) | Result |
|---|---:|---|
| R07 | 1286.890 | Pass |
| R08 | 1844.568 | Pass |
| R09 | 524.848 | Pass |
| R10 | 459.042 | Pass |
| R14 | 101.602 | Pass |
| R15 | 96.318 | Pass |
| R17 | 567.722 | Pass |
| R18 | 450.650 | Pass |
| R19 | 1216.451 | Pass |
| R20 | 409.583 | Pass |
| R24 | 1724.054 | Pass |
| R25 | 4553.919 | Pass |

**Result: 12 out of 12 queries met the target.**

R25 was close to the 5,000 ms threshold.

### 7.4 Batch jobs

Target: below 1,000 ms.

| Query | Large dataset result |
|---|---|
| W04 | Failed during execution due to storage limit |
| W05 | Not executed |

No performance conclusion can be drawn for these two queries from the large-dataset experiment.

## 8. Query Plan Analysis and Bottlenecks

The raw plans were inspected for queries that missed their performance targets.

### R05: League leaderboard

The plan used a parallel sequential scan of `league_memberships` to filter by week and cohort. It then joined the matching learners.

The planned index `idx_league_week_cohort_rank` could support filtering and leaderboard ordering:

```sql
CREATE INDEX idx_league_week_cohort_rank
ON league_memberships (week_start, cohort_id, weekly_xp DESC);
```

This index was not created because of the storage limit.

### R13: Learners without referrals

The plan used a hash right anti join and scanned `learners` twice. The hash operation spilled to temporary storage.

An index on `referred_by` could be evaluated:

```sql
CREATE INDEX idx_learners_referred_by
ON learners (referred_by);
```

However, the query returns a large portion of the learner table. PostgreSQL may still prefer sequential scans, so the index's actual benefit must be benchmarked.

### R16: Case-insensitive username search

The query applies `lower(username)` but the existing username index is on the original username column. The plan therefore scans many index entries and applies the lowercase expression as a filter.

The intended expression index is:

```sql
CREATE INDEX idx_learners_lower_username
ON learners (lower(username));
```

This index was not created because of the storage limit.

### R21: Daily activity streak

The query scans `daily_activity` to filter a seven-day date range and then groups records by learner.

A date-oriented index could reduce the number of rows scanned:

```sql
CREATE INDEX idx_activity_freeze_date
ON daily_activity (activity_date, learner_id);
```

The corresponding planned index was not created.

### R22: Recent attempts with deep OFFSET

The plan scanned `lesson_attempts`, sorted the results by `started_at DESC`, and used an external merge sort that spilled to disk.

An index on the timestamp could support ordered retrieval:

```sql
CREATE INDEX idx_attempts_started_desc
ON lesson_attempts (started_at DESC);
```

This planned index was not created.

For production pagination, keyset pagination is preferable to large OFFSET values. For example, the next page can use the last returned timestamp and attempt ID as a cursor.

### R23: Active paid learners

The plan used parallel scans and a parallel hash join between `learners` and `daily_activity`.

The planned partial index on positive activity dates could be evaluated for this workload:

```sql
CREATE INDEX idx_activity_positive_date
ON daily_activity (activity_date, learner_id)
WHERE xp > 0;
```

The index was not created because of the storage limit.

### W02: Updating the latest incomplete attempt

The query used a backward scan of the primary-key index and filtered records by completion status and date.

The average was 7.488 ms, although the median was 2.180 ms. The first run was slower than the later runs, indicating variation between benchmark runs.

## 9. Partitioning Design

The large `lesson_attempts` table contains 3,608,300 records covering January 2025 through June 2026.

Monthly range partitioning on `started_at` is proposed for future scalability.

The proposed design is documented in:

`sql/08_partitioning.sql`

It contains:

- Monthly range partitions from January 2025 through June 2026.
- A default partition for dates outside the explicitly defined ranges.
- An index on `started_at DESC, attempt_id DESC`.
- An example date-filtered query to demonstrate partition pruning.

### Important implementation limitation

The partitioned table was not created in Neon. Execution failed while creating the parent table because the project had exceeded its 1,024 MB storage limit.

The original `duolingo.lesson_attempts` table remains unchanged.

The proposed partitioned table uses a composite primary key `(attempt_id, started_at)`. PostgreSQL requires a partitioned table's unique or primary-key constraint to include the partition key. This differs from the original table's primary key on `attempt_id` alone.

Therefore, the design is a proposal and has not been tested against the full dataset. Partition pruning and performance improvements have not been experimentally verified.

## 10. Scaling Architecture for 100x Growth

For a future system handling substantially more data, the following improvements are recommended.

### 10.1 Partitioning

Partition large time-oriented tables such as `lesson_attempts` and `daily_activity` by month or another suitable time interval.

This can reduce the amount of data scanned by queries with time filters and make retention and maintenance easier.

### 10.2 Index strategy

Create indexes based on frequently executed query patterns rather than indexing every column.

Prioritize:

- Foreign-key lookup columns.
- Frequently filtered date columns.
- Composite indexes matching common filter and sort combinations.
- Expression indexes for case-insensitive searches.
- Partial indexes for frequently queried subsets.

Index creation should be planned alongside storage capacity because indexes consume additional disk space and increase write costs.

### 10.3 Read replicas and caching

Read replicas can distribute reporting and read-heavy workloads.

Frequently requested learner dashboards, course information, and leaderboard results can be cached to reduce repeated database work.

### 10.4 Sharding

If a single database cannot support the required data volume and workload, sharding can distribute learners and their activity across multiple database nodes.

A suitable shard key could be based on learner identity, provided cross-shard queries and relationships are designed carefully.

### 10.5 Maintenance

Regular `ANALYZE` and appropriate vacuum maintenance should be scheduled.

Query plans, index usage, table growth, disk usage, and slow queries should be monitored continuously.

## 11. Limitations and Failures

The main experimental limitation was the Neon project storage quota of 1,024 MB.

This affected the experiment in three ways:

1. Only one of the seven planned custom indexes was created successfully.
2. W04 could not complete because the database could not extend its storage.
3. The partitioned demonstration table could not be created because storage was already exhausted. W05 was consequently not benchmarked.

The storage constraint prevented a complete evaluation of the intended indexing and partitioning strategy.

No unavailable timings or performance improvements have been estimated or fabricated.

## 12. Conclusion

The large-dataset experiment successfully loaded 9,906,666 records across 11 tables and completed benchmarks for 28 of the 30 workload queries.

All 12 integrity checks passed. The experiment showed that simple indexed lookups remained fast, while several queries involving sequential scans, joins, aggregations, and sorting became significantly slower as the dataset grew.

The analytics workload met its defined 5-second target, while several interactive queries exceeded their 250 ms target.

The experiment also demonstrated the importance of storage planning: indexes and partitioned structures require additional disk space, and database capacity can limit the optimizations that can be tested.

Monthly partitioning, targeted indexing, keyset pagination, caching, read replicas, and sharding are proposed as future improvements. These recommendations require further testing on an environment with sufficient storage.

Overall, the project provides a measured baseline for future performance optimization and database scaling.