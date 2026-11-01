# Data lifecycle, export, unlinking and erasure — reconciled candidate

**Current source:** [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md) contains every decision, status, disclosure, security test and remaining blocker. D01/D02/D06/D09 are approved and [D03's recorded revision](D01_D03_RESOLUTION.md) is preserved. Other technical directions remain pending formal approval; P03/P04/P09 remain unresolved. This document reconciles the design, not a deployable retention configuration or legal-compliance claim. No tables, jobs, Auth or backend are implemented.

## Ownership and classification

A closed couple space is never reopened or reused. Private account information stays private. A new partner receives no historical scope. An archive entitlement is conditional, content-specific and time-limited; it never grants all former rows merely because a membership says archived.

**Account deletion does not automatically destroy the surviving partner's own separable shared records.** Use immutable per-unit origin/contributor aliases, current classification, privacy disposition and bounded deadline. Survivor-authored separable content remains eligible for the proposed archive; departing-authored personal content and mixed/subject-sensitive content follow specific proposed removal/redaction/review rules. Authorship/upload is product provenance, not conclusive legal ownership or immunity from valid subject privacy rights. Known privacy blocks override ordinary recovery and archive eligibility.

The consolidated ownership matrix proposes: survivor-only eligible text/media retained read-only for up to 30 days from first closure; departing-authored content hidden/purged at their account deletion; mixed/uncertain affected units held for scoped classification review with a 14-day target, escalating overdue review without automatic destruction of separable survivor portions; purge requires a validated removal or approved archive expiry. These are **P03 choices requiring approval**, not implemented defaults. A safe parent shell may retain permitted text after one photo/paragraph is removed. Do not hold unrelated survivor records, infer that all survivor prose is subject-free, or publish unknown/mixed content without the approved classification process. No indefinite author-version history or face-recognition database.

## Ordinary deletion versus privacy removal

Ordinary text deletion immediately hides normal views/search/export. P04 proposes a separate protected seven-day recovery window, capped by original content expiry, with explicit restore only by a currently paired partner; no ordinary archive restore. Restore actor rights, trash visibility and duration remain unresolved. It is a guarded new command, never a generic tombstone-clear or stale offline replay.

A valid privacy removal immediately hides protected content, cancels ordinary recoverability and triggers primary purge/redaction within the technically endorsed 24-hour target. It covers recovery copies, after-images, search, activity, snapshots, exports and derivatives. Privacy removal, expiry and revocation defeat restore. Photo removal remains immediate hide/purge under P05; the proposed text recovery window does not implicitly apply to photo bytes or ledger facts. Credible verified disputed claims receive narrow holds and bounded review, without former-space browsing. Rejecting one claim cannot override an independent block or expiry.

## Retention and audience matrix

All deadlines are server UTC; no executable value is selected without formal approval and deployment evidence. Readability, primary purge and residual backup aging are separate.

| Class | Audience / hide boundary | Candidate purge and export rule | Status / dependencies |
| --- | --- | --- | --- |
| Private identity/profile/mapping | Ordinary access ends at deletion request; restricted private recovery only before 30 days | Purge primary within 24 hours after grace unless valid private cancellation; no partner export | P02/P07/D10 technically endorsed; recovery mechanism pending |
| Survivor-only separable archive records | Original remaining reader; proposed first closure +30 days, earlier valid removal wins | Export only while currently eligible; purge primary within 24 hours after expiry | P03 unresolved; deletion alone cannot blanket-destroy these records |
| Departing-authored/mixed records | Proposed scoped hide/redaction/review, never blanket survivor deletion | No hold/removal payload export; see ownership matrix for proposed 24-hour purge after valid removal/expiry and 14-day classification review target | P03 classification, duration, review and appeal approval required |
| Ordinary deleted text | Hidden ordinary projections immediately; approved paired recovery surface only | Proposed 7-day recovery capped by source expiry; purge within 24 hours after earliest end | P04 unresolved; no restoration against privacy removal |
| Photo / valid privacy removal | Immediate block across content unit/derivatives | Primary purge target 24 hours; P05 verified review 14 days, confirmed purge <=24 hours | Technical direction endorsed; P03 and operational safeguards pending |
| Minimal financial audit | P01 facts/P02 aliases; current eligible remaining reader and finite reviewed policy | Read/export stops at actual approved deadline or last-reader loss; primary purge target 24 hours | P09 unresolved; 365 days is review maximum candidate, never mandatory/default |
| Export artifact | Current authorized requester at request/build/download; both epochs/source eligibility | Expire/purge <=creation +24 hours; earlier revocation denies immediately and never extends purge deadline | P06 direction endorsed; P03/P09 content eligibility unresolved |
| Eligible normal changes / tombstones | Authorized sync only, both epochs; removal markers contain no bodies | Eligible after-images <= 90 days; content-free markers 90 days; earlier privacy reset overrides | D04/P08 technically endorsed |
| Snapshots / receipts / search / activity | Authorized current representation only; no removed body replay | Snapshot <= 15 minutes, immediate invalidation on privacy change; affected primary cleanup <=24 hours | P08; receipt digests private/purpose-bound, not an identity retention loophole |
| Native local sensitive copies | Protected persistence and valid lease; known revocation locks/purges | 24-hour default lease, explicit trusted-device opt-in <=7 days; cooperative cleanup only | D04/D08; prior copies cannot be remotely erased |
| Initial web sensitive content / credentials | Online and session-memory only | No sensitive durable DB/outbox/media/search/Auth persistence; session reset clears memory | D08; separate verified browser design needed for any later persistence |
| Backups / erasure manifests | No ordinary serving after removal; isolated restores only | Residual encrypted backup <=35 days after primary purge; protected minimal manifests through 36 days, then purge | P08 endorsed target, actual provider/object inventory/restore tests pending |

Financial contribution notes, goal descriptions and labels are privacy-managed text, not immutable audit exceptions. Retain exact monetary facts/order/correction relationships, not original identity labels, device data, free text or precise context by convenience. An opaque goal stub preserves currency interpretation without retaining deleted titles. Alias mapping is separate from audit actor and removed on the approved private lifecycle; aliases remain pseudonymous.

## Removal and recovery workflow

1. Verify requester identity and narrow authority; record content-unit scope. Do not let a former person search the old couple or grant arbitrary removal of unrelated survivor records. Evidence is private/minimized, not a new shared archive.
2. Acquire canonical account/scope/space/entity locks, recheck current state and classify affected units. Commit block/disposition, revision, privacy-epoch change/reset floor (ordinary hide/restore also advances privacy epoch), invalidated snapshots/exports and durable cleanup jobs together. No wait for partner consent or export completion for unlink.
3. All reads/Storage/RPC/view/search/receipt/pull/export paths deny blocked units immediately, including while physical cleanup runs. Re-snapshot only sanitized current content. Exact financial facts remain accurate; a privacy cleanup is not a ledger correction.
4. Enumerate canonical/recovery/derived copies and purge with leased idempotent jobs/retries/alerts. Delete actual Storage bytes via the object API, not merely SQL metadata. If cleanup fails, serving remains blocked and status must report incomplete deletion.
5. Ordinary recovery checks current paired membership, expected revision, privacy generation, parent/child eligibility, original expiry and recovery deadline under locks. Restore cannot clear a valid privacy removal, recreate expired content or republish old versions from backups/outbox.
6. Retain minimal completion evidence only for its purpose. Backups age out without restoring removed content; isolated restore replays all erasure/expiry manifests before any service can read. Do not rotate restoration into a longer residual retention window.

## Account deletion and independent clocks

At a confirmed account-deletion request require recent reauthentication, atomically deny ordinary account access, revoke former-scope membership and device notification bindings, close space at immutable first `t_close`, invalidate epochs/invites/exports and start private recovery at `t_delete`. Current account state enforces denial even if an old access token remains valid.

Compute the survivor's eligible archive by classification and privacy policy. Preserve eligible separable survivor content; hide/remove affected departing/mixed content only under the approved scoped policy. Apply P01/P02 financial minimization separately. Missing P03/P09 approval prevents that feature from activation; it cannot be filled by all-content retention/destruction defaults.

Private cancellation before the endorsed 30-day grace ends restores only eligible private account state. It never restores membership/archive entitlement, reconnects the partner, republishes removed material, stops independent privacy/expiry jobs, or resets first closure. Finalize private/mapping/Auth purge within the endorsed 24-hour primary target after grace; Auth is removed last in ordered FK cleanup. A deleted person's creator/updater/member FK cannot preserve their labels indefinitely or cascade into survivor records/monetary facts.

The last archive reader leaving/removing the archive or requesting deletion ends access immediately and triggers final purpose-reviewed cleanup. P09 must select actual financial necessity/horizon; no automatic indefinite hold or mandatory 365-day duration. A verified legal conflict requires separate explicit review, narrow authority and expiry, not an invented exception.

## Export safeguards and disclosures

At request, generation and download, require current identity/account/membership, permitted per-field/class audience, deadline, source manifest and both epochs. Export a consistent sanitized snapshot; exclude held/trash content, removed context, partner-private profiles/tokens/invite digests/security evidence. Serialize money exactly and neutralize spreadsheet formula injection. Invalidate entire mixed artifacts when any included content loses eligibility; regenerate only if appropriate and currently authorized.

Optional pre-exit export is separate and cannot delay unilateral unlink/deletion. No former-scope access is granted merely because a job was requested earlier. Separate verified personal privacy-access requests must not reveal partner information or restore couple membership. Prior downloaded exports and in-flight bytes cannot be recalled.

Disclose archive content/deadlines/classification, ordinary recovery versus irreversible privacy removal, photo verification/review, limited private-account cancellation, pseudonym limits, exact reviewed audit period and operator access under trusted-server encryption. Explain immediate serving denial, primary purge target and backup residue separately. With 30-day private grace, 24-hour purge and 35-day backup cap, residual private backup copies may last up to 66 days; this is a technical target requiring validation, not current configured hosting behavior. No remote-erasure or E2EE claim.

Classification review is distinct from P05's verified depicted-person request: the latter retains its endorsed 14-day decision/missed-deadline-removal safeguard. Unknown authorship alone is not a valid former-subject claim. Failure to classify cannot create perpetual readable retention or automatically destroy unrelated/separable survivor work; archive activation is blocked until the policy and operational process are approved.
