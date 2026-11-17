# Baseline Benchmark Timings

## Benchmark setup

- Workload: `queries/workload_30.sql` (R01–R25 and W01–W05)
- Runs per query: 3
- Measurement: `EXPLAIN (ANALYZE, BUFFERS)`
- Phase: Baseline, before adding optimization indexes
- Timings are in milliseconds (ms).

## Timing results

| SQL Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) |
|---|:---:|---:|---:|---:|---:|
| R01 Course path: units and lessons of the Spanish course for English speakers, in order | READ | 1.463 | 0.349 | 0.343 | 0.718 |
| R02 Home screen: learner 1042's courses with total XP | READ | 2.556 | 0.141 | 0.153 | 0.950 |
| R03 Streak counter: learner 1042's current streak (consecutive days up to 30 June 2026, freezes count) | READ | 2.217 | 0.325 | 0.334 | 0.959 |
| R04 Daily goal ring: XP learner 1042 earned on 30 June 2026 vs their daily goal | READ | 86.451 | 16.882 | 19.601 | 40.978 |
| R05 Leagues tab: leaderboard of learner 1042's cohort for the week starting 29 June 2026 | READ | 21.243 | 1.772 | 1.694 | 8.236 |
| R06 "Start" button: the first lesson of learner 1042's Spanish course they have not completed yet | READ | 10.985 | 10.610 | 10.399 | 10.665 |
| R07 Curriculum team: lessons of the Spanish course with the most mistakes per attempt (100+ attempts) | READ | 45.946 | 44.173 | 43.823 | 44.647 |
| R08 Product analytics: quit rate per lesson type | READ | 94.129 | 98.843 | 94.491 | 95.821 |
| R09 Growth: daily active learners in June 2026 | READ | 60.425 | 19.246 | 19.062 | 32.911 |
| R10 Monetisation: streak freezes used per subscription tier in 2026 | READ | 26.874 | 20.734 | 17.570 | 21.726 |
| R11 Sign-in by username | READ | 1.409 | 0.089 | 0.092 | 0.530 |
| R12 Profile: learner 1042's achievements, newest first | READ | 1.595 | 0.131 | 0.130 | 0.619 |
| R13 Referral programme: learners who have not referred anyone yet | READ | 13.785 | 12.621 | 15.305 | 13.904 |
| R14 Leagues team: promotion and demotion rates per tier over the last 4 completed weeks | READ | 4.821 | 4.758 | 4.823 | 4.801 |
| R15 Retention: learners who joined in January 2026 and were still active in June 2026 | READ | 6.581 | 2.663 | 2.710 | 3.985 |
| R16 Friends: search learners by username starting with "Karan" | READ | 30.571 | 6.920 | 6.471 | 14.654 |
| R17 Product analytics: perfect-lesson rate per device in 2026 | READ | 71.412 | 71.124 | 71.806 | 71.447 |
| R18 Course popularity: enrollments per course, and how many started in 2026 | READ | 30.338 | 17.336 | 16.918 | 21.531 |
| R19 Curriculum report: completions and average mistakes of every lesson in the Spanish course | READ | 3019.192 | 3066.978 | 3032.853 | 3039.674 |
| R20 Growth: XP earned per day across the platform and running total, June 2026 | READ | 36.163 | 36.607 | 38.192 | 36.987 |
| R21 Streak reminders: learners active every day from 23 to 29 June but not yet on 30 June | READ | 80.395 | 5.509 | 5.676 | 30.527 |
| R22 Support console: all lesson attempts, newest first, page 4,001 (25 per page) | READ | 84.157 | 86.032 | 82.405 | 84.198 |
| R23 Monetisation: Super and Max learners in India who were active in the last 7 days of June 2026 | READ | 23.531 | 24.268 | 24.030 | 23.943 |
| R24 Curriculum team: average hearts lost per lesson, by CEFR level | READ | 132.191 | 132.653 | 128.634 | 131.159 |
| R25 Notifications team: lessons started per hour of the day, per country | READ | 286.419 | 293.657 | 296.340 | 292.139 |
| W01 Lesson start: learner 1042 starts lesson 1 | WRITE | 5.766 | 0.915 | 0.980 | 2.554 |
| W02 Lesson end: finish the most recent unfinished attempt of 30 June 2026 with 2 mistakes | WRITE | 16.952 | 1.950 | 1.897 | 6.933 |
| W03 Daily activity: add 20 XP to learner 1042's 1 July 2026 (creating the row if needed) | WRITE | 2.538 | 0.702 | 0.729 | 1.323 |
| W04 Weekly league close (week of 29 June 2026): rank everyone in their cohort and set promotion results | WRITE | 21.272 | 18.388 | 14.110 | 17.923 |
| W05 Achievements catch-up: award the "100 XP" badge to every learner who has 100+ XP but not the badge | WRITE | 262.796 | 123.176 | 123.307 | 169.760 |
| **Total average execution time** | — | — | — | — | **4151.128** |

## Scan types and observations

