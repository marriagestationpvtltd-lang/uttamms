-- ============================================================
-- Fix Corrupted Chat Messages
-- Run this script to repair data that prevents messages from
-- loading in the chat screens.
--
-- SAFE TO RUN: All fixes are non-destructive rewrites.
-- ============================================================

-- Step 1: Null out any replied_to fields with invalid JSON.
-- This allows the affected messages to load again; the reply
-- reference is lost but the message itself becomes visible.
UPDATE chat_messages
SET replied_to = NULL
WHERE replied_to IS NOT NULL
  AND JSON_VALID(replied_to) = 0;

-- Step 2: Fix call messages that have NULL, empty, or invalid JSON.
-- Replaces the broken payload with a safe fallback so the UI
-- can render the message without throwing a JSON parse error.
UPDATE chat_messages
SET message = JSON_OBJECT(
    'callType',     'audio',
    'callStatus',   'unknown',
    'callDuration', 0,
    'label',        'Call'
)
WHERE message_type = 'call'
  AND (message IS NULL OR message = '' OR JSON_VALID(message) = 0);

-- Step 3: Fix profile_card messages with NULL, empty, or invalid JSON.
UPDATE chat_messages
SET message = '{}'
WHERE message_type = 'profile_card'
  AND (message IS NULL OR message = '' OR JSON_VALID(message) = 0);

-- Step 4: Fix image_gallery messages that are not a valid JSON array.
UPDATE chat_messages
SET message = '[]'
WHERE message_type = 'image_gallery'
  AND (message IS NULL OR message = '' OR JSON_VALID(message) = 0);

-- Verification: check for any remaining rows with invalid JSON
SELECT
    message_type,
    COUNT(*) AS remaining_invalid
FROM chat_messages
WHERE message_type IN ('call', 'profile_card', 'image_gallery')
  AND (message IS NULL OR message = '' OR JSON_VALID(message) = 0)
GROUP BY message_type;

-- Should return 0 rows for each type.
