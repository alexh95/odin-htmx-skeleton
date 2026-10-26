#!/usr/bin/env sh
# Load-test driver. Builds the profile `-o:speed`, then for each scenario and each
# VU level launches a FRESH server on a dedicated port (clean in-memory store — see
# load-tests/PLAN.md, "The write path needs care"), waits for /healthz, runs k6
# for a warmup + measured window, scrapes the server's per-route counters, and
# collects the result. At the end it stitches every run into results/summary.md
# and prints the table.
#
# Scenarios live per feature, scenarios/<f>/<name>.js, each with a `// tags:` line
# naming every feature it touches (@<f>, or @<f>-<member> for one family member),
# as the e2e specs are tagged. A run takes the scenarios whose features the build
# has, by its own `--features --json`.
#
# Usage:
#   ./run.sh                       # default sweep (10,50,100 VUs) over the profile's scenarios
#   ./run.sh --quick               # fast sanity: 20 VUs, short window
#   ./run.sh --sweep               # full curve: 1,10,50,100,200,500 VUs
#   ./run.sh --vus 1,100,500       # explicit VU levels
#   ./run.sh static api            # only these scenarios
#   ./run.sh --base https://host   # hit a remote target; skips build + local server
#   ./run.sh --strict              # exit 1 if any run breaches its thresholds
#   ./run.sh --parity [scenario …] # the parity gate (PLAN §18.2): lib/parity.sh
#
# Env: K6 (k6 binary), DURATION (30s), WARMUP (5s), PORT_BASE (8090), PROFILE (skeleton).
set -eu
cd "$(dirname "$0")"

[ "${1:-}" = "--parity" ] && { shift; exec sh lib/parity.sh "$@"; }

# ---- config / arg parsing -----------------------------------------------
SCENARIOS=""
VUS="10,50,100"
DURATION="${DURATION:-30s}"
WARMUP="${WARMUP:-5s}"
PORT_BASE="${PORT_BASE:-8090}"
BASE=""              # set => external target, no local build/launch
STRICT=""            # set => a breached threshold fails the whole run (exit 1)
P95="${P95:-50}"; P99="${P99:-100}"

while [ $# -gt 0 ]; do
  case "$1" in
    --quick)  VUS="20"; DURATION="6s"; WARMUP="2s" ;;
    --sweep)  VUS="1,10,50,100,200,500" ;;
    --vus)    shift; VUS="$1" ;;
    --duration) shift; DURATION="$1" ;;
    --base)   shift; BASE="$1" ;;
    --strict) STRICT=1 ;;
    --*)      echo "unknown flag: $1" >&2; exit 2 ;;
    *)        SCENARIOS="$SCENARIOS $1" ;;
  esac
  shift
done

# A scenario by name, wherever its feature keeps it: one file per name.
script_of() {
  set -- scenarios/*/"$1".js
  [ -f "$1" ] || { echo "no such scenario: $(basename "$1" .js)" >&2; return 1; }
  [ $# -eq 1 ] || { echo "two scenarios named $(basename "$1" .js): $*" >&2; return 1; }
  echo "$1"
}

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
# PROFILE picks the build (build.sh <profile>): skeleton, the parity witness, by default.
APP="../app"
PROFILE="${PROFILE:-skeleton}"
BIN="$APP/bin/$PROFILE"
case "$(uname -s)" in *MINGW*|*MSYS*|*CYGWIN*) BIN="$APP/bin/$PROFILE.exe" ;; esac

if [ -z "$BASE" ]; then
  echo "building $PROFILE -o:speed ..."
  sh ../build.sh "$PROFILE" -o:speed
fi

# ---- the build's features, and the scenarios that need only those ------------
# `--features --json` flattened onto one line: no jq, so plain sed.
FEATURES=""; MEMBERS=""
if [ -x "$BIN" ]; then
  info="$("$BIN" --features --json | tr -d ' \t\r\n')"
  FEATURES="$(echo "$info" | sed 's/.*"features":\[\([^]]*\)\].*/\1/' | tr -d '"' | tr ',' ' ')"
  for k in store identity client theme; do
    MEMBERS="$MEMBERS $(echo "$info" | sed "s/.*\"$k\":\"\([^\"]*\)\".*/\1/")"
  done
