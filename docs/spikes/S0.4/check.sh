#!/usr/bin/env sh
# Spike S0.4: start every candidate in each of its modes and check it, with
# smoke.sh and, given --k6, one short k6 round of every load-tests scenario.
# Proves the binaries work; it measures nothing (S0.1/S0.2 run the parity gate).
#
#   [SCENARIOS="scale write"] docs/spikes/S0.4/check.sh [--k6] [--only "v3 C"] [--modes "file"] BIN_DIR
#
# BIN_DIR holds build.sh's binaries. Each check starts a fresh server on
# PORT_BASE (18500) and up, LOG_LEVEL=warn, and stops it after. --k6 runs each
# scenario at 200 VUs (scale at 20 VUs over 20k rows, its own setting) for a 1 s
# warmup and a 5 s window, on a fresh server, then asks /healthz whether the
# server survived. k6 is $K6, else k6 on PATH, else the Windows install. In WSL,
# K6 may name the Windows k6.exe: it reaches the WSL server through WSL's
# localhost forwarding, and gets its script paths through wslpath.
#
# The modes, and the environment each one runs with (unset = the default):
#   v3noidx  ephemeral   (nothing)
#   v3       ephemeral   (nothing)          single  MEMMODE=single    file  DB_PATH=<file> SEED=1
#   A        single      (nothing)          file    DB_PATH=<file> SEED=1
#   B        ephemeral   (nothing)          file    DB_PATH=<file> SEED=1
#   C        ephemeral   (nothing)          file    DB_PATH=<file> SEED=1
set -u

HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
K6RUN=""
ONLY=""
MODES=""
while [ $# -gt 1 ]; do
  case "$1" in
    --k6) K6RUN=1 ;;
    --only) shift; ONLY="$1" ;;
    --modes) shift; MODES="$1" ;;
    *) echo "unknown flag: $1" >&2; exit 2 ;;
  esac
  shift
done
[ $# -eq 1 ] || { sed -n '2,20p' "$0"; exit 2; }
BIN=$(cd "$1" && pwd)
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) EXE=.exe ;; *) EXE= ;; esac
PORT=${PORT_BASE:-18500}
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

K6="${K6:-}"
if [ -n "$K6RUN" ] && [ -z "$K6" ]; then
  if command -v k6 >/dev/null 2>&1; then K6=k6
  elif [ -x "/c/Program Files/k6/k6.exe" ]; then K6="/c/Program Files/k6/k6.exe"
  else echo "k6 not found: set K6" >&2; exit 1; fi
fi
k6_path() {
  case "$K6" in
    *.exe) if command -v wslpath >/dev/null 2>&1; then wslpath -w "$1"; else echo "$1"; fi ;;
    *) echo "$1" ;;
  esac
}
# A Windows k6 driven from WSL reaches the server through WSL's localhost forwarding, which
# picks up a new listener about half a second after it opens: probe from that side too.
PROBE=curl
case "$K6" in *.exe) command -v wslpath >/dev/null 2>&1 && command -v curl.exe >/dev/null 2>&1 && PROBE=curl.exe ;; esac

pid=""
start() { # candidate mode
  bin="$BIN/$1$EXE"
  PORT=$((PORT + 1))
  db=""
  memmode=""
  seed=""
  case "$2" in
    file) db="$WORK/s04-$1.db"; seed=1; rm -f "$db" "$db-wal" "$db-shm" ;;
    single) [ "$1" = A ] || memmode=single ;;
  esac
  PORT=$PORT LOG_LEVEL=warn DB_PATH="$db" MEMMODE="$memmode" SEED="$seed" "$bin" > "$WORK/server.log" 2>&1 &
  pid=$!
  tries=0
  until [ "$($PROBE -s -m 1 "http://127.0.0.1:$PORT/healthz")" = ok ]; do
    tries=$((tries + 1))
    if [ $tries -gt 100 ] || ! kill -0 "$pid" 2>/dev/null; then
      echo "FAIL  $1/$2 did not start"; cat "$WORK/server.log"; return 1
    fi
    sleep 0.1
  done
}
stop() {
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  pid=""
}

failed=0
modes() {
  case "$1" in
    v3) echo "ephemeral single file" ;;
    A) echo "single file" ;;
    *) echo "ephemeral file" ;;
  esac
}
cands="${ONLY:-v3noidx v3 A B C}"
for c in $cands; do
  [ -x "$BIN/$c$EXE" ] || continue
  for m in $(modes "$c"); do
    case " ${MODES:-$m} " in *" $m "*) ;; *) continue ;; esac
    echo "== $c / $m"
    start "$c" "$m" || { failed=$((failed + 1)); continue; }
    sh "$HERE/smoke.sh" "http://127.0.0.1:$PORT" > "$WORK/smoke.out" 2>&1 || failed=$((failed + 1))
    grep -v '^ok' "$WORK/smoke.out" | sed 's/^/   /'
    grep 'lagged' "$WORK/smoke.out" | sed 's/^ok */   /'
    stop
    [ -n "$K6RUN" ] || continue
    for s in "$ROOT"/load-tests/scenarios/*.js; do
      name=$(basename "$s" .js)
      case " ${SCENARIOS:-$name} " in *" $name "*) ;; *) continue ;; esac
      vus=200
      [ "$name" = scale ] && vus=20
      start "$c" "$m" || { failed=$((failed + 1)); continue; }
      "$K6" run --quiet --no-color -e BASE_URL="http://127.0.0.1:$PORT" -e VUS=$vus -e WARMUP=1s \
        -e DURATION=5s "$(k6_path "$s")" > "$WORK/k6.out" 2>&1
      line=$(grep ' VUs: ' "$WORK/k6.out" | sed 's/^ *//')
      alive=$($PROBE -s -m 2 "http://127.0.0.1:$PORT/healthz")
      stop
      echo "   k6 ${line:-no summary}; healthz after: ${alive:-none}"
      # A run that served nothing (a failed setup, say) is a failure, whatever its fail rate.
      case "$line" in
        *" 0 rps "* | "") failed=$((failed + 1)); grep -iE 'erro|error' "$WORK/k6.out" | tail -3 | sed 's/^/      /' ;;
      esac
      [ "$alive" = ok ] || failed=$((failed + 1))
    done
  done
done
echo "$failed failed"
[ "$failed" -eq 0 ]
