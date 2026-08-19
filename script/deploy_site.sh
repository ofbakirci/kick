#!/usr/bin/env bash
# Pushes site/ to the nus server (/srv/static/kick). Never uses --delete.
# Usage: script/deploy_site.sh            # rsync site files
#        script/deploy_site.sh --caddy    # also install deploy/kick.caddy (only if absent), validate, reload
set -euo pipefail
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"
HOST="${DEPLOY_HOST:-nus}"
DEST="/srv/static/kick"

ls site/dl/Kick-*-macOS.zip >/dev/null 2>&1 || { echo "site/dl is empty: run script/package_release.sh && script/build_site.sh first" >&2; exit 1; }

echo "rsync site/ -> $HOST:$DEST"
ssh "$HOST" "mkdir -p $DEST"
rsync -avz --no-perms --omit-dir-times site/ "$HOST:$DEST/"

if [[ "${1:-}" == "--caddy" ]]; then
  if ssh "$HOST" "test -f /srv/edge/siteler/kick.caddy"; then
    echo "/srv/edge/siteler/kick.caddy already exists on the server. Not touching it (multi-agent rule)."
  else
    scp deploy/kick.caddy "$HOST:/srv/edge/siteler/kick.caddy"
    ssh "$HOST" 'cd /srv/edge && docker compose exec -T caddy caddy validate --config /etc/caddy/Caddyfile && docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile'
    echo "caddy block installed and reloaded"
  fi
fi
echo "done"
