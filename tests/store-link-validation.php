<?php
declare(strict_types=1);

require __DIR__ . '/../backend/lib.php';

foreach (['shop.html', 'product.html?id=hoodie-7832', 'shop.html?category=T-Shirts'] as $link) {
    if (!safe_store_link($link)) throw new RuntimeException("Expected a valid storefront link: $link");
}
foreach (['javascript:alert(1)', '../admin.html', 'https://user:pass@example.com/'] as $link) {
    if (safe_store_link($link)) throw new RuntimeException("Expected an unsafe storefront link to be rejected: $link");
}
echo "Store link validation: PASS\n";
