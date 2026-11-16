-- =====================================================================
-- Instagram Social Media Database: Seed Data Loading Script
-- Phase 2 / CP1 deliverable: sql/02_load_data.sql
-- Database: PostgreSQL 15+
-- Schema: instagram
--
-- Usage:
--   psql -d <database> -f sql/02_load_data.sql
--   or inside psql: \i sql/02_load_data.sql
-- Note: Run from repository root so relative path 'seed_data/*.csv' resolves.
-- =====================================================================

SET search_path TO instagram;

\echo 'Loading users...'
\copy users (user_id, username, full_name, email, bio, account_type, is_private, is_verified, followers_count, following_count, created_at) FROM 'seed_data/users.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading follows...'
\copy follows (follower_id, followee_id, status, created_at) FROM 'seed_data/follows.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading hashtags...'
\copy hashtags (hashtag_id, tag) FROM 'seed_data/hashtags.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading posts...'
\copy posts (post_id, user_id, post_type, caption, location_name, like_count, comment_count, is_archived, created_at) FROM 'seed_data/posts.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading post_hashtags...'
\copy post_hashtags (post_id, hashtag_id) FROM 'seed_data/post_hashtags.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading post_media...'
\copy post_media (post_id, position, media_type, media_url, width, height, duration_sec) FROM 'seed_data/post_media.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading likes...'
\copy likes (user_id, post_id, created_at) FROM 'seed_data/likes.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading comments...'
\copy comments (comment_id, post_id, user_id, parent_comment_id, body, is_hidden, created_at) FROM 'seed_data/comments.csv' WITH (FORMAT csv, HEADER true);

\echo 'Loading stories...'
\copy stories (story_id, user_id, media_type, created_at, expires_at, view_count) FROM 'seed_data/stories.csv' WITH (FORMAT csv, HEADER true);

\echo 'Updating optimizer statistics...'
ANALYZE;

\echo 'Data load completed successfully.'
