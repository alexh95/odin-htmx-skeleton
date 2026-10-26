#!/usr/bin/env sh
# Builds a skeleton release from git for the parity gate (PLAN §18.2 step 1): the baselines
# 709bc94 (v1.2.0) and v1.1.1, built with the pinned Odin and the same SQLite library as the
# candidate, and, for spike S0.2, 709bc94 rebuilt on the vendored odin-http fork.
#
#   tools/baseline/baseline.sh <ref> <out-binary> [--fork] [--guard]
#
#   <ref>     a tag or commit whose app/ is the skeleton's layout (src/, an app/odin-http
#             submodule at fac113f). Its tree is taken with `git archive`: no checkout, no
#             worktree, nothing in the repo changes.
#   --fork    app/odin-http is the fork in app/vendor/odin-http (at HEAD) instead of the
#             pristine fac113f vendored at c8a4037.
#   --guard   with --fork: the crash guard (docs/spikes/S0.6/guardlab/guard) is installed as the
#             fork's F-5 invoke hook, as M1's profiles will have it.
#
# htmx and the SQLite library are not fetched: they come from this checkout's prepared app/
# (run app/prepare.* first), after checking that <ref>'s prepare pins the same versions. So every
# build in a gate run links the same SQLite library. Runs in Git Bash on Windows and on Linux.
#
# M0 spike code (S0.1, S0.2); M1 productionises it (PLAN §22.3, tools/baseline).
set -eu

REF="${1:?usage: baseline.sh <ref> <out-binary> [--fork] [--guard]}"
OUT="${2:?usage: baseline.sh <ref> <out-binary> [--fork] [--guard]}"
shift 2
FORK=""; GUARD=""
for a in "$@"; do
  case "$a" in
    --fork)  FORK=1 ;;
    --guard) GUARD=1 ;;
    *) echo "unknown flag: $a" >&2; exit 2 ;;
  esac
done

ROOT="$(git rev-parse --show-toplevel)"
PRISTINE=c8a4037 # build(deps): vendor odin-http fac113f in-tree (no local changes yet)
SHA="$(git -C "$ROOT" rev-parse --short "$REF^{commit}")"

case "$(uname -s)" in
  *MINGW*|*MSYS*|*CYGWIN*) LIB=sqlite3.lib; EXE=.exe ;; # Odin needs the extension spelled out there
  *) LIB=sqlite3.a; EXE= ;;
esac
PREP="$ROOT/app"
[ -f "$PREP/vendor/sqlite/$LIB" ] && [ -f "$PREP/static/htmx.min.js" ] || {
  echo "this checkout's app/ isn't prepared: run app/prepare.* first" >&2; exit 1; }

# The ref must pin what this checkout prepared, or the comparison isn't like for like.
for pin in HTMX_SHA256 SQLITE_SHA256; do
  want="$(git -C "$ROOT" show "$REF:app/prepare.sh" | sed -n "s/^$pin=\([0-9a-f]*\).*/\1/p")"
  have="$(sed -n "s/^$pin=\([0-9a-f]*\).*/\1/p" "$PREP/prepare.sh")"
  [ "$want" = "$have" ] || { echo "$REF pins $pin=$want, this checkout $have" >&2; exit 1; }
done
link="$(git -C "$ROOT" ls-tree "$REF" app/odin-http | awk '{print $3}')"
case "$link" in fac113f*) ;; *) echo "$REF pins odin-http $link, not fac113f" >&2; exit 1 ;; esac

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
git -C "$ROOT" archive "$REF" app | tar -x -C "$TMP"
APP="$TMP/app"
rm -rf "$APP/odin-http"
if [ -n "$FORK" ]; then
  cp -r "$ROOT/app/vendor/odin-http" "$APP/odin-http"
else
  git -C "$ROOT" archive "$PRISTINE" app/vendor/odin-http | tar -x -C "$TMP"
  mv "$APP/vendor/odin-http" "$APP/odin-http"
fi
mkdir -p "$APP/vendor/sqlite" "$APP/bin"
cp "$PREP/vendor/sqlite/$LIB" "$PREP/vendor/sqlite/sqlite3.h" "$APP/vendor/sqlite/"
cp "$PREP/static/htmx.min.js" "$APP/static/htmx.min.js"

if [ -n "$GUARD" ]; then
  [ -n "$FORK" ] || { echo "--guard needs --fork" >&2; exit 2; }
  cp -r "$ROOT/docs/spikes/S0.6/guardlab/guard" "$APP/src/guard"
  # Install the guard where main builds the server's options; a dirty crash exits 70 (D15).
  awk '
    /^import http "..\/odin-http"/ { print; print "import \"guard\""; next }
    /opts := http.Default_Server_Opts/ {
      print
      print "\topts.invoke = guard.invoke"
      print "\topts.on_thread_init = proc(_: ^http.Server, _: int) { guard.thread_init() }"
      print "\tguard.install(proc(c: ^guard.Crash) { if c.dirty { os.exit(70) } })"
      next
    }
    { print }
  ' "$APP/src/main.odin" > "$APP/src/main.odin.new"
  mv "$APP/src/main.odin.new" "$APP/src/main.odin"
  grep -q 'opts.invoke = guard.invoke' "$APP/src/main.odin" || { echo "guard patch didn't apply" >&2; exit 1; }
fi

VERSION="$SHA${FORK:+-fork}${GUARD:+-guard}"
( cd "$APP" && odin build src -out:"bin/demo$EXE" -o:speed -define:VERSION="$VERSION" )
mkdir -p "$(dirname "$OUT")"
cp "$APP/bin/demo$EXE" "$OUT"
echo "built $REF ($VERSION) -> $OUT ($(wc -c < "$OUT") bytes)"
