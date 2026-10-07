#!/bin/sh
# apt-get install for CI, with retries and mirror failover.
#
# On 2026-10-07 the clang install failed CI five times. Every failure was a
# plain-HTTP (port 80) fetch timing out, from the Playwright containers, against
# the runner's default mirror (azure.archive.ubuntu.com) and once
# security.ubuntu.com. Meanwhile HTTPS downloads (npm, the Odin tarball) in the
# same jobs worked. Retrying the same mirror didn't help: two slow attempts used
# up the step's whole budget. So the first attempt uses the configured mirror,
# and later attempts switch every Ubuntu source to HTTPS on other hosts:
# Canonical's own archive first, then the kernel.org mirror. The azure mirror
# has no HTTPS.
#
# Usage: sh .github/scripts/apt-install.sh <package>...
# Runs apt-get through sudo when not already root (host runner vs container).
# APT_SOURCES overrides which source files are rewritten (used to test this).
set -u

sudo=""
[ "$(id -u)" -eq 0 ] || sudo="sudo"
# Short timeouts and one in-apt retry: a dead mirror should fail an attempt in
# well under a minute so the next attempt gets to try another one.
opts="-o Acquire::Retries=1 -o Acquire::http::Timeout=15 -o Acquire::https::Timeout=15"
sources="${APT_SOURCES:-/etc/apt/sources.list /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources}"

# Point every Ubuntu archive/security source (one-line or deb822 format) at the
# given base URLs.
use_mirror() {
  for f in $sources; do
    [ -f "$f" ] || continue
    $sudo sed -E -i \
      -e "s#https?://([a-z0-9-]+\.)*archive\.ubuntu\.com/ubuntu/?#$1/#g" \
      -e "s#https?://security\.ubuntu\.com/ubuntu/?#$2/#g" \
      -e "s#https://mirrors\.edge\.kernel\.org/ubuntu/?#$1/#g" \
      "$f"
  done
  echo "apt: switched sources to $1 (security: $2)" >&2
}

attempt=0
for mirror in default canonical canonical kernel kernel; do
  attempt=$((attempt + 1))
  case $mirror in
    canonical) use_mirror https://archive.ubuntu.com/ubuntu https://security.ubuntu.com/ubuntu ;;
    kernel)    use_mirror https://mirrors.edge.kernel.org/ubuntu https://mirrors.edge.kernel.org/ubuntu ;;
  esac
  # `update` exits 0 even when index fetches fail ("ignored, or old ones
  # used"), so success is judged by the install.
  if $sudo apt-get $opts update && $sudo apt-get $opts install -y --no-install-recommends "$@"; then
    exit 0
  fi
  echo "apt attempt $attempt/5 ($mirror mirror) failed" >&2
  [ $attempt -lt 5 ] && sleep 10
done
echo "apt-get install $* failed after 5 attempts" >&2
exit 1
