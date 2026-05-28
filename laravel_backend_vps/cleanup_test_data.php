<?php
/**
 * Cleanup script for old test groups and projects.
 *
 * Usage (on VPS):
 *   php cleanup_test_data.php              # dry-run: list what would be deleted
 *   php cleanup_test_data.php --execute    # actually delete
 *   php cleanup_test_data.php --all        # delete ALL groups and projects (careful!)
 *
 * This script bypasses permission checks — use with caution.
 */

$usage = "Usage: php cleanup_test_data.php [--execute] [--all]\n";

$isDryRun = !in_array('--execute', $argv, true);
$deleteAll = in_array('--all', $argv, true);

// Bootstrap Laravel minimally for DB access
require __DIR__ . '/vendor/autoload.php';
$app = require_once __DIR__ . '/bootstrap/app.php';
$app->make(\Illuminate\Contracts\Console\Kernel::class)->bootstrap();

use Illuminate\Support\Facades\DB;

$repo = new \App\Domain\Sync\SyncRepository();

echo $isDryRun ? "=== DRY RUN (add --execute to actually delete) ===\n\n" : "=== EXECUTING DELETION ===\n\n";

// --- Groups ---
$groups = $repo->allFamilyGroups();
echo "Groups (" . count($groups) . "):\n";
foreach ($groups as $g) {
    $members = is_array($g['members'] ?? null) ? $g['members'] : [];
    $memberStr = !empty($members) ? implode(', ', $members) : '(no members)';
    $action = $isDryRun ? '[WOULD DELETE]' : '[DELETING]';
    echo "  $action id={$g['id']}  name=\"{$g['name']}\"  owner={$g['owner_key']}  members=[{$memberStr}]\n";

    if (!$isDryRun) {
        $repo->deleteFamilyGroup($g['id']);
    }
}

// --- Projects ---
$projects = $repo->allProjects();
echo "\nProjects (" . count($projects) . "):\n";
foreach ($projects as $p) {
    $action = $isDryRun ? '[WOULD DELETE]' : '[DELETING]';
    echo "  $action id={$p['id']}  name=\"{$p['name']}\"  owner={$p['owner_key']}\n";

    if (!$isDryRun) {
        $repo->deleteProject($p['id']);
    }
}

// --- Project-Group links ---
$links = DB::table('project_family_groups')->count();
if ($links > 0) {
    echo "\nProject-group links: {$links}\n";
    if (!$isDryRun) {
        DB::table('project_family_groups')->delete();
        echo "  Deleted all project-group links.\n";
    } else {
        echo "  [WOULD DELETE] all project-group links.\n";
    }
}

echo "\n" . ($isDryRun ? "Dry run complete. Add --execute to apply changes.\n" : "Cleanup complete.\n");
