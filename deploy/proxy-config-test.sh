#!/bin/sh
# The proxies' configuration on its own (PLAN §20.1's proxy-config, X26; CI's job of that
# name): `caddy validate` on deploy/Caddyfile and on every Caddyfile snippet in the
# committed docs, `nginx -t` on NPM's rendering with §20.4's Advanced snippet
# (tests/proxy/npm.conf), every redirect alias bare and deep (D25), the 301 alias, the
# catch-all's 421 (X23) and compose's 8120:80 publish. Needs Docker; no app runs: the
# redirects and the 421 are the Caddy's own answers.
set -eu

CADDY=caddy@sha256:eb4d35b7452d1ab6171fbdbe8d9275b2301dad6dad92115d91e19fb9b24d510f
NGINX=nginx@sha256:5616878291a2eed594aee8db4dade5878cf7edcb475e59193904b198d9b830de
PORT=${PROXY_TEST_PORT:-8121}
fail=0
bad() { echo "FAIL: $*" >&2; fail=1; }
dir=$(mktemp -d)
trap 'docker rm -f proxy-config-caddy >/dev/null 2>&1 || true; rm -rf "$dir"' EXIT

validate() { # $1: a Caddyfile on disk
	docker run --rm -v "$1:/etc/caddy/Caddyfile:ro" "$CADDY" caddy validate --config /etc/caddy/Caddyfile --adapter caddyfile >/dev/null 2>"$dir/err" \
		|| { bad "caddy validate $2: $(tail -1 "$dir/err")"; }
}

validate "$PWD/deploy/Caddyfile" deploy/Caddyfile

# The docs' snippets, their placeholders filled: <NPM_UPSTREAM_ADDR> with the gateway
# compose pins, any other <NAME> with a loopback address.
n=0
for doc in $(git ls-files 'docs/*.md' 'docs/**/*.md' '*.md'); do
	awk -v out="$dir/snip" -v doc="$doc" '
		/^[ \t]*```caddyfile[ \t]*$/ { on = 1; k++; f = out "-" k; print doc > (f ".src"); next }
		on && /^[ \t]*```[ \t]*$/ { on = 0; close(f); next }
		on { sub(/^  /, ""); print > f }' "$doc"
	for f in "$dir"/snip-*; do
		case $f in *.src) continue ;; esac
		[ -f "$f" ] || continue
		sed -e 's#<NPM_UPSTREAM_ADDR>#172.31.120.1/32#g' -e 's#<[A-Z_][A-Z_]*>#127.0.0.1#g' "$f" > "$dir/Caddyfile"
		validate "$dir/Caddyfile" "the snippet in $(cat "$f.src")"
		n=$((n + 1)); rm -f "$f" "$f.src"
	done
done
echo "validated deploy/Caddyfile and $n doc snippet(s)"

# NPM's nginx: its http block and the proxy host it renders, Advanced snippet included.
docker run --rm -v "$PWD/tests/proxy/npm.conf:/etc/nginx/npm.conf:ro" --add-host starter-full:127.0.0.1 "$NGINX" \
	nginx -t -c /etc/nginx/npm.conf >/dev/null 2>"$dir/err" || bad "nginx -t: $(tail -1 "$dir/err")"
grep -q 'proxy_read_timeout 1h;' tests/proxy/npm.conf || bad "npm.conf lacks §20.4's Advanced snippet"

# The Caddy's own answers, with no app behind it.
docker run -d --name proxy-config-caddy -p "$PORT:80" -v "$PWD/deploy/Caddyfile:/etc/caddy/Caddyfile:ro" "$CADDY" >/dev/null
for i in $(seq 1 30); do curl -s -o /dev/null "http://127.0.0.1:$PORT/" && break; sleep 0.2; done
answer() { curl -s -o /dev/null -w '%{http_code} %{redirect_url}' -H "Host: $1" "http://127.0.0.1:$PORT$2"; }
expect() { got=$(answer "$1" "$2"); [ "$got" = "$3" ] || bad "$1$2 answered '$got', not '$3'"; }

for pair in full=https://houston.alexh95.com minimal=https://starter-minimal.alexh95.com \
	streams=https://starter-streams.alexh95.com skeleton=https://odin-htmx.alexh95.com; do
	p=${pair%%=*}; to=${pair#*=}
	expect odin-htmx-starter.alexh95.com "/$p" "302 $to/"
	expect odin-htmx-starter.alexh95.com "/$p/a/b?c=1" "302 $to/a/b?c=1"
done
expect htmx-odin-starter.alexh95.com "/x/y?z=1" "301 https://odin-htmx-starter.alexh95.com/x/y?z=1"
expect 192.168.1.2 / "421 "

# compose publishes the Caddy's :80 on 8120, and nothing else publishes a port.
pub=$(grep -c '^      - "8120:80"$' deploy/compose.yaml || true)
[ "$pub" = 1 ] || bad "deploy/compose.yaml doesn't publish 8120:80 exactly once"
[ "$(grep -c '^    ports:' deploy/compose.yaml)" = 1 ] || bad "a service besides the Caddy publishes a port"

[ "$fail" -eq 0 ] && echo "proxy config ok: validate, nginx -t, 8 aliases, the 301, the 421, the publish"
exit "$fail"
