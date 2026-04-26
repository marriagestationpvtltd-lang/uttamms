#!/usr/bin/env bash
# =============================================================================
# Marriage Station – Safe Server Restore Script
# Restore Point: 2026-04-26 9:00 PM NST (commit 1cb74f80)
# =============================================================================
# Run this on the LIVE server (as root or deploy user) after pulling the
# restored code from git. It performs Steps 4–7 of the restore plan:
#   - Upload directory creation & permissions
#   - Database schema migrations (idempotent – safe to re-run)
#   - Environment validation
#   - PM2 socket-server restart
#
# Usage:
#   chmod +x scripts/server-restore.sh
#   sudo ./scripts/server-restore.sh
# =============================================================================

set -e
BOLD='\033[1m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

ok()   { echo -e "${GREEN}  ✅  $*${NC}"; }
warn() { echo -e "${YELLOW}  ⚠️   $*${NC}"; }
fail() { echo -e "${RED}  ❌  $*${NC}"; exit 1; }
step() { echo -e "\n${BOLD}── $* ─────────────────────────────────────────────${NC}"; }

# ---------------------------------------------------------------------------
# 0. Configuration (edit to match your server)
# ---------------------------------------------------------------------------
BACKEND_DIR="${BACKEND_DIR:-/var/www/html/Backend}"
SOCKET_DIR="${SOCKET_DIR:-$BACKEND_DIR/socket-server}"
UPLOAD_DIR_PHP="${UPLOAD_DIR_PHP:-$BACKEND_DIR/uploads}"
UPLOADS_ROOT="${UPLOADS_ROOT:-/var/www/html/uploads}"
WEB_USER="${WEB_USER:-www-data}"
DB_HOST="${DB_HOST:-localhost}"
DB_USER="${DB_USER:-ms}"
DB_PASS="${DB_PASS:-ms}"
DB_NAME="${DB_NAME:-ms}"
PM2_APP="${PM2_APP:-socket-server}"

# ---------------------------------------------------------------------------
step "Step 4: Upload Directories"
# ---------------------------------------------------------------------------
for dir in \
  "$SOCKET_DIR/uploads/chat_images" \
  "$SOCKET_DIR/uploads/voice_messages" \
  "$SOCKET_DIR/logs" \
  "$UPLOAD_DIR_PHP/ringtones" \
  "$UPLOADS_ROOT/ringtones"; do
  if [ ! -d "$dir" ]; then
    mkdir -p "$dir"
    ok "Created: $dir"
  else
    ok "Exists:  $dir"
  fi
done

if id "$WEB_USER" &>/dev/null; then
  chown -R "$WEB_USER":"$WEB_USER" "$UPLOADS_ROOT" "$UPLOAD_DIR_PHP" "$SOCKET_DIR/uploads" 2>/dev/null || true
  ok "Ownership set to $WEB_USER"
fi
chmod -R 755 "$UPLOADS_ROOT" "$UPLOAD_DIR_PHP" "$SOCKET_DIR/uploads" 2>/dev/null || true
ok "Permissions set (755)"

# ---------------------------------------------------------------------------
step "Step 5: Environment Validation"
# ---------------------------------------------------------------------------
ENV_FILE="$SOCKET_DIR/.env"
if [ ! -f "$ENV_FILE" ]; then
  warn ".env not found at $ENV_FILE"
  warn "Copy $SOCKET_DIR/.env.example to $ENV_FILE and fill in your values, then re-run."
  warn "Required vars: DB_HOST DB_USER DB_PASSWORD DB_NAME PORT UPLOAD_DIR ALLOWED_ORIGINS PUBLIC_URL"
else
  ok ".env found"
  for var in DB_HOST DB_USER DB_PASSWORD DB_NAME PORT UPLOAD_DIR ALLOWED_ORIGINS; do
    if grep -q "^${var}=" "$ENV_FILE"; then
      ok "  $var is set"
    else
      warn "  $var is MISSING in .env"
    fi
  done
  # Warn if ALLOWED_ORIGINS is a wildcard in what looks like production
  if grep -q "^ALLOWED_ORIGINS=\*" "$ENV_FILE"; then
    warn "ALLOWED_ORIGINS=* — restrict to your domain in production!"
  fi
fi

# ---------------------------------------------------------------------------
step "Step 6: Database Schema Migrations"
# ---------------------------------------------------------------------------
MYSQL_CMD="mysql -h$DB_HOST -u$DB_USER -p$DB_PASS $DB_NAME"

# Test connection
if ! $MYSQL_CMD -e "SELECT 1" &>/dev/null; then
  fail "Cannot connect to MySQL ($DB_USER@$DB_HOST/$DB_NAME). Check credentials."
