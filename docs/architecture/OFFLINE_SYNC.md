# Offline-first synchronization protocol

**Current decision specification:** [DECISION_SPECIFICATION.md](DECISION_SPECIFICATION.md) is the reconciled source for final proposed wording, status, tests, disclosures and implementation gates. D01/D02 approvals and D03’s recorded revision are preserved. Technical endorsement is pending formal approval; P03/P04/P09 product choices remain unresolved. No backend implementation is authorized.

**Specification only.** Drift is the future local store, Supabase the authoritative acceptance boundary. Neither dependency is installed for this phase. [Data model](DATA_MODEL.md), [security rules](SECURITY_MODEL.md), and approval decisions D04/D08/D09 apply.

## Reading and write guarantees

Native screens observe protected Drift query streams. Initial web observes session-memory repository streams backed by live authorized reads and online commands; it has no durable sensitive outbox/cache. Network responses never bypass repositories into widgets. The offline guarantees below apply only to the protected native capability, not web. Each scope has an authoritative accepted base plus a separate optimistic overlay derived from queued commands. Pending, conflicted, rejected, and accepted records are visibly distinct. A locally saved record is not presented as server-confirmed or delivered to the partner.

| Action | Offline behavior |
| --- | --- |
| Read authorized cached entities/photos | Allowed within a non-expired access lease, with last-synced/pending indicators; absent media remains unavailable |
| Create/edit ordinary bucket items, categories, dates, plans/tasks, memories | Local transaction plus durable outbox, with known active paired membership lease; eventual acceptance not guaranteed |
| Contribution/reversal intent | Exact bounded integer provisional entry only; accepted balance and provisional balance displayed separately; server validates/rejects on reconnect |
| Theme/dashboard/notification preference edits | Local update/outbox; OS notification permission remains a separate device fact |
| Choose local photos | Local file/metadata intent allowed within quota; no claim of remote upload until online reservation/processing/finalization |
| Register/verify/recover Auth, create/link/unlink couple, delete account/space, export authoritative data, register/revoke device token | Online only; never optimistically grant membership or display a deletion as completed |
| Edit archived/draft shared content | Rejected locally and on server; archived read-only or unpaired draft state is explicit |

Keep authenticated identity and scope partitions separate. Never display a previous account's database while a new account signs in. A new partner/couple gets a new scope and initial snapshot, not a re-labeled cache.

## Protected native Drift records

| Local table / store | Purpose and constraints |
| --- | --- |
| accepted entity mirrors | Server IDs, tenant IDs, revision, tombstone, authoritative values; no direct UI writes; unique scope/entity key |
| `pending_operations` | operation UUID PK, account ID, scope ID, captured authorization_epoch and privacy_epoch, entity ID/type, command/schema version, base revision, immutable payload, payload hash, dependencies, local sequence, state, attempts, next retry time, created-at hint, last safe error code |
| `operation_dependencies` | `(operation_id,depends_on_id)` PK; FK local outbox; dependency graph acyclic and scope-safe; parents submitted before dependent children |
| `local_sync_state` | account/scope PK, applied cursor, epoch, last authoritative access check, privacy_epoch, lease data, snapshot staging ID, error status; cursor changes only in the same transaction as applied rows |
| `local_conflicts` | operation ID, base/server versions and minimal proposed changes, safe failure type; account/scope-isolated; never silently discarded |
| `local_attachments` | attachment intent ID, scope/account, protected local path/blob reference, checksum, size, upload state, reservation expiry; bytes outside main SQL DB; bounded cache and cleanup |
| snapshot staging tables | New authoritative base populated page by page; not visible to normal UI until complete verification/atomic swap |
| local search projections | Rebuildable from authorized accepted/pending records; purged with scope; no global cross-account index |

Within one Drift transaction persist the user's intent, enqueue the operation, and update the visible overlay. If persistence/quota fails, report failure and do not show a successful save. [Drift transactions](https://drift.simonbinder.eu/dart_api/transactions/) supply atomic local updates, not distributed transactions with PostgreSQL.

