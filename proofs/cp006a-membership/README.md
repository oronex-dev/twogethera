# CP-006A — local membership and authorization proof

Disposable local Supabase proof for the root membership migration. This does not add a product planner module and is not the invitation milestone. The sole `cp006a_test_shared_records` table is created by the test runner, has synthetic rows, is absent from application migrations, and exists only to exercise the approved D09 read boundary.

## Run

From the repository root, with local OrbStack and Supabase CLI 2.122.0:

```sh
rtk proxy python3 -u proofs/cp006a-membership/start_local.py
rtk proxy python3 -u proofs/cp006a-membership/run_tests.py
```

The stack uses loopback-only ports 59321–59324, enables local email confirmation and Mailpit, and does not use the root stack or other CP-004 proof stacks. The test runner captures credential-bearing CLI output and never prints it. The application migration is read from `supabase/migrations/20261102000100_membership_foundation.sql` and installed only in the guarded disposable database. The root local `supabase/config.toml` and local database are not reset or modified by this proof.

The runner uses local Auth administration only to create reserved `example.invalid` fixtures and read synthetic verification mail/state. Client authorization assertions use real signed user JWTs through PostgREST. Database-superuser SQL is limited to guarded setup, synthetic fixture rows, catalog checks, and outcome inspection; it is never used as evidence of client authorization.

CP-006A.1 additionally requires Python `cryptography` locally to create a short-lived ES256 regression JWT using the isolated project's private signing key. The key is generated under ignored `.local/` with restrictive directory/file permissions. The signed test token has a real synthetic Auth subject and valid expiry but deliberately omits the `role` claim; neither the token nor key is emitted. The concurrency proof uses six synchronized HTTP clients, a temporary database gate and observed PostgreSQL `pg_stat_activity` wait events. Temporary test objects are removed during the run.

## Scope and limits

The migration contains only couple spaces, memberships, a private creation idempotency receipt, an Auth-owned verified-identity check, RLS, and an atomic `create_couple_space` command. Invitation token generation/acceptance, unlink UI/API, archive retention, product tables, Storage, Realtime and Flutter integration are out of scope. A test-only planner-record table is not an application feature. No hosted project is linked.

This first migration is exercised on a clean isolated database. There is no prior root application migration to upgrade from, so an N-1 populated upgrade cannot yet be claimed. The Auth-owned column-read bridge, role ownership, and local role grants need a managed-Supabase portability review before production promotion.

## CP-006A.1 assurance additions

- JWT identity validation is null-safe for a missing role claim; the no-role signed-token and direct identity-gate regressions must fail closed.
- The owner-role migration guard rejects unsafe attributes, either direction of role membership, and an unexpected ownership marker.
- Membership states are limited to `active` and `revoked`; the server assigns `revoked_at`. No archive membership entitlement, unlink workflow, invite acceptance, or replacement partner is implemented.
- A draft must retain exactly one active seat-1 creator. Six concurrent create HTTP requests are released together; the suite observes one transaction in the test sleep gate and five PostgreSQL lock waits, expects exactly one success and five conflict responses, and checks final space/member/receipt counts.
- The injected receipt failure asserts an exact SQLSTATE and message and compares all in-scope persistent row counts before/after.
- The private-schema HTTP probe explicitly requests the `app_private` profile and expects the configured schema exposure denial.

The runner reports scenario groups and `require()` assertion counts separately. Keep the actual latest results in `docs/CP-006A.md`; historical CP-004B results must not be represented as rerun unless their suites were executed in the same verification.

Latest CP-006A.1 verification: **21/21 scenario groups and 182 `require()` checks passed**. The deterministic concurrency observation was `1 PgSleep` plus `5` lock waits; outcomes were exactly `1` HTTP success and `5` HTTP conflicts, with final state `1` space / `1` active membership / `1` receipt. Flutter analysis passed, Flutter tests passed **88/88**, Dart format reported **38 files unchanged**, and `git diff --check` passed. CP-004B.1 and CP-004B.2 were not rerun for this checkpoint.
