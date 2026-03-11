#!/bin/bash
# Setup automated certificate lifecycle monitoring

echo "======================================================"
echo "  Certificate Monitoring - Automated Scheduling Setup"
echo "======================================================"
echo ""

SCRIPT_PATH="/Users/ismailzemouri/OpenBao PKI/monitor_certificate_lifecycle.sh"
CRON_SCHEDULE="0 9 * * *"  # Daily at 9 AM

# Verify script exists and is executable
if [ ! -f "$SCRIPT_PATH" ]; then
    echo "❌ Error: Monitoring script not found at: $SCRIPT_PATH"
    exit 1
fi

if [ ! -x "$SCRIPT_PATH" ]; then
    echo "⚠️  Making script executable..."
    chmod +x "$SCRIPT_PATH"
fi

echo "✅ Monitoring script found: $SCRIPT_PATH"
echo ""

# Show current crontab
echo "Current crontab entries:"
echo "------------------------"
crontab -l 2>/dev/null || echo "(No existing crontab)"
echo ""

# Create new cron entry
CRON_ENTRY="$CRON_SCHEDULE cd /Users/ismailzemouri/OpenBao\ PKI && ./monitor_certificate_lifecycle.sh >> monitoring_reports/cron.log 2>&1"

echo "Proposed cron job:"
echo "------------------------"
echo "$CRON_ENTRY"
echo ""
echo "This will run the monitoring script:"
echo "  - Daily at 9:00 AM"
echo "  - Logs output to: monitoring_reports/cron.log"
echo ""

# Check if already exists
if crontab -l 2>/dev/null | grep -q "monitor_certificate_lifecycle.sh"; then
    echo "⚠️  A monitoring cron job already exists!"
    echo ""
    echo "Existing entry:"
    crontab -l | grep "monitor_certificate_lifecycle.sh"
    echo ""
    read -p "Do you want to replace it? (y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled. No changes made."
        exit 0
    fi
    # Remove old entry
    crontab -l | grep -v "monitor_certificate_lifecycle.sh" | crontab -
fi

# Add new entry
(crontab -l 2>/dev/null; echo "$CRON_ENTRY") | crontab -

echo ""
echo "✅ Cron job installed successfully!"
echo ""

# Verify installation
echo "Verification - New crontab:"
echo "------------------------"
crontab -l
echo ""

# Test run suggestion
echo "======================================================"
echo "  Setup Complete!"
echo "======================================================"
echo ""
echo "📅 Schedule: Daily at 9:00 AM"
echo "📁 Logs: monitoring_reports/cron.log"
echo ""
echo "To test immediately (without waiting for 9 AM):"
echo "  ./monitor_certificate_lifecycle.sh"
echo ""
echo "To view cron log after first run:"
echo "  tail -f monitoring_reports/cron.log"
echo ""
echo "To remove this cron job:"
echo "  crontab -e  # then delete the line"
echo "  # or use: crontab -l | grep -v monitor_certificate_lifecycle.sh | crontab -"
echo ""
