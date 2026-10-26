#!/usr/bin/env bash
# S0.11: smoke a running skeleton build: /healthz, two pages, a write, a search,
# every sort, then a burst of 400 mixed reads and writes from 16 clients.
#   smoke.sh <binary> <port> <db path or :memory:>
# Prints one line per check and "smoke: N failed" at the end; exits non-zero on
# any failure. SMOKE_LOG=<file> keeps the server's output.
set -u
bin=$1; port=$2; db=$3
base="http://127.0.0.1:$port"
fails=0
check() { # <name> <expected code> <curl args...>
  name=$1; want=$2; shift 2
  got=$(curl -s -o /dev/null -w '%{http_code}' "$@")
  if [ "$got" = "$want" ]; then echo "ok   $name ($got)"; else echo "FAIL $name (got $got, want $want)"; fails=$((fails + 1)); fi
}
grep_body() { # <name> <needle> <curl args...>
  name=$1; needle=$2; shift 2
  if curl -s "$@" | grep -q "$needle"; then echo "ok   $name"; else echo "FAIL $name (no '$needle')"; fails=$((fails + 1)); fi
}
one() { # <i>: even i writes a contact, odd i reads a sorted, filtered page
  if [ $(($1 % 2)) = 0 ]; then
    curl -s -o /dev/null -w '%{http_code}\n' -X POST --data-urlencode "name=Burst $1" \
      --data-urlencode "email=b$1@example.com" --data-urlencode "role=Engineer" "$base/contacts"
  else
    curl -s -o /dev/null -w '%{http_code}\n' "$base/contacts?sort=role&q=burst"
  fi
}

[ "$db" != ":memory:" ] && rm -f "$db" "$db-wal" "$db-shm"
DB_PATH=$db SEED=1 PORT=$port "$bin" > "${SMOKE_LOG:-/dev/null}" 2>&1 &
pid=$!
for _ in $(seq 1 100); do
  curl -s -o /dev/null "$base/healthz" && break
  sleep 0.1
done

check "/healthz" 200 "$base/healthz"
grep_body "/healthz says ok" "^ok" "$base/healthz"
check "page /" 200 "$base/"
check "page /data" 200 "$base/data"
for s in name email score role status; do
  check "contacts sort=$s" 200 "$base/contacts?sort=$s&dir=desc"
done
check "write POST /contacts" 200 -X POST --data-urlencode "name=Zelda Smoketest" \
  --data-urlencode "email=zelda@example.com" --data-urlencode "role=Designer" "$base/contacts"
grep_body "search finds the write" "Zelda" "$base/search?q=zelda"
grep_body "api search finds the write" "zelda@example.com" "$base/api/search?q=ZELDA"
grep_body "search folds case per rune" "Zelda" "$base/search?q=SMOKETEST"

# Burst: 16 clients, 400 requests, half of them writes; count the 200s.
export base
export -f one
n200=$(seq 1 400 | xargs -P 16 -I{} bash -c 'one {}' | tr -d '\r' | grep -c '^200$')
if [ "$n200" = 400 ]; then echo "ok   burst: 400/400 answered 200"
else echo "FAIL burst: $n200/400 answered 200"; fails=$((fails + 1)); fi
grep_body "burst writes are searchable" "b400@example.com" "$base/api/search?q=b400@"
check "/healthz after burst" 200 "$base/healthz"

kill "$pid" 2>/dev/null; wait "$pid" 2>/dev/null
echo "smoke: $fails failed"
[ $fails = 0 ]
