#!/usr/bin/env bash
# S0.8 matrix: every case through measure.mjs, one JSON line each, with the box's CPU sampled just
# before the run (typeperf, Windows) and over it (cpu_run, from measure.mjs). A run whose box was
# busier than MAX_CPU % is repeated, up to 3 tries; every try is kept with its number.
# PRIO=high runs the client at high priority (set the server and Caddy to High too).
# Needs `s08.exe 18780` and `caddy run` (Caddyfile) running. Usage: ./run.sh [out.jsonl]
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
out=${1:-results.jsonl}
MAX_CPU=${MAX_CPU:-50}
BR='gzip, deflate, br, zstd' # Chromium's Accept-Encoding: Caddy picks zstd
GZ='gzip, deflate'           # a client without zstd: Caddy picks gzip

cpu() { MSYS_NO_PATHCONV=1 typeperf '\Processor(_Total)\% Processor Time' -sc 1 | sed -n 3p | awk -F'"' '{printf "%.0f", $4}'; }

run() { # run <label> <port> <ae> <measure args...>
	local label=$1 port=$2 ae=$3; shift 3
	local try c line busy
	for try in 1 2 3; do
		c=$(cpu)
		line=$(node "$here/measure.mjs" "base=http://127.0.0.1:$port" "ae=$ae" "label=$label" ${PRIO:+"prio=$PRIO"} "$@")
		line="${line%\}},\"cpu_before\":$c,\"try\":$try}"
		echo "$line" | tee -a "$out"
		busy=$(sed -E 's/.*"cpu_run":([0-9]+).*/\1/' <<<"$line")
		((busy <= MAX_CPU)) && break
	done
	return 0
}

# label     port   Accept-Encoding
CASES=(
	"direct   18780 $BR"
	"plain    18781 $BR"
	"stack    18783 $BR"
	"spark-zstd 18782 $BR"
	"spark-gzip 18782 $GZ"
	"matcher  18785 $BR"
)

for c in "${CASES[@]}"; do
	read -r label port ae <<<"$c" # ae takes the rest of the line
	# steady state: one stream, 1000 events 10 ms apart, small (< 512 B) and 1 KiB events
	run "$label" "$port" "$ae" kind=sse n=1000 ms=10 pad=0
	run "$label" "$port" "$ae" kind=sse n=1000 ms=10 pad=1024
	run "$label" "$port" "$ae" kind=mp n=1000 ms=10 pad=0
	run "$label" "$port" "$ae" kind=mp n=1000 ms=10 pad=1024
	# first event of a fresh stream: 200 streams, 10 at a time, 3 events 50 ms apart
	run "$label" "$port" "$ae" kind=sse n=3 ms=50 pad=1024 streams=200 conc=10
	run "$label" "$port" "$ae" kind=mp n=3 ms=50 pad=1024 streams=200 conc=10
	# fan-out: 100 concurrent streams, 200 events each, 20 ms apart
	run "$label" "$port" "$ae" kind=sse n=200 ms=20 pad=1024 streams=100 conc=100
	run "$label" "$port" "$ae" kind=mp n=200 ms=20 pad=1024 streams=100 conc=100
done

# the app-side opt-out: spark's site, streams sent with `Cache-Control: no-cache, no-transform`
run spark-nt 18782 "$BR" kind=sse n=1000 ms=10 pad=1024 nt=1
run spark-nt 18782 "$BR" kind=mp n=1000 ms=10 pad=1024 nt=1

# WebSocket through spark's site (encode on): server push and echo round trip
run spark-ws 18782 "$BR" kind=ws n=1000 ms=10 pad=0
run spark-ws 18782 "$BR" kind=ws n=1000 ms=10 pad=1024
run spark-ws 18782 "$BR" kind=echo n=1000 ms=5 pad=64
run direct-ws 18780 "$BR" kind=ws n=1000 ms=10 pad=1024
run direct-ws 18780 "$BR" kind=echo n=1000 ms=5 pad=64
