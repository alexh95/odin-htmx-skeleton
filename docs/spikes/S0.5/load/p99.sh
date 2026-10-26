#!/usr/bin/env bash
# S0.5: /ui/ping p99 with and without 50 logins/s, the arms interleaved (the order rotates each
# round). The server gets CPUs 0-3 (an apollo-sized box: THREADS=2), k6 the rest.
#   p99.sh <s05 binary> <rounds> <ping rps> <seconds> <out dir> [arms...]
# Arms: base (no logins), pool (50/s on the argon pool), idle (the same with the workers under
# SCHED_IDLE), pool1 and idle1 (one argon thread instead of two), inline (50/s hashed on the loop),
# basepin and pin (base and pool with the loops on CPUs 0-1 and the workers on 2-3).
# One line per run: the k6 numbers, the server's counters, and CPU busy % over the run for the
# server's CPUs, the other CPUs of the VM, and (WIN_CPU=1) the Windows host as a whole.
# RATE sets the login arms' logins/s (50). QUOTA=200% caps the server's cgroup at 2 CPUs of time
# (compose's `cpus: 2.0`) through systemd-run, and adds the cgroup's throttling counters to the line.
set -uo pipefail
bin=$1 rounds=$2 rps=$3 secs=$4 out=$5
shift 5
arms=("${@:-base pool inline}")
read -r -a arms <<<"${arms[*]}"
here=$(cd "$(dirname "$0")" && pwd)
k6=${K6:-k6}
mkdir -p "$out"
port=${PORT0:-18800}

# busy% per CPU group between two /proc/stat snapshots: "<server cpus> <other cpus>"
cpu_snap() { grep '^cpu[0-9]' /proc/stat; }
cpu_busy() {
	awk 'NR==FNR { for (i = 2; i <= NF; i++) t0[$1] += $i; i0[$1] = $5 + $6; next }
		{ for (i = 2; i <= NF; i++) t1[$1] += $i; i1[$1] = $5 + $6 }
		END {
			for (c in t1) { n = substr(c, 4) + 0; dt = t1[c] - t0[c]; di = i1[c] - i0[c]
				if (n < 4) { st += dt; si += di } else { ot += dt; oi += di } }
			printf "%.1f %.1f", 100 * (st - si) / st, 100 * (ot - oi) / ot }' "$1" "$2"
}

n=${#arms[@]}
for r in $(seq 1 "$rounds"); do
	for j in $(seq 0 $((n - 1))); do
		arm=${arms[$(((j + r - 1) % n))]}
		inline=0 logins=${RATE:-50} sched= argon=2 pin=
		case $arm in
		base) logins=0 ;;
		basepin) logins=0 pin=1 ;;
		pin) pin=1 ;;
		inline) inline=1 ;;
		idle) sched=idle ;;
		pool1) argon=1 ;;
		idle1) sched=idle argon=1 ;;
		esac
		wrap=()
		[ -n "${QUOTA:-}" ] && wrap=(systemd-run --scope --quiet -p "CPUQuota=$QUOTA")
		ARGON_PRESET=${ARGON_PRESET:-owasp} ARGON_SCHED=$sched PIN=$pin INLINE=$inline THREADS=2 ACCOUNTS_ARGON_THREADS=$argon PORT=$port \
			"${wrap[@]}" taskset -c 0-3 "$bin" >"$out/server-$arm-$r.log" 2>&1 &
		pid=$!
		until curl -sf -o /dev/null "127.0.0.1:$port/ui/ping"; do sleep 0.1; done

		win=""
		if [ "${WIN_CPU:-0}" = 1 ]; then
			typeperf.exe '\Processor(_Total)\% Processor Time' -si 1 -sc $((secs + 5)) \
				>"$out/win-$arm-$r.csv" 2>/dev/null &
			win=$!
		fi
		cpu_snap >"$out/cpu0"
		taskset -c 4-15 "$k6" run -q -e BASE="http://127.0.0.1:$port" -e PING_RPS="$rps" -e LOGINS="$logins" \
			-e WARM="${WARM:-5}s" -e DUR="${secs}s" -e OUT="$out/k6-$arm-$r.json" "$here/p99.js" >/dev/null 2>&1
		cpu_snap >"$out/cpu1"
		stats=$(curl -s "127.0.0.1:$port/stats")
		# Under QUOTA: how often the cgroup ran out of CPU time in a period, and for how long in all.
		throttled=-
		if [ -n "${QUOTA:-}" ]; then
			cg=/sys/fs/cgroup$(cut -d: -f3 "/proc/$pid/cgroup")
			throttled=$(awk '$1 == "nr_periods" || $1 == "nr_throttled" || $1 == "throttled_usec" { printf "%s=%s ", $1, $2 }' "$cg/cpu.stat")
		fi
		kill -INT "$pid"
		wait "$pid"
		wincpu=-
		if [ -n "$win" ]; then
			wait "$win"
			wincpu=$(tr -d '"\r' <"$out/win-$arm-$r.csv" | awk -F, 'NR > 2 && $2 != "" { s += $2; n++ } END { if (n) printf "%.1f", s / n }')
		fi
		printf '%s round=%d k6=%s server=%s cpu_server_other=%s cpu_win=%s throttle=%s\n' \
			"$arm" "$r" "$(cat "$out/k6-$arm-$r.json")" "$stats" "$(cpu_busy "$out/cpu0" "$out/cpu1")" "$wincpu" "$throttled"
		port=$((port + 1))
	done
done
