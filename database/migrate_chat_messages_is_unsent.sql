-- =============================================================================
-- Migration: Add is_unsent column to chat_messages
-- Run this script against an existing database that was created from a schema
-- version before is_unsent was added to the chat_messages table.
--
-- The column is also added automatically by the socket server at startup, but
-- running this migration ensures the column is present even when the socket
-- server has not yet been started (e.g. on a fresh install that uses only the
-- PHP backend).
-- =============================================================================

-- Idempotent guard using INFORMATION_SCHEMA (compatible with MySQL 5.7+).
DROP PROCEDURE IF EXISTS _migration_add_is_unsent;

DELIMITER $$
CREATE PROCEDURE _migration_add_is_unsent()
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM   INFORMATION_SCHEMA.COLUMNS
        WHERE  TABLE_SCHEMA = DATABASE()
          AND  TABLE_NAME   = 'chat_messages'
          AND  COLUMN_NAME  = 'is_unsent'
    ) THEN
        ALTER TABLE chat_messages
            ADD COLUMN is_unsent TINYINT(1) NOT NULL DEFAULT 0;
    END IF;
END$$
DELIMITER ;

CALL _migration_add_is_unsent();
DROP PROCEDURE IF EXISTS _migration_add_is_unsent;
