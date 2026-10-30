<?php
declare(strict_types=1);

// Offline, additive importer for read-only JSON exports. It never opens a
// connection to the prior provider and never deletes either source or target.
require dirname(__DIR__) . '/lib.php';

if (PHP_SAPI !== 'cli') { fwrite(STDERR, "Run this only from the command line.\n"); exit(1); }
$directory = $argv[1] ?? '';
if (!$directory || !is_dir($directory)) { fwrite(STDERR, "Usage: php import_supabase_export.php <export-directory>\n"); exit(1); }

function exported_rows(string $directory, string $name): array {
    $file = $directory . DIRECTORY_SEPARATOR . $name . '.json';
    if (!is_file($file)) return [];
    $data = json_decode((string) file_get_contents($file), true, 512, JSON_THROW_ON_ERROR);
    return is_array($data) && array_is_list($data) ? $data : [];
}

function value_json(mixed $value): string {
    if (is_string($value)) {
        json_decode($value, true);
        if (json_last_error() === JSON_ERROR_NONE) return $value;
    }
    return json_encode($value ?? [], JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR);
}

function nullable_json(mixed $value): ?string {
    return $value === null ? null : value_json($value);
}

function exported_permissions(mixed $value): array {
    if (is_array($value)) return array_values(array_filter($value, 'is_string'));
    if (!is_string($value)) return [];
    $decoded = json_decode($value, true);
    if (is_array($decoded)) return array_values(array_filter($decoded, 'is_string'));
    if (preg_match('/^\{(.*)\}$/s', trim($value), $matches)) return array_values(array_filter(array_map('trim', str_getcsv($matches[1])), static fn(string $permission): bool => $permission !== ''));
    return [];
}

function source_role(array $profile): string {
    $role = text($profile['role'] ?? 'customer', 48);
    return $role === 'admin' ? 'owner' : ($role ?: 'customer');
}

function source_is_active(array $source, array $profile, ?string $hash): bool {
    if ($hash === null) return false;
    if (array_key_exists('is_active', $profile) && !in_array($profile['is_active'], [true, 1, '1'], true)) return false;
    $bannedUntil = database_timestamp($source['banned_until'] ?? null);
    return !$bannedUntil || strtotime($bannedUntil . ' UTC') <= time();
}

function source_user_exists(PDO $pdo, string $id): bool {
    $query = $pdo->prepare('SELECT id FROM users WHERE id=?');
    $query->execute([$id]);
    return (bool) $query->fetchColumn();
}

$counts = [
    'roles' => 0, 'state' => 0, 'orders' => 0, 'order_items' => 0,
    'messages' => 0, 'identities_active' => 0, 'identities_pending_reset' => 0,
    'identities_skipped_email_conflict' => 0, 'checkout_requests' => 0, 'audit' => 0,
];

