# Implementation sequence, approval gates, and verification

**Current decision specification:** [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md) is the reconciled source for wording, status, tests, disclosures and implementation gates. D01/D02/D06/D09 are approved; D03’s recorded revision and unresolved P03/P04/P09 choices are preserved. Other technical directions remain pending formal approval. No backend implementation is authorized by this documentation update.

## Current CP-006 readiness

See [CP-006 readiness and implementation plan](../CP-006.md). D06 and D09 policy decisions are formally approved, so a bounded partner-linking implementation can be planned without re-approval of those policies. The CP-004 proofs are references only. In particular, CP-004A's draft-record read behavior must not be copied; unpaired planner data is now expressly denied. P03/P04/P09 continue to block archived-content, ordinary-recovery and audit-retention surfaces. This document update does not itself authorize implementation.

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

## Historical CP-004 recommendation from CP-003B

The Flutter foundation and approved CP-003A UI remain unchanged. [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md) supersedes earlier implementation recommendations and defines the current formal-approval and product gates. No migration/Auth/backend work begins in this documentation task.

1. Formally approve endorsed directions and resolve P03/P04/P09. Approve concrete archive/ordinary-text/audit policy values, classifications/review and disclosures. D01/D02 need no reapproval; D03's revision remains recorded with implementation details incomplete.
2. First separately authorized backend milestone: isolated local synthetic-data identity/scope authorization proof. Review account-state gate, unique active membership/two seats, draft/paired/closed transitions, canonical locking and atomic single-use invite/idempotency. Prove RLS/grant isolation, concurrency and old-JWT denial before integrating UI or a live project.
3. Include epoch/first-closure/account-denial seams; keep unavailable archive/export/content paths denied. Do not implement placeholder 365-day retention or blanket survivor deletion to bypass product gates.
4. Prove protected native persistence/key/temp/media/credential lifecycle; initial sensitive web remains online/session-memory without a durable sensitive outbox. A new verified browser persistence design needs separate approval. No dependency is added by this review.
5. After policy approval, stage ownership-aware content and exact ledger separation, privacy reset/cleanup/restore, authenticated media and export as small tested slices. Preserve current Riverpod/go_router/visual layout and run regression checks when actual code changes are separately authorized.

Readiness is conditional for an explicitly scoped isolated foundation slice, **not** full schema freeze, production deployment or unapproved archive/deletion behavior. All future security gates below still apply. Historical CP-002 baseline statements above describe that earlier milestone, not current Git state.

## Database/security gates before a usable paired space

- Schema constraints: all tenant/parent FKs, immutable fields, row/aggregate revisions, lifecycle states, typed enums, and deletion transitions; catalog inspection of RLS/grants/function execution permissions.
- Concurrency: simultaneous acceptance by same/different recipients, competing create_space, unlink vs accept/write/upload, account deletion vs financial write, and receipt collision with different payload. Use separate real DB connections and verify committed invariants, not single-thread mocks.
- Access matrix: anon, owner, partner, unrelated couple, archived reader, revoked member with old JWT, deleting account, revoked device. Cover reads, projections, CRUD attempts, RPCs, storage paths/derivatives, export artifacts, error messages, and realtime.
- Money: exact exponent parsing, near-limit values, aggregate overflow prevention, same-ID retry, concurrent deposits, competing reversals, reversal of reversal rejection, parent-goal/currency mismatch, and immutable audit fields. Assert no doubles on every serialization/storage path.
- Storage: old authenticated requests after revocation, staging object access, overwrite/copy/upsert denial, MIME spoof, EXIF removal, parent deletion during processing, and orphan cleanup after crashes. Verify actual cache headers and no public/bearer URLs.
- Lifecycle: unblock account exit without partner consent, no archive access for leaver/new partner, retry partial erasure, no resurrection from old queues, privacy-redacted backups/restores and exports. Validate published retention claims against actual hosting settings.

## Sync/local gates before offline writes ship

