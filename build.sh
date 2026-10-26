#!/usr/bin/env sh
# build.sh <profile> [odin flags...]: the one place a profile's family flags live (PLAN §7.2).
#   CMD=build (default) | check | test | run
#   VERSION=<tag or commit> becomes -define:VERSION (default dev), sent as x-version.
#   OUT=<path> builds there instead (tools/bundle's scan build, beside a running binary).
# Every path here is relative to the repo root; the binary lands in app/bin/<profile>, and the
# assets prepare built for the profile (app/build/<profile>/) are embedded from BUILD_DIR.
# run.*, prepare.*, CI, the Dockerfile, the e2e setup and load-tests/run.sh all call this.
set -eu
cd "$(dirname "$0")"

p="${1:-}"
[ -n "$p" ] || { echo "usage: build.sh <minimal|skeleton|lab> [odin flags...]" >&2; exit 2; }
shift
src="$p"
case "$p" in
  minimal)  store=memory id=platform/authz/anonymous client=vanilla theme=lite ;;
  skeleton) store=sqlite id=platform/authz/anonymous client=vanilla theme=full ;;
  lab)      store=memory id=platform/authz/anonymous client=hyperscript theme=full ;;
  *) echo "build.sh: unknown profile '$p' (minimal, skeleton, lab)" >&2; exit 2 ;;
esac

case "$(uname -s)" in
  *MINGW*|*MSYS*|*CYGWIN*) exe=.exe ;; # Odin won't infer the extension on Windows
  *) exe= ;;
esac

cmd="${CMD:-build}"
case "$cmd" in
  build|run) out="-out:${OUT:-app/bin/$p$exe}" ;;
  test)      out="-out:${OUT:-app/bin/$p-test$exe} -define:ODIN_TEST_FAIL_ON_BAD_MEMORY=true" ;;
  check)     out="" ;;
  *) echo "build.sh: unknown CMD '$cmd' (build, check, test, run)" >&2; exit 2 ;;
esac
mkdir -p app/bin

# shellcheck disable=SC2086 # $out is the output flag (and, for test, leaks fatal) or nothing
exec odin "$cmd" "app/cmd/$src" $out \
  -collection:store="app/stores/$store" -collection:identity="app/$id" \
  -collection:client="app/platform/client/$client" -collection:theme="app/platform/theme/$theme" \
  -define:VERSION="${VERSION:-dev}" -define:BUILD_DIR="../../build/$p" \
  -vet -vet-cast -vet-semicolon -vet-tabs -vet-using-param -disallow-do -strict-style -warnings-as-errors "$@"
