#!/usr/bin/env sh
# Deploy odin-htmx to the apollo-11 home server.
#
# Strategy: build ON the server. The repo Dockerfile is self-contained (fetches
# Odin + htmx, produces a static binary), so we sync the build context and run
# `docker compose up -d --build`. No registry, no local Docker needed.
#
# The service dir (/mnt/fast-storage/odin-htmx) is root-owned like the box's
# other services, and the SSH user has no passwordless sudo. But that user IS in
# the docker group, and the daemon runs as root — so files are placed via a
# throwaway busybox container (writing as root), then made world-readable so the
# docker CLI can read the build context. Net: the dir stays root-owned (matching
# convention) and the deploy needs no sudo. Only prerequisite: the dir exists.
#
# Usage: ./deploy.sh            (build + up)
#        HOST=other ./deploy.sh (override the ssh alias)
set -eu

# Config (override via env). HOST is your ssh alias for the box; nothing here
# hardcodes an IP or domain — the LAN hint below is read off the server.
HOST="${HOST:-apollo-11_local}"
REMOTE_DIR="${REMOTE_DIR:-/mnt/fast-storage/odin-htmx}"
HOST_PORT="${HOST_PORT:-8090}"        # must match the published port in docker-compose.yml
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"     # deploy/apollo-11 -> repo root

# Write whatever arrives on our stdin into the root-owned service dir, via a
# root container, then normalise perms so the (non-root) docker CLI can read it.
# $1 = a shell snippet run inside busybox with the piped data on its stdin.
remote_put() {
	ssh "$HOST" "docker run --rm -i -v '$REMOTE_DIR':/dest busybox sh -c '$1 && chmod -R a+rX /dest'"
}

echo "==> syncing build context -> $HOST:$REMOTE_DIR/src"
# tar the docker build context (Dockerfile + .dockerignore + app/, minus junk)
# and unpack on the server. tar-over-ssh avoids needing rsync on Windows.
tar czf - -C "$REPO" \
    --exclude='.git' --exclude='app/bin' --exclude='*.exe' \
    --exclude='*.pdb' --exclude='*.log' \
    Dockerfile .dockerignore app \
  | remote_put 'rm -rf /dest/src && mkdir -p /dest/src && tar xzf - -C /dest/src'

echo "==> pushing docker-compose.yml"
remote_put 'cat > /dest/docker-compose.yml' < "$HERE/docker-compose.yml"

echo "==> build + up (first build pulls Odin + clang, ~2-4 min)"
ssh "$HOST" "cd '$REMOTE_DIR' && docker compose up -d --build"

echo "==> waiting for health"
ssh "$HOST" "for i in \$(seq 1 30); do
    if curl -fs http://localhost:$HOST_PORT/healthz >/dev/null 2>&1; then echo '  healthy'; exit 0; fi
    sleep 1
  done
  echo '  NOT healthy after 30s; recent logs:'; docker logs --tail 40 odin-htmx; exit 1"

# Read the server's primary LAN IP for a copy-paste hint (no hardcoding).
IP="$(ssh "$HOST" 'hostname -I 2>/dev/null | awk "{print \$1}"')"
echo "==> up: http://${IP:-<server-lan-ip>}:$HOST_PORT/  (direct LAN, proxy-free)"
echo "    subdomain via nginx-proxy-manager: forward to  odin-htmx:8080"
