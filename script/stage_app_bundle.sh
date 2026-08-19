#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "usage: $0 <binary> <app-bundle>" >&2
  exit 2
fi

APP_NAME="Kick"
BUNDLE_ID="co.nousworks.kick"
VERSION="${KICK_VERSION:-1.0.0}"
BUILD_NUMBER="${KICK_BUILD_NUMBER:-1}"
MIN_SYSTEM_VERSION="14.0"
SIGN_IDENTITY="${KICK_SIGN_IDENTITY--}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_BINARY="$1"
APP_BUNDLE="$2"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
ICON_FILE="$ROOT_DIR/Resources/Kick.icns"

if [[ ! -f "$BUILD_BINARY" || ! -x "$BUILD_BINARY" ]]; then
  echo "missing executable build product: $BUILD_BINARY" >&2
  exit 1
fi

if [[ "$(basename "$APP_BUNDLE")" != "$APP_NAME.app" ]]; then
  echo "the app bundle path must end with $APP_NAME.app" >&2
  exit 2
fi

case "$APP_BUNDLE" in
  "$ROOT_DIR/dist/$APP_NAME.app"|"$ROOT_DIR/dist/release/$APP_NAME.app")
    ;;
  *)
    echo "the app bundle path must be dist/$APP_NAME.app or dist/release/$APP_NAME.app" >&2
    exit 2
    ;;
esac

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "KICK_VERSION must contain one to three numeric components." >&2
  exit 2
fi

if [[ ! "$BUILD_NUMBER" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "KICK_BUILD_NUMBER must contain one to three numeric components." >&2
  exit 2
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "KICK_SIGN_IDENTITY cannot be empty. Omit it for an ad hoc signature." >&2
  exit 2
fi

if [[ ! -f "$ICON_FILE" ]]; then
  "$ROOT_DIR/script/generate_app_icon.sh" >/dev/null
fi

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
cp "$ICON_FILE" "$APP_RESOURCES/Kick.icns"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleIconFile</key>
  <string>Kick.icns</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>$VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>LSApplicationCategoryType</key>
  <string>public.app-category.utilities</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSHumanReadableCopyright</key>
  <string>© 2026 nousworks. MIT License.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

plutil -lint "$INFO_PLIST" >/dev/null

if [[ "$SIGN_IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP_BUNDLE"
else
  codesign \
    --force \
    --options runtime \
    --timestamp \
    --sign "$SIGN_IDENTITY" \
    "$APP_BUNDLE"
fi

codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
