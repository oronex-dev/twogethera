# Consolidated architecture decision specification · CP-003B final resolution

**Documentation reconciliation only; no implementation authorization.** This is the single current decision specification. It supersedes incompatible *recommendations* in [FINAL_DECISION_PROPOSALS.md](FINAL_DECISION_PROPOSALS.md), the CP-002 blueprint and the historical review. It preserves the existing D01/D02 approvals and [D03’s recorded revision](D01_D03_RESOLUTION.md). D06 and D09 were formally approved in CP-006 on 2 November 2026; this update records those exact policy boundaries without approving unrelated implementation details. Earlier records are retained as history.

Status meanings: **already approved** applies to D01, D02, D06 and D09 (D02 retains its safeguards). **technically endorsed pending formal approval** records the user's direction and security/testing/disclosure conditions without approving unresolved mechanisms or numerical defaults. **unresolved** covers D03's incomplete implementation package and revised P03/P04/P09 choices. No unapproved policy value is an executable default. Formal policy approval is not migration, Auth, Supabase, dependency or commit permission.

## Complete decision matrix

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

## Decision specifications

Each final proposed wording below includes its dependencies; an endorsed direction does not endorse an unresolved dependent policy. Required tests are future acceptance requirements, **not tests run in this documentation phase**.

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
