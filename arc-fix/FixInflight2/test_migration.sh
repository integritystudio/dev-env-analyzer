#!/bin/bash

# Test suite for migrate_inflight_to_lru_cache.sh
# This script validates that the migration script works correctly

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Test configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TEST_LOG="$SCRIPT_DIR/test_results.log"
TEST_TEMP_DIR="$SCRIPT_DIR/.test_temp"
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Initialize test log
echo "Test suite started at $(date)" > "$TEST_LOG"

# Test result tracking (using regular variables for compatibility)

# Function to log test messages
log_test() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$TEST_LOG"
    
    case $level in
        PASS)
            echo -e "${GREEN}✓ $message${NC}"
            ((TESTS_PASSED++))
            ;;
        FAIL)
            echo -e "${RED}✗ $message${NC}"
            ((TESTS_FAILED++))
            ;;
        SKIP)
            echo -e "${YELLOW}⊘ $message${NC}"
            ((TESTS_SKIPPED++))
            ;;
        INFO)
            echo -e "${BLUE}ℹ $message${NC}"
            ;;
        *)
            echo "$message"
            ;;
    esac
}

# Function to assert condition
assert() {
    local test_name=$1
    local condition=$2
    local error_msg=${3:-"Assertion failed"}
    
    if eval "$condition"; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: $error_msg"
        return 1
    fi
}

# Function to assert command success
assert_command() {
    local test_name=$1
    shift
    local command="$@"
    
    if $command > /dev/null 2>&1; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: Command failed: $command"
        return 1
    fi
}

# Function to check file exists
assert_file_exists() {
    local test_name=$1
    local file=$2
    
    if [ -f "$file" ]; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: File not found: $file"
        return 1
    fi
}

# Function to check directory exists
assert_dir_exists() {
    local test_name=$1
    local dir=$2
    
    if [ -d "$dir" ]; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: Directory not found: $dir"
        return 1
    fi
}

# Function to check package is not installed
assert_package_not_present() {
    local test_name=$1
    local package=$2
    
    if ! npm ls "$package" 2>/dev/null | grep -q "$package@"; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: Package still present: $package"
        return 1
    fi
}

# Function to check package is installed
assert_package_present() {
    local test_name=$1
    local package=$2
    
    if npm ls "$package" --depth=0 2>/dev/null | grep -q "$package@"; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: Package not found: $package"
        return 1
    fi
}

