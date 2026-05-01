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
