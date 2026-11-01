# Final decision proposals · CP-003B Part 2

> **Historical decision record.** The body below preserves this review stage and its then-current statuses. CP-006 has since formally approved D06 and D09; those two former “Pending user approval” labels below are historical only. No other proposal is approved by that update. The latest user directions and reconciled proposals are in [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md). Earlier blanket nonfinancial deletion, no-text-recovery and automatic 365-day audit recommendations are superseded there; they are not current policy. D01/D02 approvals and D03's recorded revision remain unchanged.

**Status: all 17 recommendations below are PENDING USER APPROVAL.** “Final” names this consolidated review candidate; it does not mean approved or implemented. No policy recommendation changes current product functionality or authorizes migrations, Supabase configuration, authentication, credentials, a Git commit, or a push.

D01 remains approved; D02 remains approved with safeguards; D03 remains a recorded revised policy whose implementation details are unresolved. Their verbatim record is preserved in [D01_D03_RESOLUTION.md](D01_D03_RESOLUTION.md). Original D04–D11 proposals and prior advisory recommendations remain in [the original approval review](APPROVAL_REVIEW.md) and [the architecture register](README.md). This file proposes an implementable package to resolve the open choices; until approved, the Part 1 implementation gates remain in force.

This is product/security engineering advice, not a legal retention determination. The time limits below are deliberately proposed product limits, not claims about statutory duties, existing hosting configuration, free-tier availability or guaranteed cleanup performance. Review applicable obligations and verify technical feasibility before publishing them to users. No paid service is assumed or added.

## 1. Approval ledger and shared definitions

| ID | Topic | Recommended package | Approval status | Database gate |
| --- | --- | --- | --- | --- |
| P01 | Minimal financial audit data | Field allowlist, exact monetary facts, dates/order rather than precise timestamps after erasure; no free text | Pending user approval | Ledger/projection/redaction design |
| P02 | Pseudonyms and identity links | Random per-space aliases; private mapping; erase deleted-account mapping after 30-day grace | Pending user approval | Membership/attribution/FKs |
| P03 | Conditional archive | Sole remaining member, read-only; text/media up to 30 days after closure, minimal audit up to 365 days; earlier removal wins | Pending user approval | Archive entitlements and reads |
| P04 | Shared text and notes | Either current partner may remove a shared item; immediate hide, primary purge within 24 hours; bounded archive expiry | Pending user approval | Text/note redaction and lifecycle |
| P05 | Photos and subjects | Same removal limits, all derivatives; verified former-subject request process; no uploader-only rule | Pending user approval | Storage metadata/policies/jobs |
| P06 | Export | Current access only; pre-exit export optional; 24-hour artifact lifetime, revoked immediately on loss of access | Pending user approval | Export audience/schema/worker |
| P07 | Deletion and recovery | Immediate account denial; 30-day identity/private-profile cancellation; no restored relationship/archive or guaranteed shared-content recovery | Pending user approval | Account state and deletion jobs |
| P08 | Copies and evidence | Redact/reset history, invalidate snapshots/exports, 24-hour primary-copy cleanup targets and at most 35-day residual backups | Pending user approval | Sync epoch/history/cleanup protocol |
| P09 | Audit horizon | 365 days from first space closure, shortened by last reader departure; no automatic indefinite hold | Pending user approval | Ledger expiry/final purge |
| D04 | Retention / offline | 90-day content-free tombstones; 24-hour native lease by default, explicit opt-in up to seven days; other clocks as below | Pending user approval | Sync/lifecycle and local cache |
| D05 | Savings | Fixed per-goal currency/exponent, exact integer minor units, deposits/full reversals only | Pending user approval | Currency/ledger constraints |
| D06 | Invitations | Verified-email binding, 256-bit one-use token, 24-hour expiry, manual sharing | Pending user approval | Identity/invitation schema |
| D07 | Media delivery | Private authenticated reads, current DB entitlement per request, no downloadable signed bearer links | Pending user approval | Storage and content authorization |
| D08 | Trust / encryption | Trusted server; encrypted native cache as a shipping gate; sensitive web data online-only initially | Pending user approval | Trust model/schema freeze; local persistence |
| D09 | Unpaired / archive writes | Shared writes only when exactly two active members; unpaired draft metadata/invites only; archive read-only | Pending user approval | Membership state/count rules |
| D10 | Account grace | Deny immediately; restricted 30-day cancellation; no automatic membership restoration | Pending user approval | Auth/account lifecycle |
| D11 | Recurrence | Explicit invalid-date policy; default last-valid-day/Feb 28; retain earlier-fold/first-valid-gap behavior | Pending user approval | Recurrence/occurrence keys |

**Package dependencies:** P01/P02/P09 define the audit exception together. P03/P04/P05/P06 determine archive content together. P07/D10/P08/D04 share one deletion timeline. D07 must satisfy already-approved D02; a new bearer-link proposal cannot silently weaken immediate future server-access revocation. D08 changes the initial web offline scope and needs explicit approval. D09's exact draft/paired counts are proposed here, not inferred from D01's maximum-two approval.

### Clocks, access and precedence — recommended, not approved

- `t_close` is the first committed transition of a space from paired to closed/archive, caused by unlinking or a member's account deletion. Store one server UTC instant; retries, cancellation, exports and later account deletions never reset it. Draft abandonment is separate and has no shared planner data under proposed D09.
- `t_delete` is an individual's committed account-deletion request. Private identity/profile recovery ends at t_delete + 30 days. It does not extend an old space's t_close-based clocks.
- Nonfinancial archive read access ends at t_close + 30 days unless a removal or account-deletion event hides it earlier. Account deletion hides **all shared nonfinancial content in that closed space**, including material supplied by the other partner. This privacy-first recommendation can cause the remaining partner to lose their own work and is a significant product choice requiring approval.
- Necessary contribution audit read access ends at t_close + 365 days, or earlier when the sole archive reader leaves/removes the archive or starts account deletion. P09 defines final purge when no eligible reader remains.
- Immediate means future requests check committed server state; an already-running response may have delivered bytes. Previously downloaded files and disconnected copies cannot be remotely recalled. Native offline leases are best-effort limits on a cooperative app, not revocation of information a person already possesses.
- The earliest applicable hide/removal/expiry wins. No grace period, export job, retry or backup restore reopens a closed space or renews content retention. Exact-boundary requests use server time with `now >= deadline` denied, not device time.
- Once content is inaccessible under its policy, primary physical purge completes within the proposed cleanup target (normally 24 hours). An archive read deadline is not an extra grace for reading. Targets require reliable jobs/alerts and must not be advertised as achieved until tested.

## 2. P01–P09 privacy recommendations


### P01 — Minimal retained contribution audit fields

**Existing unresolved choice (verbatim):**

> Minimal retained contribution audit fields

**Existing options/implications (verbatim):**

> Review transaction IDs, exact minor-unit amount/currency/exponent, correction links, goal reference and time precision individually. Free-text notes and human-readable context need a separate removal/retention decision, not automatic inclusion

**Recommended wording — pending approval:**

> After account deletion, retain only the accepted contribution UUID, opaque space/goal identifiers, per-space actor alias, deposit/reversal kind, exact signed minor-unit amount, currency and exponent, reversal reference, effective calendar date, server-recorded UTC day and a server-assigned audit order. Retain a version/integrity marker sufficient to verify ordering and corrections. Do not retain free-text notes, goal titles/descriptions, original names, emails, Auth user IDs, device IDs, photo references or full-resolution timestamps in the retained audit projection. Apply the P09 horizon.

