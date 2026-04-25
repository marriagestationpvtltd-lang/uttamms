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

-- Idempotent: ADD COLUMN IF NOT EXISTS is supported on MySQL 8.0.3+ and
-- MariaDB 10.0+.  For older MySQL 5.7 installs the INFORMATION_SCHEMA guard
-- below is used instead.

ALTER TABLE chat_messages ADD COLUMN IF NOT EXISTS
    is_unsent TINYINT(1) NOT NULL DEFAULT 0;
