# contacts

The skeleton's worked example: a contacts table with search, paging, sorting, a detail drawer and an activity
timeline, and the JSON API. Packages: `contacts` (the domain: validation, paging, the write op), `models` (the types,
labels and the store contract), `views`, `web`. Its store is SQLite only (`app/stores/sqlite/contacts/`, migrations
0001–0004); store v3 commits its writes on the writer task, and the handlers answer through a deferred response.

## Prefixes

Beyond `/contacts`, `/admin/contacts` and `/api/contacts` (D9):

| Prefix | Why |
|---|---|
| `/data` | the skeleton's table page, at its exact URL: the parity gate compares the same paths (PLAN §6.3, §18) |
| `/search` | the skeleton's active-search fragment, which the k6 `search` scenario hits; global search is `find`'s `/find` |
| `/api/search` | the skeleton's JSON API, at its exact URL (the k6 `api` scenario) |

## The demo (full's lab host)

`full` mounts contacts as a public demo: `contacts_web.demo_init()` reads `CONTACTS_CAP` (2000; a create past it is a
422 like a validation error) and `CONTACTS_RESET_HOUR_UTC` (2), and `full` mounts `contacts_web.DEMO_JOBS`, whose
`contacts.reset` empties both tables and seeds them again once a day at that hour (the store's `reset`, one
transaction). The skeleton does neither, so its rows are never capped or reset.

Audited: bf831da 2026-10-26 docs/audit/M1.md; its M2 edits (`html.behave`, the layout's `#live`) are outside `docs/audit/M2.md`'s scope: audit debt
