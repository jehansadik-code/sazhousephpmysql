-- Disposable integration-test fixture only. It reproduces the reported state:
-- nine valid role rows exist, then only roles.slug is changed to 0900 collation.
CREATE DATABASE `saz_house` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
USE `saz_house`;
CREATE TABLE `roles` (
  `slug` VARCHAR(48) NOT NULL,
  `name` VARCHAR(80) NOT NULL,
  `description` VARCHAR(240) NOT NULL DEFAULT '',
  `permissions` JSON NOT NULL,
  `is_protected` TINYINT NOT NULL DEFAULT 0,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`slug`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO `roles` (`slug`,`name`,`description`,`permissions`,`is_protected`) VALUES
('owner','Owner','Full control of the store and access controls.',JSON_ARRAY('*'),1),
('administrator','Administrator','Runs the store day to day without changing team security.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage','products.manage','coupons.manage','messages.view','messages.manage','content.manage','settings.manage','store.manage','customers.view'),0),
('manager','Store Manager','Oversees orders, catalog, promotions and store content.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage','products.manage','coupons.manage','messages.view','content.manage','customers.view'),0),
('fulfillment','Fulfillment','Views and updates customer orders.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage'),0),
('catalog-editor','Catalog Editor','Maintains products, collections and promotions.',JSON_ARRAY('admin.access','dashboard.view','products.manage','coupons.manage','content.manage'),0),
('support','Customer Support','Reads orders and handles customer messages.',JSON_ARRAY('admin.access','dashboard.view','orders.view','messages.view','messages.manage','customers.view'),0),
('marketing','Marketing','Edits storefront content and promotions.',JSON_ARRAY('admin.access','dashboard.view','content.manage','coupons.manage'),0),
('analyst','Analyst','Has read-only access to operational dashboards.',JSON_ARRAY('admin.access','dashboard.view','orders.view','messages.view','customers.view'),0),
('customer','Customer','Store customer account.',JSON_ARRAY(),1);
ALTER TABLE `roles` MODIFY COLUMN `slug` VARCHAR(48) CHARACTER SET utf8mb4 COLLATE utf8mb4_0900_ai_ci NOT NULL;
