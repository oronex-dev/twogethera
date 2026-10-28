# Implementation sequence, approval gates, and verification

**CP-002 stops at this blueprint.** No migration, Auth screen, backend connection, product module, or speculative Dart contract class has been implemented. All tests below described as future gates are requirements, not claims that a backend exists or was tested.

## CP-001 baseline verification for CP-002

Project root: `/Users/fielmark.oronos/Developer/twogethera`. Inspected README, feature boundaries, bootstrap, router, themes, configuration, dependency manifest/lock, tests, native ignore files, and platform scaffolding. Runtime dependencies remain Riverpod 3.4.3 and go_router 18.1.1 on Flutter 3.47.7 stable / Dart 3.13.5.

| Check | Actual result on 28 October 2026 |
| --- | --- |
| `git status --short` / `git rev-parse --show-toplevel` | Not a Git repository; local CP-001 baseline commit blocked; nothing staged because no index exists |
| Disk before work (`df -h .`) | Approximately 39 GiB free; CP-001 disk-full condition no longer present |
| Ignore review | Root/native ignore files cover current generated caches, tool configs, local properties, IDE state, plugin registrants, Pods, and Android signing artifacts |
| `flutter analyze` | Passed, no issues found |
| `flutter test` | Passed, all 6 original tests retained |
| `flutter build web` | Passed, output `build/web`; Wasm dry run succeeded |
| Build notices | Existing optional Cupertino font-reference notice and four newer out-of-constraint transitive packages; no new dependency or warning introduced |
| Application/config/test fingerprint comparison | SHA-256 comparison: all 56 recorded application/configuration/test files unchanged |
| Native builds | Not repeated for documentation-only CP-002; CP-001 APK/simulator builds remain prior evidence, not new device/runtime verification |
| Supabase/PostgreSQL/Storage/RLS tests | Not run: no backend provisioned or connected, no migrations authorized |

Shell commands are invoked through `rtk proxy` per the user's RTK instructions. No Git initialization, commit, remote creation, or push occurred. If version control is desired, explicitly authorize local Git initialization and review a baseline before continuing; CP-002 does not infer that authorization from the conditional commit instruction.

## Recommended CP-003 scope (requires approval)

Build the **smallest executable data/security foundation**, not the full couples planner:

1. Resolve [D01–D11](README.md), especially unilateral unlink/archive access, shared-record retention, account-erasure/media behavior, and offline-read risk. Verify target jurisdictions/privacy notice, deployment/version support, and local encryption feasibility before claiming privacy properties.
2. If separately authorized, initialize local Git in this exact directory and commit the CP-001 baseline with reviewed ignore rules. Check staged paths/content for credentials/generated files; keep pubspec.lock. No remote/push by default.
3. Implement minimal pure-Dart identity/scope/revision/Money values and typed outcomes only as needed for the first vertical slice. Preserve app routes/themes/screens and existing tests. Add meaningful money/decimal-string/web-boundary tests, not empty repository stubs.
4. Design and review migrations in an isolated local Supabase/PostgreSQL development environment **only after explicit migration approval**. Start with app_users/profiles, couple_spaces/memberships, invitations, currencies, sync counters/receipts, private helpers, explicit grants/RLS, and lifecycle hooks. Do not start Bucket List, plans, or live production tables.
5. Exercise real verified-identity fixtures and concurrency tests locally: one active couple per account, draft/paired count invariants, double/third invite acceptance, timeout retry, revocation races, and no direct DML bypass. Do not ship a mock-auth flow. Real Auth UI/integration also requires the user's next authorization.
6. Spike Drift persistence/migrations across Android/iOS/web, exact integer codecs, worker deployment, quota failure, encrypted local storage/key lifecycle, and cross-account wipe. Select packages based on verified needs; no premature Storage/notifications dependencies. Native encryption and web confidentiality cannot be assumed equivalent.
7. Prove an end-to-end local-only sync fixture with outbox transactions, commit-ordered scope log, immutable snapshots, conflict handling, receipt-based retry, and membership revocation. Use synthetic test data, not a production couple or fake shipped backend. Avoid a full product module until the protocol is validated.
8. Document evidence and limitations, run existing Flutter checks, review changes, and stop for the next milestone. Connecting any live project, configuring credentials, production migrations, or expanding feature scope needs explicit authorization.

If CP-003 is intended to remain entirely backend-free, limit it to approved domain values and Drift feasibility/tests; do not present RLS/linking security as verified until the database integration work is approved and run.

