-- ============================================================
-- Marriage Station – Complete Chat System SQL Schema
--
-- This single file covers ALL tables required by both the
-- Socket.IO real-time chat server and the admin chat panel.
--
-- HOW TO IMPORT
-- Option A (recommended) – MySQL CLI:
--   mysql -u <user> -p <your_database> < chat_tables.sql
--
-- Option B – MySQL CLI interactive:
--   mysql -u <user> -p
--   USE <your_database>;
--   SOURCE /path/to/chat_tables.sql
--
-- Option C – phpMyAdmin:
--   1. Select your database in the left panel (NOT information_schema).
--   2. Click "Import" and upload this file.
--
-- TABLE SUMMARY
-- ── Socket.IO / User-to-User Chat ─────────────────────────────
--   1.  chat_rooms              – chat rooms between two users
--   2.  chat_unread_counts      – per-room unread counter per user
--   3.  chat_messages           – individual messages
--   4.  user_online_status      – online/last-seen status
--   5.  call_history            – 1-on-1 audio/video call log
--   6.  group_calls             – admin-initiated group call sessions
--   7.  user_activities         – all user-action log
--   8.  blocks                  – user block list
-- ── Admin Chat Panel ──────────────────────────────────────────
--   9.  agent_users             – admin panel agents / operators
--   10. ac_memorial_profiles    – matrimony profiles shared in chats
--   11. ac_chats                – agent ↔ contact conversation threads
--   12. ac_messages             – individual admin-chat messages
--   13. ac_profile_shares       – profile-share tracking
-- ============================================================

SET NAMES utf8mb4;
-- Normalise session timezone so CURRENT_TIMESTAMP values are stored in UTC.
-- Ensure your application layer also reads/writes datetimes in UTC.
SET time_zone             = '+00:00';
-- Prevent silent storage-engine substitution (e.g. MyISAM falling back when
-- InnoDB is unavailable); the import will error instead of silently degrading.
SET sql_mode              = 'NO_ENGINE_SUBSTITUTION';
SET FOREIGN_KEY_CHECKS    = 0;

-- ============================================================
-- SECTION 1 – SOCKET.IO / USER-TO-USER CHAT
-- ============================================================

