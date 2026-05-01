-- =============================================================================
-- Marriage Station – Consolidated Migrations
-- Run this script once against any existing database that was created from an
-- older version of schema.sql to bring it up to date.
--
-- All statements are idempotent: safe to re-run on a database that is already
-- fully up to date.
--
-- Sections (in dependency order):
--   1. admins           – add username column
--   2. user_documents   – per-document status tracking
--   3. user_activities  – full ENUM + optional columns
--   4. chat_messages    – add is_unsent column
--   5. chat_rooms       – normalize participants to string arrays (data fix)
--   6. user_online_status – add socket_id column + is_online index
--   7. chat_messages    – add delivered_at, read_at columns + unread index
--   8. group_call_members – create table for per-member group-call tracking
--   9. user_settings    – create key-value settings table
--  9b. app_settings     – create global app key-value settings table (call-tone)
--  10. users            – add isOnline index
--  11. DROP obsolete legacy tables (safe, all guarded with IF EXISTS)
-- =============================================================================

-- =============================================================================
-- 1. admins – add username column
-- =============================================================================

-- Step 1a: Add the username column (nullable initially so existing rows don't
--          violate NOT NULL).  Guard with INFORMATION_SCHEMA so it is idempotent.
SET @_add_admin_username = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE admins ADD COLUMN username VARCHAR(100) NULL AFTER id',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'admins'
      AND COLUMN_NAME  = 'username'
);
PREPARE _stmt FROM @_add_admin_username;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Step 1b: Back-fill username from the email local-part for any existing rows.
UPDATE admins
SET username = SUBSTRING_INDEX(email, '@', 1)
WHERE username IS NULL;

-- Step 1c: Make the column NOT NULL and add the unique constraint.
--          MODIFY COLUMN is safe to re-run (idempotent).
ALTER TABLE admins
    MODIFY COLUMN username VARCHAR(100) NOT NULL;

-- Step 1d: Add unique constraint if it does not already exist.
SET @_add_admin_uk = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE admins ADD CONSTRAINT uk_admin_username UNIQUE (username)',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'admins'
      AND INDEX_NAME   = 'uk_admin_username'
);
PREPARE _stmt FROM @_add_admin_uk;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Step 1e: Ensure the default admin row has the standard username.
UPDATE admins
SET username = 'admin'
WHERE email = 'admin@ms.com'
  AND (username IS NULL OR username = '');

-- =============================================================================
-- 2. user_documents – per-document status tracking
-- =============================================================================

-- Step 2a: Add reject_reason column.
SET @_add_reject_reason = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_documents ADD COLUMN reject_reason VARCHAR(500) DEFAULT NULL AFTER status',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_documents'
      AND COLUMN_NAME  = 'reject_reason'
);
PREPARE _stmt FROM @_add_reject_reason;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Step 2b: Ensure documenttype is NOT NULL.
--          Back-fill any NULL rows with a placeholder first.
UPDATE user_documents SET documenttype = 'Legacy_Document' WHERE documenttype IS NULL;
ALTER TABLE user_documents
    MODIFY COLUMN documenttype VARCHAR(100) NOT NULL;

-- Step 2c: Drop the old single-user unique key (one doc per user).
SET @_drop_idx_uk_userid = (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE user_documents DROP INDEX uk_userid',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_documents'
      AND INDEX_NAME   = 'uk_userid'
);
PREPARE _stmt FROM @_drop_idx_uk_userid;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Step 2d: Add composite unique key (one row per user per document type).
SET @_add_idx_uk_userid_doctype = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_documents ADD UNIQUE KEY uk_userid_doctype (userid, documenttype)',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_documents'
      AND INDEX_NAME   = 'uk_userid_doctype'
);
PREPARE _stmt FROM @_add_idx_uk_userid_doctype;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Step 2e: Remove legacy columns doc_type and doc_url if they exist.
SET @_drop_col_doc_type = (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE user_documents DROP COLUMN doc_type',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_documents'
      AND COLUMN_NAME  = 'doc_type'
);
PREPARE _stmt FROM @_drop_col_doc_type;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

