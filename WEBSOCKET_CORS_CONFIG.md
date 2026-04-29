# WebSocket and CORS Configuration Guide

## Overview
This document explains the WebSocket and CORS configuration for the Marriage Station application.

## WebSocket Configuration

### Socket Server
- **Port**: 3000 (configurable via `PORT` environment variable)
- **Location**: `/home/runner/work/uttamms/uttamms/Backend/socket-server/`
- **Technology**: Node.js with Socket.IO
- **CORS**: Enabled for all origins (configurable via `ALLOWED_ORIGINS`)

### Connection URLs

#### Production Configuration
The application uses secure WebSocket connections (wss://) through HTTPS:

**Mobile App (APK):**
- Base URL: `https://adminnew.marriagestation.com.np` (from `apk/lib/config/app_endpoints.dart`)
- Socket.IO will automatically use: `wss://adminnew.marriagestation.com.np/socket.io/`

**Admin Panel:**
- Base URL: `https://adminnew.marriagestation.com.np` (from `admin/lib/config/app_endpoints.dart`)
- Socket.IO will automatically use: `wss://adminnew.marriagestation.com.np/socket.io/`

#### How Socket.IO Works
Socket.IO automatically handles the protocol:
- When you connect to `https://domain.com`, it uses `wss://domain.com/socket.io/`
- The Socket.IO client library handles the WebSocket upgrade automatically
- No need to manually specify `ws://` or `wss://` protocol

### Nginx Proxy Configuration

The Nginx configuration (`Backend/socket-server/nginx.conf`) provides two WebSocket endpoints:

1. **Standard Socket.IO endpoint** (`/socket.io/`):
   ```nginx
   location /socket.io/ {
       proxy_pass http://socketio_nodes;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_buffering off;
   }
   ```

2. **Alternative WebSocket endpoint** (`/socket/`):
   ```nginx
   location /socket/ {
       proxy_pass http://127.0.0.1:3000;
       proxy_http_version 1.1;
       proxy_set_header Upgrade $http_upgrade;
       proxy_set_header Connection "Upgrade";
       proxy_buffering off;
   }
   ```

### Upstream Pool
The server can run multiple instances (PM2 cluster mode):
```nginx
upstream socketio_nodes {
    server 127.0.0.1:3000;
    server 127.0.0.1:3001;
    server 127.0.0.1:3002;
    server 127.0.0.1:3003;
    keepalive 64;
}
```

## CORS Configuration

### PHP API Files (Backend/Api2/)

All PHP API endpoints now include CORS headers:

```php
header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: *');
header('Access-Control-Allow-Methods: GET, POST, OPTIONS');

// Handle preflight OPTIONS request
if ($_SERVER['REQUEST_METHOD'] == 'OPTIONS') {
    http_response_code(200);
    exit();
}
```

Files updated:
- `signin.php`
- `signup.php`
- `myprofile.php`
- Many others already had CORS headers

### Apache .htaccess (Backend/Api2/)

The `.htaccess` file provides server-level CORS configuration:

```apache
<IfModule mod_headers.c>
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Headers "*"
    Header set Access-Control-Allow-Methods "GET, POST, OPTIONS"

    RewriteEngine On
    RewriteCond %{REQUEST_METHOD} OPTIONS
    RewriteRule ^(.*)$ $1 [R=200,L]
</IfModule>
```

### Static Files (Images, etc.)

The `Backend/Api2/uploads/.htaccess` file already includes CORS headers for static files:

```apache
<FilesMatch "\.(jpg|jpeg|png|gif|webp|svg|ico|mp3|ogg|wav|mp4|pdf)$">
    Header set Access-Control-Allow-Origin "*"
    Header set Access-Control-Allow-Methods "GET, OPTIONS"
    Header set Access-Control-Allow-Headers "Origin, Accept, Content-Type"
</FilesMatch>
```

## Image URL Configuration

### Server-Side (Node.js Socket Server)

The socket server uses `PUBLIC_URL` environment variable to generate full image URLs:

```javascript
const PUBLIC_URL = process.env.PUBLIC_URL || '';
```

**Recommended .env configuration:**
```env
PUBLIC_URL=https://adminnew.marriagestation.com.np
```

This ensures uploaded images return full URLs like:
```
https://adminnew.marriagestation.com.np/uploads/chat_images/filename.jpg
```

### Client-Side (Flutter)

The Flutter apps already handle image loading with error fallbacks:

```dart
Image.network(
  imageUrl,
  errorBuilder: (context, error, stackTrace) {
    return Icon(Icons.person);
  },
)
```

## Deployment Checklist

### 1. Socket Server
- [ ] Set `PORT=3000` in `.env` (or rely on default)
- [ ] Set `PUBLIC_URL=https://adminnew.marriagestation.com.np` in `.env`
- [ ] Set `ALLOWED_ORIGINS=*` in `.env` (or specific domains)
- [ ] Restart the Node.js server: `pm2 restart socket-server`

### 2. Nginx
- [ ] Copy `Backend/socket-server/nginx.conf` to `/etc/nginx/sites-available/`
- [ ] Update `server_name` to your domain (digitallami.com)
- [ ] Update SSL certificate paths
- [ ] Enable the site: `ln -sf /etc/nginx/sites-available/socket-server /etc/nginx/sites-enabled/`
- [ ] Test configuration: `nginx -t`
- [ ] Reload Nginx: `systemctl reload nginx`

### 3. PHP Backend
- [ ] Verify Apache has `mod_headers` enabled: `a2enmod headers`
- [ ] Verify `.htaccess` files are in place:
  - `Backend/Api2/.htaccess`
  - `Backend/Api2/uploads/.htaccess`
- [ ] Restart Apache: `systemctl restart apache2`

### 4. Testing

**Test WebSocket Connection:**
```bash
# From browser console or using wscat
wscat -c wss://adminnew.marriagestation.com.np/socket.io/?transport=websocket
```

**Test Image Loading:**
```bash
# Should return image without CORS error
curl -I https://digitallami.com/Api2/uploads/default.png
# Look for: Access-Control-Allow-Origin: *
```

**Test API Endpoint:**
```bash
# Preflight request
curl -X OPTIONS https://digitallami.com/Api2/signin.php \
  -H "Origin: https://example.com" \
  -H "Access-Control-Request-Method: POST" \
  -i

# Should return 200 with CORS headers
```

## Troubleshooting

### WebSocket Connection Fails

**Error:** "WebSocket is closed before the connection is established"

**Solutions:**
1. Verify Node.js server is running: `pm2 status`
2. Check server logs: `pm2 logs socket-server`
3. Verify Nginx is proxying correctly: `tail -f /var/log/nginx/error.log`
4. Test direct connection to Node: `curl http://localhost:3000`
5. Verify SSL certificates are valid: `curl https://adminnew.marriagestation.com.np`

### CORS Errors

**Error:** "No 'Access-Control-Allow-Origin' header present"

**Solutions:**
1. Verify Apache `mod_headers` is enabled
2. Check `.htaccess` files are being read (test with `AllowOverride All`)
3. Clear browser cache
4. Check PHP files have CORS headers at the top (before any output)
5. Verify preflight OPTIONS requests return 200

### Images Not Loading

**Error:** Images return 404 or CORS error

**Solutions:**
1. Check image path is correct (full URL, not relative)
2. Verify `uploads/.htaccess` has CORS headers
3. Check file permissions on uploads directory
4. Set `PUBLIC_URL` in socket server `.env`
5. Verify API returns full URLs like `https://domain.com/Api2/uploads/...`

## Configuration Files Modified

1. `Backend/socket-server/server.js` - Port changed to 3000
2. `Backend/socket-server/nginx.conf` - Added /socket/ endpoint, updated ports
3. `Backend/Api2/.htaccess` - Created with CORS headers
4. `Backend/Api2/cors_headers.php` - Helper file for CORS
5. `Backend/Api2/signin.php` - Added CORS headers
6. `Backend/Api2/signup.php` - Added CORS headers
7. `Backend/Api2/myprofile.php` - Added CORS headers

## No Changes Needed

The following files are already correctly configured:
- `apk/lib/config/app_endpoints.dart` - Uses HTTPS URL
- `admin/lib/config/app_endpoints.dart` - Uses HTTPS URL
- `apk/lib/service/socket_service.dart` - Socket.IO client configured correctly
- `admin/lib/adminchat/services/admin_socket_service.dart` - Socket.IO client configured correctly
- `Backend/Api2/uploads/.htaccess` - Already has CORS headers for static files

## Important Notes

1. **No hardcoded ws:// URLs**: The application uses Socket.IO client library which automatically handles the protocol (wss:// for HTTPS sites)

2. **Environment Variables**: Use `.env` file for configuration, don't hardcode values

3. **Security**: In production, restrict `ALLOWED_ORIGINS` to specific domains instead of `*`

4. **PM2 Cluster**: The nginx configuration supports multiple Node.js instances for load balancing

5. **Image URLs**: Always return full URLs from APIs, not relative paths

## Success Criteria

✅ WebSocket connects successfully
✅ No "connection closed" errors
✅ Images load in APK without CORS errors
✅ API requests work from web and mobile
✅ Real-time chat functions properly
✅ Admin panel syncs with mobile app in real-time
