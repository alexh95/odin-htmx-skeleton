#!/bin/sh
# apt-get install with retries, for every CI job that needs clang & co.
#
# A runner's route to the Ubuntu mirrors can drop out for minutes at a time
# (2026-10-07: azure.archive.ubuntu.com and security.ubuntu.com both timed out
# mid-run, three times in one day), and one failed fetch used to fail the whole
# job before any test ran. apt's own Acquire::Retries only retries a single
# fetch within seconds, so the whole update+install is retried with backoff.
#
# Usage: sh .github/scripts/apt-install.sh <package>...
# Runs apt-get through sudo when not already root (host runner vs container).
set -u

sudo=""
[ "$(id -u)" -eq 0 ] || sudo="sudo"
opts="-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30"

for attempt in 1 2 3 4 5; do
  # `update` exits 0 even when index fetches fail ("ignored, or old ones
  # used"), so success is judged by the install.
  if $sudo apt-get $opts update && $sudo apt-get $opts install -y --no-install-recommends "$@"; then
    exit 0
  fi
  echo "apt attempt $attempt/5 failed; retrying in $((attempt * 20))s" >&2
  sleep $((attempt * 20))
done
echo "apt-get install $* failed after 5 attempts" >&2
exit 1
