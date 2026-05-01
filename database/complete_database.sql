-- =============================================================================
-- Marriage Station – Complete Database (All Tables)
-- =============================================================================
--
-- This file combines:
--   1. The full new schema (schema.sql) – authoritative table definitions
--   2. Additional legacy tables from the old database not in the new schema
--   3. Idempotent ALTER TABLE migrations for existing databases
--
-- Usage (fresh install):
--   mysql -u <user> -p <database> < complete_database.sql
--
-- Usage (update existing old database):
--   mysql -u <user> -p <database> < complete_database.sql
--   (All statements use CREATE TABLE IF NOT EXISTS and ALTER TABLE IF NOT EXISTS
--    guards so they are safe to run against an existing database.)
-- =============================================================================

-- =============================================================================
-- PART 1: CURRENT SCHEMA (all new tables)
-- =============================================================================

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
-- These IDs must match the index-based mapping used by the Flutter app
-- (signupscreen2.dart: _maritalStatusOptions.indexOf(selected) + 1).
-- ID 1 = Still Unmarried, ID 2 = Widowed, ID 3 = Divorced, ID 4 = Waiting Divorce
-- ON DUPLICATE KEY UPDATE ensures existing rows are corrected, not skipped.
INSERT INTO maritalstatus (id, name) VALUES
    (1, 'Still Unmarried'),
    (2, 'Widowed'),
    (3, 'Divorced'),
    (4, 'Waiting Divorce'),
    (5, 'Annulled')
