-- Reject stale full-state admin saves so they cannot overwrite stock changed
-- by a concurrent transactional checkout or order cancellation/restock.
-- MySQL 8.0.46 does not support MariaDB-style conditional ADD COLUMN syntax.
-- Inspect metadata and prepare the ALTER only when revision is absent so an
-- interrupted upgrade can be resumed without a destructive workaround.
SET @saz_revision_sql := IF(
  EXISTS(
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'store_state' AND column_name = 'revision'
  ),
  'SELECT ''store_state.revision already exists'' AS migration_notice',
  'ALTER TABLE `store_state` ADD COLUMN `revision` BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER `value`'
);
PREPARE saz_revision_stmt FROM @saz_revision_sql;
EXECUTE saz_revision_stmt;
DEALLOCATE PREPARE saz_revision_stmt;
