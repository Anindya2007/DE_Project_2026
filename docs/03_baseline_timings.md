# Phase 3 / CP2: Baseline Timings & Performance Analysis

**Project Name:** Instagram Social Media Database  
**Course:** Database Management Systems (DBMS)  
**Team Number:** T0145 · **Section:** A  
**Author:** Badal Khandelwal (`badalkhandelwal346-ai`) — Performance Analysis & Documentation  
**Team Members:** Anindya Sarkar (Lead), Atharv Upadhyay, Anshika Srivastava  
**Target Database:** PostgreSQL 15+ (Reported Neon Serverless PostgreSQL 18.7)  
**Schema:** `instagram`  
**Checkpoint Due Date:** Tuesday 17 November 2026, 11:59 PM  

---

## 1. Project Overview & CP2 Objectives

### 1.1 Context & Scope
The Instagram Social Media Database is a high-throughput relational data platform modeling the core operational mechanics of Instagram. The architecture captures user identity, asymmetric social graphs, rich media publication (photos, videos, multi-item carousels, reels), hashtags, temporary ephemeral 24-hour stories, hierarchical threaded conversations, and high-velocity engagement interactions (likes).

Following Phase 1 (Problem Understanding in `docs/01_problem_understanding.md`) and Phase 2 (Relational Schema Design & Normalization in `docs/02_schema_design.md`), the objective of **Checkpoint 2 (CP2)** is to establish an un-optimized, mathematically rigorous **performance baseline** across 30 predefined operational queries (`queries/workload_30.sql`).

### 1.2 Database Architecture & Dataset Scale
The database consists of nine core normalized tables residing in the dedicated `instagram` schema. At baseline (Phase 2 / CP1), only candidate keys (`PRIMARY KEY`, `UNIQUE`) and structural constraints (`FOREIGN KEY`, `CHECK`) are implemented. **No secondary performance indexes have been created.**

```
+-------------------------------------------------------------------------+
|                       DATABASE ENTITY RECORD SUMMARY                    |
+-------------------+-----------------+-----------------------------------+
| Table Name        | Total Records   | Storage & Entity Role             |
+-------------------+-----------------+-----------------------------------+
| users             |          30,000 | Core user accounts & counters     |
| follows           |         258,588 | Asymmetric social graph edges     |
| hashtags          |              50 | Unique taxonomy keywords          |
| posts             |          60,000 | Published feed media publications |
| post_hashtags     |         150,000 | M:N post-to-hashtag mappings      |
| post_media        |          89,854 | Physical image/video asset items  |
| likes             |         419,954 | User-to-post engagement records   |
| comments          |         150,000 | Threaded hierarchical comments    |
| stories           |          40,000 | Ephemeral 24-hour video/images    |
+-------------------+-----------------+-----------------------------------+
| Total Baseline    |       1,198,446 | Total Relational Tuples           |
+-------------------+-----------------+-----------------------------------+
```

### 1.3 Workload Composition
The standardized workload comprises **30 SQL queries**:
- **24 Read Queries (`R01` – `R24`):** Covering real-time feed assembly, explore algorithms, prefix search, social graph traversals, and creator analytics aggregations.
- **6 Write Queries (`W01` – `W06`):** Covering single-row inserts, counter synchronizations, bulk status updates, cascading deletions, and whole-table batch reconciliations.

---

## 2. Benchmark Methodology

To ensure consistency, reproducibility, and compliance with academic evaluation standards, all baseline measurements are governed by strict execution protocols executed via `benchmarks/run_benchmark.sh`.

### 2.1 Execution Instrumentation: `EXPLAIN (ANALYZE, BUFFERS)`
PostgreSQL's built-in query profiler is invoked using:
```sql
SET search_path TO instagram;
EXPLAIN (ANALYZE, BUFFERS) <query>;
```
- **`EXPLAIN`:** Generates the query execution tree (cost estimates, planned scan methods, join strategies).
- **`ANALYZE`:** Executes the query to completion, reporting true wall-clock execution time (`Execution Time` in ms), actual row counts per node, and loop iterations.
- **`BUFFERS`:** Quantifies memory hierarchy activity across shared buffer pool cache hits (`shared hit`), disk reads (`shared read`), dirtied pages (`shared dirtied`), and written blocks (`shared written`).

### 2.2 Multi-Run Protocol & Statistical Aggregation
Every individual query is executed **3 consecutive times** under identical runtime conditions:
1. **Run 1 (Cold / Semi-Warm Cache):** Measures latency when table pages may need to be paged into PostgreSQL shared buffers.
2. **Run 2 (Warm Cache):** Measures hot in-memory execution.
3. **Run 3 (Warm Cache):** Confirms measurement stability.

The reported metrics include:
$$\text{Average Execution Time} = \frac{T_1 + T_2 + T_3}{3}$$
$$\text{Median Execution Time} = \text{middle value of sorted } (T_1, T_2, T_3)$$
$$\text{Min Execution Time} = \min(T_1, T_2, T_3), \quad \text{Max Execution Time} = \max(T_1, T_2, T_3)$$

### 2.3 Transaction Isolation for Write Queries
All write operations (`W01` – `W06`) are strictly encapsulated within transaction blocks:
```sql
SET search_path TO instagram;
BEGIN;
EXPLAIN (ANALYZE, BUFFERS) <write_dml_statement>;
ROLLBACK;
```
This guarantees that **zero data mutation occurs**, maintaining identical dataset state (1,198,446 rows) across all 3 runs and subsequent queries.

---

## 3. Workload Mapping to Production Problem Statements (P1–P9)

In Phase 1 (`docs/01_problem_understanding.md`), nine production bottlenecks were identified. The 30 benchmark queries map directly to these business problems:

