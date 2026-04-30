# WebSocket HTTP 400 & CORS Error - Troubleshooting Guide

## Current Status

You're seeing **two critical errors**:

1. **WebSocket HTTP 400**: `wss://adminnew.marriagestation.com.np/socket.io/` connection rejected
2. **CORS Error**: `/api/send-message` returning no `Access-Control-Allow-Origin` header

Both indicate the **production server process hasn't restarted** since the `.env` file was created.

---

## Immediate Fix: Restart Socket Server

### Option 1: Using PM2 (Recommended for Production)

```bash
# Check if PM2 is running the socket server
pm2 list

# If it's running, restart it
pm2 restart socket-server

# Watch logs in real-time
pm2 logs socket-server
```

**Expected output after restart:**
```
⚙️  Loaded configuration:
   PORT: 3001
   ALLOWED_ORIGINS: *
   PUBLIC_URL: https://adminnew.marriagestation.com.np
   API_BASE_URL: https://digitallami.com
   CALLS_ENABLED: true
✅ MySQL connected
✅ chat_rooms table ready
🚀 Socket.IO server running on port 3001
✅ CORS is enabled for all origins
📝 Test endpoint: http://localhost:3001/health
🧪 Test CORS: http://localhost:3001/cors-test
```

### Option 2: Manual Restart (Development/Direct)

```bash
# Kill any existing Node.js processes on port 3001
lsof -i :3001
kill -9 <PID>

# Or kill all node processes
killall node

# Install dependencies if not already installed
cd Backend/socket-server
npm install

# Start the server
node server.js
```

---

## Verify Configuration

After restarting, verify the `.env` file is properly loaded:

### Test 1: Check Health Endpoint

```bash
# From any terminal/browser
curl http://localhost:3001/health | json_pp

# Expected response:
{
  "status": "ok",
  "config": {
    "port": 3001,
    "allowedOrigins": ["*"],
    "publicUrl": "https://adminnew.marriagestation.com.np",
    "apiBaseUrl": "https://digitallami.com",
    "callsEnabled": true
  }
}
```

### Test 2: Check CORS Headers

```bash
# Test CORS endpoint
curl -H "Origin: http://localhost:62386" \
     -H "Access-Control-Request-Method: POST" \
     -H "Access-Control-Request-Headers: Content-Type" \
     -X OPTIONS \
     http://localhost:3001/cors-test

# Expected response should include:
# Access-Control-Allow-Origin: *
# Access-Control-Allow-Methods: ...
```

### Test 3: Test WebSocket Connection (from Browser Console)

```javascript
// From admin web panel (http://localhost:62386)
const socket = io('wss://adminnew.marriagestation.com.np/socket.io/', {
  transports: ['websocket'],
  auth: { 
    userId: '1',  // admin user ID
  }
});

socket.on('connect', () => {
  console.log('✅ WebSocket connected!');
});

socket.on('connect_error', (err) => {
  console.error('❌ Connection error:', err.message);
  console.error('Code:', err.code);
});

socket.on('disconnect', (reason) => {
  console.log('⚠️ Disconnected:', reason);
});
```

---

## Root Causes & Solutions

### Problem: HTTP 400 on WebSocket Handshake

**Possible Causes:**

1. ✅ **Server not restarted** - `.env` file created but process still running with old config
   - **Fix**: `pm2 restart socket-server` or restart manually

2. ⚠️ **Nginx reverse proxy not configured for WebSocket**
   - **Fix**: Verify Nginx has these headers in `/socket.io/` location:
     ```nginx
     proxy_http_version 1.1;
     proxy_set_header Upgrade $http_upgrade;
     proxy_set_header Connection "upgrade";
     ```

3. ⚠️ **SSL certificate mismatch or expired**
   - **Fix**: Verify certificate:
     ```bash
     openssl s_client -connect adminnew.marriagestation.com.np:443
     ```

4. ⚠️ **Port 3001 not accessible**
   - **Fix**: Check firewall and Nginx proxy rules

---

### Problem: CORS "No 'Access-Control-Allow-Origin' Header" on REST API

**Root Cause**: CORS middleware not being applied properly, usually because:

