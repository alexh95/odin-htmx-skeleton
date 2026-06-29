# Deploy: apollo-11 (home server)

Deploys odin-htmx to the `apollo-11` Ubuntu/Docker box so load tests can run with the **generator
and target on separate machines** — the two-host setup the load-test plan calls for
([`../../load-tests/PLAN.md`](../../load-tests/PLAN.md)). The workstation runs k6; apollo-11 runs
the server.

## How it works

The repo `Dockerfile` is self-contained (fetches a pinned Odin + htmx + SQLite, compiles and links
a single static binary), so we **build on the server** — no registry, and no Docker needed on
Windows.
[`deploy.sh`](deploy.sh) tars the build context (`Dockerfile` + `app/`) over SSH, drops it in
`/mnt/fast-storage/odin-htmx/src`, pushes [`docker-compose.yml`](docker-compose.yml), and runs
`docker compose up -d --build`. Matches the other services on the box: a folder under
`/mnt/fast-storage`, joined to the shared `npm` network.

```
workstation                         apollo-11 (<server-lan-ip>, 4 threads)
  deploy.sh ── tar over ssh ──▶  /mnt/fast-storage/odin-htmx/
                                   ├─ docker-compose.yml
                                   └─ src/{Dockerfile,.dockerignore,app/}
                                          │ docker compose up -d --build
                                          ▼
                                   odin-htmx container
                                     :8090 on host (direct, proxy-free)
                                     odin-htmx:8080 on `npm` net (via NPM)
```

## One-time setup

Just create the service dir (root-owned is fine, like the box's other services):

```sh
ssh apollo-11_local 'sudo mkdir -p /mnt/fast-storage/odin-htmx'
```

That's the only sudo. The deploy itself is sudo-free: the SSH login user is in the `docker` group,
so `deploy.sh` places the build context into the root-owned dir via a throwaway root container and
makes it world-readable — see the header comment in [`deploy.sh`](deploy.sh).

## Deploy

```sh
cd deploy/apollo-11
./deploy.sh
```

First run builds the image (pulls Odin + clang, fetches + compiles SQLite, ~2–4 min); later runs
are cached and fast. On success it health-checks `http://localhost:8090/healthz` on the server and
prints the LAN URL.

The SQLite DB **persists**: the compose mounts a named volume (`odin-htmx-data`) at `/data` with
`DB_PATH=/data/data.db`, so data survives redeploys and restarts (migrations apply in order on
boot). Set `DB_PATH=:memory:` in `docker-compose.yml` for an ephemeral, freshly-seeded store
instead.

## Reverse proxy (nginx-proxy-manager)

The container is on the `npm` network, so NPM reaches it by name. In the NPM web UI (`:81`) →
**Hosts → Proxy Hosts → Add Proxy Host**:

- **Domain Names:** your chosen subdomain (e.g. `odin.example.com`)
- **Scheme:** `http`
- **Forward Hostname / IP:** `odin-htmx`
- **Forward Port:** `8080`
- **Block Common Exploits:** on; **Websockets Support:** on (harmless)
- **SSL tab:** request a Let's Encrypt cert, Force SSL on

DNS for the subdomain must point at the box's public IP (and the router must forward 80/443 to it),
same as the other proxied services.

## Two-host load test

Once it's up, point the suite at the server from the workstation — generator and target now on
separate hosts over the LAN, which is the whole point:

```sh
cd load-tests
./run.sh --base http://<server-lan-ip>:8090          # direct, proxy-free (cleanest signal)
./run.sh --base https://odin.example.com             # through NPM + TLS (full real path)
```

Direct (`:8090`) isolates the server; the subdomain adds the proxy + TLS, useful to measure that
overhead. Compare against the loopback numbers in
[`../../load-tests/RESULTS.md`](../../load-tests/RESULTS.md) — this run has a real network hop and a
4-core box, so it's the first set of numbers where latency isn't loopback-fictional.

## On-server before/after

apollo-11 has 4 cores, so you can rerun the thread-count experiment natively: edit
`docker-compose.yml` to set `THREADS=1`, `./deploy.sh`, sweep; then `THREADS=4`, redeploy, sweep.
