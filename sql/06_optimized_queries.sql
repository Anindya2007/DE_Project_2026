-- =====================================================================
-- Instagram DBMS Project: Optimized Workload (Phase 4 / CP3)
-- Team T0145
--
-- Optimization Rules:
--   1. Preserve all 30 query markers (-- @R01 .. -- @W06).
--   2. Maintain exact relational semantics and return schemas.
--   3. Replace non-sargable expressions (DATE(), EXTRACT(), ::date) with index-scannable ranges.
--   4. Fix SQL three-valued logic trap in R13 (NOT IN NULL trap -> NOT EXISTS).
--   5. Refactor correlated quadratic subqueries into set-based joins (R19).
--   6. Leverage covering and composite secondary indexes defined in sql/05_indexes.sql.
-- =====================================================================
SET search_path TO instagram;
BEGIN;

-- @R01
-- Home feed: the latest 30 posts from accounts user 1042 follows
-- OPTIMIZATION: Relies on idx_follows_follower_status and idx_posts_user_created
SELECT p.post_id, p.user_id, p.post_type, p.caption, p.like_count, p.created_at
FROM follows f
JOIN posts p ON p.user_id = f.followee_id
WHERE f.follower_id = 1042
  AND f.status = 'ACCEPTED'
  AND NOT p.is_archived
ORDER BY p.created_at DESC
LIMIT 30;

-- @R02
-- Profile grid: user 217's latest 12 posts
-- OPTIMIZATION: Accelerated by partial composite index idx_posts_user_created
SELECT post_id, post_type, like_count, comment_count, created_at
FROM posts
WHERE user_id = 217 AND NOT is_archived
ORDER BY created_at DESC
LIMIT 12;

-- @R03
-- Open a profile by username
-- OPTIMIZATION: Point lookup using existing unique index uq_users_username
SELECT user_id, full_name, bio, is_private, is_verified, followers_count, following_count
FROM users
WHERE username = 'karan_singh217';

-- @R04
-- Post page: top-level comments on post 59689 with the number of replies each has
-- OPTIMIZATION: Supported by idx_comments_post_parent and idx_comments_parent
SELECT c.comment_id, c.user_id, c.body, c.created_at, count(r.comment_id) AS replies
FROM comments c
LEFT JOIN comments r ON r.parent_comment_id = c.comment_id
WHERE c.post_id = 59689
  AND c.parent_comment_id IS NULL
  AND NOT c.is_hidden
GROUP BY c.comment_id, c.user_id, c.body, c.created_at
ORDER BY c.created_at;

-- @R05
-- Explore: top posts tagged #travel in June 2026
-- OPTIMIZATION: Accelerated by idx_post_hashtags_hashtag_id and idx_posts_created_at
SELECT p.post_id, p.user_id, p.like_count
FROM hashtags h
JOIN post_hashtags ph ON ph.hashtag_id = h.hashtag_id
JOIN posts p          ON p.post_id = ph.post_id
WHERE h.tag = 'travel'
  AND p.created_at >= '2026-06-01'
ORDER BY p.like_count DESC
LIMIT 30;

-- @R06
-- Search bar: accounts whose username starts with "karan" or whose name contains "karan sharma"
-- OPTIMIZATION: B-tree text pattern index accelerates username prefix seek
SELECT user_id, username, full_name, is_verified, followers_count
FROM users
WHERE username ILIKE 'karan%' OR full_name ILIKE '%karan sharma%'
ORDER BY is_verified DESC, followers_count DESC
LIMIT 20;

-- @R07
-- "Liked by": people who liked post 59689, showing whether user 1042 follows them
-- OPTIMIZATION: Accelerated by idx_likes_post_id and follows_pkey
SELECT l.user_id, u.username, (f.follower_id IS NOT NULL) AS you_follow, l.created_at
FROM likes l
JOIN users u ON u.user_id = l.user_id
LEFT JOIN follows f ON f.follower_id = 1042 AND f.followee_id = l.user_id AND f.status = 'ACCEPTED'
WHERE l.post_id = 59689
ORDER BY you_follow DESC, l.created_at DESC;

-- @R08
-- "Suggested for you": friends-of-friends of user 1042 that 1042 doesn't follow yet
-- OPTIMIZATION: Accelerated by idx_follows_followee_status
SELECT f2.followee_id AS suggested_user, count(*) AS mutual_connections
FROM follows f1
JOIN follows f2 ON f2.follower_id = f1.followee_id AND f2.status = 'ACCEPTED'
WHERE f1.follower_id = 1042
  AND f1.status = 'ACCEPTED'
  AND f2.followee_id <> 1042
  AND NOT EXISTS (SELECT 1 FROM follows x WHERE x.follower_id = 1042 AND x.followee_id = f2.followee_id)
GROUP BY f2.followee_id
ORDER BY mutual_connections DESC, suggested_user
LIMIT 20;

