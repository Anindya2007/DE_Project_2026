# Phase 1: Problem Understanding & Stakeholder Analysis

**Instagram Social Media Database (DBMS Project)**  
**Team:** T0145 · **Section:** A  
**Lead:** Anindya Sarkar | **Members:** Atharv Upadhyay, Badal Khandelwal, Anshika Srivastava  

---

## 1. Executive Summary

Instagram's core platform architecture is centered on a high-throughput social graph connecting accounts, media publications (photos, videos, carousels, reels), temporary ephemeral content (24-hour stories), and engagement interactions (likes, hierarchical comments, follow requests). The database currently operates without a formal relational schema specification, resulting in severe performance degradation across primary user journeys and critical backend processing pipelines.

This document systematically deconstructs the nine reported production bottlenecks (P1–P9), maps their business impact to respective stakeholder groups, classifies operational workloads into customer-facing real-time versus batch analytics tiers, and outlines core platform assumptions.

---

## 2. Problem Deconstruction (P1 – P9)

| # | Problem Reported | Primary Stakeholders | Classification | Associated Queries | Root Cause & Business Impact |
|---|---|---|---|---|---|
| **P1** | Slow Home Feed & Profile Grid for high-following users | End Users, Feed Engineering Team | Customer-Facing / Real-Time (< 5 ms target) | `R01`, `R02`, `R03` | Unindexed foreign keys on `follows` and `posts(user_id, created_at)` cause multi-table sequential scans when aggregating reverse-chronological feeds. Directly impairs user retention and app session initiation latency. |
| **P2** | Slow Viral Post Pages (comments, replies, like button states) | End Users, Content Consumers, Post Page Team | Customer-Facing / Real-Time (< 5 ms target) | `R04`, `R07`, `R23`, `W02`, `W03` | High concurrency lookups on viral post comments and likes suffer from unbounded scans across 420k+ likes and 150k+ comments. Real-time engagement checks (`EXISTS` on likes) stall during active traffic surges. |
| **P3** | High Latency in Explore & Search Type-Ahead | Search & Discovery Team, General Users | Interactive Search (< 250 ms target) | `R05`, `R06`, `R12`, `R16` | Case-insensitive prefix/substring pattern matching (`ILIKE '%karan%'`) on user entities and unindexed location filtering trigger full-table sequential sweeps, breaking real-time type-ahead expectations. |
| **P4** | Lag in Friend Recommendations & Pending Follow Requests | Social Graph Team, Private Account Users | Real-Time & Interactive (< 250 ms target) | `R08`, `R09`, `W06` | Two-hop friends-of-friends graph traversals (`f1 JOIN f2`) execute nested loop sequential joins. Private users waiting to triage pending follow requests experience lag due to missing `(followee_id, status)` indexes. |
| **P5** | Creator Insights & Audience Analytics Bottlenecks | Creator Ecosystem, Business Accounts | Reporting & Analytics (< 5,000 ms target) | `R11`, `R14`, `R17`, `R21` | Heavy aggregations calculating engagement rates, asymmetric follow relationships, video duration thresholds, and ghost followers require multi-table hash joins across full historical datasets without pre-aggregated summaries. |
| **P6** | Creator Tool "Comments Without Replies" Returning Empty | Creators, Community Management Team | Interactive / Diagnostic (< 250 ms target) | `R13` | Three-valued logic SQL defect: `NOT IN (SELECT parent_comment_id FROM comments)` evaluates to `UNKNOWN`/empty because `parent_comment_id` contains `NULL`s for all top-level comments. Requires query rewrite or filtering. |
| **P7** | Stored Profile Counters Drifting Out of Sync | Data Integrity Team, Platform Reliability | Batch Maintenance (< 3,000 ms target) | `R15`, `W04` | Asynchronous counter increments and incomplete atomic guarantees cause denormalized follower/like counts to drift. The corrective full-table join sweep (`W04`) is too slow for nocturnal execution windows without delta tracking. |
| **P8** | High Latency in Ephemeral Story Cleanup & Moderation Console | Trust & Safety Team, Ephemeral Media Team | Interactive & Batch (< 3,000 ms target) | `R10`, `R22`, `R24`, `W05` | Offset pagination on flagged comments (`OFFSET 1500`) scans and discards hundreds of pages. Large-scale bulk deletion of expired stories (`W05`) lacks partition pruning and index-driven range deletes. |
| **P9** | Analytics Query Timeouts Under 20× Anticipated Volume Growth | Growth Analytics, Executive Leadership | Complex Analytics (< 5,000 ms target) | `R18`, `R19`, `R20`, `W01` | Multi-dimensional grouping over high-cardinality event streams (posts, likes, comments by date/type) scales linearly or quadratically. The database requires architectural indexing, summary layers, and table partitioning. |

