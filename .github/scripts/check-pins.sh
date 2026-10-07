#!/bin/sh
# Checks that version pins which must move together still agree, so a bump
# that misses one fails CI instead of quietly building two different things.
#   - Odin: the Dockerfile's ODIN_VERSION and ODIN_SHA256 args, the same two in
#     ci.yml's env, and the build matrix's asset names and linux-amd64 digest.
#   - Playwright: every mcr.microsoft.com/playwright image tag in ci.yml against
#     @playwright/test in e2e/package-lock.json (the image bakes in the
#     browsers that exact version drives).
#
# Usage: sh .github/scripts/check-pins.sh   (from the repo root)
set -eu

ci=.github/workflows/ci.yml
fail=0
bad() { echo "pin mismatch: $*" >&2; fail=1; }

odin=$(sed -n 's/^  ODIN_VERSION: *//p' "$ci")
sha=$(sed -n 's/^  ODIN_SHA256: *//p' "$ci")
[ -n "$odin" ] && [ -n "$sha" ] || { echo "no ODIN_VERSION/ODIN_SHA256 in $ci's env" >&2; exit 1; }

[ "$(sed -n 's/^ARG ODIN_VERSION=//p' Dockerfile)" = "$odin" ] || bad "Dockerfile ODIN_VERSION isn't $odin (ci.yml)"
[ "$(sed -n 's/^ARG ODIN_SHA256=//p' Dockerfile)" = "$sha" ] || bad "Dockerfile ODIN_SHA256 isn't ci.yml's"

assets=$(sed -n 's/^ *odin_asset: *//p' "$ci")
[ -n "$assets" ] || bad "no odin_asset entries in $ci"
for a in $assets; do
  case $a in
    odin-*-"$odin".tar.gz | odin-*-"$odin".zip) ;;
    *) bad "matrix asset $a isn't the $odin release" ;;
  esac
done
# The linux-amd64 leg downloads the same tarball as the env pin describes.
leg=$(awk '/odin_asset: odin-linux-amd64-/ { on = 1 } on && /odin_sha256:/ { print $2; exit }' "$ci")
[ "$leg" = "$sha" ] || bad "the linux-amd64 leg's odin_sha256 isn't ci.yml's ODIN_SHA256"

pw=$(awk '/"node_modules\/@playwright\/test"/ { on = 1 }
          on && /"version"/ { gsub(/[",]/, "", $2); print $2; exit }' e2e/package-lock.json)
[ -n "$pw" ] || bad "no @playwright/test version in e2e/package-lock.json"
images=$(grep -o 'mcr\.microsoft\.com/playwright:[^ ]*' "$ci" || true)
[ -n "$images" ] || bad "no Playwright image in $ci"
for img in $images; do
  case $img in
    *:v"$pw"-*) ;;
    *) bad "$img doesn't match @playwright/test $pw (e2e/package-lock.json)" ;;
  esac
done

[ "$fail" -eq 0 ] && echo "pins agree: Odin $odin, Playwright $pw"
exit "$fail"
