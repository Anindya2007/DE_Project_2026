-- =====================================================================
-- Instagram DBMS Project: Production Secondary Indexes (CP3 / Phase 4)
-- Author: Anshika Srivastava (Soysauce69)
-- Team: T0145
--
-- DESIGN RATIONALE:
--   The baseline workload revealed severe performance bottlenecks caused by:
--     1. Foreign key columns lacking secondary indexes (e.g., follows.followee_id,
--        likes.post_id, comments.post_id, stories.user_id).
--     2. Composite query patterns requiring both filtering and sorting (e.g.,
--        user_id + created_at DESC).
--     3. Massive full table scans on multi-hundred-thousand row tables
--        (likes: 420k rows, follows: 258k rows, comments: 150k rows).
--
--   This file establishes target secondary indexes, partial indexes, and
--   covering indexes (INCLUDE) that directly eliminate sequential scans
--   while minimizing write overhead.
-- =====================================================================

SET search_path TO instagram;

-- ---------------------------------------------------------------------
-- 1. FOLLOWS TABLE INDEXES (Table size: 258,588 rows)
-- Primary key is (follower_id, followee_id).
-- Queries filtering by followee_id undergo full sequential scans.
-- ---------------------------------------------------------------------

-- Eliminates 258k-row sequential scan when looking up followers of an account.
-- Crucial for R01 (Home feed), R07 (Liked by), R08 (Suggested), R10 (Stories),
-- R14 (Not following back), R15 (Data quality), R21 (Ghost followers), W04.
CREATE INDEX IF NOT EXISTS idx_follows_followee_status
ON follows (followee_id, status)
INCLUDE (follower_id);

-- Partial index dedicated to pending follow requests.
-- Greatly accelerates R09 (pending requests for private accounts) and W06 (bulk approve).
CREATE INDEX IF NOT EXISTS idx_follows_pending
ON follows (followee_id, created_at DESC)
WHERE status = 'PENDING';

-- ---------------------------------------------------------------------
-- 2. POSTS TABLE INDEXES (Table size: 60,000 rows)
-- Primary key is post_id.
-- ---------------------------------------------------------------------

-- Composite partial index for active user feeds and profile grids.
-- Provides index-ordered retrieval for R01 and R02 without separate Sort node.
CREATE INDEX IF NOT EXISTS idx_posts_user_created
ON posts (user_id, created_at DESC)
WHERE NOT is_archived;

-- Temporal range index for analytical queries filtering by date.
-- Supports R05, R11, R12, R16, R18, R20.
CREATE INDEX IF NOT EXISTS idx_posts_created_at
ON posts (created_at DESC);

-- Partial index for creators' video reels in 2026.
-- Supports R17 by eliminating table scans on non-reel posts.
CREATE INDEX IF NOT EXISTS idx_posts_reels_2026
ON posts (post_id, like_count DESC)
WHERE post_type = 'REEL'
  AND created_at >= '2026-01-01 00:00:00+00'
  AND created_at < '2027-01-01 00:00:00+00';

-- ---------------------------------------------------------------------
-- 3. LIKES TABLE INDEXES (Table size: 419,954 rows)
-- Primary key is (user_id, post_id).
-- ---------------------------------------------------------------------

-- Reverse composite index. Point lookup by post_id previously scanned 420k rows.
-- Transforms R07, R19, R20, R21 from sequential scans into tight Index Scans.
CREATE INDEX IF NOT EXISTS idx_likes_post_id
ON likes (post_id, created_at DESC)
INCLUDE (user_id);

-- ---------------------------------------------------------------------
-- 4. COMMENTS TABLE INDEXES (Table size: 150,000 rows)
-- Primary key is comment_id.
-- ---------------------------------------------------------------------

-- Supports post comment page retrieval with hierarchical parent lookup (R04).
CREATE INDEX IF NOT EXISTS idx_comments_post_parent
ON comments (post_id, parent_comment_id, created_at)
WHERE NOT is_hidden;

-- Partial index on reply comments to support hierarchical self-joins (R04)
-- and anti-join NOT EXISTS checks for unanswered comments (R13).
CREATE INDEX IF NOT EXISTS idx_comments_parent
ON comments (parent_comment_id)
WHERE parent_comment_id IS NOT NULL;

-- Partial index for moderation queue pagination (R22).
-- Filters only hidden comments, drastically shrinking index size and speeding up OFFSET/LIMIT.
CREATE INDEX IF NOT EXISTS idx_comments_hidden_created
ON comments (created_at DESC)
WHERE is_hidden;

-- Index on post_id for comment aggregation (R20).
CREATE INDEX IF NOT EXISTS idx_comments_post_id
ON comments (post_id);

-- ---------------------------------------------------------------------
-- 5. STORIES TABLE INDEXES (Table size: 40,000 rows)
-- Primary key is story_id.
-- ---------------------------------------------------------------------

-- Composite index on author and timestamp for story feed retrieval (R10, R24).
CREATE INDEX IF NOT EXISTS idx_stories_user_created
ON stories (user_id, created_at DESC);

-- Partial index on expired stories for housekeeping cleanup (W05).
-- Allows instantaneous index range seek for expired story deletion.
CREATE INDEX IF NOT EXISTS idx_stories_expires_at
ON stories (expires_at)
WHERE expires_at < '2026-06-01 00:00:00+00';

-- ---------------------------------------------------------------------
-- 6. POST_HASHTAGS TABLE INDEXES (Table size: 150,000 rows)
-- Primary key is (post_id, hashtag_id).
-- ---------------------------------------------------------------------

-- Reverse index on hashtag_id to allow fast retrieval of posts for a given hashtag (R05, R12).
CREATE INDEX IF NOT EXISTS idx_post_hashtags_hashtag_id
ON post_hashtags (hashtag_id, post_id);

-- ---------------------------------------------------------------------
-- 7. USERS TABLE INDEXES (Table size: 30,000 rows)
-- Primary key is user_id. Existing unique on username and email.
-- ---------------------------------------------------------------------

-- Partial index on verified users for VIP analytics reporting (R19).
CREATE INDEX IF NOT EXISTS idx_users_verified
ON users (user_id)
WHERE is_verified;

-- Partial index on creators for creator insights and data quality audits (R11, R15).
CREATE INDEX IF NOT EXISTS idx_users_creators
ON users (user_id, followers_count)
WHERE account_type = 'CREATOR';

-- Update database statistics after index creation
ANALYZE users;
ANALYZE follows;
ANALYZE posts;
ANALYZE comments;
ANALYZE likes;
ANALYZE stories;
ANALYZE post_hashtags;
ANALYZE hashtags;
ANALYZE post_media;
