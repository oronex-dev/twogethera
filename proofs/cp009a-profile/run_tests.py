#!/usr/bin/env python3
"""CP-009A profile ownership and partner-visibility proof via local JWT API."""
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid

ROOT = Path(__file__).resolve().parents[2]
API = "http://127.0.0.1:54321"
CONTAINER = "supabase_db_twogethera"
DOCKER = shutil.which("docker") or "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"
ENV = dict(os.environ, PATH=str(Path(DOCKER).parent) + ":" + os.environ.get("PATH", ""))
OPENER = urllib.request.build_opener(urllib.request.ProxyHandler({}))
ASSERTIONS = 0


def check(ok, message):
    global ASSERTIONS
    ASSERTIONS += 1
    if not ok:
        raise RuntimeError(message)


def command(args):
    return subprocess.run(args, capture_output=True, text=True, env=ENV, timeout=30)


def request(url, method="GET", body=None, headers=None):
    parsed = urllib.parse.urlsplit(url)
    check(parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
          and parsed.port == 54321, "refusing non-local API endpoint")
    data = body if isinstance(body, bytes) else (
        json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, method=method, headers=headers or {})
    try:
        response = OPENER.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    try:
        decoded = json.loads(raw) if raw else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        decoded = raw
    return response.code, decoded


