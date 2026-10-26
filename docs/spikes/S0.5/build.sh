#!/usr/bin/env bash
# S0.5: builds the prototype's variants on Linux.
#   build.sh <dir holding odin-http with fork.diff applied> <dir holding the fork as it is> <out dir>
# The server/ directory is next to this script.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
f13=$1 orig=$2 out=$3
mkdir -p "$out"
cd "$here/server"
odin build . -o:speed -collection:vendor_fork="$f13" -out:"$out/s05"
odin build . -o:speed -define:F13=false -collection:vendor_fork="$orig" -out:"$out/s05-nof13"
# ASan builds keep -o:speed (an unoptimised verify takes about 1 s, too few per run) and -debug
# so a report names the line.
asan=(-o:speed -debug -sanitize:address)
odin build . "${asan[@]}" -collection:vendor_fork="$f13" -out:"$out/s05-asan"
odin build . "${asan[@]}" -define:GEN_CHECK=false -collection:vendor_fork="$f13" -out:"$out/s05-asan-nogen"
odin build . "${asan[@]}" -define:F13=false -collection:vendor_fork="$orig" -out:"$out/s05-asan-nof13"
odin check . -vet -strict-style -collection:vendor_fork="$f13"
