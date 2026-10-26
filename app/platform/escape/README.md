# platform/escape

The injection boundary: `esc` for text and attributes, `url_encode` for a URL component, `json_esc` for a string
inside JSON, `w` for markup. One definition of each; `platform/html` re-exports them for views and
`platform/markdown` uses them directly. A leaf: core only. Layer L1 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
