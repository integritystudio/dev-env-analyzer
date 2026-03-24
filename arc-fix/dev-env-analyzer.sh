#!/bin/bash
#
# Development Environment Analyzer
# Scans for programming language directories and provides organization recommendations
# Created: 2025-10-22
#

set -eo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

RUN_DATE=$(date)
REPORT_FILE="$HOME/dev-env-analysis-$(date +%Y%m%d-%H%M%S).txt"

echo "========================================="
echo "Development Environment Analysis"
echo "Date: $RUN_DATE"
echo "========================================="
echo ""

check_dir() {
    local dir=$1
    [ -d "$dir" ] && [ -n "$(find "$dir" -maxdepth 1 -mindepth 1 -print -quit 2>/dev/null)" ]
}

get_dir_size() {
    du -sh "$1" 2>/dev/null | cut -f1
}

# Store recommendations as single records: "source|target|env_update"
declare -a RECOMMENDATIONS=()

echo "Scanning for language-specific directories..."
echo ""

check_tool_installed() {
    local cmd="$1"
    if command -v "$cmd" &> /dev/null; then
        echo "  ✓ $cmd installed: $($cmd --version 2>&1 | head -1)"
        return 0
    else
        echo "  - $cmd not installed"
        return 1
    fi
}

check_version_manager() {
    local tool_dir="$1"
    local root_var="$2"
    local target="$3"
    local env_export="$4"

    if check_dir "$tool_dir"; then
        local size
        size=$(get_dir_size "$tool_dir")
        echo "    - $(basename "$tool_dir") exists ($size)"
        local current_val="${!root_var}"
        if [ -n "$current_val" ]; then
            echo "      $root_var=$current_val"
        else
            echo -e "    ${YELLOW}⚠${NC} $root_var not set in current shell"
        fi
    fi
}

echo -e "${BLUE}[GO]${NC}"
if [ -d "$HOME/code/go" ]; then
    echo -e "  ${GREEN}✓${NC} Go workspace already organized at ~/code/go"
    if [ -d "$HOME/code/go/bin" ]; then
        bins=("$HOME/code/go/bin"/*)
        BIN_COUNT=${#bins[@]}
        echo "    - bin/ contains $BIN_COUNT binaries"
    fi
    if [ -n "$GOPATH" ]; then
        echo "    - GOPATH is set to: $GOPATH"
        SIZE=$(get_dir_size "$GOPATH")
        echo "cache and binaries size: ($SIZE)"
    else
        echo -e "    ${YELLOW}⚠${NC} GOPATH is not set in current shell"
    fi
else
    echo "  - No Go workspace found"
fi
echo ""

echo -e "${BLUE}[NODE.JS]${NC}"
if check_tool_installed node; then
    NPM_VERSION=$(npm --version 2>/dev/null || echo "not found")
    echo "  ✓ npm version: $NPM_VERSION"

    NPM_PREFIX=$(npm config get prefix 2>/dev/null || echo "")
    if [ -n "$NPM_PREFIX" ]; then
        echo "    - npm global prefix: $NPM_PREFIX"
    fi

    if check_dir "$HOME/.npm"; then
        SIZE=$(get_dir_size "$HOME/.npm")
        echo "    - ~/.npm cache exists ($SIZE)"
    fi

    if check_dir "$HOME/.nvm"; then
        SIZE=$(get_dir_size "$HOME/.nvm")
        echo "    - ~/.nvm exists ($SIZE)"
        echo "      (NVM manages multiple Node versions - recommend keeping in home)"
    fi
fi
echo ""

echo -e "${BLUE}[PYTHON]${NC}"
if check_tool_installed python3; then
    check_version_manager "$HOME/.pyenv" PYENV_ROOT "~/code/python/pyenv" "PYENV_ROOT=\$HOME/code/python/pyenv"

    PIP_USER_BASE=$(python3 -m site --user-base 2>/dev/null || echo "")
    if [ -n "$PIP_USER_BASE" ] && [ -d "$PIP_USER_BASE" ]; then
        echo "    - pip user base: $PIP_USER_BASE"
    fi

    if [ -n "$PYTHONPATH" ]; then
        echo "    - PYTHONPATH=$PYTHONPATH"
    fi
fi
echo ""

echo -e "${BLUE}[RUBY]${NC}"
if check_tool_installed ruby; then
    check_version_manager "$HOME/.rbenv" RBENV_ROOT "~/code/ruby/rbenv" "RBENV_ROOT=\$HOME/code/ruby/rbenv"

    if check_dir "$HOME/.gem"; then
        SIZE=$(get_dir_size "$HOME/.gem")
        echo "    - ~/.gem exists ($SIZE)"
    fi

    if [ -n "$GEM_HOME" ]; then
        echo "    - GEM_HOME=$GEM_HOME"
    fi
fi
echo ""

echo -e "${BLUE}[RUST]${NC}"
if check_tool_installed rustc; then
    check_version_manager "$HOME/.cargo" CARGO_HOME "~/code/rust/cargo" "CARGO_HOME=\$HOME/code/rust/cargo"
    check_version_manager "$HOME/.rustup" RUSTUP_HOME "~/code/rust/rustup" "RUSTUP_HOME=\$HOME/code/rust/rustup"
fi
echo ""

echo "========================================="
echo "RECOMMENDATIONS"
echo "========================================="
echo ""

if [ ${#RECOMMENDATIONS[@]} -eq 0 ]; then
    echo -e "${GREEN}✓ Your development environment is well organized!${NC}"
    echo "All language directories are either already in ~/code/ or appropriately located."
else
    echo -e "${YELLOW}The following directories could be better organized:${NC}"
    echo ""
    for rec in "${RECOMMENDATIONS[@]}"; do
        IFS='|' read -r source target env_update <<< "$rec"
        echo "  • $source -> $target"
    done
    echo ""

    echo -e "${YELLOW}Environment variables that would need updating:${NC}"
    echo ""
    for rec in "${RECOMMENDATIONS[@]}"; do
        IFS='|' read -r source target env_update <<< "$rec"
        echo "  • $env_update"
    done
    echo ""

    echo "To organize your development environment, you can:"
    echo "  1. Run the interactive organizer script: ~/code/arc-fix/dev-env-organizer.sh"
    echo "  2. Or manually move directories and update your ~/.zshrc file"
fi

echo ""
echo "========================================="
echo "Report saved to: $REPORT_FILE"
echo "========================================="

{
    echo "Development Environment Analysis Report"
    echo "Generated: $RUN_DATE"
    echo ""
    echo "Directories that could be moved:"
    for rec in "${RECOMMENDATIONS[@]}"; do
        IFS='|' read -r source target env_update <<< "$rec"
        echo "  - $source -> $target"
    done
    echo ""
    echo "Environment variables to update:"
    for rec in "${RECOMMENDATIONS[@]}"; do
        IFS='|' read -r source target env_update <<< "$rec"
        echo "  - $env_update"
    done
} > "$REPORT_FILE"
