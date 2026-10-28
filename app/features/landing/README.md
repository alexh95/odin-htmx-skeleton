# landing

The starter's own page (PLAN §15.5, M3): the lab host's `/`, which the profile mounts. It shows the profiles running
now, the catalog (`docs/catalog.json`, the generator's `--list --json`, embedded at build time and read once at boot)
as a table of profiles and one of features, and the init-command builder: a form whose fragment answer,
`GET /landing/command`, is the `odin run tools/init -- …` line and what it pulls in, or why the generator would refuse
it. `plan` mirrors the generator's rules (the dependency closure, the root, the store a feature needs); the
generator's own `--explain` stays the authority, and the page says so. Packages: `landing` (the catalog and `plan`),
`views` and `web`; no store. The page is rendered once at boot; the builder's answer per request.

It owns `/landing`, its own prefix; `/` is the profile's root row.
