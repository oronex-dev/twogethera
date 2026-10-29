# CP-004B.3 — isolated migration and hardening rehearsal

Local synthetic-data experiment, not production migrations. Read [the report](../../docs/CP-004B3.md) before interpreting results.

## Run

From the repository root, with OrbStack, Supabase CLI **2.122.0** and ordinary Python 3.11+:

```sh
rtk proxy python3 -u proofs/cp004b3-rehearsal/start_local.py
rtk proxy python3 -u proofs/cp004b3-rehearsal/run_tests.py
```

Expected: **38 unchanged B.2 Auth/HTTP scenarios + 15 B.3 rehearsal scenarios passed; zero mocks/skips.** The runner imports the checkpointed B.2 regression methods without editing them and pins their source checksum. Its module globals point exclusively to B.3, and its separate HTTP wrapper permits only B.3 loopback ports. No production client receives an administrator key. Admin access is limited to synthetic fixture creation, DDL/catalog inspection and lock/failure instrumentation.

The independent project is `twogethera-b3`, on loopback API 57321, PostgreSQL 57322, shadow 57320 and captured mail 57324. The `twogethera-b3` container labels and actual bind addresses are checked before mutation. All Auth identities must use reserved `example.invalid` addresses; unexpected data/markers fail closed. No hosted link, external email, Storage, Realtime, Flutter wiring or new package is required. Dedicated generated ES256 material stays ignored under `supabase/.local/` (0700 directory, 0600 file); never display raw CLI status/start output or debug traces.

Startup was executed twice successfully; rerunning it reuses the dedicated local stack. No other stack is restarted or reset. The runner replaces only the marked B.3 application's proof/ledger schemas, never its Auth users, database or other projects. Synthetic Auth accounts accumulate. Run one rehearsal at a time; the runner is not a concurrent migration deployment tool. Cleaning up Docker volumes/accounts requires a separately reviewed, project-scoped command; no broad prune/reset is provided.

## Migration sequence

[Migrations manifest](migrations.json) pins the three ordered SQL files and SHA-256 checksums. The runner checks these before execution and uses a private `cp004b3_rehearsal.applied` ledger. Each slice and its ledger insertion commit atomically. Changed checksums/out-of-order execution are rejected; already applied identical slices are no-ops. Automatic Supabase migrations and seeds are disabled: these files are deliberately executed only by the guarded rehearsal runner.

1. `20261029000100_bootstrap.sql`: PostgreSQL/pgcrypto prerequisites and marked nonlogin owner with role-membership checks in both directions; minimal Auth REFERENCES grant.
2. `20261029000200_kernel.sql`: snapshot of checkpointed B.2 SQL, preserving the `cp004b2` object names in a **different cluster** so exact regression methods can run. Only the header, B.3 marker and transaction-wrapper ownership differ from the source. No product schema is introduced.
3. `20261029000300_default_execution.sql`: revoke global default function EXECUTE for the application's owner. Per-schema revokes cannot subtract PostgreSQL's global PUBLIC default.

The marked target is `twogethera:cp004b3:disposable:v1`. SQL file 002 intentionally has no standalone BEGIN/COMMIT: the runner owns the transaction, including the ledger. Do not apply files individually, copy them into root migrations, run `db push`, or treat this custom ledger as Supabase's migration history.

The populated N-1 rehearsal installs slices 001/002, explicitly restores B.2's factory-default future-function privileges in this isolated environment, creates a real-JWT paired space/invitation/receipts, and upgrades with slice 003. Six-table content digests, including the random HMAC key, remain unchanged. The intentionally vulnerable canary is rollback-only; after hardening, a new harmless definer canary is actually denied over HTTP, then removed. No vulnerable canary remains installed.

## Scope of results

The suite verifies clean/repeated schema rebuild, ordering, checksum drift, populated upgrade, migration rollback, grants/ownership/default ACLs, lost invitation responses, replacement, absent rate quotas and the known ban-versus-JWT-read boundary. The unchanged B.2 methods exercise real client RLS, single-use verified-email binding, operation receipts, nine coordinated HTTP races and injected command rollback. Catalog/constraint probes use privileged setup SQL and are not substituted for user-token authorization assertions.

Production prerequisites remain unresolved: Auth-owner helper portability/replacement, Auth lock interactions, durable rate limits, receipt/key lifecycle, independently protected admin credentials, session revocation, redacted monitoring, backup/restore drills and supported cross-version upgrades. Local Auth legacy secrets are shared across these CLI stacks; user-token verification is restricted to B.3 ES256 JWKS, but this does not prove independently isolated privileged Auth credentials. The report separates evidence from proposed controls. Pending privacy decisions and the existing Flutter application remain unchanged.
