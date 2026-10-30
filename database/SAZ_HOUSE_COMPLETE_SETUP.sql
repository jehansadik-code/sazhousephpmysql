-- SAZ House complete local MySQL 8.0.46 setup.
-- Safe for a new database and the known partial state where roles exists but
-- users failed with Error 3780. It never drops, truncates, deletes, or updates
-- application data. Run this in MySQL Workbench while connected as a local
-- administrator. It intentionally does not create a database login/password.

CREATE DATABASE IF NOT EXISTS `saz_house`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER DATABASE `saz_house`
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `saz_house`;
SET NAMES utf8mb4 COLLATE utf8mb4_unicode_ci;
SET time_zone = '+00:00';

-- roles is created first because every staff identity references it.
CREATE TABLE IF NOT EXISTS `roles` (
  `slug` VARCHAR(48) NOT NULL,
  `name` VARCHAR(80) NOT NULL,
  `description` VARCHAR(240) NOT NULL DEFAULT '',
  `permissions` JSON NOT NULL,
  `is_protected` TINYINT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Repair exactly the reported parent-column mismatch when no existing FK
-- depends on it. If an unexpected dependent FK exists, no alteration is made;
-- later verification reports it so it can be repaired as a coordinated change.
SET @saz_roles_slug_needs_fix := (
  SELECT COUNT(*) > 0
  FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'roles' AND column_name = 'slug'
    AND (character_set_name <> 'utf8mb4' OR collation_name <> 'utf8mb4_unicode_ci')
);
SET @saz_roles_slug_has_dependents := (
  SELECT COUNT(*) > 0
  FROM information_schema.key_column_usage
  WHERE referenced_table_schema = DATABASE() AND referenced_table_name = 'roles'
    AND referenced_column_name = 'slug'
);
SET @saz_sql := IF(
  @saz_roles_slug_needs_fix = 1 AND @saz_roles_slug_has_dependents = 0,
  'ALTER TABLE `roles` MODIFY COLUMN `slug` VARCHAR(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL',
  'SELECT ''roles.slug already compatible, or has dependent foreign keys and was left unchanged for safety'' AS setup_notice'
);
PREPARE saz_setup_stmt FROM @saz_sql;
EXECUTE saz_setup_stmt;
DEALLOCATE PREPARE saz_setup_stmt;

INSERT IGNORE INTO `roles` (`slug`,`name`,`description`,`permissions`,`is_protected`) VALUES
('owner','Owner','Full control of the store and access controls.',JSON_ARRAY('*'),1),
('administrator','Administrator','Runs the store day to day without changing team security.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage','products.manage','coupons.manage','messages.view','messages.manage','content.manage','settings.manage','store.manage','customers.view'),0),
('manager','Store Manager','Oversees orders, catalog, promotions and store content.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage','products.manage','coupons.manage','messages.view','content.manage','customers.view'),0),
('fulfillment','Fulfillment','Views and updates customer orders.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage'),0),
('catalog-editor','Catalog Editor','Maintains products, collections and promotions.',JSON_ARRAY('admin.access','dashboard.view','products.manage','coupons.manage','content.manage'),0),
('support','Customer Support','Reads orders and handles customer messages.',JSON_ARRAY('admin.access','dashboard.view','orders.view','messages.view','messages.manage','customers.view'),0),
('marketing','Marketing','Edits storefront content and promotions.',JSON_ARRAY('admin.access','dashboard.view','content.manage','coupons.manage'),0),
('analyst','Analyst','Has read-only access to operational dashboards.',JSON_ARRAY('admin.access','dashboard.view','orders.view','messages.view','customers.view'),0),
('customer','Customer','Store customer account.',JSON_ARRAY(),1);

