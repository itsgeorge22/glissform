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
# Icon Composer assets need the full Xcode toolchain, not Command Line Tools.
# Discover a standard Xcode installation without changing the user's global selection.
if ! xcrun --find actool >/dev/null 2>&1 && [[ -z "${DEVELOPER_DIR:-}" ]] && [[ -d /Applications/Xcode.app/Contents/Developer ]]; then
    export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
fi
if ! xcrun --find actool >/dev/null 2>&1; then
    echo "Xcode 26 or later is required to compile Glissform's native app icon. Install Xcode, open it once to finish setup, and rebuild." >&2
    exit 1
fi
XCODE_VERSION="$(xcodebuild -version | awk '/^Xcode / { print $2 }')"
if [[ ! "${XCODE_VERSION%%.*}" =~ ^[0-9]+$ ]] || (( ${XCODE_VERSION%%.*} < 26 )); then
    echo "Xcode 26 or later is required; selected version is $XCODE_VERSION." >&2
    exit 1
fi
mkdir -p build
ICON_BUILD="$(mktemp -d "$PWD/build/icon-assets.XXXXXX")"
trap 'rm -rf "$ICON_BUILD"' EXIT
mkdir "$ICON_BUILD/Resources"
ICON_COMPOSER="${DEVELOPER_DIR:-$(xcode-select -p)}/../Applications/Icon Composer.app/Contents/Executables/ictool"
if [[ ! -x "$ICON_COMPOSER" ]]; then
    echo "Icon Composer is required to export the app's Clear appearance for the menu bar." >&2
    exit 1
fi
MENU_ASSET="$ICON_BUILD/MenuBar.xcassets/GlissformMenuBar.imageset"
mkdir -p "$MENU_ASSET"
for appearance in ClearDark; do
    for scale in 1 2; do
        "$ICON_COMPOSER" "$PWD/Artwork/Glissform.icon" \
            --export-image --output-file "$MENU_ASSET/$appearance-$scale.png" \
            --platform macOS --rendition "$appearance" --width 18 --height 18 --scale "$scale"
    done
done
swift scripts/make-menu-template.swift "$MENU_ASSET/ClearDark-1.png" "$MENU_ASSET/ClearDark-2.png"
cat > "$MENU_ASSET/Contents.json" <<'JSON'
{
  "images": [
    {"filename":"ClearDark-1.png","idiom":"mac","scale":"1x"},
    {"filename":"ClearDark-2.png","idiom":"mac","scale":"2x"}
  ],
  "properties": {"template-rendering-intent":"template"},
  "info": {"author":"xcode","version":1}
}
JSON
xcrun actool "$PWD/Artwork/Glissform.icon" \
    "$ICON_BUILD/MenuBar.xcassets" \
    --compile "$ICON_BUILD/Resources" \
    --app-icon Glissform \
    --platform macosx \
    --minimum-deployment-target 14.0 \
    --output-partial-info-plist "$ICON_BUILD/Info.plist" \
    --output-format human-readable-text \
    --notices --warnings
if [[ ! -s "$ICON_BUILD/Resources/Assets.car" ]] || [[ ! -s "$ICON_BUILD/Resources/Glissform.icns" ]]; then
    echo "The app icon compiler did not produce both native and legacy icon resources." >&2
    exit 1
fi
swift build -c release
APP="$PWD/build/Glissform.app"
mkdir -p "$APP/Contents/MacOS"
BIN_DIR="$(swift build -c release --show-bin-path)"
cp "$BIN_DIR/Glissform" "$APP/Contents/MacOS/Glissform"
mkdir -p "$APP/Contents/Resources"
ditto "$BIN_DIR/Glissform_Glissform.bundle" "$APP/Contents/Resources/Glissform_Glissform.bundle"
ditto "$ICON_BUILD/Resources" "$APP/Contents/Resources"
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
/usr/libexec/PlistBuddy -c "Merge '$ICON_BUILD/Info.plist'" "$APP/Contents/Info.plist"
# Rebuilding resources in place does not update the .app directory date. Let
# Launch Services notice the changed icon on the next launch.
touch "$APP"
# Stable local identity allows subsequent development builds to reuse permission.
codesign --force --sign - --identifier com.george.glissform.mvp --requirements '=designated => identifier "com.george.glissform.mvp"' "$APP"
codesign --verify --strict "$APP"
printf 'Built %s\n' "$APP"
