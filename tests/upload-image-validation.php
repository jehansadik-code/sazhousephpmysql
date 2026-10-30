<?php
declare(strict_types=1);

require __DIR__ . '/../backend/lib.php';

$metadata = trusted_image_metadata(__DIR__ . '/../frontend/assets/images/brand/logo.png');
if (!is_array($metadata) || $metadata['mime'] !== 'image/png' || $metadata['extension'] !== 'png') {
    throw new RuntimeException('Expected the known PNG asset to pass content-based upload validation.');
}
echo "Image upload metadata validation: PASS\n";
