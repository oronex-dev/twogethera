# Consolidated architecture decision specification · Private Beta V1

**Current policy record — Private Beta V1, 8 November 2026.** This addendum records the user's approved product-policy scope for a controlled beta with exactly two existing partner accounts. Policy approval is not proof that the software, provider, cleanup jobs, backups, or restore process satisfy the policy. Numerical values below are **approved targets**, not guaranteed deadlines until verified end to end.

The beta includes Bucket List, Important Dates, Plans/itineraries, Budget/expenses, recurring expenses, appearance/personalization, and profile management. Profile photos remain disabled until their complete private-storage verification gate passes. Savings, notifications, offline sync, self-service unified export, public registration, unrestricted invitations/onboarding, multi-couple rollout, and survivor archive UI are deferred. No E2EE claim is permitted.

## Approved Private Beta V1 policies

| Area | Approved policy | Technical status / limit |
| --- | --- | --- |
| Couple and beta access (D01, D02, D06, D09) | Exactly the two existing partner accounts; no public registration or unrestricted onboarding. Closure/unlink revokes both partners immediately, creates no survivor archive, and never reuses the archived space; a later new space is subject to the two-account gate. Downloaded copies cannot be remotely erased. | Additive migration 028 enforces a two-user allowlist and close transaction. Account UI and server RPC are implemented locally. The local allowlist contains only the two existing synthetic beta identities; hosted identity enrollment remains a controlled operator action. |
| Shared data and nonfinancial retention (D03/P03) | Purge shared nonfinancial primary copies within a **30-day target** after immutable couple closure. Both users lose server access immediately. | Migration 028 creates manifest-backed purge jobs; Edge maintenance worker exists but is not scheduled or provider-verified. The target is not guaranteed until hosted scheduling, failure alerts, Storage cleanup and restore behavior pass. |
| Financial audit (P01/P02/P09) | Retain only the approved minimized allowlist for **90 days from immutable couple closure**, attributed by random per-couple aliases. Exclude splits, payer aliases, direct identifiers, text, receipts, recurrence, and unnecessary timestamps. Former partners cannot read audit rows. | Migration 028 captures prospective expense events in a private append-only projection; migrations 030/031 add currency and retry guards. No direct API-role access. The purge worker is implemented but unscheduled. Existing pre-migration rows are not backfilled; historical edits cannot be reconstructed. |
| Ordinary deletion and privacy removal (P04) | Ordinary shared-text delete hides immediately and either currently paired partner may restore within **7 days**. Privacy removal hides immediately, cannot be restored, and has a **24-hour primary-copy purge target**; preserve safe separated content, otherwise remove the smallest shared record for both. | Migrations 028/030 implement tombstones, privacy blocks and cleanup jobs. Migration 030 exposes recovery metadata and corrects goal-child job cancellation. Account, planner, budget and memory UI expose privacy removal; the purge worker is not scheduled or failure-alerted. |
| Account deletion/recovery (P07/D10) | Deletion irreversibly closes the whole couple, immediately denies both partners, has no archive and no account recovery. Starts 30-day nonfinancial and 90-day minimized-audit targets. Reauthentication required; former downloads cannot be erased remotely. | Migration 028 and `delete-account` Edge Function implement close-first, retryable Auth deletion; migration 029 lets maintenance claim due retries. UI requires typing DELETE and signs out on 200/202. End-to-end managed Auth deletion and worker retry are not verified. |
| Backups and restore (P08/D04) | A **30-day maximum backup target** is conditional on provider support. Restores must replay deletion/privacy state before any API access. | No provider backup-retention or restore gate/replay mechanism is configured or verified. This remains a release blocker; application code cannot prove or enforce provider snapshots. |
| Profile photos (D07) | Private authenticated access only. Keep profile photo functions disabled until full authorization, upload/reload, revocation, and object/derivative cleanup tests pass. | Flutter controls are disabled and migration 028 adds restrictive denial; existing objects were not deleted. Re-enable only after actual managed Storage round trip and cleanup-failure tests. |
| Export (P06) | No self-service export. Support-assisted export is unavailable until a real contact, named operators, identity verification, and encrypted delivery/expiry/deletion workflow are configured and tested. | No endpoint is advertised or enabled. Existing proposal below is a runbook design only, not an available service. |
| Offline and web session (D04/D08) | No offline synchronization or durable sensitive browser storage. Web users sign in again after refresh/close; unsynced changes may be lost. No E2EE claim. | Auth remains memory-only; web build removes Flutter's offline worker and bootstrap clears old service workers/cache. Automated checks exist; deployed browser verification is still required. |
| Deferred features (D05 and beta scope) | Savings Tracker, notifications/token collection, offline sync, self-service unified export, public signup/unrestricted onboarding, multi-couple rollout, and survivor archive UI are out of V1. Future notifications must be opt-in with generic lock-screen content. | Do not expose or enable deferred entry points/services in the beta. Existing Budget/expense functionality remains in scope and keeps exact minor-unit money semantics. |
| Recurrence (D11) | Date-only annual dates remain civil dates. Monthly recurrence clamps to the last valid day; Feb. 29 recurs on Feb. 28 in non-leap years. Timed plans store an instant and explicit IANA timezone. DST scheduling, external calendar integration, and RRULE support are deferred. | Existing expense recurrence clamps dates; timed-plan schema/runtime timezone handling and Important Dates parity require verification. |
| Legal documents | Privacy Policy and Terms remain drafts until counsel/product review and approval. Do not claim legal compliance. | In-app documents remain marked drafts. Responsible entity, contact, jurisdiction, and final lifecycle disclosure must be supplied before the two partner accounts use real personal data. |

### Approved targets are not guarantees

The 30-day nonfinancial purge after closure, 90-day minimized financial audit retention, 7-day ordinary recovery, 24-hour primary purge after privacy removal, and conditional 30-day maximum backup target are approved policy targets, not guaranteed deadlines. Account recovery is explicitly not offered in V1. Previously downloaded or in-flight bytes remain outside reliable remote erasure.

### Approved financial audit field mapping and implementation status

The user approved the exact retained-field allowlist below. The source is `couple_expenses` in `supabase/migrations/20261102000900_shared_budget_expenses.sql`; relevant row triggers are in migrations 011 and 028. Existing source columns are `id`, `couple_id`, `budget_id`, `title`, `description`, `amount_minor`, `currency_code`, `currency_exponent`, `occurred_on`, `category_key`, `paid_by_user`, `split_mode`, `split_a_user_id`, `split_a_minor`, `split_b_user_id`, `split_b_minor`, `recurring_rule_id`, `recurrence_key`, `receipt_count`, `created_by`, `updated_by`, `created_at`, `updated_at`, and `revision`. Existing rows do not contain a financial event history.

| Audit field | Existing source column | Transformation | Purpose | Privacy risk |
| --- | --- | --- | --- | --- |
| `audit_event_id` | None | New random UUID, never derived from an expense ID | Identify one immutable audit event | Low; random identifier still permits event-level linkage |
| `opaque_couple_ref` | `couple_id` only as an in-transaction input | New random per-couple UUID; source mapping removed at closure | Group events for the fixed retention window | Low-to-moderate; events correlate within one couple |
| `event_type` | Operation context | Fixed enum: `recorded`, `corrected`, `reversed` | Explain the financial event action | Low; no user-supplied text |
| `actor_alias` | Verified `auth.uid()` at the event | Random alias scoped to couple; identity map is private and deleted at closure | Attribute a new event without a retained account ID | Moderate; events link to the same pseudonym within this couple |
| `amount_minor` | `amount_minor` | Signed integer: positive record, signed amount delta for correction, negative amount for reversal | Preserve exact amount facts | Moderate; amount can reveal behavior |
| `currency_code`, `currency_exponent` | Same-named source columns | Copy validated ISO code and exponent; source currency cannot change after record | Interpret integer amounts exactly | Low-to-moderate; may contribute to inference |
| `effective_date` | `occurred_on` | Copy civil date; no timestamp conversion | Preserve date-level financial context | Moderate; dates can reveal routines |
| `event_sequence` | None | Monotonic generated sequence within the opaque couple scope | Deterministic event order | Low; reveals relative order only |
| `schema_version` | None | Generated constant `1` | Interpret the stable projection format | Low |
| `correction_reference` | None | Nullable FK to the prior generated `audit_event_id` only | Relate a signed correction/reversal to the previous retained event | Low-to-moderate; reveals a financial event relationship |

The implementation uses `app_private.financial_audit_events`, a private append-only table with no authenticated/API role read access. Trigger capture is prospective; it does not invent or backfill pre-migration history. The current `couple_expenses` schema cannot reconstruct previous amounts, editor history, or the time of earlier edits. Thus only events captured after the audit trigger is installed are represented; this is not a complete audit of earlier row history. The audit purge deadline is anchored to immutable server `couple_spaces.closed_at + 90 days`. The cleanup worker is written but no scheduler/alerting is configured, so physical expiry is not currently guaranteed.

