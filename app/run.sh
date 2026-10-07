#!/usr/bin/env sh
# Build and run on Linux or macOS (Odin uses clang here; no extra setup).
# Usage:  ./run.sh [port]   (default 8080; OPEN=1 also opens it in the browser)
set -e
cd "$(dirname "$0")"

if [ ! -d odin-http ] || [ ! -f static/htmx.min.js ] || [ ! -f vendor/sqlite/sqlite3.a ]; then
  echo "Dependencies are missing. Run ./prepare.sh first."
  exit 1
fi

# Local dev persists to ./data.db by default (gitignored); export DB_PATH=:memory:
# for an ephemeral, freshly-seeded store.
: "${DB_PATH:=data.db}"
export DB_PATH
# A file DB is only seeded when asked; a dev store wants the demo rows.
: "${SEED:=1}"
export SEED

mkdir -p bin
odin build src -out:bin/demo

PORT="${1:-8080}"
# With OPEN=1, open the browser shortly after the server comes up (best effort).
# 127.0.0.1, not localhost: the server listens on IPv4 loopback only.
if [ "${OPEN:-}" = 1 ]; then
  ( sleep 1
    if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://127.0.0.1:$PORT"
    elif command -v open    >/dev/null 2>&1; then open    "http://127.0.0.1:$PORT"
    fi >/dev/null 2>&1 ) &
fi

exec ./bin/demo "$@"
