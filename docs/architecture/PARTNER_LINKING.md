# Partner linking protocol

**Design only.** Approval assumptions: D01, D02, D06, D09, D10 in the [decision register](README.md). No invite endpoints, email sender, or authentication screen exists yet.

## States and invariants

An account can have at most one `active` membership across all spaces. A new space starts `draft`, with the creator in seat 1. It becomes `paired` only when two distinct active users occupy seats 1 and 2. An archived/purging space has no active seats and cannot be reactivated or accept a new partner. Historical seat rows are never reused. Both active partners have equal shared-data rights; the creator has no permanent unilateral admin privilege over the other partner.

```mermaid
stateDiagram-v2
    [*] --> Draft: authenticated create_space
    Draft --> Draft: create / replace / expire invitation
    Draft --> Paired: atomic accept_invitation
    Draft --> Purging: sole member abandons draft
    Paired --> Archived: either member leaves / account becomes deleting
    Archived --> Purging: archived reader requests deletion or no reader remains
    Purging --> [*]: privileged cleanup completes
```

At commit: draft => 1 active, paired => 2 active, archived/purging => 0 active; archived => at most 1 archived reader, all other seats revoked. Unique seat checks and partial unique active user index are necessary but not sufficient: deferred constraints validate space/member counts and legal transitions. No client INSERT/UPDATE/DELETE grants on either table.

## Create and issue

1. User must be authenticated with a verified server-side email identity and active account. `create_space(operation_id, name, time_zone)` checks idempotency and current membership, creates the space/member/sync scope atomically, and returns only its authorized projection.
2. Creator explicitly enters the recipient's email. Server normalizes according to its verified-identity policy (trim surrounding whitespace, canonical domain, do not invent Gmail-style dot/plus equivalence) and stores a keyed HMAC with key version; plaintext is not stored in the invitation or activity. Future key management is server-only and requires no key now; retain verification keys through invite expiry or explicitly revoke affected invites on key retirement.
3. `issue_invitation` locks the creator/account and scope, confirms draft and sole membership, revokes an existing pending invite, and creates a cryptographically random 256-bit token. Store only SHA-256 token digest and recipient HMAC. Expiry is server UTC now + 24 hours. Partial unique pending invitation enforces one outstanding invite; an expired pending row is explicitly transitioned before creating another, not indexed using volatile `now()` predicates.
4. Return the token/link once to its authenticated creator. The app offers user-initiated sharing; do not silently send messages. Reopening the app cannot recover the token from the database; regenerate if lost. Do not persist the token to Drift, analytics, clipboard history owned by the app, crash logs, or saved URLs.
5. Invite links should carry the token in a fragment handled by the client and immediately removed from visible history after capture. No third-party scripts/trackers on the landing page, restrictive referrer policy, no tokens in HTTP query/access logs. The token is submitted over TLS in an authenticated request body and cleared after use/cancel. For the existing hash-router foundation, a future web link can use `/#/join?token=...` (token is inside the fragment, not the HTTP query), then replace history with `/#/join` after capture. This route is not added in CP-002. If external Auth navigation would lose in-memory state, ask the user to sign in and reopen the original invitation; do not persist the token or place it in an OAuth redirect/state parameter. Native deep-link handling must apply the same redaction. A manually shared link remains sensitive even when email-bound.

Do not disclose whether the recipient already has an account. The inviter sees a masked recipient summary and expiry through an authorized RPC, never arbitrary identity lookup or stored digests.

## Acceptance and concurrency algorithm

Acceptance is **online only** and explicitly confirmed by the recipient after signing in. A pre-auth landing page is generic. A verified email match permits a minimal authenticated preview, but does not grant couple data access. A wrong email, unknown token, expired/revoked token, and inaccessible invite return a generic unavailable result. Rate limit and audit outcomes without raw secrets.

Commands that mutate user/membership/scope state use this lock order: relevant `app_users` rows sorted by UUID; relevant `sync_scopes` sorted by UUID; couple rows sorted by UUID; then invitation/entity rows sorted by ID. Ordinary shared writes follow the same order for their actor and shared scope. Discover lock targets before acquiring locks, then re-read and validate; if membership/scope discovery changed, release/retry the transaction instead of acquiring an out-of-order lock. Creation of a previously absent personal scope is serialized by its app_user lock. Deadlock/serialization failures retry with the same operation ID.