Explicit exclusions: split amounts, split participant aliases, payer aliases, `id`, direct user/account IDs, email, profile data, `title`, `description`, receipts/object paths, recurrence references, `category_key`, budget links/limits, `split_mode`, `receipt_count`, `created_at`, `updated_at`, `revision`, and all unnecessary metadata. `created_by`, `updated_by`, `paid_by_user`, split-user IDs, and source `id` are not retained; source identifiers are not hashed. Currency unit changes are rejected after an expense is recorded so a signed correction never subtracts values expressed in different units.

Correction/idempotency design: a correction appends a new immutable signed delta referring only to the preceding generated audit event ID. A reversal appends the negative amount and generated reference. A private live-only `financial_audit_heads` mapping supports source-row deduplication while the couple is active and is deleted with the private couple scope at closure; it is not part of retained events. Database transaction and row triggers ensure retries of a source mutation do not append a duplicate event. The initial closure operation is idempotent and returns the same immutable closure timestamp on retry.

Retention clock: starts at the first server-set `closed_at`; it cannot be reset by retry, account deletion, or restore. `purge_expired_financial_audit()` is service-role-only and removes all events at or after `closed_at + 90 days`. Provider backups can retain inaccessible bytes longer; the provider's backup aging, restore replay, and purge behavior remain unverified. No statutory retention rule is inferred.

**Approved policy; implemented locally; not yet fully verified.** Exact audit field list, correction rule, no-split/no-payer choice, and 90-day-after-closure period are approved. Local managed-role/API, closure, mutation capture, and purge-boundary proofs still need to pass; historic event gaps remain an explicit limitation.

### Approved privacy-removal policy and implementation requirements

The policy is approved: privacy removal is distinct from ordinary deletion; separable personal information is removed or redacted while safe shared records are preserved. If content is inseparable, remove the smallest affected record for both partners. After an authorized request, hide the affected content immediately, never restore it, and target primary-copy purge within 24 hours. Financial records may retain only the separately approved minimized audit information, subject to legal review. Operational logs contain only content-free processing metadata. These are policy targets, not verified technical guarantees; backups and previously downloaded copies are not represented as remotely erased.

| Data category | Proposed behavior | What remains / boundary |
| --- | --- | --- |
| Private profile fields and personal appearance preferences | Owner may request removal/reset; immediately blank or block the affected field and revoke its media pointer. Require current identity; recent reauthentication for broad account-level removal. | Remove only that user's profile/preferences. Do not affect the partner's private profile or theme. |
| A user's authored text in a shared memory, plan/task, note, or other shared prose | Remove/redact the eligible personal contribution when it is safely separable. If it is inseparable, immediately hide then remove the smallest affected record for both partners. | Never retain removed free text for audit; no restore. Preserve other safe records. |
| Shared photos and attachments depicting or identifying a requester | Immediately revoke pointers and deny reads; remove the smallest affected attachment for both partners if the image/content is inseparable. Purge original and known derivatives. | No restore. Storage, cache, derivative, and backup cleanup remain unverified. Photo flows remain disabled until their verification gate passes. |
| Budget and expense prose / receipts | Hide and remove affected text and receipt objects; invalidate access paths and purge Storage objects/known derivatives. | Receipt images/paths are excluded from financial audit. Do not retain notes/descriptions for audit. |
| Financial facts (amount, currency, date, correction integrity) | Do not silently rewrite shared financial facts as part of prose removal. Retain only the user-approved minimized audit allowlist, subject to legal review. | The policy/field allowlist is approved; local capture and purge behavior still require verification. No legal hold is inferred. |
| Shared structured facts (date, location, category, checklist/status, goal/milestone state) | Remove/redact separable personal information while preserving safe shared records. If inseparable, immediately hide and remove the smallest affected record for both partners. | No restore; avoid changing unrelated records or corrupting safe shared history. |
| Operational request metadata | Retain only opaque request/target reference, fixed reason code, processing state, and timestamps needed for execution/retry. | Content-free metadata only. Exact operational log retention and access controls remain implementation details to define and test. |

The policy approval is not legal advice. Counsel must assess applicable rights and any narrow mandatory financial-record requirements in the actual jurisdiction; no such obligation or compliance status is assumed here.

### Support-assisted export — operational proposal awaiting approval

1. **Request:** The user requests an export through a support contact/channel configured by the owner. No email address or channel is implied by this specification. Record only a request ID, requesting account reference, requested scope, status, and timestamps.
2. **Verify identity and access:** Require the user to authenticate in the app and confirm through a separately verified channel configured for the beta. Support checks current account status and current membership at request acceptance, export generation, and delivery. A closed/unlinked or deletion-pending account receives no shared-space export. Support does not use partner credentials or impersonate either user.
3. **Scope and contents:** Export only the requester's own private profile/preferences and the shared records they are currently authorized to read: Bucket List, Important Dates, Plans/tasks, and active shared budget/expense data. Exclude the partner's private profile/preferences and account identifiers, internal security metadata, invitation secrets, session/token data, privacy-removed content, closed-space archives, and the post-closure financial audit projection. Exclude profile/receipt media until the private-media workflow is verified and specifically approved for export. Use a documented versioned format and minimize fields to the current user-facing data needed.
4. **Generate and deliver:** Generate in a restricted worker with least privilege and no broad service key in client code. Encrypt the temporary artifact at rest; deliver only through a short-lived, single-recipient authenticated download or another secure method explicitly configured by the owner. Recheck access immediately before making it available. Do not put export links or contents in ordinary email or application logs.
5. **Expire and delete:** Proposed default is a 24-hour download window, one successful download, and automatic deletion of the temporary artifact and working copies at expiry or after download. This duration and delivery method require approval and a test proving deletion; until then, support export is not an available beta promise.
6. **Support controls:** Restrict the operation to named, individually authenticated support operators with least-privilege, time-bounded access and an auditable approval/action record. Log operator identity, request ID, scope code, timestamps, and outcome only—not export contents or unnecessary personal narrative. Review access logs periodically and revoke operator access when no longer needed.

**Approval required:** Configure the contact channel, verify method, response expectation, artifact format, download window, operator list, and operational-log retention. The proposal does not grant support access to former-partner data or authorize a survivor archive.

### Privacy-removal verification and implementation requirements

1. Require a current authenticated identity. The server derives `auth.uid()` and checks the account gate and applicable current ownership/membership; a client-supplied user ID or ownership flag never establishes authority. Do not require partner consent for a request to remove the requesting person's own eligible personal information.
2. Require explicit confirmation of the exact content unit(s) and removal class. For account deletion or a broad/irreversible request, require recent reauthentication. A narrow removal of the requester's own profile field can use a valid session plus confirmation; a former member uses a verified support channel without regaining couple access.
3. Commit an idempotent request ID, target opaque IDs, policy reason code, server timestamp, and privacy-generation/block marker in one transaction. Do not copy the removed text, image, token, or request narrative into the job/audit log. Rate-limit by account and operation class; retries return the same request outcome and do not reset deadlines.
4. Immediately deny reads for the affected content unit across RLS, RPC, search, activity, Storage paths, signed/cache routes, export, and stale sync snapshots. Queue purge of primary and derived copies, retry failures, and alert on missed targets. Keep only restricted operational evidence (request ID, scope, status/timestamps, non-content reason code) for a separately approved operational retention period.
5. For shared content containing both partners' information, redact the requester's eligible information where safe. If the affected unit is inseparable, immediately hide and remove the smallest affected record for both partners; never quarantine it for later restoration. Financial facts follow only the separately approved audit allowlist; do not retain text or silently rewrite financial history to satisfy a text request.

**Tests required:** owner and former-member request paths; unrelated-account denial; client-ID spoofing; no partner-consent dependency for eligible own data; request enumeration resistance; idempotent retry; rate limits; immediate cross-surface block; ordinary-restore race loses to privacy removal; cleanup retry/alert; no removed content in operational logs; financial projection remains exact while excluded personal fields disappear.

**Legal question, not inferred here:** whether any specific financial record must be retained under the applicable jurisdiction. Obtain jurisdiction-specific review; do not create a legal hold by assumption.

### Approved account-deletion policy and implementation status

Account deletion is irreversible in Private Beta V1. It closes the entire couple space, immediately denies both members, creates no archive, and does not offer private-account recovery. Reauthentication is required; previously downloaded or in-flight copies cannot be remotely erased. No membership or shared content is restored.

