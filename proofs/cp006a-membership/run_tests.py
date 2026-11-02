#!/usr/bin/env python3
"""Real local Auth JWT -> PostgREST -> auth.uid() -> RLS CP-006A proof."""
import concurrent.futures
import base64
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

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
PROJECT = "twogethera-cp006a"
SENTINEL = "twogethera:cp006a:disposable:v1"
CONTAINER = "supabase_db_" + PROJECT
API = "http://127.0.0.1:59321"
MAIL = "http://127.0.0.1:59324"
MIGRATION = ROOT / "supabase/migrations/20261102000100_membership_foundation.sql"
SIGNING_KEY = HERE / "supabase/.local/signing_keys.json"
DOCKER = shutil.which("docker") or "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"
ENV = dict(os.environ, PATH=str(Path(DOCKER).parent) + ":" + os.environ.get("PATH", ""))
ASSERTION_COUNT = 0


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())


def require(ok, message):
    global ASSERTION_COUNT
    ASSERTION_COUNT += 1
    if not ok:
        raise RuntimeError(message)


def proc(args, stdin=None, timeout=25):
    return subprocess.run(args, input=stdin, capture_output=True, text=True, env=ENV, timeout=timeout)


def sql(statement, must_succeed=True):
    p = proc([DOCKER, "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-w", "-h", "127.0.0.1",
              "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"],
             "SET log_statement='none'; SET log_min_error_statement='panic'; SET statement_timeout='10s';\n" + statement)
    if must_succeed and p.returncode:
        safe = next((line[:180] for line in p.stderr.splitlines() if line.startswith("ERROR:")), "database error (details suppressed)")
        raise RuntimeError("guarded fixture/catalog SQL failed: " + safe)
    return p.stdout.strip() if must_succeed else p


def sql_quote(value):
    return "'" + value.replace("'", "''") + "'"


def b64url(value):
    return base64.urlsafe_b64encode(value).rstrip(b"=").decode("ascii")


def http(url, method="GET", body=None, headers=None):
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == "http" and parsed.hostname == "127.0.0.1" and parsed.port in (59321, 59324),
            "refusing nonlocal HTTP target")
    payload = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json", **(headers or {})}, method=method)
    try:
        response = HTTP.open(request, timeout=20)
    except urllib.error.HTTPError as e:
        response = e
    data = response.read()
    try:
        decoded = json.loads(data) if data else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        decoded = data.decode(errors="replace")
    return response.code, decoded


