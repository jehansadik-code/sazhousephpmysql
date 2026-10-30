<?php
declare(strict_types=1);

const SAZ_MAX_JSON_BYTES = 1048576;

function cfg(): array {
    static $config = null;
    if ($config !== null) return $config;
    $file = __DIR__ . '/config.php';
    if (!is_file($file)) throw new RuntimeException('Server configuration is unavailable.');
    return $config = require $file;
}

function db(): PDO {
    static $pdo = null;
    if ($pdo instanceof PDO) return $pdo;
    $db = cfg()['db'];
    $dsn = sprintf('mysql:host=%s;port=%d;dbname=%s;charset=utf8mb4', $db['host'], (int) $db['port'], $db['name']);
    return $pdo = new PDO($dsn, $db['user'], $db['pass'], [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_EMULATE_PREPARES => false,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
}

function uuid(): string {
    $bytes = random_bytes(16);
    $bytes[6] = chr((ord($bytes[6]) & 0x0f) | 0x40);
    $bytes[8] = chr((ord($bytes[8]) & 0x3f) | 0x80);
    return vsprintf('%s%s-%s-%s-%s-%s%s%s', str_split(bin2hex($bytes), 4));
}

function api_headers(): void {
    header('Content-Type: application/json; charset=utf-8');
    header('Cache-Control: no-store, private');
    header('X-Content-Type-Options: nosniff');
    header('Referrer-Policy: same-origin');
}

function out(array $payload, int $status = 200): never {
    api_headers();
    http_response_code($status);
    echo json_encode($payload, JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    exit;
}

function fail(string $message, int $status = 400): never { out(['error' => $message], $status); }

function request_body(): array {
    if ((int) ($_SERVER['CONTENT_LENGTH'] ?? 0) > SAZ_MAX_JSON_BYTES) fail('Request is too large.', 413);
    try { $body = json_decode(file_get_contents('php://input'), true, 512, JSON_THROW_ON_ERROR); }
    catch (JsonException) { fail('Invalid request.', 400); }
    if (!is_array($body)) fail('Invalid request.', 400);
    return $body;
}

function text(mixed $value, int $max): string { return is_string($value) ? mb_substr(trim($value), 0, $max) : ''; }
function email(mixed $value): string { $value = strtolower(text($value, 254)); return filter_var($value, FILTER_VALIDATE_EMAIL) ? $value : ''; }
function valid_id(string $value): bool { return (bool) preg_match('/^[A-Za-z0-9_-]{1,128}$/', $value); }
function valid_nonnegative_integer(mixed $value): bool {
    return (is_int($value) && $value >= 0) || (is_string($value) && preg_match('/^\d+$/', $value));
}

// Persisted storefront data is rendered into URLs by the existing frontend.
// Accept the original relative asset conventions and normal HTTP(S) URLs, but
// never persist executable/data URLs, traversal paths, credentials, or controls.
function safe_public_asset(mixed $value, int $maxLength = 2048): bool {
    if (!is_string($value)) return false;
    $value = trim($value);
    if ($value === '') return true;
    if (strlen($value) > $maxLength || preg_match('/[\x00-\x1F\x7F]/', $value) || str_contains($value, '\\') || str_contains($value, '..')) return false;
    if (preg_match('#^/?(?:assets|uploads|videos)/[A-Za-z0-9._~/%+\-]+$#', $value)) return true;
    if (preg_match('#^[A-Za-z0-9._-]+\.(?:jpe?g|png|webp|gif|mp4|webm|svg)$#i', $value)) return true;
    $parts = parse_url($value);
    return is_array($parts)
        && isset($parts['scheme'], $parts['host'])
        && in_array(strtolower((string) $parts['scheme']), ['http', 'https'], true)
        && !isset($parts['user'], $parts['pass']);
}

function safe_store_link(mixed $value, int $maxLength = 2048): bool {
    if (!is_string($value)) return false;
    $value = trim($value);
    if ($value === '') return true;
    if (safe_public_asset($value, $maxLength) && preg_match('#^https?://#i', $value)) return true;
    return strlen($value) <= $maxLength
        && (bool) preg_match('@^[A-Za-z0-9_-]+\.html(?:[?#][A-Za-z0-9._~!$&\'()*+,;=:%/?-]*)?$@', $value);
}

/**
 * Returns trusted image metadata from file contents, or null when the upload
 * is not an allowed image. getimagesize() is available in the PHP core and is
 * the secure fallback for local/cPanel installations without fileinfo.
 */
function trusted_image_metadata(string $path): ?array {
    $info = @getimagesize($path);
    if (!is_array($info)) return null;
    $width = (int) ($info[0] ?? 0);
    $height = (int) ($info[1] ?? 0);
    $mime = $info['mime'] ?? null;
    $extensions = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
    if ($width < 1 || $height < 1 || ($width * $height) > 40000000 || !is_string($mime) || !isset($extensions[$mime])) return null;

    // When fileinfo is enabled, require its independent content check to agree.
    // When it is not enabled, getimagesize() still validates the image header.
    if (class_exists('finfo')) {
        try { $detected = (new finfo(FILEINFO_MIME_TYPE))->file($path); }
        catch (Throwable) { return null; }
        if (!is_string($detected) || !hash_equals($mime, $detected)) return null;
    }
    return ['mime' => $mime, 'extension' => $extensions[$mime], 'width' => $width, 'height' => $height];
}

// Supabase Auth exports may contain a bcrypt hash. PHP can verify bcrypt
// directly, so only a strictly shaped bcrypt value is eligible for import.
function portable_password_hash(mixed $value): ?string {
    return is_string($value) && preg_match('/^\$2[aby]\$\d{2}\$[.\/A-Za-z0-9]{53}$/', $value) ? $value : null;
}

function database_timestamp(mixed $value): ?string {
    if (!is_string($value) || trim($value) === '') return null;
    try { return (new DateTimeImmutable($value))->setTimezone(new DateTimeZone('UTC'))->format('Y-m-d H:i:s'); }
    catch (Throwable) { return null; }
}

function strong_password(mixed $value): string {
    if (!is_string($value) || strlen($value) < 12 || strlen($value) > 128 || !preg_match('/[a-z]/', $value) || !preg_match('/[A-Z]/', $value) || !preg_match('/\d/', $value)) {
        fail('Use 12-128 characters with uppercase, lowercase, and a number.');
    }
    return $value;
}

function password_reset_link(string $selector, string $token): string {
    $base = rtrim((string) (cfg()['app_url'] ?? ''), '/');
    if (!filter_var($base, FILTER_VALIDATE_URL) || !preg_match('#^https?://#i', $base)) {
        throw new RuntimeException('Password-reset URL is not configured.');
    }
    // The token is deliberately placed after # so it is never sent in an HTTP
    // request, web-server access log, or Referer header.
    return $base . '/reset-password.html#selector=' . rawurlencode($selector) . '&token=' . rawurlencode($token);
}

function send_password_reset_email(string $recipient, string $selector, string $token): bool {
    $from = trim((string) (cfg()['mail_from'] ?? ''));
    $name = trim((string) (cfg()['mail_from_name'] ?? 'SAZ House'));
    if (!filter_var($from, FILTER_VALIDATE_EMAIL) || preg_match('/[\r\n]/', $name)) return false;
    $link = password_reset_link($selector, $token);
    $subject = 'Reset your SAZ House password';
    $message = "A password reset was requested for your SAZ House account.\n\n"
        . "Open this one-time link within " . max(1, (int) (cfg()['password_reset_ttl_minutes'] ?? 30)) . " minutes:\n"
        . $link . "\n\nIf you did not request this, you can ignore this email.";
    $headers = 'From: ' . $name . ' <' . $from . ">\r\n"
        . "Content-Type: text/plain; charset=UTF-8\r\n"
        . "X-Content-Type-Options: nosniff";
    return @mail($recipient, $subject, $message, $headers);
}

function session_start_secure(): void {
    if (session_status() === PHP_SESSION_ACTIVE) return;
    $secure = (!empty($_SERVER['HTTPS']) && $_SERVER['HTTPS'] !== 'off') || (($_SERVER['HTTP_X_FORWARDED_PROTO'] ?? '') === 'https');
    session_name(cfg()['session_name']);
    session_set_cookie_params(['lifetime' => 0, 'path' => '/', 'secure' => $secure, 'httponly' => true, 'samesite' => 'Lax']);
    session_start();
}

function csrf(): string { session_start_secure(); return $_SESSION['csrf'] ??= bin2hex(random_bytes(32)); }
function require_csrf(): void { session_start_secure(); $token = $_SERVER['HTTP_X_CSRF_TOKEN'] ?? ''; if (!is_string($token) || !hash_equals($_SESSION['csrf'] ?? '', $token)) fail('Invalid security token.', 403); }

function current_user(): ?array {
    session_start_secure();
    $id = $_SESSION['uid'] ?? null;
    if (!is_string($id) || !preg_match('/^[0-9a-f-]{36}$/i', $id)) return null;
    $query = db()->prepare('SELECT u.id,u.email,u.role_slug,u.is_active,r.name,r.permissions,r.is_protected FROM users u JOIN roles r ON r.slug=u.role_slug WHERE u.id=?');
    $query->execute([$id]);
    $user = $query->fetch();
    return $user && (bool) $user['is_active'] ? $user : null;
}

function permissions(?array $user): array { $values = $user ? json_decode((string) $user['permissions'], true) : []; return is_array($values) ? $values : []; }
function can(string $permission): bool { $values = permissions(current_user()); return in_array('*', $values, true) || in_array($permission, $values, true); }
function require_permission(string $permission): array { $user = current_user(); if (!$user || !can($permission)) fail('You do not have permission to perform this action.', 403); return $user; }

function user_summary(?array $user): ?array {
    if (!$user) return null;
    return ['id' => $user['id'], 'email' => $user['email'], 'role' => ['slug' => $user['role_slug'], 'name' => $user['name'], 'permissions' => permissions($user), 'is_protected' => (bool) $user['is_protected']]];
}

function audit(?string $actorId, string $action, string $targetType, ?string $targetId, array $details = []): void {
    $query = db()->prepare('INSERT INTO admin_audit_log(id,actor_id,action,target_type,target_id,details) VALUES(?,?,?,?,?,?)');
    $query->execute([uuid(), $actorId, $action, $targetType, $targetId, json_encode($details, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR)]);
}

function state_record(string $key, bool $forUpdate = false): ?array {
    $query = db()->prepare('SELECT value,revision FROM store_state WHERE `key`=?' . ($forUpdate ? ' FOR UPDATE' : ''));
    $query->execute([$key]);
    $record = $query->fetch();
    return $record === false ? null : ['value' => json_decode((string) $record['value'], true), 'revision' => (int) $record['revision']];
}

function state(string $key, bool $forUpdate = false): mixed {
    $record = state_record($key, $forUpdate);
    return $record['value'] ?? null;
}

function persist_state(string $key, mixed $value): int {
    $encoded = json_encode($value, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
    $query = db()->prepare('INSERT INTO store_state(`key`,value,revision) VALUES(?,?,1) ON DUPLICATE KEY UPDATE value=VALUES(value),revision=revision+1,updated_at=UTC_TIMESTAMP()');
    $query->execute([$key, $encoded]);
    $revision = db()->prepare('SELECT revision FROM store_state WHERE `key`=?');
    $revision->execute([$key]);
    return (int) $revision->fetchColumn();
}

function transaction(callable $callback): mixed {
    $pdo = db();
    $pdo->beginTransaction();
    try { $result = $callback($pdo); $pdo->commit(); return $result; }
    catch (Throwable $error) { if ($pdo->inTransaction()) $pdo->rollBack(); throw $error; }
}

function safe_error(Throwable $error): array {
    $message = $error->getMessage();
    if (str_contains($message, 'no longer available') || str_contains($message, 'Insufficient stock') || str_contains($message, 'Store data changed') || str_contains($message, 'cannot be removed') || str_contains($message, 'Historical order variants')) return [$message, 409];
    $allowed = ['Please check your checkout details and try again.', 'Choose a valid payment method.', 'That payment method is not available. Please choose another.', 'Select a delivery area.', 'Coupon is invalid.', 'This submission conflicts with an earlier request.', 'Your cart contains an invalid item.', 'A product is no longer available.', 'Store data changed. Refresh and try again.', 'A product used by an order cannot be removed. Mark it inactive instead.', 'Historical order variants must remain available for inventory reconciliation.'];
    return [in_array($message, $allowed, true) ? $message : 'Unable to process this request right now.', 400];
}