1. Reauthenticate and submit an idempotent deletion request. In a transaction, mark the account deletion-pending in the authoritative account gate, deny new operations immediately, revoke refresh/device sessions, and invalidate pending commands/exports. Existing access JWTs must fail the account-state check; token revocation alone is insufficient.
2. If the account is an active member, atomically close/unlink the couple using the no-archive V1 rule. Both partners immediately lose shared server access; the remaining partner does not become an archive reader. Set one immutable server `closed_at` used for the 30-day nonfinancial purge target and 90-day financial audit clock. Existing privacy-removal blocks are never cleared.
3. Process Auth identity deletion only after the shared-space close and private-data deletion request have committed. A failed external Auth deletion remains inaccessible and retryable; it must never reopen the account or couple.
4. Remove the active identity-to-alias mapping at closure, finish nonfinancial primary cleanup by the 30-day target, and retain only the allowlisted inaccessible audit projection until its 90-day expiry. Earlier privacy-removal deadlines always win.
5. Store deletion/revocation replay state outside the snapshot being restored, or otherwise prove it survives restoration of an older snapshot. Before restored services/API traffic are enabled, replay it, enforce current account/membership/privacy epochs, suppress blocked content, and run a post-restore verification. A rolling 30-day backup window may leave inaccessible residual bytes beyond primary purge; provider behavior and the user-facing residual-copy disclosure must be verified.

**Tests required:** request versus concurrent write/unlink; both partners denied after closure with old JWTs; repeated closure/deletion operations; deletion cannot restore membership/content; privacy removal survives restore; correct 30-/90-day clocks are not reset by retries; Auth deletion ordering; account IDs/notes absent from retained audit; restore gate fails closed when replay is unavailable.

### Policy-to-implementation assessment

**Current Private Beta V1 status (controlling; supersedes this historical assessment where it differs):**

| Status | Policy areas | Evidence and limit |
| --- | --- | --- |
| Previously verified locally, bounded proof | D01/D06/D09 membership and invitations; paired-only planner/financial RLS; integer minor-unit money; appearance owner isolation; private Storage authorization; recurrence uniqueness; Date Night/Goal CAS and lifecycle guards. | Existing migrations 001–027 and proofs are historical evidence, not proof of new lifecycle behavior or managed hosting. |
| Implemented locally; final verification incomplete | Two-account allowlist, closed signup, couple closure, irreversible deletion request, ordinary restore, privacy blocks/redaction, minimized audit, and worker queue in migrations 028–030 with UI/Edge Functions. | Migration 031 and CP-013 database proof remain pending after local PostgreSQL stopped responding. Maintenance scheduling/alerts, Storage cleanup, managed Auth deletion and restore replay remain unverified. |
| Intentionally disabled | Profile photos, public registration, export, offline sync, durable web sessions, Savings, notifications, unrestricted invitations. | Keep disabled until their scoped operational/security release gates pass. |
| Provider/legal blockers | Backup aging and restore replay, managed-role migration compatibility, hosted Auth restrictions, SMTP, schedule/alerts, final legal terms and support operation. | No hosted services were accessed. These require isolated staging, provider configuration and legal review. |

The following CP-003B rows and sequence are retained as historical planning evidence only; they do not describe current implementation status.

| Status | Policy areas | Evidence and limit |
| --- | --- | --- |
| Historical CP-003B assessment | Earlier proposal-time status for D01–D11/P01–P09. | Preserved as history; current controlling implementation status appears above. |
| Provider-dependent / cannot be verified locally | Managed Supabase grants/migration behavior; hosted Auth restriction; actual backup aging and restore; Storage derivative cleanup; production cache controls; final legal entity/contact/jurisdiction; browser-only workflows. | Requires isolated managed staging, provider-side evidence, human legal review, and manual UI testing. No hosted system was accessed. |

### Historical CP-003B implementation sequence

The following older sequence is preserved as decision history and is not the current implementation plan.

1. **Recover local verification safely:** apply pending migration 031 without resetting data, run the rollback-only CP-013 proof, then focused Flutter checks and Web release build.
2. **Complete lifecycle proofs:** test stale JWTs, closure/write races, retries, privacy blocks, retention boundaries, Auth deletion retry and Storage cleanup failure.
3. **Verify isolated managed staging:** dry-run migrations in order; configure the exact two users, disable signup/invites at provider and database layers; validate RLS, Auth, SMTP, Edge Functions and private Storage.
4. **Prove operations:** configure maintenance scheduling/alerts and perform a quarantined restore/replay drill; verify backup aging and rollback.
5. **Finish manual UI/legal gates:** two-account responsive review, destructive-action disclosures, counsel-approved legal documents, entity/contact/jurisdiction and the support process.

### Genuine user decisions and technical gates still open

- **Support-export configuration:** Set a real support contact, named operators, identity verification, response target, secure delivery, temporary expiry and verified deletion process. No contact is assumed.
- **Operational/legal question — pending review:** Counsel and infrastructure owners must verify jurisdiction-specific financial retention, actual provider backup/delete behavior, and maximum residual-copy time. No legal requirement is presumed.
- **Operational detail — pending:** Define access controls and a retention duration for minimal privacy-request processing metadata, plus the responsible owner/alert path for purge failures. The content-removal behavior and 24-hour target are approved policy, not pending product decisions.
- **Provider gate:** Verify whether 30-day backups and restore-time replay can meet the approved targets; document maximum residual-copy time if backups contain rows past primary purge.
- **Legal review:** Confirm applicable financial-record duties, privacy-request rights, entity/contact, and jurisdiction with qualified counsel. No legal requirement or compliance status is asserted here.

Account deletion recovery is not offered in V1. Either currently paired partner may restore ordinary shared text only within the seven-day window through the guarded restore flow; privacy removal always defeats restoration.

## Historical CP-003B proposal matrix (superseded)

The status matrix and technical recommendation detail below preserve CP-003B history. They are not the current Private Beta V1 approval register. Where their old status or numerical recommendations conflict with the approved policy above, the V1 addendum controls. Preserve these sections for decision history; do not treat old “pending approval” labels as the current policy status.

| ID | Decision | Status | Remaining gate |
| --- | --- | --- | --- |
| D01 | Couple membership and archive reuse | already approved | One active space/account and a two-member maximum remain in force; the D09 access boundary is also approved. |
| D02 | Independent unlinking | already approved | Archive implementation depends on P03/P04/P09, without reopening the approved unilateral-exit rule. |
| D03 | Recorded shared-record erasure revision | unresolved | Revision is recorded, not withdrawn or newly approved; unresolved P03/P04/P09 details prevent complete implementation approval. |
| P01 | Minimal financial audit fields | technically endorsed pending formal approval | Formal approval of the exact field allowlist/time precision and P09 audience/horizon; integrity-marker format and canonical encoding require a tested design. Integrity evidence must cover only retained monetary facts, not hashes that preserve removed identity/text. |
| P02 | Per-space aliases and mapping | technically endorsed pending formal approval | Formal approval; encrypted mapping/key-management mechanism and minimum ownership-provenance retention require review. Do not preserve an extra deleted-user map for convenience. |
| P03 | Ownership-aware bounded archives | unresolved | Approve the 30-day duration, departing-authored retention/removal, joint/mixed classification and review process. No safe automatic rule for all mixed prose/photos is assumed. |
| P04 | Ordinary text deletion versus privacy removal | unresolved | Approve seven days (or another bounded value), who can restore collaborative text, trash visibility and dispute validation. Recommend either current paired partner may restore; no ordinary restore in a closed archive. |
| P05 | Photos and depicted-person requests | technically endorsed pending formal approval | Formal approval; staffed review process/verification/access logging and P03 mixed-photo policy. Target deadlines need operational proof. |
| P06 | Current-authorization exports | technically endorsed pending formal approval | Formal approval; P03/P09 determine archive content and audit export horizon. Verified privacy-request scope and operational identity checks remain to specify. |
| P07 | Recovery boundaries | technically endorsed pending formal approval | Formal approval with D10; restricted identity verification and confirmation language; P03/P09 remain independent blockers. |
| P08 | Secondary copies, privacy epochs and backups | technically endorsed pending formal approval | Formal approval; actual hosting/backup configuration, monitoring and restore drills must prove targets. Manifest fail-closed behavior and receipt purpose/expiry need test evidence. |
| P09 | Purpose-bounded contribution audit | unresolved | Select purpose and duration (e.g. 90/180/up to 365 days), audience and jurisdiction review. Any verified mandatory preservation needs separately reviewed narrow authority/access/expiry; no invented legal hold. |
| D04 | Retention and offline lease | technically endorsed pending formal approval | Formal approval of limits and tested job/native enforcement; P08 backup feasibility. Do not publish unverified cleanup commitments. |
| D05 | Exact savings integrity | technically endorsed pending formal approval | Formal approval; catalog/version and precise command canonicalization/integrity format. P09 blocks closed-ledger retention, not pure Money tests. |
| D06 | Verified single-use invitation | already approved | Implement verified-recipient binding, 256-bit single-use token, 24-hour expiry, atomic/idempotent acceptance and abuse limits; Auth email-change semantics, key handling and limit values need tested implementation choices. |
| D07 | Private authenticated media | technically endorsed pending formal approval | Formal approval; actual Storage/cache/transform/proxy behavior must pass tests. Fail closed rather than weaken authorization for convenience. |
| D08 | Trusted server and platform persistence | technically endorsed pending formal approval | Formal approval; encryption/key/credential spike, license review, threat model and browser session design. No dependencies selected/installed here. |
| D09 | Unpaired, paired and archived access | already approved | Enforce no shared planner reads/writes when unpaired; paired shared planner writes require exactly two active members. P03/P04/P09 still constrain what an archived reader may access or export. |
| D10 | Deletion and limited cancellation | technically endorsed pending formal approval | Formal approval with P07; secure reauthentication/recovery process and operational purge evidence. |
| D11 | Recurrence identity and edge cases | technically endorsed pending formal approval | Formal approval; calendar library/tzdata compatibility and future-series-edit semantics, count behavior and RRULE interoperability must be specified/tested before recurrence migration. |