| Problem ID | Business Problem Description | Stakeholder Group | Target Latency Tier | Associated Queries |
|---|---|---|---|---|
| **P1** | Slow Home Feed & Profile Grid for high-following accounts | End Users, Feed Team | Real-Time (< 5 ms) | `R01`, `R02`, `R03` |
| **P2** | Slow Viral Post Pages (comments, reply counts, like state) | Consumers, Post Team | Real-Time (< 5 ms) | `R04`, `R07`, `R23`, `W02`, `W03` |
| **P3** | Explore & Search Type-Ahead Latency | Discovery & Search Team | Interactive (< 250 ms) | `R05`, `R06`, `R12`, `R16` |
| **P4** | Lag in Friend Suggestions & Pending Follow Requests | Social Graph Team | Interactive (< 250 ms) | `R08`, `R09`, `W06` |
| **P5** | Creator Insights & Audience Analytics Bottlenecks | Creator Ecosystem | Reporting (< 5,000 ms) | `R11`, `R14`, `R17`, `R21` |
| **P6** | Creator Tool "Comments Without Replies" returns 0 rows | Creators, Community Team | Bug / Interactive (< 500 ms) | `R13` |
| **P7** | Profile Counters Drift & Nightly Recount Bottleneck | Data Quality Team | Batch Job (< 30,000 ms) | `R15`, `W04` |
| **P8** | Ephemeral Stories Clean-up & Moderation Queue Latency | Trust & Safety, Stories | Real-Time & Batch | `R10`, `R22`, `R24`, `W05` |
| **P9** | Content Analytics Timeouts & 20x Scale Resilience | Executive Analytics | Analytics Tier (< 10,000 ms)| `R18`, `R19`, `R20`, `W01` |

---

## 4. Comprehensive Architectural Analysis of All 30 Queries

Below is the exhaustive, query-by-query analysis of the 30 workload statements from `queries/workload_30.sql`.

---

### R01 — Home Feed (Followed Accounts Recent Posts)
- **Category:** READ
- **Purpose:** Assemble the home feed for user `1042` by retrieving the latest 30 active posts from accounts they follow.
- **Tables Involved:** `follows f`, `posts p`
- **Join Operations:** `INNER JOIN posts p ON p.user_id = f.followee_id`
- **Filtering (`WHERE`):** `f.follower_id = 1042 AND f.status = 'ACCEPTED' AND NOT p.is_archived`
- **Sorting & Slicing:** `ORDER BY p.created_at DESC LIMIT 30`
- **Expected Execution Behaviour:** `follows` can use `follows_pkey` on `(follower_id, followee_id)` to filter `follower_id = 1042`. However, joining to `posts` on `user_id` has no supporting index on `posts(user_id)`. The planner will either perform a Nested Loop with sequential scans on `posts` or a Hash Join scanning all 60,000 rows of `posts`, followed by an expensive Top-N Sort on `p.created_at DESC`.
- **CP3 Optimization Potential:** Composite index on `posts(user_id, created_at DESC)` to eliminate post sequential scans and avoid sorting.

---

### R02 — Profile Grid (User Recent Posts)
- **Category:** READ
- **Purpose:** Display the profile grid for user `217` showing their 12 most recent non-archived posts.
- **Tables Involved:** `posts`
- **Join Operations:** None (Single-table query)
- **Filtering (`WHERE`):** `user_id = 217 AND NOT is_archived`
- **Sorting & Slicing:** `ORDER BY created_at DESC LIMIT 12`
- **Expected Execution Behaviour:** In the absence of an index on `posts.user_id`, PostgreSQL must perform a full `Seq Scan on posts` (60,000 rows), filter matching user records in memory, and sort by `created_at DESC`.
- **CP3 Optimization Potential:** Composite index on `posts(user_id, created_at DESC) WHERE NOT is_archived`.

---

### R03 — Profile Header Lookup
- **Category:** READ
- **Purpose:** Retrieve user profile header details by unique handle (`karan_singh217`).
- **Tables Involved:** `users`
- **Join Operations:** None
- **Filtering (`WHERE`):** `username = 'karan_singh217'`
- **Sorting & Slicing:** None
- **Expected Execution Behaviour:** Utilizes the unique constraint B-tree index `uq_users_username` via an `Index Scan` or `Index Only Scan`. Extremely fast single-row tuple fetch.
- **CP3 Optimization Potential:** Already optimal at single-row point lookup; potential covering index if hot columns are frequently projected.

---

### R04 — Post Page Comments & Reply Counts
- **Category:** READ
- **Purpose:** Fetch top-level comments on post `59689` and calculate the number of replies each comment has received.
- **Tables Involved:** `comments c`, `comments r` (self-join)
- **Join Operations:** `LEFT JOIN comments r ON r.parent_comment_id = c.comment_id`
- **Filtering (`WHERE`):** `c.post_id = 59689 AND c.parent_comment_id IS NULL AND NOT c.is_hidden`
- **Grouping & Sorting:** `GROUP BY c.comment_id, c.user_id, c.body, c.created_at ORDER BY c.created_at`
- **Expected Execution Behaviour:** `comments` has only `comments_pkey (comment_id)`. Filtering by `post_id = 59689` requires a full sequential scan on 150,000 comments. The self-join on `r.parent_comment_id = c.comment_id` requires scanning comments again. A HashAggregate or GroupAggregate computes counts.
- **CP3 Optimization Potential:** Foreign key index on `comments(post_id)` and secondary index on `comments(parent_comment_id)`.

---

