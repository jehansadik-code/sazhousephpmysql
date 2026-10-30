-- Read-only verification for SAZ_HOUSE_COMPLETE_SETUP.sql on MySQL 8.0.46.
USE `saz_house`;

SELECT VERSION() AS mysql_version, DATABASE() AS database_name,
       @@character_set_database AS database_character_set,
       @@collation_database AS database_collation;

SELECT table_name, engine, table_collation
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('roles','users','store_state','orders','order_items','contact_messages','checkout_requests','submission_throttle','admin_audit_log','media_uploads')
ORDER BY table_name;

SELECT 'required_table_count' AS check_name, COUNT(*) AS actual, 10 AS expected,
       IF(COUNT(*) = 10,'PASS','FAIL') AS result
FROM information_schema.tables
WHERE table_schema = DATABASE()
  AND table_name IN ('roles','users','store_state','orders','order_items','contact_messages','checkout_requests','submission_throttle','admin_audit_log','media_uploads');

SELECT table_name, column_name, column_type, is_nullable, column_key,
       character_set_name, collation_name
FROM information_schema.columns
WHERE table_schema = DATABASE()
  AND table_name IN ('roles','users','store_state','orders','order_items','contact_messages','checkout_requests','submission_throttle','admin_audit_log','media_uploads')
ORDER BY table_name, ordinal_position;

SELECT table_name, index_name, non_unique, seq_in_index, column_name
FROM information_schema.statistics
WHERE table_schema = DATABASE()
  AND table_name IN ('roles','users','store_state','orders','order_items','contact_messages','checkout_requests','submission_throttle','admin_audit_log','media_uploads')
ORDER BY table_name, index_name, seq_in_index;

SELECT table_name, constraint_name, column_name, referenced_table_name,
       referenced_column_name
FROM information_schema.key_column_usage
WHERE table_schema = DATABASE() AND referenced_table_name IS NOT NULL
ORDER BY table_name, constraint_name, ordinal_position;

WITH expected_foreign_keys AS (
  SELECT 'users' AS table_name, 'role_slug' AS column_name, 'roles' AS referenced_table_name, 'slug' AS referenced_column_name, 'NO ACTION' AS expected_delete_rule
  UNION ALL SELECT 'order_items', 'order_id', 'orders', 'id', 'CASCADE'
  UNION ALL SELECT 'checkout_requests', 'order_reference', 'orders', 'reference', 'RESTRICT'
  UNION ALL SELECT 'admin_audit_log', 'actor_id', 'users', 'id', 'SET NULL'
  UNION ALL SELECT 'media_uploads', 'uploaded_by', 'users', 'id', 'SET NULL'
)
SELECT expected_foreign_keys.table_name, expected_foreign_keys.column_name,
       expected_foreign_keys.referenced_table_name, expected_foreign_keys.referenced_column_name,
       expected_foreign_keys.expected_delete_rule, kcu.constraint_name,
       rc.delete_rule AS actual_delete_rule,
       IF(
         kcu.constraint_name IS NOT NULL
         AND (rc.delete_rule = expected_foreign_keys.expected_delete_rule
              OR (expected_foreign_keys.expected_delete_rule = 'NO ACTION' AND rc.delete_rule = 'RESTRICT')),
         'PASS', 'FAIL'
       ) AS result
FROM expected_foreign_keys
LEFT JOIN information_schema.key_column_usage AS kcu
  ON kcu.table_schema = DATABASE()
 AND kcu.table_name = expected_foreign_keys.table_name
 AND kcu.column_name = expected_foreign_keys.column_name
 AND kcu.referenced_table_name = expected_foreign_keys.referenced_table_name
 AND kcu.referenced_column_name = expected_foreign_keys.referenced_column_name
LEFT JOIN information_schema.referential_constraints AS rc
  ON rc.constraint_schema = kcu.constraint_schema
 AND rc.table_name = kcu.table_name
 AND rc.constraint_name = kcu.constraint_name
ORDER BY expected_foreign_keys.table_name, expected_foreign_keys.column_name;

SELECT c.table_name, c.column_name, c.column_type, c.character_set_name,
       c.collation_name,
       IF(c.character_set_name = 'utf8mb4' AND c.collation_name = 'utf8mb4_unicode_ci','PASS','FAIL') AS result
FROM information_schema.columns AS c
WHERE c.table_schema = DATABASE()
  AND (c.table_name, c.column_name) IN (('roles','slug'),('users','role_slug'),('orders','id'),('order_items','order_id'),('orders','reference'),('checkout_requests','order_reference'),('users','id'),('admin_audit_log','actor_id'),('media_uploads','uploaded_by'))
