# Restore Log — 2026-04-26 9:00 PM NST

## Summary

Controlled restore of the Marriage Station project to the state of
**2026-04-26 at 9:00 PM NST** (commit `1cb74f80`).

This was executed as part of the Safe & Controlled Restore Plan.
All changes are minimal and surgical — only files that had drifted from
the target state were touched.

---

## Restore Point

| Field | Value |
|-------|-------|
| Target Commit | `1cb74f80d489e2033fba589633222fcd2992a619` |
| Commit Message | `Fix image file not found: add trust proxy + PUBLIC_URL support for correct HTTPS URLs` |
| Commit Date | 2026-04-26 20:18 NST (14:33 UTC) |
| Pre-restore HEAD | `32fdbd25d6c57be74e2ca2fdb597d76b1d716c26` |
| Backup Tag | `backup/pre-restore-20260426-183023` |

---

## Files Restored (14 files)

These files were reverted from a pair of earlier restore-PRs (#157, #158)
back to the correct 9 PM NST state:

| File | Change |
|------|--------|
| `Backend/get.php` | Restored match/profile endpoint |
| `Backend/socket-server/.env.example` | Restored full .env template with PUBLIC_URL, Redis, CALLS_ENABLED docs |
| `Backend/socket-server/server.js` | Restored trust-proxy + PUBLIC_URL image URL fix |
| `admin/lib/adminchat/chat_theme.dart` | Restored premium purple UI theme |
| `admin/lib/adminchat/chathome.dart` | Restored admin chat home with move-to-top, payment badge |
| `admin/lib/adminchat/left.dart` | Restored admin message read indicator fix |
| `admin/lib/adminchat/right.dart` | Restored admin message right-side bubbles |
| `admin/lib/adminchat/services/admin_socket_service.dart` | Restored socket service with unread-count & multi-image support |
| `apk/lib/Chat/ChatdetailsScreen.dart` | Restored user chat details with is_unsent handling |
| `apk/lib/Chat/ChatlistScreen.dart` | Restored user chat list |
| `apk/lib/Chat/adminchat.dart` | Restored admin-side user chat screen |
| `apk/lib/service/socket_service.dart` | Restored socket service with real-time unsent events |
| `database/migrate_chat_messages_is_unsent.sql` | Restored idempotent `is_unsent` column migration |
| `database/schema.sql` | Restored full schema including `is_unsent` in chat_messages |

---

## Files NOT Touched (preserved as-is)

- `.env` files (not in git — server-side only)
- `uploads/` directories (user data — never overwritten by git)
- `Backend/uploads/` (ringtones — user data)
- `Backend/socket-server/uploads/` (chat images, voice messages — user data)
- `Backend/db_connect.php` (live DB credentials)
- `Backend/Api2/db_config.php` (live DB credentials)

---

## New Files Added

| File | Purpose |
|------|---------|
| `scripts/server-restore.sh` | Server-side restore script (run on live server after git pull) |
| `Backend/socket-server/logs/.gitkeep` | Ensures PM2 log directory exists |

---

## Server-Side Steps Required

After pulling this branch on the live server, run:

```bash
chmod +x scripts/server-restore.sh
sudo ./scripts/server-restore.sh
```

This script will:

1. **Create upload directories** (chat_images, voice_messages, ringtones, logs)
2. **Fix ownership & permissions** (www-data, chmod 755)
3. **Validate .env** — checks required env vars are present
4. **Apply DB migrations** — idempotent, safe to re-run:
   - `database/schema.sql` (CREATE TABLE IF NOT EXISTS)
   - `database/migrate_chat_messages_is_unsent.sql`
   - `database/migrate_admins_username.sql`
   - `database/migrate_user_activities.sql`
   - `database/migration_per_doc_status.sql`
5. **Verify chat table row counts**
6. **Run chat diagnostics** (`diagnose_chat_issues.sql`)
7. **Restart PM2 socket server** (`pm2 restart socket-server`)
8. **Check Nginx config** (`nginx -t`)

---

## Environment Validation Checklist

Verify these manually on the live server after restore:

### `Backend/socket-server/.env`
```
DB_HOST=localhost
DB_PORT=3306
DB_USER=<your_db_user>
DB_PASSWORD=<your_db_password>
DB_NAME=ms
PORT=3001
UPLOAD_DIR=./uploads
PUBLIC_URL=https://adminnew.marriagestation.com.np
ALLOWED_ORIGINS=https://digitallami.com,https://adminnew.marriagestation.com.np,...
CALLS_ENABLED=true
REDIS_ENABLED=true
REDIS_HOST=127.0.0.1
REDIS_PORT=6379
```

### `Backend/db_connect.php`
```php
$host = "localhost";
$user = "ms";   // or your actual user
$pass = "ms";   // or your actual password
$dbname = "ms";
```

### `Backend/Api2/db_config.php`
```php
define('DB_HOST', '127.0.0.1');
define('DB_NAME', 'ms');
define('DB_USER', 'ms');
define('DB_PASS', 'ms');  // or your actual password
```

---

## Final Testing Checklist

| # | Test | Expected |
|---|------|----------|
| 1 | User login (`POST /Backend/Api2/login.php`) | `{"success":true, "token":"..."}` |
| 2 | Chat send/receive (Socket.IO `send_message`) | `new_message` event received |
| 3 | Image upload (`POST /upload`) | `{"url":"https://..."}` with correct HTTPS URL |
| 4 | Voice message upload (`POST /upload`) | Same as above |
| 5 | Real-time status (`user_online`, `message_delivered`) | Events fire correctly |
| 6 | Admin panel loads | Dashboard + chat list visible |
| 7 | PM2 logs | `pm2 logs socket-server --lines 50` — no errors |
| 8 | Nginx | `nginx -t` → "syntax is ok, test is successful" |

---

## Rollback

If anything breaks after restore, roll back with:

```bash
git checkout backup/pre-restore-20260426-183023
```

The tag `backup/pre-restore-20260426-183023` points to the state immediately
before this restore was applied.

---

## Risks & Warnings

| Risk | Status |
|------|--------|
| DB schema migration drops tables | ✅ SAFE — all use `CREATE TABLE IF NOT EXISTS` |
| Upload files overwritten | ✅ SAFE — `uploads/` is gitignored, never touched |
| `.env` overwritten | ✅ SAFE — `.env` is gitignored, never touched |
| Socket server downtime during restart | ⚠️  Brief (~2s). PM2 auto-restarts on crash |
| Redis not running | ⚠️  Set `REDIS_ENABLED=false` in `.env` if Redis unavailable |