transaction(function (PDO $pdo) use ($directory, &$counts): void {
    $roleInsert = $pdo->prepare('INSERT INTO roles(slug,name,description,permissions,is_protected) VALUES(?,?,?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name),description=VALUES(description),permissions=VALUES(permissions),is_protected=VALUES(is_protected)');
    foreach (array_merge(exported_rows($directory, 'access_roles'), exported_rows($directory, 'roles')) as $role) {
        if (!is_array($role)) continue;
        $slug = text($role['slug'] ?? '', 48);
        $name = text($role['name'] ?? '', 80);
        if (!preg_match('/^[a-z0-9][a-z0-9-]{0,47}$/', $slug) || mb_strlen($name) < 2) continue;
        $roleInsert->execute([$slug, $name, text($role['description'] ?? '', 240), value_json(exported_permissions($role['permissions'] ?? [])), !empty($role['is_protected']) ? 1 : 0]);
        $counts['roles']++;
    }

    $stateInsert = $pdo->prepare('INSERT INTO store_state(`key`,value,updated_at) VALUES(?,?,COALESCE(?,UTC_TIMESTAMP())) ON DUPLICATE KEY UPDATE value=VALUES(value),revision=revision+1,updated_at=VALUES(updated_at)');
    $validState = ['products', 'product_types', 'coupons', 'settings', 'site_content', 'page_products', 'home_categories'];
    foreach (exported_rows($directory, 'store_state') as $row) {
        if (!is_array($row) || !in_array($row['key'] ?? '', $validState, true)) continue;
        $stateInsert->execute([$row['key'], value_json($row['value'] ?? []), database_timestamp($row['updated_at'] ?? null)]);
        $counts['state']++;
    }

    $orderInsert = $pdo->prepare('INSERT INTO orders(id,reference,customer_name,phone,email,address,city,district,division,payment_method,subtotal,shipping,discount,total,coupon,status,line_items,created_at) VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,COALESCE(?,UTC_TIMESTAMP())) ON DUPLICATE KEY UPDATE customer_name=VALUES(customer_name),phone=VALUES(phone),email=VALUES(email),address=VALUES(address),city=VALUES(city),district=VALUES(district),division=VALUES(division),payment_method=VALUES(payment_method),subtotal=VALUES(subtotal),shipping=VALUES(shipping),discount=VALUES(discount),total=VALUES(total),coupon=VALUES(coupon),status=VALUES(status),line_items=VALUES(line_items)');
    $findOrderId = $pdo->prepare('SELECT id FROM orders WHERE reference=?');
    $itemInsert = $pdo->prepare('INSERT INTO order_items(order_id,product_id,name,color,size,quantity,unit_price) VALUES(?,?,?,?,?,?,?) ON DUPLICATE KEY UPDATE name=VALUES(name),quantity=VALUES(quantity),unit_price=VALUES(unit_price)');
    foreach (exported_rows($directory, 'orders') as $order) {
        if (!is_array($order) || !($reference = text($order['reference'] ?? '', 32))) continue;
        $id = preg_match('/^[0-9a-f-]{36}$/i', (string) ($order['id'] ?? '')) ? $order['id'] : uuid();
        $items = is_array($order['line_items'] ?? null) ? $order['line_items'] : (json_decode((string) ($order['line_items'] ?? '[]'), true) ?: []);
        $status = in_array($order['status'] ?? '', ['Processing', 'Shipped', 'Delivered', 'Cancelled'], true) ? $order['status'] : 'Processing';
        $orderInsert->execute([$id, $reference, text($order['customer_name'] ?? '', 100), text($order['phone'] ?? '', 30), email($order['email'] ?? null) ?: null, text($order['address'] ?? '', 500), text($order['city'] ?? '', 100) ?: null, text($order['district'] ?? '', 100) ?: null, text($order['division'] ?? '', 100) ?: null, text($order['payment_method'] ?? '', 30), (float) ($order['subtotal'] ?? 0), (float) ($order['shipping'] ?? 0), (float) ($order['discount'] ?? 0), (float) ($order['total'] ?? 0), text($order['coupon'] ?? '', 50) ?: null, $status, value_json($items), database_timestamp($order['created_at'] ?? null)]);
        $findOrderId->execute([$reference]);
        $destinationId = $findOrderId->fetchColumn();
        foreach ($items as $item) {
            if (!is_array($item)) continue;
            $itemInsert->execute([$destinationId, text($item['id'] ?? '', 100), text($item['name'] ?? '', 160), text($item['color'] ?? '', 60), text($item['size'] ?? '', 30), max(1, (int) ($item['qty'] ?? 1)), (float) ($item['price'] ?? 0)]);
            $counts['order_items']++;
        }
        $counts['orders']++;
    }

    $messageInsert = $pdo->prepare('INSERT INTO contact_messages(id,name,email,subject,message,created_at) VALUES(?,?,?,?,?,COALESCE(?,UTC_TIMESTAMP())) ON DUPLICATE KEY UPDATE name=VALUES(name),email=VALUES(email),subject=VALUES(subject),message=VALUES(message)');
    foreach (exported_rows($directory, 'contact_messages') as $message) {
        if (!is_array($message) || !($id = text($message['id'] ?? '', 100)) || !($mail = text($message['email'] ?? '', 254))) continue;
        $messageInsert->execute([$id, text($message['name'] ?? '', 100), $mail, text($message['subject'] ?? '', 160) ?: null, text($message['message'] ?? '', 4000), database_timestamp($message['created_at'] ?? null)]);
        $counts['messages']++;
    }

    $profiles = [];
    foreach (exported_rows($directory, 'profiles') as $profile) if (is_array($profile) && isset($profile['id'])) $profiles[(string) $profile['id']] = $profile;
    $findEmail = $pdo->prepare('SELECT id FROM users WHERE email=?');
    $roleExists = $pdo->prepare('SELECT slug FROM roles WHERE slug=?');
    $userInsert = $pdo->prepare('INSERT INTO users(id,email,password_hash,role_slug,is_active,created_at,last_sign_in_at) VALUES(?,?,?,?,?,COALESCE(?,UTC_TIMESTAMP()),?) ON DUPLICATE KEY UPDATE email=VALUES(email),role_slug=VALUES(role_slug),is_active=VALUES(is_active),last_sign_in_at=COALESCE(VALUES(last_sign_in_at),last_sign_in_at),password_hash=IF(VALUES(is_active)=1,VALUES(password_hash),password_hash)');
    foreach (exported_rows($directory, 'auth_users') as $source) {
        if (!is_array($source) || !preg_match('/^[0-9a-f-]{36}$/i', (string) ($source['id'] ?? '')) || !($mail = email($source['email'] ?? null))) continue;
        $id = (string) $source['id'];
        $findEmail->execute([$mail]);
        $existingEmailId = $findEmail->fetchColumn();
        if ($existingEmailId !== false && $existingEmailId !== $id) { $counts['identities_skipped_email_conflict']++; continue; }
        $profile = is_array($profiles[$id] ?? null) ? $profiles[$id] : [];
        $role = source_role($profile);
        $roleExists->execute([$role]);
        if (!$roleExists->fetchColumn()) $role = 'customer';
        $hash = portable_password_hash($source['encrypted_password'] ?? null) ?? portable_password_hash($source['password_hash'] ?? null);
        $active = source_is_active($source, $profile, $hash);
        $userInsert->execute([$id, $mail, $hash ?? password_hash(bin2hex(random_bytes(32)), PASSWORD_DEFAULT), $role, $active ? 1 : 0, database_timestamp($source['created_at'] ?? null), database_timestamp($source['last_sign_in_at'] ?? null)]);
        $counts[$active ? 'identities_active' : 'identities_pending_reset']++;
    }

    $orderExists = $pdo->prepare('SELECT reference FROM orders WHERE reference=?');
    $checkoutInsert = $pdo->prepare('INSERT INTO checkout_requests(idempotency_key,request_hash,response,order_reference,created_at) VALUES(?,?,?,?,COALESCE(?,UTC_TIMESTAMP())) ON DUPLICATE KEY UPDATE request_hash=VALUES(request_hash),response=VALUES(response),order_reference=VALUES(order_reference)');
    foreach (exported_rows($directory, 'checkout_requests') as $request) {
        if (!is_array($request)) continue;
        $key = text($request['idempotency_key'] ?? '', 128);
        $hash = text($request['request_hash'] ?? '', 64);
        $reference = text($request['order_reference'] ?? '', 32) ?: null;
        if (!preg_match('/^[A-Za-z0-9_-]{16,128}$/', $key) || !preg_match('/^[a-f0-9]{64}$/', $hash)) continue;
        if ($reference !== null) { $orderExists->execute([$reference]); if (!$orderExists->fetchColumn()) continue; }
        $checkoutInsert->execute([$key, $hash, nullable_json($request['response'] ?? null), $reference, database_timestamp($request['created_at'] ?? null)]);
        $counts['checkout_requests']++;
    }

    $auditInsert = $pdo->prepare('INSERT INTO admin_audit_log(id,actor_id,action,target_type,target_id,details,created_at) VALUES(?,?,?,?,?,?,COALESCE(?,UTC_TIMESTAMP())) ON DUPLICATE KEY UPDATE actor_id=VALUES(actor_id),action=VALUES(action),target_type=VALUES(target_type),target_id=VALUES(target_id),details=VALUES(details)');
    foreach (exported_rows($directory, 'admin_audit_log') as $entry) {
        if (!is_array($entry) || !($action = text($entry['action'] ?? '', 80)) || !($targetType = text($entry['target_type'] ?? '', 40))) continue;
        $id = preg_match('/^[0-9a-f-]{36}$/i', (string) ($entry['id'] ?? '')) ? $entry['id'] : uuid();
        $actor = preg_match('/^[0-9a-f-]{36}$/i', (string) ($entry['actor_id'] ?? '')) && source_user_exists($pdo, (string) $entry['actor_id']) ? $entry['actor_id'] : null;
        $auditInsert->execute([$id, $actor, $action, $targetType, text($entry['target_id'] ?? '', 100) ?: null, value_json($entry['details'] ?? []), database_timestamp($entry['created_at'] ?? null)]);
        $counts['audit']++;
    }
});

echo 'Imported ' . json_encode($counts, JSON_UNESCAPED_SLASHES) . PHP_EOL;
