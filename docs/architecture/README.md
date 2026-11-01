# CP-002 · Data architecture and security blueprint

Status: **proposed architecture; not deployed or security-certified**. The blueprint was prepared 28 October 2026. Subsequent CP-004 milestones added isolated, synthetic-only local PostgreSQL/Supabase proofs, and CP-005 added a local/debug Auth experience; these are not production migrations, production authentication or deployed RLS. The root application `supabase/migrations/` directory is absent. CP-001 remains the app foundation.

## Current reconciliation

Read [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md) first for the complete current matrix and policy/schema/protocol reconciliation. D01, D02, D06 and D09 are formally approved; D03 remains a recorded revision with unresolved implementation details. Other technical directions remain pending formal approval; P03/P04/P09 still need product resolution. The [CP-006 readiness report](../CP-006.md) records repository evidence and a bounded implementation sequence. Earlier proposal wording below is preserved history, not competing current defaults. This documentation update does not authorize implementation.

## Reading order

1. [Data model and ER diagram](DATA_MODEL.md)
2. [Authorization and threat boundaries](SECURITY_MODEL.md)
3. [Partner invitation protocol](PARTNER_LINKING.md)
4. [Offline and synchronization protocol](OFFLINE_SYNC.md)
5. [Export, unlinking, retention, and deletion](DATA_LIFECYCLE.md)
6. [Application contracts and data flows](APPLICATION_CONTRACTS.md)
7. [Implementation gates and verification](IMPLEMENTATION_SEQUENCE.md)

These documents specify a design to implement and test. Policy predicates and transaction algorithms are specifications, not runnable SQL. Database concurrency and adversarial authorization tests are required before any claim of production security.

## Original product decision register — preserved wording and history

The table preserves the original proposal wording. D06/D09 status notes reflect CP-006; the dated review snapshots below retain their original status. D01–D03 user decisions and open P01–P09 choices are recorded in [D01_D03_RESOLUTION.md](D01_D03_RESOLUTION.md).

For D01–D03, the table below contains the current user wording; D04–D11 retain their original proposed wording. Preliminary technical mechanisms remain designs to validate, not deployed or implicitly approved implementations.

| ID | Decision / proposal | Status / consequence |
| --- | --- | --- |
| D01 | One active couple space per account, maximum two active members. Archived spaces cannot be reopened or reused with a replacement partner. | Approved. Active membership limits fixed; archived spaces cannot be reused; draft state details remain proposed. |
| D02 | Either partner may unlink independently. The departing partner immediately loses server access. The remaining partner may receive a read-only archive, subject to the D03 privacy and retention rules. Do not claim that previously downloaded data can be remotely erased. | Approved with safeguards. Archive access is conditional on D03; delivered/downloaded data cannot be remotely erased. |
| D03 | Preserve only necessary, auditable contribution history with pseudonymized attribution after account deletion. Shared text, notes, and photographs must have a clearly documented removal, retention, and export process. Do not assume indefinite retention of all shared content. | Revised policy recorded. No indefinite shared-content assumption; resolve P01–P09 before affected implementation. |
| D04 | Change log/tombstones retained at least 90 days; offline read lease at most 7 days; account deletion grace 30 days; unreferenced uploads 24 hours; exports 24 hours | Stale clients require full snapshots; cached offline data cannot be remotely recalled |
| D05 | One immutable ISO currency and minor-unit exponent per savings goal; recorded deposits and exact reversals only; no FX, bank integration, interest, or withdrawal workflow initially | Amounts never use floating point; planner records do not claim to verify real bank balances |
| D06 | Invite is bound to a verified email identity, lasts 24 hours, and is single-use; user shares the link manually | **Formally approved in CP-006** with 256-bit token, atomic acceptance, idempotent replay handling and required creation/acceptance abuse limits; no automatic email delivery |
| D07 | Private photo bucket with authenticated reads; no downloadable signed bearer links in the initial product | Membership is checked on subsequent online reads; copies and in-flight bytes cannot be recalled |
| D08 | Trusted-server model, not end-to-end encryption; native key storage/encrypted local persistence require a separate technical spike; web has weaker local secrecy | Do not advertise E2EE or equivalent browser/device security; user must understand offline cache risk |
| D09 | Shared planner writes require a paired space; no shared content writes in an unpaired draft | **Formally approved in CP-006:** planner writes require exactly two active linked members; unpaired setup/invites only; archives limited to read/export/privacy removal; no third/replacement member |
| D10 | Account deletion immediately disables access; cancellable for 30 days through a restricted recovery flow; cancellation does not restore former memberships | Other partner is not held hostage to account recovery or deletion consent |
| D11 | Missing monthly days/Feb 29 are skipped; DST gaps advance to first valid local instant and folds choose the earlier offset | Recurrence previews and reminder scheduler must share a versioned ruleset |

Bounds in the schema (text lengths, money magnitude, upload sizes, rate limits) are proposed operational defaults to validate during CP-003. They are not service-plan promises. No paid service is assumed.

## Baseline protection

Historical CP-002 record below. The subsequent user-authorized Git baseline and advisory decision review are recorded in [APPROVAL_REVIEW.md](APPROVAL_REVIEW.md); the historical review is retained, with current D01–D03 outcomes and unresolved privacy gates now recorded above.

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

## Historical CP-003B Part 2 proposal review

[FINAL_DECISION_PROPOSALS.md](FINAL_DECISION_PROPOSALS.md) records the CP-003B review of nine privacy choices and D04–D11, with the recommendations and approval states as they stood then. CP-006 formally approved D06/D09 only; all other historical proposal states remain subject to the current consolidated specification. This history is not authorization to implement a backend.
