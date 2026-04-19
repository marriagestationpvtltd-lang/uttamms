-- =============================================================================
-- Marriage Station – Admin Chat Schema (MERGED INTO 'ms' DATABASE)
-- =============================================================================
--
-- NOTE: These tables have been merged into the main 'ms' matrimony database.
--       Use schema.sql (section 30) for the authoritative table definitions.
--       This file is kept for reference only and should NOT be applied separately.
--
-- Table mapping (adminchat → ms):
--   users            → agent_users
--   chats            → ac_chats
--   messages         → ac_messages
--   memorial_profiles → ac_memorial_profiles
--   profile_shares   → ac_profile_shares
--
-- The Backend/api/ code has been updated to connect to 'ms' and use the
-- renamed tables accordingly.
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- 1. ADMIN / AGENT USERS
-- =============================================================================

CREATE TABLE IF NOT EXISTS users (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username   VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    password   VARCHAR(255) NOT NULL,
    avatar_url VARCHAR(500) DEFAULT NULL,
    is_active  TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    last_login DATETIME DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_username (username),
    UNIQUE KEY uk_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default agent user (password: admin — CHANGE IMMEDIATELY)
INSERT IGNORE INTO users (id, username, email, password) VALUES
    (1, 'agent', 'agent@marriagestation.com',
     '$2y$10$UgRVAVqW2RmLi.x2UEcYtuBW7yxx3wGq2cGEV/JTtQtX1le40g7eG');

-- =============================================================================
-- 2. MEMBER PROFILES  (matrimony profiles shared inside chats)
-- =============================================================================

CREATE TABLE IF NOT EXISTS memorial_profiles (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name              VARCHAR(255) NOT NULL,
    avatar_url        VARCHAR(500) DEFAULT NULL,
    match_percentage  INT UNSIGNED NOT NULL DEFAULT 0,
    membership_status ENUM('free','paid') NOT NULL DEFAULT 'free',
    status            ENUM('newProfile','alreadySent') NOT NULL DEFAULT 'newProfile',
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_mp_membership (membership_status),
    INDEX idx_mp_match      (match_percentage)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 3. CHATS  (conversation threads between agents and contacts)
-- =============================================================================

CREATE TABLE IF NOT EXISTS chats (
    id               INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name             VARCHAR(255) NOT NULL DEFAULT '',
    avatar_url       VARCHAR(500) DEFAULT NULL,
    last_message     TEXT         DEFAULT NULL,
    last_message_time VARCHAR(20) DEFAULT NULL,
    is_pinned        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    is_unread        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    is_group         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    has_file         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    membership_status ENUM('free','paid') NOT NULL DEFAULT 'free',
    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_chat_pinned  (is_pinned),
    INDEX idx_chat_updated (updated_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 4. MESSAGES  (individual messages within a chat)
-- =============================================================================

CREATE TABLE IF NOT EXISTS messages (
    id                VARCHAR(100) NOT NULL,   -- composite key, e.g. "chatId-msg-timestamp-rand"
    chat_id           INT UNSIGNED NOT NULL,
    sender_id         INT UNSIGNED DEFAULT NULL,
    sender_type       ENUM('agent','contact') NOT NULL DEFAULT 'agent',
    message_type      ENUM('text','image','file','profile') NOT NULL DEFAULT 'text',
    text_content      TEXT         DEFAULT NULL,
    shared_profile_id INT UNSIGNED DEFAULT NULL,
    is_read           TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    FOREIGN KEY (chat_id)           REFERENCES chats(id)            ON DELETE CASCADE,
    FOREIGN KEY (sender_id)         REFERENCES users(id)            ON DELETE SET NULL,
    FOREIGN KEY (shared_profile_id) REFERENCES memorial_profiles(id) ON DELETE SET NULL,
    INDEX idx_msg_chat       (chat_id),
    INDEX idx_msg_created_at (chat_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 5. PROFILE SHARES  (tracks which profiles were shared in which chats)
-- =============================================================================

CREATE TABLE IF NOT EXISTS profile_shares (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    chat_id    INT UNSIGNED NOT NULL,
    profile_id INT UNSIGNED NOT NULL,
    shared_by  INT UNSIGNED DEFAULT NULL,
    shared_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_ps_chat_profile (chat_id, profile_id),
    FOREIGN KEY (chat_id)    REFERENCES chats(id)            ON DELETE CASCADE,
    FOREIGN KEY (profile_id) REFERENCES memorial_profiles(id) ON DELETE CASCADE,
    FOREIGN KEY (shared_by)  REFERENCES users(id)            ON DELETE SET NULL,
    INDEX idx_ps_chat    (chat_id),
    INDEX idx_ps_profile (profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- End of admin chat schema
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 1;
