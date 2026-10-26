#!/bin/sh
# Checks that version pins which must move together still agree, so a bump
# that misses one fails CI instead of quietly building two different things.
#   - Odin: the Dockerfile's ODIN_VERSION and ODIN_SHA256 args, the same two in
#     every workflow's env, and .github/actions/setup-odin's asset names and its
#     linux-amd64 digest.
#   - htmx, _hyperscript and SQLite: prepare.sh and prepare.bat fetch the same htmx and
#     _hyperscript versions (their files' digests are app/vendor/<package>/PINS, which
#     both read), pin the same SQLite
#     digest and build it with the same flags (the Dockerfile and CI run prepare.sh,
#     Windows developers prepare.bat).
#   - odin-http: the base commit app/vendor/odin-http/UPSTREAM.md names is the
#     one tools/baseline checks the skeleton's releases against.
#   - Playwright: every mcr.microsoft.com/playwright image tag in the workflows against
#     @playwright/test in e2e/package-lock.json (the image bakes in the
#     browsers that exact version drives).
#
# Usage: sh .github/scripts/check-pins.sh   (from the repo root)
set -eu

ci=.github/workflows/ci.yml
action=.github/actions/setup-odin/action.yml
fail=0
bad() { echo "pin mismatch: $*" >&2; fail=1; }

odin=$(sed -n 's/^  ODIN_VERSION: *//p' "$ci")
sha=$(sed -n 's/^  ODIN_SHA256: *//p' "$ci")
[ -n "$odin" ] && [ -n "$sha" ] || { echo "no ODIN_VERSION/ODIN_SHA256 in $ci's env" >&2; exit 1; }

[ "$(sed -n 's/^ARG ODIN_VERSION=//p' Dockerfile)" = "$odin" ] || bad "Dockerfile ODIN_VERSION isn't $odin (ci.yml)"
for wf in .github/workflows/*.yml; do
  [ "$wf" = "$ci" ] && continue
  v=$(sed -n 's/^  ODIN_VERSION: *//p' "$wf"); d=$(sed -n 's/^  ODIN_SHA256: *//p' "$wf")
  [ -z "$v" ] || [ "$v" = "$odin" ] || bad "$wf ODIN_VERSION isn't $odin (ci.yml)"
  [ -z "$d" ] || [ "$d" = "$sha" ] || bad "$wf ODIN_SHA256 isn't ci.yml's"
done
[ "$(sed -n 's/^ARG ODIN_SHA256=//p' Dockerfile)" = "$sha" ] || bad "Dockerfile ODIN_SHA256 isn't ci.yml's"

assets=$(grep -o 'asset=odin-[^;]*' "$action" | sed 's/^asset=//')
[ -n "$assets" ] || bad "no Odin assets in $action"
for a in $assets; do
  case $a in
    odin-*-"$odin".tar.gz | odin-*-"$odin".zip) ;;
    *) bad "$action's asset $a isn't the $odin release" ;;
  esac
done
# The linux-amd64 runner downloads the tarball the env pin describes.
leg=$(grep 'Linux-X64)' "$action" | grep -o 'sha=[0-9a-f]*' | sed 's/^sha=//')
[ "$leg" = "$sha" ] || bad "$action's linux-amd64 digest isn't ci.yml's ODIN_SHA256"

# prepare.sh: `SQLITE_SHA256=…` (indented inside a step); prepare.bat: `set "SQLITE_SHA256=…"`.
for pin in HTMX_VERSION HYPERSCRIPT_VERSION SQLITE_SHA256 SQLITE_FLAGS; do
  sh_v=$(sed -n "s/^ *$pin=\"\{0,1\}\([^\"]*\)\"\{0,1\}\$/\1/p" app/prepare.sh)
  bat_v=$(sed -n "s/^set \"$pin=\([^\"]*\)\"\r\{0,1\}\$/\1/p" app/prepare.bat)
  [ -n "$sh_v" ] || bad "no $pin in app/prepare.sh"
  [ "$sh_v" = "$bat_v" ] || bad "app/prepare.sh and app/prepare.bat pin different $pin"
done

grep -q '^htmx.min.js  *[0-9a-f]\{64\}$' app/vendor/htmx/PINS || bad "app/vendor/htmx/PINS pins no htmx.min.js"
grep -q '^_hyperscript.min.js  *[0-9a-f]\{64\}$' app/vendor/hyperscript/PINS || bad "app/vendor/hyperscript/PINS pins no _hyperscript.min.js"

base=$(sed -n 's/^- \*\*Base:\*\* `\([0-9a-f]\{7\}\).*/\1/p' app/vendor/odin-http/UPSTREAM.md)
[ -n "$base" ] || bad "app/vendor/odin-http/UPSTREAM.md names no base commit"
grep -q "in $base\\*)" tools/baseline/baseline.sh || bad "tools/baseline checks odin-http against another commit than UPSTREAM.md's $base"

pw=$(awk '/"node_modules\/@playwright\/test"/ { on = 1 }
          on && /"version"/ { gsub(/[",]/, "", $2); print $2; exit }' e2e/package-lock.json)
[ -n "$pw" ] || bad "no @playwright/test version in e2e/package-lock.json"
images=$(cat .github/workflows/*.yml | grep -o 'mcr\.microsoft\.com/playwright:[^ ]*' || true)
[ -n "$images" ] || bad "no Playwright image in the workflows"
for img in $images; do
  case $img in
    *:v"$pw"-*) ;;
    *) bad "$img doesn't match @playwright/test $pw (e2e/package-lock.json)" ;;
  esac
done

[ "$fail" -eq 0 ] && echo "pins agree: Odin $odin, htmx, _hyperscript and SQLite in both prepare scripts, odin-http $base, Playwright $pw"
exit "$fail"
