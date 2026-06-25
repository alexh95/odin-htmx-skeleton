# TODO

Source of truth for outstanding work. Check items off as you finish them; add follow-ups you
discover. See `CLAUDE.md` for the standing policy. Keep this and `CHANGELOG.md` current.

## Now / next

- [ ] **Set up infrastructure** per [`infra/PLAN.md`](infra/PLAN.md): remote git host (GitHub),
      CI/CD (GitHub Actions), and a permanently-reachable deployment (Fly.io free allowance, or
      Oracle Always Free for $0). Also stands up where e2e and load-tests run.
  - [ ] Prereq code change: bind `net.IP4_Any` (0.0.0.0) and read `PORT` from env in
        `app/main.odin` so the binary is deployable (keep loopback as the local default).
  - [ ] Pin odin-http as a submodule for reproducible CI (today `prepare.*` clones latest).
- [ ] Implement the e2e suite per [`e2e/PLAN.md`](e2e/PLAN.md). Fold in the three fixed bugs as
      regression tests (modal outside-click, form field-persist, slider fill).
- [ ] Implement the load-tests per [`load-tests/PLAN.md`](load-tests/PLAN.md). Lead with the
      single-thread ceiling measurement.
- [ ] **Sync gate:** once both suites exist, every endpoint must appear in both. Backfill any
      gaps and keep them paired going forward.

## Backlog

- [ ] Data table: the actions column overflows into horizontal scroll on narrow viewports.
      Consider a responsive tweak (narrower engagement column, or stacked actions).
- [ ] Pin htmx to an exact version in `prepare.*` (currently `@2`) for reproducible builds.
- [ ] Optional: a build-flag-gated `/__reset` endpoint to reseed the store (useful for load
      tests; must never ship in a normal build). Tie to `load-tests/PLAN.md`.
- [ ] Optional: `-o:speed` build path for benchmarking vs. the default showcase build.

## Done

- [x] Initial showcase app (dashboard, components, forms, data + CRUD, search, JSON API).
- [x] Bug fixes: modal outside-click, `/forms` field reset, static slider fill.
- [x] Restructure into `app/` + `e2e/` + `load-tests/`; project docs (`CLAUDE.md`, this file,
      `CHANGELOG.md`).
- [x] git init + first commit; adopted Conventional Commits; infrastructure plan
      (`infra/PLAN.md`).
