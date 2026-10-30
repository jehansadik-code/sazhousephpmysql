<?php
declare(strict_types=1);

// Emergency/migration-only CLI helper for an existing identity. It never
// touches the prior system and records the destination-side activation.
require dirname(__DIR__) . '/lib.php';

if (PHP_SAPI !== 'cli') { fwrite(STDERR, "Run this only from the command line.\n"); exit(1); }
if (isset($argv[1])) $emailAddress = email($argv[1]);
else { fwrite(STDOUT, 'Email address: '); $emailAddress = email(trim((string) fgets(STDIN))); }
if (!$emailAddress) { fwrite(STDERR, "Enter a valid email address.\n"); exit(1); }
fwrite(STDOUT, 'New password (input is visible): ');
$password = trim((string) fgets(STDIN));
if (!is_string($password) || strlen($password) < 12 || strlen($password) > 128 || !preg_match('/[a-z]/', $password) || !preg_match('/[A-Z]/', $password) || !preg_match('/\d/', $password)) {
    fwrite(STDERR, "Use 12-128 characters with uppercase, lowercase, and a number.\n");
    exit(1);
}

transaction(function (PDO $pdo) use ($emailAddress, $password): void {
    $query = $pdo->prepare('SELECT id FROM users WHERE email=? FOR UPDATE');
    $query->execute([$emailAddress]);
    $user = $query->fetch();
    if (!$user) throw new RuntimeException('No imported identity exists for that email.');
    $pdo->prepare('UPDATE users SET password_hash=?,is_active=1 WHERE id=?')->execute([password_hash($password, PASSWORD_DEFAULT), $user['id']]);
    audit(null, 'identity.password_activated', 'user', (string) $user['id'], ['via' => 'cli']);
});

echo "Password updated and identity activated.\n";
