# Privacy and authorization model

**Specification, not deployed policies.** See [approval decisions](README.md), especially archive access (D02), retained shared records (D03), offline lease (D04), and non-E2EE storage (D08).

## Trust boundaries and authorization predicates

Supabase Auth establishes identity. PostgreSQL establishes current authorization. A router redirect, local membership cache, invite URL, UUID, device ID, or JWT custom claim does not establish couple access. Membership and account state must be read from current authoritative rows on every request/command. Never trust writable user metadata for roles or membership.

Define these conceptual predicates with `auth.uid()` as the principal, not a caller-supplied user ID:

- `eligible_user()`: authenticated user has `app_users.state = active`; identity exists, session/device is not rejected for privileged commands.
- `can_read_space(c)`: eligible user has an active membership in draft/paired c, or an archived membership in archived c. No reads in purging. A revoked membership never qualifies.
- `can_write_space(c)`: eligible user has active membership and c is paired. Parent row must also be live and the command's specific checks must pass.
- `can_manage_draft(c)`: eligible user is the sole active member of a draft; only invitation and draft management, no shared planner edits.
- `owns_personal_row(u)`: eligible user and u equals `auth.uid()`; private scope constraints apply additionally if a personal preference references a couple.

Authorization epoch is an invalidation marker; matching an epoch is **not** a substitute for checking membership. Writes recheck after taking transaction locks. RLS evaluates reads against the request's database snapshot; a read already in flight before revocation may finish. Revocation cannot recall bytes already delivered.

## Exposure, grants, and RLS specification

Enable RLS on all application and operational tables; apply FORCE RLS where appropriate and test the actual owner/execution roles. `anon` gets no table grants or application command EXECUTE. `authenticated` has only explicit read grants and named command EXECUTE. Direct INSERT/UPDATE/DELETE is revoked for all canonical tables, including preferences and memberships. No implicit ALL policy, wildcard schema grant, or automatic access to new tables/functions.

| Surface | SELECT / read rule | INSERT / UPDATE / DELETE rule |
| --- | --- | --- |
| profiles and personal preferences | Own user only; couple-context preferences also require `can_read_space` | No direct DML; typed commands derive user and enforce allowlisted editable fields/revision |
| couple_spaces | `can_read_space(id)` | Only create/rename/link/unlink/lifecycle commands; clients cannot set state/count/epoch |
| memberships | `can_read_space(couple_id)` exposes only member card/seat/state; caller's own revoked-state discovery through `account_context()` | No direct DML; no role promotion, user substitution, seat reassignment, or resurrection |
| bucket/date/plan/memory/category entities | `can_read_space(couple_id)` AND live row/root (no tombstone or deletion_started_at), including live owning parent for child rows | No direct DML; commands enforce `can_write_space`, live parents, expected revision, and old/new scope immutability |
| savings goals/contributions | Same scope read; goals have archive status, contributions retained for audit | Ledger insert only through dedicated money commands; no ledger update/delete grants or edit RPC |
| photo metadata | Same scope read, live memory/attachment; only safe metadata fields | Reservation/caption/remove/finalize commands; clean object metadata server-owned |
| activity_events | Same scope; no secret/content payload; retention applies | Server-generated append-only; client cannot impersonate actor or append arbitrary events |
| invitations / app_users / security audits / lifecycle jobs | No direct access; narrow authenticated own-state/inviter-summary RPCs only | Internal transactions/jobs; token hashes never returned |
| devices | Own safe metadata projection only, no auth credentials | Online register/rename/revoke commands; requires authenticated user and validated device ownership |
| notification_tokens | No client SELECT, including the owner | Online register/rotate/revoke RPC; token ciphertext is server-only |
| sync internals / receipts / cursors / snapshots | No direct tables; authorized scope-bound pull/snapshot/status commands | Server commands only; ACK cannot change scope membership or trusted head |
| export jobs | Own status through RPC, current source scope access required | Online request/cancel/download workflows only |
| currencies | Read-only reference catalog for eligible users | Privileged reviewed catalog updates only |

