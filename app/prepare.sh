#!/usr/bin/env sh
# One-time setup: fetch the two things the build needs that aren't in this repo.
#   1. odin-http  - the HTTP library, cloned next to the sources.
#   2. htmx.min.js - embedded into the binary via #load at compile time.
# Idempotent: re-running skips whatever is already in place.
set -e
cd "$(dirname "$0")"

if [ -d odin-http ]; then
  echo "[skip] odin-http already cloned."
else
  echo "[get ] cloning odin-http ..."
  git clone --depth 1 https://github.com/laytan/odin-http odin-http
fi

if [ -f static/htmx.min.js ]; then
  echo "[skip] static/htmx.min.js already present."
else
  echo "[get ] downloading htmx.min.js ..."
  url="https://unpkg.com/htmx.org@2/dist/htmx.min.js"
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$url" -o static/htmx.min.js
  else
    wget -qO static/htmx.min.js "$url"
  fi
fi

echo
echo "Ready. Start the server with:  ./run.sh"
