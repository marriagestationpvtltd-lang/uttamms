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
        \`room_id\`         VARCHAR(100) DEFAULT NULL,
        \`caller_id\`       VARCHAR(50)  NOT NULL,
        \`caller_name\`     VARCHAR(200) DEFAULT '',
        \`caller_image\`    VARCHAR(500) DEFAULT '',
        \`recipient_id\`    VARCHAR(50)  NOT NULL DEFAULT '',
        \`recipient_name\`  VARCHAR(200) DEFAULT '',
        \`recipient_image\` VARCHAR(500) DEFAULT '',
        \`call_type\`       ENUM('audio','video','group') NOT NULL DEFAULT 'audio',
        \`participants\`    TEXT         DEFAULT NULL,
        \`start_time\`      DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,
        \`end_time\`        DATETIME     DEFAULT NULL,
        \`duration\`        INT          NOT NULL DEFAULT 0,
        \`status\`          ENUM('completed','missed','declined','cancelled','ended','rejected') NOT NULL DEFAULT 'missed',
        \`initiated_by\`    VARCHAR(50)  NOT NULL,
        \`ended_by\`        VARCHAR(50)  DEFAULT NULL,
        \`recording_uid\`   VARCHAR(200) DEFAULT NULL,
        \`recording_sid\`   VARCHAR(200) DEFAULT NULL,
        \`recording_resource_id\` VARCHAR(500) DEFAULT NULL,
        \`recording_url\`   VARCHAR(1000) DEFAULT NULL,
        INDEX \`idx_caller\`     (\`caller_id\`),
        INDEX \`idx_recipient\`  (\`recipient_id\`),
        INDEX \`idx_start_time\` (\`start_time\`),
        INDEX \`idx_room_id\`    (\`room_id\`)
      ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
    `);
    console.log('✅ call_history table ready');

    // Add / migrate call_history columns for existing deployments (idempotent).
    const callHistoryCols = [
      { name: 'room_id',         def: 'VARCHAR(100) DEFAULT NULL' },
      { name: 'participants',    def: 'TEXT DEFAULT NULL' },
      { name: 'ended_by',        def: 'VARCHAR(50) DEFAULT NULL' },
      { name: 'recording_uid',   def: 'VARCHAR(200) DEFAULT NULL' },
      { name: 'recording_sid',   def: 'VARCHAR(200) DEFAULT NULL' },
      { name: 'recording_resource_id', def: 'VARCHAR(500) DEFAULT NULL' },
      { name: 'recording_url',   def: 'VARCHAR(1000) DEFAULT NULL' },
    ];
    for (const { name: col, def } of callHistoryCols) {
      const [[exists]] = await conn.query(
        `SELECT 1 FROM INFORMATION_SCHEMA.COLUMNS
          WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'call_history' AND COLUMN_NAME = ?
          LIMIT 1`,
        [dbName, col],
      );
      if (!exists) {
        await conn.query(`ALTER TABLE call_history ADD COLUMN \`${col}\` ${def}`);
        console.log(`✅ Added ${col} column to call_history`);
      }
    }

    // Extend call_type ENUM to include 'group' (idempotent – safe to re-run).
    await conn.query(
      `ALTER TABLE call_history MODIFY COLUMN \`call_type\`
         ENUM('audio','video','group') NOT NULL DEFAULT 'audio'`
    ).catch(e => console.warn('call_type ENUM extend (idempotent):', e.message));

    // Extend status ENUM to include 'ended' and 'rejected' (idempotent).
    await conn.query(
      `ALTER TABLE call_history MODIFY COLUMN \`status\`
         ENUM('completed','missed','declined','cancelled','ended','rejected') NOT NULL DEFAULT 'missed'`
    ).catch(e => console.warn('status ENUM extend (idempotent):', e.message));

    // Add room_id index if not present (idempotent).
    const [[idxRoomId]] = await conn.query(
      `SELECT 1 FROM INFORMATION_SCHEMA.STATISTICS
        WHERE TABLE_SCHEMA = ? AND TABLE_NAME = 'call_history' AND INDEX_NAME = 'idx_room_id'
        LIMIT 1`,
      [dbName],
    );
    if (!idxRoomId) {
      await conn.query(
        `ALTER TABLE call_history ADD INDEX idx_room_id (room_id)`
      ).catch(e => console.warn('idx_room_id already exists:', e.message));
      console.log('✅ Added idx_room_id index to call_history');
    }

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

