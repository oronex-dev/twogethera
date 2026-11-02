#!/usr/bin/env python3
"""Focused real local Auth/PostgREST/SQL CP-006B invitation security suite."""
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
API = "http://127.0.0.1:54321"
CONTAINER = "supabase_db_twogethera"
DOCKER = shutil.which("docker") or "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"
ENV = dict(os.environ, PATH=str(Path(DOCKER).parent) + ":" + os.environ.get("PATH", ""))
FIXTURE = "public.cp006b_test_planner_records"
HTTP_CLIENT = urllib.request.build_opener(urllib.request.ProxyHandler({}))
ASSERTIONS = 0


def require(condition, message):
    global ASSERTIONS
    ASSERTIONS += 1
    if not condition:
        raise RuntimeError(message)


def run(command, stdin=None, timeout=20):
    return subprocess.run(command, input=stdin, capture_output=True, text=True,
                          env=ENV, timeout=timeout)


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


def sql(statement, must_succeed=True):
    result = run([DOCKER, "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-w",
                  "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1",
                  "-v", "VERBOSITY=verbose"],
                 "SET log_statement='none'; SET log_min_error_statement='panic'; "
                 "SET statement_timeout='12s';\n" + statement)
    if must_succeed and result.returncode:
        safe = next((line[:180] for line in result.stderr.splitlines()
                     if line.startswith("ERROR:")), "database command failed (details suppressed)")
        raise RuntimeError(safe)
    return result.stdout.strip() if must_succeed else result


def http(url, method="GET", body=None, headers=None, timeout=15):
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
            and parsed.port == 54321, "refusing nonlocal Supabase API target")
    payload = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(
        url, data=payload,
        headers={"Content-Type": "application/json", **(headers or {})},
        method=method,
    )
    try:
        response = HTTP_CLIENT.open(request, timeout=timeout)
    except urllib.error.HTTPError as error:
        response = error
    data = response.read()
    try:
        decoded = json.loads(data) if data else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        decoded = None
    return response.code, decoded


