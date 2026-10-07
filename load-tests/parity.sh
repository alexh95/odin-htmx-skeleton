#!/usr/bin/env sh
# Route parity check. CLAUDE.md asks for every endpoint to have a behaviour test
# (e2e/tests/) and a load scenario (load-tests/scenarios/). This lists each route
# registered in app/src/routes.odin and whether each suite mentions its path.
#
# It's a text search, not coverage: a spec that names the path counts, and one
# that only reaches a route by clicking a button that requests it doesn't. Treat
# a gap as a prompt to look, not proof. Routes whose path is built at runtime
# (no string literal in the route_* call) aren't listed.
#
# Usage: ./parity.sh            # report; always exits 0
#        ./parity.sh --strict   # exit 1 if any route lacks either reference
set -eu
cd "$(dirname "$0")/.."

STRICT=""
case "${1:-}" in
  --strict) STRICT=1 ;;
  "") ;;
  *) echo "usage: $0 [--strict]" >&2; exit 2 ;;
esac

ROUTES="app/src/routes.odin"
E2E="e2e/tests"
LOAD="load-tests/scenarios"

# `http.route_get(r, "/contacts/(%d+)", ...)` -> `get /contacts/(%d+)`
routes=$(grep -oE 'route_(get|post|put|patch|delete|options)\(r, "[^"]+"' "$ROUTES" |
  sed -E 's/route_([a-z]+)\(r, "([^"]+)"/\1 \2/')

# Whether the files under $1 name the route path $2. A route pattern is searched
# by its literal head: up to the first capture or character class, with Lua's
# %-escapes undone, so `/contacts/(%d+)` looks for `/contacts/` and
# `/favicon%.ico` for `/favicon.ico`. `/` alone would match every path, so it
# has to appear as a whole string.
mentions() {
  lit=$(printf '%s' "$2" | sed -E 's/[([].*$//; s/%(.)/\1/g')
  if [ "$lit" = "/" ]; then
    grep -rqE "['\"]/['\"]|\\\$\{BASE\}/\`" "$1"
  else
    grep -rqF -- "$lit" "$1"
  fi
}

total=0; no_e2e=0; no_load=0
printf '%-7s %-26s %-4s %s\n' METHOD PATH E2E LOAD
while read -r method path; do
  [ -n "$method" ] || continue
  total=$((total + 1))
  e="yes"; l="yes"
  mentions "$E2E" "$path" || { e="-"; no_e2e=$((no_e2e + 1)); }
  mentions "$LOAD" "$path" || { l="-"; no_load=$((no_load + 1)); }
  printf '%-7s %-26s %-4s %s\n' "$(echo "$method" | tr a-z A-Z)" "$path" "$e" "$l"
done <<EOF
$routes
EOF

echo
echo "$total routes: $no_e2e without an e2e reference, $no_load without a load reference."
if [ -n "$STRICT" ] && [ $((no_e2e + no_load)) -gt 0 ]; then
  exit 1
fi