### R05 — Explore Feed (#travel June 2026)
- **Category:** READ
- **Purpose:** Identify the top 30 most-liked posts tagged `#travel` published on or after June 1, 2026.
- **Tables Involved:** `hashtags h`, `post_hashtags ph`, `posts p`
- **Join Operations:** `JOIN post_hashtags ph ON ph.hashtag_id = h.hashtag_id JOIN posts p ON p.post_id = ph.post_id`
- **Filtering (`WHERE`):** `h.tag = 'travel' AND p.created_at >= '2026-06-01'`
- **Sorting & Slicing:** `ORDER BY p.like_count DESC LIMIT 30`
- **Expected Execution Behaviour:** `h.tag` uses `uq_hashtags_tag` (1 row). However, `post_hashtags` has PK `(post_id, hashtag_id)`; searching by `hashtag_id` without leading column forces a full scan of 150,000 rows in `post_hashtags`. Then joins 60,000 rows of `posts`, filters by `created_at`, and sorts by `like_count DESC`.
- **CP3 Optimization Potential:** Reverse composite index on `post_hashtags(hashtag_id, post_id)` and index on `posts(created_at, like_count)`.

---

### R06 — Account Search Bar (Prefix & Substring)
- **Category:** READ
- **Purpose:** Search accounts by handle prefix (`karan%`) or name substring (`%karan sharma%`), ordered by verification status and followers.
- **Tables Involved:** `users`
- **Join Operations:** None
- **Filtering (`WHERE`):** `username ILIKE 'karan%' OR full_name ILIKE '%karan sharma%'`
- **Sorting & Slicing:** `ORDER BY is_verified DESC, followers_count DESC LIMIT 20`
- **Expected Execution Behaviour:** Standard B-tree indexes cannot service leading wildcard queries (`%karan sharma%`) or case-insensitive pattern matching (`ILIKE`) without special operator classes. Triggers a full `Seq Scan on users` (30,000 rows) with in-memory filter and sort.
- **CP3 Optimization Potential:** Trigram index (`pg_trgm`) via GIN or expression index on `lower(username) varchar_pattern_ops`.

---

### R07 — "Liked By" List with Social Graph Context
- **Category:** READ
- **Purpose:** Retrieve all users who liked post `59689` and check if current user `1042` follows each liker.
- **Tables Involved:** `likes l`, `users u`, `follows f`
- **Join Operations:** `JOIN users u ON u.user_id = l.user_id LEFT JOIN follows f ON f.follower_id = 1042 AND f.followee_id = l.user_id AND f.status = 'ACCEPTED'`
- **Filtering (`WHERE`):** `l.post_id = 59689`
- **Sorting:** `ORDER BY you_follow DESC, l.created_at DESC`
- **Expected Execution Behaviour:** `likes` table has PK `(user_id, post_id)`. Filtering by `post_id = 59689` cannot utilize the composite PK index as `post_id` is the trailing column. Forces a full `Seq Scan on likes` (419,954 rows).
- **CP3 Optimization Potential:** Secondary index on `likes(post_id, user_id)`.

---

### R08 — "Suggested for You" (Friends-of-Friends Traversal)
- **Category:** READ
- **Purpose:** Recommend 2nd-degree social graph connections (friends of friends) of user `1042` whom `1042` does not currently follow.
- **Tables Involved:** `follows f1`, `follows f2`, `follows x` (anti-join subquery)
- **Join Operations:** Self-join `f1 JOIN f2 ON f2.follower_id = f1.followee_id`
- **Filtering (`WHERE`):** `f1.follower_id = 1042 AND f1.status = 'ACCEPTED' AND f2.followee_id <> 1042 AND NOT EXISTS (...)`
- **Grouping & Sorting:** `GROUP BY f2.followee_id ORDER BY mutual_connections DESC, suggested_user LIMIT 20`
- **Expected Execution Behaviour:** `f1` filters `follower_id = 1042` via PK. `f2` looks up by `f2.follower_id` using PK. However, the anti-join `NOT EXISTS` subquery checks `follows x` for each candidate edge. Grouping and ordering adds hash aggregation and sort overhead.
- **CP3 Optimization Potential:** Index on `follows(followee_id, follower_id)` for reverse edge lookups; optimized join formulation.

---

### R09 — Pending Follow Requests Screen
- **Category:** READ
- **Purpose:** Retrieve all pending follow requests directed to private user `338`, newest first.
- **Tables Involved:** `follows f`, `users u`
- **Join Operations:** `INNER JOIN users u ON u.user_id = f.follower_id`
- **Filtering (`WHERE`):** `f.followee_id = 338 AND f.status = 'PENDING'`
- **Sorting:** `ORDER BY f.created_at DESC`
- **Expected Execution Behaviour:** `follows` PK is `(follower_id, followee_id)`. Because `followee_id` is the second column, PostgreSQL cannot perform an index range scan on `followee_id = 338`. Triggers a full sequential scan on 258,588 follow edges.
- **CP3 Optimization Potential:** Composite index on `follows(followee_id, status) INCLUDE (created_at)`.

---

### R10 — Story Highlights Feed
- **Category:** READ
- **Purpose:** Display June 2026 stories published by accounts followed by user `1042`.
- **Tables Involved:** `stories s`, `follows f`
- **Join Operations:** `INNER JOIN follows f ON f.followee_id = s.user_id`
- **Filtering (`WHERE`):** `f.follower_id = 1042 AND f.status = 'ACCEPTED' AND DATE(s.created_at) BETWEEN '2026-06-01' AND '2026-06-30'`
- **Sorting:** `ORDER BY s.created_at DESC`
- **Expected Execution Behaviour:** `follows` uses PK on `follower_id = 1042`. But `stories` has no index on `user_id` or `created_at`. In addition, wrapping `created_at` in `DATE()` prevents standard range index utilization. Requires full sequential scan on 40,000 stories.
- **CP3 Optimization Potential:** Index on `stories(user_id, created_at)` and rewrite filter to sargable range (`s.created_at >= '2026-06-01' AND s.created_at < '2026-07-01'`).

