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

CREATE TABLE IF NOT EXISTS chat_unread_counts (
    chat_room_id VARCHAR(150) NOT NULL,
    user_id      VARCHAR(50)  NOT NULL,
    unread_count INT          NOT NULL DEFAULT 0,
    PRIMARY KEY (chat_room_id, user_id),
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

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
    delivered_at            DATETIME     DEFAULT NULL,
    read_at                 DATETIME     DEFAULT NULL,
    created_at              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
    INDEX idx_chat_room_time       (chat_room_id, created_at),
    INDEX idx_created_at           (created_at),
    INDEX idx_cm_sender            (sender_id),
    INDEX idx_cm_receiver          (receiver_id),
    INDEX idx_sender_receiver_time (sender_id, receiver_id, created_at),
    INDEX idx_cm_receiver_read     (receiver_id, is_read),
    FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS user_online_status (
    user_id             VARCHAR(50)  NOT NULL PRIMARY KEY,
    is_online           TINYINT(1)   NOT NULL DEFAULT 0,
    last_seen           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    active_chat_room_id VARCHAR(150) DEFAULT NULL,
    socket_id           VARCHAR(255) DEFAULT NULL,
    INDEX idx_uos_online (is_online)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