An in-flight payload, operation ID, and request hash never change. Subsequent edits enqueue a dependent command rather than modifying an uncertain command. A never-sent command can be replaced before freezing/hash assignment. For a dependent edit whose base revision is not known yet, hold it as an unsent intent; assign the accepted parent revision and final immutable hash immediately before its first submission. Rebase is a new operation ID. Dependency rejection blocks descendants and exposes recovery, not infinite retries.

## Server command envelope and atomicity

Command input: protocol version, operation_id, registered device_id, scope_id, expected authorization_epoch and privacy_epoch, entity IDs, expected revisions, and a typed allowlisted payload. Identity comes from the session. The device ID must belong to the current user and not be revoked; it is not a credential. All integer protocol fields are decimal strings on the wire.

Processing order:

1. Authenticate, validate protocol/size, discover authorized lock targets, and acquire user/scope/root/entity locks in the [canonical order](PARTNER_LINKING.md). Recheck current account, device, and membership after locks. An old JWT does not preserve membership rights.
2. Check `(actor,operation_id)` receipt before revision/epoch validation for an already accepted command. Same canonical request hash returns the previous sanitized result only if actor still has current scope access. Different hash is `operation_id_reused`. Never return old content/receipts after access revocation. Linking receipt handling follows the same rule.
3. For a new command validate both captured epochs, allowed space/goal state, exact field types, all parent scopes/liveness, actor rights, revision preconditions, uniqueness, and financial constraints. No caller-set revision/timestamps/actor fields. Cross-feature child links require explicit scope checks.
4. Apply all effects, assign server revisions/timestamps, append safe activity and per-row change events, advance scope sequence counters, and insert the success receipt **in the same PostgreSQL transaction**. Multiple touched scopes are locked in UUID order. Failures roll back all business effects. Transient failures have no success receipt.
5. Commit before returning accepted state or dispatching generic invalidation. A lost response is resolved by retrying the unchanged operation or querying own operation status, not creating a new contribution ID.

Canonical request hashing is versioned: UTF-8 JSON with deterministically ordered keys, validated decimal strings, explicit null/omitted-field rules, command type/version, scope, device, expected authorization/privacy epochs and revisions, and payload. Exclude JWTs, retry counters, and network timestamps. Server recomputes the hash; a client-provided hash is not trusted. Receipts store request hashes and compact outcome/entity revisions, not intimate payloads. Receipt retention is a proposed deduplication mechanism to reconcile with D03/P08/P09; preserve necessary non-content evidence without treating scope lifetime as an exemption from privacy cleanup. Retention of change pages does not remove financial/idempotency protection. Entity UUIDs are never reused after deletion, and ledger `(couple_id,operation_id)` uniqueness is a second defense. Once a whole scope is purged, it cannot be reopened: old commands cannot resurrect it. An account's hard erasure removes its receipts only after its write permissions are irreversibly removed; only the necessary contribution audit history may remain with approved pseudonymization, audience and retention under P01–P03/P09; notes and personal labels do not receive blanket preservation.

## Ordering without a sequence-gap bug

A timestamp or PostgreSQL sequence/identity number allocated before commit is not a safe pull cursor: transaction N+1 could commit before N, making N permanently skippable. Use the locked `sync_scopes.last_sequence` counter instead.

Every scope mutation locks the same scope row and appends sequence values while holding that lock until commit. The next scope transaction cannot obtain a higher committed value before the previous transaction completes. Rollback restores the counter. This serializes a two-member space deliberately; optimize only after proving an equivalent commit-order guarantee. A multi-row command can append several contiguous entries; it commits them as a unit. Personal preferences use a separate user scope with the same rule.

`sync_changes` stores allowlisted authoritative after-images (not references to mutable current rows) and minimal tombstones. Each entry carries sequence, type, ID, revision, and kind. No table-name injection, arbitrary columns, auth email, token, invitation secret, or private profile leaks into a shared stream. A shared change-log event is not an activity feed event.

## Reconnection, pull, and checkpoints

