# Architecture & Message Flow Diagram

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                     LOCAL DEVELOPMENT ENVIRONMENT                │
│                         (192.168.1.25)                           │
└──────────────────────────────────────────────────────────────────┘

┌────────────────┐                              ┌──────────────────┐
│   APK App      │                              │  Admin Panel     │
│   (User)       │                              │  (Web/Desktop)   │
│                │                              │                  │
│  Socket URL:   │                              │  Socket URL:     │
│  192.168.1.25  │                              │  192.168.1.25    │
│  :3001         │                              │  :3001           │
└────────┬────────┘                              └────────┬─────────┘
         │                                               │
         │  Socket.IO Connection (ws protocol)          │
         │                                               │
         └───────────────────────┬─────────────────────┘
                                 │
                                 ▼
                    ┌─────────────────────────┐
                    │  Socket.IO Server       │
                    │  (Node.js)              │
                    │  Port: 3001             │
                    │  Status: ✅ RUNNING    │
                    │                         │
                    │  Key Features:          │
                    │  - Receive messages     │
                    │  - Route to rooms       │
                    │  - Broadcast updates    │
                    │  - Queue messages       │
                    │  - Batch processing     │
                    └────────────┬────────────┘
                                 │
                                 │ (SQL Queries)
                                 ▼
                    ┌─────────────────────────┐
                    │  MySQL Database         │
                    │  (localhost:3306)       │
                    │  Database: ms           │
                    │  User: root             │
                    │  Password: (empty)      │
                    │                         │
                    │  Tables:                │
                    │  ✅ chat_rooms          │
                    │  ✅ chat_messages       │
                    │  ✅ chat_unread_counts  │
                    │  ✅ user_online_status  │
                    └─────────────────────────┘
```

---

## Message Flow: User to Admin

```
1. USER SENDS MESSAGE
   ┌────────────────────┐
   │ User taps Send     │
   │ _sendMessage()     │
   └────────┬───────────┘
            │
            ▼
   ┌────────────────────┐
   │ Create optimistic  │
   │ message in UI      │
   │ (shows immediately)│
   └────────┬───────────┘
            │
            ▼
   ┌────────────────────────────────────────┐
   │ Check socket.isConnected()             │
   │ - If YES: emit 'send_message' via      │
   │           socket                        │
   │ - If NO:  POST to /api/send-message    │
   └────────┬─────────────────────────────────┘
            │
            ▼
        ╔═══════════════════════════════════╗
        ║   SOCKET SERVER RECEIVES           ║
        ║   emit 'send_message' event        ║
        ╚═════════════╤═══════════════════════╝
                      │
                      ▼
        ┌──────────────────────────────────────┐
        │ 1. Validate sender & receiver        │
        │ 2. Check if either is blocked        │
        │ 3. Validate message length (64KB)    │
        └─────────────┬────────────────────────┘
                      │
                      ▼
        ┌──────────────────────────────────────┐
        │ 1. Create message object             │
        │ 2. Add to messageQueue               │
        │ 3. Broadcast immediately to room:    │
        │    'new_message' event               │
        │ 4. Broadcast to sender's rooms       │
        └─────────────┬────────────────────────┘
                      │
        ┌─────────────┴──────────────┐
        │                            │
        ▼                            ▼
   ┌─────────────────┐      ┌──────────────────────┐
   │ Admin receives  │      │ User receives        │
   │ 'new_message'   │      │ 'new_message' event  │
   │ event           │      │                      │
   │                 │      │ Update optimistic    │
   │ Replaces        │      │ message with real    │
   │ placeholder     │      │ ID from server       │
   │ with real data  │      └──────────────────────┘
   │                 │
   │ Display in UI   │
   │ immediately     │
   └─────────────────┘
        │
        │
   ┌────┴──────────────────────────────────┐
   │ Meanwhile: Socket Server Worker        │
   │ Every 750ms (or when queue > 200):     │
   │                                        │
   │ 1. Drain messageQueue (batch 200)      │
   │ 2. Ensure chat_rooms exist             │
   │ 3. INSERT messages to chat_messages    │
   │ 4. UPDATE chat_rooms.last_message      │
   │ 5. UPDATE chat_unread_counts           │
   │ 6. Broadcast 'message-batch-saved'     │
   └────────┬─────────────────────────────────┘
            │
            ▼
   ┌──────────────────────────────┐
   │ Messages Persisted in DB:    │
   │ chat_messages table          │
   │ chat_rooms updated           │
   │ chat_unread_counts updated   │
   └──────────────────────────────┘

2. FINAL STATE
   ✅ Message delivered to Admin instantly (< 100ms)
   ✅ Message saved to DB (< 1s, in batch)
   ✅ Chat room created/updated
   ✅ Unread count incremented
   ✅ Admin receives read receipt
