# status

`/status` (PLAN §15.4, D36; basic at M2): is everything up? Packages: `status` (the domain: a probe per module that
reports its health to obs, plus the loops and the process), `views` (a card per probe) and `web`. The page writes each
card as "checking", and its board fills them from one `multipart/parallel` response, `GET /status/parts`, a part per
probe into its own card as the probe answers (all at once at M2: every probe is in the process; M5's external probes
each get 2 s). `?mode=poll` fetches the cards every 30 s instead (`GET /status/board`, hx-ptag over the states: 304
while none changed). A probe's message is shown to `Admin_Ops` only, but an external's (its version and time) is
what it answers anyone.

`STATUS_PROBES` (`name=host:port,…`) adds externals: a thread probes each one's `/healthz` every 10 s with a 2 s socket
timeout (resolve and connect have none of their own: on a stack network a stopped container doesn't resolve) and keeps
its last answer, which the board shows. In `lab` that is the witness board (M3): `deploy/compose.yaml` names the
other witnesses by their service names.

It owns `/status`, its own prefix.

Audited: 5c5ebf2 2026-10-27 docs/audit/M2.md
