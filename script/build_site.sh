#!/usr/bin/env bash
# Refreshes site/ with the current release artifacts (icon + downloads).
# Run script/package_release.sh first. Deploy with script/deploy_site.sh.
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

mkdir -p site/dl
if [[ -f Resources/Kick.icns ]]; then
  sips -s format png Resources/Kick.icns --out site/icon.png >/dev/null
  sips -Z 512 site/icon.png --out site/icon.png >/dev/null
fi

if [[ -d dist/release ]]; then
  cp dist/release/Kick-*-macOS.zip site/dl/ 2>/dev/null || true
  cp dist/release/SHA256SUMS site/dl/SHA256SUMS 2>/dev/null || true
fi
ls -la site site/dl
