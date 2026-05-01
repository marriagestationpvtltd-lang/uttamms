-- ============================================================================
-- Migration: Normalize chat_rooms.participants to string-type JSON arrays
-- ============================================================================
-- Problem: Some chat rooms were created with numeric participant IDs
--   (e.g. [123, 456]) instead of string IDs (e.g. ["123", "456"]).
--   MySQL's JSON_CONTAINS with JSON_QUOTE() only matches string values,
--   so those rooms were invisible in getChatRooms() queries.
--
-- Fix: Convert any numeric values in the participants array to strings.
--   Safe to run multiple times (idempotent via WHERE clause).
-- ============================================================================

-- Step 1: Preview affected rows (run this first to see how many rows to fix)
SELECT id, participants
FROM chat_rooms
WHERE JSON_TYPE(JSON_EXTRACT(participants, '$[0]')) = 'INTEGER';

-- Step 2: Fix them — convert [123, 456] → ["123", "456"]
-- This uses JSON_TABLE to extract each element and re-builds the array as strings.
-- Only rows where the first element is an INTEGER are updated.
UPDATE chat_rooms cr
JOIN (
    SELECT
        base.id,
        JSON_ARRAYAGG(CAST(jt.pid AS CHAR)) AS new_participants
    FROM chat_rooms base
    JOIN JSON_TABLE(
        base.participants,
        '$[*]' COLUMNS (pid BIGINT PATH '$')
    ) AS jt ON TRUE
    WHERE JSON_TYPE(JSON_EXTRACT(base.participants, '$[0]')) = 'INTEGER'
    GROUP BY base.id
) sub ON cr.id = sub.id
SET cr.participants = sub.new_participants;

-- Step 3: Verify no numeric arrays remain
SELECT COUNT(*) AS remaining_numeric_arrays
FROM chat_rooms
WHERE JSON_TYPE(JSON_EXTRACT(participants, '$[0]')) = 'INTEGER';
-- Expected result: 0