class ProfileProof:
    def __init__(self):
        self.anon = self.admin = None
        self.users = {}
        self.space = None
        self.token = None

    def sql(self, statement):
        result = subprocess.run([DOCKER, "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-w",
                                 "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
                                input=statement, capture_output=True, text=True, env=ENV, timeout=30)
        if result.returncode:
            raise RuntimeError("local database security preflight failed")
        return result.stdout.strip()

    def preflight(self):
        status = command(["supabase", "status", "-o", "json"])
        check(status.returncode == 0, "local Supabase status unavailable")
        config = json.loads(status.stdout)
        self.anon, self.admin = config.get("ANON_KEY"), config.get("SERVICE_ROLE_KEY")
        check(config.get("API_URL") == API and "@127.0.0.1:54322/" in config.get("DB_URL", ""),
              "refusing unexpected Supabase endpoint")
        labels = command([DOCKER, "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"])
        check(labels.returncode == 0 and
              json.loads(labels.stdout).get("com.supabase.cli.project") == "twogethera",
              "refusing database outside local Twogethera project")
        applied = set(self.sql("SELECT version FROM supabase_migrations.schema_migrations" ).splitlines())
        check({"20261102000600", "20261102000700"}.issubset(applied),
              "profile migrations are not fully applied locally")
        policy = self.sql("SELECT c.relrowsecurity||'|'||c.relforcerowsecurity FROM pg_class c "
                          "WHERE c.oid='public.user_profiles'::regclass")
        check(policy == "true|true", "profile table is missing enabled/forced RLS")
        public_bucket = self.sql("SELECT public FROM storage.buckets WHERE id='profile-photos'")
        check(public_bucket == "f", "profile photo bucket must remain private")
        check(bool(self.anon and self.admin), "local synthetic Auth setup keys unavailable")

    def create_user(self, label):
        email = f"cp009a-{secrets.token_hex(5)}-{label}@example.invalid"
        password = secrets.token_urlsafe(28)
        code, user = request(API + "/auth/v1/admin/users", "POST",
            {"email": email, "password": password, "email_confirm": True,
             "user_metadata": {"display_name": f"Synthetic {label}"}},
            {"apikey": self.anon, "Authorization": "Bearer " + self.admin,
             "Content-Type": "application/json"})
        check(code == 200 and isinstance(user, dict) and isinstance(user.get("id"), str),
              "synthetic local Auth identity setup failed")
        code, session = request(API + "/auth/v1/token?grant_type=password", "POST",
            {"email": email, "password": password},
            {"apikey": self.anon, "Content-Type": "application/json"})
        check(code == 200 and isinstance(session, dict) and session.get("access_token"),
              "real local Supabase sign-in failed")
        self.users[label] = {"id": user["id"], "email": email,
                             "jwt": session["access_token"]}

    def headers(self, actor=None, accept="application/json"):
        result = {"apikey": self.anon, "Accept": accept}
        if actor:
            result["Authorization"] = "Bearer " + self.users[actor]["jwt"]
        return result

    def rpc(self, actor, name, body):
        return request(API + "/rest/v1/rpc/" + name, "POST", body,
                       {**self.headers(actor), "Content-Type": "application/json"})

    def rest(self, actor, path, method="GET", body=None, extra=None):
        return request(API + "/rest/v1/" + path, method, body,
                       {**self.headers(actor), "Content-Type": "application/json",
                        "Prefer": "return=representation", **(extra or {})})

    def setup(self):
        for label in ("a", "b", "c"):
            self.create_user(label)
        for label in ("a", "b", "c"):
            code, result = self.rpc(label, "ensure_account", {})
            check(code == 200, "own profile provisioning failed")
        code, self.space = self.rpc("a", "create_couple_space",
                                    {"p_operation_id": str(uuid.uuid4())})
        check(code == 200 and isinstance(self.space, str), "couple draft creation failed")
        code, invite = self.rpc("a", "issue_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_couple_id": self.space,
            "p_expected_epoch": 1, "p_recipient_email": self.users["b"]["email"]})
        check(code == 200 and isinstance(invite, dict) and invite.get("token"),
              "verified synthetic partner invite failed")
        self.token = invite["token"]
        code, accepted = self.rpc("b", "accept_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_token": self.token})
        check(code == 200 and accepted.get("status") == "accepted", "pairing failed")
        for actor, name, about in (("a", "Partner A", "private A note"),
                                   ("b", "Partner B", "private B note")):
            code, rows = self.rest(actor, "user_profiles?user_id=eq." + self.users[actor]["id"],
                "PATCH", {"display_name": name, "about": about},
                {"Content-Profile": "public"})
            check(code == 200 and isinstance(rows, list) and len(rows) == 1,
                  "owner profile update failed")

    def profile_access(self):
        a_id, b_id = self.users["a"]["id"], self.users["b"]["id"]
        code, rows = self.rest("a", f"user_profiles?user_id=eq.{a_id}&select=user_id,display_name,about")
        check(code == 200 and len(rows) == 1 and rows[0]["about"] == "private A note",
              "owner cannot read own private profile")
        code, rows = self.rest("b", f"user_profiles?user_id=eq.{a_id}&select=user_id,display_name,about")
        check(code == 200 and rows == [], "partner read private profile table fields")
        code, rows = self.rest("c", f"user_profiles?user_id=eq.{a_id}&select=user_id,display_name,about")
        check(code == 200 and rows == [], "unpaired account read another profile")
        code, rows = self.rest(None, f"user_profiles?user_id=eq.{a_id}&select=user_id")
        check((code == 200 and rows == []) or code in (401, 403),
              "anonymous request read profile")
        code, projection = self.rpc("a", "partner_profile", {})
        check(code == 200 and set(projection) == {"display_name", "avatar_path"}
              and projection["display_name"] == "Partner B"
              and "about" not in projection and "user_id" not in projection,
              "partner RPC returned nonshared personal data")
        code, projection = self.rpc("c", "partner_profile", {})
        check(code == 200 and projection is None, "unpaired account received partner profile")
        code, changed = self.rest("b", f"user_profiles?user_id=eq.{a_id}", "PATCH",
                                  {"about": "unauthorized edit"})
        check(code == 200 and changed == [], "partner modified private profile")
        code, changed = self.rest("c", f"user_profiles?user_id=eq.{a_id}", "PATCH",
                                  {"display_name": "Impersonated"})
        check(code == 200 and changed == [], "unpaired user modified another profile")
        code, _ = self.rest("a", f"user_profiles?user_id=eq.{a_id}", "PATCH",
                            {"user_id": b_id})
        check(code in (400, 401, 403), "authenticated user changed immutable profile owner id")
        code, rows = self.rest("a", f"user_profiles?user_id=eq.{a_id}&select=about")
        check(code == 200 and rows == [{"about": "private A note"}],
              "unauthorized profile update changed stored private data")

    def storage_access(self):
        # A valid 1x1 PNG payload. Storage only accepts sanitized image/png.
        png = bytes.fromhex("89504e470d0a1a0a0000000d49484452000000010000000108060000001f15c489"
                            "0000000b49444154789c636000020000050001a5f645400000000049454e44ae426082")
        path = self.users["a"]["id"] + "/avatar"
        code, rows = self.rest("a", "user_profiles?user_id=eq." + self.users["a"]["id"],
                               "PATCH", {"avatar_path": path})
        check(code == 200 and len(rows) == 1,
              "owner could not authorize profile photo through own profile pointer")
        code, _ = request(API + "/storage/v1/object/profile-photos/" + path, "POST", png,
                          {**self.headers("a", "*/*"), "Content-Type": "image/png",
                           "x-upsert": "true"})
        check(code in (200, 201), "owner could not upload private profile photo")
        code, data = request(API + "/storage/v1/object/profile-photos/" + path, "GET",
                             headers=self.headers("b", "image/png"))
        check(code == 200 and isinstance(data, bytes) and data.startswith(b"\x89PNG"),
              "active partner could not read authorized photo")
        code, _ = request(API + "/storage/v1/object/profile-photos/" + path, "GET",
                          headers=self.headers("c", "image/png"))
        check(code in (400, 401, 403, 404), "unpaired user fetched profile photo")
        code, _ = request(API + "/storage/v1/object/public/profile-photos/" + path,
                          headers={"apikey": self.anon})
        check(code in (400, 401, 403, 404), "private avatar was exposed through public Storage route")
        code, rows = self.rest("a", "user_profiles?user_id=eq." + self.users["a"]["id"],
                               "PATCH", {"avatar_path": None})
        check(code == 200 and len(rows) == 1, "owner could not revoke partner photo visibility")
        code, _ = request(API + "/storage/v1/object/profile-photos/" + path, "GET",
                          headers=self.headers("b", "image/png"))
        check(code in (400, 401, 403, 404), "partner retained photo access after pointer revocation")
        code, result = request(API + "/storage/v1/object/profile-photos", "DELETE",
                               {"prefixes": [path]},
                               {**self.headers("a"), "Content-Type": "application/json"})
        error_type = (result.get("error") or result.get("statusCode")
                      if isinstance(result, dict) else type(result).__name__)
        error_message = (result.get("message") if isinstance(result, dict) else None)
        if isinstance(error_message, str):
            error_message = error_message.replace(path, "[path]")
        check(code in (200, 204),
              "owner could not delete the hidden private photo object (HTTP " + str(code) +
              ", error type " + str(error_type) + ", message " + str(error_message) + ")")

    def run(self):
        self.preflight()
        self.setup()
        self.profile_access()
        self.storage_access()
        print(f"PASS: CP-009A profile and private Storage RLS proof ({ASSERTIONS} assertions).")
        print("Each run leaves its synthetic Auth identities and couple in the local database; repeated runs accumulate fixtures.")
        print("Credentials, JWTs, and invitation tokens were suppressed.")


if __name__ == "__main__":
    try:
        ProfileProof().run()
    except Exception as error:
        print("FAIL:", str(error), file=__import__("sys").stderr)
        raise SystemExit(1)
