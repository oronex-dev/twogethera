#!/usr/bin/env python3
"""Exercise Phase 4/5 RLS and private Storage through local Supabase JWTs.

The only privileged requests create synthetic local Auth accounts and perform
the final synthetic membership-revocation setup. Feature assertions use each
user's real local Auth access token through PostgREST and Storage.
"""
import base64
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


def request(url, method="GET", body=None, headers=None, raw=None):
    parsed = urllib.parse.urlsplit(url)
    check(parsed.scheme == "http" and parsed.hostname == "127.0.0.1"
          and parsed.port == 54321, "refusing non-local Supabase endpoint")
    data = raw if raw is not None else (json.dumps(body).encode() if body is not None else None)
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        response = HTTP.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    content = response.read()
    try:
        value = json.loads(content) if content else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        value = content
    return response.code, value


class LocalProof:
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
            raise RuntimeError("local synthetic fixture setup failed: " + result.stderr[-500:])
        return result.stdout.strip()

    def preflight(self):
        status = subprocess.run(["supabase", "status", "-o", "json"],
                                capture_output=True, text=True, env=ENV, timeout=30)
        check(status.returncode == 0, "local Supabase status unavailable")
        config = json.loads(status.stdout)
        check(config.get("API_URL") == API and
              "@127.0.0.1:54322/" in config.get("DB_URL", ""),
              "refusing unexpected Supabase endpoints")
        self.anon, self.admin = config.get("ANON_KEY"), config.get("SERVICE_ROLE_KEY")
        check(bool(self.anon and self.admin), "local synthetic Auth setup unavailable")
        labels = subprocess.run(
            [DOCKER, "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"],
            capture_output=True, text=True, env=ENV, timeout=20,
        )
        check(labels.returncode == 0 and
              json.loads(labels.stdout).get("com.supabase.cli.project") == "twogethera",
              "refusing database outside the local Twogethera project")
        applied = set(self.sql("SELECT version FROM supabase_migrations.schema_migrations" ).splitlines())
        check({"20261102000900", "20261102001000"}.issubset(applied),
              "Phase 4/5 local migrations are not applied")
        check(self.sql("SELECT relrowsecurity||'|'||relforcerowsecurity FROM pg_class WHERE oid='public.couple_expenses'::regclass") == "true|true",
              "expense RLS must be enabled and forced")
        check(self.sql("SELECT relrowsecurity||'|'||relforcerowsecurity FROM pg_class WHERE oid='public.couple_memories'::regclass") == "true|true",
              "memory RLS must be enabled and forced")
        check(self.sql("SELECT public FROM storage.buckets WHERE id IN ('couple-receipts','couple-memories') ORDER BY id") == "f\nf",
              "feature media buckets must remain private")

    def create_user(self, label):
        email = f"cp011-{secrets.token_hex(5)}-{label}@example.invalid"
        password = "A" + secrets.token_hex(24) + "a1!"
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
              "real local Auth sign-in failed")
        self.users[label] = {"id": user["id"], "email": email, "jwt": session["access_token"]}

    def headers(self, label=None, storage=False):
        headers = {"apikey": self.anon, "Content-Type": "application/json",
                   "Prefer": "return=representation"}
        if label:
            headers["Authorization"] = "Bearer " + self.users[label]["jwt"]
        return headers

    def rest(self, label, table, path="", method="GET", body=None, upsert=False):
        headers = self.headers(label)
        if upsert:
            headers["Prefer"] += ", resolution=merge-duplicates"
        return request(API + "/rest/v1/" + table + path, method, body, headers)

    def rpc(self, label, function, body):
        return request(API + "/rest/v1/rpc/" + function, "POST", body, self.headers(label))

    def pair(self):
        for label in ("a", "b", "c"):
            self.create_user(label)
        code, self.space = self.rpc("a", "create_couple_space", {
            "p_operation_id": str(uuid.uuid4())})
        check(code == 200 and isinstance(self.space, str), "local couple creation failed")
        code, invitation = self.rpc("a", "issue_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_couple_id": self.space,
            "p_expected_epoch": 1, "p_recipient_email": self.users["b"]["email"],
        })
        check(code == 200 and isinstance(invitation, dict) and invitation.get("token"),
              "verified local partner invitation failed")
        code, accepted = self.rpc("b", "accept_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_token": invitation["token"],
        })
        check(code == 200 and accepted.get("status") == "accepted", "local invitation acceptance failed")
        rows = self.rest("a", "couple_memberships",
                         f"?select=user_id,seat&couple_id=eq.{self.space}&state=eq.active&order=seat")
        check(rows[0] == 200 and len(rows[1]) == 2, "pair fixture did not create exactly two active members")
        self.members = {int(row["seat"]): row["user_id"] for row in rows[1]}

    def create_records(self):
        month = __import__("datetime").date.today().replace(day=1).isoformat()
        code, budgets = self.rest("a", "couple_budgets", "", "POST", {
            "couple_id": self.space, "month_start": month,
            "currency_code": "USD", "currency_exponent": 2, "limit_minor": 150000,
        })
        check(code in (200, 201) and isinstance(budgets, list) and len(budgets) == 1,
              f"paired user could not create monthly budget (HTTP {code}: {budgets})")
        self.budget = budgets[0]
        category_path = "?on_conflict=budget_id,category_key"
        category = {"couple_id": self.space, "budget_id": self.budget["id"],
                    "category_key": "food", "limit_minor": 50000}
        code, _ = self.rest("a", "budget_category_limits", category_path, "POST", category, upsert=True)
        check(code in (200, 201), "paired user could not create category limit")
        category["limit_minor"] = 60000
        code, _ = self.rest("b", "budget_category_limits", category_path, "POST", category, upsert=True)
        check(code in (200, 201), "partner category-limit upsert failed")
        code, rows = self.rest("a", "budget_category_limits",
                               f"?select=couple_id,budget_id,category_key,limit_minor&budget_id=eq.{self.budget['id']}")
        check(code == 200 and rows == [{"couple_id": self.space,
                                        "budget_id": self.budget["id"],
                                        "category_key": "food", "limit_minor": 60000}],
              "category-limit upsert did not update the shared limit")
        code, _ = self.rest("a", "budget_category_limits",
                            f"?budget_id=eq.{self.budget['id']}", "PATCH",
                            {"couple_id": str(uuid.uuid4())})
        check(code in (400, 403), "client moved a category limit to another couple")
        day = __import__("datetime").date.today().isoformat()
        code, expenses = self.rest("a", "couple_expenses", "", "POST", {
            "couple_id": self.space, "budget_id": self.budget["id"],
            "title": "Synthetic grocery run", "amount_minor": 1001,
            "currency_code": "USD", "currency_exponent": 2,
            "occurred_on": day, "category_key": "food", "paid_by_user": self.members[1],
            "split_mode": "equal", "split_a_user_id": self.members[1],
            "split_a_minor": 500, "split_b_user_id": self.members[2],
            "split_b_minor": 501,
        })
        check(code in (200, 201) and isinstance(expenses, list) and len(expenses) == 1,
              f"server rejected a valid exact-minor-unit expense (HTTP {code}: {expenses})")
        self.expense = expenses[0]
        # The deferred aggregate and row guards reject malformed splits even
        # when the caller holds a genuine paired-member JWT.
        invalid = dict(expenses[0])
        invalid.pop("id", None)
        invalid.pop("created_by", None)
        invalid.pop("updated_by", None)
        invalid.pop("created_at", None)
        invalid.pop("updated_at", None)
        invalid.pop("revision", None)
        invalid["title"] = "Invalid split fixture"
        invalid["split_a_minor"], invalid["split_b_minor"] = 400, 601
        code, _ = self.rest("a", "couple_expenses", "", "POST", invalid)
        check(code in (400, 403, 409), "database accepted an invalid equal split")
        code, memories = self.rest("a", "couple_memories", "", "POST", {
            "couple_id": self.space, "title": "Synthetic local memory",
            "caption": "Fixture only", "personal_notes": "Shared note fixture",
            "memory_on": day, "category_key": "everyday", "tags": ["test"],
            "is_favorite": False,
        })
        check(code in (200, 201) and len(memories) == 1, "paired user could not create memory")
        self.memory = memories[0]
        code, receipts = self.rest("a", "expense_receipts", "", "POST", {
            "couple_id": self.space, "expense_id": self.expense["id"],
            "content_type": "image/png", "byte_size": 68,
        })
        check(code in (200, 201) and len(receipts) == 1,
              "paired user could not reserve private receipt attachment")
        self.receipt = receipts[0]
        code, current_expense = self.rest("a", "couple_expenses",
                                          f"?select=receipt_count&id=eq.{self.expense['id']}")
        check(code == 200 and current_expense[0]["receipt_count"] == 1,
              "server receipt counter did not track attachment metadata")
        code, _ = self.rest("a", "couple_expenses",
                            f"?id=eq.{self.expense['id']}", "PATCH", {"receipt_count": 5})
        check(code in (400, 403), "client directly modified server-maintained receipt count")
        reserved = []
        for _ in range(4):
            code, rows = self.rest("a", "expense_receipts", "", "POST", {
                "couple_id": self.space, "expense_id": self.expense["id"],
                "content_type": "image/png", "byte_size": 1,
            })
            check(code in (200, 201) and len(rows) == 1,
                  "valid receipt slot could not be reserved")
            reserved.append(rows[0]["id"])
        code, _ = self.rest("a", "expense_receipts", "", "POST", {
            "couple_id": self.space, "expense_id": self.expense["id"],
            "content_type": "image/png", "byte_size": 1,
        })
        check(code in (400, 403), "server accepted more than five receipt reservations")
        for receipt_id in reserved:
            self.rest("a", "expense_receipts", f"?id=eq.{receipt_id}", "DELETE")
        png = base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pWQAAAAASUVORK5CYII=")
        code, attachments = self.rest("a", "memory_attachments", "", "POST", {
            "couple_id": self.space, "memory_id": self.memory["id"],
            "content_type": "image/png", "byte_size": len(png),
        })
        check(code in (200, 201) and len(attachments) == 1,
              "paired user could not reserve private memory attachment")
        self.attachment = attachments[0]
        for index in range(9):
            code, rows = self.rest("a", "memory_attachments", "", "POST", {
                "couple_id": self.space, "memory_id": self.memory["id"],
                "content_type": "image/png", "byte_size": index + 1,
            })
            check(code in (200, 201) and len(rows) == 1,
                  "valid memory photo reservation was rejected")
        code, _ = self.rest("a", "memory_attachments", "", "POST", {
            "couple_id": self.space, "memory_id": self.memory["id"],
            "content_type": "image/png", "byte_size": 1,
        })
        check(code in (400, 403), "server accepted more than ten photos for one memory")
        extra = self.rest("a", "memory_attachments", "?memory_id=eq." + self.memory["id"], "GET")[1]
        for row in extra:
            if row["id"] != self.attachment["id"]:
                self.rpc("a", "delete_couple_memory_attachment", {
                    "p_couple_id": self.space, "p_attachment_id": row["id"],
                })
        path = urllib.parse.quote(self.attachment["object_path"], safe="/")
        upload = request(API + "/storage/v1/object/couple-memories/" + path,
                         "POST", headers={"apikey": self.anon,
                         "Authorization": "Bearer " + self.users["a"]["jwt"],
                         "Content-Type": "image/png", "x-upsert": "false"}, raw=png)
        check(upload[0] in (200, 201), "paired member could not upload private image object")
        receipt_path = urllib.parse.quote(self.receipt["object_path"], safe="/")
        upload = request(API + "/storage/v1/object/couple-receipts/" + receipt_path,
                         "POST", headers={"apikey": self.anon,
                         "Authorization": "Bearer " + self.users["a"]["jwt"],
                         "Content-Type": "image/png", "x-upsert": "false"}, raw=png)
        check(upload[0] in (200, 201), "paired member could not upload private receipt object")
        code, _ = self.rest("a", "memory_attachments",
                            f"?id=eq.{self.attachment['id']}", "DELETE")
        check(code in (400, 403), "client bypassed private storage cleanup through metadata deletion")
        code, result = self.rpc("a", "delete_couple_memory_attachment", {
            "p_couple_id": self.space, "p_attachment_id": self.attachment["id"],
        })
        check(code in (400, 403) or result is not True,
              "attachment cleanup RPC deleted metadata while object remained")

    def verify_member_access(self):
        for label in ("a", "b"):
            code, rows = self.rest(label, "couple_expenses",
                                   f"?select=id,amount_minor&couple_id=eq.{self.space}")
            check(code == 200 and len(rows) == 1 and rows[0]["id"] == self.expense["id"],
                  f"paired {label.upper()} could not read shared expense")
            code, rows = self.rest(label, "couple_memories",
                                   f"?select=id,title&couple_id=eq.{self.space}")
            check(code == 200 and len(rows) == 1 and rows[0]["id"] == self.memory["id"],
                  f"paired {label.upper()} could not read shared memory")
            path = urllib.parse.quote(self.attachment["object_path"], safe="/")
            code, data = request(API + "/storage/v1/object/couple-memories/" + path,
                                 headers={"apikey": self.anon,
                                          "Authorization": "Bearer " + self.users[label]["jwt"]})
            check(code == 200 and isinstance(data, bytes) and len(data) > 0,
                  f"paired {label.upper()} could not download private image")
            receipt_path = urllib.parse.quote(self.receipt["object_path"], safe="/")
            code, data = request(API + "/storage/v1/object/couple-receipts/" + receipt_path,
                                 headers={"apikey": self.anon,
                                          "Authorization": "Bearer " + self.users[label]["jwt"]})
            check(code == 200 and isinstance(data, bytes) and len(data) > 0,
                  f"paired {label.upper()} could not download private receipt")

    def verify_denials(self):
        code, rows = self.rest("c", "couple_expenses", f"?couple_id=eq.{self.space}")
        check(code == 200 and rows == [], "unpaired account read couple expense")
        code, rows = self.rest("c", "couple_memories", f"?couple_id=eq.{self.space}")
        check(code == 200 and rows == [], "unpaired account read couple memory")
        code, rows = self.rest(
            "c", "couple_expenses",
            f"?id=eq.{self.expense['id']}&couple_id=eq.{self.space}",
            "PATCH", {"title": "Unpaired overwrite"})
        check(code == 200 and rows == [], "unpaired account modified an expense")
        code, rows = self.rest(
            "c", "couple_memories",
            f"?id=eq.{self.memory['id']}&couple_id=eq.{self.space}",
            "PATCH", {"title": "Unpaired overwrite"})
        check(code == 200 and rows == [], "unpaired account modified a memory")
        code, rows = self.rest(
            "c", "couple_expenses",
            f"?id=eq.{self.expense['id']}&couple_id=eq.{self.space}", "DELETE")
        check(code in (401, 403, 404) or (code in (200, 204) and rows in ([], None)),
              f"unpaired account delete request was not filtered (HTTP {code}: {rows})")
        code, rows = self.rest(
            "c", "couple_memories",
            f"?id=eq.{self.memory['id']}&couple_id=eq.{self.space}", "DELETE")
        check(code in (401, 403, 404) or (code in (200, 204) and rows in ([], None)),
              "unpaired account delete request was not filtered for memory")
        for table, record in (("couple_expenses", {
            "couple_id": self.space, "budget_id": self.budget["id"],
            "title": "Unauthorized", "amount_minor": 1, "currency_code": "USD",
            "currency_exponent": 2, "occurred_on": __import__("datetime").date.today().isoformat(),
            "category_key": "other", "paid_by_user": self.members[1],
            "split_mode": "equal", "split_a_user_id": self.members[1],
            "split_a_minor": 0, "split_b_user_id": self.members[2], "split_b_minor": 1,
        }), ("couple_memories", {
            "couple_id": self.space, "title": "Unauthorized memory",
            "memory_on": __import__("datetime").date.today().isoformat(),
        })):
            code, _ = self.rest("c", table, "", "POST", record)
            check(code in (401, 403), f"unpaired account inserted into {table}")
        code, rows = self.rest(None, "couple_memories", f"?couple_id=eq.{self.space}")
        check(code in (401, 403), "anonymous request accessed shared memories")
        path = urllib.parse.quote(self.attachment["object_path"], safe="/")
        code, _ = request(API + "/storage/v1/object/couple-memories/" + path,
                          headers={"apikey": self.anon,
                                   "Authorization": "Bearer " + self.users["c"]["jwt"]})
        check(code in (400, 403, 404), "unpaired account downloaded private photo")
        forged_path = urllib.parse.quote(f"{self.space}/{uuid.uuid4()}/{uuid.uuid4()}.blob", safe="/")
        code, _ = request(API + "/storage/v1/object/couple-memories/" + forged_path,
                          "POST", headers={"apikey": self.anon,
                                           "Authorization": "Bearer " + self.users["c"]["jwt"],
                                           "Content-Type": "image/png"},
                          raw=base64.b64decode("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+/pWQAAAAASUVORK5CYII="))
        check(code in (400, 403, 404), "unpaired account uploaded a private photo")
        receipt_path = urllib.parse.quote(self.receipt["object_path"], safe="/")
        code, _ = request(API + "/storage/v1/object/couple-receipts/" + receipt_path,
                          headers={"apikey": self.anon,
                                   "Authorization": "Bearer " + self.users["c"]["jwt"]})
        check(code in (400, 403, 404), "unpaired account downloaded private receipt")
        # Attempt to forge a foreign scope as a valid paired member; RLS plus
        # the shared-membership trigger must reject the insert.
        forged = {"couple_id": str(uuid.uuid4()), "title": "Forged scope",
                  "memory_on": __import__("datetime").date.today().isoformat()}
        code, _ = self.rest("a", "couple_memories", "", "POST", forged)
        check(code in (401, 403, 409), "client supplied a foreign couple scope")
        code, rows = self.rest("a", "couple_expenses",
                               f"?select=title&id=eq.{self.expense['id']}")
        check(code == 200 and rows == [{"title": "Synthetic grocery run"}],
              "unauthorized attempts changed the shared expense")
        code, rows = self.rest("a", "couple_memories",
                               f"?select=title&id=eq.{self.memory['id']}")
        check(code == 200 and rows == [{"title": "Synthetic local memory"}],
              "unauthorized attempts changed the shared memory")

    def verify_revocation(self):
        self.sql("BEGIN; "
                 f"UPDATE public.couple_memberships SET state='revoked', revoked_at=statement_timestamp(), revision=revision+1 "
                 f"WHERE couple_id='{self.space}'::uuid; "
                 f"UPDATE public.couple_spaces SET state='archived' WHERE id='{self.space}'::uuid; COMMIT;")
        for label in ("a", "b"):
            code, rows = self.rest(label, "couple_memories", f"?couple_id=eq.{self.space}")
            check(code == 200 and rows == [], f"revoked member {label.upper()} retained memory read access")
            code, rows = self.rest(label, "couple_expenses", f"?couple_id=eq.{self.space}")
            check(code == 200 and rows == [], f"revoked member {label.upper()} retained expense read access")
            path = urllib.parse.quote(self.attachment["object_path"], safe="/")
            code, _ = request(API + "/storage/v1/object/couple-memories/" + path,
                              headers={"apikey": self.anon,
                                       "Authorization": "Bearer " + self.users[label]["jwt"]})
            check(code in (400, 403, 404), f"revoked member {label.upper()} retained private photo access")
            receipt_path = urllib.parse.quote(self.receipt["object_path"], safe="/")
            code, _ = request(API + "/storage/v1/object/couple-receipts/" + receipt_path,
                              headers={"apikey": self.anon,
                                       "Authorization": "Bearer " + self.users[label]["jwt"]})
            check(code in (400, 403, 404), f"revoked member {label.upper()} retained receipt access")

    def run(self):
        print("Checking local-only migration and RLS preflight...", flush=True)
        self.preflight()
        print("Creating synthetic Auth identities and pairing two members...", flush=True)
        self.pair()
        print("Creating budget, expense, category limit, memory, and private objects...", flush=True)
        self.create_records()
        print("Verifying paired-member reads and private Storage...", flush=True)
        self.verify_member_access()
        print("Verifying unpaired, anonymous, forged-scope, and write denials...", flush=True)
        self.verify_denials()
        print("Verifying archived-space access revocation...", flush=True)
        self.verify_revocation()
        print(f"PASS: local Phase 4/5 RLS and private Storage proof ({CHECKS} assertions).")
        print("Only real local Auth JWTs were used for feature requests; no token or key was printed.")
        print("Synthetic fixture accounts, couple, records, and one image remain in local Supabase.")


if __name__ == "__main__":
    try:
        LocalProof().run()
    except Exception as error:
        print("FAIL:", str(error), file=__import__("sys").stderr)
        raise SystemExit(1)