## Historical CP-003B technical proposals — preserved for decision history

The detailed decision text below records the earlier CP-003B proposal stage. Its statuses and archive/recovery/retention recommendations are not the current Private Beta V1 approval state. Apply the Private Beta V1 addendum above where wording differs. Required tests below remain useful acceptance guidance, **not tests run in this documentation phase**.

### D01 — Couple membership and archive reuse

**Status:** already approved.

**Final proposed wording:** One active couple space per account, maximum two active members. Archived spaces cannot be reopened or reused with a replacement partner.

**Implementation consequence:** Partial unique active user membership; at most two seats; guarded commit-time counts; irreversible first closure. Archived entitlements never grant a new partner access.

**Required security tests:** Race two space creations and third-member acceptance; try replacing seats and reopening closed scopes through every command.

**User-facing disclosure:** One active space; no replacement-partner reuse or transfer of historical archives.

**Remaining blocker:** No product blocker within the approved D01/D09 boundary; implementation must enforce it with server-side constraints and authorization tests.

### D02 — Independent unlinking

**Status:** already approved.

**Final proposed wording:** Either partner may unlink independently. The departing partner immediately loses server access. The remaining partner may receive a read-only archive, subject to the D03 privacy and retention rules. Do not claim that previously downloaded data can be remotely erased.

**Implementation consequence:** Lock and revoke membership, invalidate authorization and privacy sessions/exports; independently evaluate survivor archive records. No partner consent or export completion prerequisite.

**Required security tests:** Old JWT, URL, export, RPC, view, Storage derivative and sync-page requests after committed unlink must fail for the leaver; test concurrent writes.

**User-facing disclosure:** Previously delivered bytes, screenshots and disconnected copies cannot be recalled. Remaining archive access is conditional.

**Remaining blocker:** Archive implementation depends on P03/P04/P09, without reopening the approved unilateral-exit rule.

### D03 — Recorded shared-record erasure revision

**Status:** unresolved.

**Final proposed wording:** Preserve only necessary, auditable contribution history with pseudonymized attribution after account deletion. Shared text, notes, and photographs must have a clearly documented removal, retention, and export process. Do not assume indefinite retention of all shared content.

**Implementation consequence:** Preserve the recorded revision verbatim. Separate monetary facts from removable identity/context; apply the P decisions below rather than interpreting D03 as complete erasure approval.

**Required security tests:** Check no full-row audit, old snapshot, export, note or identity FK bypasses minimization; verify exact balances after redaction.

**User-facing disclosure:** Pseudonymized records can still be recognized; no indefinite shared-content guarantee.

**Remaining blocker:** Revision is recorded, not withdrawn or newly approved; unresolved P03/P04/P09 details prevent complete implementation approval.

### P01 — Minimal financial audit fields

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Retain only accepted transaction UUID, opaque scope/goal identifiers, per-space actor alias, event kind, exact signed integer minor amount, currency/exponent, reversal reference, effective date, recorded UTC day, immutable audit order and integrity/version marker. Exclude names, Auth IDs, email, devices, free text, photos and precise timestamps from the post-erasure audit projection.

**Implementation consequence:** Separate ledger facts, removable notes/context and goal stubs. Redact nonessential precision/context within the endorsed 24-hour primary cleanup target after its privacy boundary. Retention is P09, not an automatic 365-day rule.

**Required security tests:** Field-allowlist tests across queries, exports and history; amounts/order/reversal relations unchanged after identity and note removal; no reconstructable labels in goal stubs.

**User-facing disclosure:** A former partner may recognize contributions from amounts/dates; this is self-reported planning, not a bank statement.

**Remaining blocker:** Formal approval of the exact field allowlist/time precision and P09 audience/horizon; integrity-marker format and canonical encoding require a tested design. Integrity evidence must cover only retained monetary facts, not hashes that preserve removed identity/text.

### P02 — Per-space aliases and mapping

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Use cryptographically random 128-bit aliases per member per space, never email/global-user hashes. Keep identity mapping private and encrypted; deleting-account mapping expires after its 30-day private recovery grace and is purged within 24 hours. No public reidentification surface.

**Implementation consequence:** Decouple audit actors and content provenance from Auth FKs. Survivor authorization mapping may survive only for its own eligible archive. Auth removal cannot cascade ledger loss or preserve the deleted person through membership labels.

**Required security tests:** Cross-space correlation/no reuse; role denial for mapping; mapping purge and key lifecycle; survivor still reads only eligible records after deleted identity is removed.

**User-facing disclosure:** Aliases are pseudonyms, not anonymity; the partner may remember who supplied a record.

**Remaining blocker:** Formal approval; encrypted mapping/key-management mechanism and minimum ownership-provenance retention require review. Do not preserve an extra deleted-user map for convenience.

### P03 — Ownership-aware bounded archives

**Status:** unresolved.

**Final proposed wording:** Account deletion alone must not destroy the remaining partner's own eligible shared records. Propose a read-only archive ending 30 days after first closure, with per-content classification, privacy blocks and earlier removal. Survivor-authored separable content remains eligible; departing-authored or inseparable mixed content requires the rules in the ownership matrix. No perpetual or replacement-partner access.

**Implementation consequence:** Private provenance and per-content disposition determine read/export eligibility, not a blanket account-deletion cascade or membership label. Store first closure, content expiry and archive entitlement separately. Uncertain fragments are narrowly quarantined, not the whole survivor archive.

**Required security tests:** Survivor-only note/photo remains after other account deletion; departing personal fragments hidden; mixed redaction cannot leak via parent/child/media/history/export; expiry cannot reset on recovery.

**User-facing disclosure:** Explain what remains, what is redacted/held, archive deadline and how privacy requests affect mixed material. Authorship is product provenance, not a legal ownership ruling.

**Remaining blocker:** Approve the 30-day duration, departing-authored retention/removal, joint/mixed classification and review process. No safe automatic rule for all mixed prose/photos is assumed.

### P04 — Ordinary text deletion versus privacy removal

**Status:** unresolved.

**Final proposed wording:** Propose a seven-day ordinary-text recovery window, capped by original archive/content expiry. Hide ordinary deleted bodies from normal reads and exports immediately; allow explicit authorized recovery only while still eligible. Valid privacy removal hides protected content immediately and purges affected primary copies within 24 hours. Privacy removal, revocation and expiry always defeat recovery.

**Implementation consequence:** Distinct ordinary_deleted, privacy_blocked, privacy_removed and expired dispositions with a monotonic privacy generation. Only a guarded restore command can clear an ordinary deletion; old offline edits cannot. Ordinary recovery copies are segregated from normal sync/export and purged at their deadline. Photos keep P05's immediate removal direction without a photo trash window.

**Required security tests:** Restore racing a privacy request/expiry/unlink fails; child recovery cannot reveal a blocked parent or subject; backups/history/outbox cannot restore privacy-removed bodies.

**User-facing disclosure:** State the seven-day proposal, who may delete/restore, earlier expiry and irreversible privacy removal. Shared text recovery is not an archive extension.

**Remaining blocker:** Approve seven days (or another bounded value), who can restore collaborative text, trash visibility and dispute validation. Recommend either current paired partner may restore; no ordinary restore in a closed archive.

### P05 — Photos and depicted-person requests

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Treat originals, sanitized copies, captions, EXIF, staging and derivatives as one privacy unit. Either active partner may remove a photo: immediate hide and primary purge within 24 hours. Verified specific former-subject requests trigger a narrow hold, review within 14 days and confirmed purge within 24 hours; missed review deadline removes rather than republishes. Apply revised P03 classification, never blanket destruction of survivor-only photos.

