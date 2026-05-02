# Quick Test Script for Chat System

## Prerequisites Check
```bash
# 1. Verify MySQL is Running
tasklist | findstr mysqld
# Expected: mysqld.exe running

# 2. Verify Socket Server is Running  
netstat -ano | findstr :3001
# Expected: LISTENING

# 3. Verify Node.js is Available
node --version
npm --version
```

## Database Verification
```bash
# Connect to MySQL and check all tables exist
C:\xampp\mysql\bin\mysql.exe -u root ms -e "
SHOW TABLES;
SELECT COUNT(*) as total_messages FROM chat_messages;
SELECT COUNT(*) as total_rooms FROM chat_rooms;
SELECT COUNT(*) as total_unread FROM chat_unread_counts;
SELECT COUNT(*) as online_users FROM user_online_status;
"
```

## Socket Server Health Check
```bash
# 1. Check if server is listening
netstat -ano | findstr :3001
# Should show: Proto=TCP, State=LISTENING, Port=3001

# 2. Check Node process
tasklist | findstr node.exe
# Should show: node.exe with PID

# 3. Check if port is accessible locally
# From Windows PowerShell:
Test-NetConnection -ComputerName localhost -Port 3001 -InformationLevel Quiet
# Expected: True (or port is open message)
```

## App Configuration Verification
```bash
# 1. Check APK Socket URL
grep -r "192.168.1.25:3001" c:/xampp/htdocs/uttamms/apk/lib/

# 2. Check Admin Socket URL  
grep -r "192.168.1.25:3001" c:/xampp/htdocs/uttamms/admin/lib/

# Both should return matches in app_endpoints.dart files
```

## Full System Test
```bash
# Terminal 1: Ensure MySQL is running
C:\xampp\mysql\bin\mysqld.exe --port=3306

# Terminal 2: Ensure Socket Server is running
cd C:\xampp\htdocs\uttamms\Backend\socket-server
npm start

# Terminal 3: Monitor database
C:\xampp\mysql\bin\mysql.exe -u root ms -e "
WATCH SELECT * FROM chat_messages ORDER BY created_at DESC LIMIT 1;
"

# Terminal 4: Test from APK app
cd C:\xampp\htdocs\uttamms\apk
flutter run

# Terminal 5: Test from Admin panel
cd C:\xampp\htdocs\uttamms\admin
flutter run

# Then:
# 1. Log in with user account on APK
# 2. Log in with admin account on Admin panel
# 3. Send message from APK to Admin
# 4. Expected: Message appears in Admin panel within 1 second
# 5. Send message from Admin to APK user  
# 6. Expected: Message appears in APK within 1 second
# 7. Check database for both messages

```

## Common Issues & Fixes

### Socket Server Won't Start
```bash
# Check for errors
cd C:\xampp\htdocs\uttamms\Backend\socket-server
npm start 2>&1
# Common errors:
# - "EADDRINUSE: address already in use" → Change port or kill process
# - "Cannot find module" → Run: npm install
# - "MySQL connection failed" → Ensure mysqld.exe is running
```

### Messages Not Sending
```bash
# 1. Check socket connection in app logs
# 2. Verify firewall allows localhost:3001
# 3. Check if socket service is connected:
#    - In Flutter app, print: _socketService.isConnected

# 4. Test socket manually:
#    npm install -g socket.io-client
#    # Then create test client
```

### Database Issues
```bash
# Check table structure
C:\xampp\mysql\bin\mysql.exe -u root ms -e "DESC chat_messages;"

# Check for stuck processes
C:\xampp\mysql\bin\mysql.exe -u root ms -e "SHOW PROCESSLIST;"

# Clear old test data
C:\xampp\mysql\bin\mysql.exe -u root ms -e "DELETE FROM chat_messages WHERE created_at < NOW() - INTERVAL 1 HOUR;"
```

## Success Indicators

✅ **All Working When:**
- [ ] MySQL service running
- [ ] Socket server listening on 3001
- [ ] Apps can reach socket server
- [ ] Messages send and receive within 1 second
- [ ] Messages appear in database immediately
- [ ] Chat rooms created in chat_rooms table
- [ ] Unread counts increment properly
- [ ] Admin panel shows user messages in real-time
- [ ] APK shows admin messages in real-time

❌ **Issues Likely If:**
- [ ] Messages delay > 2 seconds
- [ ] Messages don't appear in database
- [ ] Socket server errors in console
- [ ] MySQL connection fails
- [ ] Messages only work one direction
- [ ] App crashes on message send