CREATE TABLE IF NOT EXISTS `users` (
  `id` CHAR(36) NOT NULL,
  `email` VARCHAR(254) NOT NULL,
  `password_hash` VARCHAR(255) NOT NULL,
  `role_slug` VARCHAR(48) NOT NULL DEFAULT 'customer',
  `is_active` TINYINT NOT NULL DEFAULT 1,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `last_sign_in_at` TIMESTAMP NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `email` (`email`),
  KEY `users_role_idx` (`role_slug`),
  CONSTRAINT `users_role_fk` FOREIGN KEY (`role_slug`) REFERENCES `roles` (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `store_state` (
  `key` VARCHAR(32) NOT NULL,
  `value` JSON NOT NULL,
  `revision` BIGINT UNSIGNED NOT NULL DEFAULT 1,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`key`),
  CONSTRAINT `store_state_key_ck` CHECK (`key` IN ('products','product_types','coupons','settings','site_content','page_products','home_categories'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `orders` (
  `id` CHAR(36) NOT NULL,
  `reference` VARCHAR(32) NOT NULL,
  `customer_name` VARCHAR(100) NOT NULL,
  `phone` VARCHAR(30) NOT NULL,
  `email` VARCHAR(254) NULL,
  `address` VARCHAR(500) NOT NULL,
  `city` VARCHAR(100) NULL,
  `district` VARCHAR(100) NULL,
  `division` VARCHAR(100) NULL,
  `payment_method` VARCHAR(30) NOT NULL,
  `subtotal` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `shipping` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `discount` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `total` DECIMAL(12,2) NOT NULL DEFAULT 0,
  `coupon` VARCHAR(50) NULL,
  `status` ENUM('Processing','Shipped','Delivered','Cancelled') NOT NULL DEFAULT 'Processing',
  `line_items` JSON NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `reference` (`reference`),
  KEY `orders_created_at_idx` (`created_at`),
  KEY `orders_status_idx` (`status`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `order_items` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `order_id` CHAR(36) NOT NULL,
  `product_id` VARCHAR(100) NOT NULL,
  `name` VARCHAR(160) NOT NULL,
  `color` VARCHAR(60) NOT NULL,
  `size` VARCHAR(30) NOT NULL,
  `quantity` INT UNSIGNED NOT NULL,
  `unit_price` DECIMAL(12,2) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `order_item_variant_uniq` (`order_id`,`product_id`,`color`,`size`),
  CONSTRAINT `order_items_order_fk` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `contact_messages` (
  `id` VARCHAR(100) NOT NULL,
  `name` VARCHAR(100) NOT NULL,
  `email` VARCHAR(254) NOT NULL,
  `subject` VARCHAR(160) NULL,
  `message` TEXT NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `contact_created_at_idx` (`created_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `checkout_requests` (
  `idempotency_key` VARCHAR(128) NOT NULL,
  `request_hash` CHAR(64) NOT NULL,
  `response` JSON NULL,
  `order_reference` VARCHAR(32) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`idempotency_key`),
  UNIQUE KEY `order_reference` (`order_reference`),
  CONSTRAINT `checkout_order_fk` FOREIGN KEY (`order_reference`) REFERENCES `orders` (`reference`) ON DELETE RESTRICT
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `submission_throttle` (
  `fingerprint` CHAR(64) NOT NULL,
  `action` VARCHAR(20) NOT NULL,
  `last_seen` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`fingerprint`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `admin_audit_log` (
  `id` CHAR(36) NOT NULL,
  `actor_id` CHAR(36) NULL,
  `action` VARCHAR(80) NOT NULL,
  `target_type` VARCHAR(40) NOT NULL,
  `target_id` VARCHAR(100) NULL,
  `details` JSON NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `audit_created_idx` (`created_at`),
  CONSTRAINT `audit_actor_fk` FOREIGN KEY (`actor_id`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `media_uploads` (
  `id` CHAR(36) NOT NULL,
  `stored_name` VARCHAR(80) NOT NULL,
  `relative_path` VARCHAR(255) NOT NULL,
  `mime_type` VARCHAR(32) NOT NULL,
  `byte_size` INT UNSIGNED NOT NULL,
  `uploaded_by` CHAR(36) NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `stored_name` (`stored_name`),
  UNIQUE KEY `relative_path` (`relative_path`),
  KEY `media_created_at_idx` (`created_at`),
  CONSTRAINT `media_uploaded_by_fk` FOREIGN KEY (`uploaded_by`) REFERENCES `users` (`id`) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- Repair a pre-existing unreferenced users.role_slug before adding its FK.
-- Do not narrow an unknown legacy value or convert NULLs: either condition is
-- surfaced by the later FK step rather than risking an implicit data change.
SET @saz_users_role_needs_fix := (
  SELECT COUNT(*) > 0 FROM information_schema.columns
  WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'role_slug'
    AND (character_set_name <> 'utf8mb4' OR collation_name <> 'utf8mb4_unicode_ci' OR column_type <> 'varchar(48)')
);
SET @saz_users_role_too_long := (
  SELECT COALESCE(MAX(CHAR_LENGTH(`role_slug`)), 0) > 48 FROM `users`
);
SET @saz_users_role_has_null := (
  SELECT COUNT(*) > 0 FROM `users` WHERE `role_slug` IS NULL
);
SET @saz_sql := IF(
  @saz_users_role_needs_fix = 1 AND @saz_users_role_too_long = 0 AND @saz_users_role_has_null = 0,
  'ALTER TABLE `users` MODIFY COLUMN `role_slug` VARCHAR(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL DEFAULT ''customer''',
  IF(
    @saz_users_role_needs_fix = 1,
    'SELECT ''users.role_slug has a NULL or a value longer than 48 characters; no narrowing alteration was made'' AS setup_notice',
    'SELECT ''users.role_slug is compatible'' AS setup_notice'
  )
);
PREPARE saz_setup_stmt FROM @saz_sql;
EXECUTE saz_setup_stmt;
DEALLOCATE PREPARE saz_setup_stmt;

-- Complete safely interrupted earlier installs that created a table without a
-- named foreign key. Existing valid constraints are left unchanged. A legacy
-- orphan causes MySQL to stop instead of silently discarding data.
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='users' AND column_name='role_slug' AND referenced_table_name='roles' AND referenced_column_name='slug'),
  'SELECT ''users role FK already exists'' AS setup_notice',
  'ALTER TABLE `users` ADD CONSTRAINT `users_role_fk` FOREIGN KEY (`role_slug`) REFERENCES `roles` (`slug`)'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='order_items' AND column_name='order_id' AND referenced_table_name='orders' AND referenced_column_name='id'),
  'SELECT ''order_items order FK already exists'' AS setup_notice',
  'ALTER TABLE `order_items` ADD CONSTRAINT `order_items_order_fk` FOREIGN KEY (`order_id`) REFERENCES `orders` (`id`) ON DELETE CASCADE'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='checkout_requests' AND column_name='order_reference' AND referenced_table_name='orders' AND referenced_column_name='reference'),
  'SELECT ''checkout request order FK already exists'' AS setup_notice',
  'ALTER TABLE `checkout_requests` ADD CONSTRAINT `checkout_order_fk` FOREIGN KEY (`order_reference`) REFERENCES `orders` (`reference`) ON DELETE RESTRICT'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='admin_audit_log' AND column_name='actor_id' AND referenced_table_name='users' AND referenced_column_name='id'),
  'SELECT ''audit actor FK already exists'' AS setup_notice',
  'ALTER TABLE `admin_audit_log` ADD CONSTRAINT `audit_actor_fk` FOREIGN KEY (`actor_id`) REFERENCES `users` (`id`) ON DELETE SET NULL'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.key_column_usage WHERE table_schema=DATABASE() AND table_name='media_uploads' AND column_name='uploaded_by' AND referenced_table_name='users' AND referenced_column_name='id'),
  'SELECT ''media uploaded-by FK already exists'' AS setup_notice',
  'ALTER TABLE `media_uploads` ADD CONSTRAINT `media_uploaded_by_fk` FOREIGN KEY (`uploaded_by`) REFERENCES `users` (`id`) ON DELETE SET NULL'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.table_constraints WHERE table_schema=DATABASE() AND table_name='store_state' AND constraint_name='store_state_key_ck' AND constraint_type='CHECK'),
  'SELECT ''store_state_key_ck already exists; verification will report its clause'' AS setup_notice',
  'ALTER TABLE `store_state` ADD CONSTRAINT `store_state_key_ck` CHECK (`key` IN (''products'',''product_types'',''coupons'',''settings'',''site_content'',''page_products'',''home_categories''))'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;

-- Data-preserving migrations. 001 is covered by CREATE TABLE above. 002 is
-- performed only when no legacy identifier exceeds the destination width.
SET @saz_contact_id_too_long := (SELECT COALESCE(MAX(CHAR_LENGTH(`id`)),0) > 100 FROM `contact_messages`);
SET @saz_sql := IF(
  @saz_contact_id_too_long = 0,
  'ALTER TABLE `contact_messages` MODIFY COLUMN `id` VARCHAR(100) NOT NULL',
  'SELECT ''contact_messages.id has a value longer than 100 characters; no narrowing alteration was made'' AS setup_notice'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;
SET @saz_sql := IF(
  EXISTS(SELECT 1 FROM information_schema.columns WHERE table_schema=DATABASE() AND table_name='store_state' AND column_name='revision'),
  'SELECT ''store_state.revision already exists'' AS setup_notice',
  'ALTER TABLE `store_state` ADD COLUMN `revision` BIGINT UNSIGNED NOT NULL DEFAULT 1 AFTER `value`'
);
PREPARE saz_setup_stmt FROM @saz_sql; EXECUTE saz_setup_stmt; DEALLOCATE PREPARE saz_setup_stmt;

-- Required persisted JSON documents. INSERT IGNORE preserves every existing
-- document, including catalog, variants, inventory, content and settings.
INSERT IGNORE INTO `store_state` (`key`,`value`) VALUES
('products', JSON_ARRAY()),
('product_types', JSON_ARRAY('tee','hoodie','cap','jacket','pants','bag','other')),
('coupons', JSON_ARRAY()),
('settings', JSON_OBJECT('dhaka',80,'outside',150,'freeThreshold',3000,'payments',JSON_OBJECT('cod',true,'bkash',true,'nagad',true,'card',true),'bkashNumber','','nagadNumber','')),
('site_content', JSON_OBJECT('announcement','Free delivery on orders over Tk 3,000 - Designed in Dhaka','heroEyebrow','WEAR YOUR VISION','heroTitle','STYLE MEETS\nIDENTITY','heroText','SAZ House brings you premium streetwear that speaks your style, your story, your vibe.','heroButton','SHOP NOW','aboutStory','SAZ House started with a simple idea: everyday clothing should feel like you. We make considered streetwear with confident design, comfortable fits, and quality you can count on.','footerText','Streetwear made for your everyday. Be part of the SAZ House movement.','contactEmail','support@sazhouse.com','contactPhone','+880 1700-000000','contactLocation','Dhaka, Bangladesh','logoPath','assets/images/brand/logo.png')),
('page_products', JSON_OBJECT()),
('home_categories', JSON_ARRAY(JSON_OBJECT('label','Men','href','shop.html?department=men','image',''),JSON_OBJECT('label','Women','href','shop.html?department=women','image',''),JSON_OBJECT('label','Shoes','href','shop.html?category=Shoes','image',''),JSON_OBJECT('label','Bags','href','shop.html?category=Bags','image','')));

SELECT 'SAZ House setup completed without deleting or overwriting application data. Run SAZ_HOUSE_VERIFY.sql next.' AS result;