1. A single coordinator runs per native device; protected database worker coordination prevents duplicate drains. Initial web uses an in-memory online request coordinator without durable sensitive commands or multi-tab shared storage. Server idempotency remains mandatory on both platforms.
2. Authenticate/refresh online, call `account_context()` to check account/device and discover only own active/archived scopes and epochs. Reconcile removed scopes **before** querying cached shared content or sending queued writes. Expired/offline tokens do not establish fresh membership.
3. Pull current changes before pushing; preserve local intents as a separate overlay. This catches revoked membership and many conflicts before upload. A member's own revoked state is discoverable through the personal context; it does not require access to the revoked couple stream.
4. First pull chooses an authorized committed high-water H. Return entries only for both current epochs where cursor < sequence <= H, sorted ascending, with bounded pages (200 records / 1 MiB target), both epochs, retention floor, and `has_more`. Floor is the lowest still-valid applied cursor (normally the first retained sequence minus one; if no events remain, the current head). Bind pagination cursor to requester/scope/device/both epochs/H; revalidate access on every page. Membership changes invalidate the session and restart context/snapshot, not just the next channel subscription.
5. Apply each complete page and advance the local cursor in one Drift transaction. Deduplicate by `(scope,sequence)` and entity revision; lower/equal revisions do not overwrite newer accepted state. For a transaction spanning pages, mark grouping and stage until all its entries are present, or choose page boundaries at transaction boundaries so related parent/children publish together. API must enforce one choice; initial choice is transaction-boundary pages with capped mutation size.
6. Freeze and send eligible commands in dependency/local-order, applying accepted results and receipts atomically to local accepted base plus outbox state. Lost responses remain uncertain and retry unchanged. Then pull again through a new H to reconcile other devices and server side effects.
7. Persist ACK only after local commit. Repeat on foreground, reconnect, periodic foreground timer, and generic realtime hints. Background/OS scheduling is best effort; no continuous sync guarantee. Duplicate/out-of-order hints never affect cursor correctness.

If the next indivisible transaction exceeds the page limit, return a documented oversize batch/snapshot-required response; never omit rows and advance cursor. Commands have bounded child count/transaction size; large parent deletion uses a server-managed deletion_started_at on the aggregate root (or purging for a whole space) and a privileged chunked lifecycle process with access denied until all child tombstones exist, rather than unbounded interactive transactions.

## Initial/stale snapshots

If the local cursor precedes retention_floor, no cursor exists, the protocol/schema is incompatible, or state is corrupt, return `snapshot_required`. Do not replay a partial retained history over an incomplete base.

`begin_snapshot(scope)` locks the scope, rechecks access and epoch, records committed head H, and materializes authorized live rows plus required ledger/member/archive state into private immutable `sync_snapshot_chunks` and a requester/device/authorization-and-privacy-epoch-bound header. Snapshot copy and header commit atomically before releasing the scope lock. Size/time quotas bound this initial implementation; if quota exceeded return explicit unsupported-size error, never inconsistent pagination. A later scalable snapshot worker requires a reviewed consistent snapshot protocol.

Fetch chunks by immutable ordinal/checksum, checking membership, both epochs, content eligibility and expiry each time. Stage locally, verify all chunks/checksums and protocol version, then atomically replace accepted base and set cursor H. Pending intents stay separate; compare their original base revisions against the new snapshot and expose conflicts. Pull changes > H afterward. A snapshot header/chunk set expires after 15 minutes; partial snapshots are discarded/restarted. No pagination over a changing live table across unrelated requests pretending to be one consistent snapshot. Snapshots preserve the authorized transaction-level audit facts needed to verify exact balances/corrections, rather than a balance-only summary; after account deletion they must project only the necessary retained pseudonymized fields, excluding erased/expired notes and identity context. No full-row retention is implied.

## Conflict matrix

Server revision compare-and-swap is the default. No generic last-write-wins based on client timestamps. On conflict retain the intent, fetch authorized current state, and either apply a documented safe resolution or ask the user; any resubmission is a new operation ID based on a known revision.

