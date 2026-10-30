<?php
declare(strict_types=1);

// Imports an operator-downloaded media set into the new deployment. The tool
// deliberately has no network code: the old storage remains read-only and the
// manifest maps each real source URL to a local downloaded raster image.
require dirname(__DIR__) . '/lib.php';

if (PHP_SAPI !== 'cli') { fwrite(STDERR, "Run this only from the command line.\n"); exit(1); }
$rootArgument = $argv[1] ?? '';
if (!$rootArgument || !is_dir($rootArgument) || !($sourceRoot = realpath($rootArgument))) { fwrite(STDERR, "Usage: php import_media_manifest.php <download-directory>\n"); exit(1); }
$manifestPath = $sourceRoot . DIRECTORY_SEPARATOR . 'media_manifest.json';
if (!is_file($manifestPath)) { fwrite(STDERR, "Expected $manifestPath\n"); exit(1); }
$manifest = json_decode((string) file_get_contents($manifestPath), true, 512, JSON_THROW_ON_ERROR);
if (!is_array($manifest) || !array_is_list($manifest) || count($manifest) > 10000) { fwrite(STDERR, "media_manifest.json must be an array with at most 10,000 entries.\n"); exit(1); }

$extensions = ['image/jpeg' => 'jpg', 'image/png' => 'png', 'image/webp' => 'webp'];
$limit = (int) (cfg()['max_upload_bytes'] ?? 5242880);
$uploadRoot = rtrim((string) cfg()['upload_dir'], DIRECTORY_SEPARATOR);
$uploadUrl = trim((string) cfg()['upload_url'], '/');
$targetDirectory = $uploadRoot . DIRECTORY_SEPARATOR . 'migrated';
if (!is_dir($targetDirectory) && !mkdir($targetDirectory, 0755, true) && !is_dir($targetDirectory)) throw new RuntimeException('Upload storage is unavailable.');

$map = [];
$records = [];
$finfo = new finfo(FILEINFO_MIME_TYPE);
foreach ($manifest as $entry) {
    if (!is_array($entry) || !is_string($entry['source'] ?? null) || !is_string($entry['file'] ?? null) || !safe_public_asset($entry['source'])) throw new RuntimeException('Each manifest entry needs a safe source URL and local file path.');
    $source = trim($entry['source']);
    if ($source === '' || isset($map[$source])) throw new RuntimeException('Manifest source URLs must be unique.');
    $candidate = realpath($sourceRoot . DIRECTORY_SEPARATOR . $entry['file']);
    if ($candidate === false || !is_file($candidate) || !str_starts_with($candidate, $sourceRoot . DIRECTORY_SEPARATOR)) throw new RuntimeException('A manifest file is outside the download directory or does not exist.');
    $size = filesize($candidate);
    $info = @getimagesize($candidate);
    $mime = $finfo->file($candidate);
    if ($size === false || $size < 1 || $size > $limit || !$info || !isset($extensions[$mime]) || (int) $info[0] < 1 || (int) $info[1] < 1 || ((int) $info[0] * (int) $info[1]) > 40000000) throw new RuntimeException("Invalid image in manifest: {$entry['file']}");
    $name = bin2hex(random_bytes(20)) . '.' . $extensions[$mime];
    $destination = $targetDirectory . DIRECTORY_SEPARATOR . $name;
    if (!copy($candidate, $destination)) throw new RuntimeException('Could not copy a media file into upload storage.');
    @chmod($destination, 0644);
    $relative = $uploadUrl . '/migrated/' . $name;
    $map[$source] = '/' . $relative;
    $records[] = ['name' => $name, 'path' => $relative, 'mime' => $mime, 'size' => $size];
}

function replace_manifest_urls(mixed $value, array $map, int &$changes): mixed {
    if (is_string($value) && isset($map[$value])) { $changes++; return $map[$value]; }
    if (!is_array($value)) return $value;
    foreach ($value as $key => $item) $value[$key] = replace_manifest_urls($item, $map, $changes);
    return $value;
}

$replacements = 0;
transaction(function (PDO $pdo) use ($records, $map, &$replacements): void {
    $mediaInsert = $pdo->prepare('INSERT INTO media_uploads(id,stored_name,relative_path,mime_type,byte_size,uploaded_by) VALUES(?,?,?,?,?,NULL)');
    foreach ($records as $record) $mediaInsert->execute([uuid(), $record['name'], $record['path'], $record['mime'], $record['size']]);
    $rows = $pdo->query('SELECT `key`,value FROM store_state FOR UPDATE')->fetchAll();
    $stateUpdate = $pdo->prepare('UPDATE store_state SET value=?,revision=revision+1,updated_at=UTC_TIMESTAMP() WHERE `key`=?');
    foreach ($rows as $row) {
        $value = json_decode((string) $row['value'], true, 512, JSON_THROW_ON_ERROR);
        $changed = 0;
        $next = replace_manifest_urls($value, $map, $changed);
        if ($changed > 0) {
            $stateUpdate->execute([json_encode($next, JSON_UNESCAPED_UNICODE | JSON_THROW_ON_ERROR), $row['key']]);
            $replacements += $changed;
        }
    }
    audit(null, 'media.migrated', 'store_state', null, ['files' => count($records), 'replacements' => $replacements]);
});

echo 'Imported ' . count($records) . " media files and rewrote $replacements state URLs.\n";
