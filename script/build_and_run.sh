#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APPEARANCE="${2:-}"
APP_NAME="Kick"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
export CLANG_MODULE_CACHE_PATH="$ROOT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$ROOT_DIR/.build/swiftpm-module-cache"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_BINARY="$APP_BUNDLE/Contents/MacOS/$APP_NAME"

usage() {
  echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--demo-ready|--demo-blocked|--demo-kickable] [--demo-light|--demo-dark]" >&2
}

if [[ $# -gt 2 ]]; then
  usage
  exit 2
fi

if [[ -n "$APPEARANCE" && "$APPEARANCE" != "--demo-light" && "$APPEARANCE" != "--demo-dark" ]]; then
  echo "appearance must be --demo-light or --demo-dark" >&2
  exit 2
fi

case "$MODE" in
  run|--debug|debug|--logs|logs|--telemetry|telemetry|--verify|verify|--demo-ready|demo-ready|--demo-blocked|demo-blocked|--demo-kickable|demo-kickable)
    ;;
  *)
    usage
    exit 2
    ;;
esac

if [[ -n "$APPEARANCE" ]]; then
  case "$MODE" in
    --demo-ready|demo-ready|--demo-blocked|demo-blocked|--demo-kickable|demo-kickable)
      ;;
    *)
      echo "appearance is available only in a demo mode" >&2
      exit 2
      ;;
  esac
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true

swift build --disable-sandbox
BUILD_BINARY="$(swift build --disable-sandbox --show-bin-path)/$APP_NAME"
"$ROOT_DIR/script/stage_app_bundle.sh" "$BUILD_BINARY" "$APP_BUNDLE"

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

open_demo() {
  local state="$1"
  local arguments=("$state")
  if [[ -n "$APPEARANCE" ]]; then
    arguments+=("$APPEARANCE")
  fi
  /usr/bin/open -n "$APP_BUNDLE" --args "${arguments[@]}"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate 'subsystem == "co.nousworks.kick"'
    ;;
  --verify|verify)
    open_app
    sleep 1
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --demo-ready|demo-ready)
    open_demo --demo-ready
    ;;
  --demo-blocked|demo-blocked)
    open_demo --demo-blocked
    ;;
  --demo-kickable|demo-kickable)
    open_demo --demo-kickable
    ;;
  *)
    usage
    exit 2
    ;;
esac