---

### R11 — Creator Engagement Rate Leaderboard
- **Category:** READ
- **Purpose:** Compute engagement per follower for CREATOR accounts in 2026 with at least 20 followers.
- **Tables Involved:** `users u`, `posts p`
- **Join Operations:** `INNER JOIN posts p ON p.user_id = u.user_id`
- **Filtering (`WHERE`):** `u.account_type = 'CREATOR' AND p.created_at >= '2026-01-01'`
- **Grouping & Slicing:** `GROUP BY ... HAVING u.followers_count >= 20 ORDER BY engagement_per_follower DESC LIMIT 20`
- **Expected Execution Behaviour:** Heavy hash join scanning 30,000 `users` and 60,000 `posts`. Performs aggregation on all matched creator posts followed by floating point division and sort.
- **CP3 Optimization Potential:** Index on `users(account_type, followers_count)` and `posts(user_id, created_at)`.

---

### R12 — Trending Hashtags (Last 7 Days)
- **Category:** READ
- **Purpose:** Aggregate top 10 trending hashtags used in posts during the final week of June 2026.
- **Tables Involved:** `post_hashtags ph`, `hashtags h`, `posts p`
- **Join Operations:** 3-way join across `post_hashtags`, `hashtags`, and `posts`
- **Filtering (`WHERE`):** `p.created_at >= '2026-06-24'`
- **Grouping & Sorting:** `GROUP BY h.tag ORDER BY posts DESC LIMIT 10`
- **Expected Execution Behaviour:** Scans 60,000 posts for date filter, joins with 150,000 `post_hashtags` and 50 `hashtags`. Substantial hash aggregation and sort.
- **CP3 Optimization Potential:** Composite index on `posts(created_at, post_id)` and covering index on `post_hashtags`.

---

### R13 — Unanswered Comments (Zero Replies)
- **Category:** READ
- **Purpose:** Identify comments on post `59689` that have received no replies.
- **Tables Involved:** `comments c`, `comments r` (subquery)
- **Filtering (`WHERE`):** `c.post_id = 59689 AND c.comment_id NOT IN (SELECT r.parent_comment_id FROM comments r)`
- **Expected Execution Behaviour:** **Known Three-Valued Logic Pitfall:** The subquery `SELECT r.parent_comment_id FROM comments r` returns rows containing `NULL` (top-level comments). In SQL, `value NOT IN (..., NULL)` evaluates to `UNKNOWN`, causing the condition to reject all candidate rows. Under baseline, this query returns 0 rows while performing a full sequential scan on `comments` (150,000 rows).
- **CP3 Optimization Potential:** Rewrite using `NOT EXISTS` or `LEFT JOIN ... WHERE r.comment_id IS NULL`, and add index on `comments(post_id)` and `comments(parent_comment_id)`.

---

### R14 — Accounts Not Following Back
- **Category:** READ
- **Purpose:** Find users who follow user `217`, but user `217` does not follow back.
- **Tables Involved:** `follows f`, `follows b` (anti-join)
- **Filtering (`WHERE`):** `f.followee_id = 217 AND f.status = 'ACCEPTED' AND NOT EXISTS (SELECT 1 FROM follows b WHERE b.follower_id = 217 AND b.followee_id = f.follower_id)`
- **Sorting:** `ORDER BY f.follower_id`
- **Expected Execution Behaviour:** `f.followee_id = 217` cannot use `follows_pkey (follower_id, followee_id)`. Forces full scan on 258,588 rows of `follows`. Subquery probes `follows` for each match.
- **CP3 Optimization Potential:** Reverse composite index on `follows(followee_id, follower_id)`.

---

### R15 — Follower Counter Integrity Audit
- **Category:** READ
- **Purpose:** Detect data quality drift by comparing stored `users.followers_count` against live counted records in `follows` for verified/creator accounts.
- **Tables Involved:** `users u`, `follows f`
- **Join Operations:** `LEFT JOIN follows f ON f.followee_id = u.user_id AND f.status = 'ACCEPTED'`
- **Filtering (`WHERE`):** `u.is_verified OR u.account_type = 'CREATOR'`
- **Grouping & Having:** `GROUP BY u.user_id ... HAVING u.followers_count <> count(f.follower_id)`
- **Expected Execution Behaviour:** Scans all verified/creator users, hash joins with full `follows` table (258,588 rows) on unindexed `f.followee_id`, groups across all users, and filters discrepancies. High CPU and buffer footprint.
- **CP3 Optimization Potential:** Index on `follows(followee_id, status)` and partial index on `users(user_id) WHERE is_verified OR account_type = 'CREATOR'`.

---

### R16 — Places Search (Goa June 2026)
- **Category:** READ
- **Purpose:** Retrieve posts tagged with location containing "goa" published in June 2026, ordered by likes.
- **Tables Involved:** `posts`
- **Filtering (`WHERE`):** `location_name ILIKE '%goa%' AND created_at >= '2026-06-01' AND created_at < '2026-07-01'`
- **Sorting:** `ORDER BY like_count DESC`
- **Expected Execution Behaviour:** Full sequential scan of 60,000 rows in `posts`. Double-wildcard string pattern (`%goa%`) bypasses standard B-tree indexes.
- **CP3 Optimization Potential:** Trigram GIN index on `location_name` (`gin (location_name gin_trgm_ops)`) combined with date filtering index.

---

