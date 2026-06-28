#!/usr/bin/env sh
# Load-test driver. Builds the app `-o:speed`, then for each scenario and each VU
# level launches a FRESH server on a dedicated port (clean in-memory store — see
# load-tests/PLAN.md, "The write path needs care"), waits for /healthz, runs k6
# for a warmup + measured window, and collects the result. At the end it stitches
# every run into results/summary.md and prints the table.
#
# Usage:
#   ./run.sh                       # default sweep (10,50,100 VUs) over all scenarios
#   ./run.sh --quick               # fast sanity: 20 VUs, short window
#   ./run.sh --sweep               # full curve: 1,10,50,100,200,500 VUs
#   ./run.sh --vus 1,100,500       # explicit VU levels
#   ./run.sh static api            # only these scenarios
#   ./run.sh --base https://host   # hit a remote target; skips build + local server
#
# Env: K6 (k6 binary), DURATION (30s), WARMUP (5s), PORT_BASE (8090).
set -eu
cd "$(dirname "$0")"

# ---- config / arg parsing -----------------------------------------------
SCENARIOS=""
VUS="10,50,100"
DURATION="${DURATION:-30s}"
WARMUP="${WARMUP:-5s}"
PORT_BASE="${PORT_BASE:-8090}"
BASE=""              # set => external target, no local build/launch
P95="${P95:-50}"; P99="${P99:-100}"

while [ $# -gt 0 ]; do
  case "$1" in
    --quick)  VUS="20"; DURATION="6s"; WARMUP="2s" ;;
    --sweep)  VUS="1,10,50,100,200,500" ;;
    --vus)    shift; VUS="$1" ;;
    --duration) shift; DURATION="$1" ;;
    --base)   shift; BASE="$1" ;;
    --*)      echo "unknown flag: $1" >&2; exit 2 ;;
    *)        SCENARIOS="$SCENARIOS $1" ;;
  esac
  shift
done
[ -n "$SCENARIOS" ] || SCENARIOS="static pages search api detail write mixed"

# ---- locate k6 ----------------------------------------------------------
K6="${K6:-}"
if [ -z "$K6" ]; then
  if command -v k6 >/dev/null 2>&1; then K6="k6"
  elif [ -x "/c/Program Files/k6/k6.exe" ]; then K6="/c/Program Files/k6/k6.exe"
  else echo "k6 not found. Install it (winget install GrafanaLabs.k6) or set K6=path." >&2; exit 1
  fi
fi
echo "k6: $("$K6" version | head -1)"

# bombardier is an optional fast baseline; used only if present.
BOMBARDIER="${BOMBARDIER:-}"
[ -z "$BOMBARDIER" ] && command -v bombardier >/dev/null 2>&1 && BOMBARDIER="bombardier"

# ---- build the app (skipped for an external --base target) ---------------
APP="../app"
BIN="$APP/bin/demo"
case "$(uname -s)" in *MINGW*|*MSYS*|*CYGWIN*) BIN="$APP/bin/demo.exe" ;; esac

if [ -z "$BASE" ]; then
  echo "building app -o:speed ..."
  ( cd "$APP" && mkdir -p bin && odin build src -out:"bin/$(basename "$BIN")" -o:speed -warnings-as-errors )
fi

# ---- results dir --------------------------------------------------------
RAW="results/raw"
rm -rf results
mkdir -p "$RAW"

# ---- server lifecycle helpers -------------------------------------------
SRV_PID=""
start_server() { # $1 = port
  "$BIN" "$1" >"$RAW/server_$1.log" 2>&1 &
  SRV_PID=$!
  # wait for /healthz (up to ~10s)
  i=0
  while [ $i -lt 100 ]; do
    if curl -fs "http://127.0.0.1:$1/healthz" >/dev/null 2>&1; then return 0; fi
    i=$((i + 1)); sleep 0.1
  done
  echo "server on :$1 never became healthy; log:" >&2; cat "$RAW/server_$1.log" >&2
  return 1
}
stop_server() {
  [ -n "$SRV_PID" ] || return 0
  kill "$SRV_PID" 2>/dev/null || true
  wait "$SRV_PID" 2>/dev/null || true
  SRV_PID=""
}
trap stop_server EXIT INT TERM

# ---- run matrix ---------------------------------------------------------
port=$PORT_BASE
for s in $SCENARIOS; do
  script="scenarios/$s.js"
  [ -f "$script" ] || { echo "no such scenario: $s" >&2; exit 2; }

  for vus in $(echo "$VUS" | tr ',' ' '); do
    target="${BASE:-http://127.0.0.1:$port}"
    if [ -z "$BASE" ]; then start_server "$port" || exit 1; fi

    echo "==> $s @ ${vus} VUs (${DURATION} window) -> $target"
    "$K6" run \
      --quiet \
      --env "BASE_URL=$target" \
      --env "VUS=$vus" \
      --env "DURATION=$DURATION" \
      --env "WARMUP=$WARMUP" \
      --env "P95=$P95" --env "P99=$P99" \
      --env "OUT=$RAW/${s}_${vus}.json" \
      --env "OUT_CSV=$RAW/${s}_${vus}.csv" \
      "$script" || echo "  (thresholds breached at ${vus} VUs — recorded, continuing)"

    if [ -z "$BASE" ]; then stop_server; port=$((port + 1)); fi
  done
done

# ---- bombardier baselines (optional) ------------------------------------
if [ -n "$BOMBARDIER" ] && [ -z "$BASE" ]; then
  echo "bombardier baselines (raw throughput, 10s @ 100 conns) ..."
  start_server "$port" || exit 1
  for path in /static/app.css /api/search?q=a /; do
    echo "--- $path ---" >>"$RAW/bombardier.txt"
    "$BOMBARDIER" -d 10s -c 100 -l "http://127.0.0.1:$port$path" >>"$RAW/bombardier.txt" 2>&1 || true
  done
  stop_server
fi

# ---- stitch the summary -------------------------------------------------
SUMMARY="results/summary.md"
{
  echo "# Load-test run — $(date -u '+%Y-%m-%d %H:%M UTC')"
  echo
  echo "Target: ${BASE:-local (-o:speed, fresh server per run)} · window: $DURATION · warmup: $WARMUP"
  echo "Machine: $(uname -s -m)"
  echo
  echo "| scenario | VUs | RPS | p50 ms | p90 ms | p95 ms | p99 ms | max ms | fail % | KB/s |"
  echo "|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|"
  for f in $(ls "$RAW"/*.csv 2>/dev/null | sort); do
    # csv: scenario,vus,rps,p50,p90,p95,p99,max,fail_rate,bytes_per_s
    awk -F',' '{
      printf "| %s | %s | %s | %s | %s | %s | %s | %s | %.2f | %d |\n",
        $1, $2, $3, $4, $5, $6, $7, $8, $9*100, $10/1024
    }' "$f"
  done
} >"$SUMMARY"

echo
echo "================ summary ($SUMMARY) ================"
cat "$SUMMARY"
echo
echo "raw per-run JSON + server logs in $RAW/"
