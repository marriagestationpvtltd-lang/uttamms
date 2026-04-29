'use strict';

require('dotenv').config();
const express   = require('express');
const http      = require('http');
const { Server } = require('socket.io');
const mysql     = require('mysql2/promise');
const cors      = require('cors');
const multer    = require('multer');
const path      = require('path');
const fs        = require('fs');
const { v4: uuidv4 } = require('uuid');

// ──────────────────────────────────────────────────────────────────────────────
// Configuration
// ──────────────────────────────────────────────────────────────────────────────
const PORT        = process.env.PORT || 3001;
const UPLOAD_DIR  = process.env.UPLOAD_DIR || './uploads';
const ALLOWED_ORIGINS = (process.env.ALLOWED_ORIGINS || '*').split(',').map(s => s.trim());
// Optional: explicitly set PUBLIC_URL to the server's public HTTPS base URL.
// Recommended for production so image URLs are always correct regardless of
// how reverse-proxy headers are forwarded.
// Example: PUBLIC_URL=https://adminnew.marriagestation.com.np
const PUBLIC_URL  = (process.env.PUBLIC_URL || '').replace(/\/$/, '');
// Base URL of the PHP API, used to resolve relative profile-picture paths.
// Defaults to the known production domain; override with API_BASE_URL env var.
const API_BASE_URL = (process.env.API_BASE_URL || 'https://digitallami.com').replace(/\/$/, '');
// Set CALLS_ENABLED=false in .env to disable call signaling while keeping chat working.
// Any value other than the exact string 'false' (including undefined/missing) enables calls.
const CALLS_ENABLED = (process.env.CALLS_ENABLED ?? 'true') !== 'false';

// Ensure upload directory exists
['chat_images', 'voice_messages'].forEach(sub => {
  const dir = path.join(UPLOAD_DIR, sub);
  if (!fs.existsSync(dir)) fs.mkdirSync(dir, { recursive: true });
});

// ──────────────────────────────────────────────────────────────────────────────
// MySQL connection pool
// ──────────────────────────────────────────────────────────────────────────────
const pool = mysql.createPool({
  // TODO: Move to environment variable - SECURITY RISK: fallback credentials below must not be used in production
  host:               process.env.DB_HOST     || 'localhost',
  port:               parseInt(process.env.DB_PORT || '3306'),
  user:               process.env.DB_USER     || 'root',
  // TODO: Move to environment variable - SECURITY RISK: hardcoded password fallback
  password:           process.env.DB_PASSWORD || '',
  database:           process.env.DB_NAME     || 'ms',
  waitForConnections: true,
  connectionLimit:    50,
  // 0 = unlimited connection request queuing; safe because we also cap at
  // MAX_QUEUE_SIZE in the message queue, preventing unbounded work growth.
  queueLimit:         0,
  charset:            'utf8mb4',
  // Treat all DATETIME columns as UTC so JS Date objects are serialised/
  // deserialised in UTC regardless of the MySQL server's local timezone.
  timezone:           '+00:00',
});

// Test DB connection on startup and run safe schema migrations
pool.getConnection()
  .then(async conn => {
    console.log('✅ MySQL connected');
    const dbName = process.env.DB_NAME || 'ms';

    // Ensure this session uses UTC so UTC_TIMESTAMP() / NOW() return UTC values.
    await conn.query("SET time_zone = '+00:00'");
    console.log('✅ MySQL session timezone set to UTC');

    // ── Create core chat tables if they do not yet exist (idempotent) ─────────
    // These tables must exist before any column-migration or index-creation
    // step below.  On a fresh deployment the server previously relied on the
    // operator running sql/chat_tables.sql by hand; now it is fully automatic.

    // chat_rooms — one row per unique user-pair conversation.
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`chat_rooms\` (
        \`id\`                     VARCHAR(150) NOT NULL,
        \`participants\`           JSON         NOT NULL,
        \`participant_names\`      JSON         NOT NULL,
        \`participant_images\`     JSON         NOT NULL,
        \`last_message\`           TEXT,
        \`last_message_type\`      VARCHAR(50)  DEFAULT 'text',
        \`last_message_time\`      DATETIME     DEFAULT CURRENT_TIMESTAMP,
        \`last_message_sender_id\` VARCHAR(50)  DEFAULT '',
        \`created_at\`             DATETIME     DEFAULT CURRENT_TIMESTAMP,
        \`updated_at\`             DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        PRIMARY KEY (\`id\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ chat_rooms table ready');

    // chat_unread_counts — per-room, per-user unread message counter.
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`chat_unread_counts\` (
        \`chat_room_id\` VARCHAR(150) NOT NULL,
        \`user_id\`      VARCHAR(50)  NOT NULL,
        \`unread_count\` INT          NOT NULL DEFAULT 0,
        PRIMARY KEY (\`chat_room_id\`, \`user_id\`),
        CONSTRAINT \`fk_unread_room\` FOREIGN KEY (\`chat_room_id\`)
          REFERENCES \`chat_rooms\` (\`id\`) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ chat_unread_counts table ready');

    // chat_messages — individual messages.
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`chat_messages\` (
        \`id\`                      BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        \`message_id\`              VARCHAR(100) NOT NULL UNIQUE,
        \`chat_room_id\`            VARCHAR(150) NOT NULL,
        \`sender_id\`               VARCHAR(50)  NOT NULL,
        \`receiver_id\`             VARCHAR(50)  NOT NULL,
        \`message\`                 TEXT,
        \`message_type\`            VARCHAR(50)  NOT NULL DEFAULT 'text',
        \`is_read\`                 TINYINT(1)   NOT NULL DEFAULT 0,
        \`is_delivered\`            TINYINT(1)   NOT NULL DEFAULT 0,
        \`is_deleted_for_sender\`   TINYINT(1)   NOT NULL DEFAULT 0,
        \`is_deleted_for_receiver\` TINYINT(1)   NOT NULL DEFAULT 0,
        \`is_edited\`               TINYINT(1)   NOT NULL DEFAULT 0,
        \`edited_at\`               DATETIME,
        \`replied_to\`              JSON,
        \`liked\`                   TINYINT(1)   NOT NULL DEFAULT 0,
        \`is_unsent\`               TINYINT(1)   NOT NULL DEFAULT 0,
        \`reactions\`               TEXT         NULL DEFAULT NULL,
        \`created_at\`              DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        INDEX \`idx_chat_room_time\` (\`chat_room_id\`, \`created_at\`),
        INDEX \`idx_created_at\`    (\`created_at\`),
        INDEX \`idx_sender\`        (\`sender_id\`),
        INDEX \`idx_receiver\`      (\`receiver_id\`),
        CONSTRAINT \`fk_msg_room\` FOREIGN KEY (\`chat_room_id\`)
          REFERENCES \`chat_rooms\` (\`id\`) ON DELETE CASCADE
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ chat_messages table ready');

    // user_online_status — per-user online/last-seen record.
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`user_online_status\` (
        \`user_id\`             VARCHAR(50)  NOT NULL PRIMARY KEY,
        \`is_online\`           TINYINT(1)   NOT NULL DEFAULT 0,
        \`last_seen\`           DATETIME     DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
        \`active_chat_room_id\` VARCHAR(150) DEFAULT NULL
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ user_online_status table ready');

    // Add `liked` column to chat_messages if not present (idempotent).
    const [[col]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'liked'
        LIMIT 1`,
      [dbName],
    );
    if (!col) {
      await conn.query(
        `ALTER TABLE chat_messages ADD COLUMN liked TINYINT(1) NOT NULL DEFAULT 0`
      );
      console.log('✅ Added liked column to chat_messages');
    }

    // Add `is_unsent` column to chat_messages if not present (idempotent).
    const [[colUnsent]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'is_unsent'
        LIMIT 1`,
      [dbName],
    );
    if (!colUnsent) {
      await conn.query(
        `ALTER TABLE chat_messages ADD COLUMN is_unsent TINYINT(1) NOT NULL DEFAULT 0`
      );
      console.log('✅ Added is_unsent column to chat_messages');
    }

    // Create call_history table if not present (idempotent).
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`call_history\` (
        \`id\`              BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        \`call_id\`         VARCHAR(100) NOT NULL UNIQUE,
        \`caller_id\`       VARCHAR(50)  NOT NULL,
        \`caller_name\`     VARCHAR(200) DEFAULT '',
        \`caller_image\`    VARCHAR(500) DEFAULT '',
        \`recipient_id\`    VARCHAR(50)  NOT NULL,
        \`recipient_name\`  VARCHAR(200) DEFAULT '',
        \`recipient_image\` VARCHAR(500) DEFAULT '',
        \`call_type\`       ENUM('audio','video') NOT NULL DEFAULT 'audio',
        \`start_time\`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \`end_time\`        DATETIME     DEFAULT NULL,
        \`duration\`        INT          NOT NULL DEFAULT 0,
        \`status\`          ENUM('completed','missed','declined','cancelled') NOT NULL DEFAULT 'missed',
        \`initiated_by\`    VARCHAR(50)  NOT NULL,
        INDEX \`idx_caller\`     (\`caller_id\`),
        INDEX \`idx_recipient\`  (\`recipient_id\`),
        INDEX \`idx_start_time\` (\`start_time\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ call_history table ready');

    // Create group_calls table if not present (idempotent).
    // Tracks admin-initiated group call sessions with a dynamic participant list.
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`group_calls\` (
        \`id\`           BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        \`channel_name\` VARCHAR(150) NOT NULL UNIQUE,
        \`call_type\`    ENUM('audio','video') NOT NULL DEFAULT 'audio',
        \`admin_id\`     VARCHAR(50)  NOT NULL DEFAULT '1',
        \`participants\` JSON         NOT NULL,
        \`status\`       ENUM('active','ended') NOT NULL DEFAULT 'active',
        \`started_at\`   DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \`ended_at\`     DATETIME     DEFAULT NULL,
        INDEX \`idx_gc_channel\`  (\`channel_name\`),
        INDEX \`idx_gc_admin\`    (\`admin_id\`),
        INDEX \`idx_gc_started\`  (\`started_at\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ group_calls table ready');

    // Create user_activities table if not present (idempotent).
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`user_activities\` (
        \`id\`            BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        \`user_id\`       INT          NOT NULL,
        \`user_name\`     VARCHAR(200) DEFAULT '',
        \`target_id\`     INT          DEFAULT NULL,
        \`target_name\`   VARCHAR(200) DEFAULT NULL,
        \`activity_type\` ENUM(
          'like_sent','like_removed','message_sent',
          'request_sent','request_accepted','request_rejected',
          'call_made','call_received','profile_viewed',
          'login','logout','photo_uploaded','package_bought'
        ) NOT NULL,
        \`description\`   TEXT,
        \`created_at\`    DATETIME DEFAULT CURRENT_TIMESTAMP,
        INDEX \`idx_ua_user_id\`       (\`user_id\`),
        INDEX \`idx_ua_created_at\`    (\`created_at\`),
        INDEX \`idx_ua_activity_type\` (\`activity_type\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ user_activities table ready');

    // Create blocks table if not present (idempotent).
    await conn.query(`
      CREATE TABLE IF NOT EXISTS \`blocks\` (
        \`id\`         BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY,
        \`blocker_id\` INT NOT NULL,
        \`blocked_id\` INT NOT NULL,
        \`created_at\` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        UNIQUE KEY \`uq_block\` (\`blocker_id\`, \`blocked_id\`),
        INDEX \`idx_blocker\` (\`blocker_id\`),
        INDEX \`idx_blocked\` (\`blocked_id\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ blocks table ready');

    // Ensure standalone index on created_at for range queries (idempotent).
    const [[idxCreatedAt]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'chat_messages' AND INDEX_NAME = 'idx_created_at'
        LIMIT 1`,
      [dbName],
    );
    if (!idxCreatedAt) {
      await conn.query(
        `ALTER TABLE chat_messages ADD INDEX idx_created_at (created_at)`
      ).catch(e => console.warn('idx_created_at already exists:', e.message));
      console.log('✅ Added idx_created_at index to chat_messages');
    }

    // Add `reactions` column to chat_messages if not present (idempotent).
    // Stores a JSON object of { userId: emoji } e.g. { "3": "❤️", "7": "😂" }
    const [[colReactions]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'chat_messages' AND COLUMN_NAME = 'reactions'
        LIMIT 1`,
      [dbName],
    );
    if (!colReactions) {
      await conn.query(
        `ALTER TABLE chat_messages ADD COLUMN reactions TEXT NULL DEFAULT NULL`
      );
      console.log('✅ Added reactions column to chat_messages');
    }

    // Ensure index on users.isOnline for fast dashboard online count queries (idempotent).
    const [[idxIsOnline]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'users' AND INDEX_NAME = 'idx_isOnline'
        LIMIT 1`,
      [dbName],
    );
    if (!idxIsOnline) {
      await conn.query(
        `ALTER TABLE users ADD INDEX idx_isOnline (isOnline, isDelete)`
      ).catch(e => console.warn('idx_isOnline already exists:', e.message));
      console.log('✅ Added idx_isOnline index to users table for dashboard queries');
    }

    // Ensure composite index on chat_messages(sender_id, receiver_id, created_at)
    // for efficient queries that filter by both participants and sort by time.
    const [[idxChat]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'chat_messages' AND INDEX_NAME = 'idx_sender_receiver_time'
        LIMIT 1`,
      [dbName],
    );
    if (!idxChat) {
      await conn.query(
        `ALTER TABLE chat_messages ADD INDEX idx_sender_receiver_time (sender_id, receiver_id, created_at)`
      ).catch(e => console.warn('idx_sender_receiver_time already exists:', e.message));
      console.log('✅ Added idx_sender_receiver_time index to chat_messages');
    }

    conn.release();
  })
  .catch(err => { console.error('❌ MySQL connection failed:', err.message); });

// ──────────────────────────────────────────────────────────────────────────────
// Rate limiting & in-memory message queue
// ──────────────────────────────────────────────────────────────────────────────
const RATE_LIMIT_MAX  = 10;     // max messages a socket may send per second
const RATE_LIMIT_WIN  = 1000;   // sliding window in ms
const BATCH_INTERVAL  = 750;    // worker fires every 750 ms
const BATCH_SIZE      = 200;    // max messages processed per worker tick
const MAX_QUEUE_SIZE  = 10000;  // hard cap; oldest entries dropped when exceeded
const MAX_RETRIES     = 3;      // retry failed batch inserts up to this many times

/** socketId → { count, windowStart } */
const socketRateLimits = new Map();

/**
 * Returns true if the socket has exceeded RATE_LIMIT_MAX messages in the
 * current RATE_LIMIT_WIN window.  Increments the counter otherwise.
 */
function isRateLimited(socketId) {
  const now = Date.now();
  const rl  = socketRateLimits.get(socketId);
  if (!rl || (now - rl.windowStart) >= RATE_LIMIT_WIN) {
    socketRateLimits.set(socketId, { count: 1, windowStart: now });
    return false;
  }
  rl.count += 1;
  return rl.count > RATE_LIMIT_MAX;
}

/**
 * Queue of pending message objects.
 * Shape: { messageId, chatRoomId, senderId, receiverId, message, messageType,
 *          isRead, isDelivered, repliedTo, timestamp,
 *          user1Name, user2Name, user1Image, user2Image, _retries }
 */
const messageQueue = [];

// ──────────────────────────────────────────────────────────────────────────────
// Express + Socket.IO setup
// ──────────────────────────────────────────────────────────────────────────────
const app    = express();
// Trust reverse-proxy headers (X-Forwarded-Proto, X-Forwarded-For) so that
// req.protocol returns 'https' when running behind nginx/Apache.
app.set('trust proxy', 1);
const server = http.createServer(app);
const io     = new Server(server, {
  cors: {
    origin: ALLOWED_ORIGINS.includes('*') ? '*' : ALLOWED_ORIGINS,
    methods: ['GET', 'POST'],
  },
  pingTimeout:       60000,
  pingInterval:      25000,
  maxHttpBufferSize: 1e6,  // 1 MB — prevents large-payload DoS attacks
});

app.use(cors({
  origin: ALLOWED_ORIGINS.includes('*') ? '*' : ALLOWED_ORIGINS,
  methods: ['GET', 'POST', 'OPTIONS'],
}));
app.use(express.json());
app.use('/uploads', express.static(UPLOAD_DIR));

// ──────────────────────────────────────────────────────────────────────────────
// File upload (multer)
// ──────────────────────────────────────────────────────────────────────────────
const storage = multer.diskStorage({
  destination: (req, _file, cb) => {
    const type = req.query.type || 'chat_images';
    cb(null, path.join(UPLOAD_DIR, type === 'voice' ? 'voice_messages' : 'chat_images'));
  },
  filename: (_req, file, cb) => {
    const ext  = path.extname(file.originalname) || '.jpg';
    cb(null, `${uuidv4()}${ext}`);
  },
});
const upload = multer({ storage, limits: { fileSize: 25 * 1024 * 1024 } }); // 25 MB

// Allowed MIME types per upload category
const ALLOWED_IMAGE_MIMES = new Set([
  'image/jpeg', 'image/png', 'image/gif', 'image/webp', 'image/heic', 'image/heif',
]);
const ALLOWED_VOICE_MIMES = new Set([
  'audio/mpeg', 'audio/mp4', 'audio/webm', 'audio/ogg', 'audio/wav', 'audio/aac',
  'audio/x-m4a', 'application/octet-stream',
]);

/** Build a public URL for an uploaded file.
 *  When PUBLIC_URL is set in the environment it is used as the base, giving
 *  operators an explicit override that is immune to proxy-header variations.
 *  Otherwise the URL is derived from the incoming request (req.protocol is
 *  correct because trust proxy is enabled, so nginx's X-Forwarded-Proto is
 *  respected).
 */
function buildFileUrl(req, subDir, filename) {
  const base = PUBLIC_URL || `${req.protocol}://${req.get('host')}`;
  return `${base}/uploads/${subDir}/${filename}`;
}

// POST /upload?type=image|voice
app.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  const isVoice = req.query.type === 'voice';
  const subDir = isVoice ? 'voice_messages' : 'chat_images';
  const allowed = isVoice ? ALLOWED_VOICE_MIMES : ALLOWED_IMAGE_MIMES;
  if (!allowed.has(req.file.mimetype)) {
    return res.status(400).json({ error: 'File type not allowed' });
  }
  res.json({ url: buildFileUrl(req, subDir, req.file.filename) });
});

