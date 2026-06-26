#!/usr/bin/env sh
# Build and run on Linux or macOS (Odin uses clang here; no extra setup).
# Usage:  ./run.sh [port]   (default 8080)
set -e
cd "$(dirname "$0")"

if [ ! -d odin-http ] || [ ! -f static/htmx.min.js ]; then
  echo "Dependencies are missing. Run ./prepare.sh first."
  exit 1
fi

mkdir -p bin
odin build src -out:bin/demo

PORT="${1:-8080}"
# Open the browser shortly after the server comes up (best effort).
( sleep 1
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://localhost:$PORT"
  elif command -v open    >/dev/null 2>&1; then open    "http://localhost:$PORT"
  fi >/dev/null 2>&1 ) &

exec ./bin/demo "$@"
