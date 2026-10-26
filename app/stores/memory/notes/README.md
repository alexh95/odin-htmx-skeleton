# stores/memory/notes

Notes in memory: the newest notes in a ring behind the store's lock. A note's text is copied to the heap when added
and freed when the ring pushes it out; a reader gets a copy in its request arena. A feature store.

Audited: bf831da 2026-10-26 docs/audit/M1.md