fi
# Whether the build has every feature (and member) a scenario's tags name. With
# no binary to ask (--base, nothing built here), every scenario counts.
wanted() { # $1 = script; sh has no locals, hence the w_ names
  grep -q '^// tags: @' "$1" || { echo "$1 has no '// tags:' line" >&2; exit 2; }
  [ -n "$FEATURES" ] || return 0
  for w_tag in $(sed -n 's|^// tags: ||p' "$1"); do
    w_tag="${w_tag#@}"; w_f="${w_tag%%-*}"; w_m=""; [ "$w_f" = "$w_tag" ] || w_m="${w_tag#*-}"
    case " $FEATURES " in *" $w_f "*) ;; *) return 1 ;; esac
    [ -z "$w_m" ] && continue
    case " $MEMBERS " in *" $w_m "*) ;; *) return 1 ;; esac
  done
}
# Default: every scenario of the build's features, so a new one is just a file.
if [ -z "$SCENARIOS" ]; then
  for f in scenarios/*/*.js; do
    [ -f "$f" ] || continue
    wanted "$f" && SCENARIOS="$SCENARIOS $(basename "$f" .js)"
  done
  [ -n "$SCENARIOS" ] || { echo "no scenarios for $PROFILE in $(pwd)/scenarios" >&2; exit 2; }
fi
for s in $SCENARIOS; do script_of "$s" >/dev/null || exit 2; done

# ---- results dir --------------------------------------------------------
RAW="results/raw"
rm -rf results
mkdir -p "$RAW"

# Each run's per-route request counters, scraped from /metrics before its server
# stops, for `tools/check parity` (PLAN §19.1.11): every route the profile mounts
# needs a non-zero count from this suite and from e2e. The bearer is this run's.
ROUTES="$APP/build/coverage/load/$PROFILE"
TOKEN=""
if [ -z "$BASE" ]; then
  rm -rf "$ROUTES"; mkdir -p "$ROUTES"
  TOKEN="$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
  printf '%s' "$TOKEN" >"$ROUTES/.token"
fi

# ---- server lifecycle helpers -------------------------------------------
# free_port: the first port from $1 that nothing listens on (lib/ports.sh).
. lib/ports.sh

SRV_PID=""
start_server() { # $1 = port
  # PORT is set, not just passed: the server prefers an exported PORT over argv.
  # LOG_LEVEL=warn drops the access log (~9% of throughput) so numbers stay
  # comparable with runs before it existed; export LOG_LEVEL=info to keep it.
  PORT="$1" LOG_LEVEL="${LOG_LEVEL:-warn}" METRICS_TOKEN_FILE="$ROUTES/.token" "$BIN" "$1" >"$RAW/server_$1.log" 2>&1 &
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
stop_server() { # $1 = port and $2 = the run's name, to scrape its counters first
  [ -n "$SRV_PID" ] || return 0
  if [ -n "${2:-}" ]; then
    curl -fs -H "Authorization: Bearer $TOKEN" "http://127.0.0.1:$1/metrics" |
      grep '^app_http_requests_total{' >"$ROUTES/$2.prom" || true
  fi
  kill "$SRV_PID" 2>/dev/null || true
  wait "$SRV_PID" 2>/dev/null || true
  SRV_PID=""
}
trap stop_server EXIT INT TERM

# ---- run matrix ---------------------------------------------------------
port=$PORT_BASE
FAILED=""   # scenario@VUs of every run k6 failed (a breached threshold, or worse)
for s in $SCENARIOS; do
  script="$(script_of "$s")"

  for vus in $(echo "$VUS" | tr ',' ' '); do
    [ -n "$BASE" ] || port="$(free_port "$port")"
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
      --env "METRICS_TOKEN=$TOKEN" \
      --env "OUT=$RAW/${s}_${vus}.json" \
      --env "OUT_CSV=$RAW/${s}_${vus}.csv" \
      "$script" || {
        # Keep going either way: one breach shouldn't cost the rest of the table.
        rc=$?; FAILED="$FAILED ${s}@${vus}"
        echo "  (k6 exit $rc at ${vus} VUs: thresholds breached, or an error — recorded, continuing)"
      }

    if [ -z "$BASE" ]; then stop_server "$port" "${s}_${vus}"; port=$((port + 1)); fi
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
  echo "Target: ${BASE:-local $PROFILE (-o:speed, fresh server per run)} · window: $DURATION · warmup: $WARMUP"
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
[ -z "$BASE" ] && echo "per-route counters in $ROUTES/"

# Without --strict a breach is information (finding the knee is what a sweep is
# for); with it, the run is a gate.
if [ -n "$FAILED" ]; then
  echo "failed runs:$FAILED"
  [ -z "$STRICT" ] || exit 1
fi