// POST /upload-multiple?type=image
// Accepts up to 10 image files under the field name 'files' and returns
// an array of public URLs so the admin can send image_gallery messages.
app.post('/upload-multiple', upload.array('files', 10), (req, res) => {
  if (!req.files || req.files.length === 0) {
    return res.status(400).json({ error: 'No files uploaded' });
  }
  const subDir = 'chat_images';
  const invalidFile = req.files.find(f => !ALLOWED_IMAGE_MIMES.has(f.mimetype));
  if (invalidFile) {
    return res.status(400).json({ error: 'One or more files have a disallowed type' });
  }
  const urls = req.files.map(f => buildFileUrl(req, subDir, f.filename));
  res.json({ urls });
});

// GET /health
app.get('/health', (_req, res) => res.json({ status: 'ok', time: new Date() }));

// ──────────────────────────────────────────────────────────────────────────────
// Activity logging helper
// ──────────────────────────────────────────────────────────────────────────────
const VALID_ACTIVITY_TYPES = new Set([
  'like_sent','like_removed','message_sent',
  'request_sent','request_accepted','request_rejected',
  'call_made','call_received','profile_viewed',
  'login','logout','photo_uploaded','package_bought',
]);

/**
 * Masks sensitive data (e.g. phone numbers) in a string.
 * Replaces all but the first two and last two digits of any 8-15 digit
 * phone-like sequence with asterisks.
 * @param {string} text
 * @returns {string}
 */
function maskSensitiveData(text) {
  if (typeof text !== 'string') return String(text ?? '');
  // Match optional leading '+', then 8–15 digits (with spaces or dashes between)
  return text.replace(/\+?(?:\d[\s\-]?){7,14}\d/g, (match) => {
    const digits = match.replace(/\D/g, '');
    if (digits.length < 8) return match;
    return digits.slice(0, 2) + '*'.repeat(digits.length - 4) + digits.slice(-2);
  });
}

/**
 * Safely parses a JSON string field from a DB row.
 * Returns null if the value is null / undefined or cannot be parsed.
 * @param {any} value
 * @returns {any}
 */
function parseJsonField(value) {
  if (!value) return null;
  try { return JSON.parse(value); } catch (_) { return null; }
}

