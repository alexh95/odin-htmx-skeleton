# odin-http: where this copy comes from

The starter's HTTP server is a fork of [laytan/odin-http](https://github.com/laytan/odin-http) (MIT, `LICENSE`),
vendored in-tree so that its changes live next to the code that needs them (D11; ANSWERS F3). There is no separate
fork repo: an upstream offer goes through a GitHub fork made at that time from the changes listed below (PLAN §8.1).

- **Base:** `fac113fbd828aad3d71479a534b5de4358b6a07b` (2026-08-26, "openssl: update bundled libraries to
  openssl-3.6.4 (#120)"), the commit the skeleton pinned as its `app/odin-http` submodule. Upstream had no newer
  commit when this was vendored (2026-10-26).
- **What is vendored:** only the `http` package's own files, `LICENSE` and `README.md`. Left out: `client/`,
  `comparisons/`, `docs/`, `examples/`, `old_nbio/`, `openssl/`, `.editorconfig` and `odinfmt.json`. The server path
  uses `core:nbio` and needs no OpenSSL.
- **Odin:** `dev-2026-10` (`84bc3fc`), the toolchain pin of the Dockerfile and CI.

## Local changes

Each change is generic (nothing starter-specific goes in here), keeps upstream's style, and is listed with the files
it touches. The WS codec, the SSE encoder, the multipart writer, Range parsing and the hub stay in the starter's
`platform/stream` and `platform/hub` (PLAN §8.1), so this diff stays small enough to offer upstream.

| # | Change | Files | Status |
|---|---|---|---|
| — | none yet: this is fac113f as published | — | — |

The planned changes are F-1..F-12 (PLAN §8.1). Spike S0.2 (`docs/spikes/S0.2.md`) measures F-1 and F-5..F-12 under
the skeleton's k6 suite before anything builds on them.

## Bumping

1. Copy the new upstream commit's package files over this directory (same list as above), keeping this file.
2. Re-apply the local changes, one commit each, and update the table and the base line above.
3. Re-run the stream contract suite and the parity gate (PLAN §18) before anything ships on the new base.