ORDER BY c.table_name, c.column_name;

SELECT COUNT(*) AS role_count, IF(COUNT(*) >= 9,'PASS','FAIL') AS result
FROM roles;
SELECT slug, name, is_protected, JSON_VALID(permissions) AS permissions_json_valid
FROM roles ORDER BY slug;
WITH required_roles AS (
  SELECT 'owner' AS slug UNION ALL SELECT 'administrator' UNION ALL SELECT 'manager'
  UNION ALL SELECT 'fulfillment' UNION ALL SELECT 'catalog-editor' UNION ALL SELECT 'support'
  UNION ALL SELECT 'marketing' UNION ALL SELECT 'analyst' UNION ALL SELECT 'customer'
)
SELECT r.slug AS required_role, IF(roles.slug IS NULL,'FAIL','PASS') AS result
FROM required_roles AS r LEFT JOIN roles ON roles.slug = r.slug
ORDER BY r.slug;

SELECT `key`, JSON_TYPE(`value`) AS json_type, JSON_VALID(`value`) AS json_valid,
       revision, updated_at
FROM store_state
ORDER BY `key`;
SELECT COUNT(*) AS required_state_count,
       IF(COUNT(*) = 7,'PASS','FAIL') AS result
FROM store_state
WHERE `key` IN ('products','product_types','coupons','settings','site_content','page_products','home_categories');
SELECT COUNT(*) AS invalid_json_or_revision_rows,
       IF(COUNT(*) = 0,'PASS','FAIL') AS result
FROM store_state
WHERE JSON_VALID(`value`) = 0 OR revision < 1;

SELECT 'store_state_key_ck' AS required_constraint, cc.check_clause,
       IF(
         tc.constraint_name = 'store_state_key_ck'
         AND LOWER(cc.check_clause) LIKE '%products%'
         AND LOWER(cc.check_clause) LIKE '%product_types%'
         AND LOWER(cc.check_clause) LIKE '%coupons%'
         AND LOWER(cc.check_clause) LIKE '%settings%'
         AND LOWER(cc.check_clause) LIKE '%site_content%'
         AND LOWER(cc.check_clause) LIKE '%page_products%'
         AND LOWER(cc.check_clause) LIKE '%home_categories%',
         'PASS', 'FAIL'
       ) AS result
FROM (SELECT 1 AS required_row) AS expected
LEFT JOIN information_schema.table_constraints AS tc
  ON tc.constraint_schema = DATABASE()
 AND tc.table_name = 'store_state'
 AND tc.constraint_name = 'store_state_key_ck'
 AND tc.constraint_type = 'CHECK'
LEFT JOIN information_schema.check_constraints AS cc
  ON cc.constraint_schema = tc.constraint_schema
 AND cc.constraint_name = tc.constraint_name
;

SELECT 'user_role_orphans' AS check_name, COUNT(*) AS actual,
       IF(COUNT(*) = 0,'PASS','FAIL') AS result
FROM users u LEFT JOIN roles r ON r.slug = u.role_slug WHERE r.slug IS NULL
UNION ALL
SELECT 'audit_actor_orphans', COUNT(*), IF(COUNT(*) = 0,'PASS','FAIL')
FROM admin_audit_log al LEFT JOIN users u ON u.id = al.actor_id
WHERE al.actor_id IS NOT NULL AND u.id IS NULL
UNION ALL
SELECT 'media_uploader_orphans', COUNT(*), IF(COUNT(*) = 0,'PASS','FAIL')
FROM media_uploads mu LEFT JOIN users u ON u.id = mu.uploaded_by
WHERE mu.uploaded_by IS NOT NULL AND u.id IS NULL
UNION ALL
SELECT 'order_item_orphans' AS check_name, COUNT(*) AS actual,
       IF(COUNT(*) = 0,'PASS','FAIL') AS result
FROM order_items oi LEFT JOIN orders o ON o.id = oi.order_id WHERE o.id IS NULL
UNION ALL
SELECT 'checkout_request_orphans', COUNT(*), IF(COUNT(*) = 0,'PASS','FAIL')
FROM checkout_requests cr LEFT JOIN orders o ON o.reference = cr.order_reference
WHERE cr.order_reference IS NOT NULL AND o.reference IS NULL;

SELECT order_id, product_id, color, size, COUNT(*) AS duplicate_count
FROM order_items GROUP BY order_id, product_id, color, size HAVING COUNT(*) > 1;

CHECK TABLE roles, users, store_state, orders, order_items, contact_messages,
            checkout_requests, submission_throttle, admin_audit_log, media_uploads;
