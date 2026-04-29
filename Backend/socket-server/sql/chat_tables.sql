-- ============================================================
-- Socket.IO Chat Migration: MySQL Schema
-- Run this on your MySQL database before starting the server.
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
-- ============================================================

SET NAMES utf8mb4;
-- Normalise session timezone so CURRENT_TIMESTAMP values are stored in UTC.
-- Ensure your application layer also reads/writes datetimes in UTC.
SET time_zone             = '+00:00';
-- Prevent silent storage-engine substitution (e.g. MyISAM falling back when
-- InnoDB is unavailable); the import will error instead of silently degrading.
SET sql_mode              = 'NO_ENGINE_SUBSTITUTION';
SET FOREIGN_KEY_CHECKS    = 0;

-- Chat rooms between two users
CREATE TABLE IF NOT EXISTS `chat_rooms` (
  `id`                    VARCHAR(150) NOT NULL,
  `participants`          JSON         NOT NULL,
  `participant_names`     JSON         NOT NULL,
  `participant_images`    JSON         NOT NULL,
  `last_message`          TEXT,
  `last_message_type`     VARCHAR(50)  DEFAULT 'text',
  `last_message_time`     DATETIME     DEFAULT CURRENT_TIMESTAMP,
  `last_message_sender_id` VARCHAR(50) DEFAULT '',
  `created_at`            DATETIME     DEFAULT CURRENT_TIMESTAMP,
  `updated_at`            DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-room unread message counter per user
CREATE TABLE IF NOT EXISTS `chat_unread_counts` (
  `chat_room_id` VARCHAR(150) NOT NULL,
  `user_id`      VARCHAR(50)  NOT NULL,
  `unread_count` INT          NOT NULL DEFAULT 0,
  PRIMARY KEY (`chat_room_id`, `user_id`),
  CONSTRAINT `fk_unread_room` FOREIGN KEY (`chat_room_id`) REFERENCES `chat_rooms` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Individual chat messages
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
  INDEX `idx_chat_room_time` (`chat_room_id`, `created_at`),
  INDEX `idx_created_at`    (`created_at`),
  INDEX `idx_sender`        (`sender_id`),
  INDEX `idx_receiver`      (`receiver_id`),
  CONSTRAINT `fk_msg_room` FOREIGN KEY (`chat_room_id`) REFERENCES `chat_rooms` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- User online status (in-memory in the server, persisted here for last-seen)
CREATE TABLE IF NOT EXISTS `user_online_status` (
  `user_id`             VARCHAR(50)  NOT NULL PRIMARY KEY,
  `is_online`           TINYINT(1)   NOT NULL DEFAULT 0,
  `last_seen`           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  `active_chat_room_id` VARCHAR(150) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Call history log
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

-- Admin-initiated group call sessions with a dynamic participant list
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

-- User activity log (all user actions: likes, messages, calls, logins, etc.)
CREATE TABLE IF NOT EXISTS `user_activities` (
  `id`            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `user_id`       INT          NOT NULL,
  `user_name`     VARCHAR(200) DEFAULT '',
  `target_id`     INT          DEFAULT NULL,
  `target_name`   VARCHAR(200) DEFAULT NULL,
  `activity_type` ENUM(
    'like_sent','like_removed',
    'message_sent',
    'request_sent','request_accepted','request_rejected',
    'call_made','call_received',
    'profile_viewed',
    'login','logout',
    'photo_uploaded',
    'package_bought'
  ) NOT NULL,
  `description`   TEXT,
  `created_at`    DATETIME     DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_ua_user_id`       (`user_id`),
  INDEX `idx_ua_created_at`    (`created_at`),
  INDEX `idx_ua_activity_type` (`activity_type`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- User block list (blocker → blocked)
CREATE TABLE IF NOT EXISTS `blocks` (
  `id`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `blocker_id` INT NOT NULL,
  `blocked_id` INT NOT NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  UNIQUE KEY `uq_block`    (`blocker_id`, `blocked_id`),
  INDEX `idx_blocker` (`blocker_id`),
  INDEX `idx_blocked` (`blocked_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

SET FOREIGN_KEY_CHECKS = 1;

-- ============================================================
-- After importing, verify all tables were created by running
-- the following query manually in your MySQL client or
-- phpMyAdmin SQL tab (do NOT include it in this import file):
--
--   SHOW TABLES LIKE 'chat_%';
--   SHOW TABLES LIKE 'user_%';
--   SHOW TABLES LIKE 'call_%';
--   SHOW TABLES LIKE 'group_%';
--   SHOW TABLES LIKE 'blocks';
--
-- Expected tables: chat_rooms, chat_unread_counts,
--   chat_messages, user_online_status, call_history,
--   group_calls, user_activities, blocks
-- ============================================================
