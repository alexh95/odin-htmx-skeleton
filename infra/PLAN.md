# Infrastructure — plan

> Status: **implemented.** The `Dockerfile`, `fly.toml`, `.dockerignore`, the CI/CD workflow and a
> self-host example ([`deploy/docker-host`](../deploy/docker-host)) are all in the repo. What a new
> deployment still needs is operator setup on Fly / GitHub / Cloudflare: see **Operator steps** at
> the bottom. The rationale above them is kept as the reference.

How to host the code, build and test it on every change, and keep a live instance permanently
reachable, at free or near-zero cost.

## What's in the repo

- **The app is container-ready.** `PORT` (the platform's contract) overrides the port argument, and
  `BIND_ALL=1` switches the listen address from loopback to `0.0.0.0`. Every static asset is
  embedded into the binary (`#load`), so the artifact is **one file**: nothing sits next to it at
  runtime.
- **Reproducible dependencies.** odin-http is a git submodule pinned to a commit (`app/odin-http`).
  `prepare.*` fetches htmx and the SQLite amalgamation by pinned version + SHA-256 and compiles
  SQLite. The Odin release is pinned in the `Dockerfile` (`ARG ODIN_VERSION`) and in `ci.yml`
  (`env.ODIN_VERSION` + the three matrix asset names); bump them together.
- **`Dockerfile`**: two stages on the same Debian release (glibc must match). The build stage
  installs the pinned Odin + clang, runs `prepare.sh` and builds `-o:speed -warnings-as-errors`; the
  runtime stage is a slim base with just the binary.
- **`fly.toml`**: one always-on `shared-cpu-1x` machine, `/healthz` health check, `:memory:` SQLite
  until you add a volume (below).
- **`.github/workflows/ci.yml`**:
  1. `build`: build `-warnings-as-errors` + a curl smoke test on Linux, macOS (arm64) and Windows.
  2. `e2e`: the Playwright suite, one job per engine (Chromium, Firefox, WebKit), in Playwright's
     container image.
  3. `minimal` (template only): runs `tools/init --minimal` and the starter's e2e, so the starter
     templates can't rot. `init` deletes this job from a fork's copy, because a fork deletes
     `tools/init`.
  4. `deploy`: `flyctl deploy --remote-only` on a green push to `master`, once you opt in (step 2).
- **`deploy/docker-host`**: the same image on any Linux box with Docker, over SSH, with the SQLite
  database on a named volume. See its README.

## Hosting options

| Option | Cost | Always-on? | Notes |
|--------|------|-----------|-------|
| **Fly.io** | free allowance / ~$2–5 | Yes | Deploys the Dockerfile, free TLS + subdomain, `flyctl deploy`. Simplest always-on. **Recommended.** |
| **Any VPS or home server** with Docker | ~€4/mo, or $0 on hardware you have | Yes | [`deploy/docker-host`](../deploy/docker-host). Full control; you run the box and its TLS. |
| **Oracle Cloud Always Free** (ARM VM) | $0 | Yes | A free always-on VM; the docker-host setup applies (build for arm64). Most ops overhead. |
| **Render** free web service | $0 | No | Spins down on idle, so cold starts. Check io_uring support (below) first. |

**Recommended path:** Fly.io, with **Cloudflare** (free) in front for DNS, caching of `/static` and
TLS. See [`../docs/DATA.md`](../docs/DATA.md) for when the data layer outgrows one SQLite file.

## io_uring platform requirement

The server's event loop (odin-http on Odin's `core:nbio`) uses **io_uring on Linux**. Where io_uring
is unavailable the server aborts at startup (an `acquire_thread_event_loop` assertion), and the
platform reports a crash loop rather than a clear error. Check before choosing a host:

- **The kernel** must have io_uring enabled. Any current distribution kernel does, unless a
  hardening policy turns it off (`sysctl kernel.io_uring_disabled`: `0` allows it).
- **Containers**: Docker's default seccomp profile blocks the `io_uring_*` syscalls. Run under
  `docker/seccomp-io-uring.json`, Docker's default profile plus `io_uring_setup`, `io_uring_enter`
  and `io_uring_register` (`--security-opt seccomp=docker/seccomp-io-uring.json`; `compose.yaml` and
  `deploy/docker-host` use it), or as a blunt fallback with `seccomp=unconfined`. Other runtimes'
  default profiles (containerd under Kubernetes, for example) may block them too.
- **Sandboxed platforms** that reimplement syscalls (gVisor-based ones, for example) may not
  implement io_uring.
- **Fly.io** runs each machine as a Firecracker microVM with its own kernel, so it works as is.

macOS (kqueue) and Windows (IOCP) use other backends and aren't affected.

## Persistence on Fly

`fly.toml` leaves `DB_PATH` unset, so the store is SQLite `:memory:`: every deploy or restart starts
from the seed. To keep data, put the database on a Fly volume (the commented `[mounts]` block and
`DB_PATH` line in `fly.toml`). What that implies:

- **A volume belongs to one machine on one host.** It doesn't follow the app to another region or
  host, and Fly doesn't replicate it. Fly keeps a few days of daily snapshots
  (`fly volumes snapshots list <volume-id>`); for anything longer, copy the file off.
  [`../docs/DATA.md`](../docs/DATA.md) covers the paths beyond one file.
