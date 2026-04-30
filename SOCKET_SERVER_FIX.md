# Socket.IO Server Fix Guide

## Problem Summary
The WebSocket connection is failing with **HTTP 400 error** when clients try to connect to `wss://adminnew.marriagestation.com.np/socket.io/`. This is preventing the chat functionality from working entirely.

## Root Causes Identified

### 1. ✅ FIXED: Missing `.env` Configuration File
**Status**: Fixed - Created `.env` at `Backend/socket-server/.env`

The Socket.IO server was running without proper environment configuration. This has been resolved by creating a proper `.env` file with:
- Database credentials
- CORS settings (set to allow all origins: `*`)
- PUBLIC_URL pointing to the production domain
- Port configuration

### 2. ⚠️ REQUIRES ACTION: Server Infrastructure Check
**Status**: Needs verification on production server

The HTTP 400 error during WebSocket handshake suggests one of these issues on the production server:
- [ ] Socket.IO server is not running on port 3001
- [ ] Nginx/Apache reverse proxy not configured for WebSocket upgrades
- [ ] SSL certificate is invalid or expired
- [ ] Firewall blocking port 3001 or 443
- [ ] Node.js dependencies not installed (`npm install` not run)

### 3. Secondary Issue: Image CORS Headers
**Status**: Not fixed yet

The image CDN (digitallami.com) is returning duplicate `Access-Control-Allow-Origin` headers:
```
Access-Control-Allow-Origin: *, *
```

This should be fixed by ensuring only a single header value is sent.

## Required Actions for Production Server

### Step 1: Install Node.js Dependencies
```bash
cd /path/to/Backend/socket-server
npm install
```

### Step 2: Verify `.env` Configuration
Check `/path/to/Backend/socket-server/.env`:
```bash
PORT=3001
DB_HOST=localhost
DB_PORT=3306
DB_NAME=ms
DB_USER=root
DB_PASSWORD=(your_password)
ALLOWED_ORIGINS=*
PUBLIC_URL=https://adminnew.marriagestation.com.np
CALLS_ENABLED=true
API_BASE_URL=https://digitallami.com
```

### Step 3: Test Socket Server Startup
```bash
# Test run the server
cd /path/to/Backend/socket-server
node server.js

# Expected output:
# ✅ MySQL connected
# 🚀 Socket.IO server running on port 3001
```

### Step 4: Verify Database Connection
The server will print:
```
✅ MySQL connected
✅ MySQL session timezone set to UTC
✅ chat_rooms table ready
✅ chat_unread_counts table ready
✅ chat_messages table ready
✅ user_online_status table ready
```

If you see database errors, check:
- MySQL is running
- DB_HOST, DB_USER, DB_PASSWORD are correct in `.env`
- Database `ms` exists

### Step 5: Configure Nginx Reverse Proxy
Verify your Nginx configuration includes proper WebSocket upgrade headers:

```nginx
location /socket.io/ {
    proxy_pass http://127.0.0.1:3001;
    
    # Essential WebSocket headers
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    
    # Forward client info
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
    
    # Long timeouts for WebSocket
    proxy_connect_timeout 60s;
    proxy_send_timeout 600s;
    proxy_read_timeout 600s;
    
    # No buffering for real-time
    proxy_buffering off;
}
```

### Step 6: Use PM2 for Production
```bash
# Install PM2 globally
npm install -g pm2

# Start with ecosystem config
pm2 start ecosystem.config.js --env production

# Check logs
pm2 logs socket-server

# Make persistent
pm2 save
pm2 startup
```

### Step 7: Verify WebSocket Connection
Test from browser console:
```javascript
// From admin web panel console
const socket = io('wss://adminnew.marriagestation.com.np/socket.io/', {
  transports: ['websocket'],
  auth: { userId: '1' }
});

socket.on('connect', () => console.log('✅ Connected!'));
socket.on('connect_error', (err) => console.error('❌ Error:', err.message));
socket.on('disconnect', () => console.log('⚠️ Disconnected'));
```

## APK-Side Fixes (Already Applied)

✅ All defensive parsing and retry logic already implemented in:
- `apk/lib/Chat/ChatlistScreen.dart`
  - Safe unread count parsing (_safeUnreadCount)
  - Participant fallback resolution (_participantsFromRoom)
  - Socket retry with exponential backoff (_fetchChatRoomsWithRetry)
  - Robust user bootstrap on API failure

These fixes will automatically activate once the WebSocket connection is established.

## Image CORS Fix (Separate Issue)

The image CDN duplicate header needs fixing in `Backend/Api2/` or wherever images are served:

**Problem**: Returning duplicate headers
```
Access-Control-Allow-Origin: *, *
```

**Fix**: Ensure single header
```php
header('Access-Control-Allow-Origin: *');  // Single header, only once
```

## Testing Checklist

After implementing fixes:
- [ ] Node.js server starts without errors: `node server.js`
- [ ] MySQL connection succeeds
- [ ] All chat tables created/migrated
- [ ] Browser console shows WebSocket handshake: HTTP 101 (not 400)
- [ ] Admin web panel connects to socket server
- [ ] APK can fetch chat rooms via socket
- [ ] Chat list populates with conversations
- [ ] Messages send/receive in real-time
- [ ] Profile images load without CORS errors
- [ ] Online status updates in real-time

## Rollback Plan (if needed)

If WebSocket causes issues:
1. Stop the socket server: `pm2 stop socket-server`
2. APK has fallback logic to fetch chat rooms via REST API
3. But real-time updates won't work without WebSocket

## Performance Baseline

Once working, expected stats in logs:
```
📊 Stats | msg/s: 5-10 | queue: 0-50 | sockets: 10-50 | heap: 50-100MB | rss: 100-150MB
```

High msg/s or queue size indicates overload.

## Support Commands

```bash
# View running processes
pm2 list

# View detailed logs
pm2 logs socket-server --lines 100

# View server status
curl -s https://adminnew.marriagestation.com.np/health | json_pp

# Restart server
pm2 restart socket-server

# Stop server
pm2 stop socket-server

# Check process memory usage
pm2 monit
```
