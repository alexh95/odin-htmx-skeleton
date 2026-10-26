# dashboard

The skeleton's home page: four stat cards counted from contacts' store, link tiles and the ping button. Packages:
`dashboard` (the stats, from the contacts domain), `views`, `web`. Its page has no row in its own table: `skeleton`
mounts `dashboard_web.page` as its root row (`GET /`), and a profile that keeps another root could mount it at
`/dashboard`.

## Prefixes

Beyond `/dashboard`, `/admin/dashboard` and `/api/dashboard` (D9):

| Prefix | Why |
|---|---|
| `/ui/ping` | the skeleton's ping fragment, at its exact URL (PLAN §6.3); gallery owns the rest of `/ui` |

Audited: bf831da 2026-10-26 docs/audit/M1.md