-- @R09
-- Follow requests screen: pending requests for private account 338
-- OPTIMIZATION: Partial index idx_follows_pending on (followee_id, created_at DESC)
SELECT f.follower_id, u.username, f.created_at
FROM follows f
JOIN users u ON u.user_id = f.follower_id
WHERE f.followee_id = 338 AND f.status = 'PENDING'
ORDER BY f.created_at DESC;

-- @R10
-- Story highlights: stories posted in June 2026 by accounts user 1042 follows
-- OPTIMIZATION: SARGABLE RANGE REWRITE replaces DATE(s.created_at) wrapper
SELECT s.story_id, s.user_id, s.media_type, s.created_at, s.view_count
FROM stories s
JOIN follows f ON f.followee_id = s.user_id AND f.follower_id = 1042 AND f.status = 'ACCEPTED'
WHERE s.created_at >= '2026-06-01 00:00:00+00' AND s.created_at < '2026-07-01 00:00:00+00'
ORDER BY s.created_at DESC;

-- @R11
-- Creator insights: engagement rate (likes + comments per follower) of creators' 2026 posts, top 20
-- OPTIMIZATION: Filtered scan via idx_posts_user_created and partial index on creators
SELECT u.user_id, u.username, u.followers_count,
       round(sum(p.like_count + p.comment_count)::numeric / NULLIF(u.followers_count, 0), 3) AS engagement_per_follower
FROM users u
JOIN posts p ON p.user_id = u.user_id
WHERE u.account_type = 'CREATOR'
  AND p.created_at >= '2026-01-01'
GROUP BY u.user_id, u.username, u.followers_count
HAVING u.followers_count >= 20
ORDER BY engagement_per_follower DESC
LIMIT 20;

-- @R12
-- Trending: hashtags used most in the last 7 days of June 2026
-- OPTIMIZATION: Index scan on posts(created_at) joining post_hashtags
SELECT h.tag, count(*) AS posts
FROM post_hashtags ph
JOIN hashtags h ON h.hashtag_id = ph.hashtag_id
JOIN posts p    ON p.post_id = ph.post_id
WHERE p.created_at >= '2026-06-24'
GROUP BY h.tag
ORDER BY posts DESC
LIMIT 10;

-- @R13
-- Creator tools: comments on post 59689 that nobody has replied to yet
-- OPTIMIZATION & BUG FIX: NOT IN with NULL parent_comment_id produces empty set due to 3VL.
-- Rewritten to null-safe, anti-join NOT EXISTS supported by idx_comments_parent.
SELECT c.comment_id, c.user_id, c.body
FROM comments c
WHERE c.post_id = 59689
  AND NOT EXISTS (
      SELECT 1 FROM comments r
      WHERE r.parent_comment_id = c.comment_id
  );

-- @R14
-- "Not following back": accounts that follow user 217 whom 217 doesn't follow
-- OPTIMIZATION: Accelerated by idx_follows_followee_status
SELECT f.follower_id
FROM follows f
WHERE f.followee_id = 217 AND f.status = 'ACCEPTED'
  AND NOT EXISTS (SELECT 1 FROM follows b WHERE b.follower_id = 217 AND b.followee_id = f.follower_id)
ORDER BY f.follower_id;

-- @R15
-- Data quality: verified or creator accounts whose stored follower count is wrong
-- OPTIMIZATION: Hash aggregate over filtered users joined to indexed follows(followee_id)
SELECT u.user_id, u.username, u.followers_count AS stored, count(f.follower_id) AS actual
FROM users u
LEFT JOIN follows f ON f.followee_id = u.user_id AND f.status = 'ACCEPTED'
WHERE u.is_verified OR u.account_type = 'CREATOR'
GROUP BY u.user_id, u.username, u.followers_count
HAVING u.followers_count <> count(f.follower_id)
ORDER BY u.user_id;

-- @R16
-- Places: posts tagged with a location containing "goa" in June 2026
-- OPTIMIZATION: B-tree range scan on created_at with location filter
SELECT post_id, user_id, location_name, like_count
FROM posts
WHERE location_name ILIKE '%goa%'
  AND created_at >= '2026-06-01' AND created_at < '2026-07-01'
ORDER BY like_count DESC;

-- @R17
-- Reels team: creators' reels longer than 60 seconds posted in 2026
-- OPTIMIZATION: SARGABLE RANGE REWRITE replaces EXTRACT(YEAR FROM created_at)
SELECT p.post_id, p.user_id, pm.duration_sec, p.like_count
FROM posts p
JOIN post_media pm ON pm.post_id = p.post_id AND pm.position = 1
JOIN users u       ON u.user_id = p.user_id
WHERE p.post_type = 'REEL'
  AND pm.duration_sec > 60
  AND u.account_type = 'CREATOR'
  AND p.created_at >= '2026-01-01 00:00:00+00' AND p.created_at < '2027-01-01 00:00:00+00'
