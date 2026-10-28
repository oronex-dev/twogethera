# CP-002 architecture approval review and Git baseline

> **Historical decision record.** The body below preserves this review stage and its then-current statuses. The latest user directions and reconciled proposals are in [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md). Earlier blanket nonfinancial deletion, no-text-recovery and automatic 365-day audit recommendations are superseded there; they are not current policy. D01/D02 approvals and D03's recorded revision remain unchanged.

Prepared 28 October 2026. **CP-003B Part 1: D01 approved; D02 approved with safeguards; D03 revised policy recorded, with implementation privacy choices unresolved. D04–D11 remain pending.** Titles are review labels. D01–D03 below reflect the current user decisions, superseding earlier advisory recommendations. D04–D11 preserve the original proposals/consequences and remain advisory. See [the resolution record](D01_D03_RESOLUTION.md) for open P01–P09 choices.

## Baseline and validation

- User authorized local Git initialization on `main` and the baseline commit `chore: establish Twogethera foundation and architecture`. No remote or push is authorized.
- Existing generated Flutter/native ignores are retained. Root ignore rules now also cover local environment secrets, signing/private-key material, deployment credential files, local databases/media/exports/backups, and packaged build outputs. Placeholder-only `.env` example templates may be versioned after review.
- Initial source/document scan: 105 UTF-8 text files, no configured credential-pattern matches; no sensitive filename candidates outside known ignored build/tool caches. This is a scoped scan, not a guarantee that every possible secret format is detectable.
- Existing ignored `android/local.properties`, generated native configs/registrants, IDE state, and build/QA outputs are expected generated artifacts and must not be staged.
- Validation and staged review results are recorded below. Existing CP-002 “not a Git repository” passages describe the historical state when CP-002 was completed.

## Approval register

### D01 — Couple membership and archives

**Recorded user decision (verbatim):**

> One active couple space per account, maximum two active members. Archived spaces cannot be reopened or reused with a replacement partner.

- **Approval status:** Approved.
- **Effect:** One active couple space per account and at most two active members; no reopening or replacement-partner reuse of archives. Existing draft/paired state details remain proposed rather than newly approved. Technical constraints still require later implementation and tests.
- **Implementation gate:** Validate the active-membership and no-reuse constraints later; no database implementation is authorized now.

### D02 — Unlinking and remaining-partner access

**Recorded user decision (verbatim):**

> Either partner may unlink independently. The departing partner immediately loses server access. The remaining partner may receive a read-only archive, subject to the D03 privacy and retention rules. Do not claim that previously downloaded data can be remotely erased.

- **Approval status:** Approved with safeguards.
- **Effect:** Unilateral unlinking is approved. Departing users lose former-scope server access immediately. Remaining-partner archives are conditional on D03, not guaranteed full-content retention. Existing downloads cannot be remotely recalled.
- **Implementation gate:** Resolve the applicable [P01–P09 privacy choices](D01_D03_RESOLUTION.md) before archive/retention/export/erasure implementation; no fallback policy is selected.

### D03 — Shared records and account erasure

**Recorded user decision (verbatim):**

> Preserve only necessary, auditable contribution history with pseudonymized attribution after account deletion. Shared text, notes, and photographs must have a clearly documented removal, retention, and export process. Do not assume indefinite retention of all shared content.

- **Approval status:** Revised policy recorded; implementation privacy choices unresolved.
- **Effect:** Only necessary contribution audit history is preserved with pseudonymized attribution. Shared text, notes and photos require an explicit removal/retention/export process; indefinite retention is no longer a default. Minimal fields, pseudonymization, audience, timing and derived-copy cleanup remain unresolved.
- **Implementation gate:** Resolve the applicable [P01–P09 privacy choices](D01_D03_RESOLUTION.md) before archive/retention/export/erasure implementation; no fallback policy is selected.

### D04 — Retention and offline access limits

**Current proposal (verbatim):**

> Change log/tombstones retained at least 90 days; offline read lease at most 7 days; account deletion grace 30 days; unreferenced uploads 24 hours; exports 24 hours

**Documented consequence (verbatim):**

> Stale clients require full snapshots; cached offline data cannot be remotely recalled

- **Alternatives:** Shorter or longer change retention; online-only sensitive reads; shorter default leases with an opt-in extension; immediate or delayed account deletion.
- **Security and UX:** Long leases improve travel/offline use but extend access on disconnected revoked devices. Tombstones and snapshots avoid resurrection. Longer retention increases sensitive-data exposure; deletion grace can conflict with immediate media cleanup.
- **Recommendation:** Keep 90-day history, 30-day deletion grace, and 24-hour orphan/export targets provisionally. Prefer a 24-hour default offline lease, with an explicit opt-in extension up to seven days; do not promise instant remote wipe.
- **Finalize before database implementation?** Yes for synchronization floors, account lifecycle, and lease enforcement. Operational cleanup targets can be tuned later without silently extending published privacy commitments.
- **Approval status:** Pending user decision.

