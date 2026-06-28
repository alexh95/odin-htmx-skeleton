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

# --- SQLite amalgamation (pinned; fetched + compiled, mirroring the htmx fetch) ---
# Pin the version AND its zip SHA-256 in one place — same reproducibility
# discipline as ODIN_VERSION / htmx@2. Bump both together.
SQLITE_YEAR=2026
SQLITE_ID=sqlite-amalgamation-3530300                                            # SQLite 3.53.3
SQLITE_SHA256=646421e12aac110282ef8cc68f1a62d4bb15fc7b8f09da0b53e29ee690500431
SQLITE_DIR=vendor/sqlite

# Compiling the amalgamation makes a C toolchain a hard requirement. Check up front.
CC="${CC:-}"
if [ -z "$CC" ]; then
  if command -v clang >/dev/null 2>&1; then CC=clang
  elif command -v gcc >/dev/null 2>&1; then CC=gcc; fi
fi
if [ -z "$CC" ] || ! command -v ar >/dev/null 2>&1; then
  echo "error: a C toolchain (clang/gcc + ar) is required to build SQLite." >&2
  case "$(uname -s)" in
    Darwin) echo "  macOS:  xcode-select --install" >&2 ;;
    *)      echo "  Linux:  sudo apt-get install -y clang" >&2 ;;
  esac
  exit 1
fi

mkdir -p "$SQLITE_DIR"
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# Download + verify + extract, unless the pinned source is already in place.
if [ -f "$SQLITE_DIR/sqlite3.c" ] && [ -f "$SQLITE_DIR/sqlite3.h" ] \
   && [ "$(cat "$SQLITE_DIR/.stamp" 2>/dev/null)" = "$SQLITE_SHA256" ]; then
  echo "[skip] SQLite amalgamation $SQLITE_ID already present."
else
  echo "[get ] downloading $SQLITE_ID ..."
  url="https://sqlite.org/$SQLITE_YEAR/$SQLITE_ID.zip"
  tmp="$(mktemp -d)"
  if command -v curl >/dev/null 2>&1; then curl -fsSL "$url" -o "$tmp/s.zip"
  else wget -qO "$tmp/s.zip" "$url"; fi
  got="$(sha256_of "$tmp/s.zip")"
  if [ "$got" != "$SQLITE_SHA256" ]; then
    echo "error: SQLite checksum mismatch: expected $SQLITE_SHA256, got $got" >&2
    rm -rf "$tmp"; exit 1
  fi
  unzip -joq "$tmp/s.zip" "*/sqlite3.c" "*/sqlite3.h" -d "$SQLITE_DIR"
  rm -rf "$tmp"
  printf '%s\n' "$SQLITE_SHA256" > "$SQLITE_DIR/.stamp"
fi

# Compile to a static lib once, so `odin build` just links it.
if [ "$SQLITE_DIR/sqlite3.a" -nt "$SQLITE_DIR/sqlite3.c" ]; then
  echo "[skip] sqlite3.a is up to date."
else
  echo "[cc  ] compiling sqlite3.c with $CC ..."
  ( cd "$SQLITE_DIR" && "$CC" -O2 -c sqlite3.c -o sqlite3.o && ar rcs sqlite3.a sqlite3.o && rm -f sqlite3.o )
fi

echo
echo "Ready. Start the server with:  ./run.sh"