**Risks to either partner:** The departing person can still be recognizable from amounts/dates or the partner’s memory; pseudonymization does not eliminate that risk. The remaining partner loses descriptive context and precise transaction times. Omitting correction links or rounding money would destroy auditability; neither is allowed.

**Database / Storage / sync implications:** Separate immutable monetary facts from privacy-managed notes/labels. Build an explicit post-erasure field allowlist rather than returning whole rows. A minimal goal stub keeps the opaque reference/currency without its title. Preserve exact amounts/correction links while removing precise timestamp values within 24 hours of the privacy boundary, retaining UTC recorded day plus immutable server order. Old snapshots, exports and after-images must be redacted/reset under P08. Technical deduplication metadata stays private and content-free, not an excuse to retain identity-bearing request bodies.

**Required user-facing disclosure:** “After account deletion, a limited contribution record may remain visible to your former partner for the stated audit period. It will not include your name or notes, but they may still recognize it.” Explain which dates/amounts remain and that this is not a bank statement.

**Alternatives and tradeoffs:** Amount-only totals leak less but cannot verify individual reversals; complete ledger rows preserve context but overretain personal content. The recommended allowlist preserves transaction-level monetary integrity without all contextual text.

**Implementation gate:** Blocks ledger, goal-stub, financial-export and erasure schema finalization; no table migration is authorized.

**Approval status: Pending user approval.**

### P02 — Pseudonym generation and identity-link retention

**Existing unresolved choice (verbatim):**

> Pseudonym generation and identity-link retention

**Existing options/implications (verbatim):**

> Per-space versus per-record pseudonyms; whether any reidentification mapping survives, who can access it, and when it is erased. Existing member UUIDs alone are not proof of anonymization

**Recommended wording — pending approval:**

> Generate a cryptographically random 128-bit actor alias per member per couple space; never derive it from email, Auth ID or a global user hash. Keep the identity-to-alias mapping private and encrypted while required for current authorization, then for the deleting account only through the 30-day recovery window. At grace expiry, stop all mapping use and purge it and personal membership labels within 24 hours, retaining only the alias/reference needed by the minimal audit record. Never expose a reidentification RPC or share an alias across spaces.

**Risks to either partner:** A remaining partner may already know the alias-to-person relationship. A private mapping increases operator/reidentification exposure during grace, while removing it may prevent later identity-based corrections or support lookup. The surviving account still needs an authorization mapping for its own archive entitlement until that entitlement ends; this must not keep the erased partner’s mapping.

**Database / Storage / sync implications:** Decouple an audit actor reference from the nullable Auth/member user FK. Restrict mapping columns to trusted routines; API views/exports return aliases after erasure. Enforce per-space alias uniqueness and no cross-space reuse. Erasure jobs remove mappings/labels and references in secondary payloads; retain only necessary content-free completion evidence. Audit aliases do not themselves grant access.

**Required user-facing disclosure:** “Names are replaced with a space-specific alias, not guaranteed anonymity. The other person may remember which records are yours. Recovery mapping is removed after the stated deletion grace.”

**Alternatives and tradeoffs:** Per-record aliases reduce direct grouping but make per-partner audit difficult. A global stable pseudonym enables unwanted cross-space correlation. Never retaining a mapping complicates legitimate current authorization and recovery.

**Implementation gate:** Blocks membership/attribution FKs, audit projections and final erasure design; choose the storage/key-management mechanism in the later security spike.

**Approval status: Pending user approval.**

### P03 — Conditional archive eligibility, audience and expiry

**Existing unresolved choice (verbatim):**

> Conditional archive eligibility, audience and expiry

**Existing options/implications (verbatim):**

> Determine what the remaining partner may read after unlinking and after account deletion, whether a reduced financial-only archive exists, when access ends, and how the last reader's deletion affects it

**Recommended wording — pending approval:**

> After unilateral unlinking, only the remaining member may read the closed space’s permitted archive; the departing member has no server access. Nonfinancial content is read-only for at most 30 days from t_close, subject to earlier individual removal. Either member’s account-deletion request hides all remaining shared nonfinancial content immediately. The sole remaining member may read the minimal contribution audit until t_close + 365 days unless their own eligibility ends earlier. A new partner never inherits the archive; no archive is reopened or reused.

**Risks to either partner:** The departing partner may regard a 30-day archive as too long; the remaining partner may find it too short. Account deletion can hide text/photos they supplied themselves, without a guaranteed export opportunity. Downloaded copies can survive all deadlines. These are material relationship/privacy tradeoffs, not invisible implementation defaults.

**Database / Storage / sync implications:** Store first closure time, entitlement expiry and content-class eligibility. RLS/read RPCs, Storage, search, sync snapshots and exports check the class deadline and current entitlement; archive membership alone is insufficient. Active membership uniqueness ignores closed entitlements but still enforces D01. All shared commands stay blocked after closure. See P09 for zero-reader cleanup.

**Required user-facing disclosure:** Show the exact archive expiry date and a financial-only phase. Before sharing/exit, explain that either partner’s account deletion can end text/photo archive access immediately, including the viewer’s own shared material, and that downloaded copies are outside remote control.

**Alternatives and tradeoffs:** Revoking both members immediately is more restrictive but harms continuity. Indefinite archives conflict with D03 minimization. Per-author retention reduces collateral loss but requires ownership/version-history rules that cannot reliably separate jointly authored content in the initial model.

**Implementation gate:** Blocks archive membership/content policies, lifecycle timestamps, export eligibility and expiry jobs.

**Approval status: Pending user approval.**

### P04 — Shared text and note removal / retention

**Existing unresolved choice (verbatim):**

> Text and note removal / retention

**Existing options/implications (verbatim):**

> Specify triggers, ownership/collaborative-edit treatment, per-class deadlines, disclosure and conflict handling. Options include removal, bounded retention or an explicit export window; indefinite default retention is excluded

**Recommended wording — pending approval:**

> While paired, either active partner may remove a shared item without the other’s permission: hide it and its dependent shared text immediately, then purge primary text/notes within 24 hours. Do not retain deleted bodies in activity, receipts or change history. In an archive, the remaining eligible member may request removal but cannot edit or add shared records. All nonfinancial content expires at t_close + 30 days; account deletion hides the whole space’s nonfinancial content earlier. Contribution notes and goal labels follow this text rule, not the audit-core exception.

**Risks to either partner:** Either partner can remove collaborative work the other values. Copying a name into another note does not make it safe to retain. Retaining original versions for undo would undermine this policy; an undo/trash feature is deliberately not part of this recommendation. A verified former-person privacy request must be handled without granting access to the former space.

**Database / Storage / sync implications:** Separate note/description fields from financial facts; support privileged redaction without rewriting amounts. Tombstones contain IDs/revisions only. Root removal hides child records immediately; bounded jobs clear text, search, activity payloads and old after-images. Maintain minimal non-content evidence only. Identity-verified former-person requests use a restricted process; uncertain subject/ownership claims follow the P05 review timeline, never a public lookup.

**Required user-facing disclosure:** “Shared content can be removed by either partner. Removal is not an archive backup or undo service. Export permitted content before exit if you need a copy, but an export cannot delay another person’s departure or privacy removal.”

