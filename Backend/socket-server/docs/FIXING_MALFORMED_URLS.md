# Fixing Malformed Image URLs

## Problem

Chat images may fail to load with the error:
```
GET https://https//adminnew.marriagestation.com.np/uploads/chat_images/<filename>.jpg
net::ERR_NAME_NOT_RESOLVED
```

Notice the malformed URL: `https://https//` (double protocol).

## Root Cause

This issue can occur due to:

1. **Incorrect PUBLIC_URL environment variable** - If `PUBLIC_URL` in `.env` is set to a malformed value like `https://https//adminnew.marriagestation.com.np`
2. **Legacy data** - Images uploaded before URL sanitization was implemented may have malformed URLs stored in the database

## Solution

### 1. Fix the Environment Variable (Prevention)

Ensure `PUBLIC_URL` in your `.env` file is set correctly:

```bash
# ✅ CORRECT
PUBLIC_URL=https://adminnew.marriagestation.com.np

# ❌ WRONG
PUBLIC_URL=https://https//adminnew.marriagestation.com.np
PUBLIC_URL=https://https://adminnew.marriagestation.com.np
```

The server already includes URL sanitization logic in the `buildFileUrl` function (lines 413-434 of `server.js`), which will automatically fix malformed URLs for NEW uploads.

### 2. Fix Existing Malformed URLs in Database (Cleanup)

If you have existing images with malformed URLs in your Firebase Firestore database, run the cleanup script:

```bash
# First, do a dry run to see what would be fixed
npm run fix-urls:dry-run

# Then apply the fixes
npm run fix-urls
```

Alternatively, you can run the script directly:

```bash
node scripts/fix-malformed-image-urls.js --dry-run  # dry run
node scripts/fix-malformed-image-urls.js            # apply fixes
```

**Prerequisites:**
- Place your Firebase service account key at `service-account-key.json` in the socket-server directory
- Install dependencies: `npm install` (this will install firebase-admin as an optional dependency)

The script will:
1. Scan all chat messages in all chat rooms
2. Identify messages with image type that have malformed URLs
3. Fix the URLs using the same sanitization logic as the server
4. Update the Firestore database with corrected URLs

### 3. Verify the Fix

After running the script:

1. Check the output for the number of URLs fixed
2. Test loading the previously failing images in your app
3. Monitor for any new `ERR_NAME_NOT_RESOLVED` errors

## Technical Details

### URL Sanitization Patterns

The following malformed patterns are automatically detected and fixed:

| Malformed Pattern | Fixed Pattern | Example |
|-------------------|---------------|---------|
| `https://https://...` | `https://...` | `https://https://domain.com` → `https://domain.com` |
| `https://https//...` | `https://...` | `https://https//domain.com` → `https://domain.com` |
| `https://http//...` | `https://...` | `https://http//domain.com` → `https://domain.com` |
| `https//...` | `https://...` | `https//domain.com` → `https://domain.com` |
| `https/...` | `https://...` | `https/domain.com` → `https://domain.com` |

### Implementation

The sanitization logic is implemented in two places:

1. **Server (`server.js`)** - Automatically sanitizes URLs when generating new image URLs in the `buildFileUrl` function
2. **Cleanup Script (`scripts/fix-malformed-image-urls.js`)** - Fixes existing malformed URLs in the database

Both use the same sanitization algorithm to ensure consistency.

## Prevention

To prevent this issue in the future:

1. ✅ Always set `PUBLIC_URL` correctly in your `.env` file
2. ✅ Verify the environment variable before deploying: `echo $PUBLIC_URL`
3. ✅ Keep the URL sanitization logic in `buildFileUrl` intact
4. ✅ Test image uploads after environment changes

## Support

If you continue experiencing issues after following these steps:

1. Check the Socket.IO server logs for warnings about `PUBLIC_URL`
2. Verify the `.env` file is being loaded correctly
3. Ensure nginx is forwarding `X-Forwarded-Proto` and `Host` headers correctly
4. Run the cleanup script again to catch any newly affected images