**Implementation consequence:** Exact object/derivative manifest, privacy block and review state; no face-recognition database. Uploader is provenance, not proof of exclusive depicted-person rights. Rejected requests can release a hold only if all independent eligibility tests still pass.

**Required security tests:** Uploader/subject mismatch, spoofed claims, expired review, inaccessible staging/thumbnail/cache, parent removal during processing, survivor-only photo preserved on unrelated deletion.

**User-facing disclosure:** Describe scope, verification, review timelines, removal/backup limits and prior-copy limits; no former-space browsing to submit a claim.

**Remaining blocker:** Formal approval; staffed review process/verification/access logging and P03 mixed-photo policy. Target deadlines need operational proof.

### P06 — Current-authorization exports

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Export only currently eligible private data and shared fields/media at request, generation and download. Optional pre-exit export never delays unlink/deletion. Artifacts expire and purge no later than creation plus 24 hours; earlier access/privacy changes revoke immediately and trigger cleanup without extending that deadline.

**Implementation consequence:** Consistent filtered snapshot; per-source dependency manifest and both epochs; invalidate whole mixed artifact on affected source changes and regenerate if appropriate. Separate verified privacy-access process grants no former-space rights.

**Required security tests:** Export generation/download versus unlink/privacy/expiry races; denied legacy artifacts; exact integer strings, safe CSV and excluded partner-private fields.

**User-facing disclosure:** Export can become unavailable before completion; no guaranteed post-exit window; downloaded copies cannot be recalled.

**Remaining blocker:** Formal approval; P03/P09 determine archive content and audit export horizon. Verified privacy-request scope and operational identity checks remain to specify.

### P07 — Recovery boundaries

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Deletion immediately denies ordinary account access, revokes former-space rights and exports, and starts a 30-day identity/private-profile recovery grace. Cancellation restores only eligible private account state, never old membership/archive access, removed material or shared retention clocks. Purge private records/mapping within 24 hours after grace.

**Implementation consequence:** Separate private-account cancellation jobs from shared archive/redaction jobs. Follow ownership-aware P03 for survivor records; do not interpret independent shared cleanup as destruction of all shared data.

**Required security tests:** Cancel at deadline; delete/cancel races; repeated request cannot postpone existing shared expiry or restore relationship; private recovery cannot query shared data.

**User-facing disclosure:** Recovery does not reconnect partners or recover removed shared records; the surviving person may retain only eligible bounded content/audit.

**Remaining blocker:** Formal approval with D10; restricted identity verification and confirmation language; P03/P09 remain independent blockers.

### P08 — Secondary copies, privacy epochs and backups

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** At a committed privacy boundary block serving immediately, increment privacy epoch and invalidate snapshots/exports; require a sanitized reset and clear affected primary copies within 24 hours. Keep content-free tombstones 90 days. Encrypted residual backups must expire within 35 days after primary purge; replay erasure manifests before any restored service becomes readable.

**Implementation consequence:** Private manifests retain minimal IDs/cutoffs through backup window plus one day (36 days from primary purge), then purge. No personal after-image exemption or clock reset on restore. Distinguish actual object-byte backups from DB metadata.

**Required security tests:** Hold old snapshot/page/export tokens across erasure; crash each job stage; isolated restore before/after purge; inventory raw/clean/derived objects and logs; no old queue resurrection.

**User-facing disclosure:** Access denial, primary cleanup and inaccessible backup aging are different; grace plus purge plus backup may mean up to 66 days for private-account residuals. No remote-copy erasure promise.

**Remaining blocker:** Formal approval; actual hosting/backup configuration, monitoring and restore drills must prove targets. Manifest fail-closed behavior and receipt purpose/expiry need test evidence.

### P09 — Purpose-bounded contribution audit

**Status:** unresolved.

**Final proposed wording:** Retain only P01 audit facts with P02 aliases for a documented purpose and eligible remaining reader. Define a finite audit deadline from first closure; 365 days is a proposed maximum for product and legal review, not a required duration or default implementation value. Stop read/export on expiry or last-reader loss, then purge primary audit within 24 hours, followed by P08 backup aging.

**Implementation consequence:** Require a reviewed retention-policy version and concrete audit_expires_at before closing/serving an archive. No NULL means forever, no unreviewed fallback 365, no resetting clocks. Purge ledger, stubs and digests in FK-safe order. Export only while currently eligible.

**Required security tests:** No-reader and boundary-time purge; partial cleanup retries; unchanged amounts/correction links during retention; expired audit absent from export/snapshot/restore; config lacking reviewed duration blocks activation.

**User-facing disclosure:** State actual approved period and earliest end, pseudonym limits and lack of indefinite financial recordkeeping. Export copies can outlive service retention.

**Remaining blocker:** Select purpose and duration (e.g. 90/180/up to 365 days), audience and jurisdiction review. Any verified mandatory preservation needs separately reviewed narrow authority/access/expiry; no invented legal hold.

### D04 — Retention and offline lease

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Keep content-free tombstones 90 days and eligible ordinary change history at most 90 days; privacy cleanup overrides both. Native leases default 24 hours with explicit trusted-device opt-in up to 7 days from online verification. Private recovery 30 days, primary/orphan cleanup 24 hours, export lifetime 24 hours and snapshot lifetime 15 minutes remain endorsed targets. P03/P04/P09 supply separate unapproved durations.

**Implementation consequence:** Lease binds account/device/scope/authorization and privacy epochs; server time is authoritative; uncertain local elapsed time locks rather than extends. Web sensitive data has no offline lease under D08.

**Required security tests:** Clock rollback/reboot, opt-in expiry, revoked cache reconnect, cursor-floor resets, boundary-time cleanup, content absence despite retained markers.

**User-facing disclosure:** Show verification and lease expiry, provisional native writes and inability to wipe previously delivered copies.

**Remaining blocker:** Formal approval of limits and tested job/native enforcement; P08 backup feasibility. Do not publish unverified cleanup commitments.

### D05 — Exact savings integrity

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** One immutable currency/exponent per goal; exact signed integer minor units, BigInt domain and decimal-string wire encoding. Positive deposits and one exact full reversal per deposit; correction is reversal plus replacement. Amount magnitude 1..9,000,000,000,000 and accepted balance 0..9,000,000,000,000. No FX, withdrawal, bank connection, interest or float source of truth.

**Implementation consequence:** Scope/goal locks, immutable currency and monetary facts, unique operation/reversal keys and exact server aggregation. Notes/context outside ledger core; P01/P02/P09 govern erasure. Archive forbids ledger edits/corrections.

**Required security tests:** Precision/exponent/bounds, web integer roundtrip, duplicate retry, concurrent deposits/reversals, wrong goal/currency, reversal of reversal, unchanged sums after privacy cleanup.

**User-facing disclosure:** Planner entries are not verified balances; corrections preserve history and notes may be removed independently.

**Remaining blocker:** Formal approval; catalog/version and precise command canonicalization/integrity format. P09 blocks closed-ledger retention, not pure Money tests.

### D06 — Verified single-use invitation

**Status:** already approved (CP-006, 2 November 2026).

**Approved wording:** Invitations are bound to a verified recipient email. Each invitation uses a single-use 256-bit token and expires after 24 hours. Acceptance is atomic. Duplicate requests and replay attempts are handled safely and idempotently. Invitation creation and acceptance have abuse limits. The previously recorded proposal retains manual user sharing; this approval does not introduce automatic email delivery.

**Implementation consequence:** Generate tokens with a cryptographically secure random source, return raw token material once, and persist only a verifier/digest plus a protected recipient binding. Under transaction locks, derive the actor from `auth.uid()`, re-read active account and verified recipient identity, check expiry/state/capacity, and atomically commit membership, invite consumption and idempotency receipt. Never accept an anonymous bearer as identity or silently merge accounts. Apply server-side limits to both invite creation and acceptance. No particular numeric thresholds are approved here.

**Required security tests:** Double/concurrent acceptance, third-member and accept-into-two-spaces races, exactly-at/after expiry, revoked/used invite, verified-email mismatch/change, request replay with identical and conflicting payloads, rate-limit exhaustion/concurrency, and rollback on late transaction failure. Assert token material is absent from logs, URLs, persistent client storage, errors and receipts.

**User-facing disclosure:** Show the masked intended verified address, 24-hour expiry, single-use behavior, manual-sharing risk and revoke/regenerate path. Do not reveal whether an unrelated email has an account.

**Remaining implementation questions:** Use the Auth provider's verified email as the identity source; define and test email-change behavior, a non-aliasing canonical comparison, recipient-binding key custody/rotation, abuse-limit thresholds and observable retry behavior. These are implementation/security acceptance details, not pending product approval of D06.