async function logActivity({ userId, userName = '', targetId = null, targetName = null, activityType, description = '' }) {
  if (!userId || !VALID_ACTIVITY_TYPES.has(activityType)) return;
  try {
    const [result] = await pool.query(
      `INSERT INTO user_activities (user_id, user_name, target_id, target_name, activity_type, description)
       VALUES (?, ?, ?, ?, ?, ?)`,
      [userId, userName, targetId || null, targetName || null, activityType, description],
    );
    // Emit real-time activity event to the admin room so the admin panel
    // updates immediately without waiting for its polling interval.
    io.to('admin_activity').emit('user_activity', {
      id:            result.insertId,
      user_id:       userId,
      user_name:     userName,
      target_id:     targetId || null,
      target_name:   targetName || null,
      activity_type: activityType,
      description,
      created_at:    new Date().toISOString(),
    });
  } catch (err) {
    console.error('logActivity error:', err.message);
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// Call History REST API
// ──────────────────────────────────────────────────────────────────────────────

// POST /api/calls — Log a new call (UPSERT to prevent duplicates)
app.post('/api/calls', async (req, res) => {
  try {
    const {
      callId, callerId, callerName = '', callerImage = '',
      recipientId, recipientName = '', recipientImage = '',
      callType = 'audio', initiatedBy,
    } = req.body;

    if (!callId || !callerId || !recipientId || !initiatedBy) {
      return res.status(400).json({ error: 'callId, callerId, recipientId, initiatedBy are required' });
    }

    // Use INSERT ... ON DUPLICATE KEY UPDATE to ensure ONE call = ONE record
    // If call_id already exists, only update start_time if it's the first insert
    await pool.query(
      `INSERT INTO call_history
         (call_id, caller_id, caller_name, caller_image,
          recipient_id, recipient_name, recipient_image,
          call_type, start_time, status, initiated_by)
       VALUES (?,?,?,?,?,?,?,?,UTC_TIMESTAMP(),'missed',?)
       ON DUPLICATE KEY UPDATE
         call_id = call_id`,
      [callId, callerId, callerName, callerImage,
       recipientId, recipientName, recipientImage,
       callType === 'video' ? 'video' : 'audio', initiatedBy],
    );

    // Log call_made for caller, call_received for recipient
    await logActivity({
      userId: callerId, userName: callerName,
      targetId: recipientId, targetName: recipientName,
      activityType: 'call_made',
      description: `${callerName || 'User '+callerId} le ${recipientName || 'User '+recipientId} lai ${callType} call garyo`,
    });
    await logActivity({
      userId: recipientId, userName: recipientName,
      targetId: callerId, targetName: callerName,
      activityType: 'call_received',
      description: `${recipientName || 'User '+recipientId} le ${callerName || 'User '+callerId} bata ${callType} call payo`,
    });

    res.json({ success: true, callId });
  } catch (err) {
    console.error('POST /api/calls error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /api/calls/:callId — Update call end (duration is calculated server-side from timestamps)
app.put('/api/calls/:callId', async (req, res) => {
  try {
    const { callId } = req.params;
    const { status } = req.body;

    const allowed = ['completed', 'missed', 'declined', 'cancelled'];
    const safeStatus = allowed.includes(status) ? status : 'missed';

    await pool.query(
      `UPDATE call_history
          SET end_time = UTC_TIMESTAMP(),
              duration = GREATEST(0, TIMESTAMPDIFF(SECOND, start_time, UTC_TIMESTAMP())),
              status   = ?
        WHERE call_id = ? AND end_time IS NULL`,
      [safeStatus, callId],
    );
    res.json({ success: true });
  } catch (err) {
    console.error('PUT /api/calls/:callId error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/calls?userId=xxx[&limit=50] — Get call history for a user
app.get('/api/calls', async (req, res) => {
  try {
    const userId  = (req.query.userId  || '').toString();
    const limit   = Math.min(parseInt(req.query.limit || '100', 10), 200);

    if (!userId) return res.status(400).json({ error: 'userId is required' });

    const [rows] = await pool.query(
      `SELECT * FROM call_history
        WHERE caller_id = ? OR recipient_id = ?
        ORDER BY start_time DESC
        LIMIT ?`,
      [userId, userId, limit],
    );

    const calls = rows.map(r => ({
      callId:         r.call_id,
      callerId:       r.caller_id,
      callerName:     r.caller_name,
      callerImage:    r.caller_image,
      recipientId:    r.recipient_id,
      recipientName:  r.recipient_name,
      recipientImage: r.recipient_image,
      callType:       r.call_type,
      startTime:      r.start_time ? r.start_time.toISOString() : null,
      endTime:        r.end_time   ? r.end_time.toISOString()   : null,
      duration:       r.duration,
      status:         r.status,
      initiatedBy:    r.initiated_by,
    }));

    res.json({ success: true, calls });
  } catch (err) {
    console.error('GET /api/calls error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /api/calls/:callId — Delete a specific call record
app.delete('/api/calls/:callId', async (req, res) => {
  try {
    await pool.query('DELETE FROM call_history WHERE call_id = ?', [req.params.callId]);
    res.json({ success: true });
  } catch (err) {
    console.error('DELETE /api/calls/:callId error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// DELETE /api/calls/user/:userId — Clear all call history for a user
app.delete('/api/calls/user/:userId', async (req, res) => {
  try {
    const userId = req.params.userId;
    await pool.query(
      'DELETE FROM call_history WHERE caller_id = ? OR recipient_id = ?',
      [userId, userId],
    );
    res.json({ success: true });
  } catch (err) {
    console.error('DELETE /api/calls/user/:userId error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// Group Call REST API
// ──────────────────────────────────────────────────────────────────────────────

// GET /api/group-calls?limit=50 — List recent group calls (admin use).
app.get('/api/group-calls', async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 200);
    const [rows] = await pool.query(
      `SELECT * FROM group_calls ORDER BY started_at DESC LIMIT ?`,
      [limit],
    );
    const calls = rows.map(r => ({
      id:           r.id,
      channelName:  r.channel_name,
      callType:     r.call_type,
      adminId:      r.admin_id,
      participants: (() => { try { return JSON.parse(r.participants); } catch (_) { return []; } })(),
      status:       r.status,
      startedAt:    r.started_at ? r.started_at.toISOString() : null,
      endedAt:      r.ended_at   ? r.ended_at.toISOString()   : null,
    }));
    res.json({ success: true, calls });
  } catch (err) {
    console.error('GET /api/group-calls error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/group-calls/:channelName — Get a specific group call by channel name.
app.get('/api/group-calls/:channelName', async (req, res) => {
  try {
    const { channelName } = req.params;
    const [[row]] = await pool.query(
      'SELECT * FROM group_calls WHERE channel_name = ? LIMIT 1',
      [channelName],
    );
    if (!row) return res.status(404).json({ error: 'Group call not found' });
    res.json({
      success:      true,
      channelName:  row.channel_name,
      callType:     row.call_type,
      adminId:      row.admin_id,
      participants: (() => { try { return JSON.parse(row.participants); } catch (_) { return []; } })(),
      status:       row.status,
      startedAt:    row.started_at ? row.started_at.toISOString() : null,
      endedAt:      row.ended_at   ? row.ended_at.toISOString()   : null,
    });
  } catch (err) {
    console.error('GET /api/group-calls/:channelName error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/admin/call-history — Admin endpoint for call history with participant details
app.get('/api/admin/call-history', requireAdminToken, async (req, res) => {
  try {
    const limit = Math.min(parseInt(req.query.limit || '50', 10), 200);
    const page = Math.max(1, parseInt(req.query.page || '1', 10));
    const offset = (page - 1) * limit;

    // Count total call history records
    const [[{ total }]] = await pool.query(
      'SELECT COUNT(*) AS total FROM call_history'
    );

    // Fetch call history with participant details (JOIN with users table)
    const [rows] = await pool.query(
      `SELECT
          ch.id,
          ch.call_id,
          ch.caller_id,
          ch.caller_name,
          ch.caller_image,
          ch.recipient_id,
          ch.recipient_name,
          ch.recipient_image,
          ch.call_type,
          ch.start_time,
          ch.end_time,
          ch.duration,
          ch.status,
          ch.initiated_by,
          u1.firstName AS caller_first_name,
          u1.lastName AS caller_last_name,
          u1.profile_picture AS caller_profile_pic,
          u2.firstName AS recipient_first_name,
          u2.lastName AS recipient_last_name,
          u2.profile_picture AS recipient_profile_pic
       FROM call_history ch
       LEFT JOIN users u1 ON ch.caller_id = u1.id
       LEFT JOIN users u2 ON ch.recipient_id = u2.id
       ORDER BY ch.start_time DESC
       LIMIT ? OFFSET ?`,
      [limit, offset]
    );

    const calls = rows.map(r => ({
      id: r.id,
      callId: r.call_id,
      callType: r.call_type,
      startTime: r.start_time ? r.start_time.toISOString() : null,
      endTime: r.end_time ? r.end_time.toISOString() : null,
      duration: r.duration,
      status: r.status,
      initiatedBy: r.initiated_by,
      participants: [
        {
          id: r.caller_id,
          name: r.caller_name || `${r.caller_first_name || ''} ${r.caller_last_name || ''}`.trim(),
          avatar: r.caller_image || (r.caller_profile_pic ?
            (r.caller_profile_pic.startsWith('http') ?
              r.caller_profile_pic :
              `${API_BASE_URL}/${r.caller_profile_pic}`) :
            null),
          role: 'caller',
        },
        {
          id: r.recipient_id,
          name: r.recipient_name || `${r.recipient_first_name || ''} ${r.recipient_last_name || ''}`.trim(),
          avatar: r.recipient_image || (r.recipient_profile_pic ?
            (r.recipient_profile_pic.startsWith('http') ?
              r.recipient_profile_pic :
              `${API_BASE_URL}/${r.recipient_profile_pic}`) :
            null),
          role: 'recipient',
        },
      ],
    }));

    res.json({
      success: true,
      total: Number(total),
      page,
      limit,
      pages: Math.ceil(Number(total) / limit),
      calls,
    });
  } catch (err) {
    console.error('GET /api/admin/call-history error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/admin/dashboard-stats — Admin dashboard statistics API
app.get('/api/admin/dashboard-stats', requireAdminToken, async (req, res) => {
  try {
    // Total users count
    const [[{ totalUsers }]] = await pool.query(
      'SELECT COUNT(*) AS totalUsers FROM users'
    );

    // Online users count (from user_online_status where is_online = 1)
    const [[{ onlineUsers }]] = await pool.query(
      'SELECT COUNT(*) AS onlineUsers FROM user_online_status WHERE is_online = 1'
    );

    // Active calls count (group_calls where status = 'active' OR call_history where end_time IS NULL)
    const [[{ activeCalls }]] = await pool.query(
      `SELECT COUNT(*) AS activeCalls
       FROM (
         SELECT 1 FROM group_calls WHERE status = 'active'
         UNION ALL
         SELECT 1 FROM call_history WHERE end_time IS NULL
       ) AS active_calls_union`
    );

    // Total calls today
    const [[{ totalCallsToday }]] = await pool.query(
      `SELECT COUNT(*) AS totalCallsToday
       FROM call_history
       WHERE DATE(start_time) = CURDATE()`
    );

    // Recent activities (limit 20, sorted by created_at DESC)
    const [recentActivities] = await pool.query(
      `SELECT
          ua.id,
          ua.user_id,
          ua.user_name,
          ua.activity_type,
          ua.description,
          ua.target_id,
          ua.target_name,
          ua.created_at,
          u.firstName,
          u.lastName,
          u.profile_picture
       FROM user_activities ua
       LEFT JOIN users u ON ua.user_id = u.id
       ORDER BY ua.created_at DESC
       LIMIT 20`
    );

    // Format recent activities
    const formattedActivities = recentActivities.map(a => ({
      id: a.id,
      userId: a.user_id,
      userName: a.user_name || `${a.firstName || ''} ${a.lastName || ''}`.trim() || `User ${a.user_id}`,
      activityType: a.activity_type,
      description: a.description,
      targetId: a.target_id,
      targetName: a.target_name,
      createdAt: a.created_at ? a.created_at.toISOString() : null,
      userAvatar: a.profile_picture ?
        (a.profile_picture.startsWith('http') ?
          a.profile_picture :
          `${API_BASE_URL}/${a.profile_picture}`) :
        null,
    }));

    res.json({
      success: true,
      stats: {
        totalUsers: Number(totalUsers),
        onlineUsers: Number(onlineUsers),
        activeCalls: Number(activeCalls),
        totalCallsToday: Number(totalCallsToday),
      },
      recentActivities: formattedActivities,
    });
  } catch (err) {
    console.error('GET /api/admin/dashboard-stats error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// Call Join List API — Gender-based user filtering for group calls
// ──────────────────────────────────────────────────────────────────────────────

/**
 * GET /api/call-join-list?userId=xxx[&cursor=xxx]
 *
 * Returns users available for joining a group call with gender-based filtering:
 * - Male users see ONLY female users
 * - Female users see ONLY male users
 *
 * Sorting:
 * 1. Online users first (isOnline = true)
 * 2. Then by lastSeen DESC (most recently active)
 *
 * Pagination:
 * - Limit: 15 users per request
 * - Cursor-based (no offset duplication)
 * - Returns: { users: [], nextCursor: "", hasMore: boolean }
 */
app.get('/api/call-join-list', async (req, res) => {
  try {
    const userId = (req.query.userId || '').toString().trim();
    const cursor = (req.query.cursor || '').toString().trim();
    const limit = 15;

    if (!userId) {
      return res.status(400).json({ error: 'userId is required' });
    }

    // Get current user's gender
    const [[currentUser]] = await pool.query(
      'SELECT id, gender FROM users WHERE id = ? LIMIT 1',
      [userId]
    );

    if (!currentUser) {
      return res.status(404).json({ error: 'User not found' });
    }

    // Determine opposite gender (male sees female, female sees male)
    const oppositeGender = currentUser.gender === 'Male' ? 'Female' : 'Male';

    // Build query with cursor-based pagination
    let query = `
      SELECT
        u.id,
        u.firstName,
        u.lastName,
        u.gender,
        u.profile_picture,
        u.isOnline,
        u.lastLogin,
        COALESCE(uos.is_online, 0) AS is_online_status,
        COALESCE(uos.last_seen, u.lastLogin) AS last_seen
      FROM users u
      LEFT JOIN user_online_status uos ON u.id = uos.user_id
      WHERE u.gender = ?
        AND u.id != ?
    `;

    const params = [oppositeGender, userId];

    // Apply cursor for pagination (cursor is last user's sort key: "isOnline_lastSeen_id")
    if (cursor) {
      const [cursorIsOnline, cursorLastSeen, cursorId] = cursor.split('_');
      query += `
        AND (
          (COALESCE(uos.is_online, 0) < ?) OR
          (COALESCE(uos.is_online, 0) = ? AND COALESCE(uos.last_seen, u.lastLogin) < ?) OR
          (COALESCE(uos.is_online, 0) = ? AND COALESCE(uos.last_seen, u.lastLogin) = ? AND u.id > ?)
        )
      `;
      params.push(
        cursorIsOnline, cursorIsOnline, cursorLastSeen,
        cursorIsOnline, cursorLastSeen, cursorId
      );
    }

    // Sort: online first, then by last_seen DESC, then by id ASC for stability
    query += `
      ORDER BY
        COALESCE(uos.is_online, 0) DESC,
        COALESCE(uos.last_seen, u.lastLogin) DESC,
        u.id ASC
      LIMIT ?
    `;
    params.push(limit + 1); // Fetch one extra to determine if there are more

    const [rows] = await pool.query(query, params);

    // Check if there are more results
    const hasMore = rows.length > limit;
    const users = rows.slice(0, limit);

    // Generate next cursor from last user
    let nextCursor = '';
    if (hasMore && users.length > 0) {
      const lastUser = users[users.length - 1];
      const isOnline = lastUser.is_online_status || 0;
      const lastSeen = lastUser.last_seen ?
        new Date(lastUser.last_seen).toISOString() :
        new Date().toISOString();
      nextCursor = `${isOnline}_${lastSeen}_${lastUser.id}`;
    }

    // Format response
    const formattedUsers = users.map(u => ({
      id: u.id.toString(),
      name: `${u.firstName || ''} ${u.lastName || ''}`.trim(),
      firstName: u.firstName || '',
      lastName: u.lastName || '',
      gender: u.gender,
      profilePicture: u.profile_picture ?
        (u.profile_picture.startsWith('http') ?
          u.profile_picture :
          `${API_BASE_URL}/${u.profile_picture}`) :
        null,
      isOnline: !!(u.is_online_status || u.isOnline),
      lastSeen: u.last_seen ? new Date(u.last_seen).toISOString() : null,
    }));

    res.json({
      success: true,
      users: formattedUsers,
      nextCursor,
      hasMore,
    });

  } catch (err) {
    console.error('GET /api/call-join-list error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// Admin REST API — chat history
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Middleware: verifies the Authorization: Bearer <token> header against the
 * admin_tokens table that is shared with the PHP backend.
 * On success, attaches req.adminId.
 * On failure, returns 401.
 */
async function requireAdminToken(req, res, next) {
  const authHeader = (req.headers['authorization'] || '').trim();
  const match = authHeader.match(/^Bearer\s+(\S+)$/i);
  if (!match) {
    return res.status(401).json({ error: 'Authorization token required' });
  }

  const token = match[1];
  try {
    const [[row]] = await pool.query(
      `SELECT a.id, a.is_active
         FROM admin_tokens t
         JOIN admins a ON a.id = t.admin_id
        WHERE t.token = ? AND t.expires_at > NOW()
        LIMIT 1`,
      [token],
    );

    if (!row) {
      return res.status(401).json({ error: 'Invalid or expired token' });
    }
    if (!row.is_active) {
      return res.status(403).json({ error: 'Admin account is disabled' });
    }

    req.adminId = row.id;
    next();
  } catch (err) {
    console.error('requireAdminToken error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
}

/**
 * GET /api/admin/chat-history
 *
 * Returns paginated chat messages for admin monitoring.
 * Requires a valid admin bearer token (same token issued by the PHP login endpoint).
 *
 * Query params (all optional):
 *   chatRoomId  – filter to one chat room
 *   userId      – filter to messages where sender_id OR receiver_id = userId
 *   user1Id     – \
 *   user2Id     –  } filter to the exact chat room that contains both users
 *   page        – (default 1)
 *   limit       – (default 50, max 200)
 *
 * Response:
 *   { success, total, page, limit, pages, messages: [ { ... } ] }
 */
app.get('/api/admin/chat-history', requireAdminToken, async (req, res) => {
  try {
    const limit   = Math.min(parseInt(req.query.limit || '50', 10), 200);
    const page    = Math.max(1, parseInt(req.query.page || '1', 10));
    const offset  = (page - 1) * limit;

    const chatRoomId = (req.query.chatRoomId || '').toString().trim();
    const userId     = (req.query.userId     || '').toString().trim();
    const user1Id    = (req.query.user1Id    || '').toString().trim();
    const user2Id    = (req.query.user2Id    || '').toString().trim();

    const where  = [];
    const params = [];

    if (chatRoomId) {
      where.push('m.chat_room_id = ?');
      params.push(chatRoomId);
    } else if (user1Id && user2Id) {
      // The chat room id contains both user IDs — use JSON_CONTAINS on chat_rooms
      where.push(
        `m.chat_room_id IN (
           SELECT id FROM chat_rooms
            WHERE JSON_CONTAINS(participants, JSON_QUOTE(?))
              AND JSON_CONTAINS(participants, JSON_QUOTE(?))
         )`,
      );
      params.push(user1Id, user2Id);
    } else if (userId) {
      where.push('(m.sender_id = ? OR m.receiver_id = ?)');
      params.push(userId, userId);
    }

    const whereSQL = where.length ? `WHERE ${where.join(' AND ')}` : '';

    // Count
    const [[{ total }]] = await pool.query(
      `SELECT COUNT(*) AS total FROM chat_messages m ${whereSQL}`,
      params,
    );

    // Data
    const [rows] = await pool.query(
      `SELECT
          m.message_id     AS messageId,
          m.chat_room_id   AS chatRoomId,
          m.sender_id      AS senderId,
          m.receiver_id    AS receiverId,
          m.message,
          m.message_type   AS messageType,
          m.is_read        AS isRead,
          m.is_delivered   AS isDelivered,
          m.is_deleted_for_sender   AS isDeletedForSender,
          m.is_deleted_for_receiver AS isDeletedForReceiver,
          m.is_edited      AS isEdited,
          m.is_unsent      AS isUnsent,
          m.liked,
          m.replied_to     AS repliedTo,
          m.created_at     AS timestamp,
          CONCAT(u1.firstName, ' ', u1.lastName) AS senderName,
          CONCAT(u2.firstName, ' ', u2.lastName) AS receiverName
       FROM chat_messages m
       LEFT JOIN users u1 ON u1.id = m.sender_id
       LEFT JOIN users u2 ON u2.id = m.receiver_id
       ${whereSQL}
       ORDER BY m.created_at DESC
       LIMIT ? OFFSET ?`,
      [...params, limit, offset],
    );

    const messages = rows.map(r => ({
      messageId:            r.messageId,
      chatRoomId:           r.chatRoomId,
      senderId:             r.senderId,
      receiverId:           r.receiverId,
      senderName:           (r.senderName || '').trim() || `User ${r.senderId}`,
      receiverName:         (r.receiverName || '').trim() || `User ${r.receiverId}`,
      message:              r.message,
      messageType:          r.messageType,
      images:               parseImageUrls(r.messageType, r.message),
      isRead:               r.isRead === 1,
      isDelivered:          r.isDelivered === 1,
      isDeletedForSender:   r.isDeletedForSender === 1,
      isDeletedForReceiver: r.isDeletedForReceiver === 1,
      isEdited:             r.isEdited === 1,
      isUnsent:             r.isUnsent === 1,
      liked:                r.liked === 1,
      repliedTo:            parseJsonField(r.repliedTo),
      timestamp:            r.timestamp ? r.timestamp.toISOString() : null,
    }));

    res.json({
      success: true,
      total:   Number(total),
      page,
      limit,
      pages:   Math.ceil(Number(total) / limit),
      messages,
    });
  } catch (err) {
    console.error('GET /api/admin/chat-history error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// In-memory maps: userId → socketId, userId → Set<chatRoomId>
// ──────────────────────────────────────────────────────────────────────────────
const userSockets    = new Map(); // userId → socketId
const userActiveChatRoom = new Map(); // userId → chatRoomId | null

// Tracks calls that have been sent but not yet answered/rejected/cancelled.
// channelName → { callerId, recipientId, data, createdAt }
// Used to re-deliver incoming_call when recipient connects while call is active.
const activePendingCalls = new Map();
const PENDING_CALL_TTL_MS = 60000; // 60 seconds — matches FCM notification lifetime

// Tracks users who are currently in an active (answered) call.
// userId (string) → channelName (string)
// Used to detect busy state and reject new incoming calls automatically.
const activeCallUsers = new Map();

// Tracks all participants in each active group call channel.
// channelName (string) → Set<userId (string)>
// Allows broadcasting to ALL current participants when a new user is added.
const groupCallParticipants = new Map();

function _cleanExpiredPendingCalls() {
  const now = Date.now();
  for (const [channelName, call] of activePendingCalls) {
    if (now - call.createdAt > PENDING_CALL_TTL_MS) {
      activePendingCalls.delete(channelName);
    }
  }
}

// ──────────────────────────────────────────────────────────────────────────────
// DB helpers
// ──────────────────────────────────────────────────────────────────────────────

/**
 * Upserts the group_calls row for a channel to persist the current participant
 * set.  Uses INSERT … ON DUPLICATE KEY UPDATE so it works both for creation
 * and incremental additions.  Errors are logged but never rethrown so a
 * DB hiccup never crashes the call-signalling flow.
 */
async function persistGroupCallParticipants(channelName, callType, adminId) {
  const participants = groupCallParticipants.get(channelName);
  if (!participants) return;
  const participantsJson = JSON.stringify(Array.from(participants));
  const safeCallType = callType === 'video' ? 'video' : 'audio';
  const safeAdminId = (adminId || '1').toString();
  try {
    await pool.query(
      `INSERT INTO group_calls (channel_name, call_type, admin_id, participants, status)
         VALUES (?, ?, ?, ?, 'active')
       ON DUPLICATE KEY UPDATE
         participants = VALUES(participants),
         admin_id     = VALUES(admin_id),
         call_type    = VALUES(call_type),
         status       = 'active'`,
      [channelName, safeCallType, safeAdminId, participantsJson],
    );
  } catch (err) {
    console.error(`persistGroupCallParticipants error [${channelName}]:`, err.message);
  }
}

/**
 * Marks a group_calls row as ended.
 */
async function endGroupCall(channelName) {
  try {
    await pool.query(
      `UPDATE group_calls SET status = 'ended', ended_at = UTC_TIMESTAMP()
        WHERE channel_name = ? AND status = 'active'`,
      [channelName],
    );
  } catch (err) {
    console.error(`endGroupCall error [${channelName}]:`, err.message);
  }
}

/**
 * Returns true if either user has blocked the other.
 * Treats any DB error as unblocked so that a temporary DB hiccup does not
 * permanently prevent communication.
 */
async function isEitherBlocked(userA, userB) {
  if (!userA || !userB) return false;
  try {
    const [[row]] = await pool.query(
      `SELECT 1 FROM blocks
        WHERE (blocker_id = ? AND blocked_id = ?)
           OR (blocker_id = ? AND blocked_id = ?)
        LIMIT 1`,
      [userA, userB, userB, userA],
    );
    return !!row;
  } catch (_) {
    return false;
  }
}

/** Returns the sender_id for a message, or null if not found / IDs invalid. */
async function getMessageSender(messageId, chatRoomId) {
  if (!messageId || !chatRoomId) return null;
  const safeMessageId  = String(messageId).slice(0, 100);
  const safeChatRoomId = String(chatRoomId).slice(0, 100);
  const [[msg]] = await pool.query(
    'SELECT sender_id FROM chat_messages WHERE message_id = ? AND chat_room_id = ? LIMIT 1',
    [safeMessageId, safeChatRoomId],
  );
  return msg ? msg.sender_id?.toString() ?? null : null;
}

async function ensureChatRoom({ chatRoomId, user1Id, user2Id, user1Name, user2Name, user1Image, user2Image }) {
  const name1  = (user1Name  || '').trim();
  const name2  = (user2Name  || '').trim();
  const image1 = (user1Image || '').trim();
  const image2 = (user2Image || '').trim();

  const namesJson  = JSON.stringify({ [user1Id]: name1,  [user2Id]: name2  });
  const imagesJson = JSON.stringify({ [user1Id]: image1, [user2Id]: image2 });

  // Insert the room if it doesn't exist yet.
  await pool.query(
    `INSERT IGNORE INTO chat_rooms
       (id, participants, participant_names, participant_images, last_message, last_message_type, last_message_time, last_message_sender_id)
     VALUES (?, ?, ?, ?, '', 'text', UTC_TIMESTAMP(), '')`,
    [
      chatRoomId,
      JSON.stringify([user1Id, user2Id]),
      namesJson,
      imagesJson,
    ],
  );

  // If we have valid names or images, update any existing room that still has
  // empty/missing participant_names or participant_images so the chat list
  // displays correctly even for rooms created before this fix.
  if (name1 || name2) {
    await pool.query(
      `UPDATE chat_rooms
          SET participant_names = ?
        WHERE id = ?
          AND (participant_names IS NULL OR JSON_LENGTH(participant_names) = 0 OR participant_names = '{}')`,
      [namesJson, chatRoomId],
    );
  }
  if (image1 || image2) {
    await pool.query(
      `UPDATE chat_rooms
          SET participant_images = ?
        WHERE id = ?
          AND (participant_images IS NULL OR JSON_LENGTH(participant_images) = 0 OR participant_images = '{}')`,
      [imagesJson, chatRoomId],
    );
  }

  // Initialise unread counters
  await pool.query(
    'INSERT IGNORE INTO chat_unread_counts (chat_room_id, user_id, unread_count) VALUES (?,?,0),(?,?,0)',
    [chatRoomId, user1Id, chatRoomId, user2Id],
  );
}

async function saveMessage(msg) {
  await pool.query(
    `INSERT INTO chat_messages
       (message_id, chat_room_id, sender_id, receiver_id, message, message_type,
        is_read, is_delivered, replied_to, created_at, liked)
     VALUES (?,?,?,?,?,?,?,?,?,?,0)`,
    [
      msg.messageId,
      msg.chatRoomId,
      msg.senderId,
      msg.receiverId,
      msg.message || '',
      msg.messageType || 'text',
      msg.isRead    ? 1 : 0,
      msg.isDelivered ? 1 : 0,
      msg.repliedTo ? JSON.stringify(msg.repliedTo) : null,
      new Date(), // always use server UTC time; never trust client-supplied timestamp
    ],
  );
}

/**
 * Batch-insert an array of message objects in a single query.
 * Uses INSERT IGNORE so duplicate message_ids are silently skipped.
 */
async function saveMessageBatch(messages) {
  if (!messages.length) return;
  const values       = [];
  const placeholders = messages.map(msg => {
    values.push(
      msg.messageId,
      msg.chatRoomId,
      msg.senderId,
      msg.receiverId,
      msg.message || '',
      msg.messageType || 'text',
      msg.isRead     ? 1 : 0,
      msg.isDelivered ? 1 : 0,
      msg.repliedTo ? JSON.stringify(msg.repliedTo) : null,
      new Date(), // always use server UTC time; never trust client-supplied timestamp
    );
    return '(?,?,?,?,?,?,?,?,?,?,0)';
  }).join(',');

  await pool.query(
    `INSERT IGNORE INTO chat_messages
       (message_id, chat_room_id, sender_id, receiver_id, message, message_type,
        is_read, is_delivered, replied_to, created_at, liked)
     VALUES ${placeholders}`,
    values,
  );
}

async function updateChatRoomLastMessage({ chatRoomId, message, messageType, senderId, receiverId, isReceiverViewing }) {
  await pool.query(
    `UPDATE chat_rooms
        SET last_message = ?, last_message_type = ?, last_message_time = UTC_TIMESTAMP(), last_message_sender_id = ?
      WHERE id = ?`,
    [message, messageType || 'text', senderId, chatRoomId],
  );

  if (!isReceiverViewing) {
    await pool.query(
      `INSERT INTO chat_unread_counts (chat_room_id, user_id, unread_count)
         VALUES (?, ?, 1)
       ON DUPLICATE KEY UPDATE unread_count = unread_count + 1`,
      [chatRoomId, receiverId],
    );
  }
}

async function getChatRooms(userId) {
  const [rooms] = await pool.query(
    `SELECT cr.*,
            COALESCE(uc.unread_count, 0) AS unread_count
       FROM chat_rooms cr
       LEFT JOIN chat_unread_counts uc ON uc.chat_room_id = cr.id AND uc.user_id = ?
      WHERE JSON_CONTAINS(cr.participants, JSON_QUOTE(?))
      ORDER BY cr.last_message_time DESC`,
    [userId, userId],
  );

  if (rooms.length === 0) return [];

  // Collect all unique other-participant IDs across all rooms
  const otherParticipantIds = new Set();
  for (const r of rooms) {
    const participants = JSON.parse(r.participants);
    for (const pid of participants) {
      if (pid.toString() !== userId.toString()) {
        otherParticipantIds.add(pid.toString());
      }
    }
  }

  const userInfoMap = {};

  if (otherParticipantIds.size > 0) {
    const pidArray = Array.from(otherParticipantIds);
    const placeholders = pidArray.map(() => '?').join(',');

    // Batch-fetch user profile info (privacy, paid status, verified status, name, image)
    // Name and profile_picture are used as fallback when participant_names /
    // participant_images stored in chat_rooms are missing or empty.
    const [userRows] = await pool.query(
      `SELECT id, privacy, usertype, isVerified, firstName, lastName, profile_picture FROM users WHERE id IN (${placeholders})`,
      pidArray,
    );
    for (const u of userRows) {
      const rawPicture = (u.profile_picture || '').trim();
      const pictureUrl = rawPicture
        ? (rawPicture.startsWith('http') ? rawPicture : `${API_BASE_URL}/Api2/${rawPicture.replace(/^\/+/, '')}`)
        : '';
      userInfoMap[u.id.toString()] = {
        privacy:    u.privacy    || 'public',
        usertype:   u.usertype   || 'free',
        isVerified: u.isVerified === 1,
        isOnline:   false,
        lastSeen:   null,
        name:       [u.firstName, u.lastName].filter(Boolean).join(' ').trim(),
        profilePicture: pictureUrl,
      };
    }

    // Batch-fetch online / last-seen status
    const [onlineRows] = await pool.query(
      `SELECT user_id, is_online, last_seen FROM user_online_status WHERE user_id IN (${placeholders})`,
      pidArray,
    );
    for (const o of onlineRows) {
      const uid = o.user_id.toString();
      if (userInfoMap[uid]) {
        userInfoMap[uid].isOnline = o.is_online === 1;
        userInfoMap[uid].lastSeen = o.last_seen ? o.last_seen.toISOString() : null;
      }
    }

    // Batch-fetch photo-request status for (userId ↔ each other participant)
    const [photoRows] = await pool.query(
      `SELECT
         CASE WHEN sender_id = ? THEN receiver_id ELSE sender_id END AS other_id,
         status
       FROM proposals
       WHERE request_type = 'Photo'
         AND (
           (sender_id = ? AND receiver_id IN (${placeholders}))
           OR (receiver_id = ? AND sender_id IN (${placeholders}))
         )
       ORDER BY id DESC`,
      [userId, userId, ...pidArray, userId, ...pidArray],
    );
    // Keep only the most recent request per other participant
    const photoRequestMap = {};
    for (const pr of photoRows) {
      const otherId = pr.other_id.toString();
      if (!photoRequestMap[otherId]) {
        photoRequestMap[otherId] = pr.status || 'pending';
      }
    }
    // Attach photo-request status to userInfoMap
    for (const pid of pidArray) {
      if (userInfoMap[pid]) {
        userInfoMap[pid].photoRequest = photoRequestMap[pid] || 'not_sent';
      }
    }
  }

  return rooms.map(r => {
    const participants = JSON.parse(r.participants);

    // Parse stored names/images — fall back to empty object on parse errors.
    let storedNames  = {};
    let storedImages = {};
    try { storedNames  = JSON.parse(r.participant_names)  || {}; } catch (e) {
      console.warn(`getChatRooms: failed to parse participant_names for room ${r.id}:`, e.message);
    }
    try { storedImages = JSON.parse(r.participant_images) || {}; } catch (e) {
      console.warn(`getChatRooms: failed to parse participant_images for room ${r.id}:`, e.message);
    }

    const participantNames           = {};
    const participantImages          = {};
    const participantPrivacy         = {};
    const participantPhotoRequests   = {};
    const participantPaidStatus      = {};
    const participantVerifiedStatus  = {};
    const participantOnlineStatus    = {};
    const participantLastSeen        = {};

    for (const pid of participants) {
      const pidStr = pid.toString();
      const info = userInfoMap[pidStr];

      // Use stored name/image first; fall back to live data from users table.
      const storedName  = (storedNames[pidStr]  || '').trim();
      const storedImage = (storedImages[pidStr] || '').trim();
      participantNames[pidStr]  = storedName  || (info ? info.name          : '');
      participantImages[pidStr] = storedImage || (info ? info.profilePicture : '');

      if (info) {
        participantPrivacy[pidStr]        = info.privacy;
        participantPhotoRequests[pidStr]  = info.photoRequest || 'not_sent';
        participantPaidStatus[pidStr]     = info.usertype;
        participantVerifiedStatus[pidStr] = info.isVerified ? 1 : 0;
        participantOnlineStatus[pidStr]   = info.isOnline;
        participantLastSeen[pidStr]       = info.lastSeen;
      }
    }

    return {
      chatRoomId:                r.id,
      participants:              participants,
      participantNames,
      participantImages,
      participantPrivacy,
      participantPhotoRequests,
      participantPaidStatus,
      participantVerifiedStatus,
      participantOnlineStatus,
      participantLastSeen,
      lastMessage:               r.last_message,
      lastMessageType:           r.last_message_type,
      lastMessageTime:           r.last_message_time,
      lastMessageSenderId:       r.last_message_sender_id,
      unreadCount:               r.unread_count,
    };
  });
}

async function getMessages({ chatRoomId, page = 1, limit = 20 }) {
  const offset = (page - 1) * limit;
  const [rows] = await pool.query(
    `SELECT * FROM chat_messages
      WHERE chat_room_id = ?
      ORDER BY created_at DESC
      LIMIT ? OFFSET ?`,
    [chatRoomId, limit + 1, offset],
  );
  const hasMore = rows.length > limit;
  const messages = rows.slice(0, limit).reverse().map(row => {
    try {
      return toMessageMap(row);
    } catch (err) {
      console.error(`Failed to transform message ${row.message_id}:`, err.message);
      // Return a safe fallback message object
      return {
        messageId: row.message_id || 'unknown',
        chatRoomId: row.chat_room_id || chatRoomId,
        senderId: row.sender_id || '',
        receiverId: row.receiver_id || '',
        message: 'Error loading message',
        messageType: 'text',
        isRead: false,
        isDelivered: false,
        isDeletedForSender: false,
        isDeletedForReceiver: false,
        isEdited: false,
        isUnsent: false,
        editedAt: null,
        repliedTo: null,
        timestamp: row.created_at ? row.created_at.toISOString() : new Date().toISOString(),
        liked: false,
      };
    }
  });
  return { messages, hasMore, page };
}

async function markMessagesRead({ chatRoomId, userId }) {
  await pool.query(
    'UPDATE chat_unread_counts SET unread_count = 0 WHERE chat_room_id = ? AND user_id = ?',
    [chatRoomId, userId],
  );
  await pool.query(
    `UPDATE chat_messages
        SET is_read = 1, is_delivered = 1
      WHERE chat_room_id = ? AND receiver_id = ? AND (is_read = 0 OR is_delivered = 0)`,
    [chatRoomId, userId],
  );
}

async function editMessage({ chatRoomId, messageId, newMessage }) {
  await pool.query(
    `UPDATE chat_messages
        SET message = ?, is_edited = 1, edited_at = UTC_TIMESTAMP()
      WHERE message_id = ? AND chat_room_id = ?`,
    [newMessage, messageId, chatRoomId],
  );
  // Update last_message if it was the last one
  await pool.query(
    `UPDATE chat_rooms cr
        SET last_message = ?
      WHERE cr.id = ?
        AND last_message_sender_id = (
              SELECT sender_id FROM chat_messages WHERE message_id = ? LIMIT 1
            )
        AND last_message_time = (
              SELECT MAX(created_at) FROM chat_messages WHERE chat_room_id = ?
            )`,
    [newMessage, chatRoomId, messageId, chatRoomId],
  );
}

async function deleteMessage({ chatRoomId, messageId, userId, deleteForEveryone }) {
  if (deleteForEveryone) {
    await pool.query(
      'DELETE FROM chat_messages WHERE message_id = ? AND chat_room_id = ?',
      [messageId, chatRoomId],
    );
  } else {
    // Determine if user is sender or receiver
    const [rows] = await pool.query(
      'SELECT sender_id FROM chat_messages WHERE message_id = ?',
      [messageId],
    );
    if (!rows.length) return;
    const senderIdStr = rows[0].sender_id != null ? rows[0].sender_id.toString() : '';
    const userIdStr   = userId != null ? userId.toString() : '';
    const isSender    = senderIdStr === userIdStr;
    // Use a strict whitelist to avoid any SQL injection risk from the field name.
    const field = isSender ? 'is_deleted_for_sender' : 'is_deleted_for_receiver';
    const allowedFields = ['is_deleted_for_sender', 'is_deleted_for_receiver'];
    if (!allowedFields.includes(field)) return; // should never happen, but guard anyway
    await pool.query(
      `UPDATE chat_messages SET ${field} = 1 WHERE message_id = ? AND chat_room_id = ?`,
      [messageId, chatRoomId],
    );
  }
}

async function upsertOnlineStatus(userId, isOnline, activeChatRoomId = null) {
  try {
    // Update user_online_status table
    await pool.query(
      `INSERT INTO user_online_status (user_id, is_online, last_seen, active_chat_room_id)
         VALUES (?, ?, UTC_TIMESTAMP(), ?)
       ON DUPLICATE KEY UPDATE
         is_online           = VALUES(is_online),
         last_seen           = IF(VALUES(is_online) = 0, UTC_TIMESTAMP(), last_seen),
         active_chat_room_id = VALUES(active_chat_room_id)`,
      [userId, isOnline ? 1 : 0, activeChatRoomId],
    );

    // Update users.isOnline for dashboard queries
    // Only update if the value actually changes to minimize lock contention
    await pool.query(
      `UPDATE users SET isOnline = ? WHERE id = ? AND isOnline != ?`,
      [isOnline ? 1 : 0, userId, isOnline ? 1 : 0],
    );
  } catch (err) {
    console.error(`Failed to update online status for user ${userId}:`, err.message);
  }
}

/**
 * Decode the stored `message` field for image messages and return an `images`
 * array for the client.
 *
 * – type == 'image'         → single URL string → images: [url]
 * – type == 'image_gallery' → JSON-encoded array → images: [url1, url2, …]
 * – anything else           → images: []
 */
function parseImageUrls(messageType, message) {
  if (messageType === 'image') {
    return (typeof message === 'string' && message.length > 0) ? [message] : [];
  }
  if (messageType === 'image_gallery') {
    try {
      const parsed = JSON.parse(message);
      if (Array.isArray(parsed)) {
        return parsed.filter(u => typeof u === 'string' && u.length > 0);
      }
    } catch (_) {}
    // Fallback: treat the raw value as a single URL
    return (typeof message === 'string' && message.length > 0) ? [message] : [];
  }
  return [];
}

// Convert a DB row to the format Flutter expects (mirrors Firestore document shape)
function toMessageMap(row) {
  let repliedTo = null;
  if (row.replied_to) {
    try {
      repliedTo = JSON.parse(row.replied_to);
    } catch (err) {
      console.error(`Failed to parse replied_to JSON for message ${row.message_id}:`, err.message);
      // Leave repliedTo as null if parsing fails
    }
  }

  const messageType = row.message_type || 'text';
  const images = parseImageUrls(messageType, row.message);

  return {
    messageId:             row.message_id,
    chatRoomId:            row.chat_room_id,
    senderId:              row.sender_id,
    receiverId:            row.receiver_id,
    message:               row.message,
    messageType,
    images,
    isRead:                row.is_read === 1,
    isDelivered:           row.is_delivered === 1,
    isDeletedForSender:    row.is_deleted_for_sender === 1,
    isDeletedForReceiver:  row.is_deleted_for_receiver === 1,
    isEdited:              row.is_edited === 1,
    isUnsent:              row.is_unsent === 1,
    editedAt:              row.edited_at ? row.edited_at.toISOString() : null,
    repliedTo:             repliedTo,
    timestamp:             row.created_at ? row.created_at.toISOString() : null,
    liked:                 row.liked === 1,
    reactions:             (() => {
      try { return row.reactions ? JSON.parse(row.reactions) : {}; }
      catch (_) { return {}; }
    })(),
  };
}

// ──────────────────────────────────────────────────────────────────────────────
// Socket.IO events
// ──────────────────────────────────────────────────────────────────────────────
io.on('connection', (socket) => {
  console.log(`🔌 Socket connected: ${socket.id}`);
  let authenticatedUserId = null;

  // ── authenticate ──────────────────────────────────────────────────────────
  socket.on('authenticate', async ({ userId }) => {
    if (!userId) return;
    authenticatedUserId = userId.toString();
    userSockets.set(authenticatedUserId, socket.id);

    // Join a personal room so we can push status changes to this user
    socket.join(`user:${authenticatedUserId}`);

    await upsertOnlineStatus(authenticatedUserId, true);

    // Notify the user's contacts that they are online
    socket.broadcast.emit('user_status_change', {
      userId:   authenticatedUserId,
      isOnline: true,
      lastSeen: new Date().toISOString(),
    });

    // Emit to admin dashboard
    io.to('admin_room').emit('user_online', {
      userId:   authenticatedUserId,
      timestamp: new Date().toISOString(),
    });

    socket.emit('authenticated', { success: true, userId: authenticatedUserId });
    console.log(`✅ Authenticated: userId=${authenticatedUserId}`);

    // Re-deliver any pending calls that arrived while this user was offline.
    // Only calls younger than PENDING_CALL_TTL_MS are considered still active.
    _cleanExpiredPendingCalls();
    const now = Date.now();
    for (const [channelName, call] of activePendingCalls) {
      if (call.recipientId === authenticatedUserId && now - call.createdAt <= PENDING_CALL_TTL_MS) {
        socket.emit('incoming_call', call.data);
        console.log(`📞 Re-delivered pending call to userId=${authenticatedUserId}, channel=${channelName}`);
      }
    }

    // Push the user's current chat room list so the Chat tab is always
    // up-to-date after a (re)connect, even if chat_rooms_update events
    // were emitted while the socket was offline or not yet authenticated.
    // Both 'chat_rooms_update' and its legacy alias 'chat_list_update' are
    // emitted for backward compatibility with older app versions.
    getChatRooms(authenticatedUserId).then(rooms => {
      socket.emit('chat_rooms_update', { chatRooms: rooms });
      socket.emit('chat_list_update', { chatRooms: rooms });
    }).catch(err => {
      console.error('authenticate: getChatRooms error:', err.message);
    });
  });

  // ── join_room ─────────────────────────────────────────────────────────────
  socket.on('join_room', ({ chatRoomId }) => {
    if (chatRoomId) socket.join(chatRoomId);
  });

  // ── leave_room ────────────────────────────────────────────────────────────
  socket.on('leave_room', ({ chatRoomId }) => {
    if (chatRoomId) socket.leave(chatRoomId);
  });

  // ── admin_join ────────────────────────────────────────────────────────────
  // Admin panel emits this to subscribe to real-time activity and message events.
  // Only sockets authenticated as the admin user (userId === '1') may join.
  socket.on('admin_join', () => {
    if (authenticatedUserId !== '1') return;
    socket.join('admin_activity');
    socket.join('admin_room');
    console.log(`🛡️  Admin socket ${socket.id} joined admin_activity and admin_room`);
  });

  // ── admin_leave ───────────────────────────────────────────────────────────
  socket.on('admin_leave', () => {
    socket.leave('admin_activity');
    socket.leave('admin_room');
  });

  // ── new_activity ──────────────────────────────────────────────────────────
  // Flutter app emits this after every user action (like, request, login, etc.)
  // The server forwards the event to the admin room so the admin dashboard
  // updates in real-time without waiting for the polling interval.
  // The DB insert is already handled by the PHP API that performed the action,
  // so we only forward here to avoid duplicate rows.
  socket.on('new_activity', (data) => {
    const {
      userId,
      userName     = '',
      activityType = '',
      description  = '',
      targetId     = null,
      targetName   = null,
    } = data || {};

    if (!userId || !activityType) {
      console.warn(`⚠️  new_activity ignored: missing userId or activityType (userId=${userId})`);
      return;
    }

    console.log(`📊 new_activity: userId=${userId} type=${activityType}`);

    // Forward to admin room for immediate UI update
    io.to('admin_room').emit('admin_activity', {
      user_id:       userId,
      user_name:     userName  || `User ${userId}`,
      activity_type: activityType,
      description:   description || activityType,
      target_id:     targetId   || null,
      target_name:   targetName || null,
      created_at:    new Date().toISOString(),
    });
  });

  // ── payment_updated ───────────────────────────────────────────────────────
  // Emitted by the payment handler (PHP webhook or admin panel) to notify the
  // admin chat list that a user's payment/subscription status has changed.
  // Payload: { userId, usertype, is_paid }
  // The event is broadcast to admin_room so all admin sessions update instantly.
  socket.on('payment_updated', (data) => {
    const { userId, usertype = '', is_paid = false } = data || {};
    if (!userId) return;

    const payload = {
      userId:   userId.toString(),
      usertype: usertype,
      is_paid:  Boolean(is_paid),
      timestamp: new Date().toISOString(),
    };
    console.log(`💳 payment_updated: userId=${userId} usertype=${usertype} is_paid=${is_paid}`);
    io.to('admin_room').emit('payment_updated', payload);
  });

  // ── set_active_chat ───────────────────────────────────────────────────────
  socket.on('set_active_chat', async ({ userId, chatRoomId, isActive }) => {
    const uid = (userId || authenticatedUserId || '').toString();
    if (!uid) return;

    const activeChatRoomId = isActive && chatRoomId ? chatRoomId : null;
    userActiveChatRoom.set(uid, activeChatRoomId);
    await upsertOnlineStatus(uid, true, activeChatRoomId);
  });

  // ── send_message ──────────────────────────────────────────────────────────
  socket.on('send_message', async (data) => {
    // ── Rate limit check (synchronous, no DB) ────────────────────────────
    if (isRateLimited(socket.id)) return; // silently drop

    const {
      chatRoomId, senderId, receiverId,
      message, messageType = 'text',
      messageId = uuidv4(),
      repliedTo, isReceiverViewing = false,
      user1Name, user2Name, user1Image, user2Image,
    } = data || {};

    if (!chatRoomId || !senderId || !receiverId) return;

    // ── Block check ───────────────────────────────────────────────────────
    // Drop the message silently if either party has blocked the other.
    if (await isEitherBlocked(senderId.toString(), receiverId.toString())) {
      console.log(`🚫 send_message blocked: sender=${senderId} receiver=${receiverId}`);
      return;
    }

    // Validate messageType against whitelist
    const ALLOWED_MESSAGE_TYPES = ['text', 'image', 'voice', 'video', 'file', 'call', 'doc', 'profile_card', 'image_gallery', 'report'];
    const safeMessageType = ALLOWED_MESSAGE_TYPES.includes(messageType) ? messageType : 'text';

    // Enforce message length limit (64 KB)
    const MAX_MESSAGE_LENGTH = 65536;
    const safeMessage = typeof message === 'string' ? message.slice(0, MAX_MESSAGE_LENGTH) : '';

    const timestamp = new Date().toISOString();
    const isReceiverCurrentlyViewing = isReceiverViewing ||
      userActiveChatRoom.get(receiverId.toString()) === chatRoomId;

    const msgDoc = {
      messageId, chatRoomId, senderId, receiverId,
      message:    safeMessage,
      messageType: safeMessageType,
      timestamp,
      isRead:               isReceiverCurrentlyViewing,
      isDelivered:          isReceiverCurrentlyViewing,
      isDeletedForSender:   false,
      isDeletedForReceiver: false,
      repliedTo:            repliedTo || null,
      // metadata for worker (not emitted to clients)
      user1Name:  user1Name  || '',
      user2Name:  user2Name  || '',
      user1Image: user1Image || '',
      user2Image: user2Image || '',
      _retries:   0,
    };

    // ── Enqueue (non-blocking) ────────────────────────────────────────────
    if (messageQueue.length >= MAX_QUEUE_SIZE) {
      messageQueue.shift(); // drop oldest to prevent unbounded growth
      console.warn(`⚠️  Message queue at capacity (${MAX_QUEUE_SIZE}); oldest message dropped`);
    }
    messageQueue.push(msgDoc);

    // ── Immediate broadcast (optimistic, no DB wait) ──────────────────────
    // Emit only the client-facing fields (omit worker-only metadata).
    const { user1Name: _u1n, user2Name: _u2n, user1Image: _u1i, user2Image: _u2i, _retries, ...clientMsg } = msgDoc;
    io.to(chatRoomId).emit('new_message', clientMsg);
    // Also emit to each participant's personal room so their chat-list screen
    // receives the event instantly even when they have not joined the chat room.
    io.to(`user:${senderId}`).emit('new_message', clientMsg);
    io.to(`user:${receiverId}`).emit('new_message', clientMsg);

    // ── Real-time admin monitoring ────────────────────────────────────────
    // Emit a dedicated send_message event to admin_room for ALL message types
    // so the admin monitor sees every message instantly without refresh.
    io.to('admin_room').emit('send_message', {
      messageId,
      chatRoomId,
      senderId,
      receiverId,
      senderName:   user1Name  || `User ${senderId}`,
      receiverName: user2Name  || `User ${receiverId}`,
      message:      safeMessageType === 'text'
                      ? maskSensitiveData(safeMessage)
                      : safeMessage,
      messageType:  safeMessageType,
      timestamp,
    });
    // Keep legacy admin_activity for text messages (backward-compat with the
    // activity feed screen that consumes admin_activity events).
    if (safeMessageType === 'text') {
      io.to('admin_room').emit('admin_activity', {
        sender_id:     senderId,
        receiver_id:   receiverId,
        sender_name:   user1Name  || `User ${senderId}`,
        receiver_name: user2Name  || `User ${receiverId}`,
        message:       maskSensitiveData(safeMessage),
        timestamp,
      });
    }
  });

  // ── get_messages ──────────────────────────────────────────────────────────
  socket.on('get_messages', async ({ chatRoomId, page = 1, limit = 20 }, ack) => {
    try {
      const result = await getMessages({ chatRoomId, page, limit });
      if (typeof ack === 'function') ack({ success: true, ...result });
    } catch (err) {
      console.error('get_messages error:', err.message);
      if (typeof ack === 'function') ack({ success: false, error: err.message });
    }
  });

  // ── get_chat_rooms ────────────────────────────────────────────────────────
  socket.on('get_chat_rooms', async ({ userId }, ack) => {
    try {
      const uid = (userId || authenticatedUserId || '').toString();
      if (!uid) { if (typeof ack === 'function') ack({ success: false, error: 'No userId' }); return; }
      const chatRooms = await getChatRooms(uid);
      if (typeof ack === 'function') ack({ success: true, chatRooms });
    } catch (err) {
      console.error('get_chat_rooms error:', err.message);
      if (typeof ack === 'function') ack({ success: false, error: err.message });
    }
  });

  // ── typing_start ──────────────────────────────────────────────────────────
  socket.on('typing_start', ({ chatRoomId, userId }) => {
    if (!chatRoomId || !userId) return;
    socket.to(chatRoomId).emit('typing_start', { chatRoomId, userId });
  });

  // ── typing_stop ───────────────────────────────────────────────────────────
  socket.on('typing_stop', ({ chatRoomId, userId }) => {
    if (!chatRoomId || !userId) return;
    socket.to(chatRoomId).emit('typing_stop', { chatRoomId, userId });
  });

  // ── mark_read ─────────────────────────────────────────────────────────────
  socket.on('mark_read', async ({ chatRoomId, userId }) => {
    try {
      if (!chatRoomId || !userId) return;
      await markMessagesRead({ chatRoomId, userId });

      // Notify sender that their messages were read
      socket.to(chatRoomId).emit('messages_read', { chatRoomId, userId });

      // Refresh chat list for this user
      const rooms = await getChatRooms(userId);
      socket.emit('chat_rooms_update', { chatRooms: rooms });
      socket.emit('chat_list_update', { chatRooms: rooms });
    } catch (err) {
      console.error('mark_read error:', err.message);
    }
  });

  // ── edit_message ──────────────────────────────────────────────────────────
  socket.on('edit_message', async ({ chatRoomId, messageId, newMessage }) => {
    try {
      if (!chatRoomId || !messageId || !newMessage) return;
      if (!authenticatedUserId) return; // require authentication

      // Only allow the original sender to edit their own message
      const senderId = await getMessageSender(messageId, chatRoomId);
      if (!senderId || senderId !== authenticatedUserId) return;

      // Enforce edited message length limit
      const safeNewMessage = typeof newMessage === 'string' ? newMessage.slice(0, 65536) : '';
      await editMessage({ chatRoomId, messageId, newMessage: safeNewMessage });
      const editedAt = new Date().toISOString();
      io.to(chatRoomId).emit('message_edited', { chatRoomId, messageId, newMessage: safeNewMessage, editedAt });
    } catch (err) {
      console.error('edit_message error:', err.message);
      socket.emit('error', { message: 'Failed to edit message' });
    }
  });

  // ── delete_message ────────────────────────────────────────────────────────
  socket.on('delete_message', async ({ chatRoomId, messageId, userId, deleteForEveryone }) => {
    try {
      if (!chatRoomId || !messageId) return;
      if (!authenticatedUserId) return; // require authentication
      const uid = authenticatedUserId;

      // For "delete for everyone", only the sender may do so
      if (deleteForEveryone) {
        const senderId = await getMessageSender(messageId, chatRoomId);
        if (!senderId || senderId !== uid) return;
      }

      await deleteMessage({ chatRoomId, messageId, userId: uid, deleteForEveryone });
      io.to(chatRoomId).emit('message_deleted', { chatRoomId, messageId, deleteForEveryone, userId: uid });
    } catch (err) {
      console.error('delete_message error:', err.message);
      socket.emit('error', { message: 'Failed to delete message' });
    }
  });

  // ── toggle_like ───────────────────────────────────────────────────────────
  socket.on('toggle_like', async ({ chatRoomId, messageId }) => {
    try {
      if (!chatRoomId || !messageId) return;
      if (!authenticatedUserId) return; // Require authentication

      // Verify the authenticated user is a participant in the chat room
      // (uses JSON_CONTAINS since participants is stored as a JSON array)
      const [[room]] = await pool.query(
        `SELECT 1 FROM chat_rooms
          WHERE id = ? AND JSON_CONTAINS(participants, JSON_QUOTE(?))
          LIMIT 1`,
        [chatRoomId, authenticatedUserId],
      );
      if (!room) return; // Not a participant — silently ignore

      // Flip the liked flag atomically
      await pool.query(
        `UPDATE chat_messages SET liked = IF(liked = 1, 0, 1)
          WHERE message_id = ? AND chat_room_id = ?`,
        [messageId, chatRoomId],
      );
      const [[row]] = await pool.query(
        'SELECT liked FROM chat_messages WHERE message_id = ?',
        [messageId],
      );
      if (row) {
        io.to(chatRoomId).emit('message_liked', {
          chatRoomId,
          messageId,
          liked: row.liked === 1,
        });
      }
    } catch (err) {
      console.error('toggle_like error:', err.message);
    }
  });

  // ── add_reaction ──────────────────────────────────────────────────────────
  // Sets or removes an emoji reaction by the authenticated user on a message.
  // emoji = '' or null removes the user's reaction.
  socket.on('add_reaction', async ({ chatRoomId, messageId, emoji }) => {
    try {
      if (!chatRoomId || !messageId) return;
      const uid = authenticatedUserId;
      if (!uid) return;

      // Verify participant
      const [[room]] = await pool.query(
        `SELECT 1 FROM chat_rooms
          WHERE id = ? AND JSON_CONTAINS(participants, JSON_QUOTE(?))
          LIMIT 1`,
        [chatRoomId, uid],
      );
      if (!room) return;

      // Read current reactions JSON
      const [[msgRow]] = await pool.query(
        'SELECT reactions FROM chat_messages WHERE message_id = ? AND chat_room_id = ?',
        [messageId, chatRoomId],
      );
      if (!msgRow) return;

      let reactions = {};
      try { reactions = msgRow.reactions ? JSON.parse(msgRow.reactions) : {}; }
      catch (_) { reactions = {}; }

      const emojiStr = (emoji || '').trim();
      if (!emojiStr || reactions[uid] === emojiStr) {
        // Toggle off: remove this user's reaction
        delete reactions[uid];
      } else {
        reactions[uid] = emojiStr;
      }

      const newJson = Object.keys(reactions).length > 0 ? JSON.stringify(reactions) : null;
      await pool.query(
        'UPDATE chat_messages SET reactions = ? WHERE message_id = ? AND chat_room_id = ?',
        [newJson, messageId, chatRoomId],
      );

      io.to(chatRoomId).emit('message_reaction', {
        chatRoomId,
        messageId,
        reactions,
        reactorId: uid,
      });
    } catch (err) {
      console.error('add_reaction error:', err.message);
    }
  });

  // ── unsend_message ────────────────────────────────────────────────────────
  // Marks a message as "unsent" — replaces its content with a placeholder and
  // sets is_unsent = 1.  Only the original sender may unsend their own message.
  socket.on('unsend_message', async ({ chatRoomId, messageId, userId }) => {
    try {
      if (!chatRoomId || !messageId) return;
      const uid = (userId || authenticatedUserId || '').toString();
      if (!uid) return;

      // Only allow the sender to unsend
      const [[msg]] = await pool.query(
        'SELECT sender_id FROM chat_messages WHERE message_id = ? AND chat_room_id = ? LIMIT 1',
        [messageId, chatRoomId],
      );
      if (!msg || msg.sender_id?.toString() !== uid) return;

      await pool.query(
        `UPDATE chat_messages
            SET message = 'This message was unsent.', is_unsent = 1, is_edited = 0
          WHERE message_id = ? AND chat_room_id = ?`,
        [messageId, chatRoomId],
      );
      io.to(chatRoomId).emit('message_unsent', { chatRoomId, messageId });
    } catch (err) {
      console.error('unsend_message error:', err.message);
      socket.emit('error', { message: 'Failed to unsend message' });
    }
  });

  // ── get_user_status ───────────────────────────────────────────────────────
  socket.on('get_user_status', async ({ userId }, callback) => {
    if (typeof callback !== 'function') return;
    try {
      const uid = (userId || '').toString();
      if (!uid) return callback({ userId: uid, isOnline: false, lastSeen: null });
      const [rows] = await pool.query(
        'SELECT is_online, last_seen FROM user_online_status WHERE user_id = ?',
        [uid],
      );
      if (rows.length > 0) {
        callback({
          userId:   uid,
          isOnline: rows[0].is_online === 1,
          lastSeen: rows[0].last_seen ? rows[0].last_seen.toISOString() : null,
        });
      } else {
        callback({ userId: uid, isOnline: false, lastSeen: null });
      }
    } catch (err) {
      console.error('get_user_status error:', err.message);
      callback({ userId: (userId || '').toString(), isOnline: false, lastSeen: null });
    }
  });

  // ── call_invite ───────────────────────────────────────────────────────────
  // Caller emits this to invite a recipient. Delivered to recipient's personal
  // room if they are online; caller should also send a FCM push as fallback.
  socket.on('call_invite', async (data) => {
    if (!CALLS_ENABLED) return;
    const { recipientId, callerId, ...rest } = data || {};
    if (!recipientId) return;

    const recipientIdStr = recipientId.toString();
    const callerIdStr    = callerId ? callerId.toString() : undefined;

    // ── Block check ───────────────────────────────────────────────────────
    // Reject the call silently if either party has blocked the other.
    if (callerIdStr && await isEitherBlocked(callerIdStr, recipientIdStr)) {
      if (callerIdStr) {
        io.to(`user:${callerIdStr}`).emit('call_blocked', {
          channelName: (rest.channelName || '').toString().trim(),
          callerId:    callerIdStr,
          recipientId: recipientIdStr,
        });
      }
      return;
    }

    const callPayload = {
      ...rest,
      callerId:    callerIdStr,
      recipientId: recipientIdStr,
    };

    // Store as a pending call so we can re-deliver it if the recipient comes
    // online before the call times out on the caller side.
    const channelName = (rest.channelName || '').toString().trim();
    if (channelName) {
      activePendingCalls.set(channelName, {
        callerId:    callerIdStr,
        recipientId: recipientIdStr,
        data:        callPayload,
        createdAt:   Date.now(),
      });
    }

    // Check if recipient is already ringing for a pending call from another caller.
    let recipientAlreadyRinging = false;
    for (const [ch, call] of activePendingCalls) {
      if (call.recipientId === recipientIdStr && ch !== channelName) {
        recipientAlreadyRinging = true;
        break;
      }
    }

    // Admin (userId === '1') is always available and can handle multiple concurrent calls.
    const isAdminRecipient = recipientIdStr === '1';

    if (!isAdminRecipient && (activeCallUsers.has(recipientIdStr) || recipientAlreadyRinging)) {
      // Recipient is a normal user already on another call or ringing — notify caller immediately.
      if (channelName) activePendingCalls.delete(channelName);
      if (callerIdStr) {
        io.to(`user:${callerIdStr}`).emit('call_busy', {
          channelName: channelName,
          callerId: callerIdStr,
          recipientId: recipientIdStr,
        });
      }
    } else if (userSockets.has(recipientIdStr)) {
      // Recipient is online — deliver the call and confirm ringing to caller.
      // Mark non-admin callers as busy from the moment the call starts (not just
      // after acceptance), so that concurrent callers see the correct busy state.
      if (callerIdStr && callerIdStr !== '1' && channelName) {
        activeCallUsers.set(callerIdStr, channelName);
      }
      io.to(`user:${recipientIdStr}`).emit('incoming_call', callPayload);
      if (callerIdStr) {
        io.to(`user:${callerIdStr}`).emit('call_ringing', {
          channelName: channelName,
          recipientId: recipientIdStr,
          callerId:    callerIdStr,
        });
      }
    } else {
      // Recipient is offline — notify the caller immediately so they can show
      // an appropriate message (FCM push has already been sent by the client).
      // Still mark non-admin callers as busy while the call is pending (FCM path).
      if (callerIdStr && callerIdStr !== '1' && channelName) {
        activeCallUsers.set(callerIdStr, channelName);
      }
      if (callerIdStr) {
        io.to(`user:${callerIdStr}`).emit('call_user_offline', {
          channelName:  channelName,
          callerId:     callerIdStr,
          recipientId:  recipientIdStr,
        });
      }
    }
  });

  // ── call_ringing ──────────────────────────────────────────────────────────
  // Recipient emits this to confirm their device is actively ringing.
  // Used as fallback for FCM-delivered calls where the server cannot confirm
  // socket presence at invite time.
  socket.on('call_ringing', (data) => {
    const { callerId, ...rest } = data || {};
    if (!callerId) return;
    io.to(`user:${callerId.toString()}`).emit('call_ringing', {
      ...rest,
      callerId: callerId.toString(),
    });
  });

  // ── call_accept ───────────────────────────────────────────────────────────
  // Recipient emits this to inform the caller the call was accepted.
  socket.on('call_accept', (data) => {
    const { callerId, recipientId, ...rest } = data || {};
    if (!callerId) return;
    if (rest.channelName) activePendingCalls.delete(rest.channelName);
    // Mark both parties as busy in an active call.
    // Admin (userId === '1') is always available — do not mark them as busy.
    const callerStr    = callerId.toString();
    const recipientStr = recipientId ? recipientId.toString() : undefined;
    const channelName  = rest.channelName;
    if (channelName) {
      if (callerStr !== '1') activeCallUsers.set(callerStr, channelName);
      if (recipientStr && recipientStr !== '1') activeCallUsers.set(recipientStr, channelName);
      // Seed group-call participant tracking with both parties.
      if (!groupCallParticipants.has(channelName)) {
        groupCallParticipants.set(channelName, new Set());
      }
      groupCallParticipants.get(channelName).add(callerStr);
      if (recipientStr) groupCallParticipants.get(channelName).add(recipientStr);
      // Persist initial participants to DB asynchronously.
      persistGroupCallParticipants(channelName, rest.callType || 'audio', callerStr).catch(() => {});

      // Emit call_started to admin dashboard
      io.to('admin_room').emit('call_started', {
        channelName,
        callerId: callerStr,
        recipientId: recipientStr,
        callType: rest.callType || 'audio',
        timestamp: new Date().toISOString(),
      });
    }
    io.to(`user:${callerStr}`).emit('call_accepted', {
      ...rest,
      callerId: callerStr,
      ...(recipientId ? { recipientId: recipientStr } : {}),
    });
    // Notify any other sessions of the same recipient (e.g. admin logged in on
    // a second browser/computer) so they can dismiss their incoming call dialog.
    if (recipientStr) {
      socket.to(`user:${recipientStr}`).emit('call_answered_elsewhere', {
        ...rest,
        callerId: callerStr,
        recipientId: recipientStr,
      });
    }
  });

  // ── call_reject ───────────────────────────────────────────────────────────
  // Recipient emits this to inform the caller the call was rejected.
  socket.on('call_reject', (data) => {
    const { callerId, ...rest } = data || {};
    if (!callerId) return;
    if (rest.channelName) activePendingCalls.delete(rest.channelName);
    // Clear the caller's busy state — the call never connected.
    activeCallUsers.delete(callerId.toString());
    io.to(`user:${callerId.toString()}`).emit('call_rejected', {
      ...rest,
      callerId: callerId.toString(),
    });
  });

  // ── call_cancel ───────────────────────────────────────────────────────────
  // Caller emits this when they cancel before the recipient answers.
  socket.on('call_cancel', (data) => {
    const { recipientId, callerId, ...rest } = data || {};
    if (!recipientId) return;
    if (rest.channelName) activePendingCalls.delete(rest.channelName);
    // Clear the caller's busy state — the call was cancelled before connecting.
    if (callerId) activeCallUsers.delete(callerId.toString());
    io.to(`user:${recipientId.toString()}`).emit('call_cancelled', {
      ...rest,
      recipientId: recipientId.toString(),
    });
  });

  // ── call_end ─────────────────────────────────────────────────────────────
  // Either party emits this to notify the other the call has ended.
  socket.on('call_end', (data) => {
    const { callerId, recipientId, ...rest } = data || {};
    const channelName = rest.channelName;
    if (channelName) activePendingCalls.delete(channelName);
    // Remove both parties from the active-call tracking set
    if (callerId)    activeCallUsers.delete(callerId.toString());
    if (recipientId) activeCallUsers.delete(recipientId.toString());

    // Emit call_ended to admin dashboard
    if (channelName) {
      io.to('admin_room').emit('call_ended', {
        channelName,
        callerId: callerId ? callerId.toString() : undefined,
        recipientId: recipientId ? recipientId.toString() : undefined,
        timestamp: new Date().toISOString(),
      });
    }

    // Notify all group-call participants (not just the 2 initial parties).
    if (channelName && groupCallParticipants.has(channelName)) {
      const allParticipants = groupCallParticipants.get(channelName);
      for (const uid of allParticipants) {
        activeCallUsers.delete(uid);
        io.to(`user:${uid}`).emit('call_ended', { ...rest, callerId, recipientId });
      }
      // Persist ended status to DB then clean up in-memory map.
      endGroupCall(channelName).catch(() => {});
      groupCallParticipants.delete(channelName);
    } else {
      if (callerId) {
        io.to(`user:${callerId.toString()}`).emit('call_ended', {
          ...rest, callerId, recipientId,
        });
      }
      if (recipientId) {
        io.to(`user:${recipientId.toString()}`).emit('call_ended', {
          ...rest, callerId, recipientId,
        });
      }
    }
  });

  // ── switch_to_video_request ──────────────────────────────────────────────
  // One party requests to upgrade the ongoing audio call to a video call.
  socket.on('switch_to_video_request', (data) => {
    const { recipientId, requesterId, channelName, ...rest } = data || {};
    if (!recipientId) return;
    io.to(`user:${recipientId.toString()}`).emit('switch_to_video_request', {
      ...rest,
      recipientId: recipientId.toString(),
      requesterId: requesterId ? requesterId.toString() : undefined,
      channelName,
    });
  });

  // ── switch_to_video_accepted ─────────────────────────────────────────────
  // Recipient accepts (or declines) the switch-to-video request.
  socket.on('switch_to_video_response', (data) => {
    const { requesterId, responderId, channelName, accepted, ...rest } = data || {};
    if (!requesterId) return;
    io.to(`user:${requesterId.toString()}`).emit('switch_to_video_response', {
      ...rest,
      requesterId: requesterId.toString(),
      responderId: responderId ? responderId.toString() : undefined,
      channelName,
      accepted: accepted === true || accepted === 'true',
    });
  });

  // ── add_participant_to_call ───────────────────────────────────────────────
  // Admin emits this to add a participant to an ongoing group call.
  // Notifies the new participant AND all existing participants in the channel.
  socket.on('add_participant_to_call', (data) => {
    const { newParticipantId, channelName, callType, adminId, adminName, existingParticipantId, ...rest } = data || {};
    if (!newParticipantId || !channelName) return;

    const newParticipantStr = newParticipantId.toString();
    const adminStr = adminId ? adminId.toString() : undefined;

    // Update in-memory group-call participant set for this channel.
    if (!groupCallParticipants.has(channelName)) {
      groupCallParticipants.set(channelName, new Set());
      // If this is the first add_participant event for the channel, seed with
      // the admin and the original recipient so we have a complete picture.
      if (adminStr) groupCallParticipants.get(channelName).add(adminStr);
      if (existingParticipantId) groupCallParticipants.get(channelName).add(existingParticipantId.toString());
    }
    groupCallParticipants.get(channelName).add(newParticipantStr);

    // Persist updated participants list to DB asynchronously.
    persistGroupCallParticipants(channelName, callType || 'audio', adminStr || '1').catch(() => {});

    // Notify the new participant they're being added to a call.
    io.to(`user:${newParticipantStr}`).emit('added_to_call', {
      channelName,
      callType: callType || 'audio',
      adminId: adminStr,
      adminName,
      existingParticipantId: existingParticipantId ? existingParticipantId.toString() : undefined,
      ...rest,
    });

    // Broadcast participant_added_to_call to ALL current participants so every
    // member of the group call (not just one) knows who joined.
    const currentParticipants = groupCallParticipants.get(channelName);
    for (const uid of currentParticipants) {
      if (uid === newParticipantStr) continue; // don't notify the joiner about themselves
      io.to(`user:${uid}`).emit('participant_added_to_call', {
        newParticipantId: newParticipantStr,
        channelName,
        callType: callType || 'audio',
        ...rest,
      });
    }
  });

  // ── participant_call_accept ───────────────────────────────────────────────
  // New participant accepts the conference call invitation
  socket.on('participant_call_accept', (data) => {
    const { adminId, existingParticipantId, channelName, acceptedById, ...rest } = data || {};
    if (!channelName) return;

    // Add the accepted participant to the group-call tracking set.
    if (acceptedById && channelName) {
      if (!groupCallParticipants.has(channelName)) {
        groupCallParticipants.set(channelName, new Set());
      }
      groupCallParticipants.get(channelName).add(acceptedById.toString());
      // Mark non-admin participant as busy.
      if (acceptedById.toString() !== '1') {
        activeCallUsers.set(acceptedById.toString(), channelName);
      }
      persistGroupCallParticipants(channelName, 'audio', adminId ? adminId.toString() : '1').catch(() => {});
    }

    // Notify ALL current participants that the new member accepted.
    const currentParticipants = groupCallParticipants.get(channelName);
    if (currentParticipants) {
      for (const uid of currentParticipants) {
        io.to(`user:${uid}`).emit('participant_accepted_call', {
          acceptedById: acceptedById ? acceptedById.toString() : undefined,
          channelName,
          ...rest,
        });
      }
    } else {
      // Fallback: notify admin and original participant only.
      if (adminId) {
        io.to(`user:${adminId.toString()}`).emit('participant_accepted_call', {
          acceptedById: acceptedById ? acceptedById.toString() : undefined,
          channelName,
          ...rest,
        });
      }
      if (existingParticipantId) {
        io.to(`user:${existingParticipantId.toString()}`).emit('participant_accepted_call', {
          acceptedById: acceptedById ? acceptedById.toString() : undefined,
          channelName,
          ...rest,
        });
      }
    }
  });

  // ── participant_call_reject ───────────────────────────────────────────────
  // New participant rejects the conference call invitation
  socket.on('participant_call_reject', (data) => {
    const { adminId, existingParticipantId, channelName, rejectedById, ...rest } = data || {};
    if (!channelName) return;

    // Notify ALL current participants that the user rejected (so they can update their UI).
    const currentParticipants = groupCallParticipants.get(channelName);
    if (currentParticipants) {
      for (const uid of currentParticipants) {
        io.to(`user:${uid}`).emit('participant_rejected_call', {
          rejectedById: rejectedById ? rejectedById.toString() : undefined,
          channelName,
          ...rest,
        });
      }
    } else {
      // Fallback: notify admin and original participant only.
      if (adminId) {
        io.to(`user:${adminId.toString()}`).emit('participant_rejected_call', {
          rejectedById: rejectedById ? rejectedById.toString() : undefined,
          channelName,
          ...rest,
        });
      }
      if (existingParticipantId) {
        io.to(`user:${existingParticipantId.toString()}`).emit('participant_rejected_call', {
          rejectedById: rejectedById ? rejectedById.toString() : undefined,
          channelName,
          ...rest,
        });
      }
    }
  });

  // ── leave_group_call ─────────────────────────────────────────────────────
  // A participant emits this to voluntarily leave a group call.
  // Notifies all remaining participants so they can remove the leaver from their UI.
  socket.on('leave_group_call', (data) => {
    const { channelName, userId, callerId, recipientId } = data || {};
    if (!channelName) return;
    const leaverId = (userId || authenticatedUserId || '').toString();
    if (!leaverId) return;

    // Remove from busy tracking.
    activeCallUsers.delete(leaverId);

    // Update the in-memory participant set.
    if (groupCallParticipants.has(channelName)) {
      groupCallParticipants.get(channelName).delete(leaverId);
      const remaining = groupCallParticipants.get(channelName);

      // Notify all remaining participants about the departure.
      for (const uid of remaining) {
        io.to(`user:${uid}`).emit('participant_left_call', {
          channelName,
          leftUserId: leaverId,
        });
      }

      // Persist updated participants list.
      persistGroupCallParticipants(channelName, 'audio', '1').catch(() => {});

      // If no participants remain, end the group call in DB.
      if (remaining.size === 0) {
        endGroupCall(channelName).catch(() => {});
        groupCallParticipants.delete(channelName);
      }
    }
  });

  // ── user_speaking ────────────────────────────────────────────────────────
  // Client emits when user's audio level exceeds threshold (real-time speaking detection)
  // Server broadcasts to all participants in the room/channel
  socket.on('user_speaking', (data) => {
    const { userId, roomId, channelName, isSpeaking } = data || {};
    const speakerId = (userId || authenticatedUserId || '').toString();
    const room = (roomId || channelName || '').toString();

    if (!speakerId || !room) return;

    // Broadcast speaking_update to all participants in the group call
    const participants = groupCallParticipants.get(room);
    if (participants) {
      for (const uid of participants) {
        if (uid !== speakerId) { // Don't send back to speaker
          io.to(`user:${uid}`).emit('speaking_update', {
            userId: speakerId,
            roomId: room,
            channelName: room,
            isSpeaking: !!isSpeaking,
            timestamp: new Date().toISOString(),
          });
        }
      }
    } else {
      // Fallback: broadcast to room for non-group calls
      socket.to(room).emit('speaking_update', {
        userId: speakerId,
        roomId: room,
        isSpeaking: !!isSpeaking,
        timestamp: new Date().toISOString(),
      });
    }
  });

  // ── ping (client heartbeat) ───────────────────────────────────────────────
  // Clients emit 'ping' every 10 s to keep their online status fresh.
  // We update last_seen so the stale-user cleanup job can detect silent
  // disconnects (e.g. app crash, network loss) where no 'disconnect' fires.
  socket.on('ping', async () => {
    if (!authenticatedUserId) return;
    try {
      await pool.query(
        `UPDATE user_online_status SET last_seen = UTC_TIMESTAMP() WHERE user_id = ?`,
        [authenticatedUserId],
      );
    } catch (err) {
      console.error('ping handler error:', err.message);
    }
  });

  // ── disconnect ────────────────────────────────────────────────────────────
  socket.on('disconnect', async () => {
    console.log(`🔌 Socket disconnected: ${socket.id}`);
    socketRateLimits.delete(socket.id);
    if (!authenticatedUserId) return;

    userSockets.delete(authenticatedUserId);
    userActiveChatRoom.delete(authenticatedUserId);
    // If this user was in an active call, remove them from busy tracking.
    activeCallUsers.delete(authenticatedUserId);

    // Mark user offline after 30 seconds if they don't reconnect
    // Use a timeout to allow for brief reconnections (e.g., network switching)
    setTimeout(async () => {
      // Check if user has reconnected
      if (!userSockets.has(authenticatedUserId)) {
        await upsertOnlineStatus(authenticatedUserId, false);

        // Notify contacts
        socket.broadcast.emit('user_status_change', {
          userId:   authenticatedUserId,
          isOnline: false,
          lastSeen: new Date().toISOString(),
        });

        // Emit to admin dashboard
        io.to('admin_room').emit('user_offline', {
          userId:   authenticatedUserId,
          timestamp: new Date().toISOString(),
        });
      }
    }, 30000); // 30 seconds delay
  });
});

// ──────────────────────────────────────────────────────────────────────────────
// Batch worker — drains the message queue every BATCH_INTERVAL ms
// ──────────────────────────────────────────────────────────────────────────────
let totalMsgsSinceLastStat = 0;

setInterval(async () => {
  if (!messageQueue.length) return;

  const batch = messageQueue.splice(0, BATCH_SIZE);
  totalMsgsSinceLastStat += batch.length;

  // 1. Ensure chat rooms exist for every unique room in the batch (INSERT IGNORE).
  const uniqueRooms = new Map(); // chatRoomId → first msg with that room
  for (const msg of batch) {
    if (!uniqueRooms.has(msg.chatRoomId)) uniqueRooms.set(msg.chatRoomId, msg);
  }
  for (const [chatRoomId, msg] of uniqueRooms) {
    try {
      await ensureChatRoom({
        chatRoomId,
        user1Id:    msg.senderId,   user2Id:    msg.receiverId,
        user1Name:  msg.user1Name,  user2Name:  msg.user2Name,
        user1Image: msg.user1Image, user2Image: msg.user2Image,
      });
    } catch (err) {
      console.error(`Worker ensureChatRoom error [${chatRoomId}]:`, err.message);
    }
  }

  // 2. Batch-insert all messages; retry on failure.
  const dbStart = Date.now();
  try {
    await saveMessageBatch(batch);
    const dbMs = Date.now() - dbStart;
    if (dbMs > 500) console.warn(`⚠️  Slow batch insert: ${dbMs}ms for ${batch.length} messages`);
  } catch (err) {
    console.error('Worker batch insert error:', err.message);
    // Re-queue messages that haven't exceeded max retries
    const toRetry = batch.filter(m => (m._retries || 0) < MAX_RETRIES).map(m => {
      m._retries = (m._retries || 0) + 1;
      return m;
    });
    if (toRetry.length) {
      // Use a loop instead of spread to avoid stack overflow on large arrays.
      for (let i = toRetry.length - 1; i >= 0; i--) {
        messageQueue.unshift(toRetry[i]);
      }
    }
    const dropped = batch.length - toRetry.length;
    if (dropped > 0) console.error(`Worker dropped ${dropped} messages after ${MAX_RETRIES} retries`);
    return; // skip chat_rooms update for this failed batch
  }

  // 2b. Log message_sent activity for each unique sender in the batch.
  const senderLogged = new Set();
  for (const msg of batch) {
    const sKey = `${msg.senderId}:${msg.receiverId}`;
    if (senderLogged.has(sKey)) continue;
    senderLogged.add(sKey);
    // Skip admin-originated messages (senderId === 1)
    if (msg.senderId.toString() === '1') continue;
    logActivity({
      userId:       msg.senderId,
      userName:     msg.user1Name || '',
      targetId:     msg.receiverId,
      targetName:   msg.user2Name || '',
      activityType: 'message_sent',
      description:  `${msg.user1Name || 'User '+msg.senderId} → ${msg.user2Name || 'User '+msg.receiverId}: ${maskSensitiveData(msg.message || '')}`,
    }).catch(() => {});
  }

  // 3. Update chat_rooms with the latest message per room.
  const roomLatest = new Map(); // chatRoomId → most recent msg
  for (const msg of batch) {
    const existing = roomLatest.get(msg.chatRoomId);
    if (!existing || new Date(msg.timestamp) > new Date(existing.timestamp)) {
      roomLatest.set(msg.chatRoomId, msg);
    }
  }
  for (const [, msg] of roomLatest) {
    try {
      await updateChatRoomLastMessage({
        chatRoomId:         msg.chatRoomId,
        message:            msg.message,
        messageType:        msg.messageType,
        senderId:           msg.senderId,
        receiverId:         msg.receiverId,
        isReceiverViewing:  msg.isRead,
      });
    } catch (err) {
      console.error('Worker updateChatRoomLastMessage error:', err.message);
    }
  }

  // 4. Broadcast updated chat-room lists to all affected users (deduplicated).
  const affectedUsers = new Set();
  for (const msg of batch) {
    affectedUsers.add(msg.senderId.toString());
    affectedUsers.add(msg.receiverId.toString());
  }
  for (const uid of affectedUsers) {
    try {
      const rooms = await getChatRooms(uid);
      io.to(`user:${uid}`).emit('chat_rooms_update', { chatRooms: rooms });
      io.to(`user:${uid}`).emit('chat_list_update', { chatRooms: rooms });
    } catch (err) {
      console.error(`Worker getChatRooms error [userId=${uid}]:`, err.message);
    }
  }
}, BATCH_INTERVAL);

// ──────────────────────────────────────────────────────────────────────────────
// Stale online-user cleanup — runs every 60 s
// Users who connected but never sent a heartbeat ping (or whose last ping was
// more than STALE_THRESHOLD_S seconds ago) are marked offline.  This recovers
// from silent disconnects (app crash / network drop) where the TCP FIN never
// reaches the server and the 'disconnect' event never fires.
// The threshold is set to 3× the client heartbeat interval (10 s) + buffer.
// ──────────────────────────────────────────────────────────────────────────────
const STALE_THRESHOLD_S = 90; // seconds without a heartbeat ping before marking offline
setInterval(async () => {
  try {
    const [result] = await pool.query(
      `UPDATE user_online_status
          SET is_online = 0
        WHERE is_online = 1
          AND last_seen < UTC_TIMESTAMP() - INTERVAL ? SECOND`,
      [STALE_THRESHOLD_S],
    );
    if (result.affectedRows > 0) {
      console.log(`🧹 Stale cleanup: marked ${result.affectedRows} user(s) offline`);
      // Broadcast offline status for each affected user so clients update in real-time.
      const [staleRows] = await pool.query(
        `SELECT user_id, last_seen FROM user_online_status
          WHERE is_online = 0
            AND last_seen < UTC_TIMESTAMP() - INTERVAL ? SECOND
            AND last_seen > UTC_TIMESTAMP() - INTERVAL ? SECOND`,
        [STALE_THRESHOLD_S, STALE_THRESHOLD_S + 65], // rows updated in last interval
      );
      for (const row of staleRows) {
        io.emit('user_status_change', {
          userId:   row.user_id.toString(),
          isOnline: false,
          lastSeen: row.last_seen ? row.last_seen.toISOString() : new Date().toISOString(),
        });
      }
    }
  } catch (err) {
    console.error('Stale user cleanup error:', err.message);
  }
}, 60000);

// ──────────────────────────────────────────────────────────────────────────────
// REST — GET /api/chat-rooms?userId=xxx
// Returns the chat room list for a user, sorted by last_message_time DESC.
// Provides an HTTP fallback for clients that cannot use the socket event.
// ──────────────────────────────────────────────────────────────────────────────
app.get('/api/chat-rooms', async (req, res) => {
  try {
    const userId = (req.query.userId || '').toString().trim();
    if (!userId) return res.status(400).json({ error: 'userId is required' });
    const chatRooms = await getChatRooms(userId);
    res.json({ success: true, chatRooms });
  } catch (err) {
    console.error('GET /api/chat-rooms error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// REST — POST /api/mark-chat-read
// Marks all unread messages in a chat room as read for a user and resets the
// unread counter.  Also emits real-time socket events so the sender knows their
// messages have been read.
// Body: { chatRoomId, userId }
// ──────────────────────────────────────────────────────────────────────────────
app.post('/api/mark-chat-read', async (req, res) => {
  try {
    const { chatRoomId, userId } = req.body || {};
    if (!chatRoomId || !userId) {
      return res.status(400).json({ error: 'chatRoomId and userId are required' });
    }
    await markMessagesRead({ chatRoomId, userId });

    // Notify the other participant(s) that their messages were read
    io.to(chatRoomId).emit('messages_read', { chatRoomId, userId });

    // Push refreshed chat list to this user
    const rooms = await getChatRooms(userId.toString());
    io.to(`user:${userId}`).emit('chat_rooms_update', { chatRooms: rooms });
    io.to(`user:${userId}`).emit('chat_list_update', { chatRooms: rooms });

    res.json({ success: true });
  } catch (err) {
    console.error('POST /api/mark-chat-read error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// REST — POST /api/notify-new-message
// Called by the PHP backend after it saves a message directly to the DB so that
// the socket server can emit real-time events to both participants without
// duplicating the DB write.
// Body: { chatRoomId, senderId, receiverId, messageId, message, messageType,
//         timestamp (ISO), user1Name, user2Name, user1Image, user2Image }
// ──────────────────────────────────────────────────────────────────────────────
app.post('/api/notify-new-message', async (req, res) => {
  try {
    const {
      chatRoomId, senderId, receiverId, messageId,
      message = '', messageType = 'text',
      timestamp, user1Name = '', user2Name = '',
      user1Image = '', user2Image = '',
    } = req.body || {};

    if (!chatRoomId || !senderId || !receiverId) {
      return res.status(400).json({ error: 'chatRoomId, senderId, receiverId are required' });
    }

    const safeTimestamp = timestamp || new Date().toISOString();

    const payload = {
      messageId:   messageId || '',
      chatRoomId,
      senderId:    senderId.toString(),
      receiverId:  receiverId.toString(),
      message:     message || '',
      messageType: messageType || 'text',
      timestamp:   safeTimestamp,
      isRead:      false,
      isDelivered: false,
      repliedTo:   null,
    };

    // Emit new_message to the chat room and to each participant's personal room
    io.to(chatRoomId).emit('new_message', payload);
    io.to(`user:${senderId}`).emit('new_message', payload);
    io.to(`user:${receiverId}`).emit('new_message', payload);

    // Emit to admin room for monitoring
    io.to('admin_room').emit('send_message', {
      messageId:    payload.messageId,
      chatRoomId,
      senderId:     payload.senderId,
      receiverId:   payload.receiverId,
      senderName:   user1Name  || `User ${senderId}`,
      receiverName: user2Name  || `User ${receiverId}`,
      message:      messageType === 'text' ? maskSensitiveData(message) : message,
      messageType:  payload.messageType,
      timestamp:    safeTimestamp,
    });

    // Push refreshed chat-room lists to both participants
    for (const uid of [senderId.toString(), receiverId.toString()]) {
      try {
        const rooms = await getChatRooms(uid);
        io.to(`user:${uid}`).emit('chat_rooms_update', { chatRooms: rooms });
        io.to(`user:${uid}`).emit('chat_list_update', { chatRooms: rooms });
      } catch (e) {
        console.error(`notify-new-message: getChatRooms error [userId=${uid}]:`, e.message);
      }
    }

    res.json({ success: true });
  } catch (err) {
    console.error('POST /api/notify-new-message error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// HTTP fallback — POST /api/send-message
// Clients call this when the socket is unavailable (reconnecting after a
// network outage) so that no messages are lost.  The endpoint saves the
// message to the DB directly and broadcasts it to the chat room via Socket.IO
// exactly like the 'send_message' socket event does.
// ──────────────────────────────────────────────────────────────────────────────
app.post('/api/send-message', async (req, res) => {
  try {
    const {
      chatRoomId, senderId, receiverId, message, messageType,
      messageId, repliedTo, user1Name = '', user2Name = '',
      user1Image = '', user2Image = '',
    } = req.body || {};

    // Basic validation
    if (!chatRoomId || !senderId || !receiverId || !messageId) {
      return res.status(400).json({ error: 'Missing required fields' });
    }
    const safeType = ['text', 'image', 'image_gallery', 'voice', 'profile_card', 'report', 'call'].includes(messageType)
      ? messageType : 'text';

    // Ensure chat room exists
    await ensureChatRoom({
      chatRoomId,
      user1Id:    senderId,   user2Id:    receiverId,
      user1Name,              user2Name,
      user1Image,             user2Image,
    });

    // Save message
    await pool.query(
      `INSERT IGNORE INTO chat_messages
         (message_id, chat_room_id, sender_id, receiver_id, message, message_type,
          is_read, is_delivered, replied_to, created_at, liked)
       VALUES (?,?,?,?,?,?,0,0,?,UTC_TIMESTAMP(),0)`,
      [
        messageId, chatRoomId, senderId, receiverId,
        message || '', safeType,
        repliedTo ? JSON.stringify(repliedTo) : null,
      ],
    );

    // Update chat room last message
    await updateChatRoomLastMessage({
      chatRoomId, message, messageType: safeType,
      senderId, receiverId, isReceiverViewing: false,
    });

    const timestamp = new Date().toISOString();
    const payload = {
      messageId, chatRoomId, senderId, receiverId,
      message: message || '', messageType: safeType,
      timestamp, isRead: false, isDelivered: false,
      repliedTo: repliedTo || null,
      senderName: user1Name, receiverName: user2Name,
    };

    // Broadcast to chat room so online participants receive it immediately
    io.to(chatRoomId).emit('new_message', payload);

    // Update chat room lists for both participants
    for (const uid of [senderId.toString(), receiverId.toString()]) {
      try {
        const rooms = await getChatRooms(uid);
        io.to(`user:${uid}`).emit('chat_rooms_update', { chatRooms: rooms });
        io.to(`user:${uid}`).emit('chat_list_update', { chatRooms: rooms });
      } catch (_) {}
    }

    res.json({ success: true, messageId, timestamp });
  } catch (err) {
    console.error('POST /api/send-message error:', err.message);
    res.status(500).json({ error: 'Failed to send message' });
  }
});

// ──────────────────────────────────────────────────────────────────────────────
// Monitoring — log key stats every 10 s
// ──────────────────────────────────────────────────────────────────────────────
const MONITOR_INTERVAL = 10000; // ms (10 seconds)
setInterval(() => {
  const mem        = process.memoryUsage();
  const heapMB     = (mem.heapUsed  / 1024 / 1024).toFixed(1);
  const rssMB      = (mem.rss       / 1024 / 1024).toFixed(1);
  const rate       = (totalMsgsSinceLastStat / (MONITOR_INTERVAL / 1000)).toFixed(1);
  const queueSize  = messageQueue.length;
  const connCount  = userSockets.size;

  console.log(
    `📊 Stats | msg/s: ${rate} | queue: ${queueSize}` +
    ` | sockets: ${connCount} | heap: ${heapMB}MB | rss: ${rssMB}MB`,
  );
  totalMsgsSinceLastStat = 0;
}, MONITOR_INTERVAL);

// ──────────────────────────────────────────────────────────────────────────────
server.listen(PORT, () => {
  console.log(`🚀 Socket.IO server running on port ${PORT}`);
  if (!PUBLIC_URL) {
    console.warn(
      '⚠️  WARNING: PUBLIC_URL is not set in .env. Image URLs will be derived from request ' +
      'headers (req.protocol + req.get("host")). Set PUBLIC_URL=https://your-domain.com in ' +
      '.env to guarantee correct HTTPS image URLs regardless of proxy configuration. ' +
      'Missing PUBLIC_URL can cause uploaded images to return non-public URLs.'
    );
  } else {
    console.log(`🌐 PUBLIC_URL: ${PUBLIC_URL}`);
  }
});
