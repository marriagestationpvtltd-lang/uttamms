-- =============================================================================
-- Migration: packages and user_subscriptions tables
-- Run this on the live 'ms' database after pulling the latest schema changes.
-- Safe to re-run: all steps are idempotent (IF NOT EXISTS / type checks).
--
-- Root cause of MySQL error #3780:
--   The existing database was created with `users`.`id` as INT (signed), while
--   the new user_subscriptions table uses `userid INT UNSIGNED`. MySQL requires
--   that a foreign-key column and its referenced column share the exact same
--   data type, including the UNSIGNED attribute.
--
-- This script:
--   1. Detects whether users.id is still a signed INT.
--   2. If so, saves all FK constraints that reference users(id), drops them,
--      alters users.id (and every referencing column) to INT UNSIGNED, then
--      re-adds all constraints.
--   3. Creates the packages table IF NOT EXISTS.
--   4. Creates the user_subscriptions table IF NOT EXISTS.
-- =============================================================================

-- ─────────────────────────────────────────────────────────────────────────────
-- PART 1 – Ensure users.id is INT UNSIGNED
-- ─────────────────────────────────────────────────────────────────────────────

DROP PROCEDURE IF EXISTS _migrate_users_id_unsigned;

DELIMITER //

CREATE PROCEDURE _migrate_users_id_unsigned()
BEGIN
    DECLARE v_done     INT          DEFAULT FALSE;
    DECLARE v_tbl      VARCHAR(64);
    DECLARE v_fk       VARCHAR(64);
    DECLARE v_col      VARCHAR(64);
    DECLARE v_del      VARCHAR(64);
    DECLARE v_upd      VARCHAR(64);
    DECLARE v_nullable VARCHAR(3);
    DECLARE v_extra    VARCHAR(30);
    DECLARE v_id_type  VARCHAR(64);

    -- Cursor over the saved FK metadata (populated just before OPEN)
    DECLARE cur CURSOR FOR
        SELECT tbl_name, fk_name, col_name, del_rule, upd_rule
        FROM   _fk_users_backup;

    DECLARE CONTINUE HANDLER FOR NOT FOUND SET v_done = TRUE;

    -- ── Check current type of users.id ──────────────────────────────────────
    SELECT COLUMN_TYPE INTO v_id_type
    FROM   information_schema.COLUMNS
    WHERE  TABLE_SCHEMA = DATABASE()
      AND  TABLE_NAME   = 'users'
      AND  COLUMN_NAME  = 'id'
    LIMIT 1;

    -- Nothing to do if the column is already UNSIGNED or the table is absent
    IF v_id_type IS NULL OR INSTR(UPPER(v_id_type), 'UNSIGNED') > 0 THEN
        LEAVE _migrate_users_id_unsigned;
    END IF;

    -- ── Save FK metadata before touching anything ────────────────────────────
    DROP TEMPORARY TABLE IF EXISTS _fk_users_backup;
    CREATE TEMPORARY TABLE _fk_users_backup AS
        SELECT
            kcu.TABLE_NAME      AS tbl_name,
            kcu.CONSTRAINT_NAME AS fk_name,
            kcu.COLUMN_NAME     AS col_name,
            rc.DELETE_RULE      AS del_rule,
            rc.UPDATE_RULE      AS upd_rule
        FROM   information_schema.KEY_COLUMN_USAGE        kcu
        JOIN   information_schema.REFERENTIAL_CONSTRAINTS rc
          ON   rc.CONSTRAINT_SCHEMA = kcu.TABLE_SCHEMA
          AND  rc.CONSTRAINT_NAME   = kcu.CONSTRAINT_NAME
        WHERE  kcu.TABLE_SCHEMA            = DATABASE()
          AND  kcu.REFERENCED_TABLE_NAME   = 'users'
          AND  kcu.REFERENCED_COLUMN_NAME  = 'id';

    -- ── Step 1: Drop every FK that references users(id) ─────────────────────
    OPEN cur;
    drop_loop: LOOP
        FETCH cur INTO v_tbl, v_fk, v_col, v_del, v_upd;
        IF v_done THEN LEAVE drop_loop; END IF;

        SET @_sql = CONCAT(
            'ALTER TABLE `', v_tbl, '` DROP FOREIGN KEY `', v_fk, '`'
        );
        PREPARE _s FROM @_sql;
        EXECUTE _s;
        DEALLOCATE PREPARE _s;
    END LOOP;
    CLOSE cur;

    -- ── Step 2: Alter users.id to INT UNSIGNED ───────────────────────────────
    ALTER TABLE users MODIFY COLUMN id INT UNSIGNED NOT NULL AUTO_INCREMENT;

    -- ── Step 3: For each referencing column – alter to UNSIGNED, re-add FK ──
    SET v_done = FALSE;
    OPEN cur;
    alter_loop: LOOP
        FETCH cur INTO v_tbl, v_fk, v_col, v_del, v_upd;
        IF v_done THEN LEAVE alter_loop; END IF;

        -- Determine whether the column is nullable and if it has AUTO_INCREMENT
        SELECT IS_NULLABLE, EXTRA
        INTO   v_nullable, v_extra
        FROM   information_schema.COLUMNS
        WHERE  TABLE_SCHEMA = DATABASE()
          AND  TABLE_NAME   = v_tbl
          AND  COLUMN_NAME  = v_col
        LIMIT 1;

        -- Modify the referencing column to INT UNSIGNED, preserving nullability
        SET @_sql = CONCAT(
            'ALTER TABLE `', v_tbl,
            '` MODIFY COLUMN `', v_col, '` INT UNSIGNED',
            IF(v_nullable = 'NO', ' NOT NULL', ' DEFAULT NULL'),
            IF(v_extra LIKE '%auto_increment%', ' AUTO_INCREMENT', '')
        );
        PREPARE _s FROM @_sql;
        EXECUTE _s;
        DEALLOCATE PREPARE _s;

        -- Re-add the FK constraint (with original ON DELETE / ON UPDATE rules)
        SET @_sql = CONCAT(
            'ALTER TABLE `', v_tbl,
            '` ADD CONSTRAINT `', v_fk,
            '` FOREIGN KEY (`', v_col, '`) REFERENCES `users` (`id`)',
            CASE v_del
                WHEN 'CASCADE'   THEN ' ON DELETE CASCADE'
                WHEN 'SET NULL'  THEN ' ON DELETE SET NULL'
                WHEN 'RESTRICT'  THEN ' ON DELETE RESTRICT'
                ELSE ''
            END,
            CASE v_upd
                WHEN 'CASCADE'   THEN ' ON UPDATE CASCADE'
                WHEN 'SET NULL'  THEN ' ON UPDATE SET NULL'
                WHEN 'RESTRICT'  THEN ' ON UPDATE RESTRICT'
                ELSE ''
            END
        );
        PREPARE _s FROM @_sql;
        EXECUTE _s;
        DEALLOCATE PREPARE _s;
    END LOOP alter_loop;
    CLOSE cur;

    DROP TEMPORARY TABLE IF EXISTS _fk_users_backup;