### D07 — Private authenticated media

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Private bucket and authenticated clean-object reads with live account/member/record/privacy/expiry checks for every new request. No downloadable signed bearer links or public derivatives. Use authenticated streaming if direct Storage cannot enforce the full predicate.

**Implementation consequence:** Exact object reservation/manifest join, staging unreadable, live source checks; private no-store delivery and no sensitive service-worker/CDN bypass. Metadata and bytes use identical eligibility.

**Required security tests:** Old JWT/URL/thumbnail/range request after revocation/privacy/expiry; overwrite/copy/list/path tamper; in-flight processing cannot publish a blocked source.

**User-facing disclosure:** Later reads can be denied, but already downloaded and in-flight bytes cannot be recalled.

**Remaining blocker:** Formal approval; actual Storage/cache/transform/proxy behavior must pass tests. Fail closed rather than weaken authorization for convenience.

### D08 — Trusted server and platform persistence

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Use a trusted-server architecture and never claim E2EE. Require protected native persistence before storing any sensitive local data, including outbox/media/temp files and credentials. Sensitive web data is initially online-only in session memory; durable browser persistence needs an independently verified design and separate approval.

**Implementation consequence:** Encrypted native executor/files with per-account keys in platform protected storage; no plaintext fallback. Web no sensitive IndexedDB/OPFS/localStorage/Cache Storage/service-worker/SQL database or durable outbox. Non-sensitive app shell/appearance may remain separate.

**Required security tests:** Native DB/WAL/temp/media/key-loss/account-switch backup inspection; browser storage/network-offline inspection; denied writes never shown durable; Auth SDK cannot silently persist sensitive credentials in browser storage.

**User-facing disclosure:** Trusted operators can access server plaintext; native device protection is not E2EE. Initial web needs connectivity and unsent memory state can be lost.

**Remaining blocker:** Formal approval; encryption/key/credential spike, license review, threat model and browser session design. No dependencies selected/installed here.

### D09 — Draft, paired and archive commands

**Status:** already approved (CP-006, 2 November 2026).

**Approved wording:** Shared planner data is writable only when exactly two active members are linked. Unpaired accounts can access setup and invitation flows, not shared planner content. Archived spaces are restricted to read/export/privacy-removal operations. A third member or replacement member cannot join an existing couple space.

**Implementation consequence:** PostgreSQL must enforce the active-member limit, one active space per account, no archive reuse, and paired-only shared planner read/write authorization. Unpaired setup/invitation metadata is a distinct surface and cannot expose planner rows, aggregates, search, exports or media. Archives accept no new invitations, membership replacement, planner edits, ledger corrections or ordinary restore. The approved allowance for archive reads/exports does not define eligible record classes or retention; P03/P04/P09 remain fail-closed gates for those data paths. Privacy-removal operations remain separately scoped and cannot be used as general writes. Offline work is not authorized by this decision alone and must not retarget after unlink.

**Required security tests:** Unpaired direct SQL/API/RPC SELECT and aggregate denial for any shared planner record; setup/invitation projection isolation; two-member-only insert/update commands; concurrent third-member/replacement acceptance; archived write/invite denial and only policy-eligible read/export/removal; unlink versus writes/acceptance; old valid JWT after committed membership revocation; stale operation/receipt/cache denial. Verify constraints at commit over independent connections.

**User-facing disclosure:** Explain that setup/invitation is available before linking, shared planner content is not; exactly two linked members are required for planner changes; archives cannot accept a replacement partner; and any archive view/export depends on the approved privacy and retention rules. Do not promise remote deletion of previously downloaded bytes.

**Remaining implementation questions:** Define the database state encoding and commit-time cardinality mechanism without expanding the approved behavior. Product policy is approved; archived record eligibility and retention remain unresolved under P03/P04/P09 and block those specific data surfaces, not isolated membership/invitation work.

### D10 — Deletion and limited cancellation

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Require recent reauthentication; deny ordinary access immediately on account deletion, revoke refresh sessions/device notifications and former-space rights. Permit restricted verified 30-day identity/private recovery only; no memberships, archive visibility, pending shared commands or clock reset. Primary private purge within 24 hours after grace.

**Implementation consequence:** Current account state gates all surfaces independently of JWT validity. Separate cancellation-capable private jobs from irreversible shared privacy jobs; remove Auth last, not via broad cascades.

**Required security tests:** Old JWT across all surfaces; delete versus write/accept/export; cancel cannot access partner data; retries and partial Auth failure do not revive access.

**User-facing disclosure:** 30-day cancellation is not full content recovery; prior shared removal and bounded survivor eligibility continue.

**Remaining blocker:** Formal approval with P07; secure reauthentication/recovery process and operational purge evidence.

### D11 — Recurrence identity and edge cases

**Status:** technically endorsed pending formal approval.

**Final proposed wording:** Store explicit last_valid_day or skip policy. Default short-month anchors to last valid day and annual Feb 29 to Feb 28; show choice. DST gaps use first valid instant and folds earlier offset. Use IANA source zone, versioned ruleset and nominal occurrence key separate from observed date/instant.

**Implementation consequence:** Replace original_date-only keys with rule-generation ID plus nominal period/anchor; keep valid observed date separately. Bound expansion and deduplicate scheduling; series-edit behavior/versioning and calendar interoperability need explicit contract.

**Required security tests:** Leap/month ends, gaps/folds, timezone updates, rule edits/cancellations, duplicate scheduler delivery and preview/server parity.

**User-facing disclosure:** Preview upcoming dates/zone and visible skip/fallback choice; explain DST changes.

**Remaining blocker:** Formal approval; calendar library/tzdata compatibility and future-series-edit semantics, count behavior and RRULE interoperability must be specified/tested before recurrence migration.

## Ownership, classification and conditional archive eligibility

This is a **proposed product classification**, not a determination of copyright, data ownership or a legal retention obligation. Neither creator privilege nor uploading a photo grants unrestricted rights over the other person. Account deletion is not, by itself, a valid instruction to destroy the surviving partner's separable records. Conversely, authorship cannot defeat a valid privacy removal concerning another person.

| Class | Provenance / classification | Proposed account-deletion treatment | Read/export and expiry |
| --- | --- | --- | --- |
| Private account data | Profile, devices and preferences belong to the account scope | No partner access; deleting user's private grace/purge under P07/D10 | Own currently authorized access only; restricted recovery is not ordinary export authorization |
| Survivor-authored separable content | Survivor-origin note, task, caption or photograph with no protected departing-person content | Preserve eligible survivor content; do not cascade from departing Auth/member deletion | Remaining reader only, read-only and exportable before proposed first-closure +30 days, unless earlier valid removal/expiry |
| Departing-authored separable content | Departing-origin prose, notes, captions or images, even when shared | **Propose** hide at account deletion and purge primary within 24 hours; redact separable references from retained survivor records | No post-hide archive/export; ordinary unlink alone instead allows bounded archive eligibility subject to privacy requests; requires product approval |
| Joint/mixed sensitive content | Joint edits, both-person photos, text describing either person, merged notes; cannot be reduced to creator ID | **Propose** hide affected content units at deletion pending redaction/review; retain or release only independently eligible survivor portions with protected content removed | No serving/export while held. Proposed 14-day review target capped by archive expiry; a missed classification review keeps only the affected unit inaccessible and escalates, without automatic destruction of separable survivor portions. Purge only for a validated removal or approved archive expiry; no automatic republish on cancellation |
| Uncertain provenance | Unknown author or uncertain subject involvement | Narrowly hold affected units; do not infer survivor-only eligibility or delete unrelated records | Same proposed bounded review. No global blanket hide of all survivor-origin records; classification must be verified before claiming preservation |
| Monetary audit facts | P01 allowlist, P02 aliases; notes/context excluded | Preserve exact facts only under approved necessity/audience/horizon; never falsify balances | Current eligible remaining reader; deadline unresolved under P09. 365 days is only a review ceiling candidate |
| Ordinary deleted text | Recovery payload outside normal serving projections | Do not expose just because author remains. Privacy request converts disposition irreversibly | Proposed 7-day restore limit while paired, original expiry caps it. No ordinary restore in archives; no deleted-body export |
| Privacy-removed material | Validated privacy scope can concern either or both partners | Immediate block; primary purge target 24 hours regardless of recoverability/grace | Never ordinary restore/recreate from old payload; verified invalid holds may be released only when all other eligibility still holds |

**Implementation of authorship:** retain immutable per-content origin alias and minimal contributor aliases for the current content, never an indefinite personal edit-history archive. A partner edit conservatively marks the affected content unit mixed; it does not transfer exclusive control. Splitting redacted surviving portions creates a sanitized projection of the same immutable provenance, not permission to recover blocked versions. Typed field/attachment manifests allow a photo or paragraph unit to be held without suppressing unrelated survivor text. Parent shell eligibility must be independent of removed children; a wholly blocked root cannot leak through its children. Linked records keep safe opaque stubs or revisioned null links where context is removed.

