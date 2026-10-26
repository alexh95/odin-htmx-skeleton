#!/usr/bin/env sh
# Build a profile and run it on Linux or macOS (Odin uses clang here; no extra setup).
# Usage:  ./run.sh [port]   (default 8080; PROFILE=minimal for another profile, skeleton by
#         default; OPEN=1 also opens it in the browser)
set -e
cd "$(dirname "$0")"

PROFILE="${PROFILE:-skeleton}"
if [ ! -f vendor/htmx/htmx.min.js ] || [ ! -f "build/$PROFILE/main.js" ]; then
  echo "Dependencies are missing. Run ./prepare.sh first."
  exit 1
fi

sh ../build.sh "$PROFILE"

# A SQLite build persists to ./data.db by default (gitignored), seeded with the demo rows;
# export DB_PATH=:memory: for an ephemeral, freshly-seeded store. A memory build has
# neither variable.
if "./bin/$PROFILE" --features --json | grep -q '"store": "sqlite"'; then
  : "${DB_PATH:=data.db}"
  : "${SEED:=1}"
  export DB_PATH SEED
fi

PORT="${1:-${PORT:-8080}}"
export PORT
# With OPEN=1, open the browser shortly after the server comes up (best effort).
# 127.0.0.1, not localhost: the server listens on IPv4 loopback only.
if [ "${OPEN:-}" = 1 ]; then
  ( sleep 1
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://127.0.0.1:$PORT"
    elif command -v open    >/dev/null 2>&1; then open    "http://127.0.0.1:$PORT"
    fi >/dev/null 2>&1 ) &
fi

exec "./bin/$PROFILE"
