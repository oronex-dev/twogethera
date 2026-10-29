# CP-004B.4 — local Auth privilege and operational proof

Synthetic local experiment, not production deployment or approved privacy policy. [Full report and CP-005 readiness](../../docs/CP-004B4.md).

## Run

From repository root with OrbStack, Supabase CLI **2.122.0**, ordinary Python 3.11+:

```sh
rtk proxy python3 -u proofs/cp004b4-operations/start_local.py
rtk proxy python3 -u proofs/cp004b4-operations/run_tests.py
```

Expected: **38 unchanged B.2 scenarios + 19 B.4 operational scenarios passed**. Full Auth signer rollover is printed separately as **UNVERIFIED**, never counted as a pass. All counted cases use actual PostgreSQL or HTTP behavior; no mocked responses or skip branches. The original A/B.1/B.2/B.3 runners remain unchanged and were run separately. B.3's intentional no-quota finding is not expected under B.4; its original 53-case regression passes in its own stack.

The new project is `twogethera-b4`: API **58321**, DB **58322**, shadow **58320**, captured mail **58324**, all on a loopback-only Docker network. Container labels, exact marker `twogethera:cp004b4:disposable:v1`, synthetic-only Auth users and actual port publications are verified before mutation. No hosted project, account data, root migration or Flutter code is used. CLI output containing credentials is captured and never printed. Generated signing material and CLI metadata remain ignored; `.local` is 0700 and its signing file 0600. Do not enable HTTP/SQL tracing or publish raw CLI status/start output.

Run only one B.4 harness at a time. It replaces only this marked project's `cp004b2`, `cp004b2_private`, `cp004b4_ops` and private rehearsal-ledger namespaces. Object names are retained to run the pinned B.2 assertions; they refer to **another physical cluster**. Auth users/volumes are not reset. Synthetic Auth users accumulate with unique reserved `example.invalid` addresses. Resource cleanup requires separately reviewed project-scoped commands; no broad Docker prune/reset is provided.

## Implemented experiment contracts

[Four ordered migration slices](migrations.json) install the prior kernel/default-privilege protections and B.4 controls. The B.3 migration runner is imported with B.4 target globals; B.2/B.3 source checksums are pinned. Automatic Supabase migrations/seeds are disabled. The runner's guarded transaction includes DDL and private ledger update. Do not execute these files independently, move them to root migrations or use this harness as a production migration deployer.

| Control | Exact proof behavior |
| --- | --- |
| Live application account gate | Operator-only `cp004b4_ops.set_account_enabled(uuid,boolean)` locks an existing account; disable filters RLS reads and denies commands using the same JWT; restore is an explicit operator action |
| Maintenance privileges | Marked NOLOGIN/NOBYPASSRLS role has schema usage and EXECUTE on exactly account-state maintenance and receipt compaction; no direct table DML or Auth SELECT |
| Invitation quota | Five fresh successful issue operations per issuer per **fixed server-UTC hour bucket**, shared across that actor's scopes; not a rolling-hour limiter |
| Quota retries/failures | Exact successful retry is free; payload mismatch/invalid request does not charge; sixth fresh issue returns generic HTTP 429 and rolls replacement/receipt back |
| Pending invites | Existing unique pending-per-space index remains enforced; explicit replacement consumes budget and revokes prior token only if the transaction commits |
| Receipt availability | Results expire after one server hour; original operation IDs are denied with HTTP 409 after deadline, even before cleanup |
| Compaction | Maintainer explicitly runs `cp004b4_ops.compact_receipts(100)`; skips locked actor rows, clears expired result/request hash and retains a spent actor/operation key and required legacy metadata |
| Duplicate prevention | Spent keys are not deleted; cleanup cannot turn an expired create/issue/accept into a fresh operation. Markers persist for this proof's lifetime, until explicit proof reset |

`compact_receipts` limits **actors**, not receipt rows, per invocation. A scheduled/batched production cleanup worker is not implemented; expiry denies result delivery immediately, while physical payload clearing requires running maintenance. There is no guarantee that every stored payload vanishes automatically at one hour. Budget history also remains until proof reset. Marker retention, row-volume bounds and production cleanup scheduling need a reviewed operational design; these are not shared-content or financial retention choices.

A fixed UTC hour can admit ten operations across adjacent bucket boundaries. Request/body/IP limits, distributed ingress fairness, backoff/Retry-After, signup/recovery abuse controls and production gateway enforcement remain unimplemented. No hosted mail sender or external rate-limit service exists.

## JWT/key boundary

Normal API calls use real local Auth ES256 access tokens plus the public API key, never the fixture service key. Application account disable is independent of JWT signature/expiry and does not mean global JWT/session revocation. Auth ban/logout alone is not wired into that gate. The private current-user email helper remains Auth-owned; the report documents its narrow call surface and production privilege/managed-schema risks.

The **passing key tests** generate a new ES256 JWK via the official CLI into memory, use only its public component in actual PostgREST verification configuration, retain then remove the real token's existing public key, and restore original trust. The same unexpired Auth-issued JWT succeeds/gets 401/succeeds as expected; disabling the account still filters reads. No JWT is manually minted. Auth continues using its original signer in this passing suite.

An exploratory CLI append/restart attempt did not complete reliably. Its signing file and services were restored; full Auth signer adoption, managed dual-key rotation, refresh behavior and production cache propagation are **not verified**. The test does not replace that missing evidence with a claim of successful rotation. PostgREST uses an explicit local public-JWKS snapshot, refreshed by the runner; it is not a proof of automatic production JWKS refresh. Legacy local Auth signing authority remains an environment-isolation risk.
