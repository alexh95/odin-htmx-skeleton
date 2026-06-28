# syntax=docker/dockerfile:1
#
# Two stages: build the self-contained binary, then ship it with the on-disk
# static assets on a slim glibc base. The runtime image carries no toolchain.

# ---- build: fetch a pinned Odin, build for linux/amd64 -------------------
FROM debian:bookworm-slim AS build

# Pin the toolchain so image builds are reproducible. Bump deliberately.
ARG ODIN_VERSION=dev-2026-06

# clang is the linker driver and also compiles the SQLite amalgamation (prepare.sh);
# unzip extracts it and binutils (ar) archives it into sqlite3.a. The Odin release
# statically bundles LLVM.
RUN apt-get update \
 && apt-get install -y --no-install-recommends clang binutils unzip git curl ca-certificates tar \
 && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL "https://github.com/odin-lang/Odin/releases/download/${ODIN_VERSION}/odin-linux-amd64-${ODIN_VERSION}.tar.gz" -o /tmp/odin.tar.gz \
 && mkdir -p /opt/odin \
 && tar -xzf /tmp/odin.tar.gz -C /opt/odin --strip-components=1 \
 && rm /tmp/odin.tar.gz
ENV PATH="/opt/odin:${PATH}"

# Only the app dir is needed to build. odin-http rides in via its submodule
# (already in the build context), so prepare just fetches htmx for #load.
COPY app /src/app
WORKDIR /src/app
# Invoke via `sh` (not ./) so the build doesn't depend on the exec bit, which a
# Windows-origin build context (e.g. local `flyctl deploy`) wouldn't carry.
RUN sh prepare.sh \
 && odin build src -out:bin/demo -o:speed -warnings-as-errors

# ---- runtime: just the binary (all assets are embedded) ------------------
FROM debian:bookworm-slim
WORKDIR /app
COPY --from=build /src/app/bin/demo /app/demo

# Bind 0.0.0.0 so the platform can route in; PORT is the platform's contract.
ENV PORT=8080 BIND_ALL=1
EXPOSE 8080
CMD ["/app/demo"]