| Entity / field family | Resolution |
| --- | --- |
| Bucket/category title, description, status, category selection | Concurrent same-row edits require explicit review; no silent text overwrite or status toggle. If proposed values already equal current values, show resolved without adding a redundant write |
| Important date / recurrence / occurrence override | Treat date, time, zone, recurrence and exceptions as one revision-checked aggregate; return conflict on any concurrent aggregate edit; no duplicate notifications from merged rules |
| Savings goal metadata | Revision-check title, target, target date, archive/reopen; never merge currency changes; metadata/archive edits require the current goal revision, including intervening ledger appends; independent deposits validate current open state and currency without requiring an old balance revision |
| Savings contribution | Independent deposit commands append exactly once; serialize under goal/scope lock. No stale balance overwrite. Reversal validates unreversed original at commit; competing reversals yield one success, one conflict |
| Plan metadata / task text or completion | Row-level compare-and-swap; task add with distinct IDs commutes if live parent; cross-field text merge deferred |
| Itinerary order / category order / dashboard widget order | Explicit reorder command carries expected revisions of affected rows or an aggregate revision; integer sort keys plus ID tie-breaker; concurrent reorder returns conflict, never fractional floating point |
| Memory text/caption | Revision-check; independent attachment additions commute; privacy blocks/parent deletion win; a safe parent shell may remain with an affected unit held |
| Deletion vs edit | Hidden/deleted disposition wins over stale edits/child additions. Only approved P04 explicit paired restore may recover ordinary text within deadline; privacy removal/expiry defeats restore and deliberate re-creation from protected old payload |
| Personal theme and notification preferences | Revision-check; user can explicitly choose use this device or use synced value. No cross-account/shared theme override |
| Membership, invites, account state | Server-only online transactions; no optimistic conflict merge |
| Activity / security audit / change stream | Server append-only for normal business events; privacy-authorized redaction/invalidation and bounded purging apply; no client merge |

A goal's ledger append must also increment the goal aggregate revision so archive/reopen and displayed accepted balance have a shared concurrency point; the ledger row itself remains revision 1. Date aggregate edits advance the root important_date revision even when only a recurrence/override changes. Reorders that touch child rows validate all affected revisions and increment those rows; the selected aggregate revision is the root plan/preference revision; category-list reorder instead checks the explicit scope head sequence as specified in the application contracts.

## D03 privacy cleanup across synchronization copies

The current candidate P08 protocol separates authorization_epoch from privacy_epoch. Under canonical locks, commit content block/disposition, increment privacy epoch, invalidate old page/snapshot/export sessions, establish the valid cursor reset floor and enqueue copy cleanup together. Immediate serving predicates enforce blocks while workers purge/redact old personal after-images and snapshot chunks within the endorsed 24-hour target. Ninety-day change/tombstone retention is not an exemption from privacy removal. Snapshot immutability applies only within a current epoch, not across erasure.

On epoch mismatch stop sending queued content, discard inaccessible accepted/recovery/search/media projections and obtain a sanitized full snapshot. Preserve only still-authorized pending intent; reject operations touching removed/expired content and never automatically rebase old private text into a new entity or space. Native snapshot staging is protected; web reset is memory-only. Monetary audit order and scope commit sequence never reset when privacy epoch changes. Receipts return only current permitted metadata, not prior removed bodies; content-derived hashes remain private and purpose-bounded. Minimal financial uniqueness evidence contains no notes/identity mapping.

Ordinary text hide and any authorized restore also advance privacy epoch and invalidate affected projections/snapshots/exports. This protects immutable old chunks without eliminating an explicitly approved private recovery copy. Recovery payload lives outside ordinary pull/snapshot/export; any approved recovery surface is separately authorized while paired and before its deadline. Privacy escalation cancels recoverability and purges those copies too. Worker evidence tracks actual primary/derived deletion, not just a tombstone. Restores reapply expiry/removal before serving. Previously downloaded copies remain beyond reliable remote erasure under D02.

## Time and recurrence

Server UTC timestamps and scope sequences order events. `occurred_on` and all-day dates retain the user's calendar date; do not silently reinterpret birthdays by device UTC offset. Each timed recurrence keeps its originating IANA zone, local date/time, interval, and bounded exceptions. Display may convert instants to device zone but must identify source zone when relevant.

