#!/usr/bin/env bash
# S0.5: clients leaving mid-verify against an ASan build, then a SIGINT while verifies are in flight.
#   asan.sh <binary> <preset> <rounds> <seconds> <client threads> <log dir>
# FAKE_HASH_MS (env) is passed through: a sleep instead of the verify.
# Prints one line per round: variant, preset, round, ASan reports, exit code, client and server counts.
set -uo pipefail
bin=$1 preset=$2 rounds=$3 secs=$4 threads=$5 logs=$6
here=$(cd "$(dirname "$0")" && pwd)
mkdir -p "$logs"
port=${PORT0:-18600}
for r in $(seq 1 "$rounds"); do
	log="$logs/$(basename "$bin")-$preset-${FAKE_HASH_MS:-0}-$r.log"
	ASAN_OPTIONS=detect_leaks=0:halt_on_error=1 ARGON_PRESET=$preset THREADS=4 PORT=$port "$bin" >"$log" 2>&1 &
	pid=$!
	# The boot derives the account's tag, slow in a sanitized build: wait for the listener.
	until curl -sf -o /dev/null "127.0.0.1:$port/ui/ping"; do sleep 0.1; done
	clients=$(python3 "$here/load/disconnect.py" 127.0.0.1 "$port" "$threads" "$secs" 2>&1)
	# A last burst where every client leaves, and the stop signal in the middle of it.
	python3 "$here/load/disconnect.py" 127.0.0.1 "$port" "$threads" 1 50 1.0 >/dev/null 2>&1 &
	burst=$!
	sleep 0.3
	kill -INT "$pid" 2>/dev/null
	wait "$burst"
	wait "$pid"
	code=$?
	reports=$(grep -c "ERROR: AddressSanitizer" "$log")
	server=$(grep -o "stopped: .*" "$log" | head -1)
	printf '%s %s fake=%s round=%d asan_reports=%s exit=%d clients=%s %s\n' "$(basename "$bin")" "$preset" "${FAKE_HASH_MS:-0}" "$r" "$reports" "$code" "$clients" "$server"
	port=$((port + 1))
done