### R17 — Long Reels by Creators (> 60s)
- **Category:** READ
- **Purpose:** Find creators' reels longer than 60 seconds posted in 2026, sorted by popularity.
- **Tables Involved:** `posts p`, `post_media pm`, `users u`
- **Join Operations:** Join `p` with `pm` on `(post_id, position=1)` and with `u` on `user_id`
- **Filtering (`WHERE`):** `p.post_type = 'REEL' AND pm.duration_sec > 60 AND u.account_type = 'CREATOR' AND EXTRACT(YEAR FROM p.created_at) = 2026`
- **Sorting & Slicing:** `ORDER BY p.like_count DESC LIMIT 50`
- **Expected Execution Behaviour:** 3-table join involving unindexed foreign keys on `posts.user_id`. `EXTRACT(YEAR FROM created_at)` disables range index on date. Sequential scans across `posts` and `users`.
- **CP3 Optimization Potential:** Composite indexes on `posts(post_type, created_at, user_id)` and `post_media(post_id, position, duration_sec)`.

---

### R18 — Content Analytics: Daily Post Volume
- **Category:** READ
- **Purpose:** Aggregate daily post counts grouped by post type (`PHOTO`, `VIDEO`, etc.) for June 2026.
- **Tables Involved:** `posts`
- **Filtering (`WHERE`):** `created_at::date BETWEEN '2026-06-01' AND '2026-06-30'`
- **Grouping & Sorting:** `GROUP BY 1, 2 ORDER BY 1, 2`
- **Expected Execution Behaviour:** Type-cast `created_at::date` triggers full sequential scan on 60,000 rows of `posts`, followed by HashAggregate and sort.
- **CP3 Optimization Potential:** Sargable timestamp range filtering (`created_at >= ... AND created_at < ...`) paired with index on `posts(created_at, post_type)`.

---

### R19 — Verified Accounts Lifetime Engagement Report
- **Category:** READ
- **Purpose:** For every verified user, retrieve their most recent post timestamp and total lifetime likes received.
- **Tables Involved:** `users u`, `posts p`, `likes l`
- **Query Structure:** Two correlated subqueries in `SELECT` list:
  1. `(SELECT max(p.created_at) FROM posts p WHERE p.user_id = u.user_id)`
  2. `(SELECT count(*) FROM likes l JOIN posts p ON p.post_id = l.post_id WHERE p.user_id = u.user_id)`
- **Filtering (`WHERE`):** `u.is_verified`
- **Sorting:** `ORDER BY likes_received DESC`
- **Expected Execution Behaviour:** **Severe Architectural Bottleneck:** Correlated subqueries execute once for every single verified account in `users`. The second subquery performs a join between `likes` (419,954 rows) and `posts` (60,000 rows) repeatedly. Expected to be among the slowest queries in the workload.
- **CP3 Optimization Potential:** Rewrite correlated subqueries into set-based `LEFT JOIN` aggregations with pre-aggregated CTEs; create indexes on `posts(user_id)` and `likes(post_id)`.

---

### R20 — Top 10 Most Commented Posts (June 2026)
- **Category:** READ
- **Purpose:** Rank the 10 most commented posts published in June 2026.
- **Tables Involved:** `comments c`, `posts p`
- **Join Operations:** `INNER JOIN posts p ON p.post_id = c.post_id`
- **Filtering (`WHERE`):** `p.created_at >= '2026-06-01'`
- **Grouping & Slicing:** `GROUP BY c.post_id ORDER BY comments DESC LIMIT 10`
- **Expected Execution Behaviour:** Filters `posts` by date (seq scan on 60,000 rows), joins with `comments` (seq scan on 150,000 rows on unindexed `c.post_id`), followed by HashAggregate across all post IDs and Top-10 Sort.
- **CP3 Optimization Potential:** Index on `posts(created_at, post_id)` and foreign key index on `comments(post_id)`.

---

### R21 — Creator Ghost Followers
- **Category:** READ
- **Purpose:** Identify followers of user `217` who have never liked any of user 217's posts.
- **Tables Involved:** `follows f`, `likes l`, `posts p`
- **Join / Subquery:** Anti-join via `NOT EXISTS (SELECT 1 FROM likes l JOIN posts p ON p.post_id = l.post_id WHERE l.user_id = f.follower_id AND p.user_id = 217)`
- **Filtering (`WHERE`):** `f.followee_id = 217 AND f.status = 'ACCEPTED'`
- **Sorting:** `ORDER BY f.follower_id`
- **Expected Execution Behaviour:** Full sequential scan on `follows` (258,588 rows) for `followee_id = 217`. For each candidate follower, evaluates the subquery joining `likes` (420k rows) and `posts` (60k rows) without indexes on `posts.user_id` or `likes.post_id`. Highly resource-intensive.
- **CP3 Optimization Potential:** Reverse index on `follows(followee_id, follower_id)` and composite index on `posts(user_id, post_id)` and `likes(user_id, post_id)`.

---

### R22 — Moderation Console (Paginated Hidden Comments)
- **Category:** READ
- **Purpose:** Paginate hidden comments for trust & safety moderation (Page 61, 25 items per page).
- **Tables Involved:** `comments`
- **Filtering (`WHERE`):** `is_hidden` (boolean)
- **Sorting & Paging:** `ORDER BY created_at DESC OFFSET 1500 LIMIT 25`
- **Expected Execution Behaviour:** Sequential scan over 150,000 comments filtering `is_hidden = TRUE`. Gathers all matching records into memory, sorts by `created_at DESC`, skips 1,500 rows, and emits 25.
- **CP3 Optimization Potential:** Partial index on `comments(created_at DESC) WHERE is_hidden`.

---

