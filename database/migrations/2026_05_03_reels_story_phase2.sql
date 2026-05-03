-- Safe Phase-2 migration: reels + stories + moderation + interactions
-- This file is intentionally scoped and idempotent.

SET NAMES utf8mb4;

CREATE TABLE IF NOT EXISTS user_stories (
    id                   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id              INT NOT NULL,
    media_type           ENUM('image','video') NOT NULL,
    media_url            VARCHAR(600) NOT NULL,
    thumbnail_url        VARCHAR(600) DEFAULT NULL,
    caption              VARCHAR(1000) DEFAULT NULL,
    privacy              ENUM('public','matches_only','private') NOT NULL DEFAULT 'public',
    status               ENUM('pending_scan','active','blocked','deleted','archived') NOT NULL DEFAULT 'pending_scan',
    moderation_status    ENUM('queued','approved','rejected','manual_review') NOT NULL DEFAULT 'queued',
    moderation_confidence DECIMAL(5,4) NOT NULL DEFAULT 0.0000,
    expires_at           DATETIME NOT NULL,
    created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_story_user (user_id),
    INDEX idx_story_status (status),
    INDEX idx_story_expiry (expires_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS user_reels (
    id                   BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id              INT NOT NULL,
    video_url            VARCHAR(600) NOT NULL,
    thumbnail_url        VARCHAR(600) DEFAULT NULL,
    caption              VARCHAR(1000) DEFAULT NULL,
    privacy              ENUM('public','matches_only','private') NOT NULL DEFAULT 'public',
    status               ENUM('pending_scan','active','blocked','deleted','archived') NOT NULL DEFAULT 'pending_scan',
    allow_comments       TINYINT(1) NOT NULL DEFAULT 1,
    allow_duet           TINYINT(1) NOT NULL DEFAULT 0,
    allow_download       TINYINT(1) NOT NULL DEFAULT 0,
    moderation_status    ENUM('queued','approved','rejected','manual_review') NOT NULL DEFAULT 'queued',
    moderation_confidence DECIMAL(5,4) NOT NULL DEFAULT 0.0000,
    created_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at           DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_reel_user (user_id),
    INDEX idx_reel_status (status),
    INDEX idx_reel_created (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS reel_likes (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    reel_id     BIGINT UNSIGNED NOT NULL,
    user_id     INT NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reel_id) REFERENCES user_reels(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uk_reel_like (reel_id, user_id),
    INDEX idx_reel_likes_reel (reel_id),
    INDEX idx_reel_likes_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS reel_comments (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    reel_id     BIGINT UNSIGNED NOT NULL,
    user_id     INT NOT NULL,
    comment     VARCHAR(1000) NOT NULL,
    status      ENUM('active','hidden','deleted') NOT NULL DEFAULT 'active',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (reel_id) REFERENCES user_reels(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_reel_comments_reel (reel_id),
    INDEX idx_reel_comments_user (user_id),
    INDEX idx_reel_comments_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS reel_shares (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    reel_id     BIGINT UNSIGNED NOT NULL,
    user_id     INT NOT NULL,
    share_type  ENUM('copy_link','chat','external') NOT NULL DEFAULT 'copy_link',
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (reel_id) REFERENCES user_reels(id) ON DELETE CASCADE,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_reel_shares_reel (reel_id),
    INDEX idx_reel_shares_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS media_moderation_jobs (
    id                 BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    entity_type        ENUM('story','reel','comment') NOT NULL,
    entity_id          BIGINT UNSIGNED NOT NULL,
    user_id            INT NOT NULL,
    scan_status        ENUM('queued','processing','approved','rejected','manual_review') NOT NULL DEFAULT 'queued',
    scan_result        VARCHAR(100) DEFAULT NULL,
    confidence         DECIMAL(5,4) NOT NULL DEFAULT 0.0000,
    provider           VARCHAR(100) DEFAULT NULL,
    raw_response_json  LONGTEXT DEFAULT NULL,
    created_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at         DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_mj_entity (entity_type, entity_id),
    INDEX idx_mj_status (scan_status),
    INDEX idx_mj_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS media_reports (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    entity_type   ENUM('story','reel','comment') NOT NULL,
    entity_id     BIGINT UNSIGNED NOT NULL,
    reported_by   INT NOT NULL,
    reason        ENUM('sexual','violence','hate','harassment','spam','other') NOT NULL DEFAULT 'other',
    note          VARCHAR(1000) DEFAULT NULL,
    status        ENUM('open','reviewing','resolved','dismissed') NOT NULL DEFAULT 'open',
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (reported_by) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_reports_entity (entity_type, entity_id),
    INDEX idx_reports_status (status),
    INDEX idx_reports_by (reported_by)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
