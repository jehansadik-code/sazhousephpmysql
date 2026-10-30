import assert from 'node:assert/strict';
import { access, readFile } from 'node:fs/promises';
import test from 'node:test';

const read = file => readFile(file, 'utf8');
test('all storefront documents load the PHP API client, not the Supabase CDN', async () => {
  for (const file of ['index.html','about.html','account.html','admin.html','cart.html','checkout.html','contact.html','faq.html','product.html','search.html','shop.html','success.html']) {
    const html = await read(`frontend/${file}`);
    assert.match(html, /assets\/js\/api-client\.js/);
    assert.doesNotMatch(html, /cdn\.jsdelivr\.net\/npm\/@supabase/);
  }
});
test('PHP backend contains transactional checkout, CSRF, session and prepared-statement protections', async () => {
  const source = await read('frontend/api/index.php');
  const lib = await read('backend/lib.php');
  assert.match(lib, /beginTransaction\(\)/);
  assert.match(source, /FOR UPDATE/);
  assert.match(source, /checkout_requests/);
  assert.match(source, /password_hash/);
  assert.match(lib, /require_csrf/);
  assert.match(lib, /prepare\(/);
  assert.match(source, /function login\(\): never \{\s+require_csrf\(\);/);
  assert.match(source, /function contact\(\): never \{[\s\S]*?require_csrf\(\);/);
  assert.match(source, /function checkout\(\): never \{[\s\S]*?require_csrf\(\);/);
  assert.match(source, /Store data changed\. Refresh and try again\./);
  assert.match(lib, /safe_public_asset/);
  assert.match(lib, /safe_store_link/);
  assert.match(lib, /preg_match\('@\^\[A-Za-z0-9_-\]/);
  assert.match(lib, /function trusted_image_metadata/);
  assert.match(lib, /getimagesize/);
  assert.match(lib, /class_exists\('finfo'\)/);
  assert.match(lib, /revision=revision\+1/);
});
test('the disposable PDO test uses the same MySQL connection contract as backend/lib.php', async () => {
  const pdoTest = await read('tests/pdo-mysql-contract.php');
  assert.match(pdoTest, /mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4/);
  assert.match(pdoTest, /PDO::ATTR_EMULATE_PREPARES\s*=>\s*false/);
  assert.match(pdoTest, /Expected 10 SAZ tables/);
  assert.doesNotMatch(pdoTest, /password\s*=\s*['"][^'"]+/i);
});
test('the active project contains no Supabase or Vercel runtime dependency', async () => {
  const readme = await read('README.md');
  const client = await read('frontend/assets/js/api-client.js');
  const packageJson = await read('package.json');
  assert.doesNotMatch(readme, /Supabase|Vercel/i);
  assert.doesNotMatch(client, /SAZ_SUPABASE|supabase/i);
  assert.doesNotMatch(packageJson, /supabase/i);
});
test('obsolete local runtime directories and deployment configuration are absent', async () => {
  for (const path of ['supabase', 'node_modules', '.audit-function-download', 'vercel.json', '_headers', 'frontend/assets/js/supabase-client.js', 'frontend/assets/js/supabase-config.js']) {
    await assert.rejects(access(path));
  }
});
test('MySQL schema preserves evidenced state and excludes PostgreSQL-only runtime SQL', async () => {
  const schema = await read('database/schema.mysql.sql');
  for (const table of ['roles', 'users', 'store_state', 'orders', 'order_items', 'contact_messages', 'checkout_requests', 'submission_throttle', 'admin_audit_log', 'media_uploads']) {
    assert.match(schema, new RegExp(`CREATE TABLE ${table}\\b`, 'i'));
  }
  assert.match(schema, /CHECK \(`key` IN \('products','product_types','coupons','settings','site_content','page_products','home_categories'\)\)/);
  assert.match(schema, /revision BIGINT UNSIGNED NOT NULL DEFAULT 1/);
  assert.doesNotMatch(schema, /TINYINT\(1\)/i);
  assert.match(schema, /CREATE TABLE roles[\s\S]*?COLLATE=utf8mb4_unicode_ci/i);
  assert.match(schema, /CREATE TABLE users[\s\S]*?COLLATE=utf8mb4_unicode_ci/i);
  for (const key of ['products', 'product_types', 'coupons', 'settings', 'site_content', 'page_products', 'home_categories']) {
    assert.match(schema, new RegExp(`\\('${key.replace('_', '_')}', JSON_`, 'i'));
  }
  assert.doesNotMatch(schema, /\bjsonb\b|CREATE EXTENSION|ENABLE ROW LEVEL SECURITY|SECURITY DEFINER/i);
});
test('state revision upgrade is additive and replay-safe on supported database engines', async () => {
  const migration = await read('database/migrations/003_store_state_revisions.sql');
  assert.match(migration, /information_schema\.columns/);
  assert.match(migration, /PREPARE saz_revision_stmt FROM @saz_revision_sql/);
  assert.match(migration, /ADD COLUMN `revision` BIGINT UNSIGNED NOT NULL DEFAULT 1/i);
  assert.doesNotMatch(migration, /ADD COLUMN IF NOT EXISTS/i);
  assert.doesNotMatch(migration, /\bDROP\b|\bDELETE\b|\bTRUNCATE\b/i);
});
test('missing required JSON state can be seeded without overwriting existing records', async () => {
  const migration = await read('database/migrations/004_seed_required_store_state.sql');
  assert.match(migration, /INSERT IGNORE INTO store_state/i);
  assert.doesNotMatch(migration, /\bUPDATE\b|\bDELETE\b|\bTRUNCATE\b|\bDROP\b/i);
});
test('complete Workbench setup repairs the documented collation interruption without destructive SQL', async () => {
  const setup = await read('database/SAZ_HOUSE_COMPLETE_SETUP.sql');
  const verify = await read('database/SAZ_HOUSE_VERIFY.sql');
  for (const table of ['roles', 'users', 'store_state', 'orders', 'order_items', 'contact_messages', 'checkout_requests', 'submission_throttle', 'admin_audit_log', 'media_uploads']) {
    assert.match(setup, new RegExp('CREATE TABLE IF NOT EXISTS `' + table + '`', 'i'));
  }
  assert.match(setup, /ALTER TABLE `roles` MODIFY COLUMN `slug` VARCHAR\(48\) CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci NOT NULL/i);
  assert.match(setup, /@saz_users_role_too_long/);
  assert.match(setup, /constraint_name='store_state_key_ck'/);
  assert.match(setup, /INSERT IGNORE INTO `roles`/i);
  assert.match(setup, /INSERT IGNORE INTO `store_state`/i);
  assert.doesNotMatch(setup, /TINYINT\(1\)/i);
  assert.doesNotMatch(setup, /^\s*DROP\s+(?:DATABASE|TABLE)\b|^\s*TRUNCATE\b|^\s*DELETE\s+FROM\b|^\s*REPLACE\s+INTO\b|^\s*UPDATE\s+/im);
  assert.match(verify, /required_table_count/);
  assert.match(verify, /JSON_VALID/);
  assert.match(verify, /expected_foreign_keys/);
  assert.match(verify, /required_constraint/);
  assert.match(verify, /CHECK TABLE/);
});
test('partial-install fixture reproduces only the documented roles collation interruption', async () => {
  const fixture = await read('tests/fixtures/mysql-roles-only-collation-mismatch.sql');
  assert.match(fixture, /CREATE TABLE `roles`/);
  assert.match(fixture, /INSERT INTO `roles`/);
  assert.match(fixture, /COLLATE utf8mb4_0900_ai_ci/);
  assert.doesNotMatch(fixture, /\busers\b/i);
});
test('migration tools preserve source boundaries and include historical records and media mapping', async () => {
  const importer = await read('backend/tools/import_supabase_export.php');
  const media = await read('backend/tools/import_media_manifest.php');
  const reset = await read('backend/tools/set_user_password.php');
  assert.match(importer, /admin_audit_log/);
  assert.match(importer, /checkout_requests/);
  assert.match(importer, /portable_password_hash/);
  assert.match(media, /media_manifest\.json/);
  assert.match(media, /no network code/);
  assert.match(reset, /is_active=1/);
  assert.doesNotMatch(importer, /curl_|https?:\/\//i);
});
test('cPanel configuration and beginner guide use the package sibling-directory layout', async () => {
  const config = await read('backend/config.example.php');
  const guide = await read('docs/CPANEL_BEGINNER_DEPLOYMENT.md');
  assert.match(config, /dirname\(__DIR__\) \. '\/public_html\/uploads'/);
  assert.match(guide, /schema\.mysql\.sql/);
  assert.match(guide, /Do \*\*not\*\* also import `001`, `002`, `003`, or `004`/);
  assert.match(guide, /open_basedir/);
  assert.match(guide, /Never use `777`/);
});
test('referenced local storefront images exist and browser uploads use the PHP API', async () => {
  const app = await read('frontend/assets/js/app.js');
  const security = await read('frontend/assets/js/security.js');
  const client = await read('frontend/assets/js/api-client.js');
  const references = [...app.matchAll(/assets\/images\/[A-Za-z0-9_./-]+\.(?:png|jpe?g|webp|gif|svg)/gi)].map(match => match[0]);
  for (const reference of new Set(references)) await access(`frontend/${reference}`);
  assert.match(security, /uploadImages/);
  assert.match(security, /X-CSRF-Token/);
  assert.match(client, /getCsrfToken/);
  assert.match(client, /stateVersions/);
  assert.match(app, /managedStateKeys/);
  assert.match(app, /commitAdminState/);
  assert.doesNotMatch(app, /toDataURL/);
});
