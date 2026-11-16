-- =====================================================================
-- Instagram Social Media Database: DDL Schema Definition
-- Phase 2 / CP1 deliverable: sql/01_schema.sql
-- Database: PostgreSQL 15+
-- Schema: instagram
-- =====================================================================

CREATE SCHEMA IF NOT EXISTS instagram;
SET search_path TO instagram;

-- Clean drop for clean reproducibility if executed from scratch
DROP TABLE IF EXISTS comments CASCADE;
DROP TABLE IF EXISTS likes CASCADE;
DROP TABLE IF EXISTS post_media CASCADE;
DROP TABLE IF EXISTS post_hashtags CASCADE;
DROP TABLE IF EXISTS posts CASCADE;
DROP TABLE IF EXISTS hashtags CASCADE;
DROP TABLE IF EXISTS follows CASCADE;
DROP TABLE IF EXISTS stories CASCADE;
DROP TABLE IF EXISTS users CASCADE;

-- ---------------------------------------------------------------------
-- 1. USERS TABLE
-- ---------------------------------------------------------------------
CREATE TABLE users (
    user_id         INTEGER PRIMARY KEY,
    username        VARCHAR(50) NOT NULL,
    full_name       VARCHAR(100) NOT NULL,
    email           VARCHAR(255) NOT NULL,
    bio             TEXT,
    account_type    VARCHAR(20) NOT NULL,
    is_private      BOOLEAN NOT NULL DEFAULT FALSE,
    is_verified     BOOLEAN NOT NULL DEFAULT FALSE,
    followers_count INTEGER NOT NULL DEFAULT 0,
    following_count INTEGER NOT NULL DEFAULT 0,
    created_at      TIMESTAMPTZ NOT NULL,

    -- Candidate keys
    CONSTRAINT uq_users_username UNIQUE (username),
    CONSTRAINT uq_users_email UNIQUE (email),

    -- Domain & business integrity checks
    CONSTRAINT chk_users_account_type CHECK (account_type IN ('PERSONAL', 'CREATOR', 'BUSINESS')),
    CONSTRAINT chk_users_followers_count CHECK (followers_count >= 0),
    CONSTRAINT chk_users_following_count CHECK (following_count >= 0),
    CONSTRAINT chk_users_business_not_private CHECK (account_type <> 'BUSINESS' OR NOT is_private),
    CONSTRAINT chk_users_username_format CHECK (username ~ '^[a-zA-Z0-9._]+$'),
    CONSTRAINT chk_users_email_format CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- ---------------------------------------------------------------------
-- 2. FOLLOWS TABLE (M:N self-relationship on users)
-- ---------------------------------------------------------------------
CREATE TABLE follows (
    follower_id     INTEGER NOT NULL,
    followee_id     INTEGER NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'PENDING',
    created_at      TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (follower_id, followee_id),
    CONSTRAINT fk_follows_follower FOREIGN KEY (follower_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_follows_followee FOREIGN KEY (followee_id) REFERENCES users(user_id) ON DELETE CASCADE,

    CONSTRAINT chk_follows_no_self_follow CHECK (follower_id <> followee_id),
    CONSTRAINT chk_follows_status CHECK (status IN ('ACCEPTED', 'PENDING'))
);

-- ---------------------------------------------------------------------
-- 3. HASHTAGS TABLE
-- ---------------------------------------------------------------------
CREATE TABLE hashtags (
    hashtag_id      INTEGER PRIMARY KEY,
    tag             VARCHAR(50) NOT NULL,

    CONSTRAINT uq_hashtags_tag UNIQUE (tag),
    CONSTRAINT chk_hashtags_tag_format CHECK (tag ~ '^[a-zA-Z0-9_]+$'),
    CONSTRAINT chk_hashtags_tag_lowercase CHECK (tag = lower(tag))
);

-- ---------------------------------------------------------------------
-- 4. POSTS TABLE
-- ---------------------------------------------------------------------
CREATE TABLE posts (
    post_id         BIGINT PRIMARY KEY,
    user_id         INTEGER NOT NULL,
    post_type       VARCHAR(20) NOT NULL,
    caption         TEXT,
    location_name   VARCHAR(100),
    like_count      INTEGER NOT NULL DEFAULT 0,
    comment_count   INTEGER NOT NULL DEFAULT 0,
    is_archived     BOOLEAN NOT NULL DEFAULT FALSE,
    created_at      TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_posts_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_posts_post_type CHECK (post_type IN ('PHOTO', 'VIDEO', 'CAROUSEL', 'REEL')),
    CONSTRAINT chk_posts_like_count CHECK (like_count >= 0),
    CONSTRAINT chk_posts_comment_count CHECK (comment_count >= 0)
);

-- ---------------------------------------------------------------------
-- 5. POST_HASHTAGS TABLE (M:N between posts and hashtags)
-- ---------------------------------------------------------------------
CREATE TABLE post_hashtags (
    post_id         BIGINT NOT NULL,
    hashtag_id      INTEGER NOT NULL,

    PRIMARY KEY (post_id, hashtag_id),
    CONSTRAINT fk_post_hashtags_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    CONSTRAINT fk_post_hashtags_hashtag FOREIGN KEY (hashtag_id) REFERENCES hashtags(hashtag_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 6. POST_MEDIA TABLE (1:N weak entity / composite media items)
-- ---------------------------------------------------------------------
CREATE TABLE post_media (
    post_id         BIGINT NOT NULL,
    position        SMALLINT NOT NULL,
    media_type      VARCHAR(20) NOT NULL,
    media_url       TEXT NOT NULL,
    width           INTEGER NOT NULL,
    height          INTEGER NOT NULL,
    duration_sec    NUMERIC(5, 1),

    PRIMARY KEY (post_id, position),
    CONSTRAINT fk_post_media_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    CONSTRAINT chk_post_media_position CHECK (position >= 1 AND position <= 10),
    CONSTRAINT chk_post_media_type CHECK (media_type IN ('IMAGE', 'VIDEO')),
    CONSTRAINT chk_post_media_dimensions CHECK (width > 0 AND height > 0),
    CONSTRAINT chk_post_media_duration CHECK (
        (media_type = 'VIDEO' AND duration_sec IS NOT NULL AND duration_sec > 0)
        OR (media_type = 'IMAGE' AND duration_sec IS NULL)
    )
);

-- ---------------------------------------------------------------------
-- 7. LIKES TABLE (M:N between users and posts)
-- ---------------------------------------------------------------------
CREATE TABLE likes (
    user_id         INTEGER NOT NULL,
    post_id         BIGINT NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL,

    PRIMARY KEY (user_id, post_id),
    CONSTRAINT fk_likes_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_likes_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE
);

-- ---------------------------------------------------------------------
-- 8. COMMENTS TABLE (Hierarchical comment tree)
-- ---------------------------------------------------------------------
CREATE TABLE comments (
    comment_id          BIGINT PRIMARY KEY,
    post_id             BIGINT NOT NULL,
    user_id             INTEGER NOT NULL,
    parent_comment_id   BIGINT,
    body                TEXT NOT NULL,
    is_hidden           BOOLEAN NOT NULL DEFAULT FALSE,
    created_at          TIMESTAMPTZ NOT NULL,

    CONSTRAINT fk_comments_post FOREIGN KEY (post_id) REFERENCES posts(post_id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT fk_comments_parent FOREIGN KEY (parent_comment_id) REFERENCES comments(comment_id) ON DELETE CASCADE,
    CONSTRAINT chk_comments_parent_not_self CHECK (parent_comment_id IS NULL OR parent_comment_id <> comment_id)
);

-- ---------------------------------------------------------------------
-- 9. STORIES TABLE (Ephemeral 24h content)
-- ---------------------------------------------------------------------
CREATE TABLE stories (
    story_id        BIGINT PRIMARY KEY,
    user_id         INTEGER NOT NULL,
    media_type      VARCHAR(20) NOT NULL,
    created_at      TIMESTAMPTZ NOT NULL,
    expires_at      TIMESTAMPTZ NOT NULL,
    view_count      INTEGER NOT NULL DEFAULT 0,

    CONSTRAINT fk_stories_user FOREIGN KEY (user_id) REFERENCES users(user_id) ON DELETE CASCADE,
    CONSTRAINT chk_stories_media_type CHECK (media_type IN ('IMAGE', 'VIDEO')),
    CONSTRAINT chk_stories_expires_after_created CHECK (expires_at > created_at),
    CONSTRAINT chk_stories_view_count CHECK (view_count >= 0)
);
