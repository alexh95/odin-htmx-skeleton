#!/usr/bin/env sh
# Spike S0.3: fetch htmx 4.0.0 and its three stream extensions, pinned by version and SHA-256 as
# app/prepare.* pins htmx (the hashes are 04 §1.3's), into server/static/ for the server's #load.
# Idempotent: a file already present with the right hash is kept.
set -e
cd "$(dirname "$0")"
mkdir -p server/static server/bin

sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

HTMX_VERSION=4.0.0
fetch() { # <dist path> <sha256>
  out="server/static/$(basename "$1")"
  if [ -f "$out" ] && [ "$(sha256_of "$out")" = "$2" ]; then
    echo "[skip] $1"
    return
  fi
  echo "[get ] $1"
  curl -fsSL "https://unpkg.com/htmx.org@$HTMX_VERSION/dist/$1" -o "$out"
  got="$(sha256_of "$out")"
  if [ "$got" != "$2" ]; then
    echo "error: $1 checksum mismatch: expected $2, got $got" >&2
    rm -f "$out"; exit 1
  fi
}

fetch htmx.min.js             e484d9171a9db30a39c8f16e3d709d4137f3211c659f8e6125816635033d593f
fetch ext/hx-sse.min.js       8a834680c4000a9034d79228872372a92e140c810a075cb6d4a76690dfc13085
fetch ext/hx-ws.min.js        a7c11e4eca05417d6299bb40aaacca01572e44605389fc4d5ef12be408a4d03b
fetch ext/hx-multipart.min.js 961f51d1b7b57c9bf56798a09f3241baf0248593731f8ff41d56037c3de99126