ORDER BY p.like_count DESC
LIMIT 50;

-- @R18
-- Content analytics: new posts per day and type in June 2026
-- OPTIMIZATION: SARGABLE RANGE REWRITE replaces non-sargable created_at::date in WHERE clause
SELECT created_at::date AS day, post_type, count(*) AS posts
FROM posts
WHERE created_at >= '2026-06-01 00:00:00+00' AND created_at < '2026-07-01 00:00:00+00'
GROUP BY 1, 2
ORDER BY 1, 2;

-- @R19
-- Verified-account report: last post time and total likes received by every verified account
-- OPTIMIZATION: CORRELATED SUBQUERY REWRITE -> Set-based CTE with pre-aggregation
WITH verified_accounts AS (
    SELECT user_id, username
    FROM users
    WHERE is_verified
),
post_metrics AS (
    SELECT p.user_id,
           max(p.created_at) AS last_post_at,
           count(l.user_id) AS likes_received
    FROM posts p
    JOIN verified_accounts va ON va.user_id = p.user_id
    LEFT JOIN likes l ON l.post_id = p.post_id
    GROUP BY p.user_id
)
SELECT va.user_id, va.username,
       pm.last_post_at,
       coalesce(pm.likes_received, 0) AS likes_received
FROM verified_accounts va
LEFT JOIN post_metrics pm ON pm.user_id = va.user_id
ORDER BY likes_received DESC;

-- @R20
-- Content analytics: 10 most-commented posts of June 2026 (counting real comments)
-- OPTIMIZATION: Filter posts on created_at before aggregating comments
SELECT c.post_id, count(*) AS comments
FROM comments c
JOIN posts p ON p.post_id = c.post_id
WHERE p.created_at >= '2026-06-01'
GROUP BY c.post_id
ORDER BY comments DESC
LIMIT 10;

-- @R21
-- Creator tools: "ghost followers" of user 217 (followers who never liked any of 217's posts)
-- OPTIMIZATION: Accelerated by idx_follows_followee_status and idx_likes_post_id
SELECT f.follower_id
FROM follows f
WHERE f.followee_id = 217 AND f.status = 'ACCEPTED'
  AND NOT EXISTS (
      SELECT 1 FROM likes l
      JOIN posts p ON p.post_id = l.post_id
      WHERE l.user_id = f.follower_id AND p.user_id = 217
  )
ORDER BY f.follower_id;

-- @R22
-- Moderation console: hidden comments, newest first, page 61 (25 per page)
-- OPTIMIZATION: Partial index on is_hidden (created_at DESC)
SELECT comment_id, post_id, user_id, body, created_at
FROM comments
WHERE is_hidden
ORDER BY created_at DESC
OFFSET 1500
LIMIT 25;

-- @R23
-- Like button state: has user 1042 liked post 59689?
-- OPTIMIZATION: Point lookup using primary key likes_pkey
SELECT EXISTS (SELECT 1 FROM likes WHERE user_id = 1042 AND post_id = 59689) AS liked;

-- @R24
-- Story insights: total story views per account in the last 30 days, top 20
-- OPTIMIZATION: Index range scan on stories(created_at)
SELECT user_id, count(*) AS stories, sum(view_count) AS views
FROM stories
WHERE created_at >= '2026-06-01'
GROUP BY user_id
ORDER BY views DESC
LIMIT 20;

-- @W01
-- Publish a new photo post
INSERT INTO posts (post_id, user_id, post_type, caption, location_name, created_at)
VALUES (90000001, 1042, 'PHOTO', 'Monsoon diaries #monsoon', 'Mumbai', '2026-07-01 08:00:00+05:30');

-- @W02
-- Double-tap: user 1042 likes post 59689
INSERT INTO likes (user_id, post_id, created_at)
VALUES (1042, 59689, '2026-07-01 08:01:00+05:30')
ON CONFLICT (user_id, post_id) DO NOTHING;

-- @W03
-- Keep the counter in sync after the like
UPDATE posts SET like_count = like_count + 1 WHERE post_id = 59689;

-- @W04
-- Nightly job: recompute every user's follower count
UPDATE users u
SET followers_count = coalesce(s.n, 0)
FROM (SELECT uu.user_id, count(f.follower_id) AS n
      FROM users uu LEFT JOIN follows f ON f.followee_id = uu.user_id AND f.status = 'ACCEPTED'
      GROUP BY uu.user_id) s
WHERE s.user_id = u.user_id AND u.followers_count <> coalesce(s.n, 0);

-- @W05
-- Housekeeping: delete stories that expired before June 2026
DELETE FROM stories
WHERE expires_at < '2026-06-01';

-- @W06
-- Private account 338 accepts all pending follow requests
UPDATE follows
SET status = 'ACCEPTED'
WHERE followee_id = 338 AND status = 'PENDING';

-- @END
ROLLBACK;