class Suite:
    def __init__(self):
        self.passed = []
        self.users = {}
        self.secrets = []
        self.run_id = secrets.token_hex(8)

    def mark(self, label):
        self.passed.append(label)
        print("PASS:", label, flush=True)

    def preflight(self):
        require(not ENV.get("DOCKER_HOST") or ENV["DOCKER_HOST"].startswith("unix://"), "remote Docker override refused")
        p = proc([DOCKER, "context", "inspect", "--format", "{{.Endpoints.docker.Host}}"])
        require(p.returncode == 0 and p.stdout.strip().startswith("unix://"), "local Docker context required")
        p = proc([DOCKER, "info", "--format", "{{.OperatingSystem}}"])
        require(p.returncode == 0 and "OrbStack" in p.stdout, "OrbStack unavailable")
        p = proc(["supabase", "status", "--workdir", str(HERE), "-o", "json"])
        require(p.returncode == 0, "isolated local Supabase must be started first")
        status = json.loads(p.stdout)
        require(status.get("API_URL") == API and "@127.0.0.1:59322/" in status.get("DB_URL", ""), "unexpected local endpoints")
        self.anon, self.admin = status.get("ANON_KEY"), status.get("SERVICE_ROLE_KEY")
        require(bool(self.anon and self.admin), "local fixture credentials unavailable (values suppressed)")
        for name in ["supabase_db_", "supabase_kong_", "supabase_inbucket_"]:
            p = proc([DOCKER, "inspect", name + PROJECT, "--format", "{{json .Config.Labels}}"])
            require(p.returncode == 0 and json.loads(p.stdout).get("com.supabase.cli.project") == PROJECT,
                    "unexpected local project container")
            p = proc([DOCKER, "inspect", name + PROJECT, "--format", "{{json .NetworkSettings.Ports}}"])
            for bindings in (json.loads(p.stdout) or {}).values():
                for binding in bindings or []:
                    require(binding["HostIp"] in ("127.0.0.1", "::1"), "non-loopback publication refused")
        print("Loopback endpoints, project labels and local engine verified; credentials suppressed.", flush=True)

    def admin_auth(self, email, password, confirmed=True):
        code, data = http(API + "/auth/v1/admin/users", "POST",
                          {"email": email, "password": password, "email_confirm": confirmed},
                          {"apikey": self.anon, "Authorization": "Bearer " + self.admin})
        require(code == 200 and isinstance(data, dict) and data.get("id"), "synthetic Auth fixture creation failed")
        return data["id"]

    def sign_in(self, name):
        u = self.users[name]
        code, data = http(API + "/auth/v1/token?grant_type=password", "POST",
                          {"email": u["email"], "password": u["password"]}, {"apikey": self.anon})
        require(code == 200 and data.get("access_token"), "local Auth password sign-in failed")
        u["token"] = data["access_token"]
        self.secrets.append(u["token"])
        return data

    def signed_token_without_role(self, name):
        # Test-only ES256 signing with this loopback project's private key.
        # The key/token stay in memory or the ignored mode-0600 .local file.
        require(SIGNING_KEY.is_file() and (SIGNING_KEY.stat().st_mode & 0o077) == 0,
                "isolated signing key is missing or has unsafe permissions")
        try:
            from cryptography.hazmat.primitives import hashes
            from cryptography.hazmat.primitives.asymmetric import ec
            from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature
        except ImportError as exc:
            raise RuntimeError("the no-role JWT regression requires local Python cryptography") from exc
        values = json.loads(SIGNING_KEY.read_text())
        if isinstance(values, dict):
            values = values.get("keys", [values])
        key = next((item for item in values if item.get("alg") == "ES256" and item.get("crv") == "P-256" and item.get("d")), None)
        require(key is not None, "isolated ES256 private signing key unavailable")

        def integer(component):
            return int.from_bytes(base64.urlsafe_b64decode(component + "=" * (-len(component) % 4)), "big")

        public = ec.EllipticCurvePublicNumbers(integer(key["x"]), integer(key["y"]), ec.SECP256R1())
        private = ec.EllipticCurvePrivateNumbers(integer(key["d"]), public).private_key()
        now = int(time.time())
        header = {"alg": "ES256", "kid": key["kid"], "typ": "JWT"}
        claims = {"iss": API + "/auth/v1", "sub": self.users[name]["id"], "aud": "authenticated",
                  "iat": now, "exp": now + 120}
        require("role" not in claims and claims["sub"] == self.users[name]["id"],
                "malformed-role test token claims are incorrect")
        signing_input = (b64url(json.dumps(header, separators=(",", ":")).encode()) + "." +
                         b64url(json.dumps(claims, separators=(",", ":")).encode())).encode()
        der = private.sign(signing_input, ec.ECDSA(hashes.SHA256()))
        r, s = decode_dss_signature(der)
        token = signing_input.decode() + "." + b64url(r.to_bytes(32, "big") + s.to_bytes(32, "big"))
        self.secrets.append(token)
        return token

    def client(self, name, path, method="GET", body=None, token=None):
        headers = {"apikey": self.anon, "Accept-Profile": "public", "Content-Profile": "public",
                   "Prefer": "return=representation"}
        actual = token if token is not None else (self.users[name].get("token") if name else None)
        if actual:
            require(actual not in (self.anon, self.admin), "elevated token used as client identity")
            headers["Authorization"] = "Bearer " + actual
        return http(API + "/rest/v1/" + path, method, body, headers)

    def rpc(self, name, function, body, token=None):
        return self.client(name, "rpc/" + function, "POST", body, token)

    def identities(self):
        for name in "abcdpq":
            email = f"cp006a-{self.run_id}-{name}@example.invalid"
            password = secrets.token_urlsafe(28)
            user_id = self.admin_auth(email, password, True)
            self.users[name] = {"email": email, "password": password, "id": user_id}
            self.sign_in(name)
        email = f"cp006a-{self.run_id}-g@example.invalid"
        password = secrets.token_urlsafe(28)
        self.users["g"] = {"email": email, "password": password,
                           "id": self.admin_auth(email, password, True)}
        self.sign_in("g")
        unverified_email = f"cp006a-{self.run_id}-u@example.invalid"
        unverified_password = secrets.token_urlsafe(28)
        self.users["u"] = {"email": unverified_email, "password": unverified_password,
                           "id": self.admin_auth(unverified_email, unverified_password, False)}
        unverified_state = sql("SELECT count(*)=1 AND bool_and(email_confirmed_at IS NULL) FROM auth.users WHERE email='" + unverified_email + "'")
        require(unverified_state in ("t", "true"),
                "unverified fixture not confirmed from authoritative Auth row (observed=" + repr(unverified_state) + ")")
        code, _ = http(API + "/auth/v1/token?grant_type=password", "POST",
                       {"email": unverified_email, "password": unverified_password}, {"apikey": self.anon})
        require(code in (400, 401), "unverified account unexpectedly obtained a client session")
        self.mark("verified and unverified synthetic identities established from Auth state; unverified sign-in denied")

    def install(self):
        marker = sql("SELECT coalesce(shobj_description(oid,'pg_database'),'') FROM pg_database WHERE datname=current_database()")
        require(marker in ("", "default administrative connection database", SENTINEL), "wrong isolated database marker")
        if marker != SENTINEL:
            require(sql("SELECT count(*) FROM pg_namespace WHERE nspname='app_private'") == "0", "unmarked app schema collision")
            sql("COMMENT ON DATABASE postgres IS '" + SENTINEL + "'")
        else:
            role_marker = sql("SELECT coalesce(shobj_description(oid,'pg_authid'),'') FROM pg_roles WHERE rolname='twogethera_membership_owner'")
            require(role_marker in ("", "twogethera:cp006a:membership-owner:v1"), "unexpected membership owner role marker")
            if role_marker:
                sql("DROP FUNCTION IF EXISTS public.create_couple_space(uuid) CASCADE; "
                    "DROP FUNCTION IF EXISTS public.cp006a_test_whoami() CASCADE; "
                    "DROP FUNCTION IF EXISTS public.cp006a_test_authorized_identity() CASCADE; "
                    "DROP TABLE IF EXISTS public.cp006a_test_shared_records CASCADE; "
                    "DROP TABLE IF EXISTS public.couple_memberships CASCADE; "
                    "DROP TABLE IF EXISTS public.couple_spaces CASCADE; "
                    "DROP SCHEMA IF EXISTS app_private CASCADE")
        # The only production migration is the reviewed root application migration.
        sql(MIGRATION.read_text())
        code, jwks = http(API + "/auth/v1/.well-known/jwks.json")
        require(code == 200 and isinstance(jwks, dict) and jwks.get("keys")
                and all(key.get("alg") == "ES256" and "d" not in key for key in jwks["keys"]),
                "local Auth public signing keys unavailable or unsafe")
        sql("ALTER ROLE authenticator SET pgrst.jwt_secret=" + sql_quote(json.dumps(jwks, separators=(",", ":"))) +
            "; ALTER ROLE authenticator SET pgrst.db_schemas='public'; NOTIFY pgrst,'reload config'; NOTIFY pgrst,'reload schema'")
        p = proc([DOCKER, "restart", "supabase_rest_" + PROJECT], timeout=20)
        require(p.returncode == 0, "isolated PostgREST verifier restart failed")
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            try:
                code, _ = http(API + "/auth/v1/health")
                if code == 200:
                    break
            except Exception:
                pass
            time.sleep(0.25)
        require(code == 200, "isolated PostgREST did not recover after verifier configuration")
        self.mark("PostgREST verifier restricted to Auth-published public ES256 JWKS")
        # Test-only relation and function are deliberately installed outside supabase/migrations.
        fixture = r"""
CREATE TABLE public.cp006a_test_shared_records (
 id uuid PRIMARY KEY DEFAULT gen_random_uuid(), couple_id uuid NOT NULL REFERENCES public.couple_spaces(id),
 body text NOT NULL
);
ALTER TABLE public.cp006a_test_shared_records ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON public.cp006a_test_shared_records TO authenticated;
REVOKE ALL ON public.cp006a_test_shared_records FROM PUBLIC,anon,authenticated,service_role;
GRANT SELECT ON public.cp006a_test_shared_records TO authenticated;
CREATE POLICY cp006a_test_shared_records_read ON public.cp006a_test_shared_records
 FOR SELECT TO authenticated USING (app_private.can_read_shared_records(couple_id));
CREATE FUNCTION public.cp006a_test_whoami() RETURNS uuid LANGUAGE sql STABLE SET search_path=''
 AS 'SELECT auth.uid()';
REVOKE ALL ON FUNCTION public.cp006a_test_whoami() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.cp006a_test_whoami() TO authenticated;
CREATE FUNCTION public.cp006a_test_authorized_identity() RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER SET search_path=''
 AS $$ DECLARE v_user uuid; BEGIN v_user:=app_private.current_identity_is_verified(false); IF v_user IS NULL THEN
 RAISE EXCEPTION 'unavailable' USING ERRCODE='42501'; END IF; RETURN v_user; END $$;
ALTER FUNCTION public.cp006a_test_authorized_identity() OWNER TO twogethera_membership_owner;
REVOKE ALL ON FUNCTION public.cp006a_test_authorized_identity() FROM PUBLIC,anon,service_role;
GRANT EXECUTE ON FUNCTION public.cp006a_test_authorized_identity() TO authenticated;
NOTIFY pgrst, 'reload schema';
"""
        sql(fixture)
        deadline = time.monotonic() + 15
        while time.monotonic() < deadline:
            code, _ = http(API + "/rest/v1/rpc/create_couple_space", "POST", {"p_operation_id": str(uuid.uuid4())},
                           {"apikey": self.anon})
            if code != 404:
                break
            time.sleep(0.25)
        require(code != 404, "PostgREST did not load the isolated application command")
        self.mark("fresh isolated database accepted root migration; test-only record fixture kept outside application migrations")

    def create(self, name, op=None):
        code, data = self.rpc(name, "create_couple_space", {"p_operation_id": op or str(uuid.uuid4())})
        detail = data.get("code") if isinstance(data, dict) else type(data).__name__
        message = data.get("message", "") if isinstance(data, dict) else ""
        require(code == 200 and isinstance(data, str), f"create command expected success, got HTTP {code}/{detail}/{message[:100]}")
        return data

    def identity_and_rls(self):
        a = self.create("a")
        c = self.create("c")
        p = self.create("p")
        # Only this guarded administrator fixture pairs p/q; no invite operation is introduced.
        sql("BEGIN; UPDATE public.couple_spaces SET state='paired' WHERE id='" + p + "'::uuid; "
            "INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES('" + p + "'::uuid,'" + self.users["q"]["id"] + "'::uuid,2); COMMIT;")
        sql("INSERT INTO public.cp006a_test_shared_records(couple_id,body) VALUES "
            "('" + a + "'::uuid,'draft-only synthetic planner fixture'),('" + p + "'::uuid,'paired synthetic fixture')")
        code, who = self.rpc("a", "cp006a_test_whoami", {})
        require(code == 200 and who == self.users["a"]["id"], "auth.uid() did not resolve signed JWT principal")
        self.mark("genuine Auth JWT resolves through PostgREST to the correct auth.uid()")

        code, rows = self.client("a", "couple_spaces?select=id,state&order=id")
        require(code == 200 and [row["id"] for row in rows] == [a], "member did not read only own draft metadata")
        self.mark("draft setup metadata is visible only to the current member")

        code, rows = self.client("a", "cp006a_test_shared_records?select=id,body&couple_id=eq." + a)
        require(code == 200 and rows == [], "D09 regression: unpaired member read a draft planner record")
        code, rows = self.client("c", "cp006a_test_shared_records?select=id,body&couple_id=eq." + a)
        require(code == 200 and rows == [], "cross-couple shared record leaked")
        self.mark("unpaired draft and unrelated couple cannot read synthetic planner record (D09 regression)")

        for name in ("p", "q"):
            code, rows = self.client(name, "cp006a_test_shared_records?select=id,body&couple_id=eq." + p)
            require(code == 200 and len(rows) == 1 and rows[0]["body"] == "paired synthetic fixture",
                    "paired member failed authorized shared fixture read")
        self.mark("both members of exactly paired test space read only their shared synthetic record")

        code, rows = self.client("c", "couple_spaces?select=id")
        require(code == 200 and all(row["id"] != a for row in rows), "unrelated user saw another couple metadata")
        self.mark("PostgREST RLS filters unrelated couple metadata")
        self.ids = {"a": a, "c": c, "p": p}

    def writes_and_invariants(self):
        couple = self.ids["a"]
        cases = [
            ("insert", "POST", {"couple_id": couple, "body": "unauthorized"}),
            ("update", "PATCH", {"body": "unauthorized"}),
            ("delete", "DELETE", None),
        ]
        for label, method, body in cases:
            code, _ = self.client("a", "cp006a_test_shared_records?couple_id=eq." + couple, method, body)
            require(code in (401, 403, 405), f"direct {label} unexpectedly allowed (HTTP {code})")
        code, _ = self.client("a", "couple_memberships", "POST", {"couple_id": couple, "user_id": self.users["b"]["id"], "seat": 2})
        require(code in (401, 403, 405), "client membership insertion unexpectedly allowed")
        code, _ = self.client("a", "couple_spaces?id=eq." + couple, "PATCH", {"state": "paired"})
        require(code in (401, 403, 405), "client scope mutation unexpectedly allowed")
        self.mark("authenticated direct record/member/scope insert, update and delete are denied")

        code, body = self.client(None, "cp006a_test_shared_records?select=id")
        require(code in (401, 403), "anonymous table read unexpectedly allowed")
        code, body = self.rpc(None, "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        require(code in (401, 403), "anonymous membership command unexpectedly allowed")
        bad = "not-a-signed-jwt"
        code, _ = self.client("a", "couple_spaces?select=id", token=bad)
        require(code in (401, 403), "malformed token unexpectedly authorized")
        self.mark("anonymous and malformed-token reads/commands are denied")

        # The JWT is signed by this disposable project's actual Auth signing key,
        # has a real Auth subject and valid exp, but deliberately omits role.
        no_role = self.signed_token_without_role("a")
        code, rows = self.client("a", "cp006a_test_shared_records?select=id&couple_id=eq." + self.ids["p"], token=no_role)
        require((code in (200, 401, 403) and rows == []) or code in (401, 403),
                "signed JWT without role claim exposed shared data")
        code, _ = self.rpc("a", "create_couple_space", {"p_operation_id": str(uuid.uuid4())}, token=no_role)
        require(code in (401, 403), "signed JWT without role claim invoked membership command")
        # Assert the database gate itself is NULL-safe independently of how
        # PostgREST classifies an incomplete role claim.
        no_role_uid = self.users["a"]["id"]
        result = sql("BEGIN; SET LOCAL ROLE twogethera_membership_owner; "
                     "SELECT set_config('request.jwt.claim.sub','" + no_role_uid + "',true); "
                     "SELECT set_config('request.jwt.claims','{\"sub\":\"" + no_role_uid + "\",\"exp\":\"" + str(int(time.time()) + 60) + "\"}',true); "
                     "SELECT app_private.current_identity_is_verified(false) IS NULL; ROLLBACK;")
        require(result.splitlines()[-1:] == ["t"], "identity gate did not fail closed for a missing role claim")
        self.mark("validly signed no-role JWT and direct gate regression both fail closed")

        op = str(uuid.uuid4())
        first = self.create("b", op)
        second = self.create("b", op)
        require(first == second, "identical operation replay created a second couple")
        code, detail = self.rpc("b", "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        require(code == 409 and isinstance(detail, dict) and detail.get("code") == "23505",
                "second active-space command did not return its expected unique-conflict response")
        require(sql("SELECT count(*) FROM public.couple_memberships WHERE user_id='" + self.users["b"]["id"] + "'::uuid AND state='active'") == "1",
                "second active-space rejection changed the membership state")
        self.mark("creation retries are idempotent and a second active couple is rejected")

        # Deterministic DB gate holds the first create transaction inside its
        # space INSERT trigger while the other requests queue on the actor lock.
        sql("CREATE TABLE app_private.cp006a_test_gate(released boolean NOT NULL); "
            "INSERT INTO app_private.cp006a_test_gate VALUES(false); "
            "GRANT SELECT ON app_private.cp006a_test_gate TO twogethera_membership_owner; "
            "CREATE FUNCTION app_private.cp006a_test_gate_insert() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path='' "
            "AS $$ BEGIN WHILE NOT (SELECT released FROM app_private.cp006a_test_gate) LOOP PERFORM pg_catalog.pg_sleep(0.05); END LOOP; RETURN NEW; END $$; "
            "ALTER FUNCTION app_private.cp006a_test_gate_insert() OWNER TO twogethera_membership_owner; "
            "CREATE TRIGGER cp006a_test_gate BEFORE INSERT ON public.couple_spaces "
            "FOR EACH ROW WHEN (current_setting('application_name',true) ILIKE '%postgrest%') "
            "EXECUTE FUNCTION app_private.cp006a_test_gate_insert()")
        barrier = threading.Barrier(6)
        def attempt(_):
            barrier.wait(timeout=10)
            return self.rpc("d", "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        results = []
        overlap = None
        try:
            with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
                futures = [pool.submit(attempt, i) for i in range(6)]
                deadline = time.monotonic() + 12
                while time.monotonic() < deadline:
                    overlap = sql("SELECT count(*) FILTER (WHERE wait_event='PgSleep')::text || ',' || "
                                  "count(*) FILTER (WHERE wait_event_type='Lock')::text "
                                  "FROM pg_stat_activity WHERE datname=current_database() "
                                  "AND query ILIKE '%create_couple_space%' AND pid<>pg_backend_pid()")
                    try:
                        sleeping, locked = map(int, overlap.split(','))
                    except Exception:
                        sleeping, locked = 0, 0
                    if sleeping >= 1 and locked >= 5:
                        break
                    time.sleep(0.1)
                sql("UPDATE app_private.cp006a_test_gate SET released=true")
                require(overlap is not None and sleeping >= 1 and locked >= 5,
                        "could not observe one held transaction and five lock-waiting transactions")
                results = [f.result(timeout=25) for f in futures]
        finally:
            sql("UPDATE app_private.cp006a_test_gate SET released=true; "
                "DROP TRIGGER IF EXISTS cp006a_test_gate ON public.couple_spaces; "
                "DROP FUNCTION IF EXISTS app_private.cp006a_test_gate_insert(); "
                "DROP TABLE IF EXISTS app_private.cp006a_test_gate CASCADE", False)
        successes = [r for r in results if r[0] == 200]
        conflicts = [r for r in results if r[0] == 409]
        require(len(successes) == 1 and len(conflicts) == 5,
                "overlapping creates must yield exactly one success and five conflict responses")
        final_state = sql("SELECT "
                          "(SELECT count(*) FROM public.couple_spaces s JOIN public.couple_memberships m ON m.couple_id=s.id "
                          "WHERE m.user_id='" + self.users["d"]["id"] + "'::uuid AND m.state='active' AND s.state='draft')::text || ',' || "
                          "(SELECT count(*) FROM public.couple_memberships WHERE user_id='" + self.users["d"]["id"] + "'::uuid AND state='active')::text || ',' || "
                          "(SELECT count(*) FROM app_private.couple_create_receipts WHERE actor_user_id='" + self.users["d"]["id"] + "'::uuid)")
        require(final_state == "1,1,1", "concurrent create final space/member/receipt state was " + final_state)
        self.mark(f"six HTTP creates overlapped (observed pg_sleep/lock waits {overlap}), yielding exact 1 success/5 conflicts and 1/1/1 final state")

        # Catalog and lifecycle invariants, including revoked timestamp semantics.
        archived_state = sql("INSERT INTO public.couple_memberships(couple_id,user_id,seat,state,revoked_at) "
                             "VALUES('" + self.ids["a"] + "'::uuid,'" + self.users["g"]["id"] + "'::uuid,2,'archived',now())", False)
        require(archived_state.returncode != 0, "unsupported archived membership state was accepted")
        sql("BEGIN; UPDATE public.couple_memberships SET state='revoked' WHERE couple_id='" + self.ids["a"] + "'::uuid; ROLLBACK")
        revocation_shape = sql("SELECT state='active' AND revoked_at IS NULL FROM public.couple_memberships WHERE couple_id='" + self.ids["a"] + "'::uuid")
        require(revocation_shape == "t", "rollback lifecycle fixture changed the active membership")
        # A draft cannot be completed by replacing its original seat-1 creator.
        replacement_draft = str(uuid.uuid4())
        failed = sql("BEGIN; INSERT INTO public.couple_spaces(id) VALUES('" + replacement_draft + "'::uuid); "
                     "INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES('" + replacement_draft + "'::uuid,'" + self.users["g"]["id"] + "'::uuid,1); "
                     "UPDATE public.couple_memberships SET state='revoked' WHERE couple_id='" + replacement_draft + "'::uuid; "
                     "INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES('" + replacement_draft + "'::uuid,'" + self.users["u"]["id"] + "'::uuid,2); "
                     "UPDATE public.couple_spaces SET state='paired' WHERE id='" + replacement_draft + "'::uuid; COMMIT", False)
        require(failed.returncode != 0 and "23514" in failed.stderr,
                "draft replacement member passed deferred cardinality invariant")
        require(sql("SELECT count(*) FROM public.couple_spaces WHERE id='" + replacement_draft + "'::uuid") == "0",
                "failed draft replacement transaction left a space behind")
        self.mark("membership state and creator-seat transition constraints reject unsupported/archive replacement states")

        third = sql("INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES('" + self.ids["p"] + "'::uuid,'" + self.users["b"]["id"] + "'::uuid,3)", False)
        require(third.returncode != 0, "third seat unexpectedly passed database seat constraint")
        archive = str(uuid.uuid4())
        sql("BEGIN; INSERT INTO public.couple_spaces(id,state,closed_at) VALUES('" + archive + "'::uuid,'archived',now()); COMMIT;")
        replacement = sql("INSERT INTO public.couple_memberships(couple_id,user_id,seat) VALUES('" + archive + "'::uuid,'" + self.users["b"]["id"] + "'::uuid,1)", False)
        reopen = sql("UPDATE public.couple_spaces SET state='draft',closed_at=NULL WHERE id='" + archive + "'::uuid", False)
        require(replacement.returncode != 0 and reopen.returncode != 0, "archived space accepted replacement or reopening")
        self.mark("database rejects third seat, replacement membership and archived-space reopening")

        # Current Auth verification state is authoritative even while the signed token is still valid.
        sql("UPDATE auth.users SET email_confirmed_at=NULL WHERE id='" + self.users["a"]["id"] + "'::uuid")
        code, _ = self.rpc("a", "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        require(code in (401, 403), "current unverified Auth row did not receive an expected authorization denial")
        self.mark("server-side Auth confirmation recheck denies a still-valid JWT after verification is revoked")

    def owner_role_guard(self):
        # Re-run only the migration's fail-closed role guard against deliberately
        # misconfigured variants, always restoring the role before continuing.
        guard = MIGRATION.read_text().split("CREATE SCHEMA IF NOT EXISTS app_private AUTHORIZATION")[0]
        role = "twogethera_membership_owner"
        def rejected(label, setup, restore):
            sql(setup)
            attempt = sql(guard, False)
            sql(restore)
            require(attempt.returncode != 0 and "42501" in attempt.stderr,
                    "owner-role guard accepted unsafe configuration: " + label)
        rejected("outgoing membership", "GRANT authenticated TO " + role,
                 "REVOKE authenticated FROM " + role)
        rejected("incoming membership", "GRANT " + role + " TO authenticated",
                 "REVOKE " + role + " FROM authenticated")
        rejected("INHERIT enabled", "ALTER ROLE " + role + " INHERIT",
                 "ALTER ROLE " + role + " NOINHERIT")
        self.mark("migration owner-role guard rejects both role-membership directions and INHERIT")

    def failure_atomicity(self):
        user_id = self.users["g"]["id"]
        op = str(uuid.uuid4())
        before = sql("SELECT (SELECT count(*) FROM public.couple_spaces)::text || ',' || "
                     "(SELECT count(*) FROM public.couple_memberships)::text || ',' || "
                     "(SELECT count(*) FROM app_private.couple_create_receipts)::text || ',' || "
                     "(SELECT count(*) FROM app_private.couple_create_receipts WHERE actor_user_id='" + user_id + "'::uuid AND operation_id='" + op + "'::uuid)")
        sql("CREATE FUNCTION app_private.cp006a_test_fail_receipt() RETURNS trigger LANGUAGE plpgsql SET search_path='' "
            "AS $$ BEGIN RAISE EXCEPTION 'cp006a_injected_receipt_failure' USING ERRCODE='PT500'; END $$; "
            "CREATE TRIGGER cp006a_test_fail_receipt BEFORE INSERT ON app_private.couple_create_receipts "
            "FOR EACH ROW EXECUTE FUNCTION app_private.cp006a_test_fail_receipt()")
        code, body = self.rpc("g", "create_couple_space", {"p_operation_id": op})
        sql("DROP TRIGGER cp006a_test_fail_receipt ON app_private.couple_create_receipts; DROP FUNCTION app_private.cp006a_test_fail_receipt()")
        after = sql("SELECT (SELECT count(*) FROM public.couple_spaces)::text || ',' || "
                    "(SELECT count(*) FROM public.couple_memberships)::text || ',' || "
                    "(SELECT count(*) FROM app_private.couple_create_receipts)::text || ',' || "
                    "(SELECT count(*) FROM app_private.couple_create_receipts WHERE actor_user_id='" + user_id + "'::uuid AND operation_id='" + op + "'::uuid)")
        require(code == 500 and isinstance(body, dict) and body.get("code") == "PT500" and
                body.get("message") == "cp006a_injected_receipt_failure",
                "injected receipt trigger did not produce its exact expected HTTP error")
        require(before == after, "late command failure changed persistent state: before=" + before + " after=" + after)
        self.mark("exact injected receipt failure returned expected code/message and all space/member/receipt counts rolled back")

    def revocation_and_catalog(self):
        c, user_id = self.ids["c"], self.users["c"]["id"]
        sql("BEGIN; UPDATE public.couple_memberships SET state='revoked' WHERE couple_id='" + c + "'::uuid; "
            "UPDATE public.couple_spaces SET state='archived',closed_at=now() WHERE id='" + c + "'::uuid; COMMIT;")
        revoke_timestamp = sql("SELECT state='revoked' AND revoked_at IS NOT NULL FROM public.couple_memberships WHERE couple_id='" + c + "'::uuid")
        require(revoke_timestamp == "t", "active-to-revoked trigger did not set revoked_at")
        code, rows = self.client("c", "couple_spaces?select=id")
        require(code == 200 and all(row["id"] != c for row in rows), "revoked valid JWT retained old scope access")
        code, rows = self.client("c", "cp006a_test_shared_records?select=id&couple_id=eq." + c)
        require(code == 200 and rows == [], "revoked member retained shared-record access")
        self.mark("membership revocation and archive transition deny subsequent requests with the same signed JWT")

        checks = sql("SELECT "
            "(SELECT relrowsecurity FROM pg_class WHERE oid='public.couple_spaces'::regclass) AND "
            "(SELECT relrowsecurity FROM pg_class WHERE oid='public.couple_memberships'::regclass) AND "
            "NOT has_table_privilege('authenticated','public.couple_memberships','INSERT') AND "
            "NOT has_table_privilege('authenticated','public.couple_memberships','UPDATE') AND "
            "NOT has_table_privilege('authenticated','public.couple_memberships','DELETE') AND "
            "NOT has_function_privilege('anon','public.create_couple_space(uuid)','EXECUTE') AND "
            "NOT EXISTS (SELECT 1 FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl,acldefault('f',p.proowner))) a "
            "WHERE p.oid='public.create_couple_space(uuid)'::regprocedure AND a.grantee=0 AND a.privilege_type='EXECUTE') AND "
            "(SELECT NOT rolcanlogin AND NOT rolsuper AND NOT rolcreatedb AND NOT rolcreaterole AND NOT rolreplication "
            "AND NOT rolbypassrls AND NOT rolinherit AND shobj_description(oid,'pg_authid')='twogethera:cp006a:membership-owner:v1' "
            "FROM pg_roles WHERE rolname='twogethera_membership_owner') AND "
            "NOT EXISTS (SELECT 1 FROM pg_auth_members WHERE "
            "(roleid='twogethera_membership_owner'::regrole AND member <> 'postgres'::regrole) "
            "OR member='twogethera_membership_owner'::regrole) AND "
            "(SELECT proowner='postgres'::regrole FROM pg_proc WHERE oid='app_private.current_identity_is_verified(boolean)'::regprocedure) AND "
            "NOT EXISTS (SELECT 1 FROM pg_constraint c WHERE c.contype='f' AND c.conrelid IN "
            "('public.couple_memberships'::regclass,'app_private.couple_create_receipts'::regclass) "
            "AND c.confrelid='auth.users'::regclass)")
        require(checks == "t", "RLS/grants/function-owner catalog boundary failed")
        code, body = http(API + "/rest/v1/rpc/can_read_couple", "POST", {"p_couple_id": c},
                          {"apikey": self.anon, "Authorization": "Bearer " + self.users["b"]["token"],
                           "Accept-Profile": "app_private", "Content-Profile": "app_private"})
        require(code == 406 and isinstance(body, dict) and body.get("code") == "PGRST106",
                "private-schema profile request did not receive the expected unexposed-schema denial")
        self.mark("RLS/grants/owner attributes and explicit app_private HTTP profile denial verified")

    def expired_token(self):
        # Refresh only this synthetic fixture now so a genuine short-lived local token expires at suite end.
        self.sign_in("q")
        # Verify access while still valid before waiting for the actual Auth-issued token to expire.
        pre_code, pre_rows = self.client("q", "cp006a_test_shared_records?select=id&couple_id=eq." + self.ids["p"])
        require(pre_code == 200 and len(pre_rows) == 1, "fresh JWT could not read its authorized paired record")
        pre_auth_code, pre_user = self.rpc("q", "cp006a_test_authorized_identity", {})
        require(pre_auth_code == 200 and pre_user == self.users["q"]["id"], "fresh JWT failed current identity gate")
        import base64
        claim_part = self.users["q"]["token"].split(".")[1]
        exp = int(json.loads(base64.urlsafe_b64decode(claim_part + "=" * (-len(claim_part) % 4))).get("exp", 0))
        wait = max(0, exp - int(time.time()) + 2)
        if wait:
            print(f"Waiting {wait}s for a genuine local Auth JWT to expire.", flush=True)
            time.sleep(wait)
        auth_code, _ = http(API + "/auth/v1/user", headers={"apikey": self.anon,
                                                               "Authorization": "Bearer " + self.users["q"]["token"]})
        code, rows = self.client("q", "cp006a_test_shared_records?select=id&couple_id=eq." + self.ids["p"])
        gate_code, _ = self.rpc("q", "cp006a_test_authorized_identity", {})
        require(auth_code in (401, 403) and gate_code in (401, 403) and code == 200 and rows == [],
                "expired token retained authorized application data or Auth session")
        self.mark("expired signed token rejected by Auth; RLS read is empty and current identity RPC is denied")

    def run(self):
        self.preflight()
        self.identities()
        self.install()
        self.owner_role_guard()
        self.identity_and_rls()
        self.writes_and_invariants()
        self.failure_atomicity()
        self.revocation_and_catalog()
        self.expired_token()
        print(f"RESULT: {len(self.passed)}/{len(self.passed)} CP-006A real local Auth/PostgREST/RLS scenarios passed.", flush=True)
        print(f"ASSERTIONS: {ASSERTION_COUNT} completed require() checks; scenario groups above are not individual assertions.", flush=True)
        print("No client authorization result used a service-role token; secrets suppressed.")


if __name__ == "__main__":
    try:
        Suite().run()
    except Exception as exc:
        print("FAIL:", str(exc) if isinstance(exc, RuntimeError) else type(exc).__name__ + " (details suppressed)", file=sys.stderr)
        sys.exit(1)
