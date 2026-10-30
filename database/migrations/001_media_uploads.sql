-- Apply only to a MySQL database created by an earlier SAZ PHP migration.
-- Fresh installs already receive this table from ../schema.mysql.sql.
CREATE TABLE IF NOT EXISTS media_uploads (
  id CHAR(36) PRIMARY KEY,
  stored_name VARCHAR(80) NOT NULL UNIQUE,
  relative_path VARCHAR(255) NOT NULL UNIQUE,
  mime_type VARCHAR(32) NOT NULL,
  byte_size INT UNSIGNED NOT NULL,
  uploaded_by CHAR(36) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  KEY media_created_at_idx(created_at),
  CONSTRAINT media_uploaded_by_fk FOREIGN KEY(uploaded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Optional only when upgrading a database that already has order_items.
-- Check for duplicate historical rows before applying this statement.
-- ALTER TABLE order_items ADD UNIQUE KEY order_item_variant_uniq(order_id,product_id,color,size);
