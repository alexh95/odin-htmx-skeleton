#!/usr/bin/env sh
# TSan over the shared state (PLAN §19.2, §22.3's M2 gate): the hub, the streams, the workers and
# store/sqlite. Linux only: Windows refuses -sanitize:thread (09 §3). It builds with
# -sanitize:thread -debug and counts ThreadSanitizer reports in:
#   1. those four packages' unit tests;
#   2. lab, under tools/streamload's fan-out (SSE and WebSocket clients, a publisher across loops)
#      and a restart's reconnects;
#   3. skeleton, under k6's write and pages scenarios (the writer task, the per-loop readers, the
#      query pool).
# tsan.supp holds the one report known not to be the app's: core:nbio's cross-thread queue reads a
# field in an assert without the atomic (S0.9), until an Odin bump fixes it. Exit 1 on any report.
#
#   sh tools/drills/tsan.sh        (from the repo root, prepared)
#
# Env: K6 (k6; else /opt/k6/k6), PORT (8197).
set -eu
cd "$(dirname "$0")/../.."
[ "$(uname -s)" = Linux ] || { echo "tsan: Linux only" >&2; exit 2; }
K6="${K6:-$(command -v k6 || echo /opt/k6/k6)}"
PORT="${PORT:-8197}"
LOGS=app/build/tsan
mkdir -p "$LOGS" app/bin
export TSAN_OPTIONS="suppressions=$(pwd)/tools/drills/tsan.supp halt_on_error=0 second_deadlock_stack=1"
FAMILIES="-collection:store=app/stores/memory -collection:identity=app/platform/authz/anonymous -collection:client=app/platform/client/vanilla -collection:theme=app/platform/theme/lite"
TOTAL=0

count() { # log, what
  n=$(grep -c 'WARNING: ThreadSanitizer' "$1" || true)
  echo "tsan: $2: $n report(s)"
  TOTAL=$((TOTAL + n))
}

# A server, ready; streams' per-client caps lifted, as the suites do.
serve() { # bin, log
  STREAMS_PER_CLIENT=100000 STREAM_CONNECTS=100000 LAB_PUBLISH_PER_MINUTE=100000000 PORT="$PORT" THREADS=4 LOG_LEVEL=warn "$1" "$PORT" >"$2" 2>&1 &
  SRV=$!
  i=0
  until curl -fs "http://127.0.0.1:$PORT/readyz" >/dev/null 2>&1; do
    i=$((i + 1)); [ "$i" -lt 600 ] || { echo "tsan: $1 never got ready" >&2; tail -20 "$2" >&2; exit 1; }
    sleep 0.05
  done
}

# SIGTERM: the app's handler drains (a TSan build defers the default action, S0.9).
stop() {
  kill -TERM "$SRV" 2>/dev/null || true
  i=0
  while kill -0 "$SRV" 2>/dev/null; do
    i=$((i + 1)); [ "$i" -lt 200 ] || { kill -KILL "$SRV"; break; }
    sleep 0.05
  done
  wait "$SRV" 2>/dev/null || true
}

# ---- 1. the unit tests -------------------------------------------------------------------
for pkg in hub stream workers store/sqlite; do
  log="$LOGS/test-$(echo "$pkg" | tr / -).log"
  odin test "app/platform/$pkg" $FAMILIES -sanitize:thread -debug -out:app/bin/tsan-test >"$log" 2>&1 || echo "tsan: platform/$pkg's tests failed (see $log)"
  count "$log" "platform/$pkg's tests"
done

# ---- 2. lab under the stream load --------------------------------------------------------
echo "tsan: building lab and streamload ..."
OUT=app/bin/lab-tsan sh build.sh lab -sanitize:thread -debug >/dev/null
odin build tools/streamload -o:speed -out:app/bin/streamload >/dev/null
serve app/bin/lab-tsan "$LOGS/lab.log"
app/bin/streamload fanout --base "http://127.0.0.1:$PORT" --sse 200 --ws 200 --publish 200 --every 5 >"$LOGS/streamload.log" 2>&1 || true
stop
count "$LOGS/lab.log" "lab under 200 SSE + 200 WS and 200 publishes, then the drain"

# ---- 3. skeleton under writes and pages --------------------------------------------------
echo "tsan: building skeleton ..."
OUT=app/bin/skeleton-tsan sh build.sh skeleton -sanitize:thread -debug >/dev/null
serve app/bin/skeleton-tsan "$LOGS/skeleton.log"
for sc in contacts/write dashboard/pages; do
  "$K6" run --quiet --env BASE_URL="http://127.0.0.1:$PORT" --env VUS=20 --env DURATION=8s --env WARMUP=1s \
    --env OUT=/dev/null --env OUT_CSV=/dev/null "load-tests/scenarios/$sc.js" >/dev/null 2>&1 || true
done
stop
count "$LOGS/skeleton.log" "skeleton under write and pages, then the drain"

echo "tsan: $TOTAL report(s) in all (logs in $LOGS/)"
[ "$TOTAL" -eq 0 ]
