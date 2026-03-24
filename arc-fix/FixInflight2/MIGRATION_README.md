# Inflight Memory Leak Fix & Migration Suite

## Overview

This suite provides a comprehensive solution to remove the `inflight` package (which has a known memory leak) from your Node.js project and replace it with safer alternatives.

## Problem Statement

The `inflight` package (v1.0.6) has a known memory leak issue where it doesn't properly clean up its internal cache. This package is often included as a transitive dependency through older versions of `glob` (< v8).

## Solution

This migration suite:
1. Completely removes the `inflight` package from your dependency tree
2. Forces `glob` to upgrade to v10+ (which doesn't use inflight)
3. Optionally installs `lru-cache` as a modern caching alternative
4. Validates that your site functionality remains intact

## Files Included

### 1. `migrate_inflight_to_lru_cache.sh`
The main migration script that:
- Creates backups of your package files
- Identifies and removes inflight dependencies
- Adds npm overrides to prevent inflight reinstallation
- Installs lru-cache as a replacement
- Validates the migration
- Provides rollback capability

### 2. `test_migration.sh`
Comprehensive test suite that validates:
- Prerequisites are met
- Inflight is completely removed
- Package overrides are correctly set
- Glob version is upgraded
- Site functionality is preserved
- No security vulnerabilities introduced
- Performance is maintained

### 3. `validate_site_functionality.sh`
Pre/post migration validation that:
- Captures state before migration
- Validates JavaScript syntax
- Checks npm scripts functionality
- Compares before/after states
- Ensures no breaking changes

## Quick Start

### Prerequisites
- Node.js installed
- npm installed
- package.json in current directory

### Basic Usage

1. **Make scripts executable:**
```bash
chmod +x migrate_inflight_to_lru_cache.sh test_migration.sh validate_site_functionality.sh
```

2. **Run pre-migration validation:**
```bash
./validate_site_functionality.sh before
```

3. **Run the migration:**
```bash
./migrate_inflight_to_lru_cache.sh
```

4. **Run post-migration validation:**
```bash
./validate_site_functionality.sh after
```

5. **Run the test suite:**
```bash
./test_migration.sh
```

## Advanced Usage

### Standalone Validation
Check current state without migration:
```bash
./validate_site_functionality.sh check
```

### Manual Rollback
If issues occur, restore from backup:
```bash
cp .migration_backup/package.json.<timestamp> package.json
cp .migration_backup/package-lock.json.<timestamp> package-lock.json
npm install --ignore-scripts
```

## How It Works

### NPM Overrides
The script adds the following to your `package.json`:
```json
{
  "overrides": {
    "glob": "^10.3.10",
    "inflight": "npm:@isaacs/inflight-promise@^1.0.1"
  }
}
```

This ensures:
- Any package requiring `glob` gets v10+ (which doesn't use inflight)
- Any direct inflight requirement gets replaced with a safer alternative

### Dependency Chain Fix
Before migration:
```
@wix/cli → node-gyp → glob@7.x → inflight (memory leak)
```

After migration:
```
@wix/cli → node-gyp → glob@10.x (no inflight!)
```

## Files Created

### During Migration
- `.migration_backup/` - Backup directory containing:
  - `package.json.<timestamp>` - Package file backup
  - `package-lock.json.<timestamp>` - Lock file backup
  - `dependency-tree.<timestamp>.json` - Full dependency tree
  - `source-files.<timestamp>.txt` - List of source files
  - `inflight-deps.<timestamp>.txt` - Inflight dependency details

### Logs
- `migration.log` - Detailed migration process log
- `test_results.log` - Test suite execution results
- `validation.log` - Validation process log
- `.validation_state.json` - Pre-migration state for comparison

## Test Suite Details

The test suite validates:

| Test Group | What It Checks |
|------------|---------------|
| Prerequisites | Node, npm, package.json, script files |
| Inflight Removal | Package completely removed from tree |
| Package Overrides | Correct overrides in package.json |
| Glob Version | Upgraded to v8+ |
| LRU Cache | Installed as replacement |
| Backup | Backup files created |
| Site Functionality | npm scripts, syntax, Wix config |
| Security | No new vulnerabilities |
| Memory Leak | Inflight not accessible |
| Rollback | Backup files available |
| Performance | npm install speed |

## Troubleshooting

### Issue: Tests fail after migration
**Solution:** Run `./validate_site_functionality.sh after` to compare states

### Issue: npm install fails
**Solution:** Check `migration.log` for details, consider rollback

### Issue: Wix CLI postinstall fails
**Solution:** Use `npm install --ignore-scripts` then run `wix sync-types` manually

### Issue: Some packages still show inflight
**Solution:** Clear npm cache: `npm cache clean --force` then reinstall

## Important Notes

1. **Not a Drop-in Replacement**: `inflight` and `lru-cache` serve different purposes:
   - `inflight`: Prevents duplicate function calls
   - `lru-cache`: Implements LRU caching

2. **Code Changes May Be Required**: If your code directly uses inflight, you'll need to refactor it.

3. **Backup Always Created**: The script automatically backs up your files before making changes.

4. **Validation Recommended**: Always run the validation scripts before and after migration.

## Security Benefits

Removing `inflight` provides:
- Elimination of known memory leak vulnerability
- Reduced attack surface
- Updated dependencies with latest security patches
- Better memory management

## Performance Impact

After migration:
- ✅ No more memory leaks from inflight
- ✅ Faster npm install (glob v10 is more efficient)
- ✅ Better tree-shaking capabilities
- ✅ Reduced node_modules size

## Support

For issues or questions:
1. Check the logs: `migration.log`, `test_results.log`, `validation.log`
2. Review backups in `.migration_backup/`
3. Run the test suite: `./test_migration.sh`
4. Use rollback if needed

## License

These migration scripts are provided as-is for use with your project.

## Changelog

### Version 1.0.0
- Initial release with full inflight removal
- Comprehensive test suite
- Pre/post validation
- Automatic backup and rollback