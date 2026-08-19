#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Kick"
VERSION="${KICK_VERSION:-1.0.0}"
SIGN_IDENTITY="${KICK_SIGN_IDENTITY--}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RELEASE_DIR="$ROOT_DIR/dist/release"
APP_BUNDLE="$RELEASE_DIR/$APP_NAME.app"
ARCHIVE="$RELEASE_DIR/$APP_NAME-$VERSION-macOS.zip"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache"

if [[ ! "$VERSION" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "KICK_VERSION must contain one to three numeric components." >&2
  exit 2
fi

if [[ ! "${KICK_BUILD_NUMBER:-1}" =~ ^[0-9]+([.][0-9]+){0,2}$ ]]; then
  echo "KICK_BUILD_NUMBER must contain one to three numeric components." >&2
  exit 2
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  echo "KICK_SIGN_IDENTITY cannot be empty. Omit it for an ad hoc signature." >&2
  exit 2
fi

read -r -a ARCHITECTURES <<<"${KICK_ARCHS:-arm64 x86_64}"

if [[ ${#ARCHITECTURES[@]} -eq 0 ]]; then
  echo "KICK_ARCHS must contain arm64, x86_64, or both." >&2
  exit 2
fi

for architecture in "${ARCHITECTURES[@]}"; do
  if [[ "$architecture" != "arm64" && "$architecture" != "x86_64" ]]; then
    echo "unsupported architecture: $architecture" >&2
    exit 2
  fi
done

if [[ -n "${KICK_NOTARY_PROFILE:-}" && "$SIGN_IDENTITY" == "-" ]]; then
  echo "KICK_NOTARY_PROFILE requires a Developer ID KICK_SIGN_IDENTITY." >&2
  exit 2
fi

BUILD_ARGUMENTS=(-c release --disable-sandbox)
for architecture in "${ARCHITECTURES[@]}"; do
  BUILD_ARGUMENTS+=(--arch "$architecture")
done

mkdir -p "$RELEASE_DIR"
BIN_DIRECTORY="$(swift build "${BUILD_ARGUMENTS[@]}" --show-bin-path)"
swift build "${BUILD_ARGUMENTS[@]}"
"$ROOT_DIR/script/stage_app_bundle.sh" \
  "$BIN_DIRECTORY/$APP_NAME" \
  "$APP_BUNDLE"

BUILT_ARCHITECTURES="$(lipo -archs "$APP_BUNDLE/Contents/MacOS/$APP_NAME")"
for architecture in "${ARCHITECTURES[@]}"; do
  if [[ " $BUILT_ARCHITECTURES " != *" $architecture "* ]]; then
    echo "missing architecture: $architecture" >&2
    exit 1
  fi
done

rm -f "$ARCHIVE"
/usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"
/usr/bin/unzip -t "$ARCHIVE" >/dev/null

if [[ -n "${KICK_NOTARY_PROFILE:-}" ]]; then
  xcrun notarytool submit \
    "$ARCHIVE" \
    --keychain-profile "$KICK_NOTARY_PROFILE" \
    --wait
  xcrun stapler staple "$APP_BUNDLE"
  xcrun stapler validate "$APP_BUNDLE"
  rm -f "$ARCHIVE"
  /usr/bin/ditto -c -k --keepParent "$APP_BUNDLE" "$ARCHIVE"
  /usr/bin/unzip -t "$ARCHIVE" >/dev/null
  spctl --assess --type execute --verbose=2 "$APP_BUNDLE"
fi

(cd "$RELEASE_DIR" && shasum -a 256 "$(basename "$ARCHIVE")" > SHA256SUMS)

echo "App: $APP_BUNDLE"
echo "Archive: $ARCHIVE"
echo "SHA-256: $(cut -d' ' -f1 "$RELEASE_DIR/SHA256SUMS")"
echo "Architectures: $BUILT_ARCHITECTURES"
if [[ "$SIGN_IDENTITY" == "-" ]]; then
  echo "Signature: ad hoc (local testing only)"
else
  echo "Signature identity: $SIGN_IDENTITY"
fi
if [[ -n "${KICK_NOTARY_PROFILE:-}" ]]; then
  echo "Notarization: complete"
else
  echo "Notarization: not requested"
fi