```

---

## Message Flow: Admin to User

```
1. ADMIN SENDS MESSAGE
   ┌────────────────┐
   │ Admin taps     │
   │ send in panel  │
   │ _sendMessage() │
   └────────┬───────┘
            │
            ▼
   ┌────────────────────────┐
   │ Create optimistic msg  │
   │ in chat window         │
   │ (shows immediately)    │
   └────────┬───────────────┘
            │
            ▼
   ┌────────────────────────────────────────┐
   │ Call _socketService.ensureConnected()  │
   │ - Checks if socket.isConnected        │
   │ - Reconnects if needed                │
   │ Returns Future<bool>                   │
   └─────────────┬───────────────────────────┘
                 │
                 ▼
      ┌──────────────────────────────────┐
      │ Emit 'send_message' with:        │
      │ - chatRoomId: "1_<userId>"      │
      │ - receiverId: <userId>           │
      │ - message: text                  │
      │ - messageType: 'text'            │
      │ - messageId: unique ID           │
      │ - user1Name, user2Name           │
      │ - user1Image, user2Image         │
      └──────────────┬───────────────────┘
                     │
                     ▼
        ╔════════════════════════════════╗
        ║   SOCKET SERVER RECEIVES        ║
        ║   from Admin (userId: 1)        ║
        ╚════════════╤═══════════════════╝
                     │
                     ▼
        ┌─────────────────────────────────┐
        │ 1. Validate: sender = admin (1) │
        │ 2. Validate: receiver exists    │
        │ 3. Check block list             │
        │ 4. Create message object        │
        └──────────────┬──────────────────┘
                       │
                       ▼
        ┌─────────────────────────────────┐
        │ 1. Add to queue                 │
        │ 2. Broadcast 'new_message' to:  │
        │    - Chat room: 1_<userId>      │
        │    - User's personal room       │
        │    - Admin's personal room      │
        └──────────────┬──────────────────┘
                       │
        ┌──────────────┴───────────────────┐
        │                                  │
        ▼                                  ▼
   ┌──────────────────┐        ┌─────────────────────┐
   │ Admin receives   │        │ User (APK) receives │
   │ confirmation of  │        │ 'new_message' event │
   │ send in panel    │        │                     │
   │                  │        │ Message appears in  │
   │ Updates UI msg   │        │ chat screen         │
   │ with real ID     │        │ immediately         │
   └──────────────────┘        │                     │
                               │ Optimistic ID→Real  │
                               │ ID conversion       │
                               │                     │
                               │ Auto-scroll to      │
                               │ show new message    │
                               └─────────────────────┘
        │
        │
   ┌────┴──────────────────────────────────┐
   │ Meanwhile: Socket Server Worker        │
   │ Batch processing every 750ms:          │
   │                                        │
   │ 1. Get 200 messages from queue         │
   │ 2. Ensure chat room exists             │
   │ 3. INSERT into chat_messages           │
   │ 4. UPDATE chat_rooms.last_message      │
   │ 5. Increment chat_unread_counts        │
   │ 6. Broadcast saved event               │
   └────────────┬──────────────────────────┘
                │
                ▼
   ┌──────────────────────────────────┐
   │ Database persisted:              │
   │ ✅ Message in chat_messages      │
   │ ✅ Chat room last_message set    │
   │ ✅ Unread count incremented      │
   └──────────────────────────────────┘

2. FINAL STATE
   ✅ Message delivered to User (< 100ms)
   ✅ Message saved to DB (< 1s)
   ✅ Chat room created/updated
   ✅ Unread count incremented  
   ✅ User can see message immediately
```

---

## Event Listeners in Admin Panel

```
┌──────────────────────────────────────────────┐
│ Admin Panel (_setupSocketListeners)          │
└──────────────────────────────────────────────┘

┌─ onNewMessage ─────────────────────────────┐
│ Trigger: 'new_message' socket event         │
│ Action:  Update message list                │
│ Filter:  Match chatRoomId                   │
│ Update:  Add or replace message in UI       │
│ Mark:    Messages as read (if from user)    │
│ Save:    Cache messages locally             │
│ Scroll:  Auto-scroll to new message         │
└──────────────────────────────────────────────┘

┌─ onMessageEdited ──────────────────────────┐
│ Trigger: 'message_edited' event             │
│ Action:  Update message text in list        │
│ Set:     'edited' = true                    │
│ Sync:    Update filtered messages           │
│ Save:    Cache to local storage             │
└──────────────────────────────────────────────┘

┌─ onMessageDeleted ─────────────────────────┐
│ Trigger: 'message_deleted' event            │
│ Action:  Mark message as deleted            │
│ Display: "This message was deleted."        │
│ Save:    Cache update                       │
└──────────────────────────────────────────────┘

┌─ onMessageUnsent ──────────────────────────┐
│ Trigger: 'message_unsent' event             │
│ Action:  Mark message as unsent             │
│ Display: "This message was unsent."         │
│ Save:    Cache update                       │
└──────────────────────────────────────────────┘

┌─ onMessageLiked ───────────────────────────┐
│ Trigger: 'message_liked' event              │
│ Action:  Toggle like status                 │
│ Update:  Message 'liked' = true/false       │
│ Save:    Cache update                       │
└──────────────────────────────────────────────┘

