# platform/obs

Logs, metrics and health as data (PLAN §10.4): logfmt lines in a per-thread buffer, request ids, per-thread counters
and per-route request counters summed on a scrape, gauges, each module's health, and the limits every feature
declares at init. `platform/web` serves them as `/metrics`, `/livez`, `/readyz` and `/healthz`. Everything per
request is per thread and lock-free. Layer L2 (PLAN §5.1).

Audited: cf7f42b 2026-10-31 docs/audit/M5.md (its fixes, f42f032, read in the re-read); 5c5ebf2 2026-10-27 docs/audit/M2.md
