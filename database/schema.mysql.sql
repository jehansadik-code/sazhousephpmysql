-- SAZ House MySQL 8.0+/MariaDB 10.6+ schema. Import into an empty database.
-- This does not connect to, delete, or alter the existing Supabase project.
SET NAMES utf8mb4;
SET time_zone = '+00:00';

CREATE TABLE roles (
  slug VARCHAR(48) PRIMARY KEY, name VARCHAR(80) NOT NULL, description VARCHAR(240) NOT NULL DEFAULT '',
  permissions JSON NOT NULL, is_protected TINYINT NOT NULL DEFAULT 0,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
INSERT INTO roles (slug,name,description,permissions,is_protected) VALUES
('owner','Owner','Full control of the store and access controls.',JSON_ARRAY('*'),1),
('administrator','Administrator','Runs the store day to day without changing team security.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage','products.manage','coupons.manage','messages.view','messages.manage','content.manage','settings.manage','store.manage','customers.view'),0),
('manager','Store Manager','Oversees orders, catalog, promotions and store content.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage','products.manage','coupons.manage','messages.view','content.manage','customers.view'),0),
('fulfillment','Fulfillment','Views and updates customer orders.',JSON_ARRAY('admin.access','dashboard.view','orders.view','orders.manage'),0),
('catalog-editor','Catalog Editor','Maintains products, collections and promotions.',JSON_ARRAY('admin.access','dashboard.view','products.manage','coupons.manage','content.manage'),0),
('support','Customer Support','Reads orders and handles customer messages.',JSON_ARRAY('admin.access','dashboard.view','orders.view','messages.view','messages.manage','customers.view'),0),
('marketing','Marketing','Edits storefront content and promotions.',JSON_ARRAY('admin.access','dashboard.view','content.manage','coupons.manage'),0),
('analyst','Analyst','Has read-only access to operational dashboards.',JSON_ARRAY('admin.access','dashboard.view','orders.view','messages.view','customers.view'),0),
('customer','Customer','Store customer account.',JSON_ARRAY(),1);

