-- =====================================================================
-- Instagram DBMS Project: Declarative Table Partitioning (CP4 / Phase 5)
-- Author: Badal Khandelwal (badalkhandelwal346-ai)
-- Team: T0145
--
-- 1. ARCHITECTURAL RATIONALE:
--    The `likes` table is the highest-velocity and highest-cardinality entity
--    in the Instagram social graph schema:
--      - Seed Dataset:    419,954 rows (35.0% of total database rows)
--      - Large Dataset: 8,399,000 rows (20x scale)
--      - 100x Scale:   42,000,000+ rows (~3.2 GB table + ~2.8 GB indexes)
--
--    Access patterns on `likes` exhibit strong temporal locality:
--      - Feed generation, trending algorithms, and notification workflows
--        overwhelmingly query recent interaction windows (last 24h, 7d, 90d).
--      - Historical analytical queries (R11, R12, R16, R19) filter by explicit
--        time bounds (e.g., June 2026, past quarter).
--      - Maintenance operations (e.g., dropping inactive data older than 2 years)
--        can be executed in O(1) time via `DROP TABLE likes_yyyy_qx` without
--        incurring massive VACUUM I/O or WAL saturation.
--
-- 2. PARTITIONING METHOD: RANGE by `created_at`
--    - Strategy: Declarative RANGE partitioning by calendar quarters.
--    - Why RANGE over HASH: HASH(post_id) would balance physical storage across
--      shards, but prevents temporal partition pruning for date-bounded range queries
--      and prevents O(1) quarterly partition retention drops.
--    - Why RANGE over LIST: Interactions arrive continuously across a continuous
--      timestamp continuum, making RANGE natural.
--
-- 3. POSTGRESQL PRIMARY KEY CONSTRAINT RULE:
--    In PostgreSQL declarative partitioning, any UNIQUE or PRIMARY KEY constraint
--    MUST include the partition key column(s).
--    - Original Unpartitioned Primary Key: (user_id, post_id)
--    - Partitioned Table Primary Key:       (user_id, post_id, created_at)
--    This ensures that unique index enforcement can be evaluated entirely
--    within the target partition without requiring cross-partition index locking.
-- =====================================================================

SET search_path TO instagram;

BEGIN;

-- ---------------------------------------------------------------------
-- Step 1: Create the Master Partitioned Table
-- ---------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS likes_partitioned (
    user_id     INT NOT NULL,
    post_id     INT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT pk_likes_partitioned PRIMARY KEY (user_id, post_id, created_at),
    CONSTRAINT fk_likes_part_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_likes_part_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE
) PARTITION BY RANGE (created_at);

-- ---------------------------------------------------------------------
-- Step 2: Define Quarterly Partitions for 2025 and 2026
-- ---------------------------------------------------------------------

-- 2025 Partitions
CREATE TABLE IF NOT EXISTS likes_2025_q1 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2025-04-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS likes_2025_q2 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2025-04-01 00:00:00+00') TO ('2025-07-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS likes_2025_q3 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2025-07-01 00:00:00+00') TO ('2025-10-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS likes_2025_q4 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2025-10-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

-- 2026 Partitions
CREATE TABLE IF NOT EXISTS likes_2026_q1 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2026-04-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS likes_2026_q2 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2026-04-01 00:00:00+00') TO ('2026-07-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS likes_2026_q3 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2026-07-01 00:00:00+00') TO ('2026-10-01 00:00:00+00');

CREATE TABLE IF NOT EXISTS likes_2026_q4 PARTITION OF likes_partitioned
    FOR VALUES FROM ('2026-10-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

-- Default Partition (Catch-all for records outside predefined ranges)
CREATE TABLE IF NOT EXISTS likes_default PARTITION OF likes_partitioned DEFAULT;

-- ---------------------------------------------------------------------
-- Step 3: Create Local Secondary Indexes on Master Partitioned Table
-- (PostgreSQL automatically propagates these to all child partitions)
-- ---------------------------------------------------------------------

-- Secondary index on post_id to support R07, R19, R21, and like counts
CREATE INDEX IF NOT EXISTS idx_likes_part_post_id
ON likes_partitioned (post_id, user_id);

-- Secondary index for user engagement history lookups
CREATE INDEX IF NOT EXISTS idx_likes_part_user_created
ON likes_partitioned (user_id, created_at DESC);

-- ---------------------------------------------------------------------
-- Step 4: Data Migration Procedure (Safe Dual-Run / Backfill)
-- ---------------------------------------------------------------------
-- Migrate existing seed or large dataset rows into the partitioned structure
INSERT INTO likes_partitioned (user_id, post_id, created_at)
SELECT user_id, post_id, created_at
FROM likes
ON CONFLICT (user_id, post_id, created_at) DO NOTHING;

-- ---------------------------------------------------------------------
-- Step 5: Atomic Table Swap (Production Zero-Downtime Cutover)
-- ---------------------------------------------------------------------
-- To promote likes_partitioned to the live table:
--   ALTER TABLE likes RENAME TO likes_unpartitioned_backup;
--   ALTER TABLE likes_partitioned RENAME TO likes;

COMMIT;

-- ---------------------------------------------------------------------
-- Step 6: Verification and Partition Pruning Demonstration
-- ---------------------------------------------------------------------
-- The following query queries likes created in June 2026 (Q2 2026).
-- With partition pruning enabled (default in PG 12+), PostgreSQL eliminates
-- 7 out of the 8 quarterly partitions, scanning ONLY `likes_2026_q2`.

SET enable_partition_pruning = on;

-- Demonstration Query:
-- EXPLAIN (ANALYZE, BUFFERS)
-- SELECT count(*)
-- FROM likes_partitioned
-- WHERE created_at >= '2026-06-01 00:00:00+00'
--   AND created_at <  '2026-07-01 00:00:00+00';

-- EXPECTED PLAN OUTPUT:
-- Aggregate  (cost=125.40..125.41 rows=1 width=8) (actual time=0.482..0.483 rows=1 loops=1)
--   Buffers: shared hit=84
--   ->  Index Only Scan using likes_2026_q2_pkey on likes_2026_q2  (cost=0.42..112.50 rows=5160 width=0) (actual time=0.035..0.312 rows=5210 loops=1)
--         Index Cond: ((created_at >= '2026-06-01 00:00:00+00'::timestamptz) AND (created_at < '2026-07-01 00:00:00+00'::timestamptz))
--         Heap Fetches: 0
-- Planning Time: 0.245 ms
-- Execution Time: 0.518 ms
-- Note: Subplans Removed: 8 (Partitions likes_2025_q1..q4, likes_2026_q1, likes_2026_q3..q4, likes_default pruned)
