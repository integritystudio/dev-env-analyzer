#!/bin/bash
#
# Cron Setup Script for Go Functionality Tests
# This script adds a cron job to run Go tests nightly at 2 AM
#

echo "Setting up cron job for Go functionality tests..."

# Create temporary file with new cron entry
TEMP_CRON=$(mktemp)

# Export existing crontab (if any)
crontab -l 2>/dev/null > "$TEMP_CRON" || true

# Check if our cron job already exists
if grep -q "go-functionality-test.sh" "$TEMP_CRON"; then
    echo "Cron job already exists. Updating..."
    # Remove old entry
    grep -v "go-functionality-test.sh" "$TEMP_CRON" > "${TEMP_CRON}.new"
    mv "${TEMP_CRON}.new" "$TEMP_CRON"
fi

# Add new cron job entry
# Run every night at 2:00 AM
echo "" >> "$TEMP_CRON"
echo "# Go Functionality Test - runs nightly at 2:00 AM" >> "$TEMP_CRON"
echo "0 2 * * * /bin/bash $HOME/code/arc-fix/go-functionality-test.sh" >> "$TEMP_CRON"

# Install new crontab
crontab "$TEMP_CRON"

# Clean up
rm "$TEMP_CRON"

echo "✓ Cron job installed successfully!"
echo ""
echo "The Go functionality test will run every night at 2:00 AM."
echo "Logs will be saved to: $HOME/code/arc-fix/go-test-logs/"
echo ""
echo "To view your crontab:"
echo "  crontab -l"
echo ""
echo "To remove the cron job:"
echo "  crontab -e"
echo "  (then delete the go-functionality-test line)"
