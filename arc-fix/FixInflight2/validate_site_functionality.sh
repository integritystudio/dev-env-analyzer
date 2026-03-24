#!/bin/bash

# Site Functionality Validation Script
# Runs before and after migration to ensure no functionality is broken

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
VALIDATION_LOG="$SCRIPT_DIR/validation.log"
VALIDATION_STATE="$SCRIPT_DIR/.validation_state.json"
MODE=${1:-"check"} # "before", "after", or "check"

# Initialize log
echo "Validation started at $(date) - Mode: $MODE" >> "$VALIDATION_LOG"

# Validation results
VALIDATION_PASSED=true

# Function to log validation messages
log_validation() {
    local level=$1
    local message=$2
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $message" >> "$VALIDATION_LOG"
    
    case $level in
        PASS)
            echo -e "${GREEN}✓ $message${NC}"
            ;;
        FAIL)
            echo -e "${RED}✗ $message${NC}"
            VALIDATION_PASSED=false
            ;;
        WARN)
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

# Function to capture current state
capture_state() {
    local state_data="{"
    
    # Capture package versions
    log_validation INFO "Capturing package versions..."
    local npm_version=$(npm --version 2>/dev/null || echo "unknown")
    local node_version=$(node --version 2>/dev/null || echo "unknown")
    state_data="$state_data\"npm_version\":\"$npm_version\","
    state_data="$state_data\"node_version\":\"$node_version\","
    
    # Capture installed packages
    log_validation INFO "Capturing installed packages..."
    local packages=$(npm ls --json --depth=0 2>/dev/null | node -e "
        try {
            const data = JSON.parse(require('fs').readFileSync(0, 'utf8'));
            const deps = {...(data.dependencies || {}), ...(data.devDependencies || {})};
            const result = {};
            for (const [name, info] of Object.entries(deps)) {
                result[name] = info.version || 'unknown';
            }
            console.log(JSON.stringify(result));
        } catch(e) {
            console.log('{}');
        }
    " 2>/dev/null || echo "{}")
    state_data="$state_data\"packages\":$packages,"
    
    # Capture file checksums for important files
    log_validation INFO "Capturing file checksums..."
    local checksums="{"
    for file in package.json wix.config.json .eslintrc.json; do
        if [ -f "$file" ]; then
            local checksum=$(shasum -a 256 "$file" 2>/dev/null | cut -d' ' -f1)
            checksums="$checksums\"$file\":\"$checksum\","
        fi
    done
    checksums="${checksums%,}}"
    state_data="$state_data\"checksums\":$checksums,"
    
    # Capture source file count
    local js_count=$(find ./src -name "*.js" -type f 2>/dev/null | wc -l | tr -d ' ')
    state_data="$state_data\"js_file_count\":$js_count,"
    
    # Check if npm scripts work
    log_validation INFO "Testing npm scripts..."
    local scripts_work="true"
    if ! npm run lint --silent > /dev/null 2>&1; then
        scripts_work="false"
    fi
    state_data="$state_data\"scripts_work\":$scripts_work,"
    
    # Capture timestamp
    state_data="$state_data\"timestamp\":\"$(date -u +%Y-%m-%dT%H:%M:%SZ)\""
    state_data="$state_data}"
    
    echo "$state_data"
}

# Function to compare states
compare_states() {
    local before_state=$1
    local after_state=$2
    
    log_validation INFO "Comparing before and after states..."
    
    # Compare using Node.js for proper JSON handling
    node -e "
    try {
        const before = $before_state;
        const after = $after_state;
        let hasIssues = false;
        
        // Check Node/npm versions
        if (before.node_version !== after.node_version) {
            console.log('WARN: Node version changed from ' + before.node_version + ' to ' + after.node_version);
        }
        
        // Check if scripts still work
        if (before.scripts_work && !after.scripts_work) {
            console.log('FAIL: npm scripts no longer working');
            hasIssues = true;
        } else if (after.scripts_work) {
            console.log('PASS: npm scripts still working');
        }
        
        // Check file counts
        if (before.js_file_count !== after.js_file_count) {
            console.log('WARN: JavaScript file count changed from ' + before.js_file_count + ' to ' + after.js_file_count);
        } else {
            console.log('PASS: Source file count unchanged');
        }
        
        // Check critical files
        const criticalFiles = ['wix.config.json', '.eslintrc.json'];
        for (const file of criticalFiles) {
            if (before.checksums[file] && after.checksums[file]) {
                if (before.checksums[file] !== after.checksums[file]) {
                    console.log('WARN: ' + file + ' was modified');
                } else {
                    console.log('PASS: ' + file + ' unchanged');
                }
            }
        }
        
        // Check for removed packages (excluding inflight)
        const beforePkgs = Object.keys(before.packages || {});
        const afterPkgs = Object.keys(after.packages || {});
        const removed = beforePkgs.filter(p => !afterPkgs.includes(p) && p !== 'inflight');
        
        if (removed.length > 0) {
            console.log('WARN: Packages removed: ' + removed.join(', '));
        }
        
        // Check for lru-cache
        if (after.packages['lru-cache']) {
            console.log('PASS: lru-cache is installed');
        }
        
        // Check inflight is gone
        if (!after.packages['inflight']) {
            console.log('PASS: inflight package removed');
        } else {
            console.log('FAIL: inflight package still present');
            hasIssues = true;
        }
        
        process.exit(hasIssues ? 1 : 0);
    } catch(e) {
        console.log('ERROR: Failed to compare states: ' + e.message);
        process.exit(1);
    }
    " 2>&1 | while IFS= read -r line; do
        if [[ $line == PASS:* ]]; then
            log_validation PASS "${line#PASS: }"
        elif [[ $line == FAIL:* ]]; then
            log_validation FAIL "${line#FAIL: }"
        elif [[ $line == WARN:* ]]; then
            log_validation WARN "${line#WARN: }"
        else
            log_validation INFO "$line"
        fi
    done
    
    return ${PIPESTATUS[0]}
}

# Function to validate current functionality
validate_current() {
    echo -e "\n${BLUE}Validating Current Site Functionality${NC}"
    
    # Check package.json exists and is valid JSON
    if [ -f "package.json" ]; then
        if node -e "JSON.parse(require('fs').readFileSync('package.json'))" 2>/dev/null; then
            log_validation PASS "package.json is valid JSON"
        else
            log_validation FAIL "package.json is not valid JSON"
        fi
    else
        log_validation FAIL "package.json not found"
    fi
    
    # Check npm install works
    log_validation INFO "Testing npm install..."
    if npm install --ignore-scripts --dry-run > /dev/null 2>&1; then
        log_validation PASS "npm install dry-run successful"
    else
        log_validation FAIL "npm install would fail"
    fi
    
    # Check for syntax errors in source files
    log_validation INFO "Checking JavaScript syntax..."
    local syntax_errors=0
    while IFS= read -r file; do
        if ! node -c "$file" 2>/dev/null; then
            log_validation FAIL "Syntax error in: $file"
            ((syntax_errors++))
        fi
    done < <(find ./src -name "*.js" -type f 2>/dev/null | head -20)
    
    if [ $syntax_errors -eq 0 ]; then
        log_validation PASS "No syntax errors found"
    fi
    
    # Check eslint configuration
    if [ -f ".eslintrc.json" ]; then
        if node -e "JSON.parse(require('fs').readFileSync('.eslintrc.json'))" 2>/dev/null; then
            log_validation PASS "ESLint configuration is valid"
        else
            log_validation FAIL "ESLint configuration is invalid"
        fi
    fi
    
    # Check Wix configuration
    if [ -f "wix.config.json" ]; then
        if node -e "JSON.parse(require('fs').readFileSync('wix.config.json'))" 2>/dev/null; then
            log_validation PASS "Wix configuration is valid"
            
            # Extract site ID
            local site_id=$(node -e "
                const config = JSON.parse(require('fs').readFileSync('wix.config.json'));
                console.log(config.siteId || 'unknown');
            " 2>/dev/null)
            log_validation INFO "Site ID: $site_id"
        else
            log_validation FAIL "Wix configuration is invalid"
        fi
    fi
    
    # Test npm scripts
    log_validation INFO "Testing npm scripts..."
    if npm run lint > /dev/null 2>&1; then
        log_validation PASS "npm run lint works"
    else
        log_validation WARN "npm run lint has issues (may be expected)"
    fi
    
    # Check for inflight
    local inflight_count=$(npm ls 2>/dev/null | grep -c "inflight@" || echo "0")
    if [ $inflight_count -gt 0 ]; then
        log_validation INFO "inflight package currently present (will be removed)"
    else
        log_validation INFO "inflight package not present"
    fi
    
    return 0
}

# Main execution
main() {
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}     Site Functionality Validation${NC}"
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    
    case $MODE in
        before)
            echo -e "\n${YELLOW}Running pre-migration validation...${NC}"
            
            # Validate current functionality
            validate_current
            
            # Capture current state
            log_validation INFO "Capturing pre-migration state..."
            local state=$(capture_state)
            echo "$state" > "$VALIDATION_STATE"
            
            log_validation INFO "Pre-migration state saved to $VALIDATION_STATE"
            ;;
            
        after)
            echo -e "\n${YELLOW}Running post-migration validation...${NC}"
            
            # Check if we have a before state
            if [ ! -f "$VALIDATION_STATE" ]; then
                log_validation WARN "No pre-migration state found. Running standalone validation."
                validate_current
            else
                # Validate current functionality
                validate_current
                
                # Capture current state
                log_validation INFO "Capturing post-migration state..."
                local after_state=$(capture_state)
                
                # Load before state
                local before_state=$(cat "$VALIDATION_STATE")
                
                # Compare states
                echo -e "\n${BLUE}Comparing before and after states...${NC}"
                if compare_states "$before_state" "$after_state"; then
                    log_validation PASS "State comparison successful"
                else
                    log_validation FAIL "State comparison found issues"
                    VALIDATION_PASSED=false
                fi
            fi
            ;;
            
        check|*)
            echo -e "\n${YELLOW}Running standalone validation...${NC}"
            validate_current
            
            # Quick inflight check
            echo -e "\n${BLUE}Checking inflight status...${NC}"
            if npm ls inflight 2>&1 | grep -q "inflight@"; then
                log_validation WARN "inflight package is present"
            else
                log_validation PASS "inflight package is not present"
            fi
            ;;
    esac
    
    # Summary
    echo ""
    echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
    if [ "$VALIDATION_PASSED" = true ]; then
        echo -e "${GREEN}     Validation Completed Successfully${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        exit 0
    else
        echo -e "${RED}     Validation Found Issues${NC}"
        echo -e "${BLUE}═══════════════════════════════════════════════════════${NC}"
        echo -e "\nPlease review the validation log: $VALIDATION_LOG"
        exit 1
    fi
}

# Run main function
main