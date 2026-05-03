-- View count support for user_reels
-- Run once against the `ms` database

ALTER TABLE user_reels
  ADD COLUMN IF NOT EXISTS view_count INT UNSIGNED NOT NULL DEFAULT 0;

-- Per-user view tracking (deduplication)
CREATE TABLE IF NOT EXISTS reel_views (
  id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  reel_id     INT             NOT NULL,
  user_id     INT             NOT NULL,
  watched_seconds TINYINT UNSIGNED NOT NULL DEFAULT 0,
  created_at  TIMESTAMP       NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY uq_reel_user_view (reel_id, user_id),
  KEY idx_rv_reel (reel_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
