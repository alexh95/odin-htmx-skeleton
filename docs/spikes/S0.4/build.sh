#!/usr/bin/env sh
# Spike S0.4: build the :memory: parity candidates from their patch series over
# this checkout's app/, without touching app/ itself.
#
#   docs/spikes/S0.4/build.sh [--out DIR] [--test] [candidate ...]
#
# Candidates (default: v3 A B C):
#   v3noidx  candidates/v3/0001 only: store v3 as research 12 measured it
#   v3       candidates/v3/*: store v3 + the sort indexes (also the file-DB build)
#   A        v3 + candidates/A/*: MEMMODE=single by default, dashboard cached 1 s
#   B        v3 + candidates/B/*: ephemeral file with synchronous=OFF, /dev/shm on Linux
#   C        B  + candidates/C/*: group commit of contact writes on a writer thread
#
# Run it in Git Bash for the Windows binaries and in WSL (or any Linux) for the
# Linux ones; each run builds its own OS's. It copies app/ to DIR/base (default
# ${TMPDIR:-/tmp}/s04-build), applies each candidate's patches to its own copy
# in DIR/trees/<candidate>/app, and builds `odin build src -o:speed` there into
# DIR/<candidate>[.exe], with -define:VERSION=s04-<candidate> (the x-version
# header names the candidate). --test also runs `odin check -vet -strict-style`
# and `odin test src/repository` and `src/views` in each tree.
#
# SQLite is the skeleton's own build in both cases, so the candidates link what
# the baselines link: on Windows the checkout's app/vendor/sqlite/sqlite3.lib
# (run app/prepare.bat once first); on Linux prepare.sh compiles sqlite3.a in
# DIR/base with `cc -O2` and no defines.
set -eu

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OUT=""
TEST=""
CANDS=""
while [ $# -gt 0 ]; do
  case "$1" in
    --out) shift; OUT="$1" ;;
    --test) TEST=1 ;;
    -h|--help) sed -n '2,26p' "$0"; exit 0 ;;
    -*) echo "unknown flag: $1" >&2; exit 2 ;;
    *) CANDS="$CANDS $1" ;;
  esac
  shift
done
[ -n "$CANDS" ] || CANDS="v3 A B C"

case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) OS=windows; EXE=.exe ;;
  *) OS=linux; EXE= ;;
esac

OUT="${OUT:-${TMPDIR:-/tmp}/s04-build}"
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
case "$OUT/" in
  "$ROOT"/*) echo "--out must be outside the checkout ($ROOT)" >&2; exit 2 ;;
esac

# The patch files a candidate applies, in order.
patches() {
  case "$1" in
    v3noidx) set -- "v3/0001-*.patch" ;;
    v3) set -- "v3/*.patch" ;;
    A) set -- "v3/*.patch" "A/*.patch" ;;
    B) set -- "v3/*.patch" "B/*.patch" ;;
    C) set -- "v3/*.patch" "B/*.patch" "C/*.patch" ;;
    *) echo "unknown candidate: $1 (v3noidx, v3, A, B, C)" >&2; return 2 ;;
  esac
  for glob in "$@"; do
    for f in "$HERE"/candidates/$glob; do echo "$f"; done
  done
}

# Apply one patch inside $1, which holds app/. GIT_CEILING_DIRECTORIES keeps git
# from finding a repository above it (OUT may sit inside one), so the paths
# resolve against $1 and never against that repository's own app/.
apply() {
  ( cd "$1" && GIT_CEILING_DIRECTORIES=$(dirname "$1") git apply --whitespace=nowarn "$2" )
}

# ---- base: app/ without its build outputs, plus SQLite --------------------
BASE="$OUT/base"
rm -rf "${BASE:?}"
mkdir -p "$BASE"
tar -C "$ROOT" --exclude=app/bin --exclude='app/data.db*' -cf - app | tar -C "$BASE" -xf -
mkdir -p "$BASE/app/bin"
if [ "$OS" = linux ]; then
  # A copy off a Windows mount marks every file executable, which git apply warns about.
  find "$BASE/app" -type f ! -name '*.sh' -exec chmod 644 {} +
  # prepare.bat writes the stamp with CRLF, which prepare.sh reads as a stale
  # source and downloads it again; the source is the same pinned amalgamation.
  stamp="$BASE/app/vendor/sqlite/.stamp"
  [ -f "$stamp" ] && { tr -d '\r' < "$stamp" > "$stamp.lf"; mv "$stamp.lf" "$stamp"; }
  rm -f "$BASE/app/vendor/sqlite/sqlite3.lib" "$BASE/app/vendor/sqlite/sqlite3.a"
  ( cd "$BASE/app" && sh ./prepare.sh )
else
  for f in vendor/sqlite/sqlite3.lib static/htmx.min.js; do
    [ -f "$BASE/app/$f" ] || { echo "app/$f is missing: run app/prepare.bat once" >&2; exit 1; }
  done
fi
echo "sqlite library: $(sha256sum "$BASE"/app/vendor/sqlite/sqlite3.[al]* | awk '{print $1}')"

# ---- candidates ---------------------------------------------------------
for c in $CANDS; do
  T="$OUT/trees/$c"
  rm -rf "${T:?}"
  mkdir -p "$T"
  cp -R "$BASE/app" "$T/app"
  list=$(patches "$c")
  for p in $list; do
    apply "$T" "$p" || { echo "$c: $(basename "$p") does not apply" >&2; exit 1; }
  done
  echo "== $c: $(for p in $list; do printf '%s ' "$(basename "$(dirname "$p")")/$(basename "$p")"; done)"
  ( cd "$T/app" && odin build src -out:"bin/$c$EXE" -o:speed -warnings-as-errors -define:VERSION="s04-$c" )
  cp "$T/app/bin/$c$EXE" "$OUT/$c$EXE"
  echo "   $OUT/$c$EXE ($(wc -c < "$OUT/$c$EXE" | tr -d ' ') B)"
  if [ -n "$TEST" ]; then
    ( cd "$T/app" && odin check src -vet -strict-style -warnings-as-errors )
    for pkg in src/repository src/views; do
      log=$( cd "$T/app" && odin test "$pkg" 2>&1 ) || true
      printf '%s\n' "$log" | grep -E '^Finished|^ - |\[ERROR' | sed "s|^|   $pkg: |"
      printf '%s\n' "$log" | grep -q 'All tests were successful' || { echo "$c: $pkg failed" >&2; exit 1; }
    done
  fi
done
