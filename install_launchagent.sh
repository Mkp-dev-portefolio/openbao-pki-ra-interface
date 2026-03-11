#!/bin/bash
# Install macOS LaunchAgent for monitoring

PLIST_NAME="com.openbao.pki.monitoring.plist"
PLIST_SOURCE="/Users/ismailzemouri/OpenBao PKI/$PLIST_NAME"
PLIST_DEST="$HOME/Library/LaunchAgents/$PLIST_NAME"

echo "======================================================"
echo "  Installing macOS LaunchAgent for PKI Monitoring"
echo "======================================================"
echo ""

# Create LaunchAgents directory if it doesn't exist
mkdir -p "$HOME/Library/LaunchAgents"

# Copy plist file
echo "📋 Installing LaunchAgent..."
cp "$PLIST_SOURCE" "$PLIST_DEST"

# Load the agent
echo "🚀 Loading LaunchAgent..."
launchctl unload "$PLIST_DEST" 2>/dev/null  # Unload if already loaded
launchctl load "$PLIST_DEST"

echo ""
echo "✅ LaunchAgent installed successfully!"
echo ""
echo "📅 Schedule: Daily at 9:00 AM"
echo "📁 Logs:"
echo "   - Output: monitoring_reports/launchd.log"
echo "   - Errors: monitoring_reports/launchd.error.log"
echo ""
echo "Useful commands:"
echo "  - Check status: launchctl list | grep openbao"
echo "  - View logs: tail -f monitoring_reports/launchd.log"
echo "  - Test now: launchctl start $PLIST_NAME"
echo "  - Disable: launchctl unload $PLIST_DEST"
echo "  - Re-enable: launchctl load $PLIST_DEST"
echo ""