## Database/security gates before a usable paired space

- Schema constraints: all tenant/parent FKs, immutable fields, row/aggregate revisions, lifecycle states, typed enums, and deletion transitions; catalog inspection of RLS/grants/function execution permissions.
- Concurrency: simultaneous acceptance by same/different recipients, competing create_space, unlink vs accept/write/upload, account deletion vs financial write, and receipt collision with different payload. Use separate real DB connections and verify committed invariants, not single-thread mocks.
- Access matrix: anon, owner, partner, unrelated couple, archived reader, revoked member with old JWT, deleting account, revoked device. Cover reads, projections, CRUD attempts, RPCs, storage paths/derivatives, export artifacts, error messages, and realtime.
- Money: exact exponent parsing, near-limit values, aggregate overflow prevention, same-ID retry, concurrent deposits, competing reversals, reversal of reversal rejection, parent-goal/currency mismatch, and immutable audit fields. Assert no doubles on every serialization/storage path.
- Storage: old authenticated requests after revocation, staging object access, overwrite/copy/upsert denial, MIME spoof, EXIF removal, parent deletion during processing, and orphan cleanup after crashes. Verify actual cache headers and no public/bearer URLs.
- Lifecycle: unblock account exit without partner consent, no archive access for leaver/new partner, retry partial erasure, no resurrection from old queues, privacy-redacted backups/restores and exports. Validate published retention claims against actual hosting settings.

## Sync/local gates before offline writes ship

- Drift write/outbox/overlay atomicity under forced crashes, device full, transaction rollback, browser eviction/private mode, app upgrade, and multiple tabs/workers.
- Migration tests preserve IDs and pending commands; validate all schema upgrades and rollback/recovery strategy before deploying incompatible versions.
- Delayed commit ordering, missed/duplicate realtime hints, paginated transaction boundaries, cursor floor/snapshot fallback, interrupted snapshots, and stale optimistic overlays must converge deterministically.
- Pull authorization on every page and receipt/status query; account/scope change stops pending writes before they are sent. Exercise revoked-member caches and expired leases without promising remote deletion of prior copies.
- Cold start, foreground/background limits, timeout/backoff visibility, pending/conflict UI, row delete vs child insert, independent devices, and exact ledger reconciliation.
- Existing 320/768/1440 layouts at 200% text scaling, theme modes, route recovery, and accessibility checks remain mandatory; add focused coverage only as real behavior is added.

## Outstanding technical/product risks

1. This is a specification: policy correctness and race guarantees need executable PostgreSQL/Supabase tests. No production security certification is implied.
2. Offline access and copies already delivered cannot be instantly revoked. Encryption/browser-origin protection needs a platform feasibility decision; E2EE would require a different key-management/sync design.
3. Indefinite shared archive retention versus erasure requests is a policy conflict requiring consent/legal review. Photo subject rights extend beyond uploader ownership.
4. Serializing per-scope writes is appropriate for two members but long snapshots/deletion batches can block writes. Set and load-test bounded snapshot/command quotas and a measured timeout before rollout; never silently truncate financial history.
5. Auth session/device revocation, reliable deletion jobs, Storage cleanup/caching, notifications, and provider backup retention vary by deployment configuration and need actual integration verification.
6. Timezone database updates, DST/Feb-29 rules, currency catalog changes, and JSON/SQLite integer codecs need versioned compatibility tests across web and native.
7. Browser quota/eviction and OS background restrictions limit durability and sync timeliness. No paid plan or external service automatically solves those constraints.

## CP-002 deliverables and stopping point

Created only `docs/architecture/README.md`, `DATA_MODEL.md`, `SECURITY_MODEL.md`, `PARTNER_LINKING.md`, `OFFLINE_SYNC.md`, `DATA_LIFECYCLE.md`, `APPLICATION_CONTRACTS.md`, and this file; root README gains only an architecture link. No dependencies, application tests/source, or platform configurations are intentionally changed. Final checks: 8 architecture documents, 5 Mermaid diagrams, all local Markdown links/fences valid, approval IDs D01–D11 present. Mermaid text was inspected but not rendered by a diagram engine. `dart format --output=none --set-exit-if-changed lib test` passed (12 files, no changes). Final disk check: about 42 GiB free.

Approval gate: user approval of architecture decisions and CP-003 scope is required before implementing database migrations or authentication. This milestone ends with documentation.
