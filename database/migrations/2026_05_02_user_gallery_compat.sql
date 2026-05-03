-- Ensure user_gallery has columns expected by gallery moderation/upload flow
-- Safe to run multiple times on MySQL 8+

ALTER TABLE user_gallery
    ADD COLUMN IF NOT EXISTS status ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending' AFTER imageurl,
    ADD COLUMN IF NOT EXISTS reject_reason TEXT NULL AFTER status,
    ADD COLUMN IF NOT EXISTS created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP AFTER reject_reason,
    ADD COLUMN IF NOT EXISTS updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP AFTER created_at;

ALTER TABLE user_gallery
    ADD INDEX IF NOT EXISTS idx_ug_userid (userid),
    ADD INDEX IF NOT EXISTS idx_ug_status (status);
