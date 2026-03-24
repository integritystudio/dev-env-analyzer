#!/bin/bash
#
# Go Functionality Test Script
# Tests that Go environment is properly configured and functional
# Created: 2025-10-22
#

# Set up logging
LOG_DIR="$HOME/code/arc-fix/go-test-logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/go-test-$(date +%Y%m%d-%H%M%S).log"

# Redirect all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

echo "========================================="
echo "Go Functionality Test"
echo "Date: $(date)"
echo "========================================="
echo ""

# Set GOPATH
export GOPATH="$HOME/code/go"
export PATH="$GOPATH/bin:$PATH"

# Test counter
TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Check if go command exists
echo "[TEST 1] Checking if go command is available..."
if command -v go &> /dev/null; then
    echo "✓ PASS: go command found at $(which go)"
    GO_VERSION=$(go version)
    echo "  Version: $GO_VERSION"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL: go command not found"
    ((TESTS_FAILED++))
fi
echo ""

# Test 2: Verify GOPATH
echo "[TEST 2] Verifying GOPATH configuration..."
if [ -d "$GOPATH" ]; then
    echo "✓ PASS: GOPATH exists at $GOPATH"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL: GOPATH directory does not exist at $GOPATH"
    ((TESTS_FAILED++))
fi
echo ""

# Test 3: Check GOPATH structure
echo "[TEST 3] Checking GOPATH directory structure..."
MISSING_DIRS=""
for dir in bin pkg; do
    if [ -d "$GOPATH/$dir" ]; then
        echo "✓ $GOPATH/$dir exists"
    else
        echo "✗ $GOPATH/$dir missing"
        MISSING_DIRS="$MISSING_DIRS $dir"
    fi
done
if [ -z "$MISSING_DIRS" ]; then
    echo "✓ PASS: All required directories exist"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL: Missing directories:$MISSING_DIRS"
    ((TESTS_FAILED++))
fi
echo ""

# Test 4: Create temporary test project
echo "[TEST 4] Creating and testing temporary Go project..."
TEST_PROJECT_DIR="$HOME/code/go-nightly-test-$(date +%s)"
mkdir -p "$TEST_PROJECT_DIR"

cat > "$TEST_PROJECT_DIR/main.go" << 'EOF'
package main

import (
	"fmt"
	"os"
)

func main() {
	gopath := os.Getenv("GOPATH")
	fmt.Printf("GOPATH=%s\n", gopath)
	fmt.Println("SUCCESS")
}
EOF

cd "$TEST_PROJECT_DIR"
if go mod init test/nightly &> /dev/null; then
    echo "✓ go mod init succeeded"
else
    echo "✗ go mod init failed"
    ((TESTS_FAILED++))
    cd "$HOME"
    rm -rf "$TEST_PROJECT_DIR"
    echo ""
    continue
fi

# Test 5: Run go program
echo ""
echo "[TEST 5] Running go program..."
OUTPUT=$(go run main.go 2>&1)
if echo "$OUTPUT" | grep -q "SUCCESS"; then
    echo "✓ PASS: go run executed successfully"
    echo "  Output: $OUTPUT"
    ((TESTS_PASSED++))
else
    echo "✗ FAIL: go run failed"
    echo "  Output: $OUTPUT"
    ((TESTS_FAILED++))
fi
echo ""

# Test 6: Install binary
echo "[TEST 6] Testing go install..."
if go install &> /dev/null; then
    if [ -f "$GOPATH/bin/nightly" ]; then
        echo "✓ PASS: go install created binary at $GOPATH/bin/nightly"
        ((TESTS_PASSED++))

        # Test 7: Execute installed binary
        echo ""
        echo "[TEST 7] Executing installed binary..."
        BIN_OUTPUT=$("$GOPATH/bin/nightly" 2>&1)
        if echo "$BIN_OUTPUT" | grep -q "SUCCESS"; then
            echo "✓ PASS: Installed binary executed successfully"
            ((TESTS_PASSED++))
        else
            echo "✗ FAIL: Installed binary execution failed"
            ((TESTS_FAILED++))
        fi

        # Clean up binary
        rm -f "$GOPATH/bin/nightly"
    else
        echo "✗ FAIL: go install did not create binary"
        ((TESTS_FAILED++))
    fi
else
    echo "✗ FAIL: go install failed"
    ((TESTS_FAILED++))
fi
echo ""

# Clean up test project
cd "$HOME"
rm -rf "$TEST_PROJECT_DIR"

# Summary
echo "========================================="
echo "Test Summary"
echo "========================================="
echo "Tests Passed: $TESTS_PASSED"
echo "Tests Failed: $TESTS_FAILED"
echo "Log saved to: $LOG_FILE"
echo ""

if [ $TESTS_FAILED -eq 0 ]; then
    echo "✓ ALL TESTS PASSED"
    exit 0
else
    echo "✗ SOME TESTS FAILED"
    exit 1
fi
