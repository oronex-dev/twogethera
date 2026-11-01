#!/usr/bin/env python3
"""CP-007 planner authorization proof against local Supabase Auth/PostgREST."""
import concurrent.futures
import json
import os
from pathlib import Path
import secrets
import shutil
import subprocess
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
HTTP_CLIENT = urllib.request.build_opener(urllib.request.ProxyHandler({}))
ASSERTIONS = 0


def require(condition, message):
    global ASSERTIONS
    ASSERTIONS += 1
    if not condition:
        raise RuntimeError(message)


def run(command, stdin=None, timeout=25):
    return subprocess.run(command, input=stdin, capture_output=True, text=True,
                          env=ENV, timeout=timeout)


def sql(statement, must_succeed=True):
    result = run([DOCKER, "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-w",
                  "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
                 "SET log_statement='none'; SET log_min_error_statement='panic';\n" + statement)
    if must_succeed and result.returncode:
        raise RuntimeError("local database inspection or fixture cleanup failed")
    return result.stdout.strip() if must_succeed else result


def http(url, method="GET", body=None, headers=None, timeout=15):
    parsed = urllib.parse.urlsplit(url)
    require(parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
            and parsed.port == 54321, "test runner refuses nonlocal API endpoints")
    data = json.dumps(body).encode() if body is not None else None
    request = urllib.request.Request(url, data=data,
        headers={"Content-Type": "application/json", **(headers or {})}, method=method)
    try:
        response = HTTP_CLIENT.open(request, timeout=timeout)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    try:
        decoded = json.loads(raw) if raw else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        decoded = None
    return response.code, decoded


def quote(value):
    return "'" + str(value).replace("'", "''") + "'"


class PlannerSecuritySuite:
    tables = ("bucket_list_items", "important_dates", "plans", "plan_tasks")

    def __init__(self):
        self.anon = self.admin = None
        self.users = {}
        self.spaces = {}
        self.invitation_tokens = []
        self.run_id = secrets.token_hex(6)
        self.log_since = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())

    def preflight(self):
        status = run(["supabase", "status", "-o", "json"])
        require(status.returncode == 0, "local Supabase is unavailable")
        values = json.loads(status.stdout)
        require(values.get("API_URL") == API and "@127.0.0.1:54322/" in values.get("DB_URL", ""),
                "refusing unexpected Supabase endpoint")
        self.anon, self.admin = values.get("ANON_KEY"), values.get("SERVICE_ROLE_KEY")
        require(bool(self.anon and self.admin), "local synthetic Auth setup keys unavailable")
        labels = run([DOCKER, "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"])
        require(labels.returncode == 0 and
                json.loads(labels.stdout).get("com.supabase.cli.project") == "twogethera",
                "refusing database outside the local Twogethera project")
        ledger = set(sql("SELECT version FROM supabase_migrations.schema_migrations").splitlines())
        require({"20261102000100", "20261102000200", "20261102000300"}.issubset(ledger),
                "CP-006A/B or CP-007 migration is not applied")
        health, _ = http(API + "/auth/v1/health")
        require(health == 200, "local Supabase Auth health check failed")
        for table in self.tables:
            flags = sql("SELECT c.relrowsecurity||'|'||c.relforcerowsecurity FROM pg_class c "
                        "WHERE c.oid='public." + table + "'::regclass")
            require(flags == "true|true", table + " does not enforce and force RLS")
            grants = sql("SELECT has_table_privilege('anon','public." + table + "','SELECT')||'|'||"
                         "has_table_privilege('authenticated','public." + table + "','SELECT')||'|'||"
                         "has_table_privilege('authenticated','public." + table + "','DELETE')")
            require(grants == "false|true|false", table + " has unexpected API role grants")
        print("PASS: local project, migration ledger, Auth health, forced RLS and least-privilege grants verified", flush=True)

    def create_user(self, key):
        email = f"cp007-{self.run_id}-{key}@example.invalid"
        password = secrets.token_urlsafe(32)
        status, user = http(API + "/auth/v1/admin/users", "POST",
            {"email": email, "password": password, "email_confirm": True},
            {"apikey": self.anon, "Authorization": "Bearer " + self.admin})
        require(status == 200 and isinstance(user, dict) and isinstance(user.get("id"), str),
                "synthetic local Auth identity creation failed")
        status, session = http(API + "/auth/v1/token?grant_type=password", "POST",
            {"email": email, "password": password}, {"apikey": self.anon})
        require(status == 200 and isinstance(session, dict) and session.get("access_token"),
                "synthetic local Auth sign-in failed")
        self.users[key] = {"id": user["id"], "email": email, "jwt": session["access_token"]}

    def identities(self):
        for key in "abcdef":
            self.create_user(key)
        print("PASS: six synthetic verified accounts authenticated with genuine local JWTs", flush=True)

    def headers(self, key=None):
        value = {"apikey": self.anon, "Accept-Profile": "public", "Content-Profile": "public",
                 "Prefer": "return=representation"}
        if key is not None:
            value["Authorization"] = "Bearer " + self.users[key]["jwt"]
        return value

    def rest(self, key, path, method="GET", body=None):
        return http(API + "/rest/v1/" + path, method, body, self.headers(key))

    def rpc(self, key, function, params):
        return http(API + "/rest/v1/rpc/" + function, "POST", params, self.headers(key))

    def create_space(self, key):
        code, value = self.rpc(key, "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        require(code == 200 and isinstance(value, str), "authenticated couple draft creation failed")
        return value

    def pair(self, inviter, recipient, space):
        code, invitation = self.rpc(inviter, "issue_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_couple_id": space,
            "p_expected_epoch": 1, "p_recipient_email": self.users[recipient]["email"],
        })
        require(code == 200 and invitation.get("status") == "created" and invitation.get("token"),
                "local authenticated invitation issue failed")
        self.invitation_tokens.append(invitation["token"])
        code, accepted = self.rpc(recipient, "accept_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_token": invitation["token"],
        })
        require(code == 200 and accepted.get("status") == "accepted", "local authenticated pairing failed")

    def setup(self):
        self.identities()
        self.spaces["ab"] = self.create_space("a")
        self.pair("a", "b", self.spaces["ab"])
        self.spaces["cd"] = self.create_space("c")
        self.pair("c", "d", self.spaces["cd"])
        self.spaces["e-draft"] = self.create_space("e")
        print("PASS: two independent paired couples, one draft owner and one unpaired account ready", flush=True)

    @staticmethod
    def rows_ok(code, rows):
        return code == 200 and isinstance(rows, list)

    def table_read(self, actor, table, couple_id):
        return self.rest(actor, table + "?select=id,couple_id&couple_id=eq." + couple_id)

    def access_matrix(self):
        for table in self.tables:
            for actor, scope in (("a", "ab"), ("b", "ab"), ("c", "cd"), ("d", "cd")):
                code, rows = self.table_read(actor, table, self.spaces[scope])
                require(self.rows_ok(code, rows) and rows == [],
                        "newly paired account unexpectedly has data or cannot read its own scope")
            for actor in ("a", "b"):
                code, rows = self.table_read(actor, table, self.spaces["cd"])
                require(self.rows_ok(code, rows) and not rows, "cross-couple SELECT leaked " + table)
            for actor in ("e", "f"):
                code, rows = self.table_read(actor, table, self.spaces["ab"])
                require(self.rows_ok(code, rows) and not rows, "unpaired/draft SELECT leaked " + table)
            code, rows = self.table_read(None, table, self.spaces["ab"])
            require(code in (200, 401, 403) and (not isinstance(rows, list) or not rows),
                    "anonymous request read planner rows")
        print("PASS: RLS denies planner reads for unpaired, draft, anonymous and unrelated-couple identities", flush=True)

    def insert(self, actor, table, value):
        return self.rest(actor, table + "?select=*", "POST", value)

    def create_shared_rows(self):
        space = self.spaces["ab"]
        code, bucket = self.insert("a", "bucket_list_items", {
            "couple_id": space, "title": "Walk by the sea", "description": "Sunset together",
            "category_key": "travel", "is_completed": False,
        })
        require(code == 201 and isinstance(bucket, list) and len(bucket) == 1, "bucket list insert failed")
        self.bucket = bucket[0]
        code, date = self.insert("b", "important_dates", {
            "couple_id": space, "kind": "anniversary", "title": "Our anniversary",
            "date_value": "2024-02-29", "notes": "A special day", "recurrence": "annual",
            "leap_day_policy": "skip",
        })
        require(code == 201 and isinstance(date, list) and len(date) == 1, "important date insert failed")
        self.date = date[0]
        code, plan = self.insert("a", "plans", {
            "couple_id": space, "title": "Museum day", "description": "Take our time",
            "starts_at": "2027-06-12T09:30:00+00:00", "ends_at": "2027-06-12T12:00:00+00:00",
            "location": "City museum",
        })
        require(code == 201 and isinstance(plan, list) and len(plan) == 1, "plan insert failed")
        self.plan = plan[0]
        code, task = self.insert("b", "plan_tasks", {
            "couple_id": space, "plan_id": self.plan["id"], "title": "Book the tickets", "sort_order": 0,
        })
        require(code == 201 and isinstance(task, list) and len(task) == 1, "task insert failed")
        self.task = task[0]
        for table in self.tables:
            code, rows = self.table_read("b", table, space)
            require(self.rows_ok(code, rows) and len(rows) == 1, "second partner did not see shared " + table)
            code, rows = self.table_read("c", table, space)
            require(self.rows_ok(code, rows) and not rows, "unrelated couple read shared " + table)
        require(self.bucket["revision"] == 1 and self.date["revision"] == 1 and
                self.plan["revision"] == 1 and self.task["revision"] == 1,
                "server did not initialize row revisions")
        print("PASS: both partners share bucket items, recurring dates, plans and checklist tasks", flush=True)

    def mutate_and_isolate(self):
        space = self.spaces["ab"]
        code, updated = self.rest("b", "bucket_list_items?id=eq." + self.bucket["id"] +
            "&couple_id=eq." + space + "&revision=eq.1", "PATCH", {"is_completed": True})
        require(code == 200 and isinstance(updated, list) and len(updated) == 1 and
                updated[0]["revision"] == 2 and updated[0]["completed_at"] is not None,
                "shared completion, server timestamp or revision failed")
        self.bucket = updated[0]
        code, stale = self.rest("a", "bucket_list_items?id=eq." + self.bucket["id"] +
            "&couple_id=eq." + space + "&revision=eq.1", "PATCH", {"title": "Stale overwrite"})
        require(code == 200 and stale == [], "stale revision was not rejected by the checked update")
        code, rows = self.rest("b", "bucket_list_items?id=eq." + self.bucket["id"] + "&select=title,revision,is_completed")
        require(self.rows_ok(code, rows) and rows == [{"title": "Walk by the sea", "revision": 2, "is_completed": True}],
                "stale update changed the committed record")

        code, date_rows = self.rest("a", "important_dates?id=eq." + self.date["id"] +
            "&couple_id=eq." + space + "&revision=eq.1", "PATCH", {"notes": "Updated together"})
        require(code == 200 and isinstance(date_rows, list) and len(date_rows) == 1 and
                date_rows[0]["revision"] == 2 and date_rows[0]["notes"] == "Updated together",
                "shared important-date update failed")
        self.date = date_rows[0]
        code, plan_rows = self.rest("b", "plans?id=eq." + self.plan["id"] +
            "&couple_id=eq." + space + "&revision=eq.1", "PATCH", {"location": "New gallery"})
        require(code == 200 and isinstance(plan_rows, list) and len(plan_rows) == 1 and
                plan_rows[0]["revision"] == 2 and plan_rows[0]["location"] == "New gallery",
                "shared plan update failed")
        self.plan = plan_rows[0]
        code, task_rows = self.rest("a", "plan_tasks?id=eq." + self.task["id"] +
            "&couple_id=eq." + space + "&revision=eq.1", "PATCH", {"is_completed": True})
        require(code == 200 and isinstance(task_rows, list) and len(task_rows) == 1 and
                task_rows[0]["revision"] == 2 and task_rows[0]["completed_at"] is not None,
                "shared checklist task completion failed")
        self.task = task_rows[0]

        wrong, body = self.insert("f", "bucket_list_items", {
            "couple_id": space, "title": "Cross-scope insert", "category_key": "other",
        })
        require(wrong in (401, 403), "unpaired client insert was not rejected (HTTP " + str(wrong) + ")")
        wrong, body = self.rest("c", "plans?id=eq." + self.plan["id"], "PATCH", {"title": "Cross-scope edit"})
        require(wrong == 200 and body == [], "other couple modified a planner plan")
        wrong, body = self.rest("c", "plans?id=eq." + self.plan["id"], "DELETE")
        require(wrong in (401, 403), "other couple direct DELETE was not rejected (HTTP " + str(wrong) + ")")
        direct, _ = self.rest("a", "bucket_list_items?id=eq." + self.bucket["id"], "DELETE")
        require(direct in (401, 403), "authenticated clients received direct DELETE privilege")
        forbidden_column, _ = self.rest("a", "plans?id=eq." + self.plan["id"], "PATCH", {"couple_id": self.spaces["cd"]})
        require(forbidden_column in (401, 403), "client could change planner scope identity")

        code, other = self.insert("c", "bucket_list_items", {
            "couple_id": self.spaces["cd"], "title": "Other couple idea", "category_key": "home",
        })
        require(code == 201 and isinstance(other, list) and len(other) == 1, "second couple cannot create its own row")
        self.other_bucket = other[0]
        code, visible = self.rest("a", "bucket_list_items?id=eq." + self.other_bucket["id"] + "&select=id")
        require(code == 200 and visible == [], "other couple row became visible by guessed ID")
        code, changed = self.rest("a", "bucket_list_items?id=eq." + self.other_bucket["id"], "PATCH", {"title": "Wrong scope"})
        require(code == 200 and changed == [], "cross-couple update returned an affected row")
        require(sql("SELECT title FROM public.bucket_list_items WHERE id=" + quote(self.other_bucket["id"]) + "::uuid") == "Other couple idea",
                "cross-couple update modified stored data")
        print("PASS: paired writes share correctly; unpaired/cross-couple mutations, direct deletes, scope edits and stale revisions are denied", flush=True)

    def delete_commands(self):
        # Scope-checked commands are the only client hard-delete path.
        checks = [
            ("delete_bucket_list_item", self.bucket["id"], self.bucket["revision"], "p_item_id"),
            ("delete_important_date", self.date["id"], self.date["revision"], "p_date_id"),
            ("delete_plan_task", self.task["id"], self.task["revision"], "p_task_id"),
        ]
        for function, row_id, revision, id_arg in checks:
            code, result = self.rpc("b", function, {
                "p_couple_id": self.spaces["ab"], id_arg: row_id,
                "p_expected_revision": revision,
            })
            error_code = result.get("code") if isinstance(result, dict) else None
            require(code == 200 and result is True,
                    "authorized scoped delete command failed: " + function +
                    " (HTTP " + str(code) + ", error code " + str(error_code) + ")")
        code, result = self.rpc("f", "delete_plan", {
            "p_couple_id": self.spaces["ab"], "p_plan_id": self.plan["id"],
            "p_expected_revision": self.plan["revision"],
        })
        require(code == 200 and result is False, "unpaired account deleted a planner aggregate")
        code, result = self.rpc("a", "delete_plan", {
            "p_couple_id": self.spaces["ab"], "p_plan_id": self.plan["id"],
            "p_expected_revision": self.plan["revision"],
        })
        require(code == 200 and result is True, "authorized plan aggregate delete failed")
        require(sql("SELECT count(*) FROM public.plans WHERE id=" + quote(self.plan["id"]) + "::uuid") == "0" and
                sql("SELECT count(*) FROM public.plan_tasks WHERE plan_id=" + quote(self.plan["id"]) + "::uuid") == "0",
                "plan delete did not remove parent and checklist tasks in order")
        print("PASS: scope/revision checked delete RPCs work; unpaired denial and ordered plan/task deletion verified", flush=True)

    def log_scan(self):
        containers = ["supabase_rest_twogethera", "supabase_kong_twogethera", "supabase_auth_twogethera", CONTAINER]
        for container in containers:
            result = run([DOCKER, "logs", "--since", self.log_since, container])
            require(result.returncode == 0, "local service log inspection failed")
            content = result.stdout + result.stderr
            require(not any(token in content for token in self.invitation_tokens),
                    "synthetic invitation token appeared in a local service log")
        print("PASS: raw synthetic invitation tokens were absent from inspected local logs", flush=True)

    def cleanup(self):
        if self.spaces:
            for table in self.tables:
                sql("DELETE FROM public." + table + " WHERE couple_id IN (" + ",".join(
                    quote(space) + "::uuid" for space in self.spaces.values()) + ")", False)

    def run(self):
        self.preflight()
        self.setup()
        try:
            self.access_matrix()
            self.create_shared_rows()
            self.mutate_and_isolate()
            self.delete_commands()
            self.log_scan()
        finally:
            self.cleanup()
        print("RESULT: all CP-007 local planner security groups passed; JWTs and setup keys were suppressed.", flush=True)
        print(f"ASSERTIONS: {ASSERTIONS} completed checks.", flush=True)


if __name__ == "__main__":
    try:
        PlannerSecuritySuite().run()
    except Exception as error:
        print("FAIL:", str(error), file=__import__('sys').stderr, flush=True)
        raise SystemExit(1)
