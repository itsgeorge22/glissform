#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
DEV_TOOLS=false
if [[ "${1:-}" == "--dev" ]]; then
    DEV_TOOLS=true
elif [[ "${1:-}" != "" ]]; then
    echo "Usage: bash scripts/build.sh [--dev]" >&2
    exit 1
fi
APP_VERSION="$(cat VERSION)"
APP_BUILD="$(cat BUILD_NUMBER)"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] || [[ ! "$APP_BUILD" =~ ^[0-9]+$ ]]; then
    echo "Invalid VERSION or BUILD_NUMBER" >&2
    exit 1
fi
APP_SHORT_VERSION="${APP_VERSION%%-*}"
swift build -c release
APP="$PWD/build/Glissform.app"
mkdir -p "$APP/Contents/MacOS"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/Glissform" "$APP/Contents/MacOS/Glissform"
mkdir -p "$APP/Contents/Resources"
ditto "$BIN_DIR/Glissform_Glissform.bundle" "$APP/Contents/Resources/Glissform_Glissform.bundle"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Glissform</string>
<key>CFBundleIdentifier</key><string>com.george.glissform.mvp</string>
<key>GlissformDeveloperTools</key><$DEV_TOOLS/>
<key>CFBundleName</key><string>Glissform</string>
<key>CFBundleDisplayName</key><string>Glissform</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$APP_SHORT_VERSION</string>
<key>GlissformVersion</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Glissform animates your desktop as the lid closes. Screen images stay in memory and are never saved or transmitted.</string>
</dict></plist>
PLIST
# Stable local identity allows subsequent development builds to reuse permission.
codesign --force --sign - --identifier com.george.glissform.mvp --requirements '=designated => identifier "com.george.glissform.mvp"' "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
