# TikTok-Style Reels + Story Feature (Deep Analysis + Implementation Blueprint)

## 1) Current Project Findings (From Codebase Analysis)
- Mobile app uses custom bottom navigation via `apk/lib/ReUsable/Navbar.dart` and root orchestration in `apk/lib/Startup/MainControllere.dart`.
- Existing architecture already supports:
  - Media picking (`image_picker` dependency exists)
  - API endpoint centralization (`apk/lib/config/app_endpoints.dart`)
  - Feature gating (`apk/lib/config/feature_flags.dart`)
  - Admin APIs in `Backend/api9/`
- There is no complete short-video social module yet (no reel feed, no story table, no moderation pipeline).

## 2) Product Scope (What We Are Building)
TikTok-like ecosystem inside this app:
- Center camera/+ action in footer (done as phase-1 scaffold)
- Story upload (ephemeral, e.g., 24h)
- Reel upload (short video feed)
- Interactions: Like, Comment, Share, Save
- Safety: Sexual/NSFW content must be blocked before publish
- Privacy controls: user-owned audience visibility controls
- Admin visibility: admin can inspect user-shared reels/stories from profile context

## 3) Recommended Architecture

### 3.1 Data Model (MySQL)
Core tables:
- `user_stories`
  - `id`, `user_id`, `media_type` (image/video), `media_url`, `thumbnail_url`, `caption`, `privacy`, `status`, `expires_at`, `created_at`
- `user_reels`
  - `id`, `user_id`, `video_url`, `thumbnail_url`, `caption`, `privacy`, `status`, `allow_comments`, `allow_duet`, `allow_download`, `created_at`
- `reel_likes`
  - `id`, `reel_id`, `user_id`, `created_at` (unique on `reel_id,user_id`)
- `reel_comments`
  - `id`, `reel_id`, `user_id`, `comment`, `status`, `created_at`
- `reel_shares`
  - `id`, `reel_id`, `user_id`, `share_type`, `created_at`
- `media_moderation_jobs`
  - `id`, `entity_type` (story/reel), `entity_id`, `user_id`, `scan_status`, `scan_result`, `confidence`, `provider`, `raw_response_json`, `created_at`, `updated_at`
- `media_reports`
  - `id`, `entity_type`, `entity_id`, `reported_by`, `reason`, `note`, `status`, `created_at`

Suggested status enums:
- Reel/Story status: `pending_scan`, `active`, `blocked`, `deleted`, `archived`
- Moderation status: `queued`, `processing`, `approved`, `rejected`, `manual_review`

### 3.2 API Layer
App-side APIs (`Backend/Api2/`):
- `upload_story.php`
- `upload_reel.php`
- `reel_feed.php` (cursor pagination)
- `reel_react.php`
- `reel_comment.php`
- `reel_share.php`
- `reel_report.php`
- `story_feed.php` / `story_view.php`

Admin APIs (`Backend/api9/`):
- `get_reels_admin.php`
- `get_reel_reports.php`
- `update_reel_status.php`
- `get_user_media_activity.php`

### 3.3 Storage Strategy
- Store media under `/uploads/reels/` and `/uploads/stories/`
- Generate thumbnail for videos (FFmpeg server-side)
- Keep original upload + compressed serving variant

## 4) Sexual Content Blocking (Mandatory Safety)

### 4.1 Moderation Pipeline
1. User uploads media.
2. Record created with `pending_scan`.
3. Media goes to moderation worker.
4. If NSFW above threshold -> `blocked` + do not publish.
5. Else -> `active` and visible in feed/story.

### 4.2 Tools / Systems
Recommended tiers:
- Tier A (fast start): Cloud moderation API for image/video keyframes
  - e.g., Azure Content Safety / Vision moderation / similar
- Tier B (fallback): local frame sampling + classifier + rule engine
- Tier C (manual): admin review queue for borderline confidence

### 4.3 Practical Rule Set
- Reject immediately for high confidence sexual nudity (>= strict threshold)
- Send to manual review for medium confidence
- Allow for low confidence + log telemetry
- Also scan caption/comment text for explicit sexual terms and solicitation patterns

## 5) Privacy Model (User-Controlled)
Per-story and per-reel privacy options:
- `public`
- `matches_only`
- `followers_only` (if follow system exists)
- `private` (only self)
- `custom_list` (future)

Additional controls:
- Disable comments on reel
- Disable downloads
- Disable remix/duet
- Block list always enforced in feed query

## 6) Feed Ranking (Initial)
Base ranking score:
- recentness + watch completion + likes + comments + shares + profile affinity
- hard filters: privacy, block list, moderation status

Version 1 recommendation:
- time-decay + engagement score
- cursor pagination for smooth scrolling

## 7) Admin Visibility + Control
Admin should be able to:
- View a member’s reels/stories from member profile context
- See moderation score and reason
- Approve/reject/remove content
- Review reports and take action
- View abuse-repeat users via dashboard card

## 8) Security + Abuse Protection
- Strict mime/type and max-size validation at upload
- Frame-level scan for video (not only thumbnail)
- Rate limit uploads/comments/reactions per user/IP
- Signed URLs or validated local media paths
- XSS-safe comment rendering and length limits

## 9) Rollout Plan (Safe Delivery)
Phase 1:
- Center camera/+ button and create-entry UI (implemented)
- Endpoint constants + feature flags (implemented)

Phase 2:
- DB migration + upload APIs + pending moderation state

Phase 3:
- Reel feed + interactions + privacy filters

Phase 4:
- Admin moderation dashboard + user media section in admin profile

Phase 5:
- Ranking optimization + analytics + anti-abuse hardening

## 10) Success Metrics
- Upload success rate
- Moderation false-positive / false-negative rate
- Avg watch duration
- Interaction rate (like/comment/share)
- Abuse incidence and response time

## 11) What Has Been Added In This Update
- Footer center camera/+ action integrated in mobile navbar
- New create entry screen for Story/Reel capture/import
- Feature flags expanded for reels + moderation
- Endpoint constants for reels/stories interaction APIs

This gives a production-ready foundation while keeping rollout controlled and safe.
