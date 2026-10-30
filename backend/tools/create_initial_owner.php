<?php
declare(strict_types=1);

// Run once from a protected shell after importing schema.mysql.sql.
require dirname(__DIR__) . '/lib.php';

if (PHP_SAPI !== 'cli') { fwrite(STDERR, "Run this only from the command line.\n"); exit(1); }
if ((int) db()->query('SELECT COUNT(*) FROM users')->fetchColumn() > 0) { fwrite(STDERR, "A user already exists; use the admin panel instead.\n"); exit(1); }
fwrite(STDOUT, 'Owner email: ');
$email = email(trim((string) fgets(STDIN)));
fwrite(STDOUT, 'Owner password (input is visible): ');
$password = trim((string) fgets(STDIN));
if (!$email) { fwrite(STDERR, "A valid email is required.\n"); exit(1); }
if (strlen($password) < 12 || strlen($password) > 128 || !preg_match('/[a-z]/', $password) || !preg_match('/[A-Z]/', $password) || !preg_match('/\d/', $password)) {
    fwrite(STDERR, "Use 12-128 characters with uppercase, lowercase, and a number.\n");
    exit(1);
}
$id = uuid();
db()->prepare("INSERT INTO users(id,email,password_hash,role_slug,is_active) VALUES(?,?,?,'owner',1)")->execute([$id, $email, password_hash($password, PASSWORD_DEFAULT)]);
fwrite(STDOUT, "Initial Owner created: $email\n");
