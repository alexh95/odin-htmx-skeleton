#!/bin/sh
# The apollo stack, end to end, on this machine (PLAN §20.4; CI's `stack` job): the four
# witnesses from images already built and tagged $IMAGE_PREFIX-<profile>:$TAG, staged in a
# scratch directory beside the Caddyfile and seccomp-io-uring.json as promote.ps1 stages
# them (X21), behind the stack Caddy on 8120. Needs Docker; leaves nothing running.
#
#   IMAGE_PREFIX=local/starter TAG=ci sh deploy/stack-test.sh
set -eu

: "${IMAGE_PREFIX:?the images' prefix, e.g. local/starter}"
: "${TAG:?the images' tag}"
dir=$(mktemp -d)
cp deploy/compose.yaml deploy/Caddyfile docker/seccomp-io-uring.json "$dir/"
{
	echo "IMAGE_PREFIX=$IMAGE_PREFIX"
	for p in MINIMAL STREAMS SKELETON LAB; do echo "TAG_$p=$TAG"; done
} > "$dir/.env"
dc() { docker compose -p starter-stack-test --project-directory "$dir" -f "$dir/compose.yaml" "$@"; }
# The services' logs only when something failed, the stack's start included.
fail=1
trap '[ "$fail" -eq 0 ] || dc logs --tail 20 || true; dc down -v >/dev/null 2>&1 || true; rm -rf "$dir"' EXIT

bad() { echo "FAIL: $*" >&2; fail=1; }
get() { curl -sS -o /dev/null -w '%{http_code}' -H "Host: $1" "http://127.0.0.1:8120$2"; }

dc up -d --wait --wait-timeout 90
fail=0

# Every witness answers on its own host, through the Caddy, with its own version.
for h in starter-minimal starter-streams starter-skeleton odin-htmx-starter; do
	body=$(curl -sS -H "Host: $h.alexh95.com" http://127.0.0.1:8120/healthz) || body=
	[ "$body" = ok ] || bad "$h.alexh95.com/healthz answered '$body'"
	curl -sSI -H "Host: $h.alexh95.com" http://127.0.0.1:8120/ | grep -qi "^x-version: $TAG" || bad "$h: no x-version $TAG"
done

# X23: a request without a known host gets the catch-all's 421.
[ "$(get 127.0.0.1:8120 /)" = 421 ] || bad "a bare address isn't 421"

# The trusted chain (§17.8, X39, X43): this machine reaches the published port from the
# stack network's gateway, which the Caddy trusts for X-Forwarded-For, and the app trusts
# the Caddy's X-Real-IP. So a LAN client named that way gets the nickname form, and an
# unnamed one (the gateway itself, off the LAN) the LAN notice.
lan=$(curl -sS -H 'Host: starter-streams.alexh95.com' -H 'X-Forwarded-For: 192.168.5.5' http://127.0.0.1:8120/login)
off=$(curl -sS -H 'Host: starter-streams.alexh95.com' http://127.0.0.1:8120/login)
echo "$lan" | grep -q 'Chat is open on the LAN' && bad "a LAN client behind the proxies isn't seen as on the LAN"
echo "$off" | grep -q 'Chat is open on the LAN' || bad "the gateway is taken for a LAN client"

# The lab's witness board sees the other three up, each with its version (its first round
# runs at boot; give it a few seconds).
for i in $(seq 1 15); do
	board=$(curl -sS -H 'Host: odin-htmx-starter.alexh95.com' http://127.0.0.1:8120/status/board)
	[ "$(echo "$board" | grep -cE 'id="st-(minimal|streams|skeleton)" class="card status-card status-ok"')" = 3 ] && break
	sleep 1
done
for w in minimal streams skeleton; do
	echo "$board" | grep -q "id=\"st-$w\" class=\"card status-card status-ok\"" || bad "the witness board doesn't see $w up"
done
echo "$board" | grep -q "version $TAG" || bad "the witness board shows no version"

# Hardened as §20.4 says.
for s in starter-minimal starter-streams starter-skeleton starter-lab; do
	id=$(dc ps -q "$s")
	[ "$(docker inspect -f '{{.HostConfig.ReadonlyRootfs}} {{.Config.User}}' "$id")" = "true 10001:10001" ] || bad "$s isn't read-only as 10001"
	docker inspect -f '{{json .HostConfig.SecurityOpt}}' "$id" | grep -q 'seccomp' || bad "$s runs without the seccomp profile"
	[ -z "$(docker inspect -f '{{json .NetworkSettings.Ports}}' "$id" | grep -o HostPort)" ] || bad "$s publishes a port"
done

# A witness restarts without the Caddy's reload: the gap is latency (lb_try_duration).
dc up -d --no-deps --force-recreate starter-lab >/dev/null 2>&1
[ "$(get odin-htmx-starter.alexh95.com /healthz)" = 200 ] || bad "a request during a witness's restart failed"

[ "$fail" -eq 0 ] && echo "stack ok: 4 witnesses behind the Caddy, 421, the trusted chain, the hardening, a restart"
exit "$fail"