**Alternatives and tradeoffs:** Joint consent to removal preserves material but can trap sensitive data. Per-author fragment deletion is difficult with collaborative edits. A longer trash period enables recovery but creates extra readable/retained copies and would require separate approval.

**Implementation gate:** Blocks text/note storage boundaries, redaction API, activity/search projections and deletion jobs.

**Approval status: Pending user approval.**

### P05 — Photographs and depicted-person handling

**Existing unresolved choice (verbatim):**

> Photograph and depicted-person treatment

**Existing options/implications (verbatim):**

> Resolve uploader versus depicted-person requests, jointly supplied media, captions/EXIF, thumbnails, staging and derived objects; uploader-only deletion is not a complete policy

**Recommended wording — pending approval:**

> Treat photos, captions, staging originals, sanitized originals and thumbnails as one privacy unit. Either active partner may remove a shared photo; hide it immediately and purge primary object copies within 24 hours. Archive photos have the same 30-day maximum and earlier account-deletion hide rule as P03. For a credible identity-verified former-person request identifying media depicting them, hide the identified media pending review, decide within 14 days, and purge within 24 hours if confirmed; if the deadline is missed, remove rather than automatically republish. An invalid request may be rejected, but publication resumes only if current content eligibility still permits it.

**Risks to either partner:** An abusive request can temporarily suppress the other partner’s media; identity and record specificity must be verified without exposing images to outsiders. Uploader status alone does not settle depicted-person privacy. If an account is deleted, the other partner may lose their own uploads in that shared space. Unidentified or unverified claims cannot trigger arbitrary database-wide deletion.

**Database / Storage / sync implications:** Maintain an exact attachment/derivative manifest, content block state and idempotent Storage cleanup jobs. Authenticated object/transform endpoints consult current record eligibility, including a pending verified privacy block. Strip EXIF/GPS before publishing. Restrict review access and logs; no face recognition or biometric database is proposed. A staffed, documented review channel and bounded queue are launch dependencies; no such service is being created now.

**Required user-facing disclosure:** Explain who may remove photos, what “removed” covers, the dispute/review process and deadlines, backup residues, the effect of either account’s deletion, and the inability to recall already saved images.

**Alternatives and tradeoffs:** Uploader-only control misses depicted-person concerns. Automatic removal on anonymous claims invites abuse. Requiring partner consent can block necessary removal. The recommendation requires verified requests and bounded review rather than a new right to browse a former space.

**Implementation gate:** Blocks attachment fields, Storage read/block policies, review workflow and object-cleanup readiness.

**Approval status: Pending user approval.**

### P06 — Export eligibility and timing

**Existing unresolved choice (verbatim):**

> Export eligibility and timing

**Existing options/implications (verbatim):**

> Specify what a user may export before unlink/deletion, whether a bounded window exists, exact content/redactions and generated-artifact expiry. Any separately verified privacy-access process must not restore former couple access

**Recommended wording — pending approval:**

> Allow an authenticated, currently eligible user to export only the private data they own and shared fields/media they may read at request, generation and download. Offer export before unlink/deletion as an optional separate action; no guaranteed post-exit window and no delay to unilateral exit. In an archive, apply P03’s class deadlines. An export artifact becomes unreadable and is scheduled for primary physical purge no later than 24 hours after creation, or loses read access immediately on any earlier relevant revocation/removal/expiry. Earlier revocation must trigger cleanup within 24 hours without extending the original creation-based purge deadline. After account deletion, use a separately identity-verified privacy-request process for the requester’s permitted personal data only; it does not restore access to the former couple or their partner’s information.

**Risks to either partner:** A departing person may leave before a desired export finishes; a remaining partner may lose access when the other deletes their account. A mixed-content zip can retain removed photos or names even after source redaction. The requester controls copies they download, so technical expiry is not recall.

**Database / Storage / sync implications:** Build from a consistent authorized snapshot with an approved field allowlist, exact integer money serialization and safe CSV cells. Bind artifacts to requester/scope/epoch and to referenced source classes; invalidate mixed artifacts on any covered privacy change, not merely account state. Use authenticated download, private encrypted temporary storage and idempotent byte cleanup. Restrict pending-operation draft exports to explicitly labeled, still-authorized local data; exclude token secrets and partner-private records.

**Required user-facing disclosure:** “Exports contain only data you can currently access and may stop being available when access changes. Downloaded copies cannot be recalled. Unlinking or deletion does not wait for export completion.” State the 24-hour maximum and any earlier deadline.

**Alternatives and tradeoffs:** A guaranteed post-exit export window conflicts with D02 unless a distinct narrowly scoped personal-data channel is designed. Signed download URLs are convenient but conflict with immediate revocation. Indefinitely retained artifacts become shadow archives.

**Implementation gate:** Blocks export field/audience contracts, temporary-object authorization and invalidation jobs.

**Approval status: Pending user approval.**

### P07 — Grace, cancellation and irreversible removal

**Existing unresolved choice (verbatim):**

> Grace, cancellation and irreversible removal

**Existing options/implications (verbatim):**

> Reconcile content hiding, physical deletion and recovery expectations with still-pending D04/D10. Do not assume immediate photo purge or a 30-day recovery promise from this resolution

**Recommended wording — pending approval:**

> At account-deletion confirmation, immediately deny ordinary account access, revoke former-space membership, disable notification tokens and pending exports, and start a 30-day identity/private-profile cancellation window. A restricted verified recovery flow may cancel final identity/private-profile purge, but must not restore memberships, reset t_close, republish shared content or promise recovery of removed material. Shared archive expiry/removal requests continue on their original clocks even after cancellation. At the end of grace, purge remaining primary private records and identity mapping within 24 hours, subject to P08’s disclosed backup residue.

**Risks to either partner:** Accidental deletion is partly recoverable, but shared material may already be hidden or removed. The other partner must not be forced back into a relationship by cancellation. A compromised account could start deletion, so recent reauthentication and clear confirmation are required. The grace period stores some personal data longer than immediate erasure.

**Database / Storage / sync implications:** Use a durable deletion request with immutable deadline, idempotent worker, narrowly allowed recovery state and authorization denial independent of JWT validity. Lock state transitions with membership changes; cancellation only changes eligible private-account jobs. Jobs must distinguish identity purge from shared-space expiry/redaction. Never cascade Auth deletion straight into retained monetary facts or preserve the full shared payload for recovery.

**Required user-facing disclosure:** “You can cancel account deletion for 30 days, but this will not reconnect you, restore archive access, or recover shared items already removed. The other partner may retain the limited audit history described here.” Confirm this before the destructive request.

**Alternatives and tradeoffs:** Immediate erasure maximizes prompt deletion but removes recovery. Restoring memberships risks unwanted reconnection and conflicts with closed-space reuse boundaries. A grace period that pauses all shared cleanup covertly extends the former partner’s content retention.

**Implementation gate:** Blocks account/lifecycle states, recovery permission surface, cancellation semantics and deletion scheduling; align D10/D04.

**Approval status: Pending user approval.**

### P08 — Secondary copies and deletion completion evidence

**Existing unresolved choice (verbatim):**

> Secondary copies and deletion completion evidence

**Existing options/implications (verbatim):**

> Choose redaction/reset handling for sync after-images, snapshots, receipts, activity, search, server caches, issued media/export links, exports, object derivatives, logs and backups; establish measurable cleanup/restore rules

**Recommended wording — pending approval:**

