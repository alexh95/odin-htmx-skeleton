# stores/memory/audit

The audit log in a memory build (PLAN §11.4): each entry is one `mod=audit` logfmt line (`ev=<action>`, the actor, the
target, the reason, the hashed client id), and `list` finds nothing, so `/admin/audit` says the log is in the
process's output. A feature store.
