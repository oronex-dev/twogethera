# CP-002 · Data architecture and security blueprint

Status: **proposed architecture; not deployed or security-certified**. Prepared 28 October 2026. No migrations, Dart implementation classes, authentication UI, dependencies, credentials, or backend connections are introduced. CP-001 remains the runnable baseline.

## Reading order

1. [Data model and ER diagram](DATA_MODEL.md)
2. [Authorization and threat boundaries](SECURITY_MODEL.md)
3. [Partner invitation protocol](PARTNER_LINKING.md)
4. [Offline and synchronization protocol](OFFLINE_SYNC.md)
5. [Export, unlinking, retention, and deletion](DATA_LIFECYCLE.md)
6. [Application contracts and data flows](APPLICATION_CONTRACTS.md)
7. [Implementation gates and verification](IMPLEMENTATION_SEQUENCE.md)

These documents specify a design to implement and test. Policy predicates and transaction algorithms are specifications, not runnable SQL. Database concurrency and adversarial authorization tests are required before any claim of production security.

## Decisions requiring product approval

The following defaults let planning proceed. **They are proposals, not approved product policies.** Approve or revise these before implementing the affected migrations or workflows.

| ID | Proposed decision | Consequence |
| --- | --- | --- |
| D01 | One current couple per account; draft has one member, paired space exactly two; archived spaces cannot be reopened or receive a replacement partner | A new relationship gets a new space; historical access never carries to the new partner |
| D02 | Either partner can unlink without the other's permission; leaver immediately loses server access; remaining partner receives a read-only archive | Remaining partner may form a new couple; no automatic merge or transfer of old data |
| D03 | Shared text and exact-money ledger records remain in the remaining partner's archive after account deletion, with erased-person attribution pseudonymized; departing person's uploaded photos are removed | Shared-data ownership and privacy policy require explicit product/legal review before launch |
| D04 | Change log/tombstones retained at least 90 days; offline read lease at most 7 days; account deletion grace 30 days; unreferenced uploads 24 hours; exports 24 hours | Stale clients require full snapshots; cached offline data cannot be remotely recalled |
| D05 | One immutable ISO currency and minor-unit exponent per savings goal; recorded deposits and exact reversals only; no FX, bank integration, interest, or withdrawal workflow initially | Amounts never use floating point; planner records do not claim to verify real bank balances |
| D06 | Invite is bound to a verified email identity, lasts 24 hours, and is single-use; user shares the link manually | No anonymous redemption or automatic email delivery; changing recipient requires a replacement invite |
| D07 | Private photo bucket with authenticated reads; no downloadable signed bearer links in the initial product | Membership is checked on subsequent online reads; copies and in-flight bytes cannot be recalled |
| D08 | Trusted-server model, not end-to-end encryption; native key storage/encrypted local persistence require a separate technical spike; web has weaker local secrecy | Do not advertise E2EE or equivalent browser/device security; user must understand offline cache risk |
| D09 | Shared planner writes require a paired space; no shared content writes in an unpaired draft | No offline acceptance, unlinking, or contributions to an unpaired/archived space |
| D10 | Account deletion immediately disables access; cancellable for 30 days through a restricted recovery flow; cancellation does not restore former memberships | Other partner is not held hostage to account recovery or deletion consent |
| D11 | Missing monthly days/Feb 29 are skipped; DST gaps advance to first valid local instant and folds choose the earlier offset | Recurrence previews and reminder scheduler must share a versioned ruleset |

Bounds in the schema (text lengths, money magnitude, upload sizes, rate limits) are proposed operational defaults to validate during CP-003. They are not service-plan promises. No paid service is assumed.

## Baseline protection

Historical CP-002 record below. The subsequent user-authorized Git baseline and advisory decision review are recorded in [APPROVAL_REVIEW.md](APPROVAL_REVIEW.md); original decision proposals remain unchanged.

`git status` / `git rev-parse --show-toplevel` report **not a git repository** at `/Users/fielmark.oronos/Developer/twogethera`. Therefore no local baseline commit is possible under the requested conditional instruction. No repository or remote was created; nothing was pushed. The unrelated original chat directory was not used.

Existing root, Android, and iOS ignore files already cover `.dart_tool/`, `build/`, IDE files, Gradle caches, `local.properties`, generated plugin registrants/configuration, Pods, SwiftPM/cache state, and Android signing files. Keep `pubspec.lock`, platform source/configuration, and schema migration histories versioned when a repository is later initialized. Before introducing credentials or real data, add narrowly scoped ignores for local `.env` secrets, private certificates, database files, exports, and local media; an ignore file never sanitizes already tracked secrets. None of those artifacts are introduced in CP-002.

See [implementation sequence](IMPLEMENTATION_SEQUENCE.md) for actual CP-001 verification results and future gates.

## External technical references

Design choices are Twogethera proposals. Platform behavior was checked against primary documentation on 28 October 2026:

- [Supabase RLS](https://supabase.com/docs/guides/database/postgres/row-level-security): policy mechanics, helper functions, and view boundaries.
- [Storage access controls](https://supabase.com/docs/guides/storage/security/access-control) and [asset delivery](https://supabase.com/docs/guides/storage/serving/downloads): separate object authorization and private delivery options.
- [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization) and [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes): channel authorization and change-stream limitations.
- [PostgreSQL row locking](https://www.postgresql.org/docs/current/explicit-locking.html): transaction serialization primitives.
- [Drift transactions](https://drift.simonbinder.eu/dart_api/transactions/), [web persistence](https://drift.simonbinder.eu/platforms/web/), and [migrations](https://drift.simonbinder.eu/migrations/): local database capabilities and platform constraints.

Select the actual PostgreSQL/Supabase versions and verify feature compatibility when a development backend is approved; no database version has been provisioned here.
