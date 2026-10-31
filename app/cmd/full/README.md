# cmd/full

Houston (PLAN §7.1, §7.3), growing through M4, on SQLite, the hyperscript client and the full theme, two hosts from
one binary:

- **the main host** (`SITE_URL`): `home` (the root), `accounts` with its `identity_accounts` (sign-in, two-step,
  registration, `/admin/accounts`), `audit` (`/admin/audit`), `modules` (`/admin/modules`) and `about`;
- **the lab host** (`SITE_URL_LAB`, `LAB_BRAND`, `LAB_NAV`): every starter demo and lab page, with no identity and no
  cookie: `landing` at `/`, the skeleton's `dashboard` at `/dashboard`, `gallery`, `contacts`, `lab`, `scripting`,
  `compat` and `about`.

The main host's tables keep the names tools/init reads (`ROUTES`, `TOPICS`, `JOBS`, `NAV`); the lab host's are
`LAB_*`. tools/init doesn't edit a two-host profile: change these files by hand. A profile (PLAN §7).

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its M5 diff); d136601 2026-10-30 docs/audit/M4.md
