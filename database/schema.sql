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

    -- Document / KYC status fields (checked by check_document_status API)
    reject_reason         VARCHAR(500) DEFAULT NULL,
    document_upload_date  DATETIME     DEFAULT NULL,

    -- Login tracking
    last_login      DATETIME     DEFAULT NULL,

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

    -- New schema columns
    doc_type         VARCHAR(100) DEFAULT NULL,   -- e.g. "Aadhaar", "PAN", "Passport"
    doc_url          VARCHAR(500) DEFAULT NULL,
    status           ENUM('not_uploaded','pending','approved','rejected') NOT NULL DEFAULT 'not_uploaded',
    reviewed_by      INT UNSIGNED DEFAULT NULL,
    reviewed_at      DATETIME     DEFAULT NULL,

    -- Legacy API columns (used by upload_document.php)
    documenttype     VARCHAR(100) DEFAULT NULL,
    documentidnumber VARCHAR(100) DEFAULT NULL,
    photo            VARCHAR(500) DEFAULT NULL,

    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_userid (userid),
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
    is_active  TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    last_login DATETIME     DEFAULT NULL,
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

    UNIQUE KEY uk_admin_username (username),
    UNIQUE KEY uk_admin_email    (email)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

-- Default admin: username=admin  password=Admin@123
-- ⚠️  Change this password immediately after the first deployment.
INSERT IGNORE INTO admins (id, username, email, password, name) VALUES
    (1, 'admin', 'admin@marriagestation.com',
     '$2y$10$UgRVAVqW2RmLi.x2UEcYtuBW7yxx3wGq2cGEV/JTtQtX1le40g7eG',
     'Super Admin');

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
    edited_at               DATETIME,
    replied_to              JSON,
    created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_chat_room_time (chat_room_id, created_at),
    INDEX idx_cm_sender      (sender_id),
    INDEX idx_cm_receiver    (receiver_id),
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

-- =============================================================================
-- End of schema
-- =============================================================================

SET FOREIGN_KEY_CHECKS = 1;
