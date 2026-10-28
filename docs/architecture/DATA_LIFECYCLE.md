# Data lifecycle, export, unlinking, and erasure

**Proposed product policy, not a legal compliance claim.** D02–D04/D07/D08/D10 in the [approval register](README.md) require approval before implementation. Jurisdiction, consent wording, retention obligations, operator access, and actual provider backup retention need review before launch.

## Ownership and scope

Private profile/preferences/devices belong to the account and are never copied to its partner. Planner text, accepted savings records, and ordinary activities belong to their original couple scope and are shared while authorized. Authorship is recorded by membership ID, not by copying email into each entity. A new partner gets a new space; prior content, archives, queue entries, photo paths, and ledger balances never transfer automatically.

Uploaded photos receive special treatment under D03: account erasure removes the departing person's uploaded photos and captions from retained archives, while shared text/financial records become pseudonymously attributed. A person can also be depicted in another person's photo; uploader-based deletion alone does not resolve all privacy claims. Provide an identity-verified privacy request path and human review procedure without granting former membership access. This is a launch risk and approval issue, not something an FK can solve.

## Lifecycle matrix

| Event | Server effect | Device effect / eventual cleanup |
| --- | --- | --- |
| Normal edit | Revision-checked transaction, change log, safe activity and receipt | Local intent pending until accepted; pull converges |
| Ordinary entity removal | Tombstone, revision, child tombstones/link cleanup; read projections hide immediately | Remove local visible row/search/media; retain minimal tombstone through retention horizon |
| Category removal | Clear dependent live item category with revisions, then tombstone category | Items remain, with no category; no silent child loss |
| Savings goal removal | Archive goal; never edit/remove accepted ledger rows | Read audit history, reject pending new records unless explicit reopen succeeds |
| Unlink | Immediately revoke leaver, archive other member, archive space, bump epoch, revoke invitations, personal access events | Leaver wipes scope when known; stayer retains read-only authorized archive and clears pending writes; both may form new spaces |
| Archived reader removes archive | Space -> purging and last reader revoked; later idempotent object/database purge | Hide/wipe archive; former users cannot restore it with old commands |
| Abandon unpaired draft | Revoke sole member/invites; space -> purging | Wipe draft; no shared planner content exists by D09 |
| Sign out / account switch | Disable local installation token binding through online sign-out if possible; Auth session termination; other sessions unaffected unless explicitly revoked | Immediately lock/wipe this account's cache and auth material; no pending-data upload to next account; warn before sign-out if unsent intents will be lost |
| Device revoke | Mark device revoked, disable token bindings, deny subsequent commands/status pulls for that registered device | On next verification lock/wipe; a malicious device can still use a valid user session for table reads until session revocation, so revoke its Auth session too; no promise to recall previously cached data |
| Account deletion request | Immediately app_user -> deleting, unlink current couple, revoke archived access, tokens and invitations; restricted recovery only | Lock/wipe shared/private cache; no offline cancellation or post-revocation export |

RLS for direct authorized read surfaces checks account and current membership; per-device revocation alone is not a substitute for Auth session revocation or account/space checks. Registering a new installation does not bypass a revoked Auth session. Whether a deployment can revoke exactly one Supabase Auth session must be verified; until verified, use account-wide session invalidation for the revoke-all action and disclose the effect.

## Retention proposal

| Record / bytes | Proposed retention / purge condition |
| --- | --- |
| Live paired data | Until user-authorized entity/space deletion or approved account-erasure rules |
| Remaining partner's archive | Until they remove it or their account is erased; no reactivation; explicit D03 approval needed for indefinite retained shared text/ledger |
| Ordinary tombstones and durable change pages | At least 90 days; `retention_floor` advances only with an enforced snapshot fallback; disconnected clients do not block purge forever |
| Success idempotency receipts | Scope lifetime; compact hashes/results only; not pruned with 90-day change history |
| Accepted ledger records | Append-only through lifetime of paired/archived scope; whole-space purge may erase them |
| Pending/expired invitation digests | Expire at 24 h; terminal invite records scrub recipient HMAC/token digest after 90 days; keep only minimal audit outcome if needed |
| Staging/orphan uploads | Inaccessible immediately after reservation expiry/revocation; cleanup within 24 h target with retries/alerts |
| Removed ready photo bytes | Metadata authorization disappears immediately; delete original/derivatives through Storage API within 24 h target, retry failures |
| Materialized sync snapshots | 15 min; access rechecked during fetch; chunks delete with header |
| Export artifacts | At most 24 h and revoked immediately when source access lost; user-downloaded copies outside server control |
| Activity/security audit | 90 days proposed; redact PII on erasure; no intimate payloads |
| Account deleting state | Access disabled immediately; 30-day restricted cancellation grace before final identity/private-data purge |
| Provider backups / logs | Verify actual deployment retention/restore behavior; do not advertise a fixed expiry before selecting configuration |
| Local data/media | Read locks at lease expiry pending revalidation; purge on known revocation/sign-out/explicit clear; best-effort physical deletion, no guaranteed secure flash erasure |

