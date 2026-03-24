#!/bin/bash

# Exit on error
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Script configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
LOG_FILE="$SCRIPT_DIR/migration.log"
BACKUP_DIR="$SCRIPT_DIR/.migration_backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Initialize log file
echo "Migration started at $(date)" > "$LOG_FILE"

# Function to log messages
log_message() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$LOG_FILE"
    
    case $level in
        ERROR)
            echo -e "${RED}ERROR: $message${NC}"
            ;;
        SUCCESS)
            echo -e "${GREEN}✓ $message${NC}"
            ;;
        WARNING)
            echo -e "${YELLOW}⚠ $message${NC}"
            ;;
        INFO)
            echo -e "${BLUE}ℹ $message${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Function to create backup
create_backup() {
    log_message INFO "Creating backup..."
    
    # Create backup directory if it doesn't exist
    mkdir -p "$BACKUP_DIR"
    
    # Backup package files
    if [ -f package.json ]; then
        cp package.json "$BACKUP_DIR/package.json.$TIMESTAMP"
        log_message SUCCESS "Backed up package.json"
    fi
    
    if [ -f package-lock.json ]; then
        cp package-lock.json "$BACKUP_DIR/package-lock.json.$TIMESTAMP"
        log_message SUCCESS "Backed up package-lock.json"
    fi
    
    # Save current dependency tree
    npm ls --all --json > "$BACKUP_DIR/dependency-tree.$TIMESTAMP.json" 2>/dev/null || true
    
    # Save list of files that might use inflight
    find . -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.ts" \) -not -path "./node_modules/*" -not -path "./.git/*" > "$BACKUP_DIR/source-files.$TIMESTAMP.txt" 2>/dev/null || true
}

# Function to restore backup
restore_backup() {
    log_message WARNING "Restoring from backup..."
    
    if [ -f "$BACKUP_DIR/package.json.$TIMESTAMP" ]; then
        cp "$BACKUP_DIR/package.json.$TIMESTAMP" package.json
        log_message SUCCESS "Restored package.json"
    fi
    
    if [ -f "$BACKUP_DIR/package-lock.json.$TIMESTAMP" ]; then
        cp "$BACKUP_DIR/package-lock.json.$TIMESTAMP" package-lock.json
        log_message SUCCESS "Restored package-lock.json"
    fi
    
    # Reinstall dependencies
    npm install --ignore-scripts > /dev/null 2>&1
}

# Function to check if inflight exists
check_inflight_presence() {
    local result=$(npm ls inflight 2>/dev/null | grep -c "inflight@" || echo "0")
    echo "$result"
}

# Function to identify inflight dependencies
identify_inflight_deps() {
    log_message INFO "Identifying packages that depend on inflight..."
    
    # Get full dependency tree
    local deps=$(npm ls inflight 2>/dev/null || true)
    
    if [[ "$deps" == *"inflight"* ]]; then
        echo "$deps" > "$BACKUP_DIR/inflight-deps.$TIMESTAMP.txt"
        log_message WARNING "Found inflight in dependency tree:"
        echo "$deps" | grep -E "└|├" | head -10
        return 0
    else
        log_message SUCCESS "No inflight dependencies found"
        return 1
    fi
}

# Function to add npm overrides
add_npm_overrides() {
    log_message INFO "Adding npm overrides to eliminate inflight..."
    
    # Check if package.json exists
    if [ ! -f package.json ]; then
        log_message ERROR "package.json not found"
        return 1
    fi
    
    # Create a temporary file for the modified package.json
    local temp_file=$(mktemp)
    
    # Add overrides using Node.js for proper JSON handling
    node -e "
    const fs = require('fs');
    const packageJson = JSON.parse(fs.readFileSync('package.json', 'utf8'));
    
    // Add or update overrides
    if (!packageJson.overrides) {
        packageJson.overrides = {};
    }
    
    // Force glob to version 10+ which doesn't use inflight
    packageJson.overrides.glob = '^10.3.10';
    
    // Replace inflight with a safe alternative if directly required
    packageJson.overrides.inflight = 'npm:@isaacs/inflight-promise@^1.0.1';
    
    fs.writeFileSync('$temp_file', JSON.stringify(packageJson, null, 2));
    " 2>/dev/null
    
    if [ $? -eq 0 ]; then
        mv "$temp_file" package.json
        log_message SUCCESS "Added npm overrides to package.json"
        return 0
    else
        rm -f "$temp_file"
        log_message ERROR "Failed to add npm overrides"
        return 1
    fi
}

# Function to remove inflight if directly installed
remove_direct_inflight() {
    if npm list inflight --depth=0 &>/dev/null; then
        log_message INFO "Removing direct inflight dependency..."
        npm uninstall inflight --save
        log_message SUCCESS "Removed direct inflight dependency"
    else
        log_message INFO "inflight is not a direct dependency"
    fi
}

# Function to scan for inflight usage in code
scan_code_usage() {
    log_message INFO "Scanning code for inflight usage..."
    
    local files_with_inflight=()
    local count=0
    
    while IFS= read -r file; do
        if grep -q "require('inflight')\|require(\"inflight\")\|from 'inflight'\|from \"inflight\"" "$file" 2>/dev/null; then
            files_with_inflight+=("$file")
            ((count++))
        fi
    done < <(find . -type f \( -name "*.js" -o -name "*.mjs" -o -name "*.ts" -o -name "*.jsx" -o -name "*.tsx" \) -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null)
    
    if [ $count -gt 0 ]; then
        log_message WARNING "Found $count file(s) with inflight imports"
        for file in "${files_with_inflight[@]}"; do
            echo "  - $file" >> "$LOG_FILE"
        done
        return 1
    else
        log_message SUCCESS "No files found with inflight imports"
        return 0
    fi
}

# Function to validate migration
validate_migration() {
    log_message INFO "Validating migration..."
    
    local validation_passed=true
    
    # Check if inflight is completely removed
    if [ $(check_inflight_presence) -eq 0 ]; then
        log_message SUCCESS "inflight package is completely removed"
    else
        log_message ERROR "inflight package is still present"
        validation_passed=false
    fi
    
    # Check if glob was upgraded
    local glob_version=$(npm ls glob --depth=0 2>/dev/null | grep -oE "glob@[0-9]+\.[0-9]+\.[0-9]+" | head -1 | cut -d@ -f2)
    if [ ! -z "$glob_version" ]; then
        local major_version=$(echo "$glob_version" | cut -d. -f1)
        if [ "$major_version" -ge 8 ]; then
            log_message SUCCESS "glob upgraded to version $glob_version (v8+)"
        else
            log_message WARNING "glob version $glob_version is still below v8"
        fi
    fi
    
    # Check if lru-cache is installed
    if npm list lru-cache --depth=0 &>/dev/null; then
        log_message SUCCESS "lru-cache is installed"
    else
        log_message WARNING "lru-cache is not installed as direct dependency"
    fi
    
    # Run npm audit to check for vulnerabilities
    log_message INFO "Running security audit..."
    local audit_result=$(npm audit --json 2>/dev/null | node -e "
        const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
        console.log('Vulnerabilities: ' + data.metadata.vulnerabilities.total);
    " 2>/dev/null || echo "Audit check failed")
    log_message INFO "$audit_result"
    
    if [ "$validation_passed" = true ]; then
        log_message SUCCESS "Migration validation passed"
        return 0
    else
        log_message ERROR "Migration validation failed"
        return 1
    fi
}

# Function to run tests
run_tests() {
    log_message INFO "Running tests..."
    
    # Check if test script exists
    if [ -f "$SCRIPT_DIR/test_migration.sh" ]; then
        log_message INFO "Running migration test suite..."
        bash "$SCRIPT_DIR/test_migration.sh"
        return $?
    else
        log_message WARNING "Test suite not found. Skipping tests."
        return 0
    fi
}

# Main migration process
main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Inflight Memory Leak Fix & Migration Script${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Check prerequisites
    log_message INFO "Checking prerequisites..."
    
    if [ ! -f package.json ]; then
        log_message ERROR "package.json not found in current directory"
        exit 1
    fi
    
    if ! command -v npm &> /dev/null; then
        log_message ERROR "npm is not installed"
        exit 1
    fi
    
    if ! command -v node &> /dev/null; then
        log_message ERROR "node is not installed"
        exit 1
    fi
    
    # Show current status
    echo -e "${YELLOW}Current Status:${NC}"
    echo -e "  Working directory: $(pwd)"
    echo -e "  Node version: $(node --version)"
    echo -e "  npm version: $(npm --version)"
    
    # Check initial inflight presence
    initial_inflight_count=$(check_inflight_presence)
    if [ "$initial_inflight_count" -gt 0 ]; then
        echo -e "  ${YELLOW}inflight status: PRESENT (memory leak risk)${NC}"
    else
        echo -e "  ${GREEN}inflight status: NOT FOUND${NC}"
    fi
    echo ""
    
    # Confirm with user
    echo -e "${YELLOW}This script will:${NC}"
    echo "  1. Backup your package files"
    echo "  2. Remove inflight package completely"
    echo "  3. Add npm overrides to prevent inflight installation"
    echo "  4. Install lru-cache as a replacement (if needed)"
    echo "  5. Validate the migration"
    echo "  6. Run tests to ensure functionality"
    echo ""
    
    read -p "Do you want to proceed? (y/N): " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_message INFO "Migration cancelled by user"
        exit 0
    fi
    
    # Create backup
    create_backup
    
    # Identify dependencies
    identify_inflight_deps
    
    # Scan code usage
    scan_code_usage
    
    # Remove direct inflight dependency if exists
    remove_direct_inflight
    
    # Add npm overrides
    if ! add_npm_overrides; then
        log_message ERROR "Failed to add npm overrides"
        restore_backup
        exit 1
    fi
    
    # Clean and reinstall
    log_message INFO "Reinstalling dependencies with overrides..."
    rm -rf node_modules package-lock.json
    
    # Install with error handling
    if npm install --ignore-scripts > /dev/null 2>&1; then
        log_message SUCCESS "Dependencies reinstalled successfully"
    else
        log_message ERROR "Failed to reinstall dependencies"
        restore_backup
        exit 1
    fi
    
    # Install lru-cache if not present
    if ! npm list lru-cache --depth=0 &>/dev/null; then
        log_message INFO "Installing lru-cache..."
        npm install lru-cache@latest
        log_message SUCCESS "Installed lru-cache"
    fi
    
    # Validate migration
    if ! validate_migration; then
        log_message ERROR "Migration validation failed"
        read -p "Do you want to restore from backup? (Y/n): " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            restore_backup
            exit 1
        fi
    fi
    
    # Run tests
    run_tests
    
    # Final summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${GREEN}            Migration Complete!${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    final_inflight_count=$(check_inflight_presence)
    if [ "$final_inflight_count" -eq 0 ]; then
        echo -e "${GREEN}✓ inflight package has been completely removed${NC}"
        echo -e "${GREEN}✓ Memory leak vulnerability fixed${NC}"
    else
        echo -e "${YELLOW}⚠ Some inflight dependencies may still exist${NC}"
    fi
    
    echo ""
    echo "Next steps:"
    echo "  1. Review the migration log: $LOG_FILE"
    echo "  2. Run your application tests"
    echo "  3. Monitor memory usage"
    echo "  4. Backup files are in: $BACKUP_DIR"
    echo ""
    
    log_message SUCCESS "Migration completed at $(date)"
}

# Run main function
main "$@"