#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

if (( $# > 1 )); then
    echo "Usage: bash scripts/make-dmg.sh [output.dmg]" >&2
    exit 1
fi
APP="$PWD/build/Glissform.app"
if [[ ! -d "$APP" ]]; then
    echo "Build the release app first: bash scripts/build.sh --release" >&2
    exit 1
fi
PLIST="$APP/Contents/Info.plist"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST")" != "com.george.glissform.mvp" ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :GlissformDeveloperTools' "$PLIST")" != "false" ]]; then
    echo "Refusing to package a development app. Build with --release." >&2
    exit 1
fi

VERSION="$(cat VERSION)"
DMG="${1:-$PWD/build/Glissform-$VERSION.dmg}"
[[ "$DMG" == /* ]] || DMG="$PWD/$DMG"
if [[ "$DMG" != *.dmg ]]; then
    echo "Output must have a .dmg extension." >&2
    exit 1
fi
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :GlissformVersion' "$APP/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "Bundle version $BUNDLE_VERSION does not match VERSION $VERSION. Rebuild first." >&2
    exit 1
fi
codesign --verify --strict "$APP"

ICON_NAME="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$PLIST")"
[[ "$ICON_NAME" == *.icns ]] || ICON_NAME="$ICON_NAME.icns"
ICON="$APP/Contents/Resources/$ICON_NAME"
if [[ ! -s "$ICON" ]]; then
    echo "Missing app icon: $ICON" >&2
    exit 1
fi
SETFILE="$(xcrun --find SetFile)"
DMG_TOOLS="$PWD/build/dmg-tools"
if [[ ! -x "$DMG_TOOLS/bin/python3" ]]; then
    python3 -m venv "$DMG_TOOLS"
fi
"$DMG_TOOLS/bin/python3" -m pip install --quiet --disable-pip-version-check \
    --require-hashes --only-binary=:all: -r scripts/dmg-requirements.txt

STAGE="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
MOUNT="$STAGE/mounted"
cleanup() {
    if mount | grep -Fq " on $MOUNT ("; then
        hdiutil detach -quiet "$MOUNT" || return
    fi
    rm -rf "$STAGE"
}
trap cleanup EXIT
mkdir -p "$STAGE/content/.background" "$MOUNT"
swift scripts/render-dmg-background.swift Artwork/Installer/layout.json Artwork/Installer/Starfield.png "$STAGE/artwork"
tiffutil -cathidpicheck "$STAGE/artwork/background.png" "$STAGE/artwork/background@2x.png" \
    -out "$STAGE/content/.background/background.tiff"
ditto "$APP" "$STAGE/content/Glissform.app"
ln -s /Applications "$STAGE/content/Applications"
cp "$ICON" "$STAGE/content/.VolumeIcon.icns"
# Set the flag on the actual volume: srcfolder does not preserve this flag.
hdiutil create -quiet -fs HFS+ -volname Glissform -srcfolder "$STAGE/content" -format UDRW "$STAGE/writable.dmg"
hdiutil attach -quiet -nobrowse -mountpoint "$MOUNT" "$STAGE/writable.dmg"
"$SETFILE" -a C "$MOUNT"
"$DMG_TOOLS/bin/python3" scripts/configure-dmg.py "$MOUNT" Artwork/Installer/layout.json
hdiutil detach -quiet "$MOUNT"

hdiutil convert -quiet "$STAGE/writable.dmg" -format UDZO -ov -o "$DMG"
hdiutil verify -quiet "$DMG"
# The file icon is local Finder metadata; HTTP downloads do not preserve it.
swift scripts/set-file-icon.swift "$ICON" "$DMG"
printf 'Created %s\n' "$DMG"
shasum -a 256 "$DMG"
