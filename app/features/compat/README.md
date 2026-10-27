# compat

htmx 4's two compatibility extensions, each on a page and a fixed bundle of its own (PLAN §12.3, §15.5), under the
hash CSP. `/compat/htmx2` (htmx + htmx-2-compat) runs markup written the htmx 2 way: a refused submit's 422 is not
swapped, a child inherits its parent's `hx-target`, and htmx 2's event names fire (`static/compat.js` counts
`htmx:afterSwap`). `/compat/alpine` (htmx + hx-alpine-compat) loads the extension with no Alpine and shows that it
changes nothing. `/compat` is the index, on Main. Every row is `.Lab_Host`, since htmx-2-compat changes what every
`hx-*` attribute on its page means (D20). The starter uses neither extension anywhere else. Packages: `views`, `web`;
no store. It owns `/compat`, its own prefix.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
