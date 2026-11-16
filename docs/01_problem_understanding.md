# 01. Problem Understanding

**Project:** Duolingo Language Learning Database
**Course:** Database Management Systems (DBMS)
**Team Number:** T0097
**Database:** PostgreSQL 15 or newer

---

## 1. Business Context

Duolingo teaches languages through courses, units and short lessons. Learners enroll in courses, attempt lessons and earn XP, while daily practice keeps their streak alive. Weekly leagues, referrals and achievements keep learners engaged.

The existing database was built quickly without documentation, and only data exports are available. The goal of this project is to rebuild a well-constrained schema, measure the performance of the 30 workload queries, optimize them without changing their results, and prove that the database can handle 20 times the current activity.

## 2. Identified Business Problems

| ID | Business Requirement | Affected Stakeholders | Problem Classification |
|----|----------------------|-----------------------|------------------------|
| **P1 – Slow Home Screen** (R01–R04, R06) | The screen shown when a learner opens the app (course path, XP, daily-goal ring, streak counter and "Start" button) must load instantly so learners can continue without waiting. | Learner | Customer-facing / Real-time |
| **P2 – Slow Leagues** (R05, R14, W04) | The weekly leaderboard must open quickly, and the weekly league close (ranking everyone and setting promoted, demoted or stayed) must finish efficiently. | Gamification / Leagues Team, Learner | Customer-facing / Real-time (R05); R14 is reporting and W04 is a batch job |
| **P3 – Slow Lesson Actions** (W01–W03) | Starting a lesson, finishing it and adding to the day's XP happen in the middle of learning, so they must feel immediate. | Learner | Customer-facing / Real-time |
| **P4 – Curriculum Reporting** (R07, R08, R19, R24) | The curriculum team needs to find lessons with many mistakes, see quit rates and hearts lost, and review completions per lesson to judge the content. | Curriculum Team | Reporting / Analytics |
| **P5 – Empty Referral List** (R13) | The list of learners who have never referred anyone comes back empty even though such learners exist. This is a wrong-result (correctness) bug, not a speed problem, and it must be fixed so the programme reaches its audience. | Growth Team | Reporting / Analytics |
| **P6 – Slow Growth and Retention Dashboards** (R09, R15, R18, R20, R21, R25) | Dashboards for daily active learners, cohort retention, course popularity, XP trends, streak-reminder audiences and lesson starts by hour and country currently time out. | Growth & Retention Team, Notifications Team | Reporting / Analytics |
| **P7 – Slow Platform Tools and 20× Growth** (R10–R12, R16, R17, R22, R23, W05) | Sign-in, friend search, achievements and the support console's attempt lookup must stay responsive. Subscription and activity analysis must work, and the database must cope with 20× more activity. | Learner, Monetisation (Super/Max), Support | Customer-facing / Real-time (R11, R12, R16, R22); R10, R17 and R23 are reporting and W05 is a batch job |

## 3. Assumptions

1. **Real-time queries:** Queries where a user waits for the result during use (home screen, leaderboard, lesson start and finish, sign-in, friend search, support lookup) are treated as time-sensitive.

2. **Reporting queries:** Aggregate, historical or audience-list queries run by internal teams (curriculum reports, retention, course popularity, XP trends, streak-reminder lists) are treated as analytics workloads.

3. **Mixed problems:** P2 and P7 contain a few reporting queries and batch jobs. The main label shows the user-facing use, and the exceptions are named in the table.

4. **Fixed dates:** The seed data ends on 30 June 2026, so "today" in the queries is fixed at that date.

5. **Targets:** Exact performance targets follow the query groups given in the project brief and are applied in the later phases.

6. **Growth and correctness:** The 20× growth in P7 is a capacity expectation tested in Phase 5. Results must stay the same after optimization, except R13, whose current result is wrong and will be corrected.

## 4. Conclusion

The Duolingo database must support fast learner-facing operations and reliable reporting for internal teams. Four problems (P1, P2, P3, P7) are mainly customer-facing and need the strictest response times. Three (P4, P5, P6) are reporting workloads that can run longer. P5 is a correctness issue, so R13 must be fixed rather than only sped up.

This understanding guides the schema reconstruction, data loading, baseline benchmarking, query optimization and scalability testing in the upcoming phases.