### R23 — Like Button State Lookup
- **Category:** READ
- **Purpose:** Check if user `1042` has liked post `59689` to render UI heart button state.
- **Tables Involved:** `likes`
- **Structure:** `SELECT EXISTS (SELECT 1 FROM likes WHERE user_id = 1042 AND post_id = 59689) AS liked;`
- **Expected Execution Behaviour:** Exceptional efficiency. Because `likes` has a composite primary key on `(user_id, post_id)`, both leading and trailing keys are supplied with equality. Executes via `Index Only Scan` on `likes_pkey`. Target latency < 1 ms.
- **CP3 Optimization Potential:** Already optimal.

---

### R24 — Story Views Analytics (Top 20 Accounts)
- **Category:** READ
- **Purpose:** Calculate total story impressions and publication count per user in June 2026.
- **Tables Involved:** `stories`
- **Filtering (`WHERE`):** `created_at >= '2026-06-01'`
- **Grouping & Slicing:** `GROUP BY user_id ORDER BY views DESC LIMIT 20`
- **Expected Execution Behaviour:** Full sequential scan of 40,000 stories filtering `created_at`. In-memory HashAggregate on `user_id` followed by Top-20 Sort.
- **CP3 Optimization Potential:** Composite index on `stories(created_at, user_id, view_count)`.

---

### W01 — Publish New Photo Post
- **Category:** WRITE
- **Purpose:** User `1042` publishes a new photo post.
- **Target Table:** `posts`
- **Operation:** `INSERT INTO posts (...) VALUES (90000001, 1042, 'PHOTO', ...)`
- **Constraint Checks:** Evaluates `posts_pkey`, FK `fk_posts_user` (scans/probes `users`), and CHECK constraints `chk_posts_post_type`, `chk_posts_like_count`, `chk_posts_comment_count`.
- **Expected Execution Behaviour:** Single-row insertion into heap table followed by B-tree index update on `posts_pkey`. Fast (< 5 ms).
- **CP3 Optimization Potential:** Minimal. Unindexed tables actually benefit insert speed; adding future indexes will require evaluating index write-amplification overhead.

---

### W02 — Double-Tap Like Action
- **Category:** WRITE
- **Purpose:** User `1042` likes post `59689` with conflict idempotency.
- **Target Table:** `likes`
- **Operation:** `INSERT INTO likes (...) VALUES (...) ON CONFLICT (user_id, post_id) DO NOTHING;`
- **Constraint Checks:** Evaluates `likes_pkey`, FK `fk_likes_user`, FK `fk_likes_post`.
- **Expected Execution Behaviour:** Checks `likes_pkey` B-tree index for uniqueness conflict. Inserts tuple if absent. Fast single-row write.

---

### W03 — Post Like Counter Incremental Update
- **Category:** WRITE
- **Purpose:** Increment cached `like_count` on post `59689`.
- **Target Table:** `posts`
- **Operation:** `UPDATE posts SET like_count = like_count + 1 WHERE post_id = 59689;`
- **Expected Execution Behaviour:** `post_id = 59689` utilizes `posts_pkey` via an `Index Scan`. Fetches single row, writes updated tuple to table heap, and marks previous tuple dead.
- **CP3 Optimization Potential:** Near-optimal point update.

---

### W04 — Nightly Batch Follower Count Reconciliation
- **Category:** WRITE
- **Purpose:** Reconcile drifted `followers_count` values across all users against live records in `follows`.
- **Target Table:** `users u`
- **Operation:** Multi-table `UPDATE ... FROM (SELECT uu.user_id, count(f.follower_id) AS n FROM users uu LEFT JOIN follows f ... GROUP BY uu.user_id) s WHERE ...`
- **Expected Execution Behaviour:** **Heaviest Write Operation in Workload:** Performs a complete outer join between 30,000 `users` and 258,588 `follows`, groups across all 30,000 users, compares counts, and updates approximately 1,200 drifted rows in `users`. Generates heavy WAL, buffer dirtying, and lock time.
- **CP3 Optimization Potential:** Index on `follows(followee_id, status)` to dramatically speed up edge aggregation.

---

### W05 — Housekeeping Purge of Expired Stories
- **Category:** WRITE
- **Purpose:** Delete all ephemeral stories that expired before June 2026.
- **Target Table:** `stories`
- **Operation:** `DELETE FROM stories WHERE expires_at < '2026-06-01';`
- **Expected Execution Behaviour:** In the absence of an index on `stories.expires_at`, PostgreSQL must sequentially scan all 40,000 rows in `stories` to identify eligible rows, followed by heap deletion and index cleanup.
- **CP3 Optimization Potential:** B-tree index on `stories(expires_at)`.

---

### W06 — Bulk Accept Follow Requests
- **Category:** WRITE
- **Purpose:** Private user `338` bulk approves all pending follow requests.
- **Target Table:** `follows`
- **Operation:** `UPDATE follows SET status = 'ACCEPTED' WHERE followee_id = 338 AND status = 'PENDING';`
- **Expected Execution Behaviour:** `follows` has PK `(follower_id, followee_id)`. Without a leading index on `followee_id`, this query performs a `Seq Scan on follows` across all 258,588 rows to find pending requests for user `338`.
- **CP3 Optimization Potential:** Composite index on `follows(followee_id, status)`.

---

## 5. Expected Execution-Plan Behavior & Structural Analysis

Based on PostgreSQL query planner cost modeling and the Phase 2 schema design, we can formally predict the access methods available to the optimizer.

### 5.1 Access Paths Available vs Missing

