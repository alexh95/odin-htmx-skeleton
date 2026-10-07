#!/usr/bin/env sh
# Deploy to any Linux box that runs Docker (a home server, a VPS), over SSH.
#
# Strategy: build ON the host. The repo Dockerfile is self-contained (it fetches
# a pinned Odin + htmx + SQLite and produces a single static binary), so we sync
# the build context and run `docker compose up -d --build`. No registry, and no
# Docker needed on the machine you deploy from.
#
# Files are placed through a throwaway busybox container rather than scp: the
# SSH user only needs to be in the docker group (the daemon writes as root), so
# REMOTE_DIR can be root-owned like a server's other services and the deploy
# still needs no sudo. Docker creates REMOTE_DIR on first use.
#
# Usage: HOST=myserver ./deploy.sh
#
# Env (only HOST is required):
#   HOST        ssh destination: an alias from ~/.ssh/config, or user@host
#   NAME        container / image / compose project name   (odin-htmx-skeleton)
#   REMOTE_DIR  build context + compose file on the host    (/srv/$NAME)
#   HOST_PORT   port published on the host                  (8090)
#   VOLUME      named volume holding the SQLite database    ($NAME-data)
#   PROXY_NET   existing docker network to join, so a reverse proxy on it can
#               reach the app as $NAME:8080                   (none)
set -eu

HOST="${HOST:?set HOST to the ssh destination, e.g. HOST=myserver ./deploy.sh}"
NAME="${NAME:-odin-htmx-skeleton}"
REMOTE_DIR="${REMOTE_DIR:-/srv/$NAME}"
HOST_PORT="${HOST_PORT:-8090}"
VOLUME="${VOLUME:-$NAME-data}"
PROXY_NET="${PROXY_NET:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
REPO="$(cd "$HERE/../.." && pwd)"     # deploy/docker-host -> repo root

# Write whatever arrives on our stdin into the service dir, via a root
# container, then normalise perms so the (non-root) docker CLI can read it.
# $1 = a shell snippet run inside busybox with the piped data on its stdin.
remote_put() {
	ssh "$HOST" "docker run --rm -i -v '$REMOTE_DIR':/dest busybox sh -c '$1 && chmod -R a+rX /dest'"
}

echo "==> syncing build context -> $HOST:$REMOTE_DIR/src"
# tar the docker build context (Dockerfile + .dockerignore + app/, minus junk)
# and unpack on the server. tar-over-ssh avoids needing rsync on Windows.
tar czf - -C "$REPO" \
    --exclude='.git' --exclude='app/bin' --exclude='*.exe' \
    --exclude='*.pdb' --exclude='*.log' --exclude='app/data.db*' --exclude='app/vendor' \
    Dockerfile .dockerignore app \
  | remote_put 'rm -rf /dest/src && mkdir -p /dest/src && tar xzf - -C /dest/src'

echo "==> pushing compose files + settings"
tar czf - -C "$HERE" compose.yaml compose.proxy.yaml \
  | remote_put 'tar xzf - -C /dest'
# The seccomp profile that allows io_uring and nothing else beyond Docker's
# default. Without it, compose.yaml falls back to seccomp=unconfined.
SECCOMP="unconfined"
if [ -f "$REPO/docker/seccomp-io-uring.json" ]; then
  remote_put 'cat > /dest/seccomp-io-uring.json' < "$REPO/docker/seccomp-io-uring.json"
  SECCOMP="seccomp-io-uring.json"   # relative to $REMOTE_DIR, where compose runs
fi
# Compose reads .env from the project dir, so a plain `docker compose logs` on
# the host sees the same settings as this deploy.
files="compose.yaml"
[ -n "$PROXY_NET" ] && files="compose.yaml:compose.proxy.yaml"
printf 'COMPOSE_PROJECT_NAME=%s\nCOMPOSE_FILE=%s\nNAME=%s\nHOST_PORT=%s\nVOLUME=%s\nPROXY_NET=%s\nSECCOMP=%s\n' \
    "$NAME" "$files" "$NAME" "$HOST_PORT" "$VOLUME" "$PROXY_NET" "$SECCOMP" \
  | remote_put 'cat > /dest/.env'

echo "==> build + up (first build pulls Odin + clang, ~2-4 min)"
# --remove-orphans: a service renamed in compose.yaml would otherwise keep its
# old container (and its port) alive beside the new one.
ssh "$HOST" "cd '$REMOTE_DIR' && docker compose up -d --build --remove-orphans"

echo "==> waiting for health"
ssh "$HOST" "for i in \$(seq 1 30); do
    if curl -fs http://localhost:$HOST_PORT/healthz >/dev/null 2>&1; then echo '  healthy'; exit 0; fi
    sleep 1
  done
  echo '  NOT healthy after 30s; recent logs:'; docker logs --tail 40 '$NAME'; exit 1"

# Read the server's primary LAN IP for a copy-paste hint (no hardcoding).
IP="$(ssh "$HOST" 'hostname -I 2>/dev/null | awk "{print \$1}"')"
echo "==> up: http://${IP:-<server-ip>}:$HOST_PORT/  (direct, proxy-free)"
[ -z "$PROXY_NET" ] || echo "    reverse proxy on '$PROXY_NET': forward to  $NAME:8080"
