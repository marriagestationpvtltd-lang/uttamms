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
# Edit .env with your MySQL credentials, Redis config, and allowed origins
```

### 3. Install & start

#### Single-instance (development)
```bash
npm install
npm run dev      # auto-reload
```

#### Multi-instance production (recommended for 4000+ users)
```bash
npm install
npm install -g pm2

# Start 4 workers (adjust instances in ecosystem.config.js)
pm2 start ecosystem.config.js --env production
pm2 save          # persist across reboots
pm2 startup       # generate OS init script

# Nginx (load balancer in front of all instances)
sudo cp nginx.conf /etc/nginx/sites-available/socket-server
sudo ln -sf /etc/nginx/sites-available/socket-server /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx
```

## Architecture (high-concurrency)

```
Flutter clients
      │  WebSocket
      ▼
  Nginx (load balancer)
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
  .setTransports(['websocket'])
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