**No automatic semantic privacy oracle:** user declarations/provenance are useful, not proof that survivor-authored content contains no protected information. A credible verified specific request places only identified units on hold. Do not scrape every survivor note for names, add face recognition, or claim a deleting user legally owns everything that mentions them. Joint/mixed definition, review proof, appeal handling, default treatment of departing-authored content and the proposed 14-day classification-review target require formal approval and operational capacity. Until then the affected archive slice is blocked from implementation, not silently configured allow-all or purge-all.

**What deletion confirmation does:** close the relationship and deny the deleting account immediately; evaluate each remaining content unit using the matrix; preserve separable survivor-only material under its deadline; hide/remove departing protected material and hold mixed affected units; minimize financial data. It does not change the authorship of survivor records. A restricted former-person request process never restores couple browsing.

## Text deletion and privacy-removal state machine

Proposed ordinary recovery is distinct from endorsed immediate privacy blocking. Either current paired partner may ordinary-delete shared text; propose either current paired partner may explicitly restore it within 7 days, with expected revision and current permission. This right and interval remain unresolved. Do not apply it to monetary facts, photos, closed archives or privacy-removed material.

1. Ordinary delete commits an access-hidden disposition and revision, advances privacy epoch and invalidates affected snapshots/exports and emits a body-free marker. Its protected recovery copy is readable only through a narrow still-paired recovery workflow if that workflow is approved; never normal queries, activity, search or exports.
2. Store `ordinary_deleted_at`, `recoverable_until` and current revision; cap the deadline by every preexisting expiry. Undo is a guarded new command with its own idempotency key, expected revision and live account/member/parent/child eligibility checks. Generic UPDATE cannot clear a deletion.
3. A valid privacy request commits `privacy_blocked_at`, reason code and monotonic privacy generation, cancels recoverability and starts purge. Verification evidence is private, minimal and bounded, not embedded in shared payloads. Credible disputed claims may have a temporary hold; rejection does not override another removal, expiry or lost entitlement.
4. Once privacy removal is confirmed, no restore, cancellation, stale operation, derivative regeneration or backup restore may republish protected payload. Deliberate re-sharing of the same protected content cannot use a new entity ID to bypass a known removal. Content-scoped minimal block metadata is purpose-bounded under P08; no indefinite biometric/hash surveillance system is implied.
5. At ordinary recovery expiry, purge canonical/recovery/derived copies within 24 hours; purge sooner when privacy removal or other policy requires. Classify a privacy purge separately from an ordinary recoverability state in status/completion reporting. An ordinary delete hides immediately but intentionally retains a protected recovery copy for its explicitly disclosed short period.

## One timeline and authorization contract

Use server UTC and immutable first paired-to-closed `t_close`. `t_delete` belongs to an account and starts only its private recovery clock. A repeated request, export, restored backup, correction, cancellation or later account deletion cannot restart either shared closure horizon. At `now >= deadline`, read/download/restore is denied. Access denial is distinct from asynchronous physical purge and inaccessible backup residue.

**Precedence:** current account and membership authority; then a privacy block/removal; content/parent disposition and classification; archive audience/deadline; operation-specific permission; matching authorization/privacy epochs and revision. Every check must pass. A shorter deadline wins. Ownership does not override subject privacy; account deletion does not override separable survivor ownership by blanket cascade. Unknown/expired policy version cannot grant access. An unresolved policy configuration blocks activation of the affected feature, never creates perpetual retention.

| Event / class | Readable-until / hide | Primary cleanup recommendation | Approval state |
| --- | --- | --- | --- |
| Ordinary text delete | Hide immediately from ordinary views/export | Recoverable up to 7 days while paired if approved; purge within 24 hours after earlier deadline | P04 unresolved |
| Valid privacy removal / photo removal | Immediate committed block | Affected primary copies within 24 hours | Technical direction endorsed; mechanisms/proof pending |
| Survivor eligible nonfinancial archive | Proposed t_close + 30 days, earlier valid removal wins | Within 24 hours after expiry | P03 unresolved |
| Departing-authored / mixed content on account deletion | Selective hide/hold as matrix, not all survivor content | Proposed 24-hour clear-case purge; classification review target <= 14 days; no automatic purge on missed classification review; purge <= 24 hours after valid removal/expiry | P03 unresolved; not a selected deployment default |
| Minimal contribution audit | Approved purpose/eligible reader and finite deadline; last-reader loss earlier | Within 24 hours after approved deadline/last-reader loss | P09 unresolved; no universal 365-day value |
| Account identity/private profile/mapping | Ordinary access ends at t_delete; restricted recovery <30 days | Within 24 hours after 30-day grace unless valid cancellation | P02/P07/D10 technically endorsed, formal approval pending |
| Generated exports | <= 24 hours from creation, or earlier privacy/access/source deadline | <=creation +24 hours; earlier invalidation cannot extend this | P06 direction endorsed |
| Native sensitive cache | 24-hour default lease, explicit opt-in <= 7 days; lock/purge when revocation known | Cooperative cleanup only; no remote-copy guarantee | D04/D08 direction endorsed |
| Sensitive web content/credentials | Online/session-memory only; no durable outbox | Clear on account/scope switch/logout; inspect all browser stores | D08 direction endorsed |
| Old sync payload / snapshot | Denied immediately on relevant privacy-epoch change; snapshots <= 15 minutes | Privacy-triggered primary redaction/purge <= 24 hours | P08/D04 direction endorsed |
| Backups | Never ordinarily readable after removal | Residual age <= 35 days after primary purge; manifest through 36 days, restore re-erasure before service | P08 endorsed target; deployment unverified |

## Reconciled schema and protocol delta specification

These are logical design changes only, not SQL tables/migrations. They replace conflicting CP-002 assumptions for the next reviewed specification. Read with [DATA_MODEL.md](DATA_MODEL.md), [SECURITY_MODEL.md](SECURITY_MODEL.md), [OFFLINE_SYNC.md](OFFLINE_SYNC.md) and [DATA_LIFECYCLE.md](DATA_LIFECYCLE.md).

| Boundary | Reconciled implementation consequence | Safeguard / verification |
| --- | --- | --- |
| PostgreSQL identity / membership | Keep approved active-space uniqueness and seat bounds. Separate `closed_at` (first closure), authorization epoch and privacy epoch. Separate archive entitlement from active membership. Store concrete versioned per-class policy/deadlines only after approval | No nullable-expiry-is-forever interpretation; no closed-to-live transition; last reader exit terminates entitlement |
| Content model | Add logical content-unit provenance/classification/disposition metadata: origin alias, contributor aliases, class, privacy generation/block, ordinary deletion/recovery deadline, content expiry and purge status. Bound any provenance mapping to purpose, not infinite historical identity retention | Server owns classification transitions; refuse edits that downgrade mixed/protected classification; composite same-couple keys throughout |
| Archive model | Private archive entitlement binds original remaining user and closed scope, with revocation/deadlines. Membership `archived` is descriptive only. Separate safe parent shells from removed/held child content | Every read/search/count/export/media route filters per-record eligibility; unrelated/new partner sees none |
| Savings | Move notes into privacy-managed context separate from immutable facts. Audit actor uses per-space alias, not an exposed enduring Auth/member mapping. Goal stub exposes no removed title/description; per-event recorded day/order survives precise timestamp redaction | Full-row SELECT forbidden; exact money/currency/reversal/order preserved. Financial idempotency key retained only through justified audit lifetime |
| RLS and RPC | `can_read_record` includes live account, current active/conditional archive entitlement, class, disposition, subject privacy block and expiry. Separate eligible archive read from paired ordinary write and privileged privacy removal | Derive principal from Auth; fixed-schema definer helpers; no caller-supplied authority; direct DML denied; raw private mapping/context unavailable |
| Storage | Join exact live manifest and eligible parent/content unit, not just couple membership/uploader. All byte ranges, transformations and derivatives require same authorization; trusted processing rechecks before publication | Inaccessible staging, no public/bearer delivery, no cache bypass; object API cleanup verified separately from SQL metadata |
| Sync epochs | `authorization_epoch` invalidates access grants; independent `privacy_epoch` invalidates representations. Bind leases, pages, cursors, snapshots and exports to both. A reset does not reset monetary audit order or commit sequence | Under canonical locks atomically block content, increment privacy epoch, invalidate sessions/artifacts and establish reset floor. Old pages/receipts fail closed even before physical cleanup |
| Snapshot reset | Within current privacy epoch, snapshot is immutable. On privacy change, old chunks are inaccessible and scheduled for purge; regenerate sanitized snapshot at committed high-water. Current live reads filter blocks immediately | Preserve only still-authorized pending intents; reject any intent touching removed/expired units. Automatic rebase cannot replay old text into a new ID/scope |
| Ordinary recovery | Ordinary hide/restore also advances privacy epoch; separate protected recovery payload from normal body and change history, with bounded authorized restore command. Both ordinary hiding/restoration advance privacy epoch and invalidate affected representations; privacy upgrade permanently cancels restore | Test restore under locks against membership, parent, expiry, privacy generation; no tombstone-clearing via normal update |
| Idempotency / erasure | Store compact sanitized receipts, not raw commands. Hashes may encode low-entropy content: access/purpose-bound and purge with affected receipt/account policy. Money retains separate content-free uniqueness evidence without notes | Auth/content checks before returning prior result; body hashes never a public data dictionary; whole-scope purge irrevocably denies old operations |
| Account deletion | Atomically disable deleting account, close/revoke relationship and compute survivor eligibility by content unit; shared jobs continue independently of private grace. Remove Auth last with ordered FKs | Survivor-only records not blanket removed; deleted-person mappings/context do not survive through creator/updater/member FKs; cancellation never restores relationship |
| Browser storage | Initial web uses live authenticated reads, session-memory projections and online commands; no sensitive persistent Drift/outbox/media/search/Auth storage or worker cache. Keep harmless static app shell/theme separate | Auth SDK configuration/session refresh across reloads needs dedicated review; never silently use default persistent browser tokens or claim durable memory-only saves |
| Exports | Private job binds requester, source allowlist/dependency manifest, policy version, both epochs, high-water and actual <= 24-hour expiry. Use class-specific deadline minimum | Recheck request/build/download and regenerate after privacy changes; non-readable archive/trash content cannot appear through earlier job snapshot |
| Recurrence | Store invalid-date policy/ruleset version; nominal key uses rule-generation identity plus period/anchor, observed SQL date separately. All-day date distinct from timed UTC instant | Skip/fallback/Feb 29/DST parity; series edits, tzdata and RRULE compatibility remain a scoped contract gate |

