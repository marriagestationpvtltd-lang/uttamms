-- =============================================================================
-- Migration: Ensure user_activities table exists with all required ENUM values
-- Run this on the live 'ms' database if the table was created before the
-- full set of activity types was added to schema.sql.
-- =============================================================================

-- Step 1: Create the table if it does not already exist (full definition)
CREATE TABLE IF NOT EXISTS user_activities (
    id             INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
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
    target_user_id INT UNSIGNED DEFAULT NULL,
    target_name    VARCHAR(200) DEFAULT NULL,
    user_name      VARCHAR(200) DEFAULT NULL,
    ip_address     VARCHAR(45)  DEFAULT NULL,
    device_info    VARCHAR(255) DEFAULT NULL,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_ua_user_id    (user_id),
    INDEX idx_ua_type       (activity_type),
    INDEX idx_ua_created_at (created_at),
    INDEX idx_ua_target     (target_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Step 2: If the table already exists with an older/smaller ENUM, ALTER it to
--         add the missing values.  MySQL ALTER TABLE MODIFY COLUMN for ENUMs
--         is additive – existing data is preserved.
--
--         Only run this block when Step 1 was a no-op (table already existed).

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

-- Step 3: Add optional columns that may be missing in older installs
-- ADD COLUMN IF NOT EXISTS requires MySQL 8.0.3+; the procedure below is
-- compatible with MySQL 5.7+ by checking information_schema.COLUMNS first.
DROP PROCEDURE IF EXISTS _migrate_add_ua_columns;

DELIMITER //
CREATE PROCEDURE _migrate_add_ua_columns()
BEGIN
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

CALL _migrate_add_ua_columns();
DROP PROCEDURE IF EXISTS _migrate_add_ua_columns;