// POST /upload?type=image|voice
app.post('/upload', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file uploaded' });
  const subDir = req.query.type === 'voice' ? 'voice_messages' : 'chat_images';
  const fileUrl = `${req.protocol}://${req.get('host')}/uploads/${subDir}/${req.file.filename}`;
  res.json({ url: fileUrl });
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

// POST /api/calls — Log a new call.
// If roomId is provided and a record already exists for that roomId, the caller
// is appended to the participants array instead of creating a duplicate record.
app.post('/api/calls', async (req, res) => {
  try {
    const {
      callId, callerId, callerName = '', callerImage = '',
      recipientId = '', recipientName = '', recipientImage = '',
      callType = 'audio', initiatedBy,
      roomId,       // channel/room identifier for deduplication
      participants, // initial array of participant user-IDs (strings)
    } = req.body;

    if (!callId || !callerId || !initiatedBy) {
      return res.status(400).json({ error: 'callId, callerId, initiatedBy are required' });
    }

    const safeCallType = ['audio', 'video', 'group'].includes(callType) ? callType : 'audio';

    // Build initial participants JSON array (always stored as an array).
    const initParticipants = Array.isArray(participants)
      ? participants.map(p => p.toString())
      : (recipientId ? [callerId.toString(), recipientId.toString()] : [callerId.toString()]);
    const participantsJson = JSON.stringify(initParticipants);

    let finalCallId = callId;

    // If roomId is provided, check for an existing record to avoid duplicates.
    if (roomId) {
      const [[existing]] = await pool.query(
        'SELECT call_id, participants FROM call_history WHERE room_id = ? LIMIT 1',
        [roomId.toString()],
      );

      if (existing) {
        finalCallId = existing.call_id;
        // Append the new caller to participants if not already present.
        try {
          const existingParticipants = JSON.parse(existing.participants || '[]');
          if (!existingParticipants.includes(callerId.toString())) {
            existingParticipants.push(callerId.toString());
            await pool.query(
              'UPDATE call_history SET participants = ? WHERE room_id = ?',
              [JSON.stringify(existingParticipants), roomId.toString()],
            );
          }
        } catch (_) { /* ignore JSON parse errors */ }
        return res.json({ success: true, callId: finalCallId });
      }
    }

    await pool.query(
      `INSERT INTO call_history
         (call_id, room_id, caller_id, caller_name, caller_image,
          recipient_id, recipient_name, recipient_image,
          call_type, participants, start_time, status, initiated_by)
       VALUES (?,?,?,?,?,?,?,?,?,?,UTC_TIMESTAMP(),'missed',?)`,
      [finalCallId, roomId || null, callerId, callerName, callerImage,
       recipientId, recipientName, recipientImage,
       safeCallType, participantsJson, initiatedBy],
    );

    // Log call_made for caller, call_received for recipient
    await logActivity({
      userId: callerId, userName: callerName,
      targetId: recipientId || null, targetName: recipientName || null,
      activityType: 'call_made',
      description: `${callerName || 'User '+callerId} le ${recipientName || 'User '+recipientId} lai ${callType} call garyo`,
    });
    if (recipientId) {
      await logActivity({
        userId: recipientId, userName: recipientName,
        targetId: callerId, targetName: callerName,
        activityType: 'call_received',
        description: `${recipientName || 'User '+recipientId} le ${callerName || 'User '+callerId} bata ${callType} call payo`,
      });
    }

    res.json({ success: true, callId: finalCallId });
  } catch (err) {
    console.error('POST /api/calls error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// PUT /api/calls/:callId — Update call end (duration is calculated server-side from timestamps)
app.put('/api/calls/:callId', async (req, res) => {
  try {
    const { callId } = req.params;
    const { status, endedBy } = req.body;

    const allowed = ['completed', 'missed', 'declined', 'cancelled', 'ended', 'rejected'];
    const safeStatus = allowed.includes(status) ? status : 'missed';

    await pool.query(
      `UPDATE call_history
          SET end_time = UTC_TIMESTAMP(),
              duration = GREATEST(0, TIMESTAMPDIFF(SECOND, start_time, UTC_TIMESTAMP())),
              status   = ?,
              ended_by = COALESCE(?, ended_by)
        WHERE call_id = ? AND end_time IS NULL`,
      [safeStatus, endedBy || null, callId],
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
      roomId:         r.room_id   || null,
      callerId:       r.caller_id,
      callerName:     r.caller_name,
      callerImage:    r.caller_image,
      recipientId:    r.recipient_id,
      recipientName:  r.recipient_name,
      recipientImage: r.recipient_image,
      callType:       r.call_type,
      participants:   (() => { try { return JSON.parse(r.participants || '[]'); } catch(_) { return []; } })(),
      startTime:      r.start_time ? r.start_time.toISOString() : null,
      endTime:        r.end_time   ? r.end_time.toISOString()   : null,
      duration:       r.duration,
      status:         r.status,
      initiatedBy:    r.initiated_by,
      endedBy:        r.ended_by || null,
      recordingUrl:   r.recording_url || null,
    }));

    res.json({ success: true, calls });
  } catch (err) {
    console.error('GET /api/calls error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// GET /api/admin/calls — Admin endpoint: paginated call history for all users
app.get('/api/admin/calls', async (req, res) => {
  try {
    const page     = Math.max(1, parseInt(req.query.page  || '1',   10));
    const limit    = Math.min(100, Math.max(1, parseInt(req.query.limit || '50', 10)));
    const offset   = (page - 1) * limit;
    const search   = (req.query.search  || '').toString().trim();
    const callType = (req.query.callType || '').toString().trim();
    const status   = (req.query.status  || '').toString().trim();
    const dateFrom = (req.query.dateFrom || '').toString().trim();
    const dateTo   = (req.query.dateTo   || '').toString().trim();

    const where  = [];
    const params = [];

    if (search) {
      where.push('(caller_name LIKE ? OR recipient_name LIKE ? OR caller_id = ? OR recipient_id = ?)');
      const like = `%${search}%`;
      params.push(like, like, search, search);
    }
    if (['audio', 'video', 'group'].includes(callType)) {
      where.push('call_type = ?');
      params.push(callType);
    }
    const allowedStatuses = ['completed', 'missed', 'declined', 'cancelled', 'ended', 'rejected'];
    if (allowedStatuses.includes(status)) {
      where.push('status = ?');
      params.push(status);
    }
    if (dateFrom) { where.push('DATE(start_time) >= ?'); params.push(dateFrom); }
    if (dateTo)   { where.push('DATE(start_time) <= ?'); params.push(dateTo);   }

    const whereSql = where.length ? `WHERE ${where.join(' AND ')}` : '';

    const [[{ total }]] = await pool.query(
      `SELECT COUNT(*) AS total FROM call_history ${whereSql}`,
      params,
    );

    const dataParams = [...params, limit, offset];
    const [rows] = await pool.query(
      `SELECT * FROM call_history ${whereSql} ORDER BY start_time DESC LIMIT ? OFFSET ?`,
      dataParams,
    );

    const calls = rows.map(r => ({
      callId:         r.call_id,
      roomId:         r.room_id   || null,
      callerId:       r.caller_id,
      callerName:     r.caller_name,
      callerImage:    r.caller_image,
      recipientId:    r.recipient_id,
      recipientName:  r.recipient_name,
      recipientImage: r.recipient_image,
      callType:       r.call_type,
      participants:   (() => { try { return JSON.parse(r.participants || '[]'); } catch(_) { return []; } })(),
      startTime:      r.start_time ? r.start_time.toISOString() : null,
      endTime:        r.end_time   ? r.end_time.toISOString()   : null,
      duration:       r.duration,
      status:         r.status,
      initiatedBy:    r.initiated_by,
      endedBy:        r.ended_by || null,
      recordingUrl:   r.recording_url || null,
    }));

    res.json({
      success:    true,
      calls,
      total:      Number(total),
      page,
      limit,
      totalPages: total > 0 ? Math.ceil(Number(total) / limit) : 1,
    });
  } catch (err) {
    console.error('GET /api/admin/calls error:', err.message);
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
// Agora Cloud Recording REST API integration
// Docs: https://docs.agora.io/en/cloud-recording/
//
// Required env vars:
//   AGORA_APP_ID          – Agora App ID (same as mobile app)
//   AGORA_CUSTOMER_ID     – Agora Customer ID (RESTful API credential)
//   AGORA_CUSTOMER_SECRET – Agora Customer Secret
//   AGORA_STORAGE_VENDOR  – 1=Qiniu, 2=Amazon S3, 3=Alibaba, 6=Microsoft Azure
//   AGORA_STORAGE_REGION  – Storage region number (vendor-specific)
//   AGORA_STORAGE_BUCKET  – Storage bucket name
//   AGORA_STORAGE_KEY     – Storage access key
//   AGORA_STORAGE_SECRET  – Storage secret
// ──────────────────────────────────────────────────────────────────────────────

const AGORA_APP_ID          = process.env.AGORA_APP_ID          || '';
const AGORA_CUSTOMER_ID     = process.env.AGORA_CUSTOMER_ID     || '';
const AGORA_CUSTOMER_SECRET = process.env.AGORA_CUSTOMER_SECRET || '';
const AGORA_STORAGE_VENDOR  = parseInt(process.env.AGORA_STORAGE_VENDOR  || '0', 10);
const AGORA_STORAGE_REGION  = parseInt(process.env.AGORA_STORAGE_REGION  || '0', 10);
const AGORA_STORAGE_BUCKET  = process.env.AGORA_STORAGE_BUCKET  || '';
const AGORA_STORAGE_KEY     = process.env.AGORA_STORAGE_KEY     || '';
const AGORA_STORAGE_SECRET  = process.env.AGORA_STORAGE_SECRET  || '';

const AGORA_RECORDING_BASE  = `https://api.agora.io/v1/apps/${AGORA_APP_ID}/cloud_recording`;

function _agoraAuthHeader() {
  const cred = Buffer.from(`${AGORA_CUSTOMER_ID}:${AGORA_CUSTOMER_SECRET}`).toString('base64');
  return `Basic ${cred}`;
}

function _agoraEnabled() {
  return AGORA_APP_ID && AGORA_CUSTOMER_ID && AGORA_CUSTOMER_SECRET && AGORA_STORAGE_BUCKET;
}

// POST /api/calls/:callId/start-recording
// Body: { channelName, uid (string UID used for recording bot) }
app.post('/api/calls/:callId/start-recording', async (req, res) => {
  if (!_agoraEnabled()) {
    return res.status(501).json({ error: 'Agora cloud recording is not configured on this server.' });
  }
  try {
    const { callId } = req.params;
    const { channelName, uid = '0' } = req.body || {};
    if (!channelName) return res.status(400).json({ error: 'channelName is required' });

    // 1. Acquire a resource
    const acquireResp = await fetch(`${AGORA_RECORDING_BASE}/acquire`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json', Authorization: _agoraAuthHeader() },
      body: JSON.stringify({ cname: channelName, uid, clientRequest: { resourceExpiredHour: 24 } }),
    });
    if (!acquireResp.ok) {
      const txt = await acquireResp.text();
      console.error('Agora acquire failed:', acquireResp.status, txt);
      return res.status(502).json({ error: 'Failed to acquire Agora recording resource' });
    }
    const { resourceId } = await acquireResp.json();

    // 2. Start composite recording
    const startResp = await fetch(
      `${AGORA_RECORDING_BASE}/resourceid/${resourceId}/mode/mix/start`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: _agoraAuthHeader() },
        body: JSON.stringify({
          cname: channelName,
          uid,
          clientRequest: {
            token: '',   // pass token if the channel requires one
            recordingConfig: {
              maxIdleTime:          30,
              streamTypes:          2,   // 0=audio only, 1=video only, 2=audio+video
              channelType:          0,   // 0=communication
              videoStreamType:      0,
              transcodingConfig: {
                width: 360, height: 640, fps: 15, bitrate: 500,
                mixedVideoLayout: 1, backgroundColor: '#000000',
              },
            },
            storageConfig: {
              vendor:    AGORA_STORAGE_VENDOR,
              region:    AGORA_STORAGE_REGION,
              bucket:    AGORA_STORAGE_BUCKET,
              accessKey: AGORA_STORAGE_KEY,
              secretKey: AGORA_STORAGE_SECRET,
              fileNamePrefix: ['recordings', channelName],
            },
          },
        }),
      },
    );
    if (!startResp.ok) {
      const txt = await startResp.text();
      console.error('Agora start-recording failed:', startResp.status, txt);
      return res.status(502).json({ error: 'Failed to start Agora recording' });
    }
    const { sid } = await startResp.json();

    // Persist resourceId and sid in call_history for later stop
    await pool.query(
      'UPDATE call_history SET recording_resource_id = ?, recording_sid = ?, recording_uid = ? WHERE call_id = ?',
      [resourceId, sid, uid, callId],
    );

    console.log(`🎙️  Recording started for callId=${callId} resourceId=${resourceId} sid=${sid}`);
    res.json({ success: true, resourceId, sid });
  } catch (err) {
    console.error('POST /api/calls/:callId/start-recording error:', err.message);
    res.status(500).json({ error: 'Internal server error' });
  }
});

// POST /api/calls/:callId/stop-recording
app.post('/api/calls/:callId/stop-recording', async (req, res) => {
  if (!_agoraEnabled()) {
    return res.status(501).json({ error: 'Agora cloud recording is not configured on this server.' });
  }
  try {
    const { callId } = req.params;

    // Fetch recording state from DB
    const [[call]] = await pool.query(
      'SELECT recording_resource_id, recording_sid, recording_uid, caller_id, recipient_id FROM call_history WHERE call_id = ? LIMIT 1',
      [callId],
    );
    if (!call || !call.recording_resource_id || !call.recording_sid) {
      return res.status(404).json({ error: 'No active recording found for this call' });
    }

    // We need the channelName — derive from the call_id or fetch it; use call_id as channel
    // (matches what the mobile app uses as channelName = callId UUID)
    const channelName = callId;
    const uid         = call.recording_uid || '0';

    const stopResp = await fetch(
      `${AGORA_RECORDING_BASE}/resourceid/${call.recording_resource_id}/sid/${call.recording_sid}/mode/mix/stop`,
      {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', Authorization: _agoraAuthHeader() },
        body: JSON.stringify({
          cname: channelName,
          uid,
          clientRequest: {},
        }),
      },
    );
    if (!stopResp.ok) {
      const txt = await stopResp.text();
      console.error('Agora stop-recording failed:', stopResp.status, txt);
      return res.status(502).json({ error: 'Failed to stop Agora recording' });
    }
    const stopData = await stopResp.json();

    // Extract the recording file URL(s) from serverResponse
    const serverResponse = stopData.serverResponse || {};
    const fileList = serverResponse.fileList || [];
    let recordingUrl = null;
    if (Array.isArray(fileList) && fileList.length > 0) {
      // Use the first file (typically the composite audio+video file)
      const firstFile = fileList[0];
      recordingUrl = firstFile.fileName
        ? `https://${AGORA_STORAGE_BUCKET}.s3.amazonaws.com/${firstFile.fileName}`
        : null;
    } else if (typeof fileList === 'string') {
      recordingUrl = fileList;
    }

    if (recordingUrl) {
      await pool.query(
        'UPDATE call_history SET recording_url = ? WHERE call_id = ?',
        [recordingUrl, callId],
      );
    }

    // Notify admin room that a recording is now available
    io.to('admin_activity').emit('call_recording_ready', {
      callId,
      recordingUrl,
      callerId:    call.caller_id,
      recipientId: call.recipient_id,
    });

    console.log(`🎙️  Recording stopped for callId=${callId} url=${recordingUrl}`);
    res.json({ success: true, recordingUrl, fileList });
  } catch (err) {
    console.error('POST /api/calls/:callId/stop-recording error:', err.message);
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

// Tracks extra (conference) participants added to ongoing calls.
// channelName (string) → Set<userId (string)>
// Used to ensure all added participants receive call_ended when the call stops.
const conferenceParticipants = new Map();

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
  await pool.query(
    `INSERT IGNORE INTO chat_rooms
       (id, participants, participant_names, participant_images, last_message, last_message_type, last_message_time, last_message_sender_id)
     VALUES (?, ?, ?, ?, '', 'text', UTC_TIMESTAMP(), '')`,
    [
      chatRoomId,
      JSON.stringify([user1Id, user2Id]),
      JSON.stringify({ [user1Id]: user1Name, [user2Id]: user2Name }),
      JSON.stringify({ [user1Id]: user1Image, [user2Id]: user2Image }),
    ],
  );

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
  return rooms.map(r => ({
    chatRoomId:          r.id,
    participants:        JSON.parse(r.participants),
    participantNames:    JSON.parse(r.participant_names),
    participantImages:   JSON.parse(r.participant_images),
    lastMessage:         r.last_message,
    lastMessageType:     r.last_message_type,
    lastMessageTime:     r.last_message_time,
    lastMessageSenderId: r.last_message_sender_id,
    unreadCount:         r.unread_count,
  }));
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

  return {
    messageId:             row.message_id,
    chatRoomId:            row.chat_room_id,
    senderId:              row.sender_id,
    receiverId:            row.receiver_id,
    message:               row.message,
    messageType:           row.message_type,
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

    // ── Real-time admin monitoring ────────────────────────────────────────
    // Emit full message content (with sensitive data masked) to the admin room
    // so admins see exact messages in real-time.
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
    if (rest.channelName) {
      if (callerStr !== '1') activeCallUsers.set(callerStr, rest.channelName);
      if (recipientStr && recipientStr !== '1') activeCallUsers.set(recipientStr, rest.channelName);
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
    io.to(`user:${callerId.toString()}`).emit('call_rejected', {
      ...rest,
      callerId: callerId.toString(),
    });
  });

  // ── call_cancel ───────────────────────────────────────────────────────────
  // Caller emits this when they cancel before the recipient answers.
  socket.on('call_cancel', (data) => {
    const { recipientId, ...rest } = data || {};
    if (!recipientId) return;
    if (rest.channelName) activePendingCalls.delete(rest.channelName);
    io.to(`user:${recipientId.toString()}`).emit('call_cancelled', {
      ...rest,
      recipientId: recipientId.toString(),
    });
  });

  // ── call_end ─────────────────────────────────────────────────────────────
  // Either party emits this to notify the other the call has ended.
  socket.on('call_end', async (data) => {
    const { callerId, recipientId, callId, roomId, status, endedBy, ...rest } = data || {};
    if (rest.channelName) activePendingCalls.delete(rest.channelName);
    // Remove both parties from the active-call tracking set
    if (callerId)    activeCallUsers.delete(callerId.toString());
    if (recipientId) activeCallUsers.delete(recipientId.toString());
    if (callerId) {
      io.to(`user:${callerId.toString()}`).emit('call_ended', {
        ...rest, callerId, recipientId, callId, roomId,
      });
    }
    if (recipientId) {
      io.to(`user:${recipientId.toString()}`).emit('call_ended', {
        ...rest, callerId, recipientId, callId, roomId,
      });
    }
    // Notify any conference participants that were added to this call.
    if (rest.channelName && conferenceParticipants.has(rest.channelName)) {
      for (const participantId of conferenceParticipants.get(rest.channelName)) {
        const pidStr = participantId.toString();
        // Skip the original caller/recipient who were already notified above.
        if (pidStr === callerId?.toString() || pidStr === recipientId?.toString()) continue;
        activeCallUsers.delete(pidStr);
        io.to(`user:${pidStr}`).emit('call_ended', {
          ...rest, callerId, recipientId, callId, roomId,
        });
      }
      conferenceParticipants.delete(rest.channelName);
    }

    // Persist the call-end in the database so the record is updated even if
    // the client's subsequent REST PUT call is delayed or dropped.
    // callId   = explicit UUID from logCall  (preferred)
    // channelName is also stored as room_id, so use it as fallback room lookup.
    const effectiveRoomId = roomId
      ? roomId.toString()
      : (rest.channelName ? rest.channelName : null);

    if (callId || effectiveRoomId) {
      try {
        const allowed = ['completed', 'missed', 'declined', 'cancelled', 'ended', 'rejected'];
        const safeStatus = allowed.includes(status) ? status : 'ended';
        const safeEndedBy = endedBy
          ? endedBy.toString()
          : (callerId ? callerId.toString() : null);

        let updated = false;

        // Try to update by call_id first (most precise).
        if (callId) {
          const [result] = await pool.query(
            `UPDATE call_history
                SET end_time = UTC_TIMESTAMP(),
                    duration = GREATEST(0, TIMESTAMPDIFF(SECOND, start_time, UTC_TIMESTAMP())),
                    status   = ?,
                    ended_by = COALESCE(?, ended_by)
              WHERE call_id = ? AND end_time IS NULL`,
            [safeStatus, safeEndedBy, callId.toString()],
          );
          updated = result.affectedRows > 0;
        }

        // Fall back to room_id (channelName stored as room_id at call start).
        if (!updated && effectiveRoomId) {
          await pool.query(
            `UPDATE call_history
                SET end_time = UTC_TIMESTAMP(),
                    duration = GREATEST(0, TIMESTAMPDIFF(SECOND, start_time, UTC_TIMESTAMP())),
                    status   = ?,
                    ended_by = COALESCE(?, ended_by)
              WHERE room_id = ? AND end_time IS NULL`,
            [safeStatus, safeEndedBy, effectiveRoomId],
          );
        }
      } catch (err) {
        console.error('call_end DB update error:', err.message);
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
  // Admin emits this to add a third participant to an ongoing call (conference call).
  // This notifies the new participant and all existing participants.
  socket.on('add_participant_to_call', (data) => {
    const { newParticipantId, channelName, callType, adminId, adminName, existingParticipantId, ...rest } = data || {};
    if (!newParticipantId || !channelName) return;

    // Track only the newly added participant so they receive call_ended when
    // the call stops. The original callerId/recipientId are already notified
    // via the call_end handler's direct emit, so they are intentionally
    // excluded here to avoid duplicate events.
    if (!conferenceParticipants.has(channelName)) {
      conferenceParticipants.set(channelName, new Set());
    }
    conferenceParticipants.get(channelName).add(newParticipantId.toString());

    // Notify the new participant they're being added to a call
    io.to(`user:${newParticipantId.toString()}`).emit('added_to_call', {
      channelName,
      callType: callType || 'audio',
      adminId: adminId ? adminId.toString() : undefined,
      adminName,
      existingParticipantId: existingParticipantId ? existingParticipantId.toString() : undefined,
      ...rest,
    });

    // Notify existing participants that a new user joined
    if (existingParticipantId) {
      io.to(`user:${existingParticipantId.toString()}`).emit('participant_added_to_call', {
        newParticipantId: newParticipantId.toString(),
        channelName,
        callType: callType || 'audio',
        ...rest,
      });
    }

    // Notify admin (if different from sender)
    if (adminId) {
      io.to(`user:${adminId.toString()}`).emit('participant_added_to_call', {
        newParticipantId: newParticipantId.toString(),
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

    // Notify admin that new participant accepted
    if (adminId) {
      io.to(`user:${adminId.toString()}`).emit('participant_accepted_call', {
        acceptedById: acceptedById ? acceptedById.toString() : undefined,
        channelName,
        ...rest,
      });
    }

    // Notify existing participant
    if (existingParticipantId) {
      io.to(`user:${existingParticipantId.toString()}`).emit('participant_accepted_call', {
        acceptedById: acceptedById ? acceptedById.toString() : undefined,
        channelName,
        ...rest,
      });
    }
  });

  // ── participant_call_reject ───────────────────────────────────────────────
  // New participant rejects the conference call invitation
  socket.on('participant_call_reject', (data) => {
    const { adminId, existingParticipantId, channelName, rejectedById, ...rest } = data || {};
    if (!channelName) return;

    // Notify admin that new participant rejected
    if (adminId) {
      io.to(`user:${adminId.toString()}`).emit('participant_rejected_call', {
        rejectedById: rejectedById ? rejectedById.toString() : undefined,
        channelName,
        ...rest,
      });
    }

    // Notify existing participant (optional)
    if (existingParticipantId) {
      io.to(`user:${existingParticipantId.toString()}`).emit('participant_rejected_call', {
        rejectedById: rejectedById ? rejectedById.toString() : undefined,
        channelName,
        ...rest,
      });
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
    // Remove disconnected user from any conference participant sets.
    for (const [channelName, participants] of conferenceParticipants) {
      participants.delete(authenticatedUserId);
      if (participants.size === 0) conferenceParticipants.delete(channelName);
    }

    await upsertOnlineStatus(authenticatedUserId, false);

    // Notify contacts
    socket.broadcast.emit('user_status_change', {
      userId:   authenticatedUserId,
      isOnline: false,
      lastSeen: new Date().toISOString(),
    });

    // Auto-fix dangling call records where end_time is still NULL.
    // This handles the case where the call_end socket event was never emitted
    // (e.g. app crashed, network loss, or aggressive battery kill).
    // Only fix records that started at least 30 seconds ago to avoid
    // race-condition false-positives for very fresh calls.
    try {
      await pool.query(
        `UPDATE call_history
            SET end_time = UTC_TIMESTAMP(),
                duration = GREATEST(0, TIMESTAMPDIFF(SECOND, start_time, UTC_TIMESTAMP())),
                status   = IF(status = 'missed', 'missed',
                           IF(TIMESTAMPDIFF(SECOND, start_time, UTC_TIMESTAMP()) > 0, 'ended', 'missed')),
                ended_by = COALESCE(ended_by, ?)
          WHERE (caller_id = ? OR recipient_id = ?)
            AND end_time IS NULL
            AND start_time <= DATE_SUB(UTC_TIMESTAMP(), INTERVAL 30 SECOND)`,
        [authenticatedUserId, authenticatedUserId, authenticatedUserId],
      );
    } catch (err) {
      console.error('disconnect auto-fix dangling calls error:', err.message);
    }
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
    } catch (err) {
      console.error(`Worker getChatRooms error [userId=${uid}]:`, err.message);
    }
  }
}, BATCH_INTERVAL);

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
});
