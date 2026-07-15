#!/bin/bash
# Uninstaller for the 20-20-20 eye-break SwiftBar timer. Removes everything
# install.sh (and the launch-at-login toggle) put on the system: the plugin, the
# helpers in ~/.eyebreak, the login LaunchAgent, and any running blocker.
#
# By default it KEEPS your usage history (stats.csv); pass --purge to delete it
# and the whole ~/.eyebreak directory too.
set -euo pipefail

PURGE=false
[ "${1:-}" = "--purge" ] && PURGE=true

DATA_DIR="$HOME/.eyebreak"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/SwiftBar/Plugins}"
LOGIN_LABEL="com.eyebreak.swiftbar.login"
LOGIN_PLIST="$HOME/Library/LaunchAgents/$LOGIN_LABEL.plist"

# Stop a blocker that happens to be on screen right now.
pkill -f "$DATA_DIR/eyebreak-blocker" 2>/dev/null || true

# Remove the launch-at-login agent (modern API, legacy fallback), then the plist.
if [ -f "$LOGIN_PLIST" ]; then
    launchctl bootout "gui/$(id -u)/$LOGIN_LABEL" 2>/dev/null \
        || launchctl unload "$LOGIN_PLIST" 2>/dev/null || true
    rm -f "$LOGIN_PLIST"
    echo "Removed launch-at-login agent"
fi

# Remove the SwiftBar plugin.
if [ -f "$PLUGIN_DIR/eyebreak.1s.sh" ]; then
    rm -f "$PLUGIN_DIR/eyebreak.1s.sh"
    echo "Removed plugin from $PLUGIN_DIR"
fi

# Remove the helpers / data.
if [ -d "$DATA_DIR" ]; then
    if [ "$PURGE" = true ]; then
        rm -rf "$DATA_DIR"
        echo "Purged $DATA_DIR (including your stats history)"
    else
        # Keep stats.csv (and the config), drop the code and runtime files.
        rm -f "$DATA_DIR/eyebreak-lib.sh" "$DATA_DIR/eyebreak-ctl.sh" \
              "$DATA_DIR/eyebreak-stats.sh" "$DATA_DIR/eyebreak-blocker" \
              "$DATA_DIR/quotes.txt" "$DATA_DIR/state"
        rmdir "$DATA_DIR/.lock" 2>/dev/null || true
        echo "Removed helpers from $DATA_DIR (kept config + stats.csv)"
        echo "  Run with --purge to delete those too."
    fi
fi

echo
echo "Done. Open SwiftBar and 'Refresh All' (or quit it) to drop the menu item."
echo "If you installed via Homebrew, also run: brew uninstall eyebreak-swiftbar"