> Make privacy removal authoritative across canonical data, search, activity payloads, receipts, sync after-images, snapshots, exports, staged media and derivatives. Deny new serving at the committed privacy boundary; complete affected primary-copy redaction/purge within 24 hours. On erasure, bump a privacy epoch, invalidate affected snapshot/export sessions and require a sanitized full snapshot instead of replaying old personal payloads. Keep content-free tombstones for 90 days. Require encrypted backups to age out within at most 35 days after primary purge, with an erasure manifest reapplied before any restore becomes readable; never renew the retention clock by restoring.

**Risks to either partner:** Missed derived objects or payloads can re-expose data; a manifest containing original content would itself be another leak. Full snapshots may be expensive and erase offline edits if not staged correctly. Backups retain inaccessible residual data, and past downloads remain beyond reliable control. Hosting settings may not meet the proposed cap without a different deployment choice.

**Database / Storage / sync implications:** Separate privacy epoch from immutable monetary order, or define a verified equivalent epoch reset. Remove/redact old content-bearing change entries and advance the valid-cursor floor under the same protected transition; stale requests/pages fail closed and full snapshots retain only eligible fields. Epoch checks and source policy gates deny access immediately while cleanup runs. Store minimal scope/record IDs and removal cutoffs in a protected erasure manifest through the backup window plus one day (36 days after primary purge), then remove it. IDs in manifests/tombstones can still be linkable metadata: keep them private and purpose-bound, not publicly “anonymous.” Keep necessary content-free operation digests only through their justified scope/audit lifetime; erase account mapping separately. Validate Storage inventories, restore isolation and cleanup alerts before making deletion promises.

**Required user-facing disclosure:** Distinguish access removal, primary deletion, and backup expiry. With a 30-day account grace plus a 24-hour purge target and at most 35-day residual backups, some private backup copies can persist for up to 66 days after request. This is a proposed launch bound, not verified provider behavior. Prior downloads and malicious/disconnected devices cannot be remotely erased.

**Alternatives and tradeoffs:** Crypto-erasing uniquely scoped keys can shorten exposure but does not prove that every plaintext/derived copy is gone. Retaining immutable full after-images until a generic log expiry violates the intended removal policy. A shorter backup window reduces recovery options; a longer one needs explicit renewed approval/disclosure.

**Implementation gate:** Blocks privacy epoch/history design, snapshot/export invalidation, backup/restore configuration and erasure completion claims. The 35-day cap is a launch feasibility gate, not an assumed paid-plan feature.

**Approval status: Pending user approval.**

### P09 — Audit-history necessity horizon and final purge

**Existing unresolved choice (verbatim):**

> Audit-history necessity horizon and final purge

**Existing options/implications (verbatim):**

> Decide duration, expiry triggers, authorized readers, zero-reader-space handling and any reviewed exceptional retention basis. “Auditable” does not mean keep forever

**Recommended wording — pending approval:**

> Keep the P01 minimal pseudonymized audit history readable for at most 365 days from the space’s first closure, with the bounded primary-purge and backup-residue deadlines stated below. If the sole eligible archive reader leaves, removes the archive or begins account deletion earlier, stop audit access immediately and purge the now-unneeded primary audit within 24 hours. Otherwise purge within 24 hours after the 365-day deadline. A restore, correction, export, retry or recovery must not restart the horizon. Do not create a routine indefinite legal-hold exception; any verified mandatory preservation requirement needs a separately reviewed, narrow, access-restricted process before launch.

**Risks to either partner:** The remaining partner may need records longer than one year; shorter retention can lose useful dispute context. One year is still sensitive retention, and an exported copy may last longer outside the system. A necessary legal obligation could conflict with this product default and must be evaluated rather than guessed. Deleting the last reader’s account removes the assumed product purpose for continuing ordinary retention.

**Database / Storage / sync implications:** Store immutable closure/audit-expiry instants and current reader eligibility; schedule bounded primary purge. Keep monetary order/integrity during retention but remove privacy-managed fields on earlier deadlines. Purge goal stubs, audit rows, mappings/digests and references in correct FK order once their purpose ends; content-free 90-day deletion markers do not contain amounts or identities. Backups age out per P08 and cannot restore expired readable audit records.

**Required user-facing disclosure:** “A limited audit may remain for up to one year after this space closes, ending earlier if its last eligible reader leaves. Export permitted records beforehand if you need your own copy; the service does not provide indefinite financial recordkeeping.”

**Alternatives and tradeoffs:** Keeping until the last reader chooses removal lacks a bounded necessity horizon. A 30/90-day audit is more private but may be less useful. Indefinite retention in the name of auditability is not recommended.

**Implementation gate:** Blocks audit retention, closure timestamps, zero-reader purge and corresponding privacy disclosures; verify applicable obligations before launch.

**Approval status: Pending user approval.**

## 3. D04–D11 recommended architecture policies

### D04 — Retention and offline access limits

**Exact current proposal (verbatim):**

> Change log/tombstones retained at least 90 days; offline read lease at most 7 days; account deletion grace 30 days; unreferenced uploads 24 hours; exports 24 hours

**Recommended final wording — pending approval:**

> Keep content-free tombstones for 90 days from removal and normal eligible change history for at most 90 days, with earlier privacy redaction/reset overriding history retention. Default encrypted-native offline read leases to 24 hours; allow an explicit trusted-device opt-in up to seven days from the last successful online authorization, never automatic extension. Initial web sensitive-data access is online-only under D08. Apply the shared 30-day private-account recovery, 24-hour orphan/export/primary-copy cleanup targets, 15-minute immutable snapshot lifetime and 35-day residual-backup cap. P03/P09 govern the separate archive and audit horizons.

**Alternatives and tradeoffs:** Shorter leases reduce disconnected exposure but interrupt travel; seven-day access is convenient but prolongs that exposure. Longer change logs reduce snapshots but retain more payloads; content-free markers plus sanitized snapshots preserve correctness without keeping erased content. Immediate account purge removes recovery; a longer grace delays erasure. These numbers are recommended product limits, not legal retention minima.

**Security implications:** Expiry must use a server-issued lease bound to account/device/scope/epoch; detect backward clock changes, reboot uncertainty or key loss and require online renewal. A cooperative app can lock data, but no timer remotely erases screenshots, malicious local copies or downloaded exports. Never serve personal after-images after removal merely because 90 days have not elapsed.

**Implementation dependencies:** Needs authenticated account/context verification, encrypted-native persistence, signed lease verification, bounded outbox/snapshot recovery, content/privacy epochs, deletion/expiry jobs, cleanup alerts and verified backup configuration. Web capability reporting must refuse durable offline-write guarantees rather than silently using memory-only “saved” state.

**Blocks database implementation?** Blocks sync metadata/retention and lifecycle schema freeze. Isolated stateless contract experiments are possible only under separate authorization; no actual database work may begin from this review.

**Required disclosure:** Show last verification, exact lease expiry, opt-in risk and offline limitations; state cleanup/recovery/export clocks separately. An archive deadline, account grace and backup expiry are different things.

**Difference / reconciliation required:** Changes the original maximum-seven-day idea into a 24-hour default with explicit native opt-in, and distinguishes personal-data removal from 90-day sync markers. Cross-approve P03/P07/P08/P09/D08/D10; do not read this as approval of any prior durations.

**Approval status: Pending user approval.**

### D05 — Savings currency and audit integrity

