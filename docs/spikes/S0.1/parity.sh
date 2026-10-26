#!/usr/bin/env sh
# The parity gate's measurement loop (PLAN §18.2 steps 2-6), as spikes S0.1, S0.2 and S0.4 run it.
# M1 folded it into `load-tests/run.sh --parity` (lib/parity.sh); scenarios now live per feature.
#
#   VARIANTS="head=bin/head v111=bin/v111 fork=bin/fork" STORES="mem file" ROUNDS=3 \
#   RESULTS=out.csv docs/spikes/S0.1/parity.sh [scenario ...]
#
# Per round, per scenario, per store, every variant runs back to back (the order rotates each
# round), each on a fresh server: THREADS=16 loops, LOG_LEVEL=warn, k6 at 200 VUs (scale: 20 VUs
# over 20k rows), 3 s warmup + 10 s window. Background CPU is sampled before each block. A variant
# can carry its own env: VENV_<name>="KEY=value KEY2=value" (e.g. a memory mode), and a store can
# be limited per variant with VSTORES_<name>="mem".
#
# ROUND_FIRST numbers the rounds from there (default 1): a block re-run with the same round number
# and scenario is appended to RESULTS, and analyze.mjs takes the last row of each run.
#
# Env: K6, THREADS (16), VUS (200), SCALE_VUS (20), WARMUP (3s), DURATION (10s), PORT_BASE (9800),
# TMPDIR for file DBs. Runs in Git Bash on Windows and in Linux (WSL2); in WSL it reads the
# Windows host's CPU through typeperf.exe, since the VM can't see the host's load.
set -eu
HERE="$(cd "$(dirname "$0")" && pwd)"
LT="$(cd "$HERE/../../../load-tests" && pwd)"

VARIANTS="${VARIANTS:?set VARIANTS=\"name=binary ...\"}"
STORES="${STORES:-mem file}"
ROUNDS="${ROUNDS:-3}"
THREADS="${THREADS:-16}"
VUS="${VUS:-200}"
SCALE_VUS="${SCALE_VUS:-20}"
WARMUP="${WARMUP:-3s}"
DURATION="${DURATION:-10s}"
port="${PORT_BASE:-9800}"
RESULTS="${RESULTS:-parity.csv}"
SCEN="${*:-static seo pages list search api detail write mixed scale}"
DBDIR="${TMPDIR:-/tmp}/parity-db"
mkdir -p "$DBDIR"

case "$(uname -s)" in
  *MINGW*|*MSYS*|*CYGWIN*) WIN=1 ;;
  *) WIN= ;;
esac
K6="${K6:-}"
if [ -z "$K6" ]; then
  if [ -n "$WIN" ]; then K6="/c/Program Files/k6/k6.exe"; else K6="$(command -v k6 || echo /opt/k6/k6)"; fi
fi
path_for_k6() { if [ -n "$WIN" ]; then cygpath -w "$1"; else echo "$1"; fi; }

# The host's CPU, busy %, over one second.
bgcpu() {
  if [ -n "$WIN" ]; then tp=typeperf; else tp=/mnt/c/Windows/System32/typeperf.exe; fi
  "$tp" "\\Processor(_Total)\\% Processor Time" -sc 1 2>/dev/null | tr -d '\r' | sed -n 3p | awk -F'"' '{printf "%.0f", $4}'
}

[ -f "$RESULTS" ] || echo "round,scenario,store,variant,vus,rps,p50,p90,p95,p99,max,fail_rate,bytes_per_s,bg_cpu" > "$RESULTS"

rotate() { # rotate a word list left by $1
  n="$1"; shift
  i=0; while [ "$i" -lt "$n" ] && [ $# -gt 1 ]; do first="$1"; shift; set -- "$@" "$first"; i=$((i + 1)); done
  echo "$@"
}

run_one() { # round scenario store name binary
  r="$1"; s="$2"; st="$3"; name="$4"; bin="$5"
  port=$((port + 1))
  if [ "$st" = file ]; then
    db="$DBDIR/p_$port.db"; rm -f "$db" "$db-wal" "$db-shm"
  else
    db=":memory:"
  fi
  venv="$(eval echo "\${VENV_$name:-}")"
  log="$DBDIR/srv_$port.log"
  # shellcheck disable=SC2086
  env $venv PORT=$port THREADS=$THREADS LOG_LEVEL=warn DB_PATH="$db" SEED=1 SITE_URL= "$bin" $port > "$log" 2>&1 &
  pid=$!
  i=0
  until curl -fs "http://127.0.0.1:$port/healthz" >/dev/null 2>&1; do
    i=$((i + 1)); [ $i -gt 300 ] && { echo "$name never healthy:"; cat "$log"; break; }; sleep 0.05
  done
  v=$VUS; [ "$s" = scale ] && v=$SCALE_VUS
  csv="$DBDIR/k6_$port.csv"; rm -f "$csv"
  "$K6" run --quiet --env BASE_URL="http://127.0.0.1:$port" --env VUS="$v" --env DURATION="$DURATION" \
    --env WARMUP="$WARMUP" --env OUT_CSV="$(path_for_k6 "$csv")" "$(path_for_k6 "$(ls "$LT"/scenarios/*/"$s".js)")" > /dev/null 2>&1 || true
  kill "$pid" 2>/dev/null || true
  wait "$pid" 2>/dev/null || true
  [ "$st" = file ] && rm -f "$db" "$db-wal" "$db-shm"
  if [ -f "$csv" ]; then
    row="$(tr -d '\r\n' < "$csv")" # scenario,vus,rps,p50,p90,p95,p99,max,fail_rate,bytes_per_s
    echo "$r,$s,$st,$name,$(echo "$row" | cut -d, -f2-),$bg" >> "$RESULTS"
    echo "  r$r $s/$st $name: $(echo "$row" | cut -d, -f3) rps p99 $(echo "$row" | cut -d, -f7) ms fail $(echo "$row" | cut -d, -f9) bg=$bg"
  else
    echo "$r,$s,$st,$name,$v,,,,,,,,,$bg" >> "$RESULTS"
    echo "  r$r $s/$st $name: NO RESULT"; tail -3 "$log"
  fi
}

r="${ROUND_FIRST:-1}"
last=$((r + ROUNDS - 1))
while [ "$r" -le "$last" ]; do
  for s in $SCEN; do
    bg="$(bgcpu)"
    for st in $STORES; do
      for spec in $(rotate $((r - 1)) $VARIANTS); do
        name="${spec%%=*}"; bin="${spec#*=}"
        only="$(eval echo "\${VSTORES_$name:-}")"
        if [ -n "$only" ]; then case " $only " in *" $st "*) ;; *) continue ;; esac; fi
        run_one "$r" "$s" "$st" "$name" "$bin"
      done
    done
  done
  r=$((r + 1))
done
echo "results: $RESULTS"
