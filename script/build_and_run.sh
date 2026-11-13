#!/usr/bin/env bash
set -euo pipefail
MODE="${1:-run}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
APP_NAME="HALink"
BUNDLE_ID="app.enfinity.Hestia"
APP_BUNDLE="$ROOT_DIR/dist/$APP_NAME.app"
BUILD_CONFIGURATION="${BUILD_CONFIGURATION:-debug}"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/ModuleCache"
if [[ "$MODE" != "--build-only" ]]; then
  pkill -x "$APP_NAME" >/dev/null 2>&1 || true
  pkill -x Hestia >/dev/null 2>&1 || true
fi
swift build --disable-sandbox --scratch-path .build --configuration "$BUILD_CONFIGURATION" --product "$APP_NAME"
BIN_DIR="$(swift build --disable-sandbox --scratch-path .build --configuration "$BUILD_CONFIGURATION" --show-bin-path)"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$BIN_DIR/$APP_NAME" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"
cp Resources/Info.plist "$APP_BUNDLE/Contents/Info.plist"
if [[ ! -f Resources/AppIcon.icns ]]; then
  swift script/make_icon.swift
fi
cp Resources/AppIcon.icns "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
xattr -cr "$APP_BUNDLE"
codesign --force --sign - --identifier "$BUNDLE_ID" "$APP_BUNDLE"
case "$MODE" in
  --build-only) ;;
  run) /usr/bin/open -n "$APP_BUNDLE" ;;
  --verify|verify)
    /usr/bin/open -n "$APP_BUNDLE"
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null ;;
  --debug|debug) lldb -- "$APP_BUNDLE/Contents/MacOS/$APP_NAME" ;;
  --logs|logs)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'process == "HALink"' ;;
  --telemetry|telemetry)
    /usr/bin/open -n "$APP_BUNDLE"
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "app.enfinity.Hestia"' ;;
  *) echo "usage: $0 [run|--build-only|--verify|--debug|--logs|--telemetry]" >&2; exit 2 ;;
esac
