# Socket.IO Chat Server

Real-time chat server for the Marriage Station Flutter app, replacing Firebase Firestore with Socket.IO + MySQL.

## Requirements
- Node.js >= 18
- MySQL >= 5.7
- Redis >= 6 (required for multi-instance / 4000+ concurrent users)

## Setup

### 1. Database
Run the migration SQL on your MySQL server:
```bash
mysql -u root -p marriagestation < sql/chat_tables.sql
```

### 2. Environment
```bash
cp .env.example .env
# Edit .env with your MySQL credentials, allowed origins, etc.
```

### 3. Install & start

#### cPanel shared hosting (recommended — no nginx needed)

cPanel's Apache handles SSL automatically.  The `.htaccess` file in this
directory configures Apache to proxy both WebSocket and HTTP requests to
the Node.js process — **no nginx or SSL certificates needed in Node.js**.

1. In cPanel → **Setup Node.js App**, create a new application:
   - **Node.js version**: 18 or higher
   - **Application root**: path to this `socket-server` folder
   - **Application URL**: the sub-domain you want (e.g. `socket.yourdomain.com`)
   - **Application startup file**: `server.js`
   - **PORT**: pick any free port (e.g. `3001`) and set it in your `.env`

2. Copy `.env.example` to `.env` and fill in your MySQL credentials and
   the `PORT` value you chose above.  **Leave `SSL_CERT_PATH` and
   `SSL_KEY_PATH` blank** — cPanel/Apache handles SSL for you.

3. Click **Run NPM Install** in the cPanel UI, then **Start** the app.

4. Verify the `.htaccess` file is present in the application root
   (it is already in this repository).  cPanel may auto-generate its own
   `.htaccess`; if so, merge the WebSocket proxy rules from the
   repository's `.htaccess` into the generated file.

5. Make sure the `ALLOWED_ORIGINS` in your `.env` includes your Flutter
   web admin URL (e.g. `https://adminnew.marriagestation.com.np`).

#### Single-instance (development / local)
```bash
npm install
npm run dev      # auto-reload
```

#### Multi-instance VPS production (for 4000+ concurrent users)
```bash
npm install
npm install -g pm2

# Start 4 workers (adjust instances in ecosystem.config.js)
pm2 start ecosystem.config.js --env production
pm2 save          # persist across reboots
pm2 startup       # generate OS init script
```

If you run on a self-managed VPS **without** any proxy in front, set
`SSL_CERT_PATH` and `SSL_KEY_PATH` in `.env` to enable native HTTPS so
browsers can make `wss://` connections.

## Architecture

### cPanel / shared hosting
```
Flutter clients
      │  wss:// → Apache (SSL, port 443)
      │              │  ws://127.0.0.1:3001 (via .htaccess mod_proxy)
      ▼              ▼
   Apache       Node.js Socket.IO  ←── MySQL
  (cPanel)       server:3001
```

### High-concurrency VPS
```
Flutter clients
      │  WebSocket
      ▼
  Nginx (load balancer, optional)
  ├─ Node.js instance :3001
  ├─ Node.js instance :3002
  ├─ Node.js instance :3003  ←── all share state via Redis adapter
  └─ Node.js instance :3004
            │
            ▼
         Redis        ← Socket.IO pub/sub adapter
            │
            ▼
         MySQL        ← persistent storage (batch writes)
```

Each PM2 worker handles ~1 000 concurrent WebSocket connections.
With 4 workers and Redis adapter you get 4 000+ concurrent users with no message loss.

## Authentication

Clients send `userId` and `token` in `socket.handshake.auth` on connection:

```dart
// Flutter (socket_service.dart)
IO.OptionBuilder()
  .setTransports(['polling', 'websocket'])  // polling first for proxy compatibility
  .setAuth({'userId': userId, 'token': bearerToken})
  .build()
```

The server middleware validates these fields and assigns `socket.userId` before any events fire.
The legacy `authenticate` event is still accepted for backward-compatible clients.

## Events Reference

### Connection auth (handshake)
Pass in `socket.handshake.auth`:
| Field | Type | Description |
|---|---|---|
| `userId` | string | User's database ID |
| `token` | string | Bearer token from login API |

### Client → Server
| Event | Payload |
|---|---|
| `authenticate` | `{userId}` — legacy fallback; prefer handshake auth |
| `join_room` | `{chatRoomId}` |
| `leave_room` | `{chatRoomId}` |
| `send_message` | `{chatRoomId, senderId, receiverId, message, messageType, messageId?, repliedTo?, isReceiverViewing?}` |
| `typing_start` | `{chatRoomId, userId}` |
| `typing_stop` | `{chatRoomId, userId}` |
| `mark_read` | `{chatRoomId, userId}` |
| `set_active_chat` | `{userId, chatRoomId, isActive}` |
| `get_messages` | `{chatRoomId, page, limit}` + ack callback |
| `get_chat_rooms` | `{userId}` + ack callback |
| `edit_message` | `{chatRoomId, messageId, newMessage}` |
| `delete_message` | `{chatRoomId, messageId, userId, deleteForEveryone}` |

### Server → Client
| Event | Payload |
|---|---|
| `authenticated` | `{success, userId}` |
| `new_message` | message object |
| `message_edited` | `{chatRoomId, messageId, newMessage, editedAt}` |
| `message_deleted` | `{chatRoomId, messageId, deleteForEveryone, userId}` |
| `typing_start` | `{chatRoomId, userId}` |
| `typing_stop` | `{chatRoomId, userId}` |
| `messages_read` | `{chatRoomId, userId}` |
| `user_status_change` | `{userId, isOnline, lastSeen}` |
| `chat_rooms_update` | `{chatRooms: [...]}` |
| `error` | `{message}` |

## REST Endpoints
| Method | Path | Description |
|---|---|---|
| `POST` | `/upload?type=image\|voice` | Upload chat media. Returns `{url}` |
| `GET` | `/health` | Health check |

## Flutter Integration
Set `kSocketServerBaseUrl` in `lib/config/app_endpoints.dart` to the server's URL.
The `SocketService.connect(userId, token: token)` method accepts the bearer token
from `SharedPreferences` and passes it in the socket handshake auth.
