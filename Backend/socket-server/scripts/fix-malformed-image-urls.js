#!/usr/bin/env node
/**
 * fix-malformed-image-urls.js
 *
 * This script fixes malformed image URLs in the Firebase Firestore database.
 * It specifically targets URLs with patterns like:
 * - https://https//domain.com/...
 * - https://https://domain.com/...
 * - https//domain.com/...
 *
 * The script will:
 * 1. Scan all messages in all chat rooms
 * 2. Identify messages with malformed image URLs
 * 3. Fix the URLs using the same sanitization logic as the server
 * 4. Update the messages in the database
 *
 * Usage:
 *   node scripts/fix-malformed-image-urls.js [--dry-run]
 *
 * Options:
 *   --dry-run    Show what would be fixed without making changes
 */

const admin = require('firebase-admin');
const serviceAccount = require('../service-account-key.json');

// Initialize Firebase Admin
admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

/**
 * Sanitizes a URL by fixing common malformations
 * @param {string} url - The URL to sanitize
 * @returns {string} - The sanitized URL
 */
function sanitizeUrl(url) {
  if (typeof url !== 'string') return url;

  let sanitized = url;
  let previous;

  do {
    previous = sanitized;
    // Fix: 'https://https://...' -> 'https://...'
    sanitized = sanitized.replace(/^(https?):\/\/(https?):\/\//i, '$1://');
    // Fix: 'https://https//...' -> 'https://...' (one missing slash in second protocol)
    sanitized = sanitized.replace(/^(https?):\/\/(https)\/\//i, '$1://');
    // Fix: 'https://http//...' -> 'https://...' (one missing slash in second protocol)
    sanitized = sanitized.replace(/^(https?):\/\/(http)\/\//i, '$1://');
    // Fix: 'https//...' -> 'https://...' (missing colon between protocol and slashes)
    sanitized = sanitized.replace(/^(https?)\/\//i, '$1://');
    // Fix: 'https/...' -> 'https://...' (only one slash, no colon)
    sanitized = sanitized.replace(/^(https?)\/([^/])/i, '$1://$2');
  } while (sanitized !== previous);

  return sanitized;
}

/**
 * Check if a URL is malformed
 * @param {string} url - The URL to check
 * @returns {boolean} - True if the URL is malformed
 */
function isUrlMalformed(url) {
  if (typeof url !== 'string') return false;

  // Check for double protocols or missing colons/slashes
  const malformedPatterns = [
    /^https?:\/\/https?:\/\//i,  // https://https://...
    /^https?:\/\/https?\/\//i,    // https://https//...
    /^https?\/\//i,               // https//...
    /^https?\/[^/]/i,             // https/... (without second slash)
  ];

  return malformedPatterns.some(pattern => pattern.test(url));
}

async function fixChatRoomMessages(chatRoomId, dryRun = false) {
  const messagesRef = db.collection('chatRooms').doc(chatRoomId).collection('messages');
  const snapshot = await messagesRef.where('messageType', '==', 'image').get();

  const fixes = [];

  for (const doc of snapshot.docs) {
    const data = doc.data();
    const originalUrl = data.message;

    if (isUrlMalformed(originalUrl)) {
      const fixedUrl = sanitizeUrl(originalUrl);
      fixes.push({
        docId: doc.id,
        chatRoomId,
        originalUrl,
        fixedUrl,
      });

      if (!dryRun) {
        await doc.ref.update({ message: fixedUrl });
      }
    }
  }

  return fixes;
}

async function main() {
  const dryRun = process.argv.includes('--dry-run');

  console.log('🔍 Scanning for malformed image URLs...');
  if (dryRun) {
    console.log('🏃 DRY RUN MODE: No changes will be made\n');
  }

  try {
    // Get all chat rooms
    const chatRoomsSnapshot = await db.collection('chatRooms').get();
    console.log(`📂 Found ${chatRoomsSnapshot.size} chat rooms\n`);

    let totalFixed = 0;
    const allFixes = [];

    for (const chatRoomDoc of chatRoomsSnapshot.docs) {
      const chatRoomId = chatRoomDoc.id;
      process.stdout.write(`Checking ${chatRoomId}... `);

      const fixes = await fixChatRoomMessages(chatRoomId, dryRun);

      if (fixes.length > 0) {
        console.log(`✅ Found ${fixes.length} malformed URL(s)`);
        allFixes.push(...fixes);
        totalFixed += fixes.length;
      } else {
        console.log('✨ No issues');
      }
    }

    console.log('\n' + '='.repeat(80));
    console.log(`\n📊 Summary:`);
    console.log(`   Total malformed URLs found: ${totalFixed}`);

    if (totalFixed > 0) {
      console.log('\n📋 Details:');
      allFixes.forEach((fix, index) => {
        console.log(`\n${index + 1}. Chat Room: ${fix.chatRoomId}`);
        console.log(`   Message ID: ${fix.docId}`);
        console.log(`   Before: ${fix.originalUrl}`);
        console.log(`   After:  ${fix.fixedUrl}`);
      });

      if (dryRun) {
        console.log('\n💡 Run without --dry-run to apply these fixes');
      } else {
        console.log('\n✅ All URLs have been fixed!');
      }
    } else {
      console.log('   All URLs are correctly formatted! 🎉');
    }

  } catch (error) {
    console.error('\n❌ Error:', error.message);
    process.exit(1);
  }
}

// Run the script
main()
  .then(() => {
    console.log('\n✨ Done!');
    process.exit(0);
  })
  .catch((error) => {
    console.error('\n💥 Fatal error:', error);
    process.exit(1);
  });
