-- =============================================================================
-- Migration: Per-document status tracking
-- Moves document status from the global users.status to per-row
-- user_documents.status so that each document type can be tracked
-- independently.
-- =============================================================================

-- 1. Add reject_reason column to user_documents (stores admin rejection note
--    per document row rather than globally on users).
--    MySQL does not support ADD COLUMN IF NOT EXISTS, so we use an
--    INFORMATION_SCHEMA check with PREPARE/EXECUTE to make this idempotent.
SET @_add_col = (
    SELECT IF(
        COUNT(*) = 0,
        'ALTER TABLE user_documents ADD COLUMN reject_reason VARCHAR(500) DEFAULT NULL AFTER status',
        'SELECT 1'
    )
    FROM INFORMATION_SCHEMA.COLUMNS
    WHERE TABLE_SCHEMA = DATABASE()
      AND TABLE_NAME   = 'user_documents'
      AND COLUMN_NAME  = 'reject_reason'
);
PREPARE _stmt FROM @_add_col;
EXECUTE _stmt;
DEALLOCATE PREPARE _stmt;

-- 2. Ensure documenttype column is NOT NULL (new uploads always supply it)
--    Update any existing NULL rows to a descriptive placeholder before
--    applying the NOT NULL constraint. Records with this value are
--    pre-migration rows that should be reviewed and corrected manually.
UPDATE user_documents SET documenttype = 'Legacy_Document' WHERE documenttype IS NULL;
ALTER TABLE user_documents
    MODIFY COLUMN documenttype VARCHAR(100) NOT NULL;

-- 3. Drop the old single-user unique key (only one doc per user)
ALTER TABLE user_documents DROP INDEX IF EXISTS uk_userid;

-- 4. Add composite unique key so one user can have one row per document type
--    but cannot duplicate the same type.
ALTER TABLE user_documents
    ADD UNIQUE KEY uk_userid_doctype (userid, documenttype);

-- 5. Remove legacy new-schema columns that are replaced by the above
--    (safe to drop if they exist; harmless if they do not)
ALTER TABLE user_documents
    DROP COLUMN IF EXISTS doc_type,
    DROP COLUMN IF EXISTS doc_url;