class Suite:
    def __init__(self):
        self.users = {}
        self.groups = []
        self.raw_tokens = []
        self.anon = None
        self.admin = None
        self.started_at = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        self.run_id = secrets.token_hex(7)

    def mark(self, name):
        self.groups.append(name)
        print("PASS:", name, flush=True)

    def preflight(self):
        docker_context = run([DOCKER, "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"])
        require(docker_context.returncode == 0 and docker_context.stdout.strip().startswith("unix://"),
                "local Docker engine is required")
        status = run(["supabase", "status", "-o", "json"])
        require(status.returncode == 0, "local Supabase is not running")
        values = json.loads(status.stdout)
        require(values.get("API_URL") == API and "@127.0.0.1:54322/" in values.get("DB_URL", ""),
                "unexpected local Supabase endpoint")
        self.anon, self.admin = values.get("ANON_KEY"), values.get("SERVICE_ROLE_KEY")
        require(bool(self.anon and self.admin), "local synthetic Auth fixture credentials are unavailable")
        labels = run([DOCKER, "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"])
        require(labels.returncode == 0 and json.loads(labels.stdout).get("com.supabase.cli.project") == "twogethera",
                "refusing a database outside the root local Supabase project")
        migration_versions = set(sql("SELECT version FROM supabase_migrations.schema_migrations" ).splitlines())
        require({"20261102000100", "20261102000200"}.issubset(migration_versions),
                "CP-006A/CP-006B migrations are not recorded as applied locally")
        hosted_role_boundary = sql(
            "SELECT (SELECT proowner='postgres'::regrole FROM pg_proc WHERE oid='app_private.current_identity_is_verified(boolean)'::regprocedure) AND "
            "(SELECT proowner='postgres'::regrole FROM pg_proc WHERE oid='app_private.current_verified_email(boolean)'::regprocedure) AND "
            "NOT EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace "
            "WHERE p.prosecdef AND n.nspname IN ('public','app_private') AND "
            "NOT coalesce(p.proconfig,ARRAY[]::text[]) @> ARRAY['search_path=\"\"']::text[]) AND "
            "NOT EXISTS (SELECT 1 FROM pg_proc p WHERE p.oid = ANY(ARRAY["
            "'public.create_couple_space(uuid)'::regprocedure,'public.ensure_account()'::regprocedure,"
            "'public.account_context()'::regprocedure,'public.partner_link_context()'::regprocedure,"
            "'public.issue_partner_invitation(uuid,uuid,bigint,text)'::regprocedure,"
            "'public.accept_partner_invitation(uuid,text)'::regprocedure,"
            "'public.revoke_partner_invitation(uuid,uuid)'::regprocedure,"
            "'public.delete_bucket_list_item(uuid,uuid,bigint)'::regprocedure,"
            "'public.delete_important_date(uuid,uuid,bigint)'::regprocedure,"
            "'public.delete_plan_task(uuid,uuid,bigint)'::regprocedure,"
            "'public.delete_plan(uuid,uuid,bigint)'::regprocedure]) "
            "AND p.proowner <> 'twogethera_membership_owner'::regrole) AND "
            "has_function_privilege('twogethera_membership_owner','app_private.current_identity_is_verified(boolean)','EXECUTE') AND "
            "has_function_privilege('twogethera_membership_owner','app_private.current_verified_email(boolean)','EXECUTE') AND "
            "to_regprocedure('extensions.gen_random_bytes(integer)') IS NOT NULL AND "
            "to_regprocedure('extensions.hmac(bytea,bytea,text)') IS NOT NULL AND "
            "to_regprocedure('extensions.digest(bytea,text)') IS NOT NULL AND "
            "(SELECT NOT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication AND NOT rolbypassrls AND NOT rolinherit "
            "FROM pg_roles WHERE rolname='twogethera_membership_owner') AND "
            "NOT EXISTS (SELECT 1 FROM pg_auth_members WHERE "
            "(roleid='twogethera_membership_owner'::regrole AND member <> 'postgres'::regrole) OR member='twogethera_membership_owner'::regrole) AND "
            "NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.contype='f' AND c.conrelid IN "
            "('public.couple_memberships'::regclass,'app_private.couple_create_receipts'::regclass,"
            "'app_private.partner_invitations'::regclass,'app_private.partner_invitation_receipts'::regclass,"
            "'app_private.partner_invitation_limits'::regclass) AND c.confrelid='auth.users'::regclass)")
        require(hosted_role_boundary == "t",
                "managed-role Auth bridge or owner role catalog boundary is incorrect")
        health, _ = http(API + "/auth/v1/health")
        require(health == 200, "local Auth health endpoint did not respond")
        require(sql("SELECT to_regclass('" + FIXTURE + "') IS NULL") == "t",
                "test fixture relation already exists; refusing to overwrite it")
        self.mark("root Supabase project, loopback endpoint and CP-006A/CP-006B migrations verified; credentials suppressed")

    def create_user(self, name):
        email = f"cp006b-{self.run_id}-{name}@example.invalid"
        password = secrets.token_urlsafe(30)
        code, data = http(API + "/auth/v1/admin/users", "POST",
                          {"email": email, "password": password, "email_confirm": True},
                          {"apikey": self.anon, "Authorization": "Bearer " + self.admin})
        require(code == 200 and isinstance(data, dict) and isinstance(data.get("id"), str),
                "synthetic confirmed Auth user creation failed")
        token_code, session = http(API + "/auth/v1/token?grant_type=password", "POST",
                                   {"email": email, "password": password}, {"apikey": self.anon})
        require(token_code == 200 and isinstance(session, dict) and session.get("access_token"),
                "synthetic Auth password sign-in failed")
        self.users[name] = {"id": data["id"], "email": email, "token": session["access_token"]}

    def identities(self):
        for name in "abcdefghi":
            self.create_user(name)
        self.mark("nine verified synthetic accounts authenticated with real local Supabase JWTs")

    def client_headers(self, name=None):
        headers = {"apikey": self.anon, "Accept-Profile": "public", "Content-Profile": "public",
                   "Prefer": "return=representation"}
        if name:
            token = self.users[name]["token"]
            require(token not in (self.anon, self.admin), "elevated token supplied as a client identity")
            headers["Authorization"] = "Bearer " + token
        return headers

    def rpc(self, name, function, body):
        return http(API + "/rest/v1/rpc/" + function, "POST", body, self.client_headers(name))

    def rest(self, name, path, method="GET", body=None):
        return http(API + "/rest/v1/" + path, method, body, self.client_headers(name))

    def create_space(self, name):
        code, result = self.rpc(name, "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        require(code == 200 and isinstance(result, str), "authenticated draft creation failed")
        return result

    def context(self, name):
        code, result = self.rpc(name, "partner_link_context", {})
        require(code == 200 and isinstance(result, dict) and result.get("user_id") == self.users[name]["id"],
                "partner context did not resolve authenticated user")
        return result

    def issue(self, name, space, email, op=None, epoch=1):
        result = self.rpc(name, "issue_partner_invitation", {
            "p_operation_id": op or str(uuid.uuid4()),
            "p_couple_id": space,
            "p_expected_epoch": epoch,
            "p_recipient_email": email,
        })
        if result[0] == 200 and isinstance(result[1], dict) and isinstance(result[1].get("token"), str):
            self.raw_tokens.append(result[1]["token"])
        return result

    def accept(self, name, token, op=None):
        return self.rpc(name, "accept_partner_invitation", {
            "p_operation_id": op or str(uuid.uuid4()), "p_token": token,
        })

    def setup_planner_fixture(self, spaces):
        sql("CREATE TABLE public.cp006b_test_planner_records ("
            "id uuid PRIMARY KEY DEFAULT gen_random_uuid(), "
            "couple_id uuid NOT NULL REFERENCES public.couple_spaces(id), body text NOT NULL); "
            "ALTER TABLE public.cp006b_test_planner_records ENABLE ROW LEVEL SECURITY; "
            "REVOKE ALL ON public.cp006b_test_planner_records FROM PUBLIC,anon,authenticated,service_role; "
            "GRANT SELECT ON public.cp006b_test_planner_records TO authenticated; "
            "CREATE POLICY cp006b_test_planner_read ON public.cp006b_test_planner_records "
            "FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id)); "
            "INSERT INTO public.cp006b_test_planner_records(couple_id,body) VALUES "
            "(" + quote(spaces["a"]) + "::uuid,'fixture A'),(" + quote(spaces["f"]) + "::uuid,'fixture F'); "
            "NOTIFY pgrst, 'reload schema'")
        deadline = time.monotonic() + 8
        last_code = 0
        while time.monotonic() < deadline:
            last_code, _ = self.rest("a", "cp006b_test_planner_records?select=id&limit=0")
            if last_code == 200:
                break
            time.sleep(0.1)
        require(last_code == 200, "PostgREST did not load test-only planner fixture")

    def planner_read(self, user, space, expected_rows):
        code, rows = self.rest(user, "cp006b_test_planner_records?select=id,body&couple_id=eq." + space)
        require(code == 200 and isinstance(rows, list) and len(rows) == expected_rows,
                f"planner fixture access mismatch for pairing state (HTTP {code}, rows={len(rows) if isinstance(rows, list) else 'non-list'})")
        if expected_rows:
            require(all(row.get("body") in ("fixture A", "fixture F") for row in rows),
                    "planner fixture returned an unexpected record")

    def issue_pairing(self):
        spaces = {name: self.create_space(name) for name in ("a", "b", "f", "h", "i")}
        self.setup_planner_fixture(spaces)
        self.planner_read("a", spaces["a"], 0)
        self.planner_read("b", spaces["a"], 0)
        self.planner_read("c", spaces["a"], 0)
        self.mark("D09: draft creator, unrelated member and unpaired account all receive empty planner results")

        issue_op = str(uuid.uuid4())
        code, created = self.issue("a", spaces["a"], self.users["b"]["email"], issue_op)
        require(code == 200 and isinstance(created, dict) and created.get("status") == "created",
                "verified-email invitation creation failed (HTTP " + str(code) + ", result=" +
                (str(created.get("status")) if isinstance(created, dict) else type(created).__name__) + ")")
        token = created.get("token")
        require(isinstance(token, str) and len(token) == 64 and
                all(ch in "0123456789abcdef" for ch in token),
                "issued token was not 256-bit lowercase hex")
        expires = created.get("expires_at")
        require(isinstance(expires, str), "invitation expiry missing")
        expected_hint = self.users["b"]["email"].split("@", 1)[0][:1] + "•••@example.invalid"
        import datetime
        expiry_seconds = (datetime.datetime.fromisoformat(expires.replace("Z", "+00:00")) -
                          datetime.datetime.now(datetime.timezone.utc)).total_seconds()
        require(23 * 3600 < expiry_seconds <= 24 * 3600 + 10,
                "invitation lifetime is not 24 hours")
        hashed_token = hashlib.sha256(token.encode()).hexdigest()
        stored = sql("SELECT encode(token_digest,'hex')||'|'||octet_length(recipient_hmac)::text||'|'||"
                     "recipient_hint||'|'||key_version::text FROM app_private.partner_invitations "
                     "WHERE couple_id=" + quote(spaces["a"]) + "::uuid AND state='pending'")
        require(stored == hashed_token + "|32|" + expected_hint + "|1",
                "invitation row stored an unexpected token/email representation")
        context = self.context("a")
        require(context.get("space", {}).get("state") == "draft" and
                context.get("invitation", {}).get("recipient_hint") == expected_hint and
                "token" not in json.dumps(context),
                "pending context leaked token or did not mask the intended recipient")

        code, replay = self.issue("a", spaces["a"], self.users["b"]["email"], issue_op)
        require(code == 200 and replay.get("replayed") is True and "token" not in replay and
                replay.get("invitation_id") == created.get("invitation_id"),
                "issue operation replay did not return sanitized one-time metadata")
        require(sql("SELECT count(*) FROM app_private.partner_invitations WHERE couple_id=" +
                    quote(spaces["a"]) + "::uuid AND state='pending'") == "1",
                "idempotent issue replay created a duplicate invitation")

        wrong_code, wrong = self.accept("d", token)
        require(wrong_code == 200 and wrong == {"status": "unavailable"},
                "wrong verified email received a non-generic invitation response")
        occupied_code, occupied = self.accept("b", token)
        require(occupied_code == 200 and occupied == {"status": "unavailable"},
                "recipient with an existing draft was automatically moved into another space")
        b_context = self.context("b")
        require(b_context.get("space", {}).get("id") == spaces["b"] and
                b_context.get("space", {}).get("state") == "draft",
                "failed acceptance changed the recipient's existing couple space")

        replace_code, replacement = self.issue("a", spaces["a"], self.users["c"]["email"])
        require(replace_code == 200 and replacement.get("status") == "created" and replacement.get("token"),
                "explicit invitation replacement failed")
        old_code, old = self.accept("b", token)
        require(old_code == 200 and old == {"status": "unavailable"},
                "replaced single-use invitation remained valid")
        new_token = replacement["token"]
        self.mark("D06: 24-hour single-use token, SHA-256/HMAC storage, masked status, idempotent replay, verified recipient binding and explicit replacement verified")

        c_op = str(uuid.uuid4())
        accepted_code, accepted = self.accept("c", new_token, c_op)
        require(accepted_code == 200 and accepted.get("status") == "accepted" and
                accepted.get("space_id") == spaces["a"], "authorized recipient acceptance failed")
        replay_code, accepted_replay = self.accept("c", new_token, c_op)
        require(replay_code == 200 and accepted_replay.get("status") == "accepted" and
                accepted_replay.get("replayed") is True,
                "accept operation replay was not safe and idempotent")
        replayed_token_code, consumed = self.accept("c", new_token)
        require(replayed_token_code == 200 and consumed == {"status": "unavailable"},
                "a consumed token was reusable under a new operation")
        state = sql("SELECT s.state||'|'||(SELECT count(*) FROM public.couple_memberships m "
                    "WHERE m.couple_id=s.id AND m.state='active')::text||'|'||s.authorization_epoch::text "
                    "FROM public.couple_spaces s WHERE s.id=" + quote(spaces["a"]) + "::uuid")
        require(state == "paired|2|2", "successful acceptance did not commit exactly two members and new epoch")
        self.planner_read("a", spaces["a"], 1)
        self.planner_read("c", spaces["a"], 1)
        self.planner_read("b", spaces["a"], 0)
        self.mark("atomic acceptance pairs exactly two members; replay is idempotent; planner access begins only after pairing")

        membership_write, _ = self.rest("a", "couple_memberships", "POST", {
            "couple_id": spaces["a"], "user_id": self.users["d"]["id"], "seat": 3,
        })
        space_write, _ = self.rest("a", "couple_spaces?id=eq." + spaces["a"], "PATCH", {"state": "draft"})
        require(membership_write in (401, 403) and space_write in (401, 403),
                "client modified membership or couple state directly")
        third = sql("INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES(" +
                    quote(spaces["a"]) + "::uuid," + quote(self.users["d"]["id"]) + "::uuid,3)", False)
        require(third.returncode != 0 and "23514" in third.stderr,
                "database accepted a third membership seat")
        private_code, _ = self.rest("a", "partner_invitations?select=id")
        require(private_code in (404, 406), "private invitations relation was exposed through public PostgREST")
        self.mark("no direct membership/scope writes, no third seat, and private invitation storage exposure verified")
        self.spaces = spaces
        self.tokens = {"a_to_b": token, "a_to_c": new_token}

    def revoke_and_replace(self):
        space = self.spaces["b"]
        code, old = self.issue("b", space, self.users["d"]["email"])
        require(code == 200 and old.get("token"), "revoke fixture invitation failed")
        revoke_code, revoked = self.rpc("b", "revoke_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_invitation_id": old["invitation_id"],
        })
        require(revoke_code == 200 and revoked.get("status") == "revoked", "inviter could not revoke pending invitation")
        stale_code, stale = self.accept("d", old["token"])
        require(stale_code == 200 and stale == {"status": "unavailable"}, "revoked token was accepted")
        fresh_code, fresh = self.issue("b", space, self.users["d"]["email"])
        require(fresh_code == 200 and fresh.get("token") and fresh.get("invitation_id") != old.get("invitation_id"),
                "regeneration did not create a fresh invitation token")
        accepted_code, accepted = self.accept("d", fresh["token"])
        require(accepted_code == 200 and accepted.get("status") == "accepted" and
                accepted.get("space_id") == space, "regenerated invitation did not accept")
        self.mark("inviter revoke and regenerate invalidate the old token and pair only the fresh recipient")

    def expiry_and_limits(self):
        spaces = self.spaces
        code, expired = self.issue("h", spaces["h"], self.users["g"]["email"])
        require(code == 200 and expired.get("token"), "expiry fixture invitation failed")
        # Controlled fixture mutation: preserve the production row guard and
        # disable it only inside this test-only transaction while making the
        # issued row immediately expired. Production callers cannot do this.
        sql("BEGIN; ALTER TABLE app_private.partner_invitations DISABLE TRIGGER partner_invitation_guard; "
            "UPDATE app_private.partner_invitations SET expires_at=clock_timestamp()-interval '1 second' "
            "WHERE id=" + quote(expired["invitation_id"]) + "::uuid; "
            "ALTER TABLE app_private.partner_invitations ENABLE TRIGGER partner_invitation_guard; COMMIT")
        expired_code, denied = self.accept("g", expired["token"])
        require(expired_code == 200 and denied == {"status": "unavailable"} and
                sql("SELECT state FROM app_private.partner_invitations WHERE id=" +
                    quote(expired["invitation_id"]) + "::uuid") == "expired",
                "expired invitation was not denied and transitioned to expired")
        valid_code, valid = self.issue("h", spaces["h"], self.users["g"]["email"])
        require(valid_code == 200 and valid.get("token"), "rate-limit acceptance fixture failed")
        for _ in range(9):
            invalid_code, invalid = self.accept("g", secrets.token_hex(32))
            require(invalid_code == 200 and invalid == {"status": "unavailable"},
                    "invalid token attempt disclosed a different result")
        limited_code, limited = self.accept("g", valid["token"])
        require(limited_code == 200 and limited == {"status": "unavailable"} and
                sql("SELECT count(*) FROM public.couple_memberships WHERE user_id=" +
                    quote(self.users["g"]["id"]) + "::uuid AND state='active'") == "0" and
                sql("SELECT attempts FROM app_private.partner_invitation_limits WHERE actor_user_id=" +
                    quote(self.users["g"]["id"]) + "::uuid AND action='accept'") == "11",
                "acceptance rate limit did not stop valid token after 10 attempts")

        space = spaces["i"]
        for _ in range(5):
            issue_code, issue_result = self.issue("i", space, "target@example.invalid")
            require(issue_code == 200 and issue_result.get("status") == "created",
                    "invitation issue limit blocked an allowed attempt")
        blocked_code, blocked = self.issue("i", space, "target@example.invalid")
        require(blocked_code == 200 and blocked == {"status": "unavailable"} and
                sql("SELECT attempts FROM app_private.partner_invitation_limits WHERE actor_user_id=" +
                    quote(self.users["i"]["id"]) + "::uuid AND action='issue'") == "6" and
                sql("SELECT count(*) FROM app_private.partner_invitations WHERE issuer_user_id=" +
                    quote(self.users["i"]["id"]) + "::uuid") == "5",
                "invitation creation rate limit failed")
        self.mark("server-side 1-hour limits enforce 5 issue and 10 accept attempts with generic denials")

    def concurrent_acceptance(self):
        space = self.spaces["f"]
        code, invitation = self.issue("f", space, self.users["e"]["email"])
        require(code == 200 and invitation.get("token"), "concurrency invitation creation failed")
        sql("CREATE TABLE app_private.cp006b_test_accept_gate(released boolean NOT NULL); "
            "INSERT INTO app_private.cp006b_test_accept_gate VALUES(false); "
            "GRANT SELECT ON app_private.cp006b_test_accept_gate TO twogethera_membership_owner; "
            "CREATE FUNCTION app_private.cp006b_test_accept_gate_fn() RETURNS trigger "
            "LANGUAGE plpgsql SECURITY DEFINER SET search_path='' AS $$ BEGIN "
            "WHILE NOT (SELECT released FROM app_private.cp006b_test_accept_gate) LOOP "
            "PERFORM pg_catalog.pg_sleep(0.05); END LOOP; RETURN NEW; END $$; "
            "ALTER FUNCTION app_private.cp006b_test_accept_gate_fn() OWNER TO twogethera_membership_owner; "
            "CREATE TRIGGER cp006b_test_accept_gate BEFORE UPDATE ON app_private.partner_invitations "
            "FOR EACH ROW WHEN (OLD.state='pending' AND NEW.state='accepted') "
            "EXECUTE FUNCTION app_private.cp006b_test_accept_gate_fn()")
        barrier = threading.Barrier(2)
        def attempt(_):
            barrier.wait(timeout=10)
            return self.accept("e", invitation["token"])
        overlap = "0,0"
        results = []
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
                futures = [pool.submit(attempt, index) for index in range(2)]
                deadline = time.monotonic() + 10
                while time.monotonic() < deadline:
                    overlap = sql("SELECT count(*) FILTER (WHERE wait_event='PgSleep')::text||','||"
                                  "count(*) FILTER (WHERE wait_event_type='Lock')::text "
                                  "FROM pg_stat_activity WHERE datname=current_database() "
                                  "AND query ILIKE '%accept_partner_invitation%' AND pid<>pg_backend_pid()")
                    sleeping, locked = map(int, overlap.split(','))
                    if sleeping >= 1 and locked >= 1:
                        break
                    time.sleep(0.1)
                sql("UPDATE app_private.cp006b_test_accept_gate SET released=true")
                results = [future.result(timeout=20) for future in futures]
        finally:
            sql("UPDATE app_private.cp006b_test_accept_gate SET released=true; "
                "DROP TRIGGER IF EXISTS cp006b_test_accept_gate ON app_private.partner_invitations; "
                "DROP FUNCTION IF EXISTS app_private.cp006b_test_accept_gate_fn(); "
                "DROP TABLE IF EXISTS app_private.cp006b_test_accept_gate CASCADE", False)
        require(sleeping >= 1 and locked >= 1,
                "concurrent acceptance transactions did not overlap in PostgreSQL")
        outcomes = [item[1].get("status") for item in results if item[0] == 200 and isinstance(item[1], dict)]
        require(sorted(outcomes) == ["accepted", "unavailable"],
                "concurrent acceptance did not yield exactly one acceptance and one generic denial")
        final = sql("SELECT s.state||'|'||(SELECT count(*) FROM public.couple_memberships m "
                    "WHERE m.couple_id=s.id AND m.state='active')::text||'|'||"
                    "(SELECT count(*) FROM app_private.partner_invitations i WHERE i.couple_id=s.id AND i.state='accepted')::text "
                    "FROM public.couple_spaces s WHERE s.id=" + quote(space) + "::uuid")
        require(final == "paired|2|1", "concurrent acceptance left duplicate or partial membership state")
        require(sql("SELECT count(*) FROM app_private.partner_invitation_receipts WHERE actor_user_id=" +
                    quote(self.users["e"]["id"]) + "::uuid") == "1",
                "concurrent accept created duplicate or missing idempotency receipt")
        self.mark(f"real concurrent acceptance observed PgSleep/lock waits {overlap}; exact one success/one denial; final paired state has two active members")

    def no_replacement(self):
        couple = self.spaces["a"]
        sql("BEGIN; UPDATE public.couple_memberships SET state='revoked' WHERE couple_id=" +
            quote(couple) + "::uuid AND state='active'; UPDATE public.couple_spaces "
            "SET state='archived',closed_at=clock_timestamp() WHERE id=" + quote(couple) + "::uuid; COMMIT")
        replacement = sql("INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES(" +
                          quote(couple) + "::uuid," + quote(self.users["g"]["id"]) + "::uuid,1)", False)
        reopen = sql("UPDATE public.couple_spaces SET state='draft',closed_at=NULL WHERE id=" + quote(couple) + "::uuid", False)
        require(replacement.returncode != 0 and reopen.returncode != 0,
                "closed space accepted replacement or reopening")
        require(sql("SELECT state FROM public.couple_spaces WHERE id=" + quote(couple) + "::uuid") == "archived",
                "failed replacement attempt changed archived space")
        self.mark("D01: closed/archived space cannot be reopened or receive a replacement member")

    def log_scan(self):
        containers = ["supabase_rest_twogethera", "supabase_kong_twogethera", "supabase_auth_twogethera", CONTAINER]
        for container in containers:
            result = run([DOCKER, "logs", "--since", self.started_at, container], timeout=30)
            require(result.returncode == 0, "local service log inspection failed")
            logs = result.stdout + result.stderr
            require(not any(token in logs for token in self.raw_tokens),
                    "a tested raw invitation token appeared in local service logs")
        self.mark("local PostgREST, gateway, Auth and database logs contain none of the tested raw invitation tokens")

    def cleanup_fixture(self):
        sql("DROP TABLE IF EXISTS public.cp006b_test_planner_records CASCADE; "
            "DROP TRIGGER IF EXISTS cp006b_test_accept_gate ON app_private.partner_invitations; "
            "DROP FUNCTION IF EXISTS app_private.cp006b_test_accept_gate_fn(); "
            "DROP TABLE IF EXISTS app_private.cp006b_test_accept_gate CASCADE", False)

    def run(self):
        self.preflight()
        self.identities()
        self.spaces = {}
        try:
            self.issue_pairing()
            self.revoke_and_replace()
            self.expiry_and_limits()
            self.concurrent_acceptance()
            self.no_replacement()
            self.log_scan()
        finally:
            self.cleanup_fixture()
        print(f"RESULT: {len(self.groups)}/{len(self.groups)} CP-006B real local security scenario groups passed.", flush=True)
        print(f"ASSERTIONS: {ASSERTIONS} completed require() checks; scenario groups are not individual assertions.", flush=True)
        print("Synthetic Auth fixtures remain local; API client requests used only ordinary signed user JWTs; secrets suppressed.", flush=True)


if __name__ == "__main__":
    try:
        Suite().run()
    except Exception as error:
        print("FAIL:", str(error) if isinstance(error, RuntimeError) else type(error).__name__ + " (details suppressed)", file=sys.stderr)
        sys.exit(1)
