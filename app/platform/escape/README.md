# platform/escape

The injection boundary: `esc` for text and attributes, `url_encode` for a URL component, `json_esc` for a string
inside JSON, `w` for markup. One definition of each; `platform/html` re-exports them for views and
`platform/markdown` uses them directly. A leaf: core only. Layer L1 (PLAN §5.1).

Audited: 30988ae 2026-10-30 docs/audit/M4.md (`b64_decode` and its use, read in the re-read); 5c5ebf2 2026-10-27 docs/audit/M2.md
