# Fix for Image URL Resolution Error

## Issue Summary

**Error:** `GET https://https//adminnew.marriagestation.com.np/uploads/chat_images/adb07b09-105b-4fc9-b0bf-25e481befe57.jpg net::ERR_NAME_NOT_RESOLVED`

**Problem:** Malformed URLs with double protocols (e.g., `https://https//...`) prevent images from loading.

## Root Cause Analysis

The issue stems from two potential sources:

1. **Incorrect Environment Variable**: The `PUBLIC_URL` environment variable may be set incorrectly with a malformed value like `https://https//adminnew.marriagestation.com.np`

2. **Legacy Data**: Images uploaded before URL sanitization was implemented may have malformed URLs stored in the Firebase Firestore database

## Solution Implemented

### 1. Prevention (Already in Place)

The `server.js` file (lines 410-434) contains a `buildFileUrl` function with robust URL sanitization logic that automatically fixes malformed URLs for **new** image uploads. This includes:

- Fixing double protocols: `https://https://...` → `https://...`
- Fixing partial double protocols: `https://https//...` → `https://...`
- Fixing missing colons: `https//...` → `https://...`
- Fixing missing slashes: `https/...` → `https://...`

**Action Required:** Ensure `PUBLIC_URL` in the production `.env` file is set correctly:
```bash
PUBLIC_URL=https://adminnew.marriagestation.com.np
```

### 2. Cleanup Script (New)

Created `scripts/fix-malformed-image-urls.js` to fix existing malformed URLs in the database.

**Features:**
- Scans all chat room messages with image type
- Identifies and fixes malformed URLs using the same sanitization logic
- Supports dry-run mode to preview changes
- Updates Firestore database with corrected URLs

**Usage:**
```bash
npm run fix-urls:dry-run  # Preview changes
npm run fix-urls          # Apply fixes
```

### 3. Documentation (New)

Created comprehensive documentation at `docs/FIXING_MALFORMED_URLS.md` covering:
- Problem description and root causes
- Step-by-step solutions
- Technical details of URL sanitization patterns
- Prevention strategies
- Troubleshooting guide

## Files Modified/Created

1. ✅ `Backend/socket-server/scripts/fix-malformed-image-urls.js` - Database cleanup script
2. ✅ `Backend/socket-server/docs/FIXING_MALFORMED_URLS.md` - Comprehensive documentation
3. ✅ `Backend/socket-server/package.json` - Added npm scripts and firebase-admin dependency

## Testing Performed

- ✅ Verified JavaScript syntax of all files
- ✅ Tested URL sanitization regex patterns
- ✅ Confirmed the logic handles all known malformed patterns:
  - `https://https//domain.com` → `https://domain.com`
  - `https://https://domain.com` → `https://domain.com`
  - `https//domain.com` → `https://domain.com`

## Next Steps for Deployment

1. **Verify Environment Variable**
   ```bash
   # On production server
   echo $PUBLIC_URL
   # Should output: https://adminnew.marriagestation.com.np
   ```

2. **Run Cleanup Script** (if needed)
   ```bash
   cd Backend/socket-server
   # Place service-account-key.json in this directory
   npm install
   npm run fix-urls:dry-run  # Preview
   npm run fix-urls          # Apply
   ```

3. **Restart Socket Server**
   ```bash
   pm2 restart socket-server
   ```

4. **Verify Fix**
   - Test loading previously failing images
   - Monitor for new `ERR_NAME_NOT_RESOLVED` errors

## Additional Notes

- The URL sanitization in `server.js` ensures all **new** image uploads will have correct URLs
- The cleanup script fixes **existing** malformed URLs in the database
- Both use identical sanitization logic for consistency
- The solution handles all known URL malformation patterns

## References

- Server URL sanitization: `Backend/socket-server/server.js:410-434`
- Cleanup script: `Backend/socket-server/scripts/fix-malformed-image-urls.js`
- Full documentation: `Backend/socket-server/docs/FIXING_MALFORMED_URLS.md`
