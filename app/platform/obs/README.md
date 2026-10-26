# platform/obs

Logs, metrics and health as data (PLAN §10.4): logfmt lines in a per-thread buffer, request ids, per-thread counters
and per-route request counters summed on a scrape, gauges, each module's health, and the limits every feature
declares at init. `platform/web` serves them as `/metrics`, `/livez`, `/readyz` and `/healthz`. Everything per
request is per thread and lock-free. Layer L2 (PLAN §5.1).

Audited: bf831da 2026-10-26 docs/audit/M1.md