| Query | Scan type(s) from plan | Observation |
|---|---|---|
| R01 | Seq Scan on units; Seq Scan on courses; Index Scan on lessons | The course and unit tables are scanned; lessons are accessed through the unit/lesson index. |
| R02 | Index Scan on enrollments; Seq Scan on courses | The learner's enrollments use an index; the small courses table is scanned. |
| R03 | Index Only Scan on daily_activity | The daily_activity primary-key index supports retrieval of the learner's activity dates. |
| R04 | Index Scan on learners; Seq Scan on lesson_attempts | The learner lookup is indexed, but lesson_attempts is scanned to find matching attempts and aggregate XP. |
| R05 | Index Scan on league_memberships; Seq Scan on league_memberships; Index Scan on learners | The cohort lookup uses an index, while membership rows and learner details require additional access. |
| R06 | Index Scan on units; Index Scan on lessons; Seq Scan on lesson_attempts | Units and lessons use indexes, but the NOT EXISTS check scans lesson_attempts for completed attempts. |
| R07 | Seq Scan on lesson_attempts; Seq Scan on lessons; Seq Scan on units | Attempts are scanned and joined to lesson and unit data before grouping and calculating averages. |
| R08 | Seq Scan on lesson_attempts; Seq Scan on lessons | All attempts are examined and joined to lessons to calculate completion and quit rates by type. |
| R09 | Seq Scan on daily_activity | The date range and XP condition are evaluated across a sequential scan of daily_activity. |
| R10 | Seq Scan on daily_activity; Index Scan on learners | Daily activity is scanned to filter freeze usage and year, then matching learners are fetched through the learner index. |
| R11 | Index Scan on learners_username_key | The unique username index finds the matching learner directly. |
| R12 | Index Scan on learner_achievements; Seq Scan on achievements | The learner's achievement records are found by index; the small achievements table is scanned. |
| R13 | Seq Scan on learners | The query checks learner records and referral relationships, requiring a sequential scan. |
| R14 | Seq Scan on league_memberships | The selected weeks are filtered and grouped from a sequential scan of league_memberships. |
| R15 | Seq Scan on learners; Index Scan on daily_activity | Learners are filtered by join date, with activity existence checked using the daily_activity primary-key index. |
| R16 | Index Scan on learners_username_key | The username index is used, although the case-insensitive prefix search and ordering still require work. |
| R17 | Seq Scan on lesson_attempts | Attempts are scanned, filtered by year and completion, and grouped by device. |
| R18 | Seq Scan on enrollments; Seq Scan on courses | Enrollment rows are scanned and grouped by course, with a scan of courses for titles. |
| R19 | Index Scan on units; Index Scan on lessons; Seq Scan on lesson_attempts | Correlated subqueries repeatedly access lesson_attempts for each lesson, making this the slowest read query. |
| R20 | Seq Scan on lesson_attempts | Attempts are scanned and filtered by date before daily XP aggregation and the running-total calculation. |
| R21 | Index Only Scan on daily_activity | The activity index supports date and learner lookups; grouping and the missing-day check add processing. |
| R22 | Seq Scan on lesson_attempts | The query reads and orders attempts before skipping 100,000 rows for the requested page. |
| R23 | Seq Scan on daily_activity; Seq Scan on learners | Both tables are scanned to filter the activity window, country and subscription, then count distinct learners. |
| R24 | Seq Scan on lesson_attempts; Seq Scan on lessons; Seq Scan on units | Attempts are scanned and joined to lessons and units before grouping by CEFR level. |
| R25 | Seq Scan on lesson_attempts; Seq Scan on learners | The attempts table is scanned and joined to learners before grouping by country and hour. |
| W01 | No scan reported | The insert is a direct row write; execution includes index and constraint work. |
| W02 | Index Scan on lesson_attempts_pkey | The target attempt is located through the primary-key index after the subquery selects its ID. |
| W03 | No scan reported | The upsert writes or updates the learner-date row and handles conflicts through its unique key. |
| W04 | Seq Scan on league_memberships | Weekly membership rows are scanned and ranked by cohort before the update is applied. |
| W05 | Seq Scan on achievements; Seq Scan on enrollments | Enrollments are scanned and grouped to calculate learner XP, while achievements is scanned to find the badge. |

## Key observations

- **Slowest read query:** R19, averaging **3039.674 ms**. Its correlated subqueries repeatedly access `lesson_attempts` for each lesson.
- **Slowest write query:** W05, averaging **169.760 ms**. It scans and aggregates enrollment data to identify eligible learners.
- **Fastest read query:** R11, averaging **0.530 ms**, supported by the username index.
- Sequential scans are common on the larger `lesson_attempts` table and contribute to the cost of several analytical queries.
- Some queries vary substantially between runs. The average is reported as required; the raw plans retain the details of all three runs.

## Raw benchmark plans

The full `EXPLAIN (ANALYZE, BUFFERS)` output for all three runs of each query is stored in `benchmarks/results/baseline/` (`R01.txt`–`R25.txt` and `W01.txt`–`W05.txt`).

**Note:** Scan types and observations summarize the recorded baseline plans. The benchmark workload was not modified.