For any future invoker-DML API, INSERT requires `WITH CHECK` for current scope and owner; UPDATE requires both old-row `USING` and new-row `WITH CHECK`, plus immutable-field column restrictions/triggers. This blueprint deliberately provides no client DML grant, so those future policies must not be silently introduced. Scope IDs and authorship cannot be changed even between two spaces the same user can read. A privileged command is not made safe merely by having table RLS.

Use composite tenant FKs and server-side parent existence/liveness validation to prevent attaching an item, task, memory, or photo to someone else's row. Uniqueness/existence errors must be mapped to generic external outcomes where they could reveal another couple's records. Search, aggregates, calendars, exports, and pagination all use the same scope predicates; no unfiltered privileged global search.

## Membership helpers, views, and RPCs

Membership policies must not recursively SELECT memberships with the same RLS policy. Use a small audited private helper that reads only the required account/membership/space fields. If SECURITY DEFINER is required, its owner is a dedicated NOLOGIN role with narrowly granted table permissions; any BYPASSRLS privilege needed to avoid recursion is held only by that role, never granted through membership to application users. Helpers must not accept an arbitrary principal, return rows, or mutate data. API exposure and schema USAGE/EXECUTE are explicitly reviewed.

All SECURITY DEFINER entry points must have a fixed empty search_path, fully qualified relations/functions, no dynamic SQL constructed from client input, explicit auth/null checks, bounded inputs, and exact command-specific authorization. Revoke default EXECUTE from PUBLIC and anon; grant only the necessary functions to authenticated. A wrapper that can invoke arbitrary SQL/table names or accepts a trusted actor/role is forbidden. Definer write functions explicitly perform all security checks because their execution privileges may bypass RLS. Service-role credentials stay exclusively in trusted server runtimes and must never ship in Flutter or build defines.

Prefer invoker reads. Every exposed view uses `security_invoker = true` on a verified supporting PostgreSQL version, with explicit safe columns and reviewed underlying grants. Otherwise keep the view unexposed/revoke access. No public materialized views of private data. A definer function is treated as a separate security perimeter and receives adversarial tests, including calling it directly over the Data API.

