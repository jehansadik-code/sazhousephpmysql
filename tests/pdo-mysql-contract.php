<?php
declare(strict_types=1);

$host = getenv('SAZ_TEST_HOST');
$port = getenv('SAZ_TEST_PORT');
$name = getenv('SAZ_TEST_NAME');
$user = getenv('SAZ_TEST_USER');
$password = getenv('SAZ_TEST_PASSWORD');
if (!is_string($host) || !is_string($port) || !is_string($name) || !is_string($user) || !is_string($password) || $host === '' || $port === '' || $name === '' || $user === '') {
    throw new RuntimeException('Missing disposable MySQL PDO test environment values.');
}

// This is deliberately the same PDO DSN/options contract as backend/lib.php.
$pdo = new PDO(
    sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $host, (int) $port, $name),
    $user,
    $password,
    [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]
);
$count = (int) $pdo->query('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE()')->fetchColumn();
if ($count !== 10) throw new RuntimeException("Expected 10 SAZ tables; found $count.");
echo "PHP PDO DSN integration: PASS\n";