- **Don't scale out.** `fly scale count 2` gives the second machine its own, empty volume: two
  independent databases behind one hostname, each request landing on either. One SQLite file means
  one machine.
- **A deploy restarts that one machine**, so expect a few seconds of downtime per deploy. Fly can't
  overlap two machines on one volume.
- Create the volume **before** uncommenting `[mounts]`: a mount that names a missing volume fails
  the deploy.
- **Ownership.** Fly mounts a volume owned by root. If the image runs as a non-root user (the
  Dockerfile's `USER`, UID 10001), deploy once with `[mounts]` but `DB_PATH` still unset (the app
  stays on `:memory:` and boots), run `fly ssh console -C "chown -R 10001:10001 /data"`, then set
  `DB_PATH` and deploy again. A volume an earlier root-run image wrote needs the same chown.

## Where e2e runs

- **Per PR / push, in CI**: each engine's job builds the binary, launches it on local ports (a fresh
  `:memory:` store per worker, a clean fixture), and runs Playwright against `localhost`. It's free
  and ephemeral. Gating merges on it needs branch protection with required checks (a repo setting).
- **Optional synthetic smoke**: a scheduled job running a thin subset against the deployed URL would
  catch deploy breakage; not set up.

## Where load-tests run

Shared CI runners have noisy neighbours and shared CPU: fine for *relative* regression detection,
useless for *absolute* throughput. So the load suite runs locally (`load-tests/run.sh`; `--strict`
exits non-zero on breached thresholds) and against a dedicated host for absolute numbers, with the
generator and target on separate machines (`./run.sh --base http://<host>:8090` against
`deploy/docker-host`; see `load-tests/PLAN.md`). Do **not** gate PRs on absolute throughput from
shared runners.

## Cost summary

GitHub (free) · Actions (free tier) · Fly.io free allowance **or** a box you already have ·
Cloudflare (free). Realistic total: **$0–5 / month.**

## Operator steps

These touch external accounts, not the repo. Run them from the repo root with `flyctl` and `gh`
logged in; `gh` targets the repo of the current checkout. The deploy job runs on pushes to `master`.

**1. Create the Fly app** (once). The name must match `app` in `fly.toml`, which `tools/init` set:

```sh
fly apps create odin-htmx-skeleton        # or: fly launch --no-deploy --copy-config
fly deploy                                 # first deploy from your machine, to verify
```

`fly deploy` builds the `Dockerfile` on Fly's remote builder and boots one always-on
`shared-cpu-1x` machine. Confirm with `fly open` (the `.fly.dev` URL) and `fly logs` (look for
`listening on http://0.0.0.0:8080`).

Set **`SITE_URL`** (the `[env]` hint in `fly.toml`, or `SITE_URL` in `app/src/views/brand.odin`)
to the origin that will serve the site. It feeds the canonical tags and the sitemap, and the app
redirects `*.fly.dev` requests to it (see `canonical_host` in `app/src/main.odin` for when).

**2. Wire CI/CD deploys.** Two mutually exclusive options; pick one:

- **GitHub Actions (recommended, already in `ci.yml`):** the `deploy` job stays dormant until you
  opt in. Create a deploy token scoped to this app, store it as a secret, and flip the variable:
  ```sh
  fly tokens create deploy -x 2160h                 # 90 days; prints the token
  gh secret set FLY_API_TOKEN                       # paste it
  gh variable set FLY_DEPLOY --body true
  ```
  After that, every push to `master` builds, tests and deploys. The token expires on purpose: rotate
  it by running the first two lines again before then. (Leave `FLY_DEPLOY` unset and the deploy job
  stays skipped; CI still runs on every PR.)
- **Fly's GitHub integration:** if you'd rather Fly auto-deploy on push from its dashboard, **delete
  the `deploy` job from `ci.yml`** so the two don't double-deploy.

**3. Put Cloudflare in front** (needs a domain on your Cloudflare account):

```sh
fly ips allocate-v4 --shared       # or a dedicated v4 if you want; v6 is free
fly ips allocate-v6
fly certs add app.example.com      # Fly prints the DNS target + validation record
```

In Cloudflare DNS, add the records Fly prints (an `AAAA`/`A` to the Fly IPs, or a `CNAME` to
`odin-htmx-skeleton.fly.dev`). Set SSL/TLS mode to **Full (strict)** so Cloudflare↔Fly stays
encrypted end-to-end. Proxy (orange cloud) the record to get Cloudflare caching for `/static` and
DDoS protection; `force_https` in `fly.toml` handles the redirect. Once `fly certs show
app.example.com` reports the cert issued, the custom domain is live; point `SITE_URL` at it.

**Rollback:** `fly releases --image` lists past releases with their images; `fly deploy --image
<a good release's image>` puts one back.

**Cost:** one always-on `shared-cpu-1x`/256 MB machine sits in Fly's small-fry allowance; Cloudflare
DNS/proxy is free. Realistic total **$0–5/mo** (set `min_machines_running = 0` in `fly.toml` to
scale to zero and trade a brief cold start for $0).