SET @_drop_col_doc_url = (
    SELECT IF(
        COUNT(*) > 0,
        'ALTER TABLE user_documents DROP COLUMN doc_url',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_documents'
      AND COLUMN_NAME  = 'doc_url'
);
PREPARE _stmt FROM @_drop_col_doc_url;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- =============================================================================
-- 3. user_activities – full ENUM + optional columns
-- =============================================================================

-- Step 3a: Create the table if it does not already exist.
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

-- Step 3b: If the table already existed with an older ENUM, expand it.
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

-- Step 3c: Add optional columns that may be missing in older installs.
SET @_add_ua_target_name = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_activities ADD COLUMN target_name VARCHAR(200) DEFAULT NULL',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_activities'
      AND COLUMN_NAME  = 'target_name'
);
PREPARE _stmt FROM @_add_ua_target_name;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

SET @_add_ua_user_name = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_activities ADD COLUMN user_name VARCHAR(200) DEFAULT NULL',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_activities'
      AND COLUMN_NAME  = 'user_name'
);
PREPARE _stmt FROM @_add_ua_user_name;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

SET @_add_ua_device_info = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_activities ADD COLUMN device_info VARCHAR(255) DEFAULT NULL',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_activities'
      AND COLUMN_NAME  = 'device_info'
);
PREPARE _stmt FROM @_add_ua_device_info;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- =============================================================================
-- 4. chat_messages – add is_unsent column
-- =============================================================================

SET @_add_is_unsent = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE chat_messages ADD COLUMN is_unsent TINYINT(1) NOT NULL DEFAULT 0',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'chat_messages'
      AND COLUMN_NAME  = 'is_unsent'
);
PREPARE _stmt FROM @_add_is_unsent;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- =============================================================================
-- 5. chat_rooms – normalize participants to string arrays (data fix)
--
-- Problem: Some chat rooms were created with numeric participant IDs
--   (e.g. [123, 456]) instead of string IDs (e.g. ["123", "456"]).
--   MySQL's JSON_CONTAINS with JSON_QUOTE() only matches string values,
--   so those rooms were invisible in getChatRooms() queries.
-- Fix: Convert any numeric values in the participants array to strings.
--   Safe to re-run (idempotent via WHERE clause).
-- =============================================================================

UPDATE chat_rooms cr
JOIN (
    SELECT
        base.id,
        JSON_ARRAYAGG(CAST(jt.pid AS CHAR)) AS new_participants
    FROM chat_rooms base
    JOIN JSON_TABLE(
        base.participants,
        '$[*]' COLUMNS (pid BIGINT PATH '$')
    ) AS jt ON TRUE
    WHERE JSON_TYPE(JSON_EXTRACT(base.participants, '$[0]')) = 'INTEGER'
    GROUP BY base.id
) sub ON cr.id = sub.id
SET cr.participants = sub.new_participants;

-- =============================================================================
-- 6. user_online_status – add socket_id column
-- =============================================================================

SET @_add_socket_id = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_online_status ADD COLUMN socket_id VARCHAR(255) DEFAULT NULL',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_online_status'
      AND COLUMN_NAME  = 'socket_id'
);
PREPARE _stmt FROM @_add_socket_id;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Add index on is_online for fast online-user lookups.
SET @_add_uos_online_idx = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_online_status ADD INDEX idx_uos_online (is_online)',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_online_status'
      AND INDEX_NAME   = 'idx_uos_online'
);
PREPARE _stmt FROM @_add_uos_online_idx;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- =============================================================================
-- 7. chat_messages – add delivered_at and read_at timestamp columns
-- =============================================================================

SET @_add_cm_delivered_at = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE chat_messages ADD COLUMN delivered_at DATETIME DEFAULT NULL AFTER reactions',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'chat_messages'
      AND COLUMN_NAME  = 'delivered_at'
);
PREPARE _stmt FROM @_add_cm_delivered_at;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

