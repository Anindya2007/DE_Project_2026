# PROJECT CONTEXT — INSTAGRAM SOCIAL MEDIA DATABASE

## 1. Project Overview

Project Name: Instagram Social Media Database

Course: Database Management Systems (DBMS)

Project Repository:
https://github.com/badalkhandelwal346-ai/DE_Project_2026

Team Number: T0145

Section: A

This repository contains our Database Engineering project, which involves designing, implementing, loading, benchmarking and optimizing a PostgreSQL database representing an Instagram-like social media platform.

This document provides shared context for all AI agents and team members working on the repository.

IMPORTANT: This document provides project context, not proof of implementation. Always inspect the actual source code, SQL files, benchmark outputs and Git history before assuming a task is complete.

---

## 2. Team Information

| Name | Responsibility |
|---|---|
| Anindya Sarkar | Team Lead; database setup and implementation |
| Atharv Upadhyay | Benchmark infrastructure and execution |
| Badal Khandelwal | Baseline performance analysis and documentation |
| Anshika Srivastava | AP project ER diagram and SQL schema |

Each member must make their own genuine GitHub contribution using their own account.

---

## 3. Technology Stack

- Database: PostgreSQL
- Hosting: Neon Serverless PostgreSQL
- PostgreSQL version reported by the team: 18.7
- Database schema: instagram
- Query language: SQL
- Benchmarking: EXPLAIN (ANALYZE, BUFFERS)
- Version control: Git and GitHub

We use ONE shared PostgreSQL database for the entire team.

Do not create separate cloud databases for individual members.

Database credentials must never be committed to GitHub or written into documentation.

---

## 4. Database Overview

The database represents an Instagram-like social media platform.

It contains nine main tables:

1. users
2. follows
3. hashtags
4. posts
5. post_hashtags
6. post_media
7. likes
8. comments
9. stories

### Expected dataset

| Table | Expected rows |
|---|---:|
| users | 30,000 |
| follows | 258,588 |
| hashtags | 50 |
| posts | 60,000 |
| post_hashtags | 150,000 |
| post_media | 89,854 |
| likes | 419,954 |
| comments | 150,000 |
| stories | 40,000 |
| Total | 1,198,446 |

These are expected values. Verify actual database counts before reporting them as confirmed.

---

## 5. Current Implementation Status — Reported

The following implementation was reported by Anindya in the database setup handoff.

Latest known database setup commit:

`8cc8781`

Commit message:

`feat(de): complete PostgreSQL schema and seed data setup`

Branch: main

Reported completed files:

- sql/01_schema.sql
- sql/02_load_data.sql
- diagrams/er_diagram.png
- docs/01_problem_understanding.md
- docs/02_schema_design.md
- .gitignore
- team.json

Reported database setup:

- Neon connection verified.
- Nine tables created.
- 1,198,446 records loaded.
- ANALYZE executed.
- Primary keys, foreign keys, UNIQUE constraints and CHECK constraints created.
- All 30 workload queries reportedly passed schema compatibility testing.

IMPORTANT:

These are reported implementation details. Agents must inspect the latest repository and verify actual files and results before relying on them.

---

## 6. CP2 — Baseline Timings

CP2 focuses on measuring the current database performance before optimization.

The project contains 30 predefined SQL queries.

| Category | Query IDs | Count |
|---|---|---:|
| READ | R01–R24 | 24 |
| WRITE | W01–W06 | 6 |
| Total | | 30 |

The workload is located at:

`queries/workload_30.sql`

The benchmark script is located at:

`benchmarks/run_benchmark.sh`

### Benchmark requirements

Each query must be executed three times.

Use:

`EXPLAIN (ANALYZE, BUFFERS)`

Collect:

- Three execution times.
- Average execution time.
- Median execution time.
- Minimum execution time.
- Maximum execution time.
- Scan types.
- Actual execution plans.

Write queries must be executed inside transactions and rolled back.

Expected output:

`benchmarks/results/baseline/`

Required files:

- summary.csv
- R01.txt through R24.txt
- W01.txt through W06.txt

Never fabricate benchmark values.

An EXPLAIN compatibility test is not equivalent to an official EXPLAIN ANALYZE benchmark.

---

## 7. CP2 Deliverables

### DE Repository

Required deliverables:

- docs/03_baseline_timings.md
- benchmarks/results/baseline/summary.csv
- 30 individual execution-plan files.

### AP Repository

Separate AP project deliverables:

- dbms/02_er_diagram.png
- dbms/03_schema.sql

The AP database design must be based on the actual AP application, not the Instagram database.

---

## 8. Known Areas Requiring Investigation

Two observations were reported during database setup.

### A. Follower count drift

Approximately 1,200 users reportedly have follower counts that differ from actual records in the follows table.

W04 is intended to reconcile these counts.

### B. R13 NULL behavior

R13 reportedly returns zero rows due to SQL three-valued logic involving NOT IN and NULL values in parent_comment_id.

Both observations require verification against the actual SQL workload and database.

Do not modify the original queries during CP2.

These issues may be investigated during CP3.

---

## 9. CP3 — Optimization Phase

CP3 is separate from CP2.

Potential future activities:

- Index creation.
- Query rewriting.
- Join optimization.
- Aggregation improvements.
- Performance comparison against CP2 baseline.

Do not implement CP3 optimizations during CP2.

The CP2 baseline must represent the original database configuration.

---

## 10. GitHub Working Rules

Repository:

https://github.com/badalkhandelwal346-ai/DE_Project_2026

Default working branch: main.

Rules:

1. Always inspect Git status before modifying files.
2. Pull the latest changes before starting.
3. Never overwrite another member's work.
4. Never force-push.
5. Never reset the shared branch.
6. Commit only files owned by the assigned member.
7. Use individual GitHub accounts.
8. Do not commit database credentials.
9. Do not commit raw seed datasets.
10. Verify successful pushes.

Suggested commit messages:

Anindya:
`feat(de): complete PostgreSQL schema and seed data setup`

Atharv:
`feat(de): add CP2 baseline benchmark results`

Badal:
`docs(de): add CP2 baseline performance report`

Anshika:
`feat(ap): add CP2 ER diagram and PostgreSQL schema`

---

## 11. AI Agent Instructions

Every AI agent working on this project must:

1. Read this entire CONTEXT.md file.
2. Read README.md and CHECKPOINTS.md.
3. Inspect the actual GitHub repository.
4. Inspect the existing implementation before modifying anything.
5. Identify completed, incomplete and blocked requirements.
6. Work only on the assigned task.
7. Preserve existing project architecture and conventions.
8. Never invent data, timings, relationships or implementation results.
9. Validate all generated deliverables.
10. Commit and push only the assigned contribution.
11. Provide an honest final implementation report.

Do not assume that a task is complete merely because this document says it was reported as complete.

The actual repository and validated execution results are the source of truth.

---

## 12. Current Team Execution Order

1. Anindya — Database setup and data loading. Reported completed and pushed.
2. Badal — Baseline documentation and performance analysis.
3. Atharv — Benchmark infrastructure and official benchmark execution.
4. Anshika — AP ER diagram and SQL schema.

Badal may prepare documentation before benchmark execution, but must use actual benchmark outputs for final analysis.

Atharv must use the shared PostgreSQL database and execute the official benchmark.

The team must coordinate GitHub pushes to avoid conflicts.

---

END OF PROJECT CONTEXT