```
+-------------------+-----------------------------+------------------------------------+
| Table             | Available B-tree Indexes    | Structurally Missing Indexes       |
+-------------------+-----------------------------+------------------------------------+
| users             | users_pkey (user_id)        | None (account_type, verified)      |
|                   | uq_users_username (username)|                                    |
|                   | uq_users_email (email)      |                                    |
+-------------------+-----------------------------+------------------------------------+
| follows           | follows_pkey                | follows(followee_id, status)       |
|                   | (follower_id, followee_id)  | (Reverse graph edge lookup)        |
+-------------------+-----------------------------+------------------------------------+
| hashtags          | hashtags_pkey (hashtag_id)  | None                               |
|                   | uq_hashtags_tag (tag)       |                                    |
+-------------------+-----------------------------+------------------------------------+
| posts             | posts_pkey (post_id)        | posts(user_id, created_at)         |
|                   |                             | posts(created_at, like_count)      |
+-------------------+-----------------------------+------------------------------------+
| post_hashtags     | post_hashtags_pkey          | post_hashtags(hashtag_id, post_id) |
|                   | (post_id, hashtag_id)       | (Reverse tag lookup)               |
+-------------------+-----------------------------+------------------------------------+
| post_media        | post_media_pkey             | post_media(duration_sec)           |
|                   | (post_id, position)         |                                    |
+-------------------+-----------------------------+------------------------------------+
| likes             | likes_pkey                  | likes(post_id, user_id)            |
|                   | (user_id, post_id)          | (Post engagement reverse lookup)   |
+-------------------+-----------------------------+------------------------------------+
| comments          | comments_pkey (comment_id)  | comments(post_id, created_at)      |
|                   |                             | comments(parent_comment_id)        |
+-------------------+-----------------------------+------------------------------------+
| stories           | stories_pkey (story_id)     | stories(user_id, created_at)       |
|                   |                             | stories(expires_at)                |
+-------------------+-----------------------------+------------------------------------+
```

### 5.2 Plan Operator Breakdown
1. **Sequential Scans (`Seq Scan`):** Dominate tables `likes`, `follows`, `comments`, and `posts` whenever queries filter by unindexed foreign keys (`likes.post_id`, `comments.post_id`, `follows.followee_id`, `posts.user_id`).
2. **Primary Key / Unique Scans (`Index Scan`, `Index Only Scan`):** Limited to point lookups (`R03` on username, `R23` on likes composite key, `W03` on post ID).
3. **Join Mechanisms:**
   - **Nested Loop:** Selected when an outer index scan retrieves few tuples (e.g. `R01`, `R23`).
   - **Hash Join:** Selected for multi-table queries without supporting join indexes (`R11`, `R12`, `R15`, `R17`, `R20`). Requires building in-memory hash tables of child relations.
4. **Sort & Aggregation Nodes:**
   - `Sort` operations (`Top-N heapsort` or `quicksort`) appear across almost all read queries due to chronological ordering (`ORDER BY created_at DESC`).
   - `HashAggregate` used for multi-row groupings (`R04`, `R11`, `R12`, `R18`, `R20`, `R24`).

> [!IMPORTANT]
> The above access paths represent theoretical and structural deductions from the Phase 2 schema. The official measured plans and scan nodes will be populated in Section 6 once Atharv executes the official benchmark runs.

---

## 6. Official 30-Query Baseline Timing Table

### 6.1 Specification & Measurement Standards
The table below establishes the standardized CP2 baseline evaluation matrix. In compliance with course specifications (`README.md` §3.2 and `CHECKPOINTS.md` §3):
- Every query is timed across **three consecutive executions** (`Run 1`, `Run 2`, `Run 3`) using `EXPLAIN (ANALYZE, BUFFERS)`.
- The primary evaluation metric is the **arithmetic average** across the three runs:
  $$\text{Average Execution Time (ms)} = \frac{T_{\text{Run 1}} + T_{\text{Run 2}} + T_{\text{Run 3}}}{3}$$
- In addition, the **median** ($T_{\text{median}}$), **minimum** ($T_{\text{min}}$), and **maximum** ($T_{\text{max}}$) latencies are recorded to observe cache warming effects and tail variance.
- Observed relational scan nodes (e.g. `Seq Scan`, `Index Scan`, `Index Only Scan`) are cataloged from the execution plans.
- Data synchronization is managed programmatically via `benchmarks/analyze_baseline.py`.

<!-- BENCHMARK_TABLE_START -->
| Query | Type | Run 1 (ms) | Run 2 (ms) | Run 3 (ms) | Average (ms) | Median (ms) | Min (ms) | Max (ms) | Scan Type |
|---|---|---:|---:|---:|---:|---:|---:|---:|---|
| **R01**: Home feed: latest 30 posts from followed accounts | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R02**: Profile grid: user 217's latest 12 posts | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R03**: Open a profile by username | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R04**: Post page: top-level comments with reply counts | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R05**: Explore: top posts tagged #travel in June 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R06**: Search bar: prefix/substring match accounts | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R07**: "Liked by": users liking post with follow status | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R08**: "Suggested for you": friends-of-friends graph traversal | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R09**: Follow requests screen: pending requests for account 338 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R10**: Story highlights: stories by followed accounts in June 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R11**: Creator insights: engagement rate per follower (top 20) | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R12**: Trending: most used hashtags in late June 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R13**: Creator tools: comments with zero replies | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R14**: "Not following back": followers not followed back | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R15**: Data quality: accounts with mismatched follower counts | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R16**: Places: posts tagged in Goa during June 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R17**: Reels team: creator reels > 60s in 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R18**: Content analytics: daily post volume by type in June 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R19**: Verified-account report: last post and total likes | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R20**: Content analytics: top 10 most commented posts in June 2026 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R21**: Creator tools: ghost followers for user 217 | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R22**: Moderation console: hidden comments paginated | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R23**: Like button state: check if user 1042 liked post | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **R24**: Story insights: account story views in last 30 days | READ | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **W01**: Publish a new photo post | WRITE | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **W02**: Double-tap: user 1042 likes post 59689 | WRITE | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **W03**: Synchronize post like counter after like | WRITE | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **W04**: Nightly batch job: reconcile follower counts | WRITE | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **W05**: Housekeeping: delete expired stories before June 2026 | WRITE | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **W06**: Bulk accept pending follow requests for account 338 | WRITE | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* | *PENDING* |
| **Total Workload (Sum of all 30)** | **ALL** | — | — | — | *PENDING* | — | — | — | — |
<!-- BENCHMARK_TABLE_END -->