---

## 3. Workload Classification & Performance SLA Framework

To guide benchmarking and subsequent phase optimization, database operations are grouped into four operational tiers:

```mermaid
flowchart TD
    subgraph Tier1["Tier 1: Customer-Facing Real-Time (< 5 ms)"]
        T1A["R01: Home Feed Retrieval"]
        T1B["R02: Profile Post Grid"]
        T1C["R03: Profile Metadata by Username"]
        T1D["R04: Post Comments & Reply Count"]
        T1E["R07: Post Likers & Social Follow Check"]
        T1F["R23: Like Button State Verification"]
        T1G["W01: Publish Photo Post"]
        T1H["W02: Double-Tap Like Action"]
        T1I["W03: Post Counter Increment"]
    end

    subgraph Tier2["Tier 2: Interactive Discovery & Triage (< 250 ms)"]
        T2A["R05: Tagged Explore Posts"]
        T2B["R06: Username / Full Name Search"]
        T2C["R08: Suggested Friend-of-Friend Graph"]
        T2D["R09: Pending Follow Requests"]
        T2E["R10: Story Highlights Feed"]
        T2F["R13: Unanswered Creator Comments"]
        T2G["R14: Asymmetric Non-Mutual Followers"]
        T2H["R16: Geolocation Place Search"]
        T2I["R22: Moderation Console Paginated Audit"]
        T2J["W06: Bulk Follow Request Acceptance"]
    end

    subgraph Tier3["Tier 3: Creator & Platform Analytics (< 5,000 ms)"]
        T3A["R11: Creator Engagement Rate Top 20"]
        T3B["R12: Trending Hashtags in Window"]
        T3C["R15: Follower Counter Audit"]
        T3D["R17: Extended Reel Performance Analysis"]
        T3E["R18: Publishing Volume by Date & Type"]
        T3F["R19: Verified Account Engagement Rollup"]
        T3G["R20: Top 10 Most Commented Posts"]
        T3H["R21: Inactive Ghost Follower Detection"]
        T3I["R24: 30-Day Story View Engagement Top 20"]
    end

    subgraph Tier4["Tier 4: Platform Maintenance Batch Jobs (< 3,000 ms)"]
        T4A["W04: Nightly Follower Reconciliation"]
        T4B["W05: Ephemeral Expired Story Purge"]
    end
```

---

## 4. Key Architectural & Business Assumptions

1. **Social Graph Topology:** Follow connections are directional. If User A follows User B, User B does not automatically follow User A. Private accounts require explicit authorization (`status = 'PENDING' -> 'ACCEPTED'`), whereas public accounts transition directly to `'ACCEPTED'`. Self-following is strictly invalid.
2. **Denormalization Strategy:** Counters (`followers_count`, `following_count`, `like_count`, `comment_count`) are maintained as denormalized integers on parent tables (`users`, `posts`) for low-latency read rendering. Periodic reconciliation jobs (`W04`) correct asynchronous drift.
3. **Temporal Ephemerality:** Stories are ephemeral assets with an exact 24-hour lifetime lifecycle (`expires_at = created_at + INTERVAL '24 hours'`). Expired stories older than retention thresholds are safely purgable by background jobs (`W05`).
4. **Content Composition:** A post consists of 1 to 10 media assets (`post_media`). Single image/video posts have exactly 1 media record at position 1. Carousels must contain at least 2 media records ordered sequentially by `position`.
5. **Hierarchical Comments:** Comments support a single-level or multi-level threaded structure. A top-level comment has `parent_comment_id IS NULL`, while a reply references another valid `comment_id` belonging to the exact same `post_id`.
6. **Integrity Guarantees:** When a user or post is deleted, associated subordinate engagement records (`likes`, `comments`, `post_media`, `post_hashtags`) must cascade cleanly (`ON DELETE CASCADE`) to prevent orphaned records.
