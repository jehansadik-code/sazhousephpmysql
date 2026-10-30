<?php
$config = require __DIR__ . '/backend/config.php';
$db = $config['db'];

try {
    $pdo = new PDO(
        "mysql:host={$db['host']};port={$db['port']};dbname={$db['name']};charset=utf8mb4",
        $db['user'],
        $db['pass']
    );
    echo "Database connected successfully!\n";
} catch (PDOException $e) {
    echo "Database connection failed. Check your credentials and MySQL service.\n";
    exit(1);
}
