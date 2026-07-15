#!/bin/bash
# Installer for the 20-20-20 eye-break SwiftBar timer.
# Copies the plugin into SwiftBar's plugin folder and the helper scripts into
# ~/.eyebreak, then seeds a default config. Safe to re-run (upgrades in place).
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

DATA_DIR="$HOME/.eyebreak"
PLUGIN_DIR="${SWIFTBAR_PLUGIN_DIR:-$HOME/SwiftBar/Plugins}"

if [ ! -d "$PLUGIN_DIR" ]; then
    echo "SwiftBar plugin folder not found at: $PLUGIN_DIR" >&2
    echo "Install SwiftBar (https://swiftbar.app) and set its plugin folder, or" >&2
    echo "re-run with SWIFTBAR_PLUGIN_DIR=/path/to/plugins ./install.sh" >&2
    exit 1
fi

mkdir -p "$DATA_DIR"

# Install the shared library and helpers BEFORE the plugin, so the plugin (which
# runs once per second and sources the lib) is never present without its lib.
install -m 0644 "$REPO_DIR/lib/eyebreak-lib.sh"   "$DATA_DIR/eyebreak-lib.sh"
install -m 0755 "$REPO_DIR/lib/eyebreak-ctl.sh"   "$DATA_DIR/eyebreak-ctl.sh"
install -m 0755 "$REPO_DIR/lib/eyebreak-stats.sh" "$DATA_DIR/eyebreak-stats.sh"
install -m 0755 "$REPO_DIR/plugin/eyebreak.1s.sh" "$PLUGIN_DIR/eyebreak.1s.sh"

# Seed config only if the user does not already have one, so upgrades keep settings.
if [ ! -f "$DATA_DIR/config" ]; then
    cat >"$DATA_DIR/config" <<'EOF'
# Minutes of work between breaks, and minutes per break.
WORK_MINUTES=20
BREAK_MINUTES=2
EOF
    echo "Seeded default config at $DATA_DIR/config"
fi

echo "Installed:"
echo "  plugin -> $PLUGIN_DIR/eyebreak.1s.sh"
echo "  helpers -> $DATA_DIR/{eyebreak-lib.sh,eyebreak-ctl.sh,eyebreak-stats.sh}"
echo
echo "Next: open SwiftBar (or run 'Refresh All' from its menu) to load the plugin."
echo "Grant SwiftBar notification permission when prompted so break alerts appear."
