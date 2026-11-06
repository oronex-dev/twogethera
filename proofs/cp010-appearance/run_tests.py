#!/usr/bin/env python3
"""Prove account-scoped appearance isolation through local Supabase JWTs."""
import json
import os
import secrets
import shutil
import subprocess
import urllib.error
import urllib.parse
import urllib.request
import uuid

API = "http://127.0.0.1:54321"
CONTAINER = "supabase_db_twogethera"
DOCKER = shutil.which("docker") or "/Applications/OrbStack.app/Contents/MacOS/xbin/docker"
ENV = dict(os.environ, PATH=str(DOCKER.rsplit("/", 1)[0]) + ":" + os.environ.get("PATH", ""))
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
CHECKS = 0


def check(value, message):
    global CHECKS
    CHECKS += 1
    if not value:
        raise RuntimeError(message)


def command(args, timeout=30):
    return subprocess.run(args, capture_output=True, text=True, env=ENV, timeout=timeout)


def request(url, method="GET", body=None, headers=None):
    parsed = urllib.parse.urlsplit(url)
    check(parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
          and parsed.port == 54321, "refusing non-local Supabase endpoint")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        response = HTTP.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    try:
        value = json.loads(raw) if raw else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        value = None
    return response.code, value


class AppearanceIsolation:
    def __init__(self):
        self.users = {}
        self.space = None

    def sql(self, statement):
        result = subprocess.run(
            [DOCKER, "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-w",
             "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
            input=statement, capture_output=True, text=True, env=ENV, timeout=30,
        )
        if result.returncode:
            raise RuntimeError("local database preflight failed")
        return result.stdout.strip()

    def preflight(self):
        status = command(["supabase", "status", "-o", "json"])
        check(status.returncode == 0, "local Supabase status unavailable")
        config = json.loads(status.stdout)
        check(config.get("API_URL") == API and
              "@127.0.0.1:54322/" in config.get("DB_URL", ""),
              "refusing unexpected Supabase endpoints")
        self.anon = config.get("ANON_KEY")
        self.admin = config.get("SERVICE_ROLE_KEY")
        check(bool(self.anon and self.admin), "local synthetic Auth setup credentials unavailable")
        labels = command([DOCKER, "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"])
        check(labels.returncode == 0 and
              json.loads(labels.stdout).get("com.supabase.cli.project") == "twogethera",
              "refusing database outside the local Twogethera project")
        versions = set(self.sql("SELECT version FROM supabase_migrations.schema_migrations").splitlines())
        check("20261102000800" in versions, "local appearance migration is not applied")
        flags = self.sql("SELECT relrowsecurity||'|'||relforcerowsecurity "
                         "FROM pg_class WHERE oid='public.user_dashboard_preferences'::regclass")
        check(flags == "true|true", "account preference table must retain forced RLS")

    def create_user(self, label):
        email = f"cp010-{secrets.token_hex(5)}-{label}@example.invalid"
        password = secrets.token_urlsafe(28)
        code, user = request(API + "/auth/v1/admin/users", "POST", {
            "email": email, "password": password, "email_confirm": True,
        }, {"apikey": self.anon, "Authorization": "Bearer " + self.admin,
            "Content-Type": "application/json"})
        check(code == 200 and isinstance(user, dict) and isinstance(user.get("id"), str),
              "synthetic local Auth account creation failed")
        code, session = request(API + "/auth/v1/token?grant_type=password", "POST", {
            "email": email, "password": password,
        }, {"apikey": self.anon, "Content-Type": "application/json"})
        check(code == 200 and isinstance(session, dict) and session.get("access_token"),
              "genuine local Auth sign-in failed")
        self.users[label] = {"id": user["id"], "email": email,
                             "jwt": session["access_token"]}

    def headers(self, label=None):
        headers = {"apikey": self.anon, "Content-Type": "application/json",
                   "Prefer": "return=representation, resolution=merge-duplicates"}
        if label:
            headers["Authorization"] = "Bearer " + self.users[label]["jwt"]
        return headers

    def rpc(self, label, function, body):
        return request(API + "/rest/v1/rpc/" + function, "POST", body,
                       self.headers(label))

    def rest(self, label, path, method="GET", body=None):
        return request(API + "/rest/v1/user_dashboard_preferences" + path,
                       method, body, self.headers(label))

    def pair(self):
        for label in ("a", "b", "c"):
            self.create_user(label)
        code, self.space = self.rpc("a", "create_couple_space", {
            "p_operation_id": str(uuid.uuid4())})
        check(code == 200 and isinstance(self.space, str),
              "local test couple creation failed")
        code, invite = self.rpc("a", "issue_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_couple_id": self.space,
            "p_expected_epoch": 1, "p_recipient_email": self.users["b"]["email"],
        })
        check(code == 200 and isinstance(invite, dict) and invite.get("token"),
              "local verified-email invitation failed")
        code, result = self.rpc("b", "accept_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_token": invite["token"],
        })
        check(code == 200 and result.get("status") == "accepted",
              "local invitation acceptance failed")

    @staticmethod
    def settings(theme, mode, color=None):
        return {
            "user_id": None,
            "module_order": ["bucket_list", "important_dates", "plans"],
            "visible_modules": ["bucket_list", "important_dates", "plans"],
            "appearance_theme": theme,
            "appearance_mode": mode,
            "appearance_custom_hex": color,
        }

    def save(self, label, theme, mode, color=None):
        data = self.settings(theme, mode, color)
        data["user_id"] = self.users[label]["id"]
        return self.rest(label, "?on_conflict=user_id", "POST", data)

    def update(self, label, owner_id, theme, mode, color=None):
        return self.rest(
            label,
            f"?user_id=eq.{owner_id}",
            "PATCH",
            {
                "appearance_theme": theme,
                "appearance_mode": mode,
                "appearance_custom_hex": color,
            },
        )

    def verify(self):
        a_id, b_id = self.users["a"]["id"], self.users["b"]["id"]
        code, _ = self.save("a", "emerald", "light", None)
        check(code in (200, 201), "partner A preferences did not save")
        code, _ = self.save("b", "midnight_slate", "dark", "#6578AB")
        check(code in (200, 201), "partner B preferences did not save")

        code, rows = self.update("a", a_id, "champagne", "dark", "#C59B41")
        check(code == 200 and isinstance(rows, list) and len(rows) == 1,
              "partner A could not update their own preferences")
        code, rows = self.update("b", b_id, "ocean_blue", "light", None)
        check(code == 200 and isinstance(rows, list) and len(rows) == 1,
              "partner B could not update their own preferences")

        code, rows = self.rest("a", f"?select=user_id,appearance_theme,appearance_mode,appearance_custom_hex&user_id=eq.{a_id}")
        check(code == 200 and rows == [{
            "user_id": a_id, "appearance_theme": "champagne",
            "appearance_mode": "dark", "appearance_custom_hex": "#C59B41",
        }], "partner A did not retrieve their own settings")
        code, rows = self.rest("b", f"?select=user_id,appearance_theme,appearance_mode,appearance_custom_hex&user_id=eq.{b_id}")
        check(code == 200 and rows == [{
            "user_id": b_id, "appearance_theme": "ocean_blue",
            "appearance_mode": "light", "appearance_custom_hex": None,
        }], "partner B did not retrieve their own independent settings")
        code, rows = self.rest("a", f"?select=user_id&user_id=eq.{b_id}")
        check(code == 200 and rows == [], "partner A read partner B appearance row")
        code, rows = self.rest("b", f"?select=user_id&user_id=eq.{a_id}")
        check(code == 200 and rows == [], "partner B read partner A appearance row")

        code, rows = self.update("b", a_id, "amethyst", "light", None)
        check(code == 200 and rows == [],
              "partner B received or changed partner A's preference row")
        code, rows = self.update("a", b_id, "rose_gold", "dark", None)
        check(code == 200 and rows == [],
              "partner A received or changed partner B's preference row")

        foreign = self.settings("champagne", "dark")
        foreign["user_id"] = a_id
        code, _ = self.rest("c", "?on_conflict=user_id", "POST", foreign)
        check(code in (401, 403), "unpaired user wrote partner appearance row")
        for owner_id, owner in ((a_id, "a"), (b_id, "b")):
            code, rows = self.rest(
                "c", f"?select=user_id&user_id=eq.{owner_id}")
            check(code == 200 and rows == [],
                  f"third account read partner {owner.upper()} appearance row")
            code, rows = self.update("c", owner_id, "amethyst", "dark", None)
            check(code == 200 and rows == [],
                  f"third account changed partner {owner.upper()} appearance row")
        code, rows = self.rest("a", f"?select=appearance_theme,appearance_mode&user_id=eq.{a_id}")
        check(code == 200 and rows == [{
            "appearance_theme": "champagne", "appearance_mode": "dark",
        }], "unauthorized mutation changed partner A's stored preferences")
        code, rows = self.rest("b", f"?select=appearance_theme,appearance_mode&user_id=eq.{b_id}")
        check(code == 200 and rows == [{
            "appearance_theme": "ocean_blue", "appearance_mode": "light",
        }], "unauthorized mutation changed partner B's stored preferences")

    def run(self):
        self.preflight()
        self.pair()
        self.verify()
        print(f"PASS: per-account appearance RLS isolation ({CHECKS} assertions).")
        print("Test Auth accounts, JWTs, invitation token, and setup keys were not printed.")
        print("One synthetic couple and three synthetic accounts remain in local Supabase.")


if __name__ == "__main__":
    try:
        AppearanceIsolation().run()
    except Exception as error:
        print("FAIL:", str(error), file=__import__("sys").stderr)
        raise SystemExit(1)
