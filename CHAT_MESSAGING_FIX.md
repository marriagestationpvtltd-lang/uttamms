# Chat Messaging Issues - Root Cause and Fix

**Issue Date**: May 1, 2026  
**Status**: PARTIALLY FIXED ✅ Socket server now running | ⚠️ Requires deployment configuration

## Problem Reported
- Messages not being sent in chat
- Messages not displaying in chat  
- Affects both admin-user and user-to-user conversations

## Root Cause Analysis

### Primary Issue: Missing Database Tables ❌
The Socket.IO server (`Backend/socket-server/server.js`) was failing to connect to the database because the required tables didn't exist:

| Table | Status | Purpose |
|-------|--------|---------|
| `chat_rooms` | ❌ Missing | Stores conversation metadata |
| `chat_messages` | ❌ Missing | Stores individual messages |
| `chat_unread_counts` | ❌ Missing | Tracks unread counts per user/room |
| `user_online_status` | ❌ Missing | Tracks user online status |
| `chat`, `chats`, `userchats` | ✅ Existed | Old schema (incompatible) |

**Error in logs**: `MySQL connection failed: Table 'ms.user_online_status' doesn't exist`

### Secondary Issue: MySQL Not Running ❌
The MySQL database service (mysqld.exe) wasn't running on the system.

## Solutions Applied

### Step 1: Started MySQL Service
```bash
C:\xampp\mysql\bin\mysqld.exe --port=3306
```

### Step 2: Created Socket.IO Chat Tables
Created file: `Backend/socket-server/create_chat_tables.sql`

```sql
CREATE TABLE chat_rooms (
  id VARCHAR(150) PRIMARY KEY,
  participants JSON,
  participant_names JSON,
  participant_images JSON,
  last_message TEXT,
  last_message_type VARCHAR(50),
  last_message_time DATETIME,
  created_at DATETIME
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE chat_messages (
  id BIGINT UNSIGNED PRIMARY KEY AUTO_INCREMENT,
  message_id VARCHAR(100) UNIQUE,
  chat_room_id VARCHAR(150),
  sender_id VARCHAR(50),
  receiver_id VARCHAR(50),
  message TEXT,
  message_type VARCHAR(50),
  is_read TINYINT,
  is_delivered TINYINT,
  created_at DATETIME,
  FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE chat_unread_counts (
  chat_room_id VARCHAR(150),
  user_id VARCHAR(50),
  unread_count INT,
  PRIMARY KEY (chat_room_id, user_id),
  FOREIGN KEY (chat_room_id) REFERENCES chat_rooms(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE user_online_status (
  user_id VARCHAR(50) PRIMARY KEY,
  is_online TINYINT,
  last_seen DATETIME,
  socket_id VARCHAR(255)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

Applied using:
```bash
Get-Content "Backend/socket-server/create_chat_tables.sql" | C:\xampp\mysql\bin\mysql.exe -u root ms
```

### Step 3: Started Socket.IO Server
```bash
cd Backend/socket-server
npm start
```

**Status Output**:
```
✅ MySQL connected
✅ MySQL session timezone set to UTC
✅ chat_rooms table ready
✅ chat_unread_counts table ready
✅ chat_messages table ready
✅ user_online_status table ready
✅ call_history table ready
✅ group_calls table ready
✅ user_activities table ready
🚀 Socket.IO server running on port 3001
✅ CORS is enabled for all origins
```

## Current Status ✅
- ✅ Socket.IO server running on `localhost:3001`
- ✅ MySQL connection established
- ✅ All required tables created and initialized
- ✅ Server ready to accept chat messages
- ⚠️ **App must connect to correct socket server URL**

## Next Steps Required

### For Development/Testing:
1. **Mobile App Configuration**
   - The app is configured to connect to: `https://adminnew.marriagestation.com.np`
   - For local testing, you need to either:
     - **Option A**: Rebuild the app with `SOCKET_SERVER_URL=http://192.168.x.x:3001` (your machine's local IP)
     - **Option B**: Set up a reverse proxy to forward requests to localhost:3001
     - **Option C**: Deploy socket server to the production domain

2. **Build Command Example** (for Option A):
   ```bash
   flutter run -d <device_id> --dart-define=SOCKET_SERVER_URL=http://192.168.1.100:3001
   ```

### For Production Deployment:
1. **Set up Nginx reverse proxy** (see `Backend/socket-server/nginx.conf`)
   - Configure SSL certificates (Let's Encrypt recommended)
   - Point domain (e.g., `socket.marriagestation.com.np`) to the Node.js server
   
2. **Use PM2 for process management** (see `Backend/socket-server/ecosystem.config.js`)
   ```bash
   npm install -g pm2
   pm2 start ecosystem.config.js
   ```

3. **Enable Redis adapter** for multi-instance scaling
   - Update `.env`: `REDIS_ENABLED=true`
   - Install Redis and start service

## How to Restart Services

### Start MySQL:
```bash
C:\xampp\mysql\bin\mysqld.exe --port=3306
```

### Start Socket.IO Server:
```bash
cd C:\xampp\htdocs\uttamms\Backend\socket-server
npm start
```

### Verify Services:
```bash
# Check MySQL
tasklist | findstr mysqld

# Check Node.js
tasklist | findstr node
```

## Testing Chat Functionality

Once app connects to socket server:

1. **Send a message** in app chat screen
2. **Verify database**:
   ```bash
   C:\xampp\mysql\bin\mysql.exe -u root ms -e "SELECT COUNT(*) FROM chat_messages;"
   ```
3. **Check server logs** for message broadcast confirmations
4. **Receiver should see** message appear in real-time

## Key Files Modified
- ✅ Created: `Backend/socket-server/create_chat_tables.sql`
- ✅ Started: MySQL (mysqld.exe)
- ✅ Started: Node.js Socket.IO server (port 3001)

## Troubleshooting

| Issue | Solution |
|-------|----------|
| "Table doesn't exist" error | Run `create_chat_tables.sql` again |
| MySQL connection failed | Verify `C:\xampp\mysql\bin\mysqld.exe` is running |
| Port 3001 already in use | Kill process: `taskkill /PID <pid> /F` or change PORT in `.env` |
| App can't connect | Verify socket server URL in app endpoints config |
| Messages not saving | Check database with: `SELECT * FROM chat_messages LIMIT 1;` |

## Architecture Overview
```
Flutter App (APK/Admin)
    ↓ (connects via Socket.IO)
    ↓
Nginx Reverse Proxy (production only)
    ↓
Node.js Socket.IO Server (Port 3001)
    ↓ (queries & saves)
    ↓
MySQL Database (localhost:3306)
    ↓
[chat_rooms, chat_messages, chat_unread_counts, user_online_status]
```

---
**Date Created**: May 1, 2026  
**Last Updated**: May 1, 2026  
**Status**: Awaiting app configuration and deployment setup
