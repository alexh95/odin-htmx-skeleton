# platform/ext

The closed set of htmx 4.0.0 extensions a page can load and the page bundles' `/* exts: … */` header (D19, D21).
It imports only core, so `tools/bundle`, which writes the header, and the boot check that reads it share one table;
`platform/web` re-exports it as `web.Ext`. Layer L1 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
