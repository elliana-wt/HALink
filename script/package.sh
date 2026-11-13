#!/usr/bin/env bash
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$ROOT_DIR/Resources/Info.plist")"
OUTPUT_PATH="${1:-$ROOT_DIR/dist/HALink-$VERSION.dmg}"
BUILD_CONFIGURATION=release "$ROOT_DIR/script/build_and_run.sh" --build-only
STAGE_DIR="$(mktemp -d /private/tmp/HALink-package.XXXXXX)"
trap 'rm -rf "$STAGE_DIR"' EXIT
ditto --norsrc --noextattr "$ROOT_DIR/dist/HALink.app" "$STAGE_DIR/HALink.app"
xattr -cr "$STAGE_DIR/HALink.app"
codesign --force --sign - --identifier app.enfinity.Hestia "$STAGE_DIR/HALink.app"
codesign --verify --strict "$STAGE_DIR/HALink.app"
ln -s /Applications "$STAGE_DIR/Applications"
mkdir -p "$(dirname "$OUTPUT_PATH")"
hdiutil create -volname HALink -srcfolder "$STAGE_DIR" -ov -format UDZO "$OUTPUT_PATH"