**Exact current proposal (verbatim):**

> One immutable ISO currency and minor-unit exponent per savings goal; recorded deposits and exact reversals only; no FX, bank integration, interest, or withdrawal workflow initially

**Recommended final wording — pending approval:**

> Use one immutable currency code and approved minor-unit exponent per savings goal. Store accepted amounts as exact signed integer minor units; use BigInt domain arithmetic and decimal-string JSON, never floating point as the source of truth. Initial events are positive deposits and one exact full reversal per deposit; corrections are reversal plus replacement deposit. No arbitrary negative adjustment, partial reversal, withdrawal, FX, bank connection, interest or verified-balance claim. Bound each deposit/reversal magnitude to 1..9,000,000,000,000 minor units, and the accepted goal balance to 0..9,000,000,000,000; deposits are positive and reversals exactly negative. Reject unknown currencies, fractional minor units, excess currency precision and noncanonical numeric strings; parse entered decimal digits without a float conversion. Keep immutable monetary facts and separately removable notes; apply P01/P09 after account deletion.

**Alternatives and tradeoffs:** A single couple-wide currency is simpler but restricts goals. Multi-currency aggregation/FX and withdrawals improve realism but introduce rate/history and audit semantics. Full reversal is easy to audit; partial reversal/withdrawals can be added only as new explicitly approved event types, not edited historical amounts.

**Security implications:** Derive actor server-side, validate goal currency/state, serialize appends and exactly-once effects by operation ID. Reject stale/repeated competing reversals and mismatched goals/currencies. Accumulate with exact PostgreSQL numeric/integer-safe logic and bounds, not floating sums or a client balance column. Privacy redaction must not change amounts/correction links or keep notes as hidden audit payloads.

**Implementation dependencies:** Needs immutable currency catalog interpretation, exact decimal parser, typed Money, ledger/goal locks, unique reversal/idempotency constraints, accepted-vs-provisional UI contracts and privacy-separated fields. A local SQLite amount may be integer only within the tested safe bound; sum via BigInt. Existing repeatable integer codecs require native/web tests even though initial web is online-only.

**Blocks database implementation?** Blocks currency/goal/contribution schema and write RPCs. Exact-money pure-Dart tests may be separately authorized without backend work.

**Required disclosure:** Explain currency cannot be changed for a goal, corrections remain visible, and recorded savings are self-reported planner records. Distinguish provisional offline contributions from accepted records and state the amount limit.

**Difference / reconciliation required:** Preserves the original narrow savings scope, makes exact transport/bounds explicit, and resolves the old immutable-note conflict through P01/P04. The 9e12 bound is an explicit proposed product limit, not a statement about personal financial suitability.

**Approval status: Pending user approval.**

### D06 — Partner invitation identity and expiry

**Exact current proposal (verbatim):**

> Invite is bound to a verified email identity, lasts 24 hours, and is single-use; user shares the link manually

**Recommended final wording — pending approval:**

> Bind each invitation to the intended recipient’s current verified Auth email, with a 24-hour server expiry and cryptographically random 256-bit single-use token. Store only its digest and a keyed, versioned recipient-email HMAC; share the link manually and return the raw token only once. Require online acceptance, distinct users, current membership checks, a locked atomic transition and idempotent operation receipt. Allow at most one pending invite per draft; replacement explicitly revokes the former invite. Never infer Gmail-style dot/plus equivalence: trim input, canonicalize the domain, and match the local part against the verified provider identity’s canonical value.

**Alternatives and tradeoffs:** Bearer-only links are easier to redeem but can link a forwarded recipient incorrectly. Inviter confirmation adds safety but an extra dependency. Shorter expiry reduces exposure but increases reissues; automated email requires delivery/privacy work outside initial scope. The proposed binding can require a recipient to choose the correct verified identity or request a new invite.

**Security implications:** Use generic unavailable responses, no account-existence enumeration, no raw tokens in logs/local databases/OAuth state, and recipient preview only after verified identity matching. Proposed limits remain five issue operations/account/hour and ten acceptance attempts/account/10 minutes plus IP abuse controls. Acceptance locks users/scopes/space/invite in canonical order, checks receipt before fresh-token state failures, and cannot exceed D01 active limits. Check live account/membership rows, not custom JWT/user metadata.

**Implementation dependencies:** Needs real verified identity, server HMAC/key rotation, invite state/expiry checks, account and scope locking, RLS/RPC grants, transient fragment-token handling and explicit revoke/regenerate. Hash routing can keep tokens in a fragment, immediately remove them from visible history, and ask users to reopen after external login rather than persist the secret. Do not implement a fake sign-in for testing the user journey.

**Blocks database implementation?** Blocks invitation schema and acceptance implementation; Auth identity confirmation strategy must be chosen before those routines are written.

**Required disclosure:** Show masked recipient identity, expiry, single-use status and explicit replacement behavior. Explain that the intended verified account is required and no email will be sent automatically.

**Difference / reconciliation required:** Keeps the original email-bound/manual-sharing model and the CP-002 race-safe algorithm. No approval is inferred from having already documented that algorithm.

**Approval status: Pending user approval.**

### D07 — Private photo delivery

**Exact current proposal (verbatim):**

> Private photo bucket with authenticated reads; no downloadable signed bearer links in the initial product

**Recommended final wording — pending approval:**

> Use a private photo bucket and authenticated reads that verify current account, membership/conditional archive entitlement, content eligibility, privacy epoch and exact attachment path on every new request. Expose no public object URL or downloadable signed bearer link in the initial product. Use authenticated upload reservations and immutable keys, with server validation/sanitization; apply P05 to originals, staging and derivatives. Recheck the same conditions for thumbnails, transforms and export media. If direct Storage policy enforcement cannot meet the required gates, use a narrow authenticated streaming endpoint; do not fall back to a bearer URL.

**Alternatives and tradeoffs:** Short-lived signed URLs simplify image rendering and CDN use but continue to act as transferable bearer capabilities. An authenticated stream adds implementation/egress cost and must avoid logging content. E2EE object delivery changes the trust/key model and requires a different approved architecture. None of these options recalls bytes already delivered.

