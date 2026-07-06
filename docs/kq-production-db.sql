-- KQremoteLink production database initialization script.
-- Target: MySQL 8.x / MariaDB with InnoDB and utf8mb4.
--
-- Default app env:
--   KQ_DB_NAME=kq_remote_link
--   KQ_DB_PORT=3306
--
-- Run as a privileged database user:
--   mysql -h <db-host> -P 3306 -u <root-or-admin> -p < deploy/kq-production-db.sql
--
-- Optional user creation example. Replace placeholders before running if needed:
--   CREATE USER IF NOT EXISTS 'kq_remote_link'@'%' IDENTIFIED BY '<fill-database-password>';
--   GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, ALTER, INDEX, REFERENCES
--     ON kq_remote_link.* TO 'kq_remote_link'@'%';
--   FLUSH PRIVILEGES;

CREATE DATABASE IF NOT EXISTS `kq_remote_link`
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE `kq_remote_link`;

CREATE TABLE IF NOT EXISTS `kq_users` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `external_provider` VARCHAR(32) NOT NULL DEFAULT 'kunqiong',
  `external_user_id` VARCHAR(128) NOT NULL,
  `username` VARCHAR(128) NOT NULL,
  `nickname` VARCHAR(128) NOT NULL DEFAULT '',
  `email` VARCHAR(255) NOT NULL DEFAULT '',
  `avatar_url` TEXT NULL,
  `token_hash` CHAR(64) NULL,
  `member_active` TINYINT(1) NOT NULL DEFAULT 0,
  `member_expire_at` DATETIME NULL,
  `raw_user_json` JSON NULL,
  `last_login_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_external_user` (`external_provider`, `external_user_id`),
  KEY `idx_username` (`username`),
  KEY `idx_member_active` (`member_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `kq_connection_history` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `peer_id` VARCHAR(128) NOT NULL,
  `peer_alias` VARCHAR(255) NOT NULL DEFAULT '',
  `peer_username` VARCHAR(255) NOT NULL DEFAULT '',
  `peer_hostname` VARCHAR(255) NOT NULL DEFAULT '',
  `peer_platform` VARCHAR(64) NOT NULL DEFAULT '',
  `conn_type` VARCHAR(32) NOT NULL DEFAULT 'remote',
  `connect_count` INT UNSIGNED NOT NULL DEFAULT 1,
  `metadata` JSON NULL,
  `connected_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_peer` (`user_id`, `peer_id`),
  KEY `idx_user_last_seen` (`user_id`, `last_seen_at`),
  CONSTRAINT `fk_history_user`
    FOREIGN KEY (`user_id`) REFERENCES `kq_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `kq_account_devices` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `device_key` VARCHAR(128) NOT NULL,
  `device_id` VARCHAR(128) NOT NULL,
  `device_name` VARCHAR(255) NOT NULL DEFAULT '',
  `device_alias` VARCHAR(255) NOT NULL DEFAULT '',
  `device_hostname` VARCHAR(255) NOT NULL DEFAULT '',
  `device_platform` VARCHAR(64) NOT NULL DEFAULT '',
  `device_type` VARCHAR(64) NOT NULL DEFAULT '',
  `metadata` JSON NULL,
  `first_login_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_login_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_seen_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_device_key` (`user_id`, `device_key`),
  KEY `idx_user_device_seen` (`user_id`, `last_seen_at`),
  CONSTRAINT `fk_account_device_user`
    FOREIGN KEY (`user_id`) REFERENCES `kq_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `kq_member_orders` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `order_no` VARCHAR(64) NOT NULL,
  `package_id` INT UNSIGNED NOT NULL DEFAULT 0,
  `package_name` VARCHAR(128) NOT NULL DEFAULT '',
  `package_days` INT UNSIGNED NOT NULL DEFAULT 0,
  `pay_amount` DECIMAL(10,2) NOT NULL DEFAULT 0,
  `pay_type` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `pay_status` TINYINT UNSIGNED NOT NULL DEFAULT 0,
  `expire_at` DATETIME NULL,
  `raw_order_json` JSON NULL,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_order_no` (`order_no`),
  KEY `idx_user_order` (`user_id`, `created_at`),
  CONSTRAINT `fk_order_user`
    FOREIGN KEY (`user_id`) REFERENCES `kq_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `kq_member_snapshots` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `user_id` BIGINT UNSIGNED NOT NULL,
  `member_active` TINYINT(1) NOT NULL DEFAULT 0,
  `member_expire_at` DATETIME NULL,
  `subsite_name` VARCHAR(255) NOT NULL DEFAULT '',
  `package_count` INT UNSIGNED NOT NULL DEFAULT 0,
  `snapshot_hash` CHAR(64) NOT NULL,
  `raw_member_json` JSON NULL,
  `synced_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uniq_user_snapshot_hash` (`user_id`, `snapshot_hash`),
  KEY `idx_user_synced` (`user_id`, `synced_at`),
  CONSTRAINT `fk_snapshot_user`
    FOREIGN KEY (`user_id`) REFERENCES `kq_users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Conservative migration for databases initialized by older builds.
-- Add kq_account_devices.device_key if it is missing.
SET @kq_missing_device_key := (
  SELECT COUNT(*) = 0
  FROM information_schema.COLUMNS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'kq_account_devices'
    AND COLUMN_NAME = 'device_key'
);

SET @kq_sql := IF(
  @kq_missing_device_key,
  'ALTER TABLE `kq_account_devices` ADD COLUMN `device_key` VARCHAR(128) NOT NULL DEFAULT '''' AFTER `user_id`',
  'SELECT 1'
);
PREPARE kq_stmt FROM @kq_sql;
EXECUTE kq_stmt;
DEALLOCATE PREPARE kq_stmt;

UPDATE `kq_account_devices`
SET `device_key` = `device_id`
WHERE `device_key` = '';

-- Drop the legacy unique index if present.
SET @kq_has_legacy_index := (
  SELECT COUNT(*) > 0
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'kq_account_devices'
    AND INDEX_NAME = 'uniq_user_device'
);

SET @kq_sql := IF(
  @kq_has_legacy_index,
  'ALTER TABLE `kq_account_devices` DROP INDEX `uniq_user_device`',
  'SELECT 1'
);
PREPARE kq_stmt FROM @kq_sql;
EXECUTE kq_stmt;
DEALLOCATE PREPARE kq_stmt;

-- Ensure the current unique index exists.
SET @kq_missing_device_key_index := (
  SELECT COUNT(*) = 0
  FROM information_schema.STATISTICS
  WHERE TABLE_SCHEMA = DATABASE()
    AND TABLE_NAME = 'kq_account_devices'
    AND INDEX_NAME = 'uniq_user_device_key'
);

SET @kq_sql := IF(
  @kq_missing_device_key_index,
  'ALTER TABLE `kq_account_devices` ADD UNIQUE KEY `uniq_user_device_key` (`user_id`, `device_key`)',
  'SELECT 1'
);
PREPARE kq_stmt FROM @kq_sql;
EXECUTE kq_stmt;
DEALLOCATE PREPARE kq_stmt;