SET @_add_cm_read_at = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE chat_messages ADD COLUMN read_at DATETIME DEFAULT NULL AFTER delivered_at',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'chat_messages'
      AND COLUMN_NAME  = 'read_at'
);
PREPARE _stmt FROM @_add_cm_read_at;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- Composite index for fast unread-count queries per receiver.
SET @_add_cm_receiver_read_idx = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE chat_messages ADD INDEX idx_cm_receiver_read (receiver_id, is_read)',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'chat_messages'
      AND INDEX_NAME   = 'idx_cm_receiver_read'
);
PREPARE _stmt FROM @_add_cm_receiver_read_idx;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- =============================================================================
-- 8. group_call_members – create table for per-member group-call tracking
-- =============================================================================

CREATE TABLE IF NOT EXISTS group_call_members (
    id            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    group_call_id BIGINT UNSIGNED NOT NULL,
    user_id       VARCHAR(50)  NOT NULL,
    user_name     VARCHAR(200) DEFAULT NULL,
    joined_at     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    left_at       DATETIME     DEFAULT NULL,
    status        ENUM('active','left') NOT NULL DEFAULT 'active',
    FOREIGN KEY (group_call_id) REFERENCES group_calls(id) ON DELETE CASCADE,
    INDEX idx_gcm_call (group_call_id),
    INDEX idx_gcm_user (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- 9. user_settings – create key-value settings table
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_settings (
    id            INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id       INT UNSIGNED NOT NULL,
    setting_key   VARCHAR(100) NOT NULL,
    setting_value TEXT         DEFAULT NULL,
    created_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_us_user_key (user_id, setting_key),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_us_user_id (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 9b. app_settings – global key-value store for application-wide settings
--     (used by api9/upload_call_tone.php and api9/update_app_settings.php)
-- =============================================================================

CREATE TABLE IF NOT EXISTS app_settings (
    `setting_key`   VARCHAR(100) NOT NULL PRIMARY KEY,
    `setting_value` TEXT         DEFAULT NULL,
    `updated_at`    DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Seed default call-tone settings (INSERT IGNORE is idempotent)
INSERT IGNORE INTO app_settings (`setting_key`, `setting_value`) VALUES
    ('call_tone_id',          'default'),
    ('custom_call_tone_url',  ''),
    ('custom_call_tone_name', '');

-- =============================================================================
-- 10. users – add index on isOnline for fast online-user lookups
-- =============================================================================

SET @_add_users_isonline_idx = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE users ADD INDEX idx_isonline (isOnline)',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.STATISTICS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'users'
      AND INDEX_NAME   = 'idx_isonline'
);
PREPARE _stmt FROM @_add_users_isonline_idx;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- =============================================================================
-- 11. DROP obsolete legacy tables
--
-- These tables existed in the original database but have been superseded by
-- newer equivalents (or were never used in the current codebase). They are safe
-- to remove because:
--   a) No current Backend PHP/JS file queries them.
--   b) Their data (if any) is either meaningless or already migrated to the
--      replacement table.
--
-- All statements use IF EXISTS so this section is fully idempotent and safe to
-- re-run. FOREIGN_KEY_CHECKS is disabled for the duration of this section so
-- that the drops succeed regardless of any residual FK references.
--
-- TABLES THAT ARE *NOT* DROPPED HERE (still used by Backend/profile/* scripts):
--   annualincome, diet, documenttype, educationmedium, employmenttype,
--   images, memorial_profiles, profile_shares, userdocument, userfamilydetail
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 0;
-- Note: disabling FK checks is safe here because we are only *dropping* tables,
-- not inserting or updating data.  All tables listed below are obsolete orphans
-- whose FK children (if any) are either also dropped in this section or have
-- already had their FK columns NULLified / removed in earlier migrations.
-- MySQL will NOT corrupt data on other tables by dropping a table that is
-- referenced as a parent; it simply removes the FK definition from the child.

-- ── Old / prototype chat tables (superseded by chat_rooms + chat_messages) ──
DROP TABLE IF EXISTS `chat`;
DROP TABLE IF EXISTS `chats`;
DROP TABLE IF EXISTS `userchat`;
DROP TABLE IF EXISTS `userchats`;
DROP TABLE IF EXISTS `messages`;

-- ── Old user auth tables (superseded by user_tokens + password_resets) ──
DROP TABLE IF EXISTS `userauthdata`;
DROP TABLE IF EXISTS `userotp`;
DROP TABLE IF EXISTS `userrefreshtoken`;
DROP TABLE IF EXISTS `usertokens`;

-- ── Old activity / social tables (superseded by newer equivalents) ──
DROP TABLE IF EXISTS `userproposals`;           -- superseded by proposals (data already in proposals table)
DROP TABLE IF EXISTS `usernotifications`;        -- superseded by user_notifications (data already in user_notifications)
DROP TABLE IF EXISTS `userviewprofilehistories`; -- superseded by profile_view
DROP TABLE IF EXISTS `profile_views`;            -- superseded by profile_view
DROP TABLE IF EXISTS `userfavourites`;
DROP TABLE IF EXISTS `userblockrequest`;

-- ── Old user profile tables (superseded by structured columns) ──
DROP TABLE IF EXISTS `userastrologicdetail`;     -- superseded by user_astrologic
DROP TABLE IF EXISTS `userpersonaldetailcustomdata`;
DROP TABLE IF EXISTS `userdevicedetail`;
DROP TABLE IF EXISTS `userflags`;
DROP TABLE IF EXISTS `userflagvalues`;
DROP TABLE IF EXISTS `userroles`;
DROP TABLE IF EXISTS `userpages`;

-- ── Old wallet / payment tables (feature not implemented) ──
DROP TABLE IF EXISTS `userwallethistory`;
DROP TABLE IF EXISTS `userwallets`;
DROP TABLE IF EXISTS `payment`;
DROP TABLE IF EXISTS `paymentgateway`;
DROP TABLE IF EXISTS `coupons`;
DROP TABLE IF EXISTS `packagecoupons`;
DROP TABLE IF EXISTS `packageduration`;
DROP TABLE IF EXISTS `packagefacility`;
DROP TABLE IF EXISTS `currencies`;
DROP TABLE IF EXISTS `currencypaymentgateway`;
DROP TABLE IF EXISTS `package`;                  -- superseded by packagelist

-- ── Old geographic duplicates (superseded by districts + state + countries) ──
DROP TABLE IF EXISTS `cities`;                   -- superseded by districts
DROP TABLE IF EXISTS `city`;                     -- superseded by districts

-- ── Old CMS / admin content tables (features removed) ──
DROP TABLE IF EXISTS `blogs`;
DROP TABLE IF EXISTS `pages`;
DROP TABLE IF EXISTS `successstories`;
DROP TABLE IF EXISTS `feedback`;
DROP TABLE IF EXISTS `customnotification`;
DROP TABLE IF EXISTS `application`;
DROP TABLE IF EXISTS `authproviders`;

-- ── Old misc lookup / configuration tables (not referenced anywhere) ──
DROP TABLE IF EXISTS `registrationscreens`;
DROP TABLE IF EXISTS `questioncategories`;
DROP TABLE IF EXISTS `questions`;
DROP TABLE IF EXISTS `roles`;
DROP TABLE IF EXISTS `systemflags`;
DROP TABLE IF EXISTS `flaggroup`;
DROP TABLE IF EXISTS `valuetypes`;
DROP TABLE IF EXISTS `timeduration`;
DROP TABLE IF EXISTS `preferenceweightage`;
DROP TABLE IF EXISTS `premiumfacility`;
DROP TABLE IF EXISTS `profilefor`;
DROP TABLE IF EXISTS `customfields`;
DROP TABLE IF EXISTS `customers`;
DROP TABLE IF EXISTS `delete_request`;
DROP TABLE IF EXISTS `contact_request`;

SET FOREIGN_KEY_CHECKS = 1;
