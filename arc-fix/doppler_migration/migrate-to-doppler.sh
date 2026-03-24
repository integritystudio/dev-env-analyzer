#!/bin/bash

# Script to migrate authentication credentials from .env to Doppler
# Usage: ./migrate-to-doppler.sh [project] [config]
# Example: ./migrate-to-doppler.sh my-project dev

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
ENV_FILE="${ENV_FILE:-.env}"
PROJECT="${1}"
CONFIG="${2:-dev}"

echo -e "${YELLOW}=== Doppler Migration Script ===${NC}"
echo ""

# Check if Doppler CLI is installed
if ! command -v doppler &> /dev/null; then
    echo -e "${RED}Error: Doppler CLI is not installed${NC}"
    echo "Install it with: brew install dopplerhq/cli/doppler"
    exit 1
fi

# Check if .env file exists
if [ ! -f "$ENV_FILE" ]; then
    echo -e "${RED}Error: $ENV_FILE file not found${NC}"
    exit 1
fi

# Check if user is logged in to Doppler
if ! doppler me &> /dev/null; then
    echo -e "${YELLOW}You need to login to Doppler first${NC}"
    echo "Run: doppler login"
    exit 1
fi

# If project is not specified, show available projects
if [ -z "$PROJECT" ]; then
    echo -e "${YELLOW}Available Doppler projects:${NC}"
    doppler projects list
    echo ""
    echo -e "${RED}Error: Please specify a project${NC}"
    echo "Usage: $0 <project> [config]"
    echo "Example: $0 my-project dev"
    exit 1
fi

# Verify project exists
if ! doppler projects get "$PROJECT" &> /dev/null; then
    echo -e "${YELLOW}Project '$PROJECT' does not exist. Would you like to create it? (y/n)${NC}"
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        doppler projects create "$PROJECT" --description "Migrated from .env"
        echo -e "${GREEN}Project created successfully${NC}"
    else
        exit 1
    fi
fi

# Verify config exists, if not create it
if ! doppler configs get "$CONFIG" --project "$PROJECT" &> /dev/null; then
    echo -e "${YELLOW}Config '$CONFIG' does not exist. Creating it...${NC}"
    doppler configs create "$CONFIG" --project "$PROJECT"
    echo -e "${GREEN}Config created successfully${NC}"
fi

echo -e "${GREEN}Migrating secrets from $ENV_FILE to Doppler${NC}"
echo "Project: $PROJECT"
echo "Config: $CONFIG"
echo ""

# Parse .env file and upload to Doppler
# Filter for authentication-related variables
AUTH_PATTERNS="API_KEY|CLIENT_ID|CLIENT_SECRET|HUBSPOT|PUBLIC_KEY|PRIVATE_KEY|TOKEN|PASSWORD|SECRET|CREDENTIALS"

MIGRATED_COUNT=0
SKIPPED_COUNT=0
FAILED_COUNT=0

# Read .env file line by line
while IFS= read -r line; do
    # Skip comments and empty lines
    if [[ $line =~ ^#.*$ ]] || [[ -z $line ]]; then
        continue
    fi

    # Parse key=value pairs
    if [[ $line =~ ^([A-Za-z_][A-Za-z0-9_]*)=(.*)$ ]]; then
        KEY="${BASH_REMATCH[1]}"
        VALUE="${BASH_REMATCH[2]}"

        # Check if this is an authentication-related variable
        if [[ $KEY =~ $AUTH_PATTERNS ]]; then
            echo -e "${YELLOW}Migrating: $KEY${NC}"

            # Upload to Doppler
            if echo "$VALUE" | doppler secrets set "$KEY" --project "$PROJECT" --config "$CONFIG" --silent; then
                echo -e "${GREEN}✓ Successfully migrated: $KEY${NC}"
                ((MIGRATED_COUNT++))
            else
                echo -e "${RED}✗ Failed to migrate: $KEY${NC}"
                ((FAILED_COUNT++))
            fi
        else
            echo -e "Skipping non-auth variable: $KEY"
            ((SKIPPED_COUNT++))
        fi
    fi
done < "$ENV_FILE"

echo ""
echo -e "${GREEN}=== Migration Summary ===${NC}"
echo "Migrated: $MIGRATED_COUNT"
echo "Skipped: $SKIPPED_COUNT"
echo "Failed: $FAILED_COUNT"
echo ""

if [ $FAILED_COUNT -eq 0 ]; then
    echo -e "${GREEN}✓ Migration completed successfully!${NC}"
    echo ""
    echo "To use these secrets in your application:"
    echo "  doppler run --project $PROJECT --config $CONFIG -- <your-command>"
    echo ""
    echo "Or to view the secrets:"
    echo "  doppler secrets --project $PROJECT --config $CONFIG"
else
    echo -e "${RED}Migration completed with errors${NC}"
    exit 1
fi
