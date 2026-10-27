# notes

The minimal starter's one entity: a list of notes and a form that adds one over HTMX, refusing a blank or over-long
note with a 422. Packages: `notes` (the domain), `models` (the type and the store contract), `views`, `web` (the home
card and `POST /notes`), `storetest` (the conformance suite, run against both stores). Its stores: memory
(`app/stores/memory/notes/`, a ring of the newest 500) and SQLite (`app/stores/sqlite/notes/`). It owns `/notes`, its
own prefix.

Audited: bf831da 2026-10-26 docs/audit/M1.md; its M2 edits (`html.behave`, the layout's `#live`) are outside `docs/audit/M2.md`'s scope: audit debt
