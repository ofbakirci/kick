#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TOOLS_DIR="$ROOT_DIR/.build/tools"
ICON_FILE="$ROOT_DIR/Resources/Kick.icns"
GENERATOR="$TOOLS_DIR/AppIconGenerator"

export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"

mkdir -p "$TOOLS_DIR" "$ROOT_DIR/Resources"
xcrun swiftc \
  -framework AppKit \
  "$ROOT_DIR/Tools/AppIconGenerator/main.swift" \
  -o "$GENERATOR"

"$GENERATOR" "$ICON_FILE"

echo "$ICON_FILE"
