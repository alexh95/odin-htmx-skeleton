# 1. Use Bun for JavaScript/TypeScript tooling

- Status: **Accepted**
- Date: 2026-06-26

## Context

The product is pure Odin + HTMX with **no JavaScript build step** — HTMX is the only
front-end library and it's embedded into the binary. We hold that line deliberately (see
`CLAUDE.md` → "Dependencies").

But the e2e suite uses **Playwright**, which is a Node-ecosystem tool: running it unavoidably
drags in a JS package manager and a lockfile. This is *test-only* tooling — it never ships and
doesn't touch the product — so the constraint is "keep it out of the product," not "never use
a package manager." The first cut used **npm**, which is slow and pulls `actions/setup-node`
into CI, where GitHub flags the Node 20 action runtime as deprecated.

## Decision

Use **Bun** as the package manager and script runtime for all non-product JS/TS tooling.

- Install with `bun install`; commit the text lockfile `bun.lock`.
- Run scripts with `bun run <script>` (never `bun test` — that's Bun's own runner, not
  Playwright; our `test` script shells out to the `playwright` CLI).
- The Playwright `webServer` launcher runs under Bun (`bun serve.mjs`).
- CI uses `oven-sh/setup-bun` (pinned `bun-version`), not `actions/setup-node`.

Playwright's own CLI still executes via its Node shebang — satisfied by the Node that ships on
the CI runner / the dev box — but **we** drive everything through Bun and no longer depend on
npm or a pinned Node toolchain.

Bun is pinned (currently `1.3.14`) for reproducibility, matching how we pin Odin and htmx.

## Policy (applies beyond e2e)

**If a JS/TS tool is ever needed elsewhere** — another test harness, a one-off script,
codegen, a docs generator — **use Bun**, not npm/pnpm/yarn/Node-scripts. Reasons: it's fast,
it's a single binary, and it keeps one runtime across all our tooling.

Two hard boundaries remain:
1. **Never add JavaScript to the product.** The app is Odin + HTMX; the only shipped JS is
   `app/static/app.js` (hand-written, no deps) and embedded htmx. Bun is for dev/test tooling.
2. Tooling lives in its own directory (e.g. `e2e/`) with its own `package.json` / `bun.lock`,
   so the product build (`odin build`) stays free of any JS toolchain.

## Consequences

- **Faster** installs and script startup; one small binary instead of the npm/Node stack.
- Removes our explicit Node version pin and the `setup-node` action from CI.
- **Caveat — not fully Node-free in CI:** GitHub's own actions (`checkout`, `cache`,
  `upload-artifact`) run on GitHub's managed Node runtime. Any Node-runtime deprecation there
  is GitHub's to fix via action version bumps; we just track the latest majors. So the Node
  deprecation notice may not vanish entirely, but it's no longer coming from *our* tooling.
- Playwright runs green under this setup (validated locally and in CI). If a future tool turns
  out to be incompatible with Bun, fall back to Bun-as-package-manager + Node-as-runtime for
  that one tool, and note it here.