END //

DELIMITER ;

CALL _migrate_users_id_unsigned();
DROP PROCEDURE IF EXISTS _migrate_users_id_unsigned;


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 2 – packages table (must exist before user_subscriptions references it)
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS packages (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    name        VARCHAR(150) NOT NULL,
    price       DECIMAL(10,2) NOT NULL DEFAULT 0.00,
    duration    INT UNSIGNED NOT NULL DEFAULT 30,    -- days
    description TEXT         DEFAULT NULL,
    is_active   TINYINT(1) UNSIGNED NOT NULL DEFAULT 1,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ─────────────────────────────────────────────────────────────────────────────
-- PART 3 – user_subscriptions table
-- ─────────────────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS user_subscriptions (
    id          INT          UNSIGNED AUTO_INCREMENT PRIMARY KEY,
    userid      INT UNSIGNED NOT NULL,
    package_id  INT UNSIGNED NOT NULL,
    start_date  DATE         NOT NULL,
    end_date    DATE         NOT NULL,
    status      ENUM('active','expired','cancelled') NOT NULL DEFAULT 'active',
    payment_ref VARCHAR(255) DEFAULT NULL,
    created_at  DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,

    FOREIGN KEY (userid)     REFERENCES users(id)     ON DELETE CASCADE,
    FOREIGN KEY (package_id) REFERENCES packages(id)  ON DELETE RESTRICT,
    INDEX idx_userid     (userid),
    INDEX idx_end_date   (end_date)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