**Atomic privacy transition:** locks follow the existing account/scope/space/entity order. Commit immediate block, epoch increment, cursor reset/invalidation markers and durable cleanup jobs together; do not wait for object-byte deletion to stop serving. The serving predicate checks the block even on freshly requested snapshots while workers run. Cleanup jobs are idempotent, leased, retryable and monitored. They enumerate primary/derived/history/recovery/export copies, report failures honestly and retain only purpose-bounded completion evidence. Restore drills reapply committed removals/expiry in isolation before exposing restored DB or Storage; expired manifests/backups cannot be kept by rotating a restore into a new backup.

**Ownership preservation example:** A contributes a separable shopping note and solo landscape image; B adds a separate personal note and a both-person photograph. B deletes their account. A loses no separable own note/image merely due to B's deletion, but only has the proposed bounded archive. B's personal note follows the proposed departing-authored rule; the joint photograph is held/reviewed under P03/P05. No artifact can export the held photo or recover it through an old memory snapshot. B's restricted account cancellation does not reconnect the space.

## Contradiction disposition and remaining blockers

| Earlier mismatch | Reconciled specification | What remains unresolved |
| --- | --- | --- |
| Whole-space shared nonfinancial destruction on either deletion | Withdrawn. Use ownership/classification and valid scoped privacy removal; preserve eligible survivor portions | P03 durations, classification/review, departing-authored and mixed treatment |
| All text deletions immediately irreversible | Ordinary text recovery and privacy removal separated; privacy always wins | P04 restore actors, 7-day proposal, trash UX and evidence |
| 365 days treated as automatic audit window | Withdrawn as default. Finite purpose-reviewed deadline required; 365 days candidate ceiling only | P09 necessity, actual duration/audience and legal review |
| Web Drift persistent outbox implied by offline-first | Initial sensitive web access online/session-memory only; native-only protected offline path | Credential/session design, verified future browser design if proposed |
| Raw ledger rows/identity FKs survive as immutable audit | Exact facts separated from removable notes/precision/context and private mappings | Formal allowlist/key/integrity implementation approval |
| Immutable sync payloads survive erasure | Epoch-bound immutable snapshots invalidated and payloads redacted/purged; sanitized reset | Executable race/restore tests and bounded workload evidence |
| Grace restores relationship or stops shared cleanup | Private-only cancellation, no membership/archive restoration or clock reset | Real secure reauthentication/recovery implementation |
| Archive label grants everything | Per-record classification/privacy/deadline eligibility across every surface | P03/P09 policy approval |
| Valid original_date cannot represent nominal invalid anchor | Nominal period key + observed date + versioned rule generation | D11 future-series edit/count/interoperability contract |
| Tokens, URL expiry or DB backup alone prove revocation/erasure | Live checks and exact byte-copy inventory/restore evidence required | Platform feasibility and hosting evidence |

These are resolved as design directions, **not verified implementations or approvals**. Remaining contradictions are approval-blocked policy alternatives, not competing undocumented defaults. No jurisdiction, statutory duration, compliance certification or paid-plan capability is invented. Review applicable obligations before production privacy promises; a verified conflict returns for a new explicit decision.

## CP-004 readiness and first backend milestone

**Readiness: conditional for a separately authorized isolated foundation slice; not ready for full database schema freeze, archive/lifecycle implementation or production deployment. No implementation is authorized by this package.**

1. Obtain explicit formal approval of endorsed technical directions and resolve P03/P04/P09 product gates. D03's revision remains recorded while its implementation package stays incomplete. Approve revised disclosures and accept or revise bounded numerical proposals.
2. Recommended first backend milestone: **local, synthetic-data identity/scope authorization proof**, in an isolated development environment only after explicit authorization. Scope account-state gate, draft/paired/closed membership invariants, canonical locking, invite identity/expiry/single-use and sanitized idempotency. Establish explicit grants/RLS and no direct DML; prove unrelated-couple isolation, concurrent acceptance and old-JWT revocation. Do not connect the working UI or a live production project.
3. Include lifecycle seams (independent epochs, first closure and account denial) without inserting unapproved archive/duration defaults. The approved slice must explicitly deny unavailable archive/export/content operations. Do not implement partial silent purge behavior as a placeholder for unresolved policy.
4. Independently prove native encryption/key/media/credential handling and initial web no-sensitive-persistence/session design before sensitive local data. Existing UI/tests remain regression baseline; no speculative product modules or repository class forest.
5. Following policy approval, implement and test ownership-aware content, exact ledger minimization, expiry jobs, sanitized sync resets, private media and exports as separate bounded milestones. Prove crash recovery/restore/privacy tests before claiming deadline guarantees.

## Source checks and documentation validation

Technical reference checks support platform constraints, not legal duties or approval of our policies:

- [Supabase private downloads](https://supabase.com/docs/guides/storage/serving/downloads): private authenticated and signed delivery are distinct; the latter is excluded by our proposed D07.
- [Auth sign-out](https://supabase.com/docs/reference/javascript/auth-signout): outstanding access tokens require application authorization checks rather than assuming sign-out instantly revokes every access token.
- [Drift encryption](https://drift.simonbinder.eu/platforms/encryption/): native protected persistence requires an encrypted executor and key configuration; using Drift alone is not the encryption implementation.
- [Database backups](https://supabase.com/docs/guides/platform/backups): actual Storage object bytes require a separate inventory/backup/removal plan from database records.

Documentation checks and exact changed-file scope are recorded after reconciliation below. Security tests in this package are future acceptance tests only. No Flutter analysis, runtime or backend security result is implied by Markdown validation.

## Reconciliation validation result

- All 20 decisions have current wording, status, implementation consequences, required security tests, disclosures and explicit blockers. Current counts: 4 already approved (D01/D02/D06/D09), 12 technically endorsed pending formal approval, and 4 unresolved (D03 package and P03/P04/P09).
- D01/D02 approvals and D03's recorded revision are preserved. D06/D09 approvals are recorded from the CP-006 user instruction; prior decision-review text remains as dated history and is clearly superseded only for those two statuses.
- Local Markdown links, table column structure, fenced blocks and heading structure were checked across the architecture package/root README. Mermaid remains text-inspected, not rendered by a diagram engine.
- Git whitespace checks pass. Changes in this phase are confined to 12 architecture Markdown files: 11 existing documents plus this new consolidated specification. Existing unrelated/uncommitted work is preserved; HEAD and staging are unchanged.
- Tracked and previously untracked application/platform/test/dependency/visual files match their initial fingerprints. No Flutter analysis/test/build or backend tests were run because this phase changed only documentation; future security tests above remain requirements, not results.
- No dependency, migration, table, Auth flow, Supabase connection, credential, automatic commit or push was introduced. Stop for explicit approval before implementation.