fi
ok "MySQL connection OK"

# Show existing chat tables
echo "  Current tables (chat-related):"
$MYSQL_CMD -e "SHOW TABLES LIKE '%chat%';" 2>/dev/null | sed 's/^/    /'
$MYSQL_CMD -e "SHOW TABLES LIKE 'users';" 2>/dev/null | sed 's/^/    /'
$MYSQL_CMD -e "SHOW TABLES LIKE 'user_online_status';" 2>/dev/null | sed 's/^/    /'

# Apply main schema (CREATE TABLE IF NOT EXISTS — safe to re-run)
SCHEMA_SQL="$(dirname "$0")/../database/schema.sql"
if [ -f "$SCHEMA_SQL" ]; then
  $MYSQL_CMD < "$SCHEMA_SQL"
  ok "Applied database/schema.sql"
else
  warn "database/schema.sql not found — skipping"
fi

# Apply incremental migrations (all idempotent)
for migration_file in \
  "database/migrate_chat_messages_is_unsent.sql" \
  "database/migrate_admins_username.sql" \
  "database/migrate_user_activities.sql" \
  "database/migration_per_doc_status.sql"; do
  f="$(dirname "$0")/../$migration_file"
  if [ -f "$f" ]; then
    $MYSQL_CMD < "$f"
    ok "Applied $migration_file"
  else
    warn "$migration_file not found — skipping"
  fi
done

# Verify chat tables exist and have rows (won't fail if empty — just informational)
echo "  Row counts in chat tables:"
for tbl in users chat_rooms chat_messages chat_unread_counts user_online_status; do
  count=$($MYSQL_CMD -sN -e "SELECT COUNT(*) FROM \`$tbl\`;" 2>/dev/null || echo "TABLE MISSING")
  printf "    %-30s %s\n" "$tbl" "$count"
done

# Run diagnostic to detect corrupt JSON in replied_to field
DIAG_SQL="$(dirname "$0")/../Backend/socket-server/sql/diagnose_chat_issues.sql"
if [ -f "$DIAG_SQL" ]; then
  ok "Running chat diagnostics..."
  $MYSQL_CMD < "$DIAG_SQL" 2>/dev/null | head -20
fi

# ---------------------------------------------------------------------------
step "Step 7: PM2 Socket Server Restart"
# ---------------------------------------------------------------------------
if command -v pm2 &>/dev/null; then
  cd "$SOCKET_DIR"
  if pm2 list | grep -q "$PM2_APP"; then
    pm2 restart "$PM2_APP"
    ok "PM2: restarted $PM2_APP"
    sleep 2
    pm2 status "$PM2_APP"
  else
    warn "PM2 app '$PM2_APP' not found. Starting fresh..."
    pm2 start ecosystem.config.js --env production
    ok "PM2: started $PM2_APP"
    pm2 save
  fi
else
  warn "PM2 not installed. Start the socket server manually:"
  warn "  cd $SOCKET_DIR && node server.js"
fi

# ---------------------------------------------------------------------------
step "Step 8: Nginx Config Check"
# ---------------------------------------------------------------------------
if command -v nginx &>/dev/null; then
  if nginx -t 2>&1 | grep -q "successful"; then
    ok "Nginx config is valid"
  else
    warn "Nginx config has errors — check /etc/nginx/sites-enabled/"
    nginx -t
  fi
else
  warn "Nginx not found — skip nginx check"
fi

# ---------------------------------------------------------------------------
echo -e "\n${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
echo -e "${BOLD}${GREEN}  RESTORE COMPLETE — Final Testing Checklist${NC}"
echo -e "${BOLD}${GREEN}═══════════════════════════════════════════════════${NC}"
cat <<'EOF'

  Manual verification steps (run in browser / Postman):

  ✅ 1. User login
        POST /Backend/Api2/login.php
        Expect: { "success": true, "token": "..." }

  ✅ 2. Chat send/receive
        Connect two user sockets, emit "send_message"
        Expect: "new_message" event received by other user

  ✅ 3. Media upload
        POST /upload  (multipart, field: "file")
        Expect: { "url": "https://yourdomain.com/uploads/chat_images/..." }

  ✅ 4. Real-time status events
        Expect: "user_online", "message_delivered", "message_read"

  ✅ 5. Admin panel
        Open https://adminnew.marriagestation.com.np
        Expect: Dashboard loads, chat list visible

  ✅ 6. PM2 logs (no errors)
        pm2 logs socket-server --lines 50

  ⚠️  If any test fails, roll back with:
        git checkout backup/pre-restore-<timestamp>

EOF