# Function to check JSON property
assert_json_property() {
    local test_name=$1
    local file=$2
    local property=$3
    local expected_value=$4
    
    local actual_value=$(node -e "
        const fs = require('fs');
        const data = JSON.parse(fs.readFileSync('$file', 'utf8'));
        const props = '$property'.split('.');
        let value = data;
        for (const prop of props) {
            value = value[prop];
        }
        console.log(JSON.stringify(value));
    " 2>/dev/null)
    
    if [ "$actual_value" = "\"$expected_value\"" ] || [ "$actual_value" = "$expected_value" ]; then
        log_test PASS "$test_name"
        return 0
    else
        log_test FAIL "$test_name: Expected '$expected_value', got '$actual_value'"
        return 1
    fi
}

# Test Suite Functions

# Test 1: Prerequisites Check
test_prerequisites() {
    echo -e "\n${BLUE}Test Group: Prerequisites${NC}"
    
    assert_command "Node.js is installed" command -v node
    assert_command "npm is installed" command -v npm
    assert_file_exists "package.json exists" "package.json"
    assert_file_exists "Migration script exists" "migrate_inflight_to_lru_cache.sh"
    assert "Migration script is executable" "[ -x migrate_inflight_to_lru_cache.sh ]"
}

# Test 2: Backup Functionality
test_backup_functionality() {
    echo -e "\n${BLUE}Test Group: Backup Functionality${NC}"
    
    # Note: This would be tested after running migration
    if [ -d ".migration_backup" ]; then
        local latest_backup=$(ls -t .migration_backup/package.json.* 2>/dev/null | head -1)
        if [ ! -z "$latest_backup" ]; then
            assert_file_exists "Backup of package.json created" "$latest_backup"
        else
            log_test SKIP "Backup test - no backup files found"
        fi
    else
        log_test SKIP "Backup test - backup directory not created yet"
    fi
}

# Test 3: Inflight Removal
test_inflight_removal() {
    echo -e "\n${BLUE}Test Group: Inflight Package Removal${NC}"
    
    assert_package_not_present "inflight package is removed" "inflight"
    
    # Check that inflight is not in any dependency
    local inflight_count=$(npm ls 2>/dev/null | grep "inflight@" | wc -l | tr -d ' ')
    assert "No inflight in dependency tree" "[ $inflight_count -eq 0 ]"
}

# Test 4: Package Overrides
test_package_overrides() {
    echo -e "\n${BLUE}Test Group: Package Overrides${NC}"
    
    if [ -f "package.json" ]; then
        # Check if overrides exist
        local has_overrides=$(node -e "
            const fs = require('fs');
            const pkg = JSON.parse(fs.readFileSync('package.json', 'utf8'));
            console.log(pkg.overrides ? 'true' : 'false');
        " 2>/dev/null)
        
        assert "Package.json has overrides section" "[ '$has_overrides' = 'true' ]"
        
        # Check specific overrides
        if [ "$has_overrides" = "true" ]; then
            assert_json_property "glob override is set" "package.json" "overrides.glob" "^10.3.10"
        fi
    else
        log_test FAIL "package.json not found for override test"
    fi
}

# Test 5: Glob Version Check
test_glob_version() {
    echo -e "\n${BLUE}Test Group: Glob Package Version${NC}"
    
    local glob_version=$(npm ls glob 2>/dev/null | grep -oE "glob@[0-9]+\.[0-9]+\.[0-9]+" | head -1 | cut -d@ -f2)
    
    if [ ! -z "$glob_version" ]; then
        local major_version=$(echo "$glob_version" | cut -d. -f1)
        assert "Glob version is 8 or higher" "[ $major_version -ge 8 ]"
        log_test INFO "Glob version: $glob_version"
    else
        log_test SKIP "Glob version check - package not found"
    fi
}

# Test 6: LRU Cache Installation
test_lru_cache() {
    echo -e "\n${BLUE}Test Group: LRU Cache Package${NC}"
    
    assert_package_present "lru-cache is installed" "lru-cache"
}

# Test 7: Site Functionality Tests
test_site_functionality() {
    echo -e "\n${BLUE}Test Group: Site Functionality${NC}"
    
    # Test npm scripts still work
    assert_command "npm run lint works" npm run lint
    
    # Check if Wix CLI commands are available
    if command -v wix &> /dev/null; then
        log_test PASS "Wix CLI is available"
    else
        log_test SKIP "Wix CLI not installed globally"
    fi
    
    # Verify no syntax errors in JS files
    local count=0
    while IFS= read -r file; do
        if [ $count -lt 5 ]; then
            if node -c "$file" 2>/dev/null; then
                log_test PASS "Syntax check: $(basename "$file")"
            else
                log_test FAIL "Syntax error in: $(basename "$file")"
            fi
            ((count++))
        fi
    done < <(find ./src -name "*.js" -type f 2>/dev/null)
    
    if [ $count -eq 0 ]; then
        log_test SKIP "No JavaScript files found to test"
    fi
}

# Test 8: Security Audit
test_security_audit() {
    echo -e "\n${BLUE}Test Group: Security Audit${NC}"
    
    # Run npm audit
    local audit_output=$(npm audit --json 2>/dev/null)
    local vulnerabilities=$(echo "$audit_output" | node -e "
        try {
            const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
            console.log(data.metadata.vulnerabilities.total);
        } catch(e) {
            console.log('unknown');
        }
    " 2>/dev/null)
    
    if [ "$vulnerabilities" = "0" ]; then
        log_test PASS "No security vulnerabilities found"
    elif [ "$vulnerabilities" = "unknown" ]; then
        log_test SKIP "Security audit could not be completed"
    else
        log_test INFO "Security audit found $vulnerabilities vulnerabilities"
    fi
}

# Test 9: Memory Leak Check
test_memory_leak_prevention() {
    echo -e "\n${BLUE}Test Group: Memory Leak Prevention${NC}"
    
    # Check that inflight is not accessible
    local test_file="$TEST_TEMP_DIR/test_inflight.js"
    mkdir -p "$TEST_TEMP_DIR"
    
    cat > "$test_file" << 'EOF'
try {
    require('inflight');
    console.log('ERROR: inflight is still accessible');
    process.exit(1);
} catch(e) {
    if (e.code === 'MODULE_NOT_FOUND' && e.message.includes('inflight')) {
        console.log('SUCCESS: inflight is not accessible');
        process.exit(0);
    } else {
        console.log('ERROR: Unexpected error:', e.message);
        process.exit(1);
    }
}
EOF
    
    if node "$test_file" 2>/dev/null; then
        log_test PASS "inflight module is not accessible"
    else
        log_test FAIL "inflight module is still accessible"
    fi
    
    rm -rf "$TEST_TEMP_DIR"
}

# Test 10: Rollback Capability
test_rollback_capability() {
    echo -e "\n${BLUE}Test Group: Rollback Capability${NC}"
    
    if [ -d ".migration_backup" ]; then
        local backup_count=$(ls .migration_backup/package.json.* 2>/dev/null | wc -l)
        assert "Backup files exist for rollback" "[ $backup_count -gt 0 ]"
    else
        log_test SKIP "Rollback test - no backup directory"
    fi
}

# Performance test
test_performance() {
    echo -e "\n${BLUE}Test Group: Performance${NC}"
    
    # Test that npm install completes in reasonable time
    local start_time=$(date +%s)
    timeout 120 npm install --ignore-scripts > /dev/null 2>&1
    local exit_code=$?
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    if [ $exit_code -eq 0 ]; then
        log_test PASS "npm install completed in ${duration}s"
    elif [ $exit_code -eq 124 ]; then
        log_test FAIL "npm install timed out (>120s)"
    else
        log_test FAIL "npm install failed with exit code $exit_code"
    fi
}

# Main test execution
main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Migration Script Test Suite${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    # Run test groups
    test_prerequisites
    test_inflight_removal
    test_package_overrides
    test_glob_version
    test_lru_cache
    test_backup_functionality
    test_site_functionality
    test_security_audit
    test_memory_leak_prevention
    test_rollback_capability
    test_performance
    
    # Generate summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Test Summary${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo ""
    
    local total_tests=$((TESTS_PASSED + TESTS_FAILED + TESTS_SKIPPED))
    
    echo -e "${GREEN}Passed:${NC} $TESTS_PASSED"
    echo -e "${RED}Failed:${NC} $TESTS_FAILED"
    echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
    echo -e "${BLUE}Total:${NC} $total_tests"
    echo ""
    
    # Calculate pass rate
    if [ $total_tests -gt 0 ]; then
        local pass_rate=$((TESTS_PASSED * 100 / (TESTS_PASSED + TESTS_FAILED)))
        echo -e "Pass Rate: ${pass_rate}%"
    fi
    
    # Write summary to log
    echo "" >> "$TEST_LOG"
    echo "Test Results Summary:" >> "$TEST_LOG"
    echo "  Passed: $TESTS_PASSED" >> "$TEST_LOG"
    echo "  Failed: $TESTS_FAILED" >> "$TEST_LOG"
    echo "  Skipped: $TESTS_SKIPPED" >> "$TEST_LOG"
    
    echo "" >> "$TEST_LOG"
    echo "Test suite completed at $(date)" >> "$TEST_LOG"
    
    # Exit with appropriate code
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "\n${GREEN}All critical tests passed!${NC}"
        echo "Full test log available at: $TEST_LOG"
        exit 0
    else
        echo -e "\n${RED}Some tests failed. Please review the results.${NC}"
        echo "Full test log available at: $TEST_LOG"
        exit 1
    fi
}

# Run the test suite
main "$@"