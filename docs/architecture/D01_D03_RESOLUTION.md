# CP-003B · Architecture approval resolution, Part 1

> **Historical decision record.** The body below preserves this review stage and its then-current statuses. CP-006 later formally approved D06 and D09 only; it did not change D01/D02 or resolve D03/P01–P09. See the current [decision specification](DECISION_SPECIFICATION.md) and [CP-006 approval addendum](APPROVAL_REVIEW.md). The latest user directions and reconciled proposals are in the decision specification. Earlier blanket nonfinancial deletion, no-text-recovery and automatic 365-day audit recommendations are superseded there; they are not current policy.

This record captures the user's D01–D03 decisions verbatim. It supersedes incompatible CP-002 proposals and prior advisory recommendations. It is a documentation resolution, not permission to implement a database, backend, authentication, linking, or Flutter changes. The approved CP-003A visual design remains unchanged.

## Recorded product decisions

### D01 — Approved

> One active couple space per account, maximum two active members. Archived spaces cannot be reopened or reused with a replacement partner.

This fixes the active-space uniqueness and maximum active-member boundary. Archived entitlements do not count as active membership and cannot expose historical data to a replacement/new partner. The existing draft/paired state names, exactly-one/exactly-two state counts, and two historical seats are still proposed implementation details; D01 does not independently approve every preliminary state-machine restriction or D09's draft-writing rule. No archive may be reopened or reused to circumvent the active-space limit.

### D02 — Approved with safeguards

> Either partner may unlink independently. The departing partner immediately loses server access. The remaining partner may receive a read-only archive, subject to the D03 privacy and retention rules. Do not claim that previously downloaded data can be remotely erased.

The immediate access loss concerns the departing user's former couple scope: database reads/writes, media, exports, RPCs and future shared updates. It does not erase their unrelated account data or grant the other partner indefinite ownership. Server access revocation must not depend on partner consent or export completion. Requests already in flight and copies already delivered cannot be reliably recalled. Cooperative clients should purge revoked caches when they learn of revocation; this is best effort, not a remote-erasure guarantee.

“May receive” is conditional. An archive state/entitlement is not blanket authorization to retain/read/export every historical record. Its content, eligibility, retention and expiry must satisfy the unresolved D03 rules before implementation. Do not silently substitute either indefinite retention or immediate destruction for an undecided policy.

### D03 — Revised policy for documentation

> Preserve only necessary, auditable contribution history with pseudonymized attribution after account deletion. Shared text, notes, and photographs must have a clearly documented removal, retention, and export process. Do not assume indefinite retention of all shared content.

This replaces the earlier assumption that all shared text and full financial rows remain for the life of the remaining partner's archive. Only necessary auditable contribution history receives the stated preservation treatment; that does not establish an unlimited retention period. Free-text contribution notes, goal names/descriptions, original identity labels, photo captions, media and general activity content are not automatically necessary audit data. Pseudonymized history must not be described as anonymous or unlinkable.

The monetary audit core must remain accurate: amounts, currency interpretation, correction/reversal relationships and integrity evidence cannot be falsified by privacy cleanup. Privacy redaction of nonessential text/identifiers is a separate controlled lifecycle action, not an ordinary ledger edit. The precise retained field set, pseudonym scheme, audience and time horizon remain unresolved below. This is a recorded revised policy, **not approval of a complete erasure implementation**.

## Unresolved privacy choices — no defaults selected

All P01–P09 are open. Candidate approaches describe options, not approved behavior. Resolve each before implementing the affected schema, access rule, export, deletion job, or retention configuration.

| ID | Choice still required | Options / implications | Implementation gate |
| --- | --- | --- | --- |
| P01 | Minimal retained contribution audit fields | Review transaction IDs, exact minor-unit amount/currency/exponent, correction links, goal reference and time precision individually. Free-text notes and human-readable context need a separate removal/retention decision, not automatic inclusion | Ledger/goal schema and export/redaction contracts |
| P02 | Pseudonym generation and identity-link retention | Per-space versus per-record pseudonyms; whether any reidentification mapping survives, who can access it, and when it is erased. Existing member UUIDs alone are not proof of anonymization | Identity FKs, audit attribution and access controls |
| P03 | Conditional archive eligibility, audience and expiry | Determine what the remaining partner may read after unlinking and after account deletion, whether a reduced financial-only archive exists, when access ends, and how the last reader's deletion affects it | Archive membership/read/export predicates; no blanket content grant |
| P04 | Text and note removal / retention | Specify triggers, ownership/collaborative-edit treatment, per-class deadlines, disclosure and conflict handling. Options include removal, bounded retention or an explicit export window; indefinite default retention is excluded | Planner bodies, contribution notes, captions, search and activity lifecycle |
| P05 | Photograph and depicted-person treatment | Resolve uploader versus depicted-person requests, jointly supplied media, captions/EXIF, thumbnails, staging and derived objects; uploader-only deletion is not a complete policy | Attachment model, Storage eligibility and cleanup jobs |
| P06 | Export eligibility and timing | Specify what a user may export before unlink/deletion, whether a bounded window exists, exact content/redactions and generated-artifact expiry. Any separately verified privacy-access process must not restore former couple access | Export schemas/jobs/download authorization and exit UX |
| P07 | Grace, cancellation and irreversible removal | Reconcile content hiding, physical deletion and recovery expectations with still-pending D04/D10. Do not assume immediate photo purge or a 30-day recovery promise from this resolution | Deletion states/jobs, cancellation contract and disclosures |
| P08 | Secondary copies and deletion completion evidence | Choose redaction/reset handling for sync after-images, snapshots, receipts, activity, search, server caches, issued media/export links, exports, object derivatives, logs and backups; establish measurable cleanup/restore rules | Sync-retention protocol, erasure worker and deployment configuration |
| P09 | Audit-history necessity horizon and final purge | Decide duration, expiry triggers, authorized readers, zero-reader-space handling and any reviewed exceptional retention basis. “Auditable” does not mean keep forever | Ledger retention, zero-reader purge and backup lifecycle |

At the time this D01–D03 record was prepared, no durations in this table were approved and D04–D11 retained their original proposals. CP-006 later approved D06/D09 policy wording only; proposed 90-day logs, seven-day offline leases, 24-hour media/export targets and 30-day deletion grace remain unapproved unless separately resolved. Selecting a number by copying it from CP-002 would silently decide an unresolved policy.

## Documentation requirements for the future lifecycle

Each content class must have an approved retention purpose, audience, trigger, readable-until point, removal/redaction deadline, physical-cleanup target and export rule. Cover shared text, notes (including contribution notes), photos/captions/derivatives, minimal contribution history and operational copies separately. Until P01–P09 are resolved, this is a required policy matrix with open values, not a deployable lifecycle.

Removal process must identify authorized requests, scope affected records and derived copies, stop unauthorized serving, execute revisioned redaction/tombstones, invalidate stale exports/snapshots, retry byte cleanup, and report honest completion/backup limits. Export must use the then-approved content allowlist and current access at request, generation and download; a stored archive label is insufficient. Neither process may make unilateral unlinking depend on consent from the other partner.

D03 also applies to financial notes and old synchronization payloads. Keeping an immutable after-image or backup copy cannot be used to bypass approved erasure. A future protocol may require history redaction and/or scope snapshot invalidation; the mechanism and deadlines are not selected here. Previously downloaded copies remain outside reliable remote erasure under D02.

## Scope and stopping point

D01 is approved; D02 is approved with safeguards; D03's revised policy is recorded with P01–P09 unresolved. D04–D11 are not resolved in this part. No policy approval here authorizes migrations, Supabase configuration, authentication, Flutter changes, or an additional Git commit. Stop after the documentation consistency review.

## Documentation verification

- D01–D03 user wording matched verbatim in this record, the current register and approval review.
- D04–D11 proposed register rows and review sections remained byte-for-byte unchanged.
- All nine P01–P09 choices remain explicitly open; no retention duration, archive audience, pseudonym scheme or deletion/export window was selected.
- Local Markdown links, table column counts and code-fence balance passed; five Mermaid text blocks remain (not rendered by a diagram engine).
- Obsolete blanket shared-text retention and immutable-note/full-row-audit assumptions were checked and removed from current architecture specifications.
- All 120 tracked application/platform/design files matched their initial fingerprints. Only 11 Markdown files changed, and Git HEAD remained at the approved CP-003A commit.
- `git diff --check` passed. Flutter analysis/tests/build were not rerun for documentation-only changes; no runtime behavior was changed or revalidated in this part.
- Changes remain uncommitted. No database migrations, Supabase connection, authentication, additional product decision part or deployment was performed.