- Drift write/outbox/overlay atomicity under forced crashes, device full, transaction rollback, native app upgrade and worker coordination; web tests verify no sensitive durable persistence and honest unsaved-state handling.
- Migration tests preserve IDs and pending commands; validate all schema upgrades and rollback/recovery strategy before deploying incompatible versions.
- Delayed commit ordering, missed/duplicate realtime hints, paginated transaction boundaries, cursor floor/snapshot fallback, interrupted snapshots, and stale optimistic overlays must converge deterministically.
- Pull authorization on every page and receipt/status query; account/scope change stops pending writes before they are sent. Exercise revoked-member caches and expired leases without promising remote deletion of prior copies.
- Cold start, foreground/background limits, timeout/backoff visibility, pending/conflict UI, row delete vs child insert, independent devices, and exact ledger reconciliation.
- Existing 320/768/1440 layouts at 200% text scaling, theme modes, route recovery, and accessibility checks remain mandatory; add focused coverage only as real behavior is added.

## Outstanding technical/product risks

1. This is a specification: policy correctness and race guarantees need executable PostgreSQL/Supabase tests. No production security certification is implied.
2. Offline access and copies already delivered cannot be instantly revoked. Encryption/browser-origin protection needs a platform feasibility decision; E2EE would require a different key-management/sync design.
3. Indefinite default shared-content retention has been rejected as an assumption by revised D03. Technical directions for audit minimization/pseudonyms/media/export/recovery/copy cleanup are endorsed pending formal approval. Revised P03/P04/P09 remain unresolved product gates; ownership-aware archives must preserve eligible survivor records and subject privacy. No automatic 365-day audit duration.
4. Serializing per-scope writes is appropriate for two members but long snapshots/deletion batches can block writes. Set and load-test bounded snapshot/command quotas and a measured timeout before rollout; never silently truncate financial history.
5. Auth session/device revocation, reliable deletion jobs, Storage cleanup/caching, notifications, and provider backup retention vary by deployment configuration and need actual integration verification.
6. Timezone database updates, DST/Feb-29 rules, currency catalog changes, and JSON/SQLite integer codecs need versioned compatibility tests across web and native.
7. Browser quota/eviction and OS background restrictions limit durability and sync timeliness. No paid plan or external service automatically solves those constraints.

## CP-002 deliverables and stopping point

Created only `docs/architecture/README.md`, `DATA_MODEL.md`, `SECURITY_MODEL.md`, `PARTNER_LINKING.md`, `OFFLINE_SYNC.md`, `DATA_LIFECYCLE.md`, `APPLICATION_CONTRACTS.md`, and this file; root README gains only an architecture link. No dependencies, application tests/source, or platform configurations are intentionally changed. Final checks: 8 architecture documents, 5 Mermaid diagrams, all local Markdown links/fences valid, approval IDs D01–D11 present. Mermaid text was inspected but not rendered by a diagram engine. `dart format --output=none --set-exit-if-changed lib test` passed (12 files, no changes). Final disk check: about 42 GiB free.

Approval gate: user approval of architecture decisions and CP-003 scope is required before implementing database migrations or authentication. This milestone ends with documentation.

## CP-003B Part 1 documentation checkpoint

D01–D03 policy resolution supersedes incompatible CP-002 assumptions. Do not reopen D01's active limits as if unapproved, turn D02's conditional archive into an automatic full-content grant, or preserve contribution notes/all shared text indefinitely under D03. Complete P01–P09 and later D04–D11 resolution through separate authorized work before the affected implementation. No migration, Supabase/Auth work, Flutter change, commit or next decision part is authorized by this checkpoint.

## Current reconciliation checkpoint

See the consolidated specification for 20 decision statuses, ownership/deletion matrix, per-decision tests and ten contradiction dispositions. Historical CP-002/Part 1 stopping records above are preserved; they do not override the current technical endorsements or authorize implementation. No commit/push or application change is part of this reconciliation.
