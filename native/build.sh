#!/bin/bash
# Assemble Eyebreak.swift into a proper Eyebreak.app bundle.
#
# A menu-bar app needs a bundle (Info.plist + CFBundleIdentifier) for user
# notifications to work and to run as a background agent (LSUIElement), so we
# compile the single source into Contents/MacOS and wrap it in a minimal bundle.
#
# Usage: ./build.sh [output_dir]   (default: ./build)
set -euo pipefail

VERSION="1.2.0"
SRC_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OUT_DIR="${1:-$SRC_DIR/build}"
APP="$OUT_DIR/Eyebreak.app"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

# Compile the app. xcrun resolves the toolchain whether it's full Xcode or CLT.
xcrun swiftc -O "$SRC_DIR/Eyebreak.swift" -o "$APP/Contents/MacOS/Eyebreak"

cat >"$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Eyebreak</string>
    <key>CFBundleDisplayName</key><string>Eyebreak</string>
    <key>CFBundleIdentifier</key><string>com.eyebreak.app</string>
    <key>CFBundleExecutable</key><string>Eyebreak</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>$VERSION</string>
    <key>CFBundleVersion</key><string>$VERSION</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
    <key>NSPrincipalClass</key><string>NSApplication</string>
</dict>
</plist>
EOF

# Ad-hoc sign so the bundle has a stable identity for notifications / TCC. This
# is not Developer ID signing (no notarization) — fine for a locally built app.
codesign --force --sign - "$APP" 2>/dev/null || true

echo "Built $APP"
