# syntax=docker/dockerfile:1
#
# Two stages: build the self-contained binary, then ship it alone on a slim glibc
# base. Every static asset is embedded in it, so the runtime image carries no
# toolchain and no asset files.
#
# Running it needs Linux io_uring, which Docker's default seccomp profile blocks
# (since 25.0): start it with docker/seccomp-io-uring.json, as compose.yaml does,
# or the server aborts at startup. containerd's default (since 2.0) blocks it too,
# so on Kubernetes RuntimeDefault isn't enough: load the same profile (Localhost).

# ---- build: fetch a pinned Odin, build for linux/amd64 -------------------
# Debian 13 (trixie). Bookworm's regular security support ended 2026-07-12 (LTS
# only from there). Both stages must stay on the same release so the glibc the
# binary links against is the glibc it runs on.
FROM debian:trixie-slim AS build

# Pin the toolchain so image builds are reproducible. Bump deliberately: the
# SHA-256 is the release's published digest of the linux-amd64 tarball, the same
# one ci.yml pins (.github/scripts/check-pins.sh fails CI if they drift apart).
ARG ODIN_VERSION=dev-2026-10
ARG ODIN_SHA256=c3c8b095621fd0c75f7f73e3a0829f1b4d45324225f20ba11ed8dc4da310a8ab

# clang is the linker driver and also compiles the SQLite amalgamation (prepare.sh);
# unzip extracts it and binutils (ar) archives it into sqlite3.a. The Odin release
# statically bundles LLVM.
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang binutils unzip git curl ca-certificates tar \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/odin-linux-amd64-${ODIN_VERSION}.tar.gz" -o /tmp/odin.tar.gz \
 && echo "${ODIN_SHA256}  /tmp/odin.tar.gz" | sha256sum -c - \
 && mkdir -p /opt/odin \
 && tar -xzf /tmp/odin.tar.gz -C /opt/odin --strip-components=1 \
 && rm /tmp/odin.tar.gz
ENV PATH="/opt/odin:${PATH}"

# Only the app dir is needed to build. odin-http rides in via its submodule
# (already in the build context), so prepare only fetches htmx and SQLite (both
# pinned by SHA-256) and compiles SQLite.
COPY app /src/app
WORKDIR /src/app
# Invoke via `sh` (not ./) so the build doesn't depend on the exec bit, which a
# Windows-origin build context (e.g. local `flyctl deploy`) wouldn't carry.
RUN sh prepare.sh \
 && odin build src -out:bin/demo -o:speed -warnings-as-errors

# ---- runtime: just the binary (all assets are embedded) ------------------
# Must match the build stage's Debian release (glibc compatibility).
FROM debian:trixie-slim

# Run unprivileged, as a fixed UID so a volume can be chowned to it from outside.
# /data is where DB_PATH points to persist (DB_PATH=/data/data.db) and the one
# directory it can write; a fresh named volume mounted there inherits that owner.
# A volume that already holds root-owned files, or that the platform mounts as
# root (a Fly volume), needs a one-time `chown -R 10001:10001` first.
RUN useradd --uid 10001 --user-group --no-create-home --shell /usr/sbin/nologin app \
 && mkdir /data && chown app:app /data

WORKDIR /app
COPY --from=build /src/app/bin/demo /app/demo
# Numeric, so Kubernetes' runAsNonRoot can check it without reading /etc/passwd.
USER 10001:10001

# Bind 0.0.0.0 so the platform can route in; PORT is the platform's contract.
ENV PORT=8080 BIND_ALL=1
EXPOSE 8080

# odin-http shuts down cleanly on SIGINT (and repo_close then checkpoints SQLite).
# Without this, `docker stop` sends SIGTERM, which the binary has no handler for,
# and as PID 1 an unhandled signal is ignored: Docker waits 10 s, then SIGKILLs.
STOPSIGNAL SIGINT

# Probes /healthz with bash's /dev/tcp, because the slim base has no curl or wget
# and one probe isn't worth adding a package. Fly ignores this (fly.toml has its
# own check); Docker and compose use it.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --start-interval=1s \
  CMD ["bash", "-c", "exec 3<>/dev/tcp/127.0.0.1/${PORT:-8080} && printf 'GET /healthz HTTP/1.1\\r\\nHost: localhost\\r\\nConnection: close\\r\\n\\r\\n' >&3 && head -n1 <&3 | grep -q ' 200 '"]

CMD ["/app/demo"]
