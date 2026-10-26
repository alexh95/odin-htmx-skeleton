#!/usr/bin/env sh
# build.sh <profile> [odin flags...]: the one place each profile's four family flags live (PLAN §7.2).
# Fixture for spike S0.10, standing in for the repo root's build.sh until M1 writes it.
#   CMD=build|check|run|test   the odin command (default build)
#   OUT=<path>                 the binary (default bin/<profile>)
set -e
cd "$(dirname "$0")"
p="$1"
[ -n "$p" ] || { echo "usage: build.sh <profile> [odin flags...]" >&2; exit 2; }
shift
case "$p" in
  minimal) store=memory identity=anonymous client=vanilla     theme=lite ;;
  streams) store=memory identity=nick      client=vanilla     theme=lite ;;
  full)    store=sqlite identity=accounts  client=hyperscript theme=full ;;
  lab)     store=memory identity=anonymous client=hyperscript theme=full ;;
  *) echo "build.sh: unknown profile '$p'" >&2; exit 2 ;;
esac
exec odin "${CMD:-build}" "app/cmd/$p" \
  "-collection:store=app/stores/$store" \
  "-collection:identity=app/identity/$identity" \
  "-collection:client=app/platform/client/$client" \
  "-collection:theme=app/platform/theme/$theme" \
  "-out:${OUT:-bin/$p}" "$@"
