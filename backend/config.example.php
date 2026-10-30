<?php
// Copy to backend/config.php. Keep backend outside public_html when deploying.
return [
    'db' => ['host' => 'localhost', 'port' => 3306, 'name' => 'saz_house', 'user' => 'CHANGE_ME', 'pass' => 'CHANGE_ME'],
    'app_url' => 'https://example.com',
    // A mailbox at your domain. Configure SPF/DKIM with your hosting provider
    // before enabling password-reset delivery in production.
    'mail_from' => 'no-reply@example.com',
    'mail_from_name' => 'SAZ House',
    'password_reset_ttl_minutes' => 30,
    'session_name' => 'saz_house_session',
    // Generate with: php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"
    'throttle_pepper' => 'CHANGE_ME_TO_A_LONG_RANDOM_SECRET',
    // In the cPanel package, backend/ is a sibling of public_html/. This must
    // resolve to public_html/uploads and must not be writable outside it.
    'upload_dir' => dirname(__DIR__) . '/public_html/uploads',
    'upload_url' => '/uploads',
    // Keep this at or below PHP upload_max_filesize and post_max_size.
    'max_upload_bytes' => 5 * 1024 * 1024,
];