Technically endorsed D11 uses explicit last_valid_day/skip, default month-end and Feb 28 fallback, first-valid-instant DST gap and earlier-offset fold. Store nominal rule-generation/period/anchor identity separately from observed valid date/UTC instant; original_date alone cannot encode an invalid anchor. Version ruleset/tzdata and keep preview/scheduler parity. Future-series edits/count behavior and calendar interoperability remain formal design/test gates. Notification deduplication uses nominal occurrence/rule generation/user/device and checks current eligibility at send time.

Local device times are descriptive only. Use a server-issued, signed access lease bound to account/device/scope/both epochs with 24-hour default and explicit trusted-device opt-in up to 7 days; keep last server timestamp and monotonic elapsed-time anchor while running. Detect backward clock jumps/reboots/uncertain elapsed time and require online renewal rather than silently extending access. No software-only device clock scheme defeats a malicious user editing local storage/clock.

## Revocation and local data

On known revocation, account disablement, sign-out, or device revocation: stop workers, cancel/reject uploads, lock UI immediately, invalidate scope providers/routes, delete accepted base, pending commands/conflicts, local search, photos/thumbnails, and scope encryption keys where implemented. Never replay abandoned commands into another couple. Do not expose old data as an automatic export after access is lost. A restricted support/recovery flow must not bypass this rule.

A disconnected device cannot learn of revocation instantly. The proposed maximum offline read lease is seven days, not a seven-day guarantee of erasure. After expiry lock data until online verification; OS/background limitations, browser copies, backups, screenshots, malicious clients, and prior downloads remain outside reliable remote wipe. Disclose this rather than promising revocation of information already held. No offline membership or invitation operation is accepted as proof of access.

Native sensitive persistence is prohibited until encrypted SQLite executor, protected per-account keys, media/temp/WAL handling and credential/backup lifecycle are proven; never use plaintext fallback. Initial web sensitive content, credentials and pending requests are session-memory only and require online access. Do not deploy sensitive IndexedDB/OPFS/localStorage/Cache Storage/worker caches or durable browser outbox. A separate independently verified browser persistence design requires new approval. Unsaved web input cannot be described as durable queued work. Static app-shell caching and harmless appearance preferences are separate.

## Retry and failure taxonomy

- Network loss / 429 / transient 5xx / deadlock: exponential backoff with jitter (1 s to 5 min foreground cap), honor Retry-After, same ID/payload, bounded attempts before visible stalled status; data stays queued.
- Token expired: one coordinated refresh then revalidate account/scope. Do not treat all 401s as retryable forever.
- Permission revoked / deleting account / archived space: terminal for shared writes; hide or purge scope according to access state. Any archived reader may retain only the content currently permitted by the resolved D03 archive rules; pending writes are discarded/blocked without execution. An archived label never preserves the full old cache by default.
- Revision/uniqueness conflict: blocked for explicit resolution; no blind retry or client-clock overwrite.
- Invalid payload/currency/over-limit/unsupported command version: permanent visible rejection; dependent operations blocked; retain intent only while still authorized.
- Device storage full: fail the local transaction, surface unsaved state; do not delete unsynced data to free cache. Photo cache can evict only confirmed disposable bytes.
- Server log retention exceeded: immutable snapshot + rebase; retain pending IDs and status checks, never resubmit financial entries as new IDs merely because the cursor expired.

## Multi-device guarantees

Protected native queued commands are at-least-once delivered; web online requests can retry with stable in-memory operation IDs. Effects are exactly-once per authenticated operation key within the retained scope, and eventually reconciled while access remains valid and connectivity resumes. There is no exactly-once network delivery claim. Devices have independent queues/cursors and share server revisions. Same-user devices can conflict like partners; server-generated accepted balances, archived state, and tombstones converge through pull, even if all realtime hints are lost. Migration and protocol upgrades must preserve pending operation IDs/payloads or block with explicit recovery; never drop the outbox as a migration shortcut.

Initial web reload/response loss must not create a new financial operation automatically when its in-memory ID is lost. Reconcile current authorized server state/recent-operation summaries before explicit resubmission; expose uncertainty rather than guessing success or duplicating a deposit. No browser persistence shortcut is permitted to solve this. Native protected outbox IDs remain durable.
