#!/usr/bin/env sh
# One-time setup for the two things the build needs that aren't tracked inline.
#   1. odin-http  - the HTTP library, vendored as a pinned git submodule.
#   2. htmx.min.js - embedded into the binary via #load at compile time.
# Idempotent: re-running skips whatever is already in place.
set -e
cd "$(dirname "$0")"

# odin's -out: writes into bin/ but won't create it; a fresh clone has no bin/.
mkdir -p bin

if [ -f odin-http/server.odin ]; then
  echo "[skip] odin-http submodule already checked out."
else
  echo "[get ] initializing odin-http submodule ..."
  git -C .. submodule update --init app/odin-http
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
