#!/usr/bin/env sh
# One-time setup for the two things the build needs that aren't tracked inline.
#   1. htmx        - htmx.min.js and its extensions (vendor/htmx/PINS), bundled per profile.
#   2. SQLite      - the pinned amalgamation, compiled to a static lib.
# odin-http is vendored in-tree (vendor/odin-http, see its UPSTREAM.md): nothing to fetch.
# Idempotent: re-running skips whatever is already in place.
set -e
cd "$(dirname "$0")"

# odin's -out: writes into bin/ but won't create it; a fresh clone has no bin/.
mkdir -p bin

# sha256 helper (linux: sha256sum, macOS: shasum -a 256). Used for htmx + sqlite.
sha256_of() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | awk '{print $1}'
  else shasum -a 256 "$1" | awk '{print $1}'; fi
}

# htmx with its extensions, and _hyperscript, each file pinned exactly (version + SHA-256) for
# reproducible builds — same discipline as ODIN_VERSION and the SQLite amalgamation. The digests
# live in vendor/<package>/PINS, which prepare.bat reads too; a file already present with its
# digest is kept.
# fetch_pinned <dir> <unpkg package@version>: every file vendor/<dir>/PINS names, from its dist/.
fetch_pinned() {
  fetched=0
  while read -r file want; do
    case "$file" in ''|'#'*) continue ;; esac
    out="vendor/$1/$file"
    mkdir -p "$(dirname "$out")"
    [ -f "$out" ] && [ "$(sha256_of "$out")" = "$want" ] && continue
    echo "[get ] $2 $file ..."
    url="https://unpkg.com/$2/dist/$file"
    if command -v curl >/dev/null 2>&1; then curl -fsSL "$url" -o "$out"
    else wget -qO "$out" "$url"; fi
    got="$(sha256_of "$out")"
    if [ "$got" != "$want" ]; then
      echo "error: $2 $file checksum mismatch: expected $want, got $got" >&2
      rm -f "$out"; exit 1
    fi
    fetched=$((fetched + 1))
  done < "vendor/$1/PINS"
  [ "$fetched" -gt 0 ] || echo "[skip] $2 already present."
}
HTMX_VERSION=4.0.0
HYPERSCRIPT_VERSION=0.9.94
fetch_pinned htmx "htmx.org@$HTMX_VERSION"
fetch_pinned hyperscript "hyperscript.org@$HYPERSCRIPT_VERSION"

# --- SQLite amalgamation (pinned; fetched + compiled, mirroring the htmx fetch) ---
# NO_SQLITE=1 skips it: a memory profile's build needs no SQLite (D18), and CI builds `minimal`
# that way, with no library present, to prove it.
if [ "${NO_SQLITE:-}" = 1 ]; then
  echo "[skip] SQLite: NO_SQLITE=1"
else
  # Pin the version AND its zip SHA-256 in one place — same reproducibility
  # discipline as ODIN_VERSION / htmx. Bump both together.
  SQLITE_YEAR=2026
  SQLITE_ID=sqlite-amalgamation-3530400                                            # SQLite 3.53.4
  SQLITE_SHA256=1e71ddf93849c6a6ecf58b827c0692073d2dd7ee40196158068f7b29f422e87d
  SQLITE_DIR=vendor/sqlite

  mkdir -p "$SQLITE_DIR"

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

  # D16's flags (PLAN §11.2; spike S0.11). `.flags` records what the lib was built with, so a flag
  # change rebuilds it: a lib newer than its source isn't enough. prepare.bat holds the same string.
  SQLITE_FLAGS="-DSQLITE_DQS=0 -DSQLITE_DEFAULT_FOREIGN_KEYS=1 -DSQLITE_THREADSAFE=2 -DSQLITE_DEFAULT_MEMSTATUS=0 -DSQLITE_OMIT_LOAD_EXTENSION -DSQLITE_OMIT_SHARED_CACHE -DSQLITE_ENABLE_FTS5"

  # Compile to a static lib once, so `odin build` just links it.
  if [ "$SQLITE_DIR/sqlite3.a" -nt "$SQLITE_DIR/sqlite3.c" ] \
     && [ "$(cat "$SQLITE_DIR/.flags" 2>/dev/null)" = "$SQLITE_FLAGS" ]; then
    echo "[skip] sqlite3.a is up to date."
  else
    # Only compiling needs a C toolchain, so it is looked for here, not up front: a
    # re-run with the lib already built has nothing to compile.
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
    echo "[cc  ] compiling sqlite3.c with $CC ..."
    # shellcheck disable=SC2086 # one -D per word
    ( cd "$SQLITE_DIR" && rm -f sqlite3.a && "$CC" -O2 $SQLITE_FLAGS -c sqlite3.c -o sqlite3.o \
        && ar rcs sqlite3.a sqlite3.o && rm -f sqlite3.o )
    printf '%s\n' "$SQLITE_FLAGS" > "$SQLITE_DIR/.flags"
  fi
fi

# Each profile's assets (tools/bundle, PLAN §12.1): its htmx bundle, its stylesheet and its
# client's app.js, with a .br and a .gz beside each, in build/<profile>/, where build.sh's
# BUILD_DIR embeds them from. Cheap, so it runs every time: an edited asset is picked up.
echo "[bndl] building the profiles' assets ..."
(
  cd .. && odin build tools/bundle -out:app/bin/bundle -o:minimal >/dev/null &&
  for d in app/cmd/*/; do # every profile this checkout has
    [ -f "$d/main.odin" ] || continue
    ./app/bin/bundle "$(basename "$d")" >/dev/null || exit 1
  done
) || { echo "error: tools/bundle failed (on Linux it needs brotli and gzip: apt-get install -y brotli)" >&2; exit 1; }

echo
echo "Ready. Build a profile from the repo root:  ./build.sh skeleton"
