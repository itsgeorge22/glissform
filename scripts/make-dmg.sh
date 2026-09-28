#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

APP="$PWD/build/Glissform.app"
if [[ ! -d "$APP" ]]; then
    echo "Build the app first: bash scripts/build.sh" >&2
    exit 1
fi

VERSION="$(cat VERSION)"
BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :GlissformVersion' "$APP/Contents/Info.plist")"
if [[ "$BUNDLE_VERSION" != "$VERSION" ]]; then
    echo "Bundle version $BUNDLE_VERSION does not match VERSION $VERSION. Rebuild first." >&2
    exit 1
fi
codesign --verify --strict "$APP"

STAGE="$(mktemp -d "$PWD/build/dmg-stage.XXXXXX")"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/Glissform.app"
ln -s /Applications "$STAGE/Applications"

DMG="$PWD/build/Glissform-$VERSION.dmg"
hdiutil create -quiet -fs HFS+ -volname Glissform -srcfolder "$STAGE" -format UDZO -ov "$DMG"
hdiutil verify -quiet "$DMG"
printf 'Created %s\n' "$DMG"
shasum -a 256 "$DMG"