CREATE TABLE users (
  id CHAR(36) PRIMARY KEY, email VARCHAR(254) NOT NULL UNIQUE, password_hash VARCHAR(255) NOT NULL,
  role_slug VARCHAR(48) NOT NULL DEFAULT 'customer', is_active TINYINT NOT NULL DEFAULT 1,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, last_sign_in_at TIMESTAMP NULL,
  CONSTRAINT users_role_fk FOREIGN KEY (role_slug) REFERENCES roles(slug)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE store_state (
  `key` VARCHAR(32) PRIMARY KEY, value JSON NOT NULL, revision BIGINT UNSIGNED NOT NULL DEFAULT 1, updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT store_state_key_ck CHECK (`key` IN ('products','product_types','coupons','settings','site_content','page_products','home_categories'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
-- A new installation must be checkout-ready before the first administrator
-- saves content.  These records preserve the frontend's evidenced defaults.
INSERT INTO store_state (`key`, value) VALUES
('products', JSON_ARRAY()),
('product_types', JSON_ARRAY('tee','hoodie','cap','jacket','pants','bag','other')),
('coupons', JSON_ARRAY()),
('settings', JSON_OBJECT('dhaka',80,'outside',150,'freeThreshold',3000,'payments',JSON_OBJECT('cod',true,'bkash',true,'nagad',true,'card',true),'bkashNumber','','nagadNumber','')),
('site_content', JSON_OBJECT('announcement','Free delivery on orders over Tk 3,000 - Designed in Dhaka','heroEyebrow','WEAR YOUR VISION','heroTitle','STYLE MEETS\nIDENTITY','heroText','SAZ House brings you premium streetwear that speaks your style, your story, your vibe.','heroButton','SHOP NOW','aboutStory','SAZ House started with a simple idea: everyday clothing should feel like you. We make considered streetwear with confident design, comfortable fits, and quality you can count on.','footerText','Streetwear made for your everyday. Be part of the SAZ House movement.','contactEmail','support@sazhouse.com','contactPhone','+880 1700-000000','contactLocation','Dhaka, Bangladesh','logoPath','assets/images/brand/logo.png')),
('page_products', JSON_OBJECT()),
('home_categories', JSON_ARRAY(JSON_OBJECT('label','Men','href','shop.html?department=men','image',''),JSON_OBJECT('label','Women','href','shop.html?department=women','image',''),JSON_OBJECT('label','Shoes','href','shop.html?category=Shoes','image',''),JSON_OBJECT('label','Bags','href','shop.html?category=Bags','image','')));
CREATE TABLE orders (
  id CHAR(36) PRIMARY KEY, reference VARCHAR(32) NOT NULL UNIQUE, customer_name VARCHAR(100) NOT NULL, phone VARCHAR(30) NOT NULL,
  email VARCHAR(254) NULL, address VARCHAR(500) NOT NULL, city VARCHAR(100) NULL, district VARCHAR(100) NULL, division VARCHAR(100) NULL,
  payment_method VARCHAR(30) NOT NULL, subtotal DECIMAL(12,2) NOT NULL DEFAULT 0, shipping DECIMAL(12,2) NOT NULL DEFAULT 0,
  discount DECIMAL(12,2) NOT NULL DEFAULT 0, total DECIMAL(12,2) NOT NULL DEFAULT 0, coupon VARCHAR(50) NULL,
  status ENUM('Processing','Shipped','Delivered','Cancelled') NOT NULL DEFAULT 'Processing', line_items JSON NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY orders_created_at_idx(created_at), KEY orders_status_idx(status)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE order_items (
  id BIGINT UNSIGNED AUTO_INCREMENT PRIMARY KEY, order_id CHAR(36) NOT NULL, product_id VARCHAR(100) NOT NULL, name VARCHAR(160) NOT NULL,
  color VARCHAR(60) NOT NULL, size VARCHAR(30) NOT NULL, quantity INT UNSIGNED NOT NULL, unit_price DECIMAL(12,2) NOT NULL,
  UNIQUE KEY order_item_variant_uniq(order_id,product_id,color,size),
  CONSTRAINT order_items_order_fk FOREIGN KEY(order_id) REFERENCES orders(id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE contact_messages (id VARCHAR(100) PRIMARY KEY, name VARCHAR(100) NOT NULL, email VARCHAR(254) NOT NULL, subject VARCHAR(160) NULL, message TEXT NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY contact_created_at_idx(created_at)) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE checkout_requests (idempotency_key VARCHAR(128) PRIMARY KEY, request_hash CHAR(64) NOT NULL, response JSON NULL, order_reference VARCHAR(32) NULL UNIQUE, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, CONSTRAINT checkout_order_fk FOREIGN KEY(order_reference) REFERENCES orders(reference) ON DELETE RESTRICT) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE submission_throttle (fingerprint CHAR(64) PRIMARY KEY, action VARCHAR(20) NOT NULL, last_seen TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE admin_audit_log (id CHAR(36) PRIMARY KEY, actor_id CHAR(36) NULL, action VARCHAR(80) NOT NULL, target_type VARCHAR(40) NOT NULL, target_id VARCHAR(100) NULL, details JSON NOT NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY audit_created_idx(created_at), CONSTRAINT audit_actor_fk FOREIGN KEY(actor_id) REFERENCES users(id) ON DELETE SET NULL) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
CREATE TABLE media_uploads (
  id CHAR(36) PRIMARY KEY, stored_name VARCHAR(80) NOT NULL UNIQUE, relative_path VARCHAR(255) NOT NULL UNIQUE,
  mime_type VARCHAR(32) NOT NULL, byte_size INT UNSIGNED NOT NULL, uploaded_by CHAR(36) NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, KEY media_created_at_idx(created_at),
  CONSTRAINT media_uploaded_by_fk FOREIGN KEY(uploaded_by) REFERENCES users(id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;
