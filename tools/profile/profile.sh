#!/usr/bin/env sh
# tools/profile: the two artifacts M1's profile came from, repeatable at each milestone exit
# (docs/audit/M1.md, Profile). Linux only: perf is Linux's. On the dev PC, from WSL in a copy
# of the tree (the parity gate's leg).
#
#   sh tools/profile/profile.sh <profile> <scenario> [--spall]
#
#   perf    builds <profile> at -o:speed -debug, drives load-tests/scenarios/*/<scenario>.js at
#           200 VUs for 8 s, and records 4 s of the server with `perf record -F 199
#           --call-graph dwarf`. Out, in app/build/profile/: <p>-<scenario>.perf.txt (perf
#           script's samples: speedscope.app and the Firefox profiler open it), .folded (one
#           stack a line, with its count), .top.txt (the 30 heaviest functions, inclusive and
#           self) and, with FlameGraph's scripts on PATH or in $FLAMEGRAPH, .svg.
#   --spall also builds a scratch copy of the profile with tools/profile/spall_hook.odin in
#           its cmd/ and runs 1 VU for 1 s (and k6's 1 s warmup) on 2 loops: <p>-<scenario>.spall,
#           every procedure's calls (spall's viewer, gravitymoth.com/spall). Its times are
#           inflated by the instrumentation; its call counts are exact. Large: about 0.8 GB a
#           second of `pages`, where M1's `write` took 160 MB for 4 s.
#
# Env: K6 (k6; else /opt/k6/k6), PERF (perf; else an installed linux-tools perf), VUS (200), PORT (8195),
# SPALL_SECONDS (1).
set -eu
cd "$(dirname "$0")/../.."
[ $# -ge 2 ] || { echo "usage: sh tools/profile/profile.sh <profile> <scenario> [--spall]" >&2; exit 2; }
P="$1"; SC="$2"; SPALL=""
[ "${3:-}" = "--spall" ] && SPALL=1
# Ubuntu's perf is a wrapper that wants linux-tools for the running kernel, which WSL's kernels have
# none of; any installed linux-tools perf records them.
PERF="${PERF:-perf}"
if ! "$PERF" version >/dev/null 2>&1; then
  for p in /usr/lib/linux-tools/*/perf; do [ -x "$p" ] && PERF="$p"; done
fi
"$PERF" version >/dev/null 2>&1 || { echo "profile: no working perf (Linux: linux-tools)" >&2; exit 2; }
K6="${K6:-$(command -v k6 || echo /opt/k6/k6)}"
VUS="${VUS:-200}"
PORT="${PORT:-8195}"
set -- load-tests/scenarios/*/"$SC".js
[ -f "$1" ] || { echo "profile: no scenario $SC" >&2; exit 2; }
SCRIPT="$1"
DIR=app/build/profile
mkdir -p "$DIR"
BASE="$DIR/$P-$SC"

serve() { # bin, threads: the server in the background, ready
  PORT="$PORT" THREADS="$2" LOG_LEVEL=warn "$1" "$PORT" >"$BASE.server.log" 2>&1 &
  SRV=$!
  i=0
  until curl -fs "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 200 ] || { echo "profile: the server never got ready" >&2; cat "$BASE.server.log" >&2; exit 1; }
    sleep 0.05
  done
}

load() { # vus, seconds
  "$K6" run --quiet --env BASE_URL="http://127.0.0.1:$PORT" --env VUS="$1" --env DURATION="${2}s" --env WARMUP=1s \
    --env OUT=/dev/null --env OUT_CSV=/dev/null "$SCRIPT" >/dev/null 2>&1
}

# ---- perf ------------------------------------------------------------------------------
echo "profile: building $P at -o:speed -debug ..."
OUT_BIN="app/bin/$P-profile"
OUT="$OUT_BIN" sh build.sh "$P" -o:speed -debug >/dev/null
serve "$OUT_BIN" 16
load "$VUS" 8 &
LOAD=$!
sleep 2
"$PERF" record -F 199 --call-graph dwarf -p "$SRV" -o "$BASE.perf.data" -- sleep 4 >"$BASE.perf.log" 2>&1
wait "$LOAD" || true
kill "$SRV"; wait "$SRV" 2>/dev/null || true
"$PERF" script -i "$BASE.perf.data" >"$BASE.perf.txt" 2>>"$BASE.perf.log"
rm -f "$BASE.perf.data" "$BASE.perf.data.old"

# perf script's samples, folded: a header line, then one frame a line (leaf first), then a
# blank line. The frame's symbol loses its +0x offset; the stack is written root first.
awk '
  /^[^ \t]/ { n = 0; next }
  /^[ \t]+[0-9a-f]+ / { sym = $2; sub(/\+0x[0-9a-f]+$/, "", sym); if (sym == "") sym = "[unknown]"; f[++n] = sym; next }
  /^$/ { if (n > 0) { s = f[n]; for (i = n - 1; i >= 1; i--) s = s ";" f[i]; c[s]++ } n = 0 }
  END { if (n > 0) { s = f[n]; for (i = n - 1; i >= 1; i--) s = s ";" f[i]; c[s]++ } for (s in c) print s, c[s] }
' "$BASE.perf.txt" | sort >"$BASE.folded"

# The 30 heaviest functions: inclusive (each function once a stack) and self (the leaf).
awk '
  { cnt = $NF; stack = $0; sub(/ [0-9]+$/, "", stack); total += cnt
    m = split(stack, fr, ";"); self[fr[m]] += cnt
    delete seen; for (i = 1; i <= m; i++) if (!(fr[i] in seen)) { seen[fr[i]] = 1; incl[fr[i]] += cnt } }
  END {
    printf "samples: %d\n\ninclusive %%   self %%   function\n", total
    for (k in incl) printf "%9.1f %8.1f   %s\n", 100 * incl[k] / total, 100 * self[k] / total, k
  }
' "$BASE.folded" | { head -3; tail -n +4 | sort -rn | head -30; } >"$BASE.top.txt"

FG="${FLAMEGRAPH:-}"
if [ -n "$FG" ] && [ -x "$FG/flamegraph.pl" ]; then
  "$FG/flamegraph.pl" --title "$P $SC" "$BASE.folded" >"$BASE.svg"
elif command -v flamegraph.pl >/dev/null; then
  flamegraph.pl --title "$P $SC" "$BASE.folded" >"$BASE.svg"
fi
echo "profile: $BASE.{perf.txt,folded,top.txt$( [ -f "$BASE.svg" ] && echo ',svg')}"

# ---- spall -----------------------------------------------------------------------------
[ -n "$SPALL" ] || exit 0
echo "profile: building an instrumented copy of $P ..."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cp build.sh THIRD_PARTY_NOTICES "$TMP/" # /licenses #loads the notices from the root
cp -r app "$TMP/"
rm -rf "$TMP/app/bin"
cp tools/profile/spall_hook.odin "$TMP/app/cmd/$P/"
(cd "$TMP" && OUT="app/bin/$P-spall" sh build.sh "$P" -o:speed >/dev/null)
export SPALL_FILE="$(pwd)/$BASE.spall"
serve "$TMP/app/bin/$P-spall" 2
load 1 "${SPALL_SECONDS:-1}"
kill "$SRV"; wait "$SRV" 2>/dev/null || true
echo "profile: $BASE.spall ($(du -h "$BASE.spall" | cut -f1))"