Before resolving a token or applying fresh-invite state checks, an authenticated retry may find an already committed `(actor,operation_id)` receipt. Validate the identical request hash and current account/scope access before returning its sanitized result. This works even if the invite has since expired or its digest was pruned; own operation-status lookup uses the non-secret operation ID. A pending network request may persist that ID locally, but never the raw token. If no receipt exists, proceed with the fresh transaction below; recheck the receipt under locks for concurrent duplicates.

Acceptance transaction specification:

1. Resolve token digest internally without exposing invite details. Identify inviter, recipient, couple, and both personal scopes. Acquire locks in the canonical order, including both app_user rows and shared/personal scope counters. Lock invite; reread all state after locks. Before any fresh-invite validation, recheck the actor/operation receipt: identical already-committed request returns its sanitized result only after current access verification; a different request hash is rejected.
2. For a fresh operation (after the receipt check), derive recipient from `auth.uid()`, confirm active account and current verified Auth email matches stored HMAC. Reject self-acceptance, unverified email, expired invite using server time, non-pending state, non-draft space, absent/revoked inviter, or anything other than exactly one active inviter in seat 1. Recipient cannot be a different historical seat in that space.
3. Check the recipient has no active membership. Do not auto-leave or merge another couple, including a single-member draft. Require an explicit separate abandon/unlink workflow first. An outstanding draft has no planner data under D09.
4. For this new operation, validate protocol/command shape and freeze its canonical request hash. A consumed token with a different operation ID is unavailable; no alternate seat or second space is created. The earlier receipt check is the sole idempotent exception to that single-use response. Unique receipt/seat/member constraints remain the final commit-time backstop.
5. Insert seat 2 with the authenticated user. Set space to paired, increment authorization_epoch and relevant row revisions; mark invite accepted with recipient and timestamp. Revoke any other pending invites defensively. Append shared sanitized membership/space changes and both users' access events. Assign per-scope sequences under locked counters, and write success receipt in this same transaction.
6. Deferred state/count/uniqueness checks must pass at commit. Only after commit return success and trigger generic invalidations. The recipient's first data load is an authorized snapshot; do not copy an old unrelated scope cache.

With two accept requests, only one can consume the pending invite and seat; the other sees accepted state after waiting. With two invitations to different spaces accepted by the same account, the recipient app_user lock and partial unique active membership ensure only one can succeed. Invite expiry/revocation/unlink races serialize under the same locks and rechecks. `COUNT(*) < 2` without a lock and unique constraints is **not** sufficient. An UPDATE that changes pending to accepted without membership insertion in the same transaction is forbidden.

[PostgreSQL row-level locks](https://www.postgresql.org/docs/current/explicit-locking.html) provide the serialization primitive; this particular transaction and its invariants are proposed application behavior and need integration testing.

```mermaid
sequenceDiagram
    participant A as Inviter
    participant B as Recipient
    participant API as Authenticated command
    participant DB as PostgreSQL
    A->>API: issue invitation for verified email
    API->>DB: lock + draft check + digest insert
    DB-->>A: one-time token via API
    A->>B: explicit user-shared link
    B->>API: accept(token, operation_id)
    API->>DB: lock users/scopes/space/invite
    DB->>DB: verify identity, expiry, membership, uniqueness
    DB->>DB: seat 2 + paired + epoch + changes + receipt
    DB-->>API: commit
    API-->>B: accepted, snapshot required
    API-->>A: generic sync hint after commit
```

## Leaving, deletion, and recovery

Unlink requires recent authentication, an explicit warning, and an online operation. Either member may leave without partner approval. In one transaction: revoke leaver, convert remaining active member to archived, archive the space, increment epoch, revoke invites, update revisions, publish both users' access events, and write a receipt. There are no active seats afterward. A stale offline contribution arriving later is denied and never redirected to the user's new couple. Data export is offered before leaving but is not a prerequisite that can block safe exit.

Account deletion immediately marks the account deleting and performs the same unlink transition, disables tokens, and queues private-data/media cleanup. Cancellation does not restore a former membership. The remaining archived reader can form a new space; their new partner receives no archive access. The archived reader may leave/delete the archive, making it purging. See [data lifecycle](DATA_LIFECYCLE.md) for retention/erasure proposals.

Lost-invite recovery is regenerate/revoke, not recover stored plaintext. Account recovery uses real Auth identity verification and must not grant partner access by answering relationship questions. An accept/create/unlink network timeout is resolved by operation status/current account context; never infer success from a local UI state.
