# CP-004B.1 — Real local Auth and HTTP authorization proof

This is a disposable local prototype. No Flutter integration, production migrations, production identity system or pending-policy approval. See [the implementation report](../../docs/CP-004B1.md).

Prerequisites: running OrbStack and Supabase CLI 2.122.0. The original Twogethera project/configuration is not reset or changed. Start the independently named project, then run real Auth and PostgREST tests:

```sh
rtk proxy python3 proofs/cp004b1-http/start_local.py
rtk proxy python3 -u proofs/cp004b1-http/run_tests.py
```

The startup helper creates only a dedicated loopback-binding Docker network and this project's containers/volumes. It generates a local ES256 key with the official CLI into ignored `supabase/.local/signing_keys.json` (directory 0700, file 0600) without printing credentials. No private signing key is versioned. The HTTP runner refuses remote endpoints/engines, unexpected project/container labels, unsafe owner roles, missing database sentinel and non-loopback published ports. Missing tools/services fail the proof rather than skip tests. Local startup credentials are captured and suppressed.

Ports: API 55321, PostgreSQL 55322, local email 55324; project ID `twogethera-b1`. No Studio/Storage/Realtime/edge/analytics services are enabled. A 60-second user-token lifetime and raised synthetic-test Auth rate limits are deliberately local-only. `start_local.py` does not silently restart a running stack to apply config changes; stop **only this disposable project** with `supabase stop --workdir proofs/cp004b1-http` before restarting if needed. Never stop/reset the root developer project as a workaround.

The config initially exposes the existing empty public namespace for healthy boot. The runner installs the guarded prototype and narrows PostgREST's runtime schema to `cp004b1` and user-token verifier to the project's public ES256 JWKS. The CLI's legacy development API/admin keys remain fixture credentials; they are not used as user Bearer tokens. The runner creates actual synthetic Auth users, signs in through the password endpoint, and confirms one signup using locally captured email. It never signs a JWT or sets SQL JWT claims in place of client HTTP requests.

Files:

- `supabase/config.toml`: isolated local scaffold; automatic migration application disabled.
- `supabase/migrations/20261029000100_http_probe.sql`: **prototype-only**, applied by the sentinel-checked runner; only three tables and narrow helpers. Never copy to root production migrations.
- `start_local.py`: local engine/network/key/service setup, no hosted commands or raw credential output.
- `run_tests.py`: Python-standard-library real HTTP tests plus privileged fixture/catalog/constraint inspection.

Each run replaces only its own probe schemas under the dedicated project's database marker. It does not reset/drop the database or delete Auth accounts. Synthetic accounts and captured confirmation messages remain in disposable local volumes; private key/temporary CLI metadata are ignored. Do not use real information here or run concurrent copies. Repeated runs may eventually hit configured local rate limits; a 429 is a failure, never a skipped test.

The suite checks Auth-issued JWT acceptance, `auth.uid()`, row/grant isolation, negative writes with persisted-state checks, fresh membership checks after a real authenticated leave RPC, DB constraint backstops, corrupt/malformed tokens and **natural expiration**. The last check may take about a minute plus verifier clock tolerance. No mocks, handcrafted valid JWTs or privileged service-role client assertions.

Privileged fixture administration is explicitly separate from user requests. The application helper owns/bypasses RLS only on the three prototype tables, has no SELECT grant on private Auth rows, and never accepts a caller-supplied actor. Confirmation is enforced by Auth at sign-in; live account/email/ban state beyond membership is not implemented. Current HTTP membership creation/invitations, general idempotency and concurrency belong to CP-004B.2 or later. Closed scopes deny both former members without deleting retained rows or approving archive retention.
