-- Migration: Add username column to admins table
-- Run this script if your admins table was created from the old schema
-- (before the username column was added).

-- Step 1: Add the username column (nullable initially so existing rows don't violate NOT NULL)
ALTER TABLE admins
    ADD COLUMN username VARCHAR(100) NULL
        AFTER id;

-- Step 2: Back-fill username from the email local-part for any existing rows
UPDATE admins
SET username = SUBSTRING_INDEX(email, '@', 1)
WHERE username IS NULL;

-- Step 3: Make the column NOT NULL and add the unique constraint
ALTER TABLE admins
    MODIFY COLUMN username VARCHAR(100) NOT NULL,
    ADD CONSTRAINT uk_admin_username UNIQUE (username);

-- Step 4: Update the default admin row to set the standard username
--         (skip if the row does not exist or username is already set correctly)
UPDATE admins
SET username = 'admin'
WHERE email = 'admin@ms.com';
