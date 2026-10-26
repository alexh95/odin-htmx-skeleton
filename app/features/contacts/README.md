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

Audited: bf831da 2026-10-26 docs/audit/M1.md
