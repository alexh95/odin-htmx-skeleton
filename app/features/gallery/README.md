# gallery

The skeleton's component gallery and forms page: tabs, accordions, toasts, a modal and a drawer, each swapped in over
one request, and a form whose submit creates a contact through contacts' domain. Packages: `views`, `web`; no store
of its own.

## Prefixes

Beyond `/gallery`, `/admin/gallery` and `/api/gallery` (D9):

| Prefix | Why |
|---|---|
| `/components` | the skeleton's gallery page, at its exact URL (PLAN §6.3) |
| `/forms` | the skeleton's forms page and its submit, at their exact URLs |
| `/ui` | the overlay, tab and toast fragments the components page swaps in (`/ui/ping` is dashboard's) |
| `/validate` | the email check the forms page runs as you type |

Audited: bf831da 2026-10-26 docs/audit/M1.md; its M2 edits (`html.behave`, the layout's `#live`) are outside `docs/audit/M2.md`'s scope: audit debt