**Security implications:** RLS uses exact live attachment metadata, not just a folder prefix. Block upsert/overwrite/copy/move and unrelated listing, process raw bytes privately, validate type/size/dimensions and remove EXIF/GPS. Cache behavior must not let a revoked principal obtain new server bytes; choose private/no-store responses and prove endpoint behavior with old JWTs. A signed URL is not made safe merely by rotating Auth keys. [S1: Storage delivery](https://supabase.com/docs/guides/storage/serving/downloads)

**Implementation dependencies:** Needs attachment reservations, clean-object manifest, P05 blocks, content-aware authorization helpers, server image processing, policy/transform/cache integration tests and reliable byte cleanup. Existing keys or a live Storage project are not needed to approve this policy.

**Blocks database implementation?** Blocks Storage/attachment access-policy and media delivery implementation. It does not alone block an isolated identity-table design, but the overall project still lacks migration approval.

**Required disclosure:** “Only currently authorized people can request photos through the app, but someone may save or screenshot a photo before access ends.” Explain removal scope, cache/offline limits and photo review process.

**Difference / reconciliation required:** Retains the original authenticated-only proposal and explicitly makes D02 immediate future server-access loss a non-negotiable constraint. No CDN or signed-link exception is silently approved.

**Approval status: Pending user approval.**

### D08 — Encryption and trust model

**Exact current proposal (verbatim):**

> Trusted-server model, not end-to-end encryption; native key storage/encrypted local persistence require a separate technical spike; web has weaker local secrecy

**Recommended final wording — pending approval:**

> For the initial product use a trusted-server model with TLS, least-privilege access, private encrypted server storage/backups and protected operator access; do not claim E2EE. Before shipping persisted native sensitive data, require a verified encrypted Drift-compatible executor and encrypted media files, separate per-account keys protected by iOS Keychain/Android Keystore, explicit lock/purge behavior and backup exclusions where supported. Initial web sensitive data is online-only with session-memory caching: no durable planner outbox, local financial/media database or sensitive service-worker cache. A future trusted-browser offline mode requires a separate approved security/capability design. Complete the spike before choosing packages or advertising encryption behavior.

**Alternatives and tradeoffs:** E2EE reduces trusted-server plaintext access but changes recovery, partner key exchange, search, notifications, exports and metadata erasure; approving it later would require redesign. Browser encryption cannot reliably hide data/keys from a script already executing in the same origin. Native encrypted persistence costs integration effort and can fail on key loss; online-only web sacrifices initial offline parity but avoids making a weak confidentiality/durability promise.

**Security implications:** Drift requires an explicitly configured encrypted executor rather than guaranteeing encryption by itself. [S3: Drift encryption](https://drift.simonbinder.eu/platforms/encryption/) Never place database keys in Dart defines, ordinary preference files or exported backups; test key rotation/loss, account switching, device lock, memory exposure and deletion. Operators can still access server plaintext under this model. XSS/extensions/rooted devices and legitimate prior downloads remain risks. Native device keys should not be shared with a partner as a shortcut to coupling.

**Implementation dependencies:** Requires native executor/key-storage/file-encryption feasibility and OSS-license/dependency review, web repository capability flags and unsaved-state handling, CSP/dependency controls, backend/backup configuration evidence and an operator-access policy. No package is installed or paid service selected in this phase.

**Blocks database implementation?** Blocks trust-model/schema freeze, Auth credential-storage integration and any real sensitive local persistence. A prototype that treats unencrypted or memory-only fallback as equivalent to durable encrypted storage is not acceptable.

**Required disclosure:** State plainly that trusted operators can access plaintext, native offline storage is device-protected rather than E2EE, web initially requires connectivity and does not guarantee offline drafts, and key/device loss can remove unsynced native data.

**Difference / reconciliation required:** Makes a significant proposed scope choice: initial web is online-only for sensitive data, unlike the current broad Drift-web/offline blueprint. User approval and later documentation reconciliation are required; this review does not implement or silently adopt that change.

**Approval status: Pending user approval.**

### D09 — Unpaired and archived write behavior

**Exact current proposal (verbatim):**

> Shared planner writes require a paired space; no shared content writes in an unpaired draft

**Recommended final wording — pending approval:**

> Allow shared planner creation/editing and provisional offline shared intents only for a paired space with exactly two active members and a valid current authorization/lease. A one-member draft supports only its name/time-zone metadata and online invite/abandon actions; no planner records or solo-to-shared automatic merge. Closed archives permit only eligible read/export/removal actions under P03–P06, not new planner records, edits or ledger corrections. Archived spaces are never reopened/reused. A future personal drafting scope requires separate approval.

**Alternatives and tradeoffs:** Solo drafting improves onboarding but adds ownership and sharing/merge questions. Editable archives can preserve personal usefulness but must be separate forks so they cannot rewrite the other person’s retained audit. Paired-only writes are less useful before invitation acceptance but give a clear first-release boundary.

**Security implications:** Enforce states/counts server-side with partial unique active-user membership, at most two active seats and commit-time space/count validation; do not trust disabled UI. A stale offline operation after unlink is denied, never retargeted to a new partner. Removal of privacy-managed content is a privileged lifecycle request, not an exception allowing arbitrary archive edits.

**Implementation dependencies:** Needs approved state definitions, synchronized membership context/epoch, guarded commands and cancellation/rejection UX. Exactly-two paired behavior is an additional decision proposed here, not already granted by D01’s maximum-two approval. Account recovery never mutates an archive back to draft/paired.

**Blocks database implementation?** Blocks membership state/count constraints and all shared-write authorization. Exact historical-seat representation can be chosen later without weakening the no-reuse rule, but the paired/draft contract must be approved first.

**Required disclosure:** Tell users they can explore the visual app before pairing but cannot create shared planner records until paired. Show archives as read-only with explicit export/removal and expiry, and clearly mark offline work as provisional.

**Difference / reconciliation required:** Retains the original paired-only scope while distinguishing ordinary writes from privacy-removal requests and narrowing proposed offline writes to the native capability approved under D08.

**Approval status: Pending user approval.**

### D10 — Account deletion and recovery grace

**Exact current proposal (verbatim):**

> Account deletion immediately disables access; cancellable for 30 days through a restricted recovery flow; cancellation does not restore former memberships

**Recommended final wording — pending approval:**

> Immediately disable ordinary application access and former-space rights at account-deletion confirmation, revoke device notification bindings and refresh sessions, and start a server-timed 30-day cancellation window for identity/private-profile purge. Require recent reauthentication for the request and verified restricted recovery for cancellation. Cancellation restores only the eligible private account state: no membership, archive visibility, pending shared commands, shared content or expiry-clock reset. Shared removal/expiry continues independently under P03–P08. At grace expiry finalize primary private-data/mapping and Auth identity purge within 24 hours, with the disclosed backup limit.

**Alternatives and tradeoffs:** Immediate irreversible deletion has less residual retention but no recovery. Suspending/restoring memberships can reconnect a person without their partner’s intent and conflict with D01/D02. A 30-day grace is a convenience with a retention cost; it is not a promise that all data can be recovered.

**Security implications:** Use current app_users/membership/epoch gates for immediate denial, not signOut alone: an unexpired access JWT can remain valid. [S2: sign-out behavior](https://supabase.com/docs/reference/javascript/auth-signout) A restricted recovery path returns no ordinary shared content and cannot cancel someone else’s removal. Durable jobs recheck cancellation state for private-account work, while independent shared privacy jobs retain their original deadlines. No blind Auth cascade into retained monetary facts.

**Implementation dependencies:** Needs account deletion state/deadline, idempotent lifecycle jobs and session revocation capability, private-account recovery allowlist, distinct shared vs private cleanup scheduling, P02 mapping erasure, P08 backups and clear confirmation UX. Reauthentication policy must be tested with the chosen real Auth method; no new Auth screen is implemented here.

**Blocks database implementation?** Blocks account lifecycle, recovery and erasure schemas/routines. Approval must be explicit together with P07; identity prototype work alone is not a reason to freeze contradictory deletion semantics.

**Required disclosure:** “You may cancel account deletion for 30 days. This will not reconnect you or restore removed shared material. Some private data remains during grace and in backups for the disclosed period.” Include the remaining partner’s limited audit horizon.

**Difference / reconciliation required:** Keeps the original immediate-disable/30-day/no-membership-restoration direction, but rejects an implied stop-all-cleanup or full-recovery promise; shared-space clocks are independent.

**Approval status: Pending user approval.**

### D11 — Calendar recurrence edge cases

**Exact current proposal (verbatim):**

> Missing monthly days/Feb 29 are skipped; DST gaps advance to first valid local instant and folds choose the earlier offset

**Recommended final wording — pending approval:**

> Store an explicit per-rule invalid-date policy, initially last_valid_day or skip. Default monthly day-29/30/31 rules to the last valid day in a shorter month and annual Feb-29 rules to Feb 28 in non-leap years; show the choice before saving and let the user select skip. Keep local date/time plus IANA zone; for DST gaps choose the first valid local instant after the gap and for repeated times choose the earlier offset. Use one versioned ruleset on client/server, stable nominal-period occurrence keys, and separate actual observed dates/UTC instants. All-day dates remain dates, not UTC-midnight conversions.

**Alternatives and tradeoffs:** Skipping invalid dates preserves plain RFC-style behavior but can omit an anniversary for three years. Month-end fallback matches some expectations but changes the observed day, so it must be visible and stored. Mar-1 or later-fold options add complexity and are deferred; users needing them can explicitly reschedule an occurrence. Changes to existing series require an explicit confirmation policy rather than silently rewriting past occurrences.

**Security implications:** Duplicate/shifted reminders can expose private events at unintended times. Bound recurrence expansion, deduplicate notification scheduling by rule/version/nominal occurrence, and check current membership at send time. Device clocks do not determine accepted order or server reminder eligibility. Time-zone database updates must not silently duplicate already delivered notifications.

**Implementation dependencies:** Needs new invalid_date_policy/ruleset-version fields and an occurrence key that can represent a nominal invalid day without inserting an invalid SQL date. The existing date_occurrence_overrides.original_date-only key is insufficient for fallback identity: use rule ID + nominal year/month/anchor tuple or period ordinal, with a distinct valid observed_date and explicit series-edit migration. Test leap years, end-of-month, zones and DST folds/gaps. Plain RRULE invalid-date expansion skips invalid dates. [S4: RFC 5545](https://www.rfc-editor.org/info/rfc5545/) Therefore, fallback semantics require explicit expanded dates/metadata or an interoperability strategy, not an unsupported claim of transparent RRULE round-trip.

**Blocks database implementation?** Blocks recurrence/override schema and scheduler implementation; it need not block a separately authorized membership slice. Do not freeze the current original_date key before this decision is made.

**Required disclosure:** Preview the next few dates and source timezone. Show “last valid day” versus “skip,” explain Feb-29 observance and daylight-saving adjustments, and warn when changing the rule affects future occurrences.

**Difference / reconciliation required:** Intentionally proposes changing the original skip-invalid default while retaining its DST choices. Existing dates/recurrence documents are not updated to this proposal until the user approves it.

**Approval status: Pending user approval.**


## 4. Consolidated lifecycle recommendation — pending approval

This table disambiguates access deadlines from primary physical removal and inaccessible backup residue. P01–P09/D04/D10 must be approved together or explicitly reconciled before implementation; none of the values is currently approved.

| Class / event | Read access ends | Recommended primary-copy deadline | Backup / recovery boundary |
| --- | --- | --- | --- |
| Ordinary shared item/photo removal | At committed removal/block for both partners | Within 24 hours; dependent text/media/search/history copies included | Residual backup copies no longer than 35 days after primary purge; no user-facing trash/undo promise |
| Remaining-member text/media archive after ordinary unlink | Earlier of t_close + 30 days, an eligible removal, or either member’s account-deletion request | Within 24 hours after the earlier removal/expiry boundary | No restoration of archive access from recovery/restore; previously downloaded copies remain outside control |
| Minimal contribution audit | Earlier of t_close + 365 days or loss of its last eligible reader | Within 24 hours after that boundary; no reset by retry/export/cancellation | Residual backups follow the 35-day cap; no readable restored audit after expiry |
| Deleting account identity/private profile and its alias mapping | Ordinary access denied at t_delete; only restricted recovery remains for 30 days | Within 24 hours after t_delete + 30 days, unless valid cancellation stops private-account purge | At most 35-day residual backups after primary purge; proposed total bound up to 66 days after deletion request |
| Export artifact | At creation + 24 hours or earlier source access/privacy change | No later than creation + 24 hours; earlier invalidation triggers cleanup without extending that deadline | Do not include exports in routine backup jobs; already downloaded files cannot be recalled |
| Orphan/staging upload | At reservation expiry, revocation or abandonment | Within 24 hours after becoming orphaned; staging never becomes a public readable copy | Do not back up temporary staging/export data as if it were canonical media |
| Materialized sync snapshot | At 15-minute expiry or earlier epoch/privacy/access change | Privacy-triggered removal within 24 hours; expire and reclaim ordinary staging on bounded jobs | No serving from an expired/old-epoch snapshot; no inclusion in routine content backups |
| Tombstones and non-content sync markers | Authorized sync protocol only; never a source of intimate content | Prune at 90 days with snapshot fallback | No removed bodies, images, notes, amounts or original identity mapping in deletion markers |
| Minimal operational security diagnostics | Trusted operations only, no intimate payloads; redact personal labels at erasure | Proposed 90-day diagnostic window, except shorter purpose-bound removal; linked erasure manifest expires 36 days after related primary purge | Do not use logs/manifests to duplicate removed content or create a global perpetual identity index |

Time-bound jobs must deny access immediately at the policy boundary even if physical cleanup is delayed; failures must alert and be reported honestly, not treated as “successfully erased.” For live paired content not removed by an event, retain while both remain eligible and the item is in use; no arbitrary deletion after 30 days of creation is proposed. All closed-space clocks start at first closure, not creation or the next login.

**Example A — ordinary unlink:** close at day 0. Leaver loses server access immediately. The remaining member may read eligible text/photos before day 30 and minimal audit before day 365. Hide text/photos at day 30 and finish primary purge by day 31. If the last reader leaves at day 50, audit access ends then and primary audit purge finishes by day 51, not day 366.

**Example B — account deletion causes closure:** at day 0 deny the deleting account ordinary access and hide shared nonfinancial content from both people. Finish primary nonfinancial purge by day 1; the remaining member gets only eligible minimal audit. Private identity/profile recovery may be cancelled before day 30; otherwise finish its primary purge by day 31. With the proposed 35-day residual-backup cap, inaccessible private backup copies may remain until at most day 66. Canceling at day 10 does not republish shared media, reconnect partners, or reset the audit/archive clocks.

**No-copy recall:** read denial is not a guarantee of erasure from a device already holding data. Native local encryption and leases limit cooperative app access, not the knowledge or saved exports of either partner. Initial web has no durable sensitive offline store under proposed D08, but browser memory, screenshots and extensions still have risks.

## 5. Contradictions, changes and feasibility gates still to resolve

These recommendations intentionally differ from some existing designs. Do not silently rewrite the originals or implement both interpretations. The Part 1 gate remains authoritative until explicit approval and a subsequent reconciliation task.

| ID | Unresolved mismatch / risk | Required resolution before implementation |
| --- | --- | --- |
| C01 | Earlier offline-first descriptions include persistent Drift web storage; proposed D08 initially restricts sensitive web data to online/session-memory use | Approve initial platform capability difference or choose an alternative browser security design; update repository/outbox contracts and UX only afterward |
| C02 | Existing ledger schema includes immutable note/context fields and precise timestamps, and goal/member references can carry identifying context | Approve P01/P02; separate financial facts, removable notes, goal stubs and private identity mapping; no hidden full-row retention through views, FKs, logs or backups |
| C03 | Conditional archive eligibility was open; existing state diagrams/constraints alone cannot express content-class deadlines | Approve P03/P09/D09; specify first closure, reader eligibility and class-specific read/purge deadlines; no automatic full archive grant |
| C04 | Append-only full after-images/immutable snapshot payloads cannot simply keep erased notes until generic retention expires | Approve P08/D04 and design an atomic privacy epoch/history-floor reset, sanitized snapshots and stale-page denial without losing monetary/order integrity |
| C05 | Account cancellation could be interpreted as stopping all cleanup or restoring the former space | Approve P07/D10's limited private-account recovery and independent shared expiry/removal; confirmation copy must disclose irreversible shared-data loss |
| C06 | Original D11 skips invalid dates and uses valid original_date keys; proposed fallback requires a nominal occurrence identity that can represent an invalid anchor | Approve D11 and revise the occurrence-key/ruleset design before recurrence migrations; explicitly address RRULE interoperability and DST policy differences |
| C07 | Auth session revocation/expiry and signed-object delivery do not by themselves prove immediate access loss for a former member | Keep live account/member/content checks; prove old-JWT and old-URL denial under D02, D06/D07/D10. Never rely on short token TTL alone |
| C08 | Proposed native encryption, 24-hour purge targets and 35-day backup cap have not been verified on an actual deployment | Complete platform/job/backup feasibility and restore drills before publishing promises. Database backups do not include Storage object bytes; the object inventory and any canonical-media backup need their own bounded recovery/removal plan. [S5: backup scope](https://supabase.com/docs/guides/platform/backups) |
| C09 | Either account's deletion would remove the other person's nonfinancial shared work; unilateral removal/review can also suppress their material | Obtain explicit approval and disclosures for this privacy-first tradeoff; do not present it as an unavoidable technical rule or a currently approved entitlement |
| C10 | Purpose/jurisdiction/legal obligations for a 365-day self-reported contribution audit or exceptional preservation are not established | Review applicable obligations before launch; if a mandatory rule conflicts, return for a revised explicit policy rather than inventing an indefinite legal hold |

**Recommendation coherence:** the timeline above resolves internal clock ambiguity in this candidate package. The remaining conflicts are between this unapproved candidate and earlier open designs, plus unverified platform/operational feasibility. There is no claim that the architecture documents now describe an approved production backend.

## 6. Approval requirements and safe next sequence

1. User approves or revises each of P01–P09 and D04–D11 (17 pending entries), or explicitly approves the complete package as written. Cross-references/dependencies do not silently approve another entry. D01/D02 remain approved to their recorded scope; D03's broad revised direction remains recorded and its details remain pending.
2. Highlight the consequential choices: loss of shared text/photos on either account deletion; 30-day ordinary archive versus 365-day minimal audit; limited private-account recovery without shared restoration; online-only sensitive web data initially; and invalid-date fallback instead of skip. Resolve any rejected/partially approved combination coherently.
3. Only after approval, separately authorize a documentation reconciliation/schema-design task. Update DATA_MODEL, SECURITY_MODEL, OFFLINE_SYNC, DATA_LIFECYCLE, PARTNER_LINKING and APPLICATION_CONTRACTS to the accepted policies, including minimal ledger fields, eligibility/deadlines, privacy epoch and nominal recurrence keys. Preserve a decision-history link and unapproved alternatives.
4. Separately authorize implementation scope. A narrow local development database slice could then be designed/tested with explicit migration permission; credentials/live production projects and Auth implementation still require their own authorization. Do not start product modules as a side effect of approval.
5. Gate real sensitive-data use on adversarial authorization/concurrency tests, exact-money/native-web codec tests, ciphertext/key-loss tests, Storage revoke/remove/cache tests, deterministic recurrence tests, privacy-aware sync/snapshot tests, and database/object backup restore drills. Current Flutter widget tests do not prove any of those backend guarantees.

**Can database implementation safely begin now? No.** The policy recommendations are unapproved, some existing schemas/protocols need reconciliation, deployment capabilities remain unproven, and no database implementation/migration authorization has been given. Documentation review and explicit approval resolution are the next safe task. No backend was connected to create this review.

## 7. Technical references and provenance

Verified against primary documentation on 28 October 2026. These references support platform/format mechanics only; they do not prescribe Twogethera's proposed retention periods, privacy policy or legal obligations.

- **S1:** [Supabase private asset delivery and signed URL behavior](https://supabase.com/docs/guides/storage/serving/downloads). Authenticated delivery and signed URLs are distinct; Auth signing-key changes do not by themselves revoke existing Storage signed URLs.
- **S2:** [Supabase sign-out reference](https://supabase.com/docs/reference/javascript/auth-signout). An unexpired access token can outlive sign-out; current authorization checks remain necessary for immediate app-level denial.
- **S3:** [Drift encryption](https://drift.simonbinder.eu/platforms/encryption/). Encrypted local storage requires an appropriate configured executor and key lifecycle; no package/configuration has been added here.
- **S4:** [RFC 5545 recurrence rules](https://www.rfc-editor.org/info/rfc5545/). Plain recurrence-set generation omits invalid dates/nonexistent times; Twogethera's suggested observed-date/gap policy needs explicit handling and interoperability tests.
- **S5:** [Supabase database backup scope](https://supabase.com/docs/guides/platform/backups). Database backup coverage does not include the actual Storage object bytes; do not infer photo recovery or erasure coverage from a database backup setting.

Original proposal text comes from the existing architecture register and Part 1 privacy-choice table, copied verbatim. Earlier proposals and user approvals remain intact; this file records advisory pending alternatives only.

## 8. Validation scope

Documentation-only verification checks decision coverage, verbatim original proposals/choice descriptions, explicit pending statuses, Markdown tables/fences/anchors/links, cross-policy timeline consistency, and Git changes against the starting Part 1 working state. Flutter/backend tests are not substitutes for these checks, and no runtime code is changed. Actual final validation outcomes are recorded after the consistency checks.

### Completed documentation validation

- All 17 entries are present: P01–P09 and D04–D11. Each has its exact existing source text, a specific recommendation, relevant risks/tradeoffs, implementation implications/dependencies, disclosure, gate and **Pending user approval** status.
- Original D04–D11 proposal wording and P01–P09 choice/options wording matched the starting source files exactly. D01/D02 approvals and D03's recorded direction were not changed.
- Twelve Markdown files (project README plus current architecture documents) passed local-link, table-width and code-fence checks. This candidate uses no new Mermaid diagrams; existing diagram text was not rendered in this phase.
- Ten reconciliation/feasibility issues are explicitly recorded in section 5. The common timelines and two examples distinguish access removal, primary purge and residual backups; no current-policy approval is inferred from recommended numbers.
- Only this new file and appended navigation footers in architecture README/APPROVAL_REVIEW changed during Part 2. The original two file bodies remain byte-identical prefixes. All other starting tracked and Part 1 document fingerprints are unchanged, including approved Flutter/native/web/design files.
- `git diff --check` passed. Git HEAD and the staging area stayed unchanged. Existing uncommitted Part 1 edits were preserved; no commit or push occurred.
- No Flutter checks were rerun for Markdown-only work, and no runtime/backend/security implementation was represented as tested. Public primary documentation was consulted; no live project or credential was accessed.

**Stopping point:** review produced; all recommendations await explicit approval. Database implementation cannot safely begin under the current approvals and task authorization.