### D05 — Savings currency and audit integrity

**Current proposal (verbatim):**

> One immutable ISO currency and minor-unit exponent per savings goal; recorded deposits and exact reversals only; no FX, bank integration, interest, or withdrawal workflow initially

**Documented consequence (verbatim):**

> Amounts never use floating point; planner records do not claim to verify real bank balances

- **Alternatives:** A couple-wide fixed currency; separately tracked multi-currency goals; or explicit withdrawals/FX records.
- **Security and UX:** Exact minor units prevent rounding errors. Reversals preserve history. Fixed per-goal currency avoids ambiguous conversions; lack of withdrawals limits real-world cash-flow tracking. This remains a planner, not a verified bank balance.
- **Recommendation:** Keep the current exact-money, fixed-per-goal currency, append-only deposit/reversal model. Add withdrawals later only as a separate approved auditable event type.
- **Finalize before database implementation?** Yes — currency keys, amount checks, immutable fields, and ledger commands depend on it.
- **Approval status:** Pending user decision.

### D06 — Partner invitation identity and expiry

**Current proposal (verbatim):**

> Invite is bound to a verified email identity, lasts 24 hours, and is single-use; user shares the link manually

**Documented consequence (verbatim):**

> No anonymous redemption or automatic email delivery; changing recipient requires a replacement invite

- **Alternatives:** Bearer-token-only invitations; shorter expiry; recipient request plus inviter confirmation; or automatic email delivery.
- **Security and UX:** Email binding limits damage from a forwarded link but requires the intended verified account. A 24-hour lifetime is convenient. Single-use tokens and atomic acceptance prevent duplicate linking; rate limits are still required.
- **Recommendation:** Keep verified-email binding, single use, 24-hour expiry, and manual sharing. Show the masked intended identity and support explicit revoke/regenerate.
- **Finalize before database implementation?** Yes — invite schema, identity validation, expiry, and acceptance protocol depend on it.
- **Approval status:** Pending user decision.

### D07 — Private photo delivery

**Current proposal (verbatim):**

> Private photo bucket with authenticated reads; no downloadable signed bearer links in the initial product

**Documented consequence (verbatim):**

> Membership is checked on subsequent online reads; copies and in-flight bytes cannot be recalled

- **Alternatives:** Short-lived signed URLs; an authenticated media proxy; or E2EE object delivery.
- **Security and UX:** Authenticated reads permit new requests to check current membership. Signed bearer URLs are convenient for caching but can survive access changes until expiry. No option can recall bytes already downloaded or in flight.
- **Recommendation:** Keep private buckets and authenticated downloads initially. Verify Storage policies, derivatives, and cache behavior; do not introduce public media URLs.
- **Finalize before database implementation?** Before Storage schema/policy implementation; it need not block an isolated identity-table prototype.
- **Approval status:** Pending user decision.

### D08 — Encryption and trust model

**Current proposal (verbatim):**

> Trusted-server model, not end-to-end encryption; native key storage/encrypted local persistence require a separate technical spike; web has weaker local secrecy

**Documented consequence (verbatim):**

> Do not advertise E2EE or equivalent browser/device security; user must understand offline cache risk

- **Alternatives:** E2EE with device/partner key management; native-only encrypted local storage; or online-only web access for sensitive data.
- **Security and UX:** A trusted-server model is simpler for recovery, search, and sync, but operators can access plaintext. E2EE complicates recovery, linking, exports, server jobs, and key revocation. Browser persistence cannot be assumed as private as protected native storage.
- **Recommendation:** For the initial product, retain the trusted-server model with clear disclosure. Make the native encryption/web-security spike a prerequisite to shipping persisted sensitive data. If E2EE is a product requirement, decide now because it changes this design substantially.
- **Finalize before database implementation?** Yes — decide the trust model before schema freeze; validate local-storage protection before real sensitive data is persisted.
- **Approval status:** Pending user decision.

### D09 — Unpaired and archived write behavior

**Current proposal (verbatim):**

> Shared planner writes require a paired space; no shared content writes in an unpaired draft

**Documented consequence (verbatim):**

> No offline acceptance, unlinking, or contributions to an unpaired/archived space

- **Alternatives:** Allow solo drafting before pairing; allow private personal content that can later be explicitly shared; or let archived members edit their own fork.
- **Security and UX:** Paired-only writes simplify ownership and avoid uncertain merges. They also make onboarding less useful until a partner joins. Archived edits would need a separate fork/export model so they cannot alter the former partner’s retained record.
- **Recommendation:** Keep paired-only shared writes for the first release. Evaluate private solo drafts later as a separate scope, with an explicit sharing action.
- **Finalize before database implementation?** Yes — it affects state-based authorization and data ownership.
- **Approval status:** Pending user decision.

