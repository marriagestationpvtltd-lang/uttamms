-- ============================================================
-- Socket.IO Chat Migration: MySQL Schema
-- Run this on your MySQL database before starting the server.
-- ============================================================

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
  `id`                     BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `message_id`             VARCHAR(100) NOT NULL UNIQUE,
  `chat_room_id`           VARCHAR(150) NOT NULL,
  `sender_id`              VARCHAR(50)  NOT NULL,
  `receiver_id`            VARCHAR(50)  NOT NULL,
  `message`                TEXT,
  `message_type`           VARCHAR(50)  NOT NULL DEFAULT 'text',
  `is_read`                TINYINT(1)   NOT NULL DEFAULT 0,
  `is_delivered`           TINYINT(1)   NOT NULL DEFAULT 0,
  `is_deleted_for_sender`  TINYINT(1)   NOT NULL DEFAULT 0,
  `is_deleted_for_receiver` TINYINT(1)  NOT NULL DEFAULT 0,
  `is_edited`              TINYINT(1)   NOT NULL DEFAULT 0,
  `edited_at`              DATETIME,
  `replied_to`             JSON,
  `created_at`             DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_chat_room_time` (`chat_room_id`, `created_at`),
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
