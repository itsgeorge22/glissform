#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_VARIANT="${1:---dev}"
if [[ "$BUILD_VARIANT" != "--dev" && "$BUILD_VARIANT" != "--release" ]]; then
    echo "Usage: bash scripts/build.sh [--dev|--release]" >&2
    exit 1
fi
if [[ "$BUILD_VARIANT" == "--dev" ]]; then
    DEV_TOOLS=true
    APP_NAME="Glissform Dev"
    BUNDLE_ID="com.george.glissform.mvp.dev"
    ICON_SOURCE="$PWD/Artwork/GlissformDev.icon"
    ICON_NAME="GlissformDev"
    UPDATE_PLIST='<key>SUEnableAutomaticChecks</key><false/>'
else
    DEV_TOOLS=false
    APP_NAME="Glissform"
    BUNDLE_ID="com.george.glissform.mvp"
    ICON_SOURCE="$PWD/Artwork/Glissform.icon"
    ICON_NAME="Glissform"
    UPDATE_PLIST=''
fi
APP_VERSION="$(cat VERSION)"
APP_BUILD="$(cat BUILD_NUMBER)"
if [[ ! "$APP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-(alpha|beta|rc)\.[0-9]+)?$ ]] || [[ ! "$APP_BUILD" =~ ^[1-9][0-9]*$ ]]; then
    echo "Invalid VERSION or BUILD_NUMBER" >&2
    exit 1
fi
APP_SHORT_VERSION="${APP_VERSION%%-*}"
SPARKLE_PUBLIC_KEY=""
if [[ "$BUILD_VARIANT" == "--release" ]]; then
    SPARKLE_PUBLIC_KEY_FILE="$PWD/config/sparkle-public-key.txt"
    if [[ ! -f "$SPARKLE_PUBLIC_KEY_FILE" ]]; then
        echo "Missing Sparkle public key: $SPARKLE_PUBLIC_KEY_FILE" >&2
        exit 1
    fi
    SPARKLE_PUBLIC_KEY="$(tr -d '\r\n' < "$SPARKLE_PUBLIC_KEY_FILE")"
    if [[ ! "$SPARKLE_PUBLIC_KEY" =~ ^[A-Za-z0-9+/]{43}=$ ]]; then
        echo "Invalid Sparkle EdDSA public key in $SPARKLE_PUBLIC_KEY_FILE" >&2
        exit 1
    fi
fi
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
SDK_VERSION="$(xcrun --sdk macosx --show-sdk-version)"
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
# Xcode 26 uses positional --export-preview arguments; Xcode 27 renamed
# the command and switched to named arguments. Detect the actual capability.
ICON_HELP="$("$ICON_COMPOSER" --help 2>&1 || true)"
if [[ "$ICON_HELP" == *"--export-image"* ]]; then
    ICON_EXPORT_MODE=image
elif [[ "$ICON_HELP" == *"--export-preview"* ]]; then
    ICON_EXPORT_MODE=preview
else
    echo "Unsupported Icon Composer export interface in Xcode $XCODE_VERSION." >&2
    exit 1
fi
for appearance in ClearDark; do
    for scale in 1 2; do
        if [[ "$ICON_EXPORT_MODE" == image ]]; then
            "$ICON_COMPOSER" "$ICON_SOURCE" \
                --export-image --output-file "$MENU_ASSET/$appearance-$scale.png" \
                --platform macOS --rendition "$appearance" --width 18 --height 18 --scale "$scale"
        else
            "$ICON_COMPOSER" "$ICON_SOURCE" \
                --export-preview macOS "$appearance" 18 18 "$scale" "$MENU_ASSET/$appearance-$scale.png"
        fi
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
xcrun actool "$ICON_SOURCE" \
    "$ICON_BUILD/MenuBar.xcassets" \
    --compile "$ICON_BUILD/Resources" \
    --app-icon "$ICON_NAME" \
    --platform macosx \
    --minimum-deployment-target 15.0 \
    --output-partial-info-plist "$ICON_BUILD/Info.plist" \
    --output-format human-readable-text \
    --notices --warnings
if [[ ! -s "$ICON_BUILD/Resources/Assets.car" ]] || [[ ! -s "$ICON_BUILD/Resources/$ICON_NAME.icns" ]]; then
    echo "The app icon compiler did not produce both native and legacy icon resources." >&2
    exit 1
fi
# SwiftPM's package-product linker can stamp the executable with the deployment
# target as its SDK version. Declare the actual SDK so AppKit uses the current
# native window-control appearance on newer macOS releases.
swift build -c release \
    -Xlinker -platform_version -Xlinker macos -Xlinker 15.0 -Xlinker "$SDK_VERSION" \
    -Xlinker -rpath -Xlinker @executable_path/../Frameworks
APP="$PWD/build/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS"
BIN_DIR="$(swift build -c release --show-bin-path)"
LINKED_SDK="$(xcrun vtool -show-build "$BIN_DIR/Glissform" | awk '$1 == "sdk" { print $2; exit }')"
if [[ "$LINKED_SDK" != "$SDK_VERSION" ]]; then
    echo "Expected macOS SDK $SDK_VERSION in the app executable, found ${LINKED_SDK:-none}." >&2
    exit 1
fi
cp "$BIN_DIR/Glissform" "$APP/Contents/MacOS/Glissform"
# SwiftPM links binary frameworks but does not embed them in a manually
# assembled .app. Preserve Sparkle's framework symlinks and executable modes.
SPARKLE_SOURCE="$PWD/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"
if [[ ! -d "$SPARKLE_SOURCE" ]]; then
    echo "Sparkle.framework is missing from SwiftPM's resolved binary artifact." >&2
    exit 1
fi
SPARKLE_FRAMEWORK="$APP/Contents/Frameworks/Sparkle.framework"
mkdir -p "$APP/Contents/Frameworks"
rm -rf "$SPARKLE_FRAMEWORK"
ditto "$SPARKLE_SOURCE" "$SPARKLE_FRAMEWORK"
mkdir -p "$APP/Contents/Resources"
rm -rf "$APP/Contents/Resources/Glissform_Glissform.bundle"
ditto "$BIN_DIR/Glissform_Glissform.bundle" "$APP/Contents/Resources/Glissform_Glissform.bundle"
# Some Xcode/SwiftPM versions emit package resources as a flat directory with
# no bundle metadata. Bundle.module cannot load that layout in an installed app.
RESOURCE_BUNDLE="$APP/Contents/Resources/Glissform_Glissform.bundle"
if [[ ! -f "$RESOURCE_BUNDLE/Contents/Info.plist" ]]; then
    RESOURCE_STAGE="$(mktemp -d "$PWD/build/resource-bundle.XXXXXX")"
    ditto "$RESOURCE_BUNDLE" "$RESOURCE_STAGE/Resources"
    rm -rf "$RESOURCE_BUNDLE"
    mkdir -p "$RESOURCE_BUNDLE/Contents"
    mv "$RESOURCE_STAGE/Resources" "$RESOURCE_BUNDLE/Contents/Resources"
    rmdir "$RESOURCE_STAGE"
    cat > "$RESOURCE_BUNDLE/Contents/Info.plist" <<'BUNDLE_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>com.george.glissform.resources</string>
<key>CFBundleName</key><string>Glissform_Glissform</string>
<key>CFBundlePackageType</key><string>BNDL</string>
</dict></plist>
BUNDLE_PLIST
fi
if [[ ! -s "$RESOURCE_BUNDLE/Contents/Info.plist" ||
      ! -s "$RESOURCE_BUNDLE/Contents/Resources/FeatureIcons/monitor-display.svg" ]]; then
    echo "Glissform package resources are incomplete or not loadable as a bundle." >&2
    exit 1
fi
ditto "$ICON_BUILD/Resources" "$APP/Contents/Resources"
rm -f "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cp "$PWD/docs/SPARKLE_LICENSE.txt" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>Glissform</string>
<key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
<key>GlissformDeveloperTools</key><$DEV_TOOLS/>
<key>CFBundleName</key><string>$APP_NAME</string>
<key>CFBundleDisplayName</key><string>$APP_NAME</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
<key>CFBundleShortVersionString</key><string>$APP_SHORT_VERSION</string>
<key>GlissformVersion</key><string>$APP_VERSION</string>
<key>CFBundleVersion</key><string>$APP_BUILD</string>
$UPDATE_PLIST
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Glissform animates your desktop as the lid closes. Screen images stay in memory and are never saved or transmitted.</string>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Merge '$ICON_BUILD/Info.plist'" "$APP/Contents/Info.plist"
if [[ "$BUILD_VARIANT" == "--release" ]]; then
    /usr/libexec/PlistBuddy -c "Add :SUFeedURL string https://glissform.app/updates/appcast.xml" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $SPARKLE_PUBLIC_KEY" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SURequireSignedFeed bool true" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUVerifyUpdateBeforeExtraction bool true" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableAutomaticChecks bool true" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUScheduledCheckInterval integer 3600" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUAutomaticallyUpdate bool false" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Add :SUEnableSystemProfiling bool false" "$APP/Contents/Info.plist"
fi
# Rebuilding resources in place does not update the .app directory date. Let
# Launch Services notice the changed icon on the next launch.
touch "$APP"
# Sign nested Sparkle code before signing the containing framework and app.
# Avoid --deep for signing: Sparkle helpers have distinct bundle identities
# and the downloader may carry its own entitlements.
SPARKLE_VERSION_DIR="$SPARKLE_FRAMEWORK/Versions/Current"
codesign --force --sign - --options runtime "$SPARKLE_VERSION_DIR/XPCServices/Installer.xpc"
codesign --force --sign - --options runtime --preserve-metadata=entitlements "$SPARKLE_VERSION_DIR/XPCServices/Downloader.xpc"
codesign --force --sign - --options runtime "$SPARKLE_VERSION_DIR/Autoupdate"
codesign --force --sign - --options runtime "$SPARKLE_VERSION_DIR/Updater.app"
codesign --force --sign - --options runtime "$SPARKLE_FRAMEWORK"
# Stable local identity allows subsequent development builds to reuse permission.
codesign --force --sign - --identifier "$BUNDLE_ID" --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
codesign --verify --deep --strict "$APP"
printf 'Built %s\n' "$APP"
