# CP-004A isolated security proof

This is a disposable PostgreSQL experiment, **not production migrations or authentication**. See [the implementation report](../../docs/CP-004A.md) for results, limitations and pending policy boundaries.

Run from the Flutter project root with the existing local OrbStack/Supabase stack healthy:

```sh
rtk proxy python3 -u proofs/cp004a-security/run_tests.py
```

Python standard library only. Docker is discovered from PATH or the existing OrbStack application binary. The runner verifies the local Unix Docker context, OrbStack engine, loopback Supabase endpoints and expected project container label. It uses container-local `psql`; no host database client, DSN, cloud project, production credential or Flutter dependency is required.

It creates only the dedicated `twogethera_cp004a_proof` database and uniquely prefixed synthetic roles. Every reset requires the exact database name and disposable sentinel comment; an existing database/role collision without the expected marker is rejected. **Each run resets this proof's schemas and synthetic fixtures.** Do not put valuable data in this database. It does not reset/restart Supabase or use its migration directory.

- `schema.sql`: five logical domain tables (synthetic identities, spaces, memberships, invitations, shared records) plus private operation receipts; RLS and guarded commands.
- `run_tests.py`: real restricted-role connections, catalog/behavior assertions, deterministic independent-connection lock barriers and three race rounds; nonzero exit on any failure, no skipped tests or mocks.

The owner/group roles are NOLOGIN; synthetic client and anonymous roles are LOGIN with NULL passwords and no elevated privileges. They connect through the existing trusted **container-loopback** authentication rule. They are not production accounts or signed Supabase identities. Bootstrap uses local `supabase_admin` only for isolated setup/constraint inspection; business authorization assertions connect directly as restricted roles rather than switching down from a superuser session.

The proof leaves its disposable database and prefixed roles for inspection/repeatability. It does not add host passwords or edit PostgreSQL host-authentication configuration. Anyone controlling the local Docker engine is already trusted; this experiment does not defend against that operator. Closed spaces deny both former members all test-record reads; this deliberately implements no survivor archive or retention policy.