Cleanup targets are operational SLO proposals, not guaranteed platform execution times. Each job is idempotent with lease/retry/backoff, durable progress, bounded batches, and failure visibility. No silent “deleted everywhere” acknowledgement while bytes still await cleanup.

## Tombstones and hard deletion

Ordinary removal strips sensitive body fields when no longer required and emits a minimal ID/revision/deletion timestamp per entity. All referential changes are versioned and stream-visible. Snapshot readers never need a historical deleted body. Entity IDs cannot be reused.

Large cascades first set the server-managed root deletion_started_at (whole space uses purging) so reads, child writes, and uploads stop; process child tombstones in bounded ordered transactions, then finish the parent. Do not implement an unbounded recursive cascade or release the parent as live while its children are being removed.

Before advancing retention_floor, ensure snapshot transport is available and all still-readable current rows/ledger can be snapshotted. Do not purge receipts simply because every device acknowledged a cursor. A stale device must full-snapshot and check pending operation status before rebase; it cannot resurrect purged IDs. After a scope loses all readers, content can be physically purged in child-first order, including receipts/logs, and its scope ID remains permanently nonreusable.

## Export protocol

Online request only, from an eligible account with current read access. A user may export own private profile/preferences and shared data from each currently readable scope; never another person's private profile, Auth identity, token, invite digest, security logs, or unrelated archives. Include permitted shared ledger history with precise currency/exponent/decimal-string minor units, human-readable CSV, schema version, UTC generated-at, source-zone/date semantics, snapshot high-water, and a file checksum manifest. Images are optional, separately selected, and subject to current authorization/erasure checks.

Generate from a consistent authorized snapshot. A trusted export worker binds the job to requester/scope/epoch and rechecks authorization before starting, before publishing, and on every download request. If access changes, cancel/delete the artifact. Download uses an authenticated endpoint, not a durable signed public/bearer link. Files remain private and are automatically removed within 24 hours. Escape spreadsheet-formula leading characters in human-readable CSV text cells while retaining exact raw strings in machine-readable JSON; money in CSV is textual decimal/minor-unit representation, never float conversion.

An authoritative export excludes unaccepted outbox operations unless the user separately chooses an **unconfirmed local draft export while still authorized**. That draft export is prominently labeled and cannot be treated as financial truth or used as a membership bypass. Unlinking must not depend on export completion; offer it beforehand without delaying exit for safety reasons. Exports already downloaded by either partner cannot be recalled.

## Account deletion saga

1. Recent real authentication + explicit user intent. Mark app_users deleting in a transaction and lock its affected users/scopes in canonical order. This immediately fails `eligible_user()` everywhere; revoke current membership, convert remaining partner to archived, revoke own archived reads, bump affected epochs, disable device tokens/invites, enqueue lifecycle work, and emit other authorized users' safe access changes. For many archives, the account state is the immediate global deny; process scope cleanup in bounded jobs.
2. Auth sessions are revoked using a trusted backend. Restricted cancellation/recovery can authenticate identity but has no general application-data grants while app_user is deleting. Grace cancellation sets account active after verification, but does not reinstate memberships, invitations, revoked devices, or wiped client queues; user starts unlinked.
3. Prevent reads of attachments uploaded by deleting accounts immediately through the Storage/metadata predicate, even before the worker reaches every old archive. Keep membership-to-user linkage until its uploaded-photo tombstones and byte cleanup are scheduled. Worker strips that person's uploaded photos/captions, emits tombstones to still-authorized archives, and removes derivatives/raw staging objects with retries. After an accepted cancellation, workers recheck the lifecycle state and stop further account-erasure work; already revoked memberships are not restored. Cancellation cannot restore already removed media; warn before confirmation.
4. After 30 days, erase private profile/preferences/devices/token records/exports/personal sync records; delete or redact relevant security/audit personal identifiers. Remove personal user references from retained memberships/contributions/activity according to D03, keeping member IDs and amounts to preserve the other partner's ledger. Shared text is retained under the proposal, but must not preserve structured email/profile labels by accident. Free-text privacy requests require a separate reviewed process.
5. Purge zero-reader spaces child-first. Cancel/expire snapshot/export jobs, remove related operational FKs, and delete user-scope records/receipts before deleting app_users. Finally delete the managed Auth identity after all owned Storage objects have been handled. Do not use a blind cascade from `auth.users` to shared couple data. Persist minimal non-PII job/audit completion evidence only for approved retention.
6. A failed job remains disabled/deleting and resumes safely; never reactivate access to make cleanup easy. Keep a deletion manifest/checklist so backup restore replays erasures before making restored data available. Provider backups may retain inaccessible older copies until expiry; clarify this in the privacy policy and test recovery procedures.

## Privacy limits to disclose

Neither offline remote wipe nor recall of screenshots/downloaded exports is technically guaranteed. A partner had legitimate read access before unlinking. Server-side encryption does not prevent trusted operator access, and no E2EE claim is made. Browser persistence may be evicted or inspected by extensions/XSS. Retention of another person's contributions/text is a policy choice requiring consent/legal review. The architecture provides enforcement mechanisms; CP-002 does not establish legal compliance or certify a secure deployed system.
