#!/usr/bin/env sh
# S0.11: build a copy of the skeleton's app/ against each SQLite lib and record
# the binary size; then run the store and views tests against one lib.
#   measure.sh <app copy> <libs dir> <variants...>
#   TEST=<variant> also runs `odin test src/repository` and `odin test src/views`
#   against that variant's lib.
# The lib is copied over app/vendor/sqlite/sqlite3.{lib|a}, which is where the
# skeleton's binding (src/sqlite/sqlite.odin) links it from.
set -e
app=$1; libs=$2; shift 2
case "$(uname -s)" in
  MINGW*|MSYS*|CYGWIN*) lib=sqlite3.lib; exe=.exe ;;
  *) lib=sqlite3.a; exe= ;;
esac
size_of() { wc -c < "$1" | tr -d ' '; }
mkdir -p "$app/bin"
for v in "$@"; do
  cp "$libs/$v/$lib" "$app/vendor/sqlite/$lib"
  (cd "$app" && odin build src -o:speed "-out:bin/demo_$v$exe")
  echo "size $v $(size_of "$app/bin/demo_$v$exe") B (lib $(size_of "$libs/$v/$lib") B)"
done
if [ -n "${TEST:-}" ]; then
  cp "$libs/$TEST/$lib" "$app/vendor/sqlite/$lib"
  (cd "$app" && odin test src/repository && odin test src/views)
fi
