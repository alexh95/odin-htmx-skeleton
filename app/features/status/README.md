# status

`/status` (PLAN §15.4, D36; basic at M2): is everything up? Packages: `status` (the domain: a probe per module that
reports its health to obs, plus the loops and the process), `views` (a card per probe) and `web`. The page writes each
card as "checking", and its board fills them from one `multipart/parallel` response, `GET /status/parts`, a part per
probe into its own card as the probe answers (all at once at M2: every probe is in the process; M5's external probes
each get 2 s). `?mode=poll` fetches the cards every 30 s instead (`GET /status/board`, hx-ptag over the states: 304
while none changed). A probe's message is shown to `Admin_Ops` only.

It owns `/status`, its own prefix.