ON DUPLICATE KEY UPDATE name = VALUES(name);

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
    contactNo       VARCHAR(20)  DEFAULT NULL,   -- legacy mobile app field (same as phone)
    password        VARCHAR(255) NOT NULL,
    profile_picture VARCHAR(500) DEFAULT NULL,

    -- Demographics
    gender          VARCHAR(20)  DEFAULT NULL,
    languages       VARCHAR(200) DEFAULT NULL,
    nationality     VARCHAR(100) DEFAULT NULL,

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

    -- Social / OAuth
    google_id       VARCHAR(255) DEFAULT NULL,

    -- Push notification token
    fcm_token       VARCHAR(500) DEFAULT NULL,

    -- Online presence (used by matched.php)
    isOnline        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,

    -- Legacy admin-managed flags (used by get_users.php / get_dashboard.php)
    isActive        TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    isDelete        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,

    -- Document / KYC status fields (checked by check_document_status API)
    reject_reason         VARCHAR(500) DEFAULT NULL,
    document_upload_date  DATETIME     DEFAULT NULL,

    -- Login tracking
    last_login      DATETIME     DEFAULT NULL,
    lastLogin       DATETIME     DEFAULT NULL,   -- legacy alias (get_users.php)

    -- Legacy timestamp alias (use created_at for new code)
    createdDate     DATETIME     DEFAULT CURRENT_TIMESTAMP,

    created_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE  KEY uk_email (email),
    INDEX   idx_status   (status),
    INDEX   idx_usertype (usertype),
    INDEX   idx_gender   (gender)
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
    profileForId    VARCHAR(50)  DEFAULT NULL,   -- "For whom is this profile?" (self, son, daughter, etc.)
    height_name     VARCHAR(50)  DEFAULT NULL,   -- e.g. "5'6\""
    weight_name     VARCHAR(50)  DEFAULT NULL,   -- e.g. "65 kg"
    maritalStatusId INT UNSIGNED DEFAULT NULL,
    religionId      INT UNSIGNED DEFAULT NULL,
    communityId     INT UNSIGNED DEFAULT NULL,
    subCommunityId  INT UNSIGNED DEFAULT NULL,
    motherTongue    VARCHAR(100) DEFAULT NULL,
    aboutMe         TEXT         DEFAULT NULL,
    birthDate       DATE         DEFAULT NULL,
    Disability      VARCHAR(100) DEFAULT NULL,   -- "None" or description
    anyDisability   TINYINT(1)   DEFAULT NULL,   -- 0 = No, 1 = Yes
    haveSpecs       TINYINT(1)   DEFAULT NULL,   -- 0 = No, 1 = Yes (spectacles)
    bloodGroup      VARCHAR(10)  DEFAULT NULL,
    complexion      VARCHAR(50)  DEFAULT NULL,   -- "Fair", "Wheatish", etc.
    bodyType        VARCHAR(50)  DEFAULT NULL,   -- "Slim", "Average", etc.
    childStatus     VARCHAR(50)  DEFAULT NULL,   -- "No Children", "Has Children", etc.
    childLiveWith   VARCHAR(50)  DEFAULT NULL,   -- "Yes", "No" (children live with them)

    -- Religion/community language preference (update_religion.php)
    castlanguage    VARCHAR(100) DEFAULT NULL,

    -- Legacy ID-based FK columns (used by older matched.php / webrtc.php)
    -- Newer code uses text columns (height_name, etc.) directly.
    occupationId    INT UNSIGNED DEFAULT NULL,
    educationId     INT UNSIGNED DEFAULT NULL,
    heightId        INT UNSIGNED DEFAULT NULL,
    annualIncomeId  INT UNSIGNED DEFAULT NULL,
    addressId       INT UNSIGNED DEFAULT NULL,

    -- Legacy audit timestamps (get_personal_detail.php references these)
    createdDate     DATETIME     DEFAULT CURRENT_TIMESTAMP,
    modifiedDate    DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

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
    id               INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid           INT UNSIGNED NOT NULL,
    country          VARCHAR(100) DEFAULT NULL,
    state            VARCHAR(100) DEFAULT NULL,
    city             VARCHAR(100) DEFAULT NULL,
    district         VARCHAR(100) DEFAULT NULL,
    pincode          VARCHAR(20)  DEFAULT NULL,
    tole             VARCHAR(100) DEFAULT NULL,       -- locality / street (Nepali: टोल)
    residentalstatus VARCHAR(100) DEFAULT NULL,        -- "Own", "Rented", etc.

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- current_address  – where the user is currently residing
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS current_address (
    id               INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid           INT UNSIGNED NOT NULL,
    country          VARCHAR(100) DEFAULT NULL,
    state            VARCHAR(100) DEFAULT NULL,
    city             VARCHAR(100) DEFAULT NULL,
    tole             VARCHAR(100) DEFAULT NULL,
    residentalstatus VARCHAR(100) DEFAULT NULL,
    willingtogoabroad INT         DEFAULT 0,
    visastatus       VARCHAR(100) DEFAULT NULL,

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
-- user_astrologic  (astrology / horoscope details)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_astrologic (
    id           INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid       INT UNSIGNED NOT NULL,
    belief       VARCHAR(50)  DEFAULT NULL,   -- "Yes" or "No" (believes in astrology)
    manglik      ENUM('Yes','No','Partial') DEFAULT NULL,
    birthtime    VARCHAR(20)  DEFAULT NULL,
    birthcity    VARCHAR(100) DEFAULT NULL,
    birthcountry VARCHAR(100) DEFAULT NULL,
    zodiacsign   VARCHAR(50)  DEFAULT NULL,
    birthdate    DATE         DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- user_family
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_family (
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
-- user_family_members  – individual siblings / children entries
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_family_members (
    id            INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid        INT UNSIGNED NOT NULL,
    membertype    VARCHAR(100) DEFAULT NULL,   -- "Brother", "Sister", "Son", "Daughter"
    maritalstatus VARCHAR(100) DEFAULT NULL,
    livestatus    VARCHAR(100) DEFAULT NULL,   -- "Alive", "Deceased"

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_ufm_userid (userid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- user_lifestyle
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_lifestyle (
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
-- user_partner  (partner preferences)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_partner (
    id                  INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid              INT UNSIGNED NOT NULL,
    minage              TINYINT UNSIGNED DEFAULT NULL,
    maxage              TINYINT UNSIGNED DEFAULT NULL,
    minheight           VARCHAR(50)  DEFAULT NULL,
    maxheight           VARCHAR(50)  DEFAULT NULL,
    maritalstatus       VARCHAR(100) DEFAULT NULL,
    profilewithchild    TINYINT(1)   DEFAULT NULL,
    familytype          VARCHAR(100) DEFAULT NULL,
    religion            VARCHAR(100) DEFAULT NULL,
    caste               VARCHAR(100) DEFAULT NULL,
    subcaste            VARCHAR(150) DEFAULT NULL,
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
-- 5. LIKES
-- =============================================================================

CREATE TABLE IF NOT EXISTS likes (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    sender_id   INT UNSIGNED NOT NULL,
    receiver_id INT UNSIGNED NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (sender_id)   REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uk_like (sender_id, receiver_id),
    INDEX idx_likes_sender   (sender_id),
    INDEX idx_likes_receiver (receiver_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 6. BLOCKS
-- =============================================================================

CREATE TABLE IF NOT EXISTS blocks (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    blocker_id  INT UNSIGNED NOT NULL,
    blocked_id  INT UNSIGNED NOT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (blocker_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (blocked_id) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uk_block (blocker_id, blocked_id),
    INDEX idx_blocks_blocker (blocker_id),
    INDEX idx_blocks_blocked (blocked_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 7. NOTIFICATIONS
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

-- ----------------------------------------------------------------------------
-- user_notifications  – per-user notification inbox (legacy API table)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_notifications (
    id         INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id    INT UNSIGNED NOT NULL,
    type       VARCHAR(50)  NOT NULL DEFAULT 'general',
    title      VARCHAR(255) NOT NULL DEFAULT '',
    message    TEXT         NOT NULL,
    is_read    TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_un_user_id (user_id),
    INDEX idx_un_is_read (user_id, is_read)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- user_notification_settings  – push/email/SMS preferences per user
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_notification_settings (
    id            INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id       INT UNSIGNED NOT NULL,
    push_enabled  TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    email_enabled TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    sms_enabled   TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    updated_at    DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_uns_user_id (user_id),
    FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 8. DOCUMENTS / KYC
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_documents (
    id               INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid           INT UNSIGNED NOT NULL,

    -- Per-document status (not global – one row per document type per user)
    status           ENUM('not_uploaded','pending','approved','rejected') NOT NULL DEFAULT 'not_uploaded',
    reject_reason    VARCHAR(500) DEFAULT NULL,
    reviewed_by      INT UNSIGNED DEFAULT NULL,
    reviewed_at      DATETIME     DEFAULT NULL,

    -- Document columns
    documenttype     VARCHAR(100) NOT NULL,        -- e.g. "Death Certificate", "Divorce Decree"
    documentidnumber VARCHAR(100) DEFAULT NULL,
    photo            VARCHAR(500) DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    -- One row per (user, document type); allows multiple document types per user
    UNIQUE KEY uk_userid_doctype (userid, documenttype),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 9. PACKAGES / SUBSCRIPTIONS
-- =============================================================================

-- ----------------------------------------------------------------------------
-- packagelist  – package catalogue (used by buypackage.php / purchase_package.php)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS packagelist (
    id          INT           UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150)  NOT NULL,
    price       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    duration    INT UNSIGNED  NOT NULL DEFAULT 1,   -- months
    description TEXT          DEFAULT NULL,
    is_active   TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- packages  – alias / extended package table (new schema name)
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- user_package  – purchases (used by buypackage.php / purchase_package.php)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_package (
    id           INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid       INT UNSIGNED NOT NULL,
    packageid    INT UNSIGNED NOT NULL,
    purchasedate DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiredate   DATETIME     DEFAULT NULL,
    paidby       VARCHAR(100) DEFAULT NULL,   -- payment method / gateway reference
    netAmount    VARCHAR(100) DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_up_userid  (userid),
    INDEX idx_up_packageid (packageid)
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
-- 10. USER ACTIVITY  (app + admin panel)
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

    -- Human-readable detail (e.g. "Viewed profile #42")
    description    VARCHAR(500) DEFAULT NULL,

    -- The other user involved (e.g. whose profile was viewed, who was called)
    target_user_id INT UNSIGNED DEFAULT NULL,
    target_name    VARCHAR(200) DEFAULT NULL,
    user_name      VARCHAR(200) DEFAULT NULL,

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
-- 11. AUTHENTICATION TOKENS
-- =============================================================================

-- ----------------------------------------------------------------------------
-- user_tokens  – bearer tokens issued on login (mobile app)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS user_tokens (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid     INT UNSIGNED NOT NULL,
    token      VARCHAR(255) NOT NULL,
    expires_at DATETIME     DEFAULT NULL,
    platform   VARCHAR(50)  DEFAULT 'mobile',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uk_ut_token (token),
    INDEX idx_ut_userid (userid),
    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- password_resets  – OTP codes for forgot-password flow
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS password_resets (
    id         INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid     INT UNSIGNED NOT NULL,
    email      VARCHAR(255) NOT NULL,
    otp        VARCHAR(10)  NOT NULL,
    expires_at DATETIME     NOT NULL,
    verified   TINYINT(1)   NOT NULL DEFAULT 0,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_pr_email (email),
    INDEX idx_pr_userid (userid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 12. ADMINS
-- =============================================================================

CREATE TABLE IF NOT EXISTS admins (
    id         INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username   VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    password   VARCHAR(255) NOT NULL,   -- bcrypt hash
    name       VARCHAR(200) DEFAULT NULL,
    role       ENUM('super_admin','admin') NOT NULL DEFAULT 'admin',
    is_active  TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    last_login DATETIME     DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_admin_username (username),
    UNIQUE KEY uk_admin_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default admin: username=admin  email=admin@ms.com  password=Admin@123
-- ⚠️  Change this password immediately after the first deployment.
INSERT IGNORE INTO admins (id, username, email, password, name, role) VALUES
    (1, 'admin', 'admin@ms.com',
     '$2y$10$UgRVAVqW2RmLi.x2UEcYtuBW7yxx3wGq2cGEV/JTtQtX1le40g7eG',
     'Super Admin', 'super_admin');

-- ----------------------------------------------------------------------------
-- admin_tokens  – bearer tokens issued on login (TTL: 24 hours)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS admin_tokens (
    id         INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    admin_id   INT UNSIGNED NOT NULL,
    token      VARCHAR(128) NOT NULL,
    expires_at DATETIME     NOT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    UNIQUE KEY uk_admin_token (token),
    INDEX idx_at_admin_id   (admin_id),
    INDEX idx_at_expires_at (expires_at),
    FOREIGN KEY (admin_id) REFERENCES admins(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 13. CALL SETTINGS  (ringtones + user preferences)
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
-- 14. USER GALLERY  (photo gallery)
-- =============================================================================

CREATE TABLE IF NOT EXISTS user_gallery (
    id           INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid       INT UNSIGNED NOT NULL,
    imageurl     VARCHAR(500) NOT NULL,
    status       ENUM('pending','approved','rejected') NOT NULL DEFAULT 'pending',
    reject_reason VARCHAR(500) DEFAULT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    FOREIGN KEY (userid) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_ug_userid (userid),
    INDEX idx_ug_status (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 15. ACCOUNT DELETION LOG
-- =============================================================================

CREATE TABLE IF NOT EXISTS deletion_log (
    id         INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid     INT UNSIGNED NOT NULL,
    reason     VARCHAR(500) DEFAULT NULL,
    feedback   TEXT         DEFAULT NULL,
    deleted_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    INDEX idx_dl_userid (userid)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 16. CHAT / MESSAGING  (Socket.IO real-time chat)
-- =============================================================================

-- Chat rooms between two users
CREATE TABLE IF NOT EXISTS chat_rooms (
    id                    VARCHAR(150) NOT NULL,
    participants          JSON         NOT NULL,
    participant_names     JSON         NOT NULL,
    participant_images    JSON         NOT NULL,
    last_message          TEXT,
    last_message_type     VARCHAR(50)  DEFAULT 'text',
    last_message_time     DATETIME     DEFAULT CURRENT_TIMESTAMP,
    last_message_sender_id VARCHAR(50) DEFAULT '',
    created_at            DATETIME     DEFAULT CURRENT_TIMESTAMP,
    updated_at            DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Per-room unread message counter per user
CREATE TABLE IF NOT EXISTS chat_unread_counts (
    chat_room_id VARCHAR(150) NOT NULL,
    user_id      VARCHAR(50)  NOT NULL,
    unread_count INT          NOT NULL DEFAULT 0,
    PRIMARY KEY (chat_room_id, user_id),
    CONSTRAINT fk_unread_room FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Individual chat messages
CREATE TABLE IF NOT EXISTS chat_messages (
    id                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    message_id              VARCHAR(100) NOT NULL UNIQUE,
    chat_room_id            VARCHAR(150) NOT NULL,
    sender_id               VARCHAR(50)  NOT NULL,
    receiver_id             VARCHAR(50)  NOT NULL,
    message                 TEXT,
    message_type            VARCHAR(50)  NOT NULL DEFAULT 'text',
    is_read                 TINYINT(1)   NOT NULL DEFAULT 0,
    is_delivered            TINYINT(1)   NOT NULL DEFAULT 0,
    is_deleted_for_sender   TINYINT(1)   NOT NULL DEFAULT 0,
    is_deleted_for_receiver TINYINT(1)   NOT NULL DEFAULT 0,
    is_edited               TINYINT(1)   NOT NULL DEFAULT 0,
    is_unsent               TINYINT(1)   NOT NULL DEFAULT 0,
    edited_at               DATETIME,
    replied_to              JSON,
    liked                   TINYINT(1)   NOT NULL DEFAULT 0,
    reactions               TEXT         NULL DEFAULT NULL,
    created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_chat_room_time       (chat_room_id, created_at),
    INDEX idx_created_at           (created_at),
    INDEX idx_cm_sender            (sender_id),
    INDEX idx_cm_receiver          (receiver_id),
    INDEX idx_sender_receiver_time (sender_id, receiver_id, created_at),
    CONSTRAINT fk_msg_room FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- User online status (persisted for last-seen)
CREATE TABLE IF NOT EXISTS user_online_status (
    user_id             VARCHAR(50)  NOT NULL PRIMARY KEY,
    is_online           TINYINT(1)   NOT NULL DEFAULT 0,
    last_seen           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    active_chat_room_id VARCHAR(150) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- 17. CALL HISTORY
-- =============================================================================

CREATE TABLE IF NOT EXISTS call_history (
    id             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    call_id        VARCHAR(100) NOT NULL UNIQUE,
    caller_id      VARCHAR(50)  NOT NULL,
    caller_name    VARCHAR(200) DEFAULT '',
    caller_image   VARCHAR(500) DEFAULT '',
    recipient_id   VARCHAR(50)  NOT NULL,
    recipient_name VARCHAR(200) DEFAULT '',
    recipient_image VARCHAR(500) DEFAULT '',
    call_type      ENUM('audio','video') NOT NULL DEFAULT 'audio',
    start_time     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    end_time       DATETIME DEFAULT NULL,
    duration       INT      NOT NULL DEFAULT 0,
    status         ENUM('completed','missed','declined','cancelled') NOT NULL DEFAULT 'missed',
    initiated_by   VARCHAR(50) NOT NULL,
    INDEX idx_ch_caller    (caller_id),
    INDEX idx_ch_recipient (recipient_id),
    INDEX idx_ch_start     (start_time)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Admin-initiated group call sessions with a dynamic participant list
CREATE TABLE IF NOT EXISTS group_calls (
    id           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    channel_name VARCHAR(150) NOT NULL UNIQUE,
    call_type    ENUM('audio', 'video') NOT NULL DEFAULT 'audio',
    admin_id     VARCHAR(50)  NOT NULL DEFAULT '1',
    participants JSON         NOT NULL,
    status       ENUM('active', 'ended') NOT NULL DEFAULT 'active',
    started_at   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at     DATETIME     DEFAULT NULL,
    INDEX idx_gc_channel (channel_name),
    INDEX idx_gc_admin   (admin_id),
    INDEX idx_gc_started (started_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- =============================================================================
-- 18. GEOGRAPHICAL LOOKUP TABLES  (countries / states / districts)
-- =============================================================================

-- Countries (used by countries.php, webrtc.php)
CREATE TABLE IF NOT EXISTS countries (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    code       VARCHAR(10)  DEFAULT NULL,   -- ISO 3166-1 alpha-2, e.g. 'NP'
    is_active  TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    UNIQUE KEY uk_country_name (name),
    INDEX idx_ctry_active (is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- States / Provinces (used by states.php)
-- NOTE: table name is `state` (singular) as used by the PHP API
CREATE TABLE IF NOT EXISTS state (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name       VARCHAR(150) NOT NULL,
    countryId  INT UNSIGNED NOT NULL,
    INDEX idx_state_country (countryId),
    FOREIGN KEY (countryId) REFERENCES countries(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Districts / Cities (used by cities.php)
CREATE TABLE IF NOT EXISTS districts (
    id       INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name     VARCHAR(150) NOT NULL,
    stateId  INT UNSIGNED NOT NULL,
    INDEX idx_dist_state (stateId),
    FOREIGN KEY (stateId) REFERENCES state(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 19. LEGACY LOOKUP TABLES  (occupation / education)
--     Used by older Backend/matched.php and Backend/get_match_details.php
-- =============================================================================

CREATE TABLE IF NOT EXISTS occupation (
    id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name      VARCHAR(150) NOT NULL,
    is_active TINYINT(1) UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS education (
    id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name      VARCHAR(150) NOT NULL,
    is_active TINYINT(1) UNSIGNED NOT NULL DEFAULT 1
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 20. LEGACY ADDRESS TABLE  (used by matched.php / webrtc.php)
--     Newer code uses permanent_address / current_address directly.
-- =============================================================================

CREATE TABLE IF NOT EXISTS addresses (
    id        INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userId    INT UNSIGNED NOT NULL,
    countryId INT UNSIGNED DEFAULT NULL,
    stateId   INT UNSIGNED DEFAULT NULL,
    cityId    INT UNSIGNED DEFAULT NULL,
    address1  VARCHAR(255) DEFAULT NULL,
    address2  VARCHAR(255) DEFAULT NULL,
    pincode   VARCHAR(20)  DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (countryId) REFERENCES countries(id) ON DELETE SET NULL,
    INDEX idx_addr_user (userId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 21. LEGACY PARTNER PREFERENCES  (used by matched.php / webrtc.php)
--     Newer code uses user_partner (text-based columns) instead.
--     Both tables are kept for backwards compatibility.
-- =============================================================================

CREATE TABLE IF NOT EXISTS userpartnerpreferences (
    id              INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userId          INT UNSIGNED NOT NULL,
    pFromAge        TINYINT UNSIGNED DEFAULT NULL,
    pToAge          TINYINT UNSIGNED DEFAULT NULL,
    pFromHeight     INT UNSIGNED     DEFAULT NULL,   -- heightId lower bound
    pToHeight       INT UNSIGNED     DEFAULT NULL,   -- heightId upper bound
    pMaritalStatusId INT UNSIGNED    DEFAULT NULL,
    pReligionId      INT UNSIGNED    DEFAULT NULL,
    pCommunityId     INT UNSIGNED    DEFAULT NULL,
    pEducationTypeId INT UNSIGNED    DEFAULT NULL,
    pAnnualIncomeId  INT UNSIGNED    DEFAULT NULL,
    pOccupationTypeId INT UNSIGNED   DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_upp_userId (userId),
    FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 22. LEGACY PACKAGE TABLE  (used by webrtc.php as `userpackage`)
--     Newer code uses user_package. Both tables kept for backwards compatibility.
-- =============================================================================

CREATE TABLE IF NOT EXISTS userpackage (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userId       INT UNSIGNED NOT NULL,
    packageId    INT UNSIGNED DEFAULT NULL,
    netAmount    DECIMAL(10,2) DEFAULT NULL,
    purchaseDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    expiryDate   DATETIME DEFAULT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_upkg_user (userId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 23. LEGACY BLOCKS TABLE  (used by send_delete_request.php as `userblock`)
--     Newer code uses `blocks`. Both tables kept for backwards compatibility.
-- =============================================================================

CREATE TABLE IF NOT EXISTS userblock (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userId       INT UNSIGNED NOT NULL,
    userBlockId  INT UNSIGNED NOT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (userId)      REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (userBlockId) REFERENCES users(id) ON DELETE CASCADE,
    UNIQUE KEY uk_ub (userId, userBlockId),
    INDEX idx_ub_userId (userId)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 24. LEGACY IMAGE GALLERY  (used by match.php as `userimagegallery`)
--     Newer code uses `user_gallery`. Both tables kept for backwards compatibility.
-- =============================================================================

CREATE TABLE IF NOT EXISTS userimagegallery (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userId      INT UNSIGNED NOT NULL,
    imageUrl    VARCHAR(500) NOT NULL,
    isActive    TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    isDelete    TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    createdDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updatedDate DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    FOREIGN KEY (userId) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_uig_user_active (userId, isActive, isDelete)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 25. MATCHES  (mutual matches between users)
--     Used by get_match_details.php and matched.php
-- =============================================================================

CREATE TABLE IF NOT EXISTS matches (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    user_id    INT UNSIGNED NOT NULL,
    matched_id INT UNSIGNED NOT NULL,
    score      DECIMAL(5,2) DEFAULT NULL,   -- match percentage
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_match_pair (user_id, matched_id),
    FOREIGN KEY (user_id)    REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (matched_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_match_user    (user_id),
    INDEX idx_match_matched (matched_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 26. WEBRTC SESSIONS
-- =============================================================================

CREATE TABLE IF NOT EXISTS webrtc (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    caller_id   INT UNSIGNED NOT NULL,
    receiver_id INT UNSIGNED NOT NULL,
    room_id     VARCHAR(100) DEFAULT NULL,
    channel     VARCHAR(255) DEFAULT NULL,
    token       TEXT         DEFAULT NULL,
    call_type   ENUM('audio','video') NOT NULL DEFAULT 'audio',
    status      ENUM('pending','active','ended','missed') NOT NULL DEFAULT 'pending',
    started_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    ended_at    DATETIME DEFAULT NULL,
    FOREIGN KEY (caller_id)   REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (receiver_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_webrtc_caller   (caller_id),
    INDEX idx_webrtc_receiver (receiver_id),
    INDEX idx_webrtc_status   (status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 27. SERVICES  (used by services_api.php)
-- =============================================================================

CREATE TABLE IF NOT EXISTS services (
    id          INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    title       VARCHAR(255) NOT NULL,
    description TEXT         DEFAULT NULL,
    icon_url    VARCHAR(500) DEFAULT NULL,
    is_active   TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    sort_order  INT UNSIGNED NOT NULL DEFAULT 0,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_svc_active (is_active),
    INDEX idx_svc_sort   (sort_order)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 28. APP VERSIONS  (mobile app version control)
-- =============================================================================

CREATE TABLE IF NOT EXISTS app_versions (
    id             INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    platform       ENUM('android','ios') NOT NULL,
    version_name   VARCHAR(50)  NOT NULL,   -- e.g. "2.1.0"
    version_code   INT UNSIGNED NOT NULL,   -- e.g. 21
    min_version    VARCHAR(50)  DEFAULT NULL,  -- minimum supported version
    release_notes  TEXT         DEFAULT NULL,
    force_update   TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    is_active      TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    released_at    DATETIME     DEFAULT NULL,
    created_at     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_av_platform_active (platform, is_active)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 29. PROFILE VIEWS  (track who viewed whose profile)
-- =============================================================================

CREATE TABLE IF NOT EXISTS profile_view (
    id          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    viewer_id   INT UNSIGNED NOT NULL,
    viewed_id   INT UNSIGNED NOT NULL,
    viewed_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (viewer_id) REFERENCES users(id) ON DELETE CASCADE,
    FOREIGN KEY (viewed_id) REFERENCES users(id) ON DELETE CASCADE,
    INDEX idx_pv_viewer   (viewer_id),
    INDEX idx_pv_viewed   (viewed_id),
    INDEX idx_pv_viewed_at(viewed_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- 30. ADMIN CHAT  (agent / admin chat panel – formerly the separate 'adminchat' DB)
--     All tables are prefixed ac_ to avoid conflicts with the matrimony tables.
--     The agent user table is named agent_users (not users) for the same reason.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- agent_users  – admin panel agents / operators
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS agent_users (
    id           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    username     VARCHAR(100) NOT NULL,
    email        VARCHAR(255) NOT NULL,
    password_hash VARCHAR(255) NOT NULL,
    avatar_url   VARCHAR(500) DEFAULT NULL,
    role         ENUM('admin','agent') NOT NULL DEFAULT 'agent',
    status       ENUM('active','inactive') NOT NULL DEFAULT 'active',
    last_login   DATETIME DEFAULT NULL,
    created_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    UNIQUE KEY uk_au_username (username),
    UNIQUE KEY uk_au_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default agent user (password: admin — CHANGE IMMEDIATELY)
INSERT IGNORE INTO agent_users (id, username, email, password_hash, role) VALUES
    (1, 'agent', 'agent@marriagestation.com',
     '$2y$10$UgRVAVqW2RmLi.x2UEcYtuBW7yxx3wGq2cGEV/JTtQtX1le40g7eG',
     'admin');

-- ----------------------------------------------------------------------------
-- ac_memorial_profiles  – matrimony profiles shared inside admin chats
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ac_memorial_profiles (
    id                INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name              VARCHAR(255) NOT NULL,
    avatar_url        VARCHAR(500) DEFAULT NULL,
    match_percentage  INT UNSIGNED NOT NULL DEFAULT 0,
    membership_status ENUM('free','paid') NOT NULL DEFAULT 'free',
    status            ENUM('newProfile','alreadySent') NOT NULL DEFAULT 'newProfile',
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    INDEX idx_acmp_membership (membership_status),
    INDEX idx_acmp_match      (match_percentage)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- ac_chats  – conversation threads between agents and contacts
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ac_chats (
    id               VARCHAR(20)  NOT NULL,
    name             VARCHAR(255) NOT NULL DEFAULT '',
    contact_id       VARCHAR(100) DEFAULT NULL,
    avatar_url       VARCHAR(500) DEFAULT NULL,
    last_message     TEXT         DEFAULT NULL,
    last_message_time VARCHAR(20) DEFAULT NULL,
    is_pinned        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    is_unread        TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    is_group         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    has_file         TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    membership_status ENUM('free','paid','expired') NOT NULL DEFAULT 'free',
    assigned_to      INT UNSIGNED DEFAULT NULL,
    created_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at       DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    INDEX idx_acch_pinned     (is_pinned),
    INDEX idx_acch_updated    (updated_at),
    INDEX idx_acch_assigned   (assigned_to),
    FOREIGN KEY (assigned_to) REFERENCES agent_users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- ac_messages  – individual messages within an admin chat
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ac_messages (
    id                VARCHAR(100) NOT NULL,
    chat_id           VARCHAR(20)  NOT NULL,
    sender_id         INT UNSIGNED DEFAULT NULL,
    sender_type       ENUM('agent','contact') NOT NULL DEFAULT 'agent',
    message_type      ENUM('text','image','file','profile') NOT NULL DEFAULT 'text',
    text_content      TEXT         DEFAULT NULL,
    shared_profile_id INT UNSIGNED DEFAULT NULL,
    is_read           TINYINT(1) UNSIGNED NOT NULL DEFAULT 0,
    created_at        DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (id),
    FOREIGN KEY (chat_id)           REFERENCES ac_chats(id)            ON DELETE CASCADE,
    FOREIGN KEY (sender_id)         REFERENCES agent_users(id)         ON DELETE SET NULL,
    FOREIGN KEY (shared_profile_id) REFERENCES ac_memorial_profiles(id) ON DELETE SET NULL,
    INDEX idx_acmsg_chat       (chat_id),
    INDEX idx_acmsg_created_at (chat_id, created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- ac_profile_shares  – tracks which profiles were shared in which admin chats
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS ac_profile_shares (
    id         INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    chat_id    VARCHAR(20)  NOT NULL,
    profile_id INT UNSIGNED NOT NULL,
    shared_by  INT UNSIGNED DEFAULT NULL,
    shared_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    UNIQUE KEY uk_acps_chat_profile (chat_id, profile_id),
    FOREIGN KEY (chat_id)    REFERENCES ac_chats(id)             ON DELETE CASCADE,
    FOREIGN KEY (profile_id) REFERENCES ac_memorial_profiles(id) ON DELETE CASCADE,
    FOREIGN KEY (shared_by)  REFERENCES agent_users(id)          ON DELETE SET NULL,
    INDEX idx_acps_chat    (chat_id),
    INDEX idx_acps_profile (profile_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- =============================================================================
-- End of schema
-- =============================================================================


-- =============================================================================
-- PART 2: LEGACY TABLES (from old database – added with IF NOT EXISTS)
-- These tables existed in the old database and are preserved for
-- backwards compatibility or legacy API support.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- annualincome
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `annualincome` (
  `id` int NOT NULL,
  `value` varchar(200) NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- application
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `application` (
  `id` int NOT NULL,
  `name` varchar(45) NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- authproviders
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `authproviders` (
  `id` int NOT NULL,
  `providerName` varchar(45) NOT NULL,
  `providerIcon` varchar(500) DEFAULT NULL,
  `applicationId` varchar(300) DEFAULT NULL,
  `secretKey` varchar(300) DEFAULT NULL,
  `loginURL` varchar(300) NOT NULL,
  `tokenURL` varchar(300) NOT NULL,
  `userInfoURL` varchar(300) NOT NULL,
  `callbackURL` varchar(300) NOT NULL,
  `permission` varchar(200) NOT NULL,
  `description` varchar(500) DEFAULT NULL,
  `isActive` tinyint NOT NULL DEFAULT '1',
  `isDelete` tinyint NOT NULL DEFAULT '0',
  `createdDate` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- blogs
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `blogs` (
  `id` int NOT NULL,
  `title` varchar(400) DEFAULT NULL,
  `description` longtext,
  `authorName` varchar(100) DEFAULT NULL,
  `image` varchar(200) DEFAULT NULL,
  `tags` varchar(400) DEFAULT NULL,
  `publishDate` datetime DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdAt` datetime DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `updatedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- chat
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `chat` (
  `id` int NOT NULL,
  `userId` int NOT NULL,
  `message` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- chats
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `chats` (
  `id` int NOT NULL,
  `sender_id` int NOT NULL,
  `message` int NOT NULL,
  `receiver_id` int NOT NULL,
  `created_at` date DEFAULT (curdate())
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- cities
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `cities` (
  `id` int NOT NULL,
  `districtId` int DEFAULT NULL,
  `name` varchar(200) DEFAULT NULL,
  `pincode` varchar(10) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- city
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `city` (
  `id` int NOT NULL,
  `districtId` int NOT NULL,
  `name` varchar(150) NOT NULL,
  `pincode` varchar(10) DEFAULT NULL,
  `isActive` tinyint(1) DEFAULT '1',
  `isDelete` tinyint(1) DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- coupons
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `coupons` (
  `id` int NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `code` varchar(25) DEFAULT NULL,
  `type` varchar(12) DEFAULT NULL,
  `value` double DEFAULT NULL,
  `maxUsage` int DEFAULT NULL,
  `userUsage` int DEFAULT NULL,
  `validFrom` datetime DEFAULT NULL,
  `validTo` datetime DEFAULT NULL,
  `maxDiscountAmount` double DEFAULT NULL,
  `description` longtext,
  `termsCondition` longtext,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- currencies
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `currencies` (
  `id` int NOT NULL,
  `name` varchar(45) DEFAULT NULL,
  `symbol` varchar(5) DEFAULT NULL,
  `code` varchar(10) DEFAULT NULL,
  `isDefault` tinyint DEFAULT '0',
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- currencypaymentgateway
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `currencypaymentgateway` (
  `id` int NOT NULL,
  `currencyId` int DEFAULT NULL,
  `paymentGatewayId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- customers
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `customers` (
  `id` int NOT NULL,
  `name` varchar(255) DEFAULT NULL,
  `address` varchar(255) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- customfields
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `customfields` (
  `id` int NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `displayName` varchar(100) DEFAULT NULL,
  `mappedFieldName` varchar(100) DEFAULT NULL,
  `description` longtext,
  `valueTypeId` int DEFAULT NULL,
  `isRequired` tinyint DEFAULT '0',
  `textLength` int DEFAULT NULL,
  `allowInSearch` tinyint DEFAULT '0',
  `allowInFilter` tinyint DEFAULT '0',
  `allowIncompleteProfile` tinyint DEFAULT '0',
  `allowInPreferences` tinyint DEFAULT '0',
  `defaultValue` longtext,
  `valueList` longtext,
  `completeprofilesectioname` varchar(100) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- customnotification
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `customnotification` (
  `id` int NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `title` varchar(200) DEFAULT NULL,
  `description` longtext,
  `imageUrl` longtext,
  `sendCount` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- delete_request
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `delete_request` (
  `id` int NOT NULL,
  `userid` int NOT NULL,
  `relationship_status` varchar(50) DEFAULT NULL,
  `engagement_date` date DEFAULT NULL,
  `app_experience` enum('Yes','No') DEFAULT 'Yes',
  `feedback` text,
  `delete_reason` text CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci,
  `status` enum('pending','accepted','rejected') DEFAULT 'pending',
  `created_at` timestamp NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- diet
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `diet` (
  `id` int NOT NULL,
  `name` varchar(200) NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- documenttype
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `documenttype` (
  `id` int NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `isRequired` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- educationmedium
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `educationmedium` (
  `id` int NOT NULL,
  `name` varchar(200) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- educationtype
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `educationtype` (
  `id` int NOT NULL,
  `name` varchar(200) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- employmenttype
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `employmenttype` (
  `id` int NOT NULL,
  `name` varchar(100) NOT NULL,
  `parentId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- feedback
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `feedback` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `description` varchar(45) DEFAULT NULL,
  `title` varchar(45) DEFAULT NULL,
  `transactionDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- flaggroup
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `flaggroup` (
  `id` int NOT NULL,
  `flagGroupName` varchar(50) DEFAULT NULL,
  `detail` longtext,
  `parentFlagGroupId` int DEFAULT NULL,
  `displayOrder` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- height
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `height` (
  `id` int NOT NULL,
  `name` int NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- images
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `images` (
  `id` int NOT NULL,
  `imageUrl` longtext,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `updatedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- languages
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `languages` (
  `id` int NOT NULL,
  `name` varchar(45) NOT NULL,
  `languageCode` varchar(45) NOT NULL,
  `countryCode` varchar(45) NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- package
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `package` (
  `id` int NOT NULL,
  `name` varchar(500) NOT NULL,
  `baseAmount` decimal(10,0) NOT NULL,
  `validity` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- packagecoupons
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `packagecoupons` (
  `id` int NOT NULL,
  `packageId` int DEFAULT NULL,
  `couponId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- packageduration
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `packageduration` (
  `id` int NOT NULL,
  `packageId` int DEFAULT NULL,
  `timeDurationId` int DEFAULT NULL,
  `discount` varchar(45) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- packagefacility
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `packagefacility` (
  `id` int NOT NULL,
  `packageId` int DEFAULT NULL,
  `premiumFacilityId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- pages
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `pages` (
  `id` int NOT NULL,
  `path` varchar(45) DEFAULT NULL,
  `title` varchar(45) DEFAULT NULL,
  `type` varchar(45) DEFAULT NULL,
  `active` tinyint DEFAULT NULL,
  `group` varchar(45) DEFAULT NULL,
  `parentId` int DEFAULT NULL,
  `displayOrder` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- payment
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `payment` (
  `id` int NOT NULL,
  `paymentMode` varchar(45) DEFAULT NULL,
  `paymentRefrence` varchar(45) DEFAULT NULL,
  `amount` decimal(10,0) DEFAULT NULL,
  `userId` int DEFAULT NULL,
  `paymentStatus` varchar(45) DEFAULT NULL,
  `signature` varchar(100) DEFAULT NULL,
  `orderId` varchar(45) DEFAULT NULL,
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- paymentgateway
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `paymentgateway` (
  `id` int NOT NULL,
  `name` varchar(50) DEFAULT NULL,
  `jsonData` json DEFAULT NULL,
  `useInWallet` tinyint DEFAULT '0',
  `useInCheckout` tinyint DEFAULT '0',
  `useInAndroid` tinyint DEFAULT NULL,
  `useInApple` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL,
  `description` longtext
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- preferenceweightage
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `preferenceweightage` (
  `id` int NOT NULL,
  `name` varchar(200) DEFAULT NULL,
  `weightage` int DEFAULT '1',
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- premiumfacility
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `premiumfacility` (
  `id` int NOT NULL,
  `name` varchar(200) NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- profilefor
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `profilefor` (
  `id` int NOT NULL,
  `name` varchar(100) DEFAULT NULL,
  `gender` varchar(45) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- questioncategories
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `questioncategories` (
  `id` int NOT NULL,
  `name` varchar(45) DEFAULT NULL,
  `parentId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- questions
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `questions` (
  `id` int NOT NULL,
  `questionCategoriesId` int DEFAULT NULL,
  `question` longtext,
  `answer` longtext,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- registrationscreens
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `registrationscreens` (
  `id` int NOT NULL,
  `screenDisplayNo` int DEFAULT NULL,
  `name` varchar(200) DEFAULT NULL,
  `displayName` varchar(200) DEFAULT NULL,
  `weightage` int DEFAULT NULL,
  `isSkippable` tinyint DEFAULT '0',
  `isDisable` tinyint DEFAULT '0',
  `canDisable` tinyint DEFAULT '0',
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL,
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- roles
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `roles` (
  `id` int NOT NULL,
  `name` varchar(100) NOT NULL,
  `description` varchar(200) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- successstories
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `successstories` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `partnerUserId` int DEFAULT NULL,
  `imageId` int DEFAULT NULL,
  `maritalStatus` varchar(20) DEFAULT NULL,
  `transactionDate` datetime DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL,
  `requestStatus` varchar(20) DEFAULT 'pending'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- systemflags
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `systemflags` (
  `id` int NOT NULL,
  `flagGroupId` int DEFAULT NULL,
  `valueTypeId` int DEFAULT NULL,
  `name` varchar(200) DEFAULT NULL,
  `displayName` varchar(200) DEFAULT NULL,
  `value` longtext,
  `defaultValue` longtext,
  `valueList` longtext,
  `description` longtext,
  `label` varchar(45) DEFAULT NULL,
  `parentFlagId` int DEFAULT NULL,
  `parentFlagValue` longtext,
  `isAuthRequired` tinyint DEFAULT '1',
  `autoRender` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- timeduration
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `timeduration` (
  `id` int NOT NULL,
  `value` int NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userastrologicdetail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userastrologicdetail` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `horoscopeBelief` tinyint DEFAULT NULL,
  `birthCountryId` int DEFAULT NULL,
  `birthCityId` int DEFAULT NULL,
  `birthCountryName` varchar(200) DEFAULT NULL,
  `birthCityName` varchar(200) DEFAULT NULL,
  `zodiacSign` varchar(100) DEFAULT NULL,
  `timeOfBirth` varchar(200) DEFAULT NULL,
  `isHideBirthTime` tinyint DEFAULT '0',
  `manglik` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- userauthdata
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userauthdata` (
  `id` int NOT NULL,
  `userId` int NOT NULL,
  `oAuthUserId` varchar(100) NOT NULL,
  `oAuthUserName` varchar(100) DEFAULT NULL,
  `oAuthUserPicUrl` longtext,
  `oAuthAccessToken` longtext,
  `authProviderId` int DEFAULT NULL,
  `description` longtext,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userblockrequest
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userblockrequest` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `blockRequestUserId` int DEFAULT NULL,
  `reason` varchar(500) DEFAULT NULL,
  `status` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userchat
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userchat` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `partnerId` int DEFAULT NULL,
  `chatId` varchar(100) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userchats
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userchats` (
  `id` int NOT NULL,
  `senderUserId` int NOT NULL,
  `receiverUserId` int NOT NULL,
  `chatId` int NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userdevicedetail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userdevicedetail` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `applicationId` int DEFAULT NULL,
  `deviceId` varchar(300) DEFAULT NULL,
  `fcmToken` varchar(300) DEFAULT NULL,
  `deviceLocation` varchar(300) DEFAULT NULL,
  `deviceManufacturer` varchar(300) DEFAULT NULL,
  `deviceModel` varchar(100) DEFAULT NULL,
  `apiCallTime` varchar(100) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userfamilydetail
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userfamilydetail` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `name` varchar(200) DEFAULT NULL,
  `memberType` varchar(100) DEFAULT NULL,
  `memberSubType` varchar(100) DEFAULT NULL,
  `educationId` int DEFAULT NULL,
  `occupationId` int DEFAULT NULL,
  `maritalStatusId` int DEFAULT NULL,
  `isAlive` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- userfavourites
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userfavourites` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `favUserId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userflags
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userflags` (
  `id` int NOT NULL,
  `flagName` varchar(100) NOT NULL,
  `flagGroupId` int NOT NULL,
  `displayName` varchar(100) DEFAULT NULL,
  `description` longtext,
  `tooltip` varchar(45) DEFAULT NULL,
  `valueTypeId` int NOT NULL,
  `valueList` longtext,
  `defaultValue` longtext,
  `limit` longtext,
  `autoRender` tinyint DEFAULT NULL,
  `displayOrder` int DEFAULT NULL,
  `isActive` tinyint DEFAULT NULL,
  `isDelete` tinyint DEFAULT NULL,
  `createdAt` datetime DEFAULT CURRENT_TIMESTAMP,
  `updatedAt` datetime DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userflagvalues
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userflagvalues` (
  `id` int NOT NULL,
  `userId` int NOT NULL,
  `userFlagId` int NOT NULL,
  `userFlagValue` varchar(50) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdAt` datetime DEFAULT CURRENT_TIMESTAMP,
  `updateAt` datetime DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- usernotifications
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `usernotifications` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `title` varchar(500) DEFAULT NULL,
  `message` longtext,
  `imageUrl` longtext,
  `bodyJson` json DEFAULT NULL,
  `isRead` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userotp
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userotp` (
  `id` int NOT NULL,
  `mobileNumber` varchar(20) NOT NULL,
  `otp` varchar(6) NOT NULL,
  `createdAt` timestamp NULL DEFAULT CURRENT_TIMESTAMP,
  `expiresAt` timestamp NOT NULL,
  `isUsed` tinyint(1) DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- ----------------------------------------------------------------------------
-- userpages
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userpages` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `pageId` int DEFAULT NULL,
  `isReadPermission` tinyint(1) DEFAULT '0',
  `isAddPermission` tinyint(1) DEFAULT '0',
  `isDeletePermission` tinyint(1) DEFAULT '0',
  `isEditPermission` tinyint(1) DEFAULT '0',
  `isActive` tinyint NOT NULL DEFAULT '1',
  `isDelete` tinyint NOT NULL DEFAULT '0',
  `createdDate` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userpersonaldetailcustomdata
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userpersonaldetailcustomdata` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` varchar(45) DEFAULT NULL,
  `nadi` varchar(200) DEFAULT NULL,
  `hobbies` varchar(100) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userproposals
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userproposals` (
  `id` int NOT NULL,
  `userId` int NOT NULL,
  `proposalUserId` int NOT NULL,
  `status` tinyint DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL,
  `hascancelled` tinyint DEFAULT '0'
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userrefreshtoken
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userrefreshtoken` (
  `id` int NOT NULL,
  `userId` int NOT NULL,
  `refreshToken` longtext,
  `expireAt` datetime DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userroles
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userroles` (
  `id` int NOT NULL,
  `roleId` int NOT NULL,
  `userId` int NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- usertokens
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `usertokens` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `token` longtext,
  `isUsed` tinyint DEFAULT NULL,
  `expireAt` datetime DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userviewprofilehistories
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userviewprofilehistories` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `viewProfileByUserId` int DEFAULT NULL,
  `transactionDate` datetime DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userwallethistory
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userwallethistory` (
  `id` int NOT NULL,
  `userWalletId` int DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `isCredit` tinyint DEFAULT NULL,
  `transactionDate` datetime DEFAULT NULL,
  `remark` longtext,
  `paymentId` int DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- userwallets
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `userwallets` (
  `id` int NOT NULL,
  `userId` int DEFAULT NULL,
  `amount` decimal(10,2) DEFAULT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- valuetypes
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `valuetypes` (
  `id` int NOT NULL,
  `valueTypeName` varchar(100) DEFAULT NULL,
  `description` longtext,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL,
  `isShowInCustomField` tinyint DEFAULT NULL,
  `isUseForFilter` tinyint DEFAULT NULL,
  `remark` varchar(200) DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- weight
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `weight` (
  `id` int NOT NULL,
  `name` int NOT NULL,
  `isActive` tinyint DEFAULT '1',
  `isDelete` tinyint DEFAULT '0',
  `createdDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` datetime DEFAULT CURRENT_TIMESTAMP,
  `createdBy` int DEFAULT NULL,
  `modifiedBy` int DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- contact_request
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `contact_request` (
  `id`          BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `senderid`    INT          NOT NULL,
  `receiverid`  INT          NOT NULL,
  `status`      ENUM('pending','accepted','rejected','withdrawn') NOT NULL DEFAULT 'pending',
  `message`     TEXT         DEFAULT NULL,
  `created_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  INDEX `idx_cr_sender`   (`senderid`),
  INDEX `idx_cr_receiver` (`receiverid`),
  INDEX `idx_cr_status`   (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- occupationtype
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `occupationtype` (
  `id`           INT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `name`         VARCHAR(200)  NOT NULL,
  `isActive`     TINYINT(1)   NOT NULL DEFAULT 1,
  `isDelete`     TINYINT(1)   NOT NULL DEFAULT 0,
  `createdDate`  DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `modifiedDate` DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- profile_views
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `profile_views` (
  `id`             BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
  `viewer_user_id` INT NOT NULL,
  `viewed_user_id` INT NOT NULL,
  `viewed_at`      DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  INDEX `idx_pv_viewed_user` (`viewed_user_id`),
  INDEX `idx_pv_viewer_user` (`viewer_user_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ----------------------------------------------------------------------------
-- app_settings
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS `app_settings` (
  `setting_key`   VARCHAR(100) NOT NULL PRIMARY KEY,
  `setting_value` TEXT         DEFAULT NULL,
  `updated_at`    TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;


-- =============================================================================
-- PART 3: MIGRATIONS (add missing columns to existing old databases)
-- These ALTER TABLE statements are idempotent – safe to run on any database.
-- =============================================================================

-- ----------------------------------------------------------------------------
-- Migration: Add username column to admins table
-- ----------------------------------------------------------------------------
-- Migration: Add username column to admins table
-- Run this script if your admins table was created from the old schema
-- (before the username column was added).

DROP PROCEDURE IF EXISTS _migration_add_admin_username;

DELIMITER $$
CREATE PROCEDURE _migration_add_admin_username()
BEGIN
    -- Step 1: Add the username column only if it does not yet exist
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'admins'
          AND COLUMN_NAME  = 'username'
    ) THEN
        ALTER TABLE admins
            ADD COLUMN username VARCHAR(100) NULL AFTER id;

        -- Step 2: Back-fill username from the email local-part for existing rows
        UPDATE admins
        SET username = SUBSTRING_INDEX(email, '@', 1)
        WHERE username IS NULL;

        -- Step 3: Remove any duplicate back-filled usernames by appending the id
        UPDATE admins a
        JOIN (
            SELECT MIN(id) AS keep_id, username
            FROM admins
            GROUP BY username
            HAVING COUNT(*) > 1
        ) dup ON a.username = dup.username AND a.id <> dup.keep_id
        SET a.username = CONCAT(a.username, '_', a.id);

        -- Step 4: Make the column NOT NULL
        ALTER TABLE admins
            MODIFY COLUMN username VARCHAR(100) NOT NULL;
    END IF;

    -- Step 5: Add the unique constraint only if it does not yet exist
    IF NOT EXISTS (
        SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME   = 'admins'
          AND INDEX_NAME   = 'uk_admin_username'
    ) THEN
        ALTER TABLE admins
            ADD CONSTRAINT uk_admin_username UNIQUE (username);
    END IF;
END$$
DELIMITER ;

CALL _migration_add_admin_username();
DROP PROCEDURE IF EXISTS _migration_add_admin_username;

-- Step 6: Update the default admin row to set the standard username
--         (skip if the row does not exist or username is already set correctly)
UPDATE admins
SET username = 'admin'
WHERE email = 'admin@ms.com';

-- ----------------------------------------------------------------------------
-- Migration: Add is_unsent column to chat_messages
-- ----------------------------------------------------------------------------
-- =============================================================================
-- Migration: Add is_unsent column to chat_messages
-- Run this script against an existing database that was created from a schema
-- version before is_unsent was added to the chat_messages table.
--
-- The column is also added automatically by the socket server at startup, but
-- running this migration ensures the column is present even when the socket
-- server has not yet been started (e.g. on a fresh install that uses only the
-- PHP backend).
-- =============================================================================

-- Idempotent guard using INFORMATION_SCHEMA (compatible with MySQL 5.7+).
DROP PROCEDURE IF EXISTS _migration_add_is_unsent;

DELIMITER $$
CREATE PROCEDURE _migration_add_is_unsent()
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   INFORMATION_SCHEMA.COLUMNS
        WHERE  TABLE_SCHEMA = DATABASE()
          AND  TABLE_NAME   = 'chat_messages'
          AND  COLUMN_NAME  = 'is_unsent'
    ) THEN
        ALTER TABLE chat_messages
            ADD COLUMN is_unsent TINYINT(1) NOT NULL DEFAULT 0;
    END IF;
END$$
DELIMITER ;

CALL _migration_add_is_unsent();
DROP PROCEDURE IF EXISTS _migration_add_is_unsent;

-- ----------------------------------------------------------------------------
-- Migration: Ensure user_activities table and all ENUM values exist
-- ----------------------------------------------------------------------------
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

-- ----------------------------------------------------------------------------
-- Migration: Per-document status in user_documents
-- ----------------------------------------------------------------------------
-- =============================================================================
-- Migration: Per-document status tracking
-- Moves document status from the global users.status to per-row
-- user_documents.status so that each document type can be tracked
-- independently.
-- =============================================================================

-- 1. Add reject_reason column to user_documents (stores admin rejection note
--    per document row rather than globally on users).
--    MySQL does not support ADD COLUMN IF NOT EXISTS, so we use an
--    INFORMATION_SCHEMA check with PREPARE/EXECUTE to make this idempotent.
SET @_add_col = (
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
PREPARE _stmt FROM @_add_col;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- 2. Ensure documenttype column is NOT NULL (new uploads always supply it)
--    Update any existing NULL rows to a descriptive placeholder before
--    applying the NOT NULL constraint. Records with this value are
--    pre-migration rows that should be reviewed and corrected manually.
UPDATE user_documents SET documenttype = 'Legacy_Document' WHERE documenttype IS NULL;
ALTER TABLE user_documents
    MODIFY COLUMN documenttype VARCHAR(100) NOT NULL;

-- 3. Drop the old single-user unique key (only one doc per user)
--    MySQL does not support DROP INDEX IF EXISTS, so we use an
--    INFORMATION_SCHEMA check with PREPARE/EXECUTE to make this idempotent.
SET @_drop_idx = (
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
PREPARE _stmt FROM @_drop_idx;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- 4. Add composite unique key so one user can have one row per document type
--    but cannot duplicate the same type.
SET @_add_uk_doctype = (
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
PREPARE _stmt FROM @_add_uk_doctype;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- 5. Remove legacy new-schema columns that are replaced by the above
--    (safe to drop if they exist; harmless if they do not)
ALTER TABLE user_documents
    DROP COLUMN IF EXISTS doc_type,
    DROP COLUMN IF EXISTS doc_url;

-- =============================================================================
-- Re-enable foreign key checks
-- =============================================================================
SET FOREIGN_KEY_CHECKS = 1;
