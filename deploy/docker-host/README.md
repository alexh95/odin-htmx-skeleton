# Deploy: any Docker host over SSH

Runs the app on a Linux machine you control (a home server, a VPS) with Docker, and a SQLite
database that **persists** in a named volume. It's the self-hosted counterpart to the Fly setup in
[`../../infra/PLAN.md`](../../infra/PLAN.md). It's also how to get the **generator and target on
separate machines** for the two-host load tests ([`../../load-tests/PLAN.md`](../../load-tests/PLAN.md)):
your workstation runs k6, the host runs the server.

## How it works

The repo `Dockerfile` is self-contained (fetches a pinned Odin + htmx + SQLite, compiles and links
a single static binary), so we **build on the host**: no registry, and no Docker needed on the
machine you deploy from. [`deploy.sh`](deploy.sh) tars the build context (`Dockerfile` + `app/`)
over SSH into `$REMOTE_DIR/src`, pushes [`compose.yaml`](compose.yaml) and an `.env` with your
settings, and runs `docker compose up -d --build`.

```
workstation                         host
  deploy.sh ── tar over ssh ──▶  $REMOTE_DIR/            (default /srv/$NAME)
                                   ├─ compose.yaml, compose.proxy.yaml, .env
                                   └─ src/{Dockerfile,.dockerignore,app/}
                                          │ docker compose up -d --build
                                          ▼
                                   $NAME container
                                     :$HOST_PORT on the host (default 8090)
                                     $NAME:8080 on $PROXY_NET, if set
                                     /data ← volume $VOLUME (data.db)
```

## Requirements

- Linux with Docker and the compose plugin. The SSH user must be in the `docker` group; that's all
  the access the deploy needs (it writes files through a throwaway container, so no `sudo`).
- **io_uring.** The server's event loop (odin-http on `core:nbio`) uses io_uring on Linux. Docker's
  default seccomp profile blocks it. `deploy.sh` ships the repo's `docker/seccomp-io-uring.json`
  (Docker's default profile plus the three io_uring syscalls) and runs the container under it; if
  that file is missing it falls back to `seccomp=unconfined`. The host kernel must allow io_uring
  too: see [`../../infra/PLAN.md`](../../infra/PLAN.md) → *io_uring platform requirement*.

## Deploy

```sh
cd deploy/docker-host
HOST=myserver ./deploy.sh
```

`HOST` is an SSH destination (an alias from `~/.ssh/config`, or `user@host`). Everything else has a
default:

| Env | Default | Meaning |
|---|---|---|
| `NAME` | `odin-htmx-skeleton` | container, image and compose project name |
| `REMOTE_DIR` | `/srv/$NAME` | where the build context and compose files live on the host |
| `HOST_PORT` | `8090` | port published on the host |
| `VOLUME` | `$NAME-data` | named volume holding the database |
| `PROXY_NET` | (none) | existing docker network to join, for a reverse proxy |

The first run builds the image (pulls Odin + clang, fetches + compiles SQLite, about 2–4 min); later
runs are cached and fast. On success it health-checks `http://localhost:$HOST_PORT/healthz` on the
host and prints the URL.

## Data

`DB_PATH=/data/data.db` on the `$VOLUME` volume, so the database survives redeploys and restarts;
migrations apply in order on boot. To adopt a volume that already holds a database, set `VOLUME` to
its exact name (`docker volume ls`). Set `DB_PATH=:memory:` in `compose.yaml` for an ephemeral,
freshly-seeded store instead. [`../../docs/DATA.md`](../../docs/DATA.md) covers where the data layer
goes from here.

**Backups.** It's a live file (WAL mode), so copy it with the app stopped. `compose.yaml` stops it
with SIGINT, the signal it shuts down cleanly on, which folds the WAL back into `data.db`. On the
host, from `$REMOTE_DIR` (the volume is your `VOLUME`, if you set one), at the cost of a few seconds
of downtime:

```sh
docker compose stop
docker run --rm -v odin-htmx-skeleton-data:/data -v "$PWD":/out busybox sh -c 'cp /data/data.db* /out/'
docker compose start
```

**Volume ownership.** When the image runs as a non-root user (the Dockerfile's `USER`, UID 10001),
a new volume starts out owned by that user. A volume that an earlier, root-run image wrote needs a
one-time chown before the new image can open the database. Run it on the host, with the container
stopped, before deploying the new image:

```sh
docker run --rm -v odin-htmx-skeleton-data:/data debian:trixie-slim chown -R 10001:10001 /data
```

## Behind a reverse proxy

Set `PROXY_NET` to the docker network your proxy (nginx-proxy-manager, Caddy, Traefik) is on.
`compose.proxy.yaml` then joins the container to it, and the proxy forwards to **`$NAME:8080`** by
container name. With nginx-proxy-manager, for example: *Hosts → Proxy Hosts → Add*, scheme `http`,
forward host `$NAME`, port `8080`, and request a Let's Encrypt cert on the SSL tab. If this host
serves the public site, set `SITE_URL` in `compose.yaml` to its origin.

## Two-host load test

Once it's up, point the suite at the host from your workstation, with generator and target on
separate machines:

```sh
cd load-tests
./run.sh --base http://<server-ip>:8090          # direct, proxy-free (cleanest signal)
./run.sh --base https://app.example.com          # through the proxy + TLS (the full path)
```

Direct isolates the server; the proxied URL adds the proxy and TLS, which measures their overhead.
Compare against the loopback numbers in [`../../load-tests/RESULTS.md`](../../load-tests/RESULTS.md).
For a thread-count before/after on the host, set `THREADS=1` in `compose.yaml`, deploy, sweep; then
remove it (one thread per core), deploy, sweep.