### D10 — Account deletion and recovery grace

**Current proposal (verbatim):**

> Account deletion immediately disables access; cancellable for 30 days through a restricted recovery flow; cancellation does not restore former memberships

**Documented consequence (verbatim):**

> Other partner is not held hostage to account recovery or deletion consent

- **Alternatives:** Immediate irreversible erasure; shorter grace; or retaining memberships in a suspended state during grace.
- **Security and UX:** Immediate access denial protects the departing user. A recovery window helps accidental deletions, while restoring old memberships would surprise the other partner. Current lifecycle rules can remove media before grace ends, so cancellation must not imply full restoration.
- **Recommendation:** Keep immediate denial, 30-day restricted cancellation, and no automatic membership restoration. Explicitly disclose irreversible media effects; resolve their timing with D03/D04 before implementation.
- **Finalize before database implementation?** Yes — account states, cleanup scheduling, recovery permissions, and membership transitions depend on it.
- **Approval status:** Pending user decision.

### D11 — Calendar recurrence edge cases

**Current proposal (verbatim):**

> Missing monthly days/Feb 29 are skipped; DST gaps advance to first valid local instant and folds choose the earlier offset

**Documented consequence (verbatim):**

> Recurrence previews and reminder scheduler must share a versioned ruleset

- **Alternatives:** Use month-end for invalid monthly dates; observe Feb 29 anniversaries on Feb 28 or Mar 1; allow a per-event invalid-date policy; choose the later offset during repeated DST time.
- **Security and UX:** Skipping is deterministic but can unexpectedly hide an anniversary for three years. Month-end fallback better matches some human expectations, while silent shifting can also surprise users. Both devices and the scheduler must generate the same occurrence identity and instant.
- **Recommendation:** Keep the proposed DST gap/fold rules. Before recurrence schema work, offer an explicit invalid-date policy; recommend Feb 28 fallback for annual Feb 29 anniversaries and a visible skip/month-end choice for monthly dates. This is a proposed change, not an approval.
- **Finalize before database implementation?** Before recurrence tables/contracts and scheduling are finalized; it need not block identity and membership work.
- **Approval status:** Pending user decision.

## Recommended next task

D01–D03 have been addressed at the product-policy level as recorded above. Resolve P01–P09 before the affected privacy implementation; D04–D11 remain pending and are outside CP-003B Part 1. Do not treat visual approval, this record, or prior recommendations as approval of those remaining decisions.

After approval, CP-003 should start with pure domain identity/scope/revision/Money values and focused tests, then the approved persistence/security feasibility work in an isolated development environment. Database migrations and real authentication require explicit implementation authorization; they are not started by this review. Prove membership isolation, concurrent invite acceptance, idempotency, exact money, and revocation before product modules. No live Supabase project or paid dependency is needed for this review.

## Historical baseline verification (before CP-003B)

- `flutter analyze`: passed, no issues found.
- `flutter test`: all six original tests passed.
- `dart format --output=none --set-exit-if-changed lib test`: passed, 12 files unchanged.
- `flutter build web`: passed, including Wasm dry run; the existing optional Cupertino font-reference notice remains. No new dependencies or runtime changes were introduced.
- SHA-256 comparison: all 56 recorded CP-001 application/configuration/test files unchanged.
- Staged review: 124 files, including 96 text files and 28 expected PNG assets; no configured credential-pattern matches, excluded generated paths, unexpected binaries, or sensitive filename candidates in the index. `git diff --cached --check` passed.
- Ignore probes confirm local secrets/signing/build/data files excluded, while `pubspec.lock`, application source, platform source and placeholder-only `.env.example` remain eligible for deliberate review.
- All 11 original proposals and consequences were programmatically checked against this review for verbatim reproduction; recommendations remain unapproved. Local documentation links pass.
- Disk at initial review: approximately 42 GiB free. Native builds were not repeated for this version-control/documentation task; previous native build results are historical evidence only.

This review is included in the local baseline commit named `chore: establish Twogethera foundation and architecture`. Obtain its identifier with `git log -1 --format=%H`. No remote, push, database migration, Supabase configuration, or authentication implementation is part of this task.

## Part 2 recommendation package — awaiting approval

[FINAL_DECISION_PROPOSALS.md](FINAL_DECISION_PROPOSALS.md) reviews all nine open privacy choices and D04–D11, with specific recommended wording, risks, dependencies, disclosures and pending approval states. It is an advisory candidate, not an amendment to recorded approvals or authorization to implement a backend. Earlier proposals and history above remain unchanged; reconcile designs only after explicit user approval.