┌─ onMessagesRead ───────────────────────────┐
│ Trigger: 'messages_read' event              │
│ Action:  Mark messages as read              │
│ Update:  Message 'is_read' = true           │
│ Clear:   Unread badge                       │
│ Save:    Cache update                       │
└──────────────────────────────────────────────┘

┌─ onConnectionChange ───────────────────────┐
│ Trigger: Socket connect/disconnect          │
│ Action:  Load messages if connected         │
│ Update:  UI state (connected/offline)       │
│ Retry:   Pending operations if reconnected  │
└──────────────────────────────────────────────┘
```

---

## Room ID Generation (Consistent Both Sides)

```
Admin (ID: 1) + User (ID: 123)

Sorted: [1, 123]
Room ID: "1_123"

Both APK and Admin use SAME logic:
final ids = [id1, id2]..sort();
return ids.join('_');

This ensures:
✅ Admin→User and User→Admin use SAME room
✅ Messages broadcast to correct subscribers
✅ Chat history is unified
```

---

## Database Schema

```
┌─────────────────────────────────────┐
│ chat_messages                       │
├─────────────────────────────────────┤
│ id (BIGINT PK)                      │
│ message_id (VARCHAR 100 UNIQUE)     │
│ chat_room_id (VARCHAR 150 FK) ──┐   │
│ sender_id (VARCHAR 50)           │   │
│ receiver_id (VARCHAR 50)         │   │
│ message (LONGTEXT)               │   │
│ message_type (VARCHAR 20)        │   │
│ is_read (BOOLEAN)                │   │
│ is_delivered (BOOLEAN)           │   │
│ is_edited (BOOLEAN)              │   │
│ is_unsent (BOOLEAN)              │   │
│ liked (BOOLEAN)                  │   │
│ replied_to (JSON)                │   │
│ reactions (JSON)                 │   │
│ created_at, updated_at           │   │
└─────────────────────────────────────┘
                                      │
      ┌───────────────────────────────┘
      │
      └──────────────────────────────────┐
                                         │
┌────────────────────────────────────────▼─┐
│ chat_rooms                                │
├───────────────────────────────────────────┤
│ id (VARCHAR 150 PK) [from above]          │
│ participants (JSON array)                 │
│ participant_names (JSON array)            │
│ participant_images (JSON array)           │
│ last_message (TEXT)                       │
│ last_message_type (VARCHAR 20)            │
│ last_message_time (DATETIME)              │
│ last_message_sender_id (VARCHAR 50)       │
│ created_at, updated_at                    │
└───────────────────────────────────────────┘

┌───────────────────────────────────────────┐
│ chat_unread_counts                        │
├───────────────────────────────────────────┤
│ chat_room_id (VARCHAR 150 FK)             │
│ user_id (VARCHAR 50)                      │
│ unread_count (INT)                        │
│ Composite PK: (chat_room_id, user_id)     │
│ created_at, updated_at                    │
└───────────────────────────────────────────┘

┌───────────────────────────────────────────┐
│ user_online_status                        │
├───────────────────────────────────────────┤
│ user_id (VARCHAR 50 PK)                   │
│ is_online (BOOLEAN)                       │
│ last_seen (DATETIME)                      │
│ active_chat_room_id (VARCHAR 150)         │
│ socket_id (VARCHAR 100)                   │
│ created_at, updated_at                    │
└───────────────────────────────────────────┘
```

---

## Configuration Files

```
📁 APK App
  └─ apk/lib/config/app_endpoints.dart
     └─ kSocketServerBaseUrl = 'http://192.168.1.25:3001'

📁 Admin Panel  
  └─ admin/lib/config/app_endpoints.dart
     └─ kAdminSocketBaseUrl = 'http://192.168.1.25:3001'

📁 Socket Server
  └─ Backend/socket-server/.env
     PORT=3001
     DB_HOST=localhost
     DB_PORT=3306
     DB_NAME=ms
     DB_USER=root
     DB_PASSWORD=
     ALLOWED_ORIGINS=*

📁 MySQL
  └─ Default: localhost:3306
     Database: ms
     User: root
     Password: (empty)
```

---

## Success Criteria

✅ **All systems working when:**
1. MySQL running (mysqld.exe process active)
2. Socket server running (listening on port 3001)
3. Apps can send messages in < 500ms
4. Admin receives messages in < 1s
5. User receives messages in < 1s
6. Messages persist in database
7. Chat rooms created automatically
8. Unread counts increment
9. No errors in socket server logs
10. No connection timeouts

---

## Next Steps

1. ✅ **Start Services** (MySQL + Socket Server)
2. ✅ **Rebuild Apps** (flutter clean && pub get)
3. ✅ **Run Apps** (flutter run)
4. ✅ **Test Messages** (send in both directions)
5. ✅ **Verify Database** (check chat_messages table)
6. ✅ **Check Logs** (look for errors in socket server)
7. ✅ **Monitor Performance** (latency, persistence, reliability)
8. ✅ **Deploy** (when ready for production)