The relevant platform mechanics are documented in [Supabase RLS guidance](https://supabase.com/docs/guides/database/postgres/row-level-security); the more restrictive grants and command protocol here are Twogethera design decisions.

## Storage

Use a **private** bucket. Object authorization is independent of database row authorization; write policies on `storage.objects` must join an exact attachment reservation and live membership, not merely trust the first folder segment. Supabase documents this separate boundary in [Storage access controls](https://supabase.com/docs/guides/storage/security/access-control).

- Server reservation assigns immutable `staging/<couple UUID>/<attachment UUID>/<random UUID>` and a future clean key. Clients cannot choose another scope, overwrite a ready object, upsert, copy/move, or list unrestricted objects.
- Authenticated INSERT permits exactly the live reservation's staging path, uploader identity, unexpired reservation, live memory, and `can_write_space`. Filename, client MIME, owner metadata, and file extension are not trusted. No client UPDATE/DELETE object grants.
- Staging bytes are not client-downloadable. A trusted processor validates size, decoded image format/dimensions, removes EXIF/GPS, re-encodes to an allowed image format, calculates canonical checksum, and writes clean bytes. It then rechecks membership/epoch, parent liveness, and reservation state under the scope lock before publishing ready metadata. Storage and SQL are not an atomic transaction: failure leaves inaccessible staged/orphaned objects for cleanup.
- SELECT/download permits only clean key exactly referenced by live ready metadata with live memory and `can_read_space`; it also denies attachments whose uploader account is deleting/disabled for erasure, before background tombstoning finishes. Keep the uploader linkage until this cleanup is complete. Storage listings cannot return rows outside that predicate. Thumbnails/derivatives require the same checks; no public CDN URL or public transform endpoint.
- Use authenticated downloads, not signed bearer download URLs initially (D07). Signed URLs are a distinct private delivery option documented under [asset delivery](https://supabase.com/docs/guides/storage/serving/downloads); they are deliberately excluded because a delivered bearer URL can outlive membership changes.
- Removal first tombstones metadata and removes read permission; an idempotent server job deletes bytes through the Storage API and checks orphan cleanup. Do not delete `storage.objects` rows manually as a substitute for object deletion.
- Images, export files, thumbnails, and HTTP responses use private/no-store cache behavior where controllable; do not service-worker-cache sensitive responses. Validate actual CDN/cache headers and old URL behavior in integration tests. Device-cached photos follow the local access lease and wipe procedure.

## Realtime and notifications

Start with **invalidation only**, on private per-user channels. Disable public channel access. Channel topic is tied to the authenticated user's ID; `realtime.messages` policy permits receiving only one's own channel. Client broadcast and presence are disabled. Only a trusted dispatcher emits `sync_required: true`; payloads contain no couple IDs, entity IDs, content, financial amounts, membership lists, or cursor values. The receiver must call authenticated pull to learn anything substantive.

Do not publish application tables, tokens, invitations, or the change-log tables directly to Postgres Changes in the initial design. A revoked subscriber or delayed channel authorization cannot receive new shared content because none is broadcast. Existing channel membership is never used as proof of ongoing data access. [Realtime authorization](https://supabase.com/docs/guides/realtime/authorization) documents the private channel controls; [Postgres Changes](https://supabase.com/docs/guides/realtime/postgres-changes) is a separate feature and is not the durable synchronization transport.

The dispatcher uses current authorization when choosing recipients; missed/duplicated hints are harmless because scheduled pull reconciles. Push notifications follow the same generic-content default and recheck current member/account/device state at send time. A notification already delivered to an OS cannot be recalled reliably. Device token records never sync to the partner or appear in activity feeds.

## Revocation, abuse, and residual risk

- Unlink/deletion locks and updates membership, account state, epoch, invite state, and access events atomically; later writes/downloads fail even with a previously valid JWT. Session revocation is defense in depth, not the membership authority.
- On any access check failure, the client stops writes/downloads and hides/wipes that scope before navigation. App resume and reconnect require an online membership check before draining pending commands. An expired offline lease locks cached content; see [offline security limits](OFFLINE_SYNC.md).
- Proposed limits: 5 invite creations per account/hour, 10 acceptance attempts/account/10 minutes, bounded IP abuse limits, 100 commands/device/minute with money/linking tighter limits, 200 records/1 MiB per pull page, 10 MiB source photos. Enforce in trusted server infrastructure, without requiring a paid tier. Final values need workload testing.
- Restrict logs to action/outcome/request IDs; sanitize URL fragments, tokens, email, personal text, query errors, SQL parameters, and photo metadata. Audit security transitions, not every intimate content edit. Do not log Auth refresh credentials or raw pending-operation payloads.
- Trusted servers/operators can access plaintext: this is not E2EE. Browser XSS, malicious extensions, rooted devices, screen capture, downloaded exports, and disconnected revoked devices remain risks. CSP, dependency review, least-privilege runtime configuration, and local encryption design are required implementation work.

## Required security acceptance tests (future, not run in CP-002)

Use two unrelated couples, an unlinked account, an archived reader, a revoked member with an old JWT, and anon. Exercise every table/read projection/RPC/Storage object/channel with other-scope IDs. Test insert/check bypass, changing scope/actor, parent mismatch, guessed IDs, deleted parents, stale revisions, hidden fields, direct function calls, malicious search_path, double invite redemption, third-member attempts, and session/account deletion races. Confirm no unauthorized bytes through object URLs, thumbnails, export jobs, errors, views, or subscriptions. Catalog tests must fail if a new exposed table lacks RLS or a function has unintended EXECUTE grants. Passing Flutter widget tests does not validate this model.