-- 1. Chat rooms between two users
CREATE TABLE IF NOT EXISTS `chat_rooms` (
  `id`                     VARCHAR(150) NOT NULL,
  `participants`           JSON         NOT NULL,
  `participant_names`      JSON         NOT NULL,
  `participant_images`     JSON         NOT NULL,
  `last_message`           TEXT,
  `last_message_type`      VARCHAR(50)  DEFAULT 'text',
  `last_message_time`      DATETIME     DEFAULT CURRENT_TIMESTAMP,
  `last_message_sender_id` VARCHAR(50)  DEFAULT '',
  `created_at`             DATETIME     DEFAULT CURRENT_TIMESTAMP,
  `updated_at`             DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 2. Per-room unread message counter per user
CREATE TABLE IF NOT EXISTS `chat_unread_counts` (
  `chat_room_id` VARCHAR(150) NOT NULL,
  `user_id`      VARCHAR(50)  NOT NULL,
  `unread_count` INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (`chat_room_id`, `user_id`),
  CONSTRAINT `fk_unread_room` FOREIGN KEY (`chat_room_id`) REFERENCES `chat_rooms` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 3. Individual chat messages
CREATE TABLE IF NOT EXISTS `chat_messages` (
  `id`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `message_id`              VARCHAR(100) NOT NULL UNIQUE,
  `chat_room_id`            VARCHAR(150) NOT NULL,
  `sender_id`               VARCHAR(50)  NOT NULL,
  `receiver_id`             VARCHAR(50)  NOT NULL,
  `message`                 TEXT,
  `message_type`            VARCHAR(50)  NOT NULL DEFAULT 'text',
  `is_read`                 TINYINT(1)   NOT NULL DEFAULT 0,
  `is_delivered`            TINYINT(1)   NOT NULL DEFAULT 0,
  `is_deleted_for_sender`   TINYINT(1)   NOT NULL DEFAULT 0,
  `is_deleted_for_receiver` TINYINT(1)   NOT NULL DEFAULT 0,
  `is_edited`               TINYINT(1)   NOT NULL DEFAULT 0,
  `edited_at`               DATETIME,
  `replied_to`              JSON,
  `liked`                   TINYINT(1)   NOT NULL DEFAULT 0,
  `is_unsent`               TINYINT(1)   NOT NULL DEFAULT 0,
  `reactions`               TEXT         NULL DEFAULT NULL,
  `created_at`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_chat_room_time`        (`chat_room_id`, `created_at`),
  INDEX `idx_created_at`            (`created_at`),
  INDEX `idx_sender`                (`sender_id`),
  INDEX `idx_receiver`              (`receiver_id`),
  INDEX `idx_sender_receiver_time`  (`sender_id`, `receiver_id`, `created_at`),
  CONSTRAINT `fk_msg_room` FOREIGN KEY (`chat_room_id`) REFERENCES `chat_rooms` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 4. User online status (persisted for last-seen)
CREATE TABLE IF NOT EXISTS `user_online_status` (
  `user_id`             VARCHAR(50)  NOT NULL PRIMARY KEY,
  `is_online`           TINYINT(1)   NOT NULL DEFAULT 0,
  `last_seen`           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `active_chat_room_id` VARCHAR(150) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 5. 1-on-1 audio/video call history log
CREATE TABLE IF NOT EXISTS `call_history` (
  `id`              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `call_id`         VARCHAR(100) NOT NULL UNIQUE,
  `caller_id`       VARCHAR(50)  NOT NULL,
  `caller_name`     VARCHAR(200) DEFAULT '',
  `caller_image`    VARCHAR(500) DEFAULT '',
  `recipient_id`    VARCHAR(50)  NOT NULL,
  `recipient_name`  VARCHAR(200) DEFAULT '',
  `recipient_image` VARCHAR(500) DEFAULT '',
  `call_type`       ENUM('audio', 'video') NOT NULL DEFAULT 'audio',
  `start_time`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `end_time`        DATETIME     DEFAULT NULL,
  `duration`        INT          NOT NULL DEFAULT 0,
  `status`          ENUM('completed', 'missed', 'declined', 'cancelled') NOT NULL DEFAULT 'missed',
  `initiated_by`    VARCHAR(50)  NOT NULL,
  INDEX `idx_caller`     (`caller_id`),
  INDEX `idx_recipient`  (`recipient_id`),
  INDEX `idx_start_time` (`start_time`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 6. Admin-initiated group call sessions with a dynamic participant list
CREATE TABLE IF NOT EXISTS `group_calls` (
  `id`           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `channel_name` VARCHAR(150) NOT NULL UNIQUE,
  `call_type`    ENUM('audio', 'video') NOT NULL DEFAULT 'audio',
  `admin_id`     VARCHAR(50)  NOT NULL DEFAULT '1',
  `participants` JSON         NOT NULL,
  `status`       ENUM('active', 'ended') NOT NULL DEFAULT 'active',
  `started_at`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `ended_at`     DATETIME     DEFAULT NULL,
  INDEX `idx_gc_channel` (`channel_name`),
  INDEX `idx_gc_admin`   (`admin_id`),
  INDEX `idx_gc_started` (`started_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 7. User activity log (all user actions: likes, messages, calls, logins, etc.)
CREATE TABLE IF NOT EXISTS `user_activities` (
  `id`            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id`       INT          NOT NULL,
  `user_name`     VARCHAR(200) DEFAULT '',
  `target_id`     INT          DEFAULT NULL,
  `target_name`   VARCHAR(200) DEFAULT NULL,
  `activity_type` ENUM(
    'like_sent', 'like_removed',
    'message_sent',
    'request_sent', 'request_accepted', 'request_rejected',
    'call_made', 'call_received',
    'profile_viewed',
    'login', 'logout',
    'photo_uploaded',
    'package_bought'
  ) NOT NULL,
  `description`   TEXT,
  `created_at`    DATETIME     DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_ua_user_id`       (`user_id`),
  INDEX `idx_ua_created_at`    (`created_at`),
  INDEX `idx_ua_activity_type` (`activity_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 8. User block list (blocker → blocked)
CREATE TABLE IF NOT EXISTS `blocks` (
  `id`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `blocker_id` INT NOT NULL,
  `blocked_id` INT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_block`   (`blocker_id`, `blocked_id`),
  INDEX `idx_blocker` (`blocker_id`),
  INDEX `idx_blocked` (`blocked_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ============================================================
-- SECTION 2 – ADMIN CHAT PANEL
-- ============================================================

-- 9. Admin panel agents / operators
CREATE TABLE IF NOT EXISTS `agent_users` (
  `id`            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `username`      VARCHAR(100) NOT NULL,
  `email`         VARCHAR(255) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `avatar_url`    VARCHAR(500) DEFAULT NULL,
  `role`          ENUM('admin', 'agent') NOT NULL DEFAULT 'agent',
  `status`        ENUM('active', 'inactive') NOT NULL DEFAULT 'active',
  `last_login`    DATETIME DEFAULT NULL,
  `created_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_au_username` (`username`),
  UNIQUE KEY `uk_au_email`    (`email`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Default agent user (password: admin — CHANGE IMMEDIATELY after first deploy)
INSERT IGNORE INTO `agent_users` (`id`, `username`, `email`, `password_hash`, `role`) VALUES
  (1, 'agent', 'agent@marriagestation.com',
   '$2y$10$UgRVAVqW2RmLi.x2UEcYtuBW7yxx3wGq2cGEV/JTtQtX1le40g7eG',
   'admin');

-- 10. Matrimony profiles shared inside admin chats
CREATE TABLE IF NOT EXISTS `ac_memorial_profiles` (
  `id`                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`              VARCHAR(255) NOT NULL,
  `avatar_url`        VARCHAR(500) DEFAULT NULL,
  `match_percentage`  INT UNSIGNED NOT NULL DEFAULT 0,
  `membership_status` ENUM('free', 'paid') NOT NULL DEFAULT 'free',
  `status`            ENUM('newProfile', 'alreadySent') NOT NULL DEFAULT 'newProfile',
  `created_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_acmp_membership` (`membership_status`),
  INDEX `idx_acmp_match`      (`match_percentage`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 11. Agent ↔ contact conversation threads
CREATE TABLE IF NOT EXISTS `ac_chats` (
  `id`               VARCHAR(20)  NOT NULL,
  `name`             VARCHAR(255) NOT NULL DEFAULT '',
  `contact_id`       VARCHAR(100) DEFAULT NULL,
  `avatar_url`       VARCHAR(500) DEFAULT NULL,
  `last_message`     TEXT         DEFAULT NULL,
  `last_message_time` VARCHAR(20) DEFAULT NULL,
  `is_pinned`        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
  `is_unread`        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
  `is_group`         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
  `has_file`         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
  `membership_status` ENUM('free', 'paid', 'expired') NOT NULL DEFAULT 'free',
  `assigned_to`      INT UNSIGNED DEFAULT NULL,
  `created_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  INDEX `idx_acch_pinned`   (`is_pinned`),
  INDEX `idx_acch_updated`  (`updated_at`),
  INDEX `idx_acch_assigned` (`assigned_to`),
  FOREIGN KEY (`assigned_to`) REFERENCES `agent_users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 12. Individual messages within an admin chat
CREATE TABLE IF NOT EXISTS `ac_messages` (
  `id`                VARCHAR(100) NOT NULL,
  `chat_id`           VARCHAR(20)  NOT NULL,
  `sender_id`         INT UNSIGNED DEFAULT NULL,
  `sender_type`       ENUM('agent', 'contact') NOT NULL DEFAULT 'agent',
  `message_type`      ENUM('text', 'image', 'file', 'profile') NOT NULL DEFAULT 'text',
  `text_content`      TEXT         DEFAULT NULL,
  `shared_profile_id` INT UNSIGNED DEFAULT NULL,
  `is_read`           TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
  `created_at`        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  FOREIGN KEY (`chat_id`)           REFERENCES `ac_chats` (`id`)              ON DELETE CASCADE,
  FOREIGN KEY (`sender_id`)         REFERENCES `agent_users` (`id`)           ON DELETE SET NULL,
  FOREIGN KEY (`shared_profile_id`) REFERENCES `ac_memorial_profiles` (`id`) ON DELETE SET NULL,
  INDEX `idx_acmsg_chat`       (`chat_id`),
  INDEX `idx_acmsg_created_at` (`chat_id`, `created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- 13. Profile-share tracking (which profiles were shared in which admin chats)
CREATE TABLE IF NOT EXISTS `ac_profile_shares` (
  `id`         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `chat_id`    VARCHAR(20)  NOT NULL,
  `profile_id` INT UNSIGNED NOT NULL,
  `shared_by`  INT UNSIGNED DEFAULT NULL,
  `shared_at`  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uk_acps_chat_profile` (`chat_id`, `profile_id`),
  FOREIGN KEY (`chat_id`)    REFERENCES `ac_chats` (`id`)              ON DELETE CASCADE,
  FOREIGN KEY (`profile_id`) REFERENCES `ac_memorial_profiles` (`id`) ON DELETE CASCADE,
  FOREIGN KEY (`shared_by`)  REFERENCES `agent_users` (`id`)          ON DELETE SET NULL,
  INDEX `idx_acps_chat`    (`chat_id`),
  INDEX `idx_acps_profile` (`profile_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- After importing, verify all tables were created by running
-- the following queries manually in your MySQL client or
-- phpMyAdmin SQL tab (do NOT include them in this import file):
--
--   SHOW TABLES LIKE 'chat_%';
--   SHOW TABLES LIKE 'user_%';
--   SHOW TABLES LIKE 'call_%';
--   SHOW TABLES LIKE 'group_%';
--   SHOW TABLES LIKE 'blocks';
--   SHOW TABLES LIKE 'agent_%';
--   SHOW TABLES LIKE 'ac_%';
--
-- Expected 13 tables:
--   chat_rooms, chat_unread_counts, chat_messages,
--   user_online_status, call_history, group_calls,
--   user_activities, blocks,
--   agent_users, ac_memorial_profiles, ac_chats,
--   ac_messages, ac_profile_shares
-- ============================================================
