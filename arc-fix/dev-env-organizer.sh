#!/bin/bash
#
# Development Environment Organizer
# Interactive script to move language directories to ~/code/
# Created: 2025-10-22
#

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

echo "========================================="
echo "Development Environment Organizer"
echo "========================================="
echo ""
echo "This script will help you organize your language"
echo "directories under ~/code/ for better organization."
echo ""

# Backup shell config
SHELL_CONFIG="$HOME/.zshrc"
if [ -f "$SHELL_CONFIG" ]; then
    BACKUP_FILE="${SHELL_CONFIG}.backup-$(date +%Y%m%d-%H%M%S)"
    cp "$SHELL_CONFIG" "$BACKUP_FILE"
    echo -e "${GREEN}✓${NC} Created backup: $BACKUP_FILE"
else
    echo -e "${YELLOW}⚠${NC} No ~/.zshrc found, will create one"
fi
echo ""

# Log file
LOG_FILE="$HOME/code/arc-fix/dev-env-org-log-$(date +%Y%m%d-%H%M%S).txt"
exec > >(tee -a "$LOG_FILE") 2>&1

# Function to move directory and update config
move_and_update() {
    local source=$1
    local dest=$2
    local env_var=$3
    local path_add=$4

    echo ""
    echo "----------------------------------------"
    echo "Moving: $source"
    echo "To: $dest"
    echo "----------------------------------------"

    # Create parent directory
    PARENT_DIR=$(dirname "$dest")
    if [ ! -d "$PARENT_DIR" ]; then
        mkdir -p "$PARENT_DIR"
        echo -e "${GREEN}✓${NC} Created directory: $PARENT_DIR"
    fi

    # Check if destination exists
    if [ -d "$dest" ]; then
        echo -e "${RED}✗${NC} Destination already exists: $dest"
        echo "Skipping this move."
        return 1
    fi

    # Move directory
    if mv "$source" "$dest"; then
        echo -e "${GREEN}✓${NC} Moved successfully"
    else
        echo -e "${RED}✗${NC} Failed to move directory"
        return 1
    fi

    # Update shell config
    if [ -n "$env_var" ]; then
        echo "" >> "$SHELL_CONFIG"
        echo "# Added by dev-env-organizer $(date +%Y-%m-%d)" >> "$SHELL_CONFIG"
        echo "export $env_var" >> "$SHELL_CONFIG"
        echo -e "${GREEN}✓${NC} Added to ~/.zshrc: export $env_var"
    fi

    if [ -n "$path_add" ]; then
        echo "export PATH=\"$path_add:\$PATH\"" >> "$SHELL_CONFIG"
        echo -e "${GREEN}✓${NC} Added to PATH: $path_add"
    fi

    return 0
}

# Function to ask yes/no question
ask_yes_no() {
    local question=$1
    echo ""
    echo -e "${BLUE}?${NC} $question"
    read -p "  (y/n): " response
    case "$response" in
        [yY][eE][sS]|[yY]) return 0 ;;
        *) return 1 ;;
    esac
}

# ============================================
# PYTHON (pyenv)
# ============================================
if [ -d "$HOME/.pyenv" ] && [ ! -d "$HOME/code/python/pyenv" ]; then
    if ask_yes_no "Move ~/.pyenv to ~/code/python/pyenv?"; then
        move_and_update \
            "$HOME/.pyenv" \
            "$HOME/code/python/pyenv" \
            "PYENV_ROOT=\"\$HOME/code/python/pyenv\"" \
            "\$PYENV_ROOT/bin"
    fi
fi

# ============================================
# RUBY (rbenv)
# ============================================
if [ -d "$HOME/.rbenv" ] && [ ! -d "$HOME/code/ruby/rbenv" ]; then
    if ask_yes_no "Move ~/.rbenv to ~/code/ruby/rbenv?"; then
        move_and_update \
            "$HOME/.rbenv" \
            "$HOME/code/ruby/rbenv" \
            "RBENV_ROOT=\"\$HOME/code/ruby/rbenv\"" \
            "\$RBENV_ROOT/bin"
    fi
fi

# ============================================
# RUST (cargo and rustup)
# ============================================
if [ -d "$HOME/.cargo" ] && [ ! -d "$HOME/code/rust/cargo" ]; then
    if ask_yes_no "Move ~/.cargo to ~/code/rust/cargo?"; then
        move_and_update \
            "$HOME/.cargo" \
            "$HOME/code/rust/cargo" \
            "CARGO_HOME=\"\$HOME/code/rust/cargo\"" \
            "\$CARGO_HOME/bin"
    fi
fi

if [ -d "$HOME/.rustup" ] && [ ! -d "$HOME/code/rust/rustup" ]; then
    if ask_yes_no "Move ~/.rustup to ~/code/rust/rustup?"; then
        move_and_update \
            "$HOME/.rustup" \
            "$HOME/code/rust/rustup" \
            "RUSTUP_HOME=\"\$HOME/code/rust/rustup\"" \
            ""
    fi
fi

# ============================================
# NODE.JS (npm global prefix)
# ============================================
if command -v npm &> /dev/null; then
    NPM_PREFIX=$(npm config get prefix)
    if [[ "$NPM_PREFIX" != "$HOME/code/"* ]] && [ "$NPM_PREFIX" != "/usr/local" ]; then
        if ask_yes_no "Move npm global prefix to ~/code/node?"; then
            # Create directory
            mkdir -p "$HOME/code/node"

            # Update npm config
            npm config set prefix "$HOME/code/node"
            echo -e "${GREEN}✓${NC} Updated npm global prefix"

            # Add to PATH
            echo "" >> "$SHELL_CONFIG"
            echo "# Added by dev-env-organizer $(date +%Y-%m-%d)" >> "$SHELL_CONFIG"
            echo "export PATH=\"\$HOME/code/node/bin:\$PATH\"" >> "$SHELL_CONFIG"
            echo -e "${GREEN}✓${NC} Added ~/code/node/bin to PATH"
        fi
    fi
fi

# ============================================
# SUMMARY
# ============================================
echo ""
echo "========================================="
echo "ORGANIZATION COMPLETE"
echo "========================================="
echo ""
echo -e "${GREEN}✓${NC} All requested moves completed!"
echo ""
echo "Next steps:"
echo "  1. Open a new terminal OR run: source ~/.zshrc"
echo "  2. Test your development tools to ensure they work"
echo "  3. Check the log file: $LOG_FILE"
echo ""
echo "Your original shell config was backed up to:"
echo "  $BACKUP_FILE"
echo ""

exit 0
