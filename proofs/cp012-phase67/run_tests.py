#!/usr/bin/env python3
"""Local-only JWT/PostgREST security proof for CP-012 Phase 6/7."""
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
ASSERTIONS = 0


def check(value, message):
    global ASSERTIONS
    ASSERTIONS += 1
    if not value:
        raise RuntimeError(message)


def request(url, method="GET", body=None, headers=None):
    parsed = urllib.parse.urlsplit(url)
    check(parsed.scheme == "http" and parsed.hostname == "127.0.0.1" and parsed.port == 54321,
          "refusing non-local API endpoint")
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    try:
        response = HTTP.open(req, timeout=20)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    try:
        payload = json.loads(raw) if raw else None
    except (json.JSONDecodeError, UnicodeDecodeError):
        payload = None
    return response.code, payload


class LocalProof:
    def __init__(self):
        self.users = {}

    def sql(self, statement):
        result = subprocess.run(
            [DOCKER, "exec", "-i", CONTAINER, "psql", "-X", "-qAt", "-w",
             "-U", "supabase_admin", "-d", "postgres", "-v", "ON_ERROR_STOP=1"],
            input=statement, capture_output=True, text=True, env=ENV, timeout=30)
        if result.returncode:
            raise RuntimeError("local database security preflight failed")
        return result.stdout.strip()

    def preflight(self):
        status = subprocess.run(["supabase", "status", "-o", "json"], capture_output=True,
                                text=True, env=ENV, timeout=30)
        check(status.returncode == 0, "local Supabase status unavailable")
        config = json.loads(status.stdout)
        check(config.get("API_URL") == API and "@127.0.0.1:54322/" in config.get("DB_URL", ""),
              "refusing non-local Supabase project")
        self.anon, self.admin = config.get("ANON_KEY"), config.get("SERVICE_ROLE_KEY")
        check(bool(self.anon and self.admin), "local synthetic Auth setup unavailable")
        labels = subprocess.run([DOCKER, "inspect", CONTAINER, "--format", "{{json .Config.Labels}}"],
                                capture_output=True, text=True, env=ENV, timeout=20)
        check(labels.returncode == 0 and json.loads(labels.stdout).get("com.supabase.cli.project") == "twogethera",
              "refusing database outside local Twogethera project")
        check("20261102001800" in self.sql("SELECT version FROM supabase_migrations.schema_migrations"),
              "CP-012 local migration is not recorded")
        for table in ("date_night_ideas", "date_night_votes", "shared_goals", "shared_goal_milestones"):
            flags = self.sql("SELECT relrowsecurity||'|'||relforcerowsecurity FROM pg_class WHERE oid='public." + table + "'::regclass")
            check(flags == "true|true", table + " must use ENABLE and FORCE RLS")
            restrictive = self.sql("SELECT count(*) FROM pg_policies WHERE schemaname='public' AND tablename='" + table + "' AND permissive='RESTRICTIVE' AND policyname LIKE '%boundary'")
            check(int(restrictive) >= 1, table + " must have a restrictive membership boundary")

    def create_user(self, label):
        email = f"cp012-{secrets.token_hex(5)}-{label}@example.invalid"
        # The local Auth project now enforces uppercase/lowercase/digit/symbol
        # rules for every synthetic account used by this proof.
        password = "A" + secrets.token_hex(24) + "a1!"
        code, user = request(API + "/auth/v1/admin/users", "POST",
            {"email": email, "password": password, "email_confirm": True},
            {"apikey": self.anon, "Authorization": "Bearer " + self.admin, "Content-Type": "application/json"})
        check(code == 200 and isinstance(user, dict) and isinstance(user.get("id"), str), "local synthetic identity setup failed")
        code, session = request(API + "/auth/v1/token?grant_type=password", "POST",
            {"email": email, "password": password}, {"apikey": self.anon, "Content-Type": "application/json"})
        check(code == 200 and session.get("access_token"), "real local Auth sign-in failed")
        self.users[label] = {"email": email, "id": user["id"], "jwt": session["access_token"]}

    def headers(self, user=None):
        result = {"apikey": self.anon, "Content-Type": "application/json", "Prefer": "return=representation"}
        if user:
            result["Authorization"] = "Bearer " + self.users[user]["jwt"]
        return result

    def rpc(self, user, name, body):
        return request(API + "/rest/v1/rpc/" + name, "POST", body, self.headers(user))

    def rest(self, user, table, query="", method="GET", body=None):
        return request(API + "/rest/v1/" + table + query, method, body, self.headers(user))

    def pair(self, first, second):
        code, couple = self.rpc(first, "create_couple_space", {"p_operation_id": str(uuid.uuid4())})
        check(code == 200 and isinstance(couple, str), "local couple space creation failed")
        code, invite = self.rpc(first, "issue_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_couple_id": couple,
            "p_expected_epoch": 1, "p_recipient_email": self.users[second]["email"]})
        check(code == 200 and isinstance(invite, dict) and invite.get("token"), "local invite issuance failed")
        code, accepted = self.rpc(second, "accept_partner_invitation", {
            "p_operation_id": str(uuid.uuid4()), "p_token": invite["token"]})
        check(code == 200 and accepted.get("status") == "accepted", "local invitation acceptance failed")
        return couple

    def run(self):
        self.preflight()
        for user in ("a", "b", "c", "d", "e"):
            self.create_user(user)
        couple_ab = self.pair("a", "b")
        couple_cd = self.pair("c", "d")

        anonymous_headers = self.headers()
        code, rows = request(API + "/rest/v1/shared_goals?select=id", headers=anonymous_headers)
        check((code == 200 and rows == []) or code in (401, 403),
              "anonymous role can read shared goals")

        date = "2026-12-12"
        code, ideas = self.rest("a", "date_night_ideas", "", "POST", {
            "couple_id": couple_ab, "title": "Synthetic museum date", "description": "Local test",
            "scheduled_on": date, "estimated_amount_minor": 2500, "estimated_currency_code": "USD",
            "status": "completed"})
        check(code in (200, 201) and len(ideas) == 1,
              "paired partner A cannot create a date night: HTTP " + str(code) + " / " + str(ideas))
        idea = ideas[0]
        check(idea["status"] == "proposed", "client forged initial date-night lifecycle state")
        code, seen = self.rest("b", "date_night_ideas", "?select=id&id=eq." + idea["id"])
        check(code == 200 and len(seen) == 1, "partner B cannot read shared date night")
        code, _ = self.rest("a", "date_night_votes", "", "POST", {
            "couple_id": couple_ab, "idea_id": idea["id"], "user_id": self.users["a"]["id"], "response": "interested"})
        check(code in (200, 201), "partner A cannot record own interest")
        code, _ = self.rest("b", "date_night_votes", "", "POST", {
            "couple_id": couple_ab, "idea_id": idea["id"], "user_id": self.users["b"]["id"], "response": "not_for_me"})
        check(code in (200, 201), "partner B cannot record own interest")
        code, votes = self.rest("a", "date_night_votes", "?select=user_id,response&idea_id=eq." + idea["id"])
        check(code == 200 and len(votes) == 2, "partner A cannot see both shared responses")
        code, partner_vote = self.rest("a", "date_night_votes", "?user_id=eq." + self.users["b"]["id"], "PATCH", {"response": "interested"})
        check(code in (200, 204) and partner_vote == [], "partner A changed partner B's vote")
        code, votes = self.rest("b", "date_night_votes", "?select=user_id,response&idea_id=eq." + idea["id"])
        check(code == 200 and len(votes) == 2 and next(v["response"] for v in votes if v["user_id"] == self.users["b"]["id"]) == "not_for_me",
              "unauthorized vote update changed persisted partner response")
        code, selected = self.rpc("b", "update_date_night_idea", {
            "p_couple_id": couple_ab, "p_idea_id": idea["id"],
            "p_expected_revision": idea["revision"], "p_changes": {"status": "selected"}})
        code, selected_row = self.rest("b", "date_night_ideas", "?select=status&id=eq." + idea["id"])
        check(selected == "updated" and code == 200 and selected_row[0]["status"] == "selected",
              "valid date-night selection transition failed")
        code, _ = self.rest("a", "date_night_votes", "", "POST", {
            "couple_id": couple_ab, "idea_id": idea["id"], "user_id": self.users["a"]["id"], "response": "not_for_me"})
        check(code in (400, 403), "vote accepted after idea was selected")
        code, _ = self.rest("a", "date_night_votes", "", "POST", {
            "couple_id": couple_ab, "idea_id": idea["id"], "user_id": self.users["b"]["id"], "response": "interested"})
        check(code in (400, 403), "partner A forged partner B's vote")

        code, goals = self.rest("a", "shared_goals", "", "POST", {
            "couple_id": couple_ab, "title": "Synthetic shared goal", "description": "Local test", "category": "learning", "status": "completed"})
        check(code in (200, 201) and len(goals) == 1, "paired partner A cannot create a shared goal")
        goal = goals[0]
        check(goal["status"] == "active", "client forged initial shared-goal lifecycle state")
        code, milestones = self.rest("b", "shared_goal_milestones", "", "POST", {
            "couple_id": couple_ab, "goal_id": goal["id"], "title": "First step", "is_completed": True})
        check(code in (200, 201) and len(milestones) == 1 and milestones[0]["completed_at"],
              "partner B cannot add and complete a milestone")
        code, goals_seen = self.rest("b", "shared_goals", "?select=id&id=eq." + goal["id"])
        check(code == 200 and len(goals_seen) == 1, "partner B cannot read shared goal")
        code, completed = self.rpc("a", "update_shared_goal", {
            "p_couple_id": couple_ab, "p_goal_id": goal["id"],
            "p_expected_revision": goal["revision"], "p_changes": {"status": "completed"}})
        code, completed_row = self.rest("a", "shared_goals", "?select=status&id=eq." + goal["id"])
        check(completed == "updated" and code == 200 and completed_row[0]["status"] == "completed",
              "goal could not be completed after its milestones")
        code, _ = self.rpc("b", "update_shared_goal", {
            "p_couple_id": couple_ab, "p_goal_id": goal["id"],
            "p_expected_revision": goal["revision"] + 1, "p_changes": {"status": "active"}})
        check(code in (400, 403), "completed goal could be reopened")
        code, _ = self.rest("b", "shared_goal_milestones", "?id=eq." + milestones[0]["id"], "PATCH", {"is_completed": False})
        check(code in (400, 403), "milestone was reopened after goal completion")

        for user, other_couple in (("a", couple_cd), ("c", couple_ab), ("e", couple_ab)):
            code, rows = self.rest(user, "date_night_ideas", "?select=id&couple_id=eq." + other_couple)
            check(code == 200 and rows == [], user + " can read another/unpaired couple's ideas")
            code, rows = self.rest(user, "shared_goals", "?select=id&couple_id=eq." + other_couple)
            check(code == 200 and rows == [], user + " can read another/unpaired couple's goals")
        code, hidden = self.rest("c", "date_night_ideas", "?id=eq." + idea["id"], "PATCH", {"title": "Forged edit"})
        check(code in (401, 403), "unrelated partner has direct date-night UPDATE privilege")
        code, still_original = self.rest("b", "date_night_ideas", "?select=title&id=eq." + idea["id"])
        check(code == 200 and still_original[0]["title"] == "Synthetic museum date",
              "cross-couple update changed the persisted date-night record")
        code, hidden = self.rest("c", "shared_goals", "?id=eq." + goal["id"], "PATCH", {"description": "Forged edit"})
        check(code in (401, 403), "unrelated partner has direct shared-goal UPDATE privilege")
        code, still_original = self.rest("b", "shared_goals", "?select=description&id=eq." + goal["id"])
        check(code == 200 and still_original[0]["description"] == "Local test",
              "cross-couple update changed the persisted goal")
        code, _ = self.rest("e", "date_night_ideas", "", "POST", {"couple_id": couple_ab, "title": "Forged scope"})
        check(code in (400, 403), "unpaired user inserted into shared couple scope")
        code, _ = self.rest("c", "shared_goal_milestones", "", "POST", {
            "couple_id": couple_ab, "goal_id": goal["id"], "title": "Forged milestone"})
        check(code in (400, 403), "unrelated couple inserted milestone into another couple's goal")
        code, _ = self.rest("a", "shared_goals", "?id=eq." + goal["id"], "DELETE")
        check(code in (401, 403), "shared goal has a hard-delete API grant")
        code, _ = self.rest("a", "date_night_ideas", "?id=eq." + idea["id"], "DELETE")
        check(code in (401, 403), "date-night record has a hard-delete API grant")
        print(f"CP-012 local JWT/PostgREST proof: {ASSERTIONS} assertions passed")


if __name__ == "__main__":
    LocalProof().run()