1. **Server not restarted** - Old process still running without CORS config
   - **Fix**: Restart server with updated `.env`

2. **Invalid `ALLOWED_ORIGINS` configuration**
   - Check `.env` has: `ALLOWED_ORIGINS=*`

3. **Preflight request rejected before middleware runs**
   - **Fix**: Ensure `app.use(cors({...}))` is first middleware

---

## Enhanced Error Logging (Now Available)

I've added better logging to help diagnose issues. After restart, you'll see:

### In Server Console:
```
⚙️  Loaded configuration:
   PORT: 3001
   ALLOWED_ORIGINS: *
   PUBLIC_URL: https://adminnew.marriagestation.com.np
   API_BASE_URL: https://digitallami.com
   CALLS_ENABLED: true

✅ MySQL connected
🚀 Socket.IO server running on port 3001
✅ CORS is enabled for all origins
📝 Test endpoint: http://localhost:3001/health
🧪 Test CORS: http://localhost:3001/cors-test
```

### On Connection Errors:
```
❌ Socket.IO connection error: {
  code: 'EADDRINUSE',
  message: 'Port 3001 is already in use',
  status: 400
}
```

### Socket Diagnostics:
```
🔌 Socket connected: abc123xyz from 192.168.1.100
✅ Authenticated: userId=1
👋 Socket disconnected: abc123xyz (user: 1, reason: transport close)
```

---

## Step-by-Step Recovery

### 1. Stop Current Server
```bash
pm2 stop socket-server
# or
killall node
```

### 2. Verify .env File Exists
```bash
cat Backend/socket-server/.env | head -20

# Should show:
# PORT=3001
# ALLOWED_ORIGINS=*
# PUBLIC_URL=https://adminnew.marriagestation.com.np
```

### 3. Install Dependencies
```bash
cd Backend/socket-server
npm install
```

### 4. Start Server
```bash
# Option A: Manual (for debugging)
node server.js

# Option B: PM2 (production)
pm2 start ecosystem.config.js --env production
```

### 5. Verify Startup
```bash
# Check logs
pm2 logs socket-server --lines 50

# Test health endpoint
curl http://localhost:3001/health
```

### 6. Test from Admin Panel
```javascript
// Open Browser DevTools on admin panel
const socket = io('wss://adminnew.marriagestation.com.np/socket.io/', {
  transports: ['websocket'],
  auth: { userId: '1' }
});

socket.on('connect', () => console.log('✅ Connected'));
socket.on('error', (e) => console.error('❌', e));
```

---

## If HTTP 400 Still Occurs

1. **Check server logs for handshake errors:**
   ```bash
   pm2 logs socket-server --err | tail -50
   ```

2. **Test basic TCP connectivity:**
   ```bash
   telnet adminnew.marriagestation.com.np 443
   # or
   nc -zv adminnew.marriagestation.com.np 3001
   ```

3. **Verify Nginx config is passing WebSocket headers:**
   ```bash
   sudo nginx -t  # validate config
   sudo systemctl reload nginx
   ```

4. **Check if using reverse proxy with wrong port:**
   - Client connecting to: `wss://adminnew.marriagestation.com.np/socket.io/`
   - Should proxy to: `http://127.0.0.1:3001/socket.io/`
   - Not to any other port

---

## APK Side - Already Fixed

Once socket connects, these APK fixes activate automatically:
- ✅ Safe unread count parsing
- ✅ Participant name resolution fallbacks
- ✅ Socket retry with exponential backoff
- ✅ Defensive row rendering
- ✅ Robust user bootstrap

The chat list will populate within 1-2 seconds of successful connection.

---

## Performance Baseline

After successful restart, expect in logs:
```
📊 Stats | msg/s: 2-5 | queue: 0-10 | heap: 60MB | rss: 120MB
```

High queue or msg/s indicates overload.

---

## Quick Restart Command

```bash
pm2 restart socket-server && pm2 logs socket-server
```

Monitor logs until you see:
```
🚀 Socket.IO server running on port 3001
✅ CORS is enabled for all origins
```

Then test from admin panel console again.
