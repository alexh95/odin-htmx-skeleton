# Infrastructure — plan

> Status: **code + config implemented.** The deployable change, the odin-http submodule, the
> `Dockerfile`/`fly.toml`/`.dockerignore`, and the CI/CD workflow are all in the repo. What
> remains is operator setup on Fly / GitHub / Cloudflare — see **Operator steps** at the
> bottom. The design rationale below is kept as the reference.

How to host the code, build and test it on every change, and keep a live instance
permanently reachable — at free or near-zero cost. Where e2e and load-tests run is covered at
the end.

## Prerequisite code change (small, do first when implementing)

The server currently binds `net.IP4_Loopback` with the port as `os.args[1]` — fine for local
dev, wrong for a container.

- **Bind address**: listen on `net.IP4_Any` (0.0.0.0) in deployed mode so the platform can
  reach it. Keep loopback as the local default; gate on an env var (e.g. `BIND_ALL=1`) or just
  always bind `IP4_Any` and rely on the platform firewall.
- **Port from env**: read `PORT` (most platforms inject it) and fall back to the arg, then to
  8080. `os.get_env("PORT")`.
- `static/` must sit next to the binary at runtime (the CSS/JS are served from disk; htmx is
  embedded so it isn't needed on disk). The container `WORKDIR` is the app dir.

These are the only changes the app needs to be deployable. Track as a TODO under the infra
item.

## Remote git hosting

**GitHub** — free private/public repos, and the CI/CD below is GitHub Actions, so it's the
path of least resistance. (Codeberg/GitLab/self-hosted Gitea are fine alternatives; nothing
here is GitHub-locked except the Actions YAML.)

**odin-http for reproducible CI.** Today `prepare.*` clones odin-http at *latest*, which is
non-reproducible. For CI/CD, vendor it as a **git submodule pinned to a commit** (or a Go-style
vendored copy). Then CI checks out the exact dependency; `prepare` stays the convenience path
for local dev. This is the one thing to firm up before wiring CI.

## CI — build + test on every push/PR

**GitHub Actions** (free tier: unlimited minutes for public repos; ~2000 min/month private).

Pipeline (`.github/workflows/ci.yml`):
1. Checkout (with submodules, for odin-http).
2. Install Odin — a community action such as `laytan/setup-odin@v2`, or download a release
   tarball and cache it.
3. `prepare` the rest (fetch `htmx.min.js`).
4. `odin build app -out:app/bin/demo` — **fail on any warning**.
5. Run e2e (see below).

Cache the Odin toolchain and the htmx download between runs.

## CD — deploy a permanent instance

The artifact is a single self-contained binary plus `static/`. Containerize it:

```dockerfile
# builder: get Odin, build for linux_amd64
FROM debian:bookworm-slim AS build
RUN apt-get update && apt-get install -y clang git curl xz-utils
# install Odin release into /opt/odin, add to PATH
COPY . /src
WORKDIR /src/app
RUN ./prepare.sh && odin build . -out:bin/demo -o:speed

# runtime: slim image with just the binary + static assets
FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /src/app/bin/demo /app/demo
COPY --from=build /src/app/static   /app/static
ENV PORT=8080
EXPOSE 8080
CMD ["/app/demo"]
```

Host options, cheapest-first:

| Option | Cost | Always-on? | Notes |
|--------|------|-----------|-------|
| **Oracle Cloud Always Free** (ARM Ampere VM) | $0 | Yes | Genuinely free always-on VM; most ops overhead (you manage the box, TLS via Caddy). Best $0 path. |
| **Fly.io** | free allowance / ~$2–5 | Yes | Deploy the Dockerfile globally, free TLS + subdomain, `flyctl deploy`. Simplest always-on. **Recommended.** |
| **Render** free web service | $0 | No | Spins down on idle → cold starts. Not truly "permanently accessible"; fine for a demo if cold starts are OK. |
| **Hetzner / small VPS** | ~€4/mo | Yes | Cheap, reliable, full control; not free. |

**Recommended path:** Fly.io for simplicity (Dockerfile + `fly.toml`, auto HTTPS), with Oracle
Always Free as the $0 alternative if zero cost outranks convenience. Put **Cloudflare** (free)
in front for DNS, caching of `/static`, and TLS if the platform doesn't provide it.

**Deploy trigger:** on push to `main` after CI is green, a deploy job runs `flyctl deploy`
using a `FLY_API_TOKEN` repo secret. Optionally tag-based releases later.

## Where e2e runs

- **Per PR / push, in CI**: the Actions runner builds the binary, launches it on a local port
  (fresh in-memory store = clean fixture), and runs Playwright against `localhost`. Free,
  ephemeral, gates merges. This is the primary home for e2e.
- **Optional synthetic smoke**: a scheduled job runs a thin subset against the deployed URL to
  catch environment/deploy breakage (not full coverage).

## Where load-tests run

Shared CI runners have noisy neighbours and shared CPU — fine for *relative* regression
detection, useless for *absolute* throughput. So:

- **Absolute numbers**: run against a **dedicated environment** — the Oracle Always Free VM, or
  a Fly machine sized for the test — on a schedule or manual trigger. Generator and target on
  separate hosts over a real link (see `load-tests/PLAN.md`). **k6 Cloud** has a small free
  tier if you'd rather not manage a generator box.
- **Relative regression in CI** (optional): a short, loosely-gated bombardier run to catch
  order-of-magnitude regressions, never treated as a true benchmark.
- Do **not** gate PRs on absolute throughput from shared runners.

This is also where the single-thread-ceiling investigation (`load-tests/PLAN.md`) lives: the
dedicated env is what makes "raise `thread_count`, add the store lock, re-measure" meaningful.

## Cost summary

GitHub (free) · Actions (free tier) · Fly.io free allowance **or** Oracle Always Free ($0) ·
Cloudflare (free). Realistic total: **$0–5 / month.**

## What's implemented

1. ✅ Bind-address / `PORT` change in `app/main.odin` (`BIND_ALL=1` → `0.0.0.0`).
2. ✅ odin-http pinned as a submodule (`app/odin-http` @ `112c49b`).
3. ✅ `Dockerfile` (two-stage, pinned Odin `dev-2026-06`) + `.dockerignore` + `fly.toml`.
4. ✅ `.github/workflows/ci.yml`: build (`-warnings-as-errors`) + binary smoke test, then a
   `deploy` job that runs `flyctl deploy --remote-only` on a green push to `master`.
5. ⏳ Dedicated load-test environment — deferred until load-tests are implemented.

The CI smoke step stands in for e2e until the Playwright suite exists; swap it in then.

## Operator steps

These touch external accounts, not the repo. Run from the repo root with `flyctl` logged in.
The remote is `git@github.com:alexh95/odin-htmx-skeleton.git`; the default branch is `master`.

**1. Create the Fly app** (once). The name must match `app` in `fly.toml`:

```sh
fly apps create odin-htmx-skeleton        # or: fly launch --no-deploy --copy-config
fly deploy                                 # first deploy from your machine, to verify
```

`fly deploy` builds the `Dockerfile` on Fly's remote builder and boots one always-on
`shared-cpu-1x` machine. Confirm: `fly open` (the `.fly.dev` URL) and `fly logs` (look for
`listening on http://0.0.0.0:8080`).

**2. Wire CI/CD deploys.** Two mutually exclusive options — pick one:

- **GitHub Actions (recommended, already in `ci.yml`):** the `deploy` job is dormant until you
  opt in. Add the token secret and flip the enable variable:
  ```sh
  fly tokens create deploy -x 999999h                              # prints a token
  gh secret set FLY_API_TOKEN --repo alexh95/odin-htmx-skeleton    # paste it
  gh variable set FLY_DEPLOY --body true --repo alexh95/odin-htmx-skeleton
  ```
  After that, every push to `master` builds, smoke-tests, and deploys. (Leave `FLY_DEPLOY`
  unset and the deploy job stays skipped — CI still gates PRs via the `build` job.)
- **Fly's GitHub integration (already authorized):** if you'd rather Fly auto-deploy on push
  from its dashboard, **delete the `deploy` job from `ci.yml`** so the two don't double-deploy.
  Keep the `build` job as the PR gate.

**3. Put Cloudflare in front** (needs a domain on your Cloudflare account):

```sh
fly ips allocate-v4 --shared       # or a dedicated v4 if you want; v6 is free
fly ips allocate-v6
fly certs add app.example.com      # Fly prints the DNS target + validation record
```

In Cloudflare DNS, add the records Fly prints (an `AAAA`/`A` to the Fly IPs, or a `CNAME` to
`odin-htmx-skeleton.fly.dev`). Set SSL/TLS mode to **Full (strict)** so Cloudflare↔Fly stays
encrypted end-to-end. Proxy (orange cloud) the record to get Cloudflare caching for `/static`
and DDoS protection; `force_https` in `fly.toml` handles the redirect. Once `fly certs show
app.example.com` reports the cert issued, the custom domain is live.

**Cost:** one always-on `shared-cpu-1x`/256 MB machine sits in Fly's small-fry allowance;
Cloudflare DNS/proxy is free. Realistic total **$0–5/mo** (set `min_machines_running = 0` in
`fly.toml` to scale to zero and trade a brief cold start for $0).
