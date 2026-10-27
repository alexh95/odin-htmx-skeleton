#!/usr/bin/env sh
# The soak (PLAN §19.1.8): lab for SOAK_MINUTES (60) with 2000 streams, mixed load and a redeploy
# at half time. Linux only (it reads /proc). It passes when, in each half, RSS and the open fds
# plateau (the last sample within 10 % of the half's first full-load one), the streams' queued bytes
# stay under 64 MiB, nothing exits but the redeploy, and every stream is back within 5 s of it.
#
#   sh tools/drills/soak.sh        (from the repo root, prepared)
#
# The redeploy is a SIGTERM (the drain: 1012 to the sockets, retry: to SSE) and a new server on the
# same port at once. tools/streamload's restart mode holds 1000 SSE + 1000 WebSocket clients through
# it and times their return; a second streamload holds 2000 for the second half; k6 runs lab's pages
# and publishes at 10 VUs throughout. Samples go to app/build/soak/samples.csv every 30 s.
#
# Env: SOAK_MINUTES (60), K6 (k6; else /opt/k6/k6), PORT (8198).
set -eu
cd "$(dirname "$0")/../.."
[ "$(uname -s)" = Linux ] || { echo "soak: Linux only" >&2; exit 2; }
MIN="${SOAK_MINUTES:-60}"
HALF=$((MIN * 60 / 2))
K6="${K6:-$(command -v k6 || echo /opt/k6/k6)}"
PORT="${PORT:-8198}"
LOGS=app/build/soak
mkdir -p "$LOGS" app/bin
BIN=app/bin/lab-soak
echo "soak: building lab and streamload ..."
OUT="$BIN" sh build.sh lab -o:speed >/dev/null
odin build tools/streamload -o:speed -out:app/bin/streamload >/dev/null
ulimit -n 8192

serve() { # log
  STREAMS_PER_CLIENT=100000 STREAM_CONNECTS=100000 STREAMS_PER_USER=100000 LAB_PUBLISH_PER_MINUTE=100000000 PORT="$PORT" THREADS=4 LOG_LEVEL=warn "$BIN" "$PORT" >>"$1" 2>&1 &
  SRV=$!
  i=0
  until curl -fs "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 200 ] || { echo "soak: the server never got ready" >&2; exit 1; }
    sleep 0.05
  done
}

sample() { # half, pid: seconds, rss kB, fds, open streams, queued bytes
  rss=$(sed -n 's/^VmRSS:[[:space:]]*\([0-9]*\).*/\1/p' "/proc/$2/status" 2>/dev/null || echo 0)
  fds=$(ls "/proc/$2/fd" 2>/dev/null | wc -l)
  stats=$(curl -fs "http://127.0.0.1:$PORT/lab/stats" || echo '{}')
  open=$(echo "$stats" | sed -n 's/.*"open":\([0-9]*\).*/\1/p')
  queued=$(echo "$stats" | sed -n 's/.*"queued":\([0-9]*\).*/\1/p')
  echo "$1,$(($(date +%s) - T0)),$rss,$fds,${open:-0},${queued:-0}" >>"$LOGS/samples.csv"
}

load() { # seconds: lab's pages and publishes at 10 VUs, in the background
  "$K6" run --quiet --env BASE_URL="http://127.0.0.1:$PORT" --env VUS=10 --env DURATION="${1}s" --env WARMUP=1s \
    --env OUT=/dev/null --env OUT_CSV=/dev/null load-tests/scenarios/lab/lab.js >>"$LOGS/k6.log" 2>&1 &
  K6PID=$!
}

: >"$LOGS/server.log"; : >"$LOGS/k6.log"
echo "half,s,rss_kb,fds,open,queued" >"$LOGS/samples.csv"
T0=$(date +%s)

# ---- the first half, then the redeploy ----------------------------------------------------
serve "$LOGS/server.log"
FIRST=$SRV
app/bin/streamload restart --base "http://127.0.0.1:$PORT" --sse 1000 --ws 1000 --publish 5 --within 30 >"$LOGS/restart.log" 2>&1 &
SL=$!
load "$HALF"
end=$(($(date +%s) + HALF))
while [ "$(date +%s)" -lt "$end" ]; do sleep 30; sample 1 "$FIRST"; done
kill -TERM "$FIRST"
wait "$FIRST" 2>/dev/null && first_exit=0 || first_exit=$?
serve "$LOGS/server.log"
wait "$SL" || true
wait "$K6PID" 2>/dev/null || true

# ---- the second half ----------------------------------------------------------------------
app/bin/streamload hold --base "http://127.0.0.1:$PORT" --sse 1000 --ws 1000 --for "$HALF" >"$LOGS/hold.log" 2>&1 &
SL=$!
load "$HALF"
end=$(($(date +%s) + HALF))
alive=1
while [ "$(date +%s)" -lt "$end" ]; do
  sleep 30
  kill -0 "$SRV" 2>/dev/null || { alive=0; break; }
  sample 2 "$SRV"
done
wait "$SL" || true
wait "$K6PID" 2>/dev/null || true
kill -TERM "$SRV" 2>/dev/null || true
wait "$SRV" 2>/dev/null || true

# ---- the verdict ----------------------------------------------------------------------------
back=$(sed -n 's/^back \([0-9]*\) of \([0-9]*\) dropped .* in \([0-9]*\) ms.*/\1 \2 \3/p' "$LOGS/restart.log")
set -- $back
back_n=${1:-0}; dropped=${2:-0}; back_ms=${3:-999999}
# Plateau: per half, the last sample against the first taken under full load (the second).
verdict=$(awk -F, '
  NR == 1 { next }
  { h = $1; n[h]++; if (n[h] == 2) { r0[h] = $3; f0[h] = $4 } r1[h] = $3; f1[h] = $4; if ($6 > q) q = $6 }
  END {
    ok = 1
    for (h in n) {
      if (n[h] < 3) { printf "half %s: too few samples\n", h; ok = 0; continue }
      rg = (r1[h] - r0[h]) / r0[h]; fg = (f1[h] - f0[h]) / (f0[h] > 0 ? f0[h] : 1)
      printf "half %s: rss %d -> %d kB (%+.1f %%), fds %d -> %d (%+.1f %%)\n", h, r0[h], r1[h], 100 * rg, f0[h], f1[h], 100 * fg
      if (rg > 0.10 || fg > 0.10) ok = 0
    }
    printf "queued: at most %d B\n", q
    if (q > 64 * 1024 * 1024) ok = 0
    print (ok ? "PLATEAU" : "GROWTH")
  }' "$LOGS/samples.csv")
echo "$verdict"
echo "soak: the redeploy: first server exit $first_exit; back $back_n of $dropped in $back_ms ms"
case "$verdict" in *PLATEAU*) plateau=1 ;; *) plateau=0 ;; esac
if [ "$plateau" = 1 ] && [ "$alive" = 1 ] && [ "$first_exit" = 0 ] && [ "$dropped" -ge 2000 ] && [ "$back_n" -ge "$dropped" ] && [ "$back_ms" -le 5000 ]; then
  echo "soak: PASS ($MIN min)"
else
  echo "soak: FAIL ($MIN min; alive=$alive)"
  exit 1
fi