---

## 7. Performance Bottleneck Analysis Framework

<!-- RANKINGS_START -->
> [!NOTE]
> **Awaiting Official Benchmark Execution**  
> Complete rankings and empirical execution latencies will be automatically calculated and ranked by `benchmarks/analyze_baseline.py` once Atharv runs the benchmark on the shared Neon database.
<!-- RANKINGS_END -->

### 7.1 Expected Slowest Queries (Hypothesized Bottlenecks)
Based on relational complexity, relational algebra, and cardinality scans:
1. **`R19` (Verified Account Report):** Correlated subqueries executing an unindexed join over `likes` (420k rows) and `posts` (60k rows) for every verified user.
2. **`W04` (Follower Count Reconciliation):** Full outer join and aggregation over 258,588 follow records and 30,000 user rows, followed by ~1,200 heap updates.
3. **`R21` (Creator Ghost Followers):** Multi-table anti-join subquery scanning `follows` and joining `likes` and `posts` without supporting foreign key indexes.
4. **`R15` (Follower Count Discrepancy Audit):** Full table scans on `users` and `follows` with complete hash aggregation.
5. **`R07` / `R08` / `R09` (Social Graph Traversals):** Lack of index on `follows(followee_id)` forces 258,588 row sequential scans.

### 7.2 Expected Fastest Queries
1. **`R23` (Like Button State):** Point lookup using composite primary key index `likes_pkey (user_id, post_id)` via `Index Only Scan`.
2. **`R03` (Profile by Username):** Point lookup using unique B-tree index `uq_users_username`.
3. **`W01` / `W02` (Single Row Inserts):** Direct append to table heaps with single PK check.
4. **`W03` (Single Post Counter Increment):** Direct single-tuple update via `posts_pkey`.

### 7.3 Buffer Pool Hierarchy & Memory Impact
In un-indexed baseline configurations:
- **Shared Hit vs Shared Read:** Initial query runs will exhibit high `shared read` counts as 1.2M rows are pulled from remote storage into local Neon / PostgreSQL buffer cache. Subsequent runs will transition to `shared hit`.
- **Buffer Bloat:** Sequential scans over `likes` (419,954 rows) and `follows` (258,588 rows) will repeatedly flush active working sets from the PostgreSQL buffer ring buffer.

---

## 8. CP3 Optimization Opportunities (Forward-Looking Strategy)

The baseline analysis highlights key structural optimization vectors to be investigated in Checkpoint 3 (CP3). **In strict adherence to CP2 rules, no optimizations are implemented at this time.**

### 8.1 Critical Missing Indexes (Candidate Index Set)
1. **Social Graph Reverse Lookup:**
   ```sql
   CREATE INDEX idx_follows_followee_status ON follows (followee_id, status);
   ```
   *Targets:* `R09`, `R14`, `R15`, `W04`, `W06`.
2. **Post Engagement & Reverse Like Index:**
   ```sql
   CREATE INDEX idx_likes_post_user ON likes (post_id, user_id);
   ```
   *Targets:* `R07`, `R19`, `R20`, `R21`.
3. **Comment Post & Threading Hierarchy:**
   ```sql
   CREATE INDEX idx_comments_post_parent ON comments (post_id, parent_comment_id);
   ```
   *Targets:* `R04`, `R13`, `R20`.
4. **User Feed Publication Ordering:**
   ```sql
   CREATE INDEX idx_posts_user_created ON posts (user_id, created_at DESC);
   ```
   *Targets:* `R01`, `R02`, `R11`.
5. **Partial & Trigram Indexes:**
   ```sql
   CREATE INDEX idx_users_username_trgm ON users USING gin (username gin_trgm_ops);
   CREATE INDEX idx_comments_hidden ON comments (created_at DESC) WHERE is_hidden;
   ```
   *Targets:* `R06`, `R16`, `R22`.

### 8.2 Query Rewriting & Architectural Refactoring
1. **R13 NULL-Safe Refactoring:** Replace `c.comment_id NOT IN (SELECT r.parent_comment_id ...)` with `NOT EXISTS` or `LEFT JOIN` to resolve SQL three-valued logic failures.
2. **R19 Set-Based Transformation:** Eliminate correlated subqueries by computing verified user metrics through a single pre-aggregated Common Table Expression (CTE) or joined summary view.
3. **R10 Sargable Date Rewriting:** Convert `DATE(s.created_at) BETWEEN ...` into open timestamp intervals (`s.created_at >= '2026-06-01' AND s.created_at < '2026-07-01'`).

---

## 9. Conclusion & Next Steps

Checkpoint 2 establishes the foundational reference measurements for the Instagram Social Media Database. By measuring the raw relational performance of the unindexed schema against the 30-query workload:
1. Every query's baseline mechanics, access paths, and computational complexity have been formally documented.
2. The exact measurement framework (`run_benchmark.sh` and `analyze_baseline.py`) is locked and ready for execution.
3. Clear empirical targets are defined for CP3, where indexing and query refactoring will be evaluated against these baseline timings.

Upon execution of the official benchmark suite by Atharv, the results will be ingested directly into Section 6 to complete the quantitative evaluation.
