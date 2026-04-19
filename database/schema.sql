-- =============================================================================
-- Marriage Station – Complete Database Schema
-- =============================================================================
--
-- Usage:
--   mysql -u <user> -p <database> < schema.sql
--
-- All tables use:
--   • utf8mb4  charset (full Unicode, including emoji)
--   • InnoDB   storage engine (for foreign-key support and transactions)
--   • created_at / updated_at timestamps where relevant
-- =============================================================================

SET NAMES utf8mb4;
SET FOREIGN_KEY_CHECKS = 0;

-- =============================================================================
-- 1. LOOKUP / REFERENCE TABLES
-- =============================================================================

-- ----------------------------------------------------------------------------
-- maritalstatus
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS maritalstatus (
    id   INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed data
INSERT IGNORE INTO maritalstatus (id, name) VALUES
    (1, 'Never Married'),
    (2, 'Divorced'),
    (3, 'Widowed'),
    (4, 'Awaiting Divorce'),
    (5, 'Annulled');

-- ----------------------------------------------------------------------------
-- religion
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS religion (
    id   INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name VARCHAR(100) NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

INSERT IGNORE INTO religion (id, name) VALUES
    (1, 'Hindu'),
    (2, 'Muslim'),
    (3, 'Christian'),
    (4, 'Sikh'),
    (5, 'Buddhist'),
    (6, 'Jain'),
    (7, 'Other');

-- ----------------------------------------------------------------------------
-- community  (caste / community)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS community (
    id         INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    religionId INT UNSIGNED,
    FOREIGN KEY (religionId) REFERENCES religion(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- subcommunity
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS subcommunity (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    communityId INT UNSIGNED,
    FOREIGN KEY (communityId) REFERENCES community(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 2. USERS
-- =============================================================================

CREATE TABLE IF NOT EXISTS users (
    id              INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    firstName       VARCHAR(100) NOT NULL,
    lastName        VARCHAR(100) NOT NULL DEFAULT '',
    email           VARCHAR(255) NOT NULL,
    phone           VARCHAR(20)  DEFAULT NULL,
    password        VARCHAR(255) NOT NULL,
    profile_picture VARCHAR(500) DEFAULT NULL,

    -- "verified" = ID-verified, "unverified" = default, "pending" = under review
    status          ENUM('verified','unverified','pending') NOT NULL DEFAULT 'unverified',

    -- Profile privacy: who can see details without a request
    privacy         ENUM('public','private') NOT NULL DEFAULT 'public',

    -- "free" or "paid" subscription tier
    usertype        ENUM('free','paid') NOT NULL DEFAULT 'free',

    -- Whether the admin has verified the account (separate from email/ID verification)
    isVerified      TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,

    -- Onboarding step tracker (used by the app to resume incomplete signup)
    pageno          TINYINT UNSIGNED NOT NULL DEFAULT 1,

    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE  KEY uk_email (email),
    INDEX   idx_status   (status),
    INDEX   idx_usertype (usertype)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 3. USER PROFILE SECTIONS
-- =============================================================================

-- ----------------------------------------------------------------------------
-- userpersonaldetail  – height, blood group, religion, etc.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS userpersonaldetail (
    id              INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid          INT UNSIGNED NOT NULL,
    memberid        VARCHAR(50)  DEFAULT NULL,   -- human-readable member code
    height_name     VARCHAR(50)  DEFAULT NULL,   -- e.g. "5'6\""
    maritalStatusId INT UNSIGNED DEFAULT NULL,
    religionId      INT UNSIGNED DEFAULT NULL,
    communityId     INT UNSIGNED DEFAULT NULL,
    subCommunityId  INT UNSIGNED DEFAULT NULL,
    motherTongue    VARCHAR(100) DEFAULT NULL,
    aboutMe         TEXT         DEFAULT NULL,
    birthDate       DATE         DEFAULT NULL,
    Disability      VARCHAR(100) DEFAULT NULL,   -- "None" or description
    bloodGroup      VARCHAR(10)  DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid)          REFERENCES users(id)         ON DELETE CASCADE,
    FOREIGN KEY (maritalStatusId) REFERENCES maritalstatus(id) ON DELETE SET NULL,
    FOREIGN KEY (religionId)      REFERENCES religion(id)      ON DELETE SET NULL,
    FOREIGN KEY (communityId)     REFERENCES community(id)     ON DELETE SET NULL,
    FOREIGN KEY (subCommunityId)  REFERENCES subcommunity(id)  ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- permanent_address
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS permanent_address (
    id       INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid   INT UNSIGNED NOT NULL,
    country  VARCHAR(100) DEFAULT NULL,
    state    VARCHAR(100) DEFAULT NULL,
    city     VARCHAR(100) DEFAULT NULL,
    district VARCHAR(100) DEFAULT NULL,
    pincode  VARCHAR(20)  DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- educationcareer
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS educationcareer (
    id              INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid          INT UNSIGNED NOT NULL,

    -- Education
    educationtype   VARCHAR(100) DEFAULT NULL,
    educationmedium VARCHAR(100) DEFAULT NULL,
    faculty         VARCHAR(100) DEFAULT NULL,
    degree          VARCHAR(150) DEFAULT NULL,

    -- Career
    areyouworking   TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    occupationtype  VARCHAR(100) DEFAULT NULL,
    companyname     VARCHAR(200) DEFAULT NULL,
    designation     VARCHAR(200) DEFAULT NULL,
    workingwith     VARCHAR(100) DEFAULT NULL,
    annualincome    VARCHAR(100) DEFAULT NULL,
    businessname    VARCHAR(200) DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- user_astrology
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_astrology (
    id        INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid    INT UNSIGNED NOT NULL,
    manglik   ENUM('Yes','No','Partial') DEFAULT NULL,
    birthtime VARCHAR(20)  DEFAULT NULL,
    birthcity VARCHAR(100) DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- userfamily
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS userfamily (
    id               INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid           INT UNSIGNED NOT NULL,
    familytype       VARCHAR(100) DEFAULT NULL,   -- "Nuclear", "Joint", etc.
    familybackground VARCHAR(100) DEFAULT NULL,
    fatherstatus     VARCHAR(100) DEFAULT NULL,
    fathername       VARCHAR(150) DEFAULT NULL,
    fathereducation  VARCHAR(150) DEFAULT NULL,
    fatheroccupation VARCHAR(150) DEFAULT NULL,
    motherstatus     VARCHAR(100) DEFAULT NULL,
    mothercaste      VARCHAR(100) DEFAULT NULL,
    mothereducation  VARCHAR(150) DEFAULT NULL,
    motheroccupation VARCHAR(150) DEFAULT NULL,
    familyorigin     VARCHAR(150) DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- userlifestyle
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS userlifestyle (
    id        INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid    INT UNSIGNED NOT NULL,
    smoketype VARCHAR(100) DEFAULT NULL,
    diet      VARCHAR(100) DEFAULT NULL,   -- "Veg", "Non-Veg", etc.
    drinks    TINYINT(1)   DEFAULT NULL,
    drinktype VARCHAR(100) DEFAULT NULL,
    smoke     TINYINT(1)   DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- userpartnerpreferences
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS userpartnerpreferences (
    id                  INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid              INT UNSIGNED NOT NULL,
    minage              TINYINT UNSIGNED DEFAULT NULL,
    maxage              TINYINT UNSIGNED DEFAULT NULL,
    maritalstatus       VARCHAR(100) DEFAULT NULL,
    profilewithchild    TINYINT(1)   DEFAULT NULL,
    familytype          VARCHAR(100) DEFAULT NULL,
    religion            VARCHAR(100) DEFAULT NULL,
    caste               VARCHAR(100) DEFAULT NULL,
    mothertoungue       VARCHAR(100) DEFAULT NULL,
    herscopeblief       VARCHAR(100) DEFAULT NULL,   -- horoscope match preference
    manglik             VARCHAR(50)  DEFAULT NULL,
    country             VARCHAR(100) DEFAULT NULL,
    state               VARCHAR(100) DEFAULT NULL,
    city                VARCHAR(100) DEFAULT NULL,
    qualification       VARCHAR(150) DEFAULT NULL,
    educationmedium     VARCHAR(100) DEFAULT NULL,
    proffession         VARCHAR(150) DEFAULT NULL,
    workingwith         VARCHAR(100) DEFAULT NULL,
    annualincome        VARCHAR(100) DEFAULT NULL,
    diet                VARCHAR(100) DEFAULT NULL,
    smokeaccept         TINYINT(1)   DEFAULT NULL,
    drinkaccept         TINYINT(1)   DEFAULT NULL,
    disabilityaccept    TINYINT(1)   DEFAULT NULL,
    complexion          VARCHAR(50)  DEFAULT NULL,
    bodytype            VARCHAR(50)  DEFAULT NULL,
    otherexpectation    TEXT         DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 4. PROPOSALS  (connection / request system)
-- =============================================================================

CREATE TABLE IF NOT EXISTS proposals (
    id           INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sender_id    INT UNSIGNED NOT NULL,
    receiver_id  INT UNSIGNED NOT NULL,

    -- Type of access being requested
    request_type ENUM('Photo','Profile','Chat') NOT NULL DEFAULT 'Photo',

    -- Lifecycle status
    status       ENUM('pending','accepted','rejected') NOT NULL DEFAULT 'pending',

    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (sender_id)   REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE,

    -- Searching proposals by participant
    INDEX idx_sender_id   (sender_id),
    INDEX idx_receiver_id (receiver_id),
    INDEX idx_status      (status),
    INDEX idx_request_type(request_type),

    -- Combined index for the "get history" query pattern
    INDEX idx_participants_status (sender_id, receiver_id, status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 5. NOTIFICATIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS notifications (
    id           INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id      INT UNSIGNED NOT NULL,
    title        VARCHAR(255) NOT NULL DEFAULT '',
    message      TEXT         NOT NULL,

    -- Namespaced type for grouping notifications in the app
    type         VARCHAR(50)  NOT NULL DEFAULT 'general',

    -- ID of the related record (e.g. proposal id, message id)
    reference_id INT UNSIGNED DEFAULT NULL,

    is_read      TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_user_id   (user_id),
    INDEX idx_is_read   (user_id, is_read),
    INDEX idx_type      (type)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 6. DOCUMENTS / KYC
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_documents (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid      INT UNSIGNED NOT NULL,
    doc_type    VARCHAR(100) DEFAULT NULL,   -- e.g. "Aadhaar", "PAN", "Passport"
    doc_url     VARCHAR(500) DEFAULT NULL,
    status      ENUM('not_uploaded','pending','approved','rejected') NOT NULL DEFAULT 'not_uploaded',
    reviewed_by INT UNSIGNED DEFAULT NULL,
    reviewed_at DATETIME     DEFAULT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 7. PACKAGES / SUBSCRIPTIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS packages (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    price       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    duration    INT UNSIGNED NOT NULL DEFAULT 30,    -- days
    description TEXT         DEFAULT NULL,
    is_active   TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS user_subscriptions (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid      INT UNSIGNED NOT NULL,
    package_id  INT UNSIGNED NOT NULL,
    start_date  DATE         NOT NULL,
    end_date    DATE         NOT NULL,
    status      ENUM('active','expired','cancelled') NOT NULL DEFAULT 'active',
    payment_ref VARCHAR(255) DEFAULT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (userid)     REFERENCES users(id)     ON DELETE CASCADE,
    FOREIGN KEY (package_id) REFERENCES packages(id)  ON DELETE RESTRICT,
    INDEX idx_userid     (userid),
    INDEX idx_end_date   (end_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 8. USER ACTIVITY  (app + admin panel)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_activities (
    id             INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id        INT UNSIGNED NOT NULL,

    -- The action the user performed
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
        'other'
    ) NOT NULL DEFAULT 'other',

    -- Human-readable detail (e.g. "Viewed profile #42")
    description    VARCHAR(500) DEFAULT NULL,

    -- The other user involved (e.g. whose profile was viewed, who was called)
    target_user_id INT UNSIGNED DEFAULT NULL,

    -- Client info for admin diagnostics
    ip_address     VARCHAR(45)  DEFAULT NULL,
    device_info    VARCHAR(255) DEFAULT NULL,

    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_ua_user_id       (user_id),
    INDEX idx_ua_type          (activity_type),
    INDEX idx_ua_created_at    (created_at),
    INDEX idx_ua_target_user   (target_user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 9. CALL SETTINGS  (ringtones + user preferences)
-- =============================================================================

-- System ringtones managed by admin
CREATE TABLE IF NOT EXISTS ringtones (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    file_url    VARCHAR(500) NOT NULL,

    -- Only one ringtone should be the system default
    is_default  TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,

    -- Soft-delete: admin can deactivate without losing the record
    is_active   TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    INDEX idx_rt_is_active  (is_active),
    INDEX idx_rt_is_default (is_default)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Seed: one built-in default ringtone (adjust file_url as needed)
INSERT IGNORE INTO ringtones (id, name, file_url, is_default, is_active) VALUES
    (1, 'Default Ringtone', '/uploads/ringtones/default.mp3', 1, 1);

-- Per-user call settings (one row per user)
CREATE TABLE IF NOT EXISTS user_call_settings (
    id                INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id           INT UNSIGNED NOT NULL,

    -- System ringtone chosen by the user (NULL = use the system default)
    ringtone_id       INT UNSIGNED DEFAULT NULL,

    -- Custom tone uploaded by the user
    custom_tone_url   VARCHAR(500) DEFAULT NULL,
    custom_tone_name  VARCHAR(255) DEFAULT NULL,

    -- 1 = play custom_tone_url when this user is called
    -- 0 = play the ringtone_id (or system default if ringtone_id is NULL)
    is_custom         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_ucs_user_id (user_id),
    FOREIGN KEY (user_id)     REFERENCES users(id)     ON DELETE CASCADE,
    FOREIGN KEY (ringtone_id) REFERENCES ringtones(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- End of schema
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 1;
