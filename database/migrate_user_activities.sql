-- =============================================================================
-- Migration: Ensure user_activities and call_history tables are up-to-date
-- Run this on the live 'ms' database after pulling the latest schema changes.
-- Safe to re-run: all steps are idempotent (IF NOT EXISTS / IF EXISTS guards).
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1 – user_activities
-- ─────────────────────────────────────────────────────────────────────────────

-- Step 1: Create the table if it does not already exist (canonical definition).
--         Uses `target_id` – the correct column name used everywhere in code.
CREATE TABLE IF NOT EXISTS user_activities (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id        INT UNSIGNED NOT NULL,
    activity_type  ENUM(
        'login',
        'logout',
        'profile_view',
        'search',
        'proposal_sent',
        'proposal_accepted',
        'proposal_rejected',
        'call_initiated',
        'call_received',
        'call_ended',
        'custom_tone_set',
        'custom_tone_removed',
        'settings_changed',
        'like_sent',
        'like_removed',
        'message_sent',
        'request_sent',
        'request_accepted',
        'request_rejected',
        'call_made',
        'photo_uploaded',
        'package_bought',
        'other'
    ) NOT NULL DEFAULT 'other',
    description    VARCHAR(500) DEFAULT NULL,
    target_id      INT UNSIGNED DEFAULT NULL,
    target_name    VARCHAR(200) DEFAULT NULL,
    user_name      VARCHAR(200) DEFAULT NULL,
    ip_address     VARCHAR(45)  DEFAULT NULL,
    device_info    VARCHAR(255) DEFAULT NULL,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_ua_user_id    (user_id),
    INDEX idx_ua_type       (activity_type),
    INDEX idx_ua_created_at (created_at),
    INDEX idx_ua_target     (target_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Step 2: Expand the ENUM to include all required activity types.
--         MySQL MODIFY COLUMN for ENUMs is additive – existing data is preserved.
ALTER TABLE user_activities
    MODIFY COLUMN activity_type ENUM(
        'login',
        'logout',
        'profile_view',
        'search',
        'proposal_sent',
        'proposal_accepted',
        'proposal_rejected',
        'call_initiated',
        'call_received',
        'call_ended',
        'custom_tone_set',
        'custom_tone_removed',
        'settings_changed',
        'like_sent',
        'like_removed',
        'message_sent',
        'request_sent',
        'request_accepted',
        'request_rejected',
        'call_made',
        'photo_uploaded',
        'package_bought',
        'other'
    ) NOT NULL DEFAULT 'other';

-- Step 3: Rename target_user_id → target_id on installs that used the old name,
--         and add any missing optional columns.
-- Uses a stored procedure for MySQL 5.7 compatibility (no ADD COLUMN IF NOT EXISTS).
DROP PROCEDURE IF EXISTS _migrate_ua_columns;

DELIMITER //
CREATE PROCEDURE _migrate_ua_columns()
BEGIN
    -- Rename target_user_id → target_id if the old column still exists
    IF EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND COLUMN_NAME  = 'target_user_id'
    ) THEN
        ALTER TABLE user_activities
            CHANGE COLUMN target_user_id target_id INT UNSIGNED DEFAULT NULL;
    END IF;

    -- Drop the old index (idx_ua_target_user) if it still exists after the rename
    IF EXISTS (
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND INDEX_NAME   = 'idx_ua_target_user'
    ) THEN
        ALTER TABLE user_activities DROP INDEX idx_ua_target_user;
    END IF;

    -- Ensure idx_ua_target index exists on the (now correctly named) target_id column
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND INDEX_NAME   = 'idx_ua_target'
    ) THEN
        ALTER TABLE user_activities ADD INDEX idx_ua_target (target_id);
    END IF;

    -- Add target_id column if neither target_id nor target_user_id exist yet
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND COLUMN_NAME  = 'target_id'
    ) THEN
        ALTER TABLE user_activities ADD COLUMN target_id INT UNSIGNED DEFAULT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND COLUMN_NAME  = 'target_name'
    ) THEN
        ALTER TABLE user_activities ADD COLUMN target_name VARCHAR(200) DEFAULT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND COLUMN_NAME  = 'user_name'
    ) THEN
        ALTER TABLE user_activities ADD COLUMN user_name VARCHAR(200) DEFAULT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'user_activities'
          AND COLUMN_NAME  = 'device_info'
    ) THEN
        ALTER TABLE user_activities ADD COLUMN device_info VARCHAR(255) DEFAULT NULL;
    END IF;
END //
DELIMITER ;

CALL _migrate_ua_columns();
DROP PROCEDURE IF EXISTS _migrate_ua_columns;

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2 – call_history  (Agora Cloud Recording columns)
-- ─────────────────────────────────────────────────────────────────────────────

-- Ensure the table exists (matches the canonical definition in schema.sql).
CREATE TABLE IF NOT EXISTS call_history (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    call_id                 VARCHAR(100)  NOT NULL UNIQUE,
    caller_id               VARCHAR(50)   NOT NULL,
    caller_name             VARCHAR(200)  DEFAULT '',
    caller_image            VARCHAR(500)  DEFAULT '',
    recipient_id            VARCHAR(50)   NOT NULL,
    recipient_name          VARCHAR(200)  DEFAULT '',
    recipient_image         VARCHAR(500)  DEFAULT '',
    call_type               ENUM('audio','video') NOT NULL DEFAULT 'audio',
    start_time              DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time                DATETIME      DEFAULT NULL,
    duration                INT           NOT NULL DEFAULT 0,
    status                  ENUM('completed','missed','declined','cancelled') NOT NULL DEFAULT 'missed',
    initiated_by            VARCHAR(50)   NOT NULL,
    recording_uid           VARCHAR(200)  DEFAULT NULL,
    recording_sid           VARCHAR(200)  DEFAULT NULL,
    recording_resource_id   VARCHAR(500)  DEFAULT NULL,
    recording_url           VARCHAR(1000) DEFAULT NULL,
    INDEX idx_ch_caller    (caller_id),
    INDEX idx_ch_recipient (recipient_id),
    INDEX idx_ch_start     (start_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Add recording columns to existing call_history installs that pre-date the recording feature.
DROP PROCEDURE IF EXISTS _migrate_call_history_columns;

DELIMITER //
CREATE PROCEDURE _migrate_call_history_columns()
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'call_history'
          AND COLUMN_NAME  = 'recording_uid'
    ) THEN
        ALTER TABLE call_history ADD COLUMN recording_uid VARCHAR(200) DEFAULT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'call_history'
          AND COLUMN_NAME  = 'recording_sid'
    ) THEN
        ALTER TABLE call_history ADD COLUMN recording_sid VARCHAR(200) DEFAULT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'call_history'
          AND COLUMN_NAME  = 'recording_resource_id'
    ) THEN
        ALTER TABLE call_history ADD COLUMN recording_resource_id VARCHAR(500) DEFAULT NULL;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'call_history'
          AND COLUMN_NAME  = 'recording_url'
    ) THEN
        ALTER TABLE call_history ADD COLUMN recording_url VARCHAR(1000) DEFAULT NULL;
    END IF;
END //
DELIMITER ;

CALL _migrate_call_history_columns();
DROP PROCEDURE IF EXISTS _migrate_call_history_columns;
