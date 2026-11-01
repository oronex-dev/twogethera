#!/usr/bin/env python3
"""CP-008 private dashboard preference RLS proof against local Supabase."""

import json
import secrets
import subprocess
import urllib.error
import urllib.parse
import urllib.request

API = "http://127.0.0.1:54321"
HTTP = urllib.request.build_opener(urllib.request.ProxyHandler({}))
ASSERTIONS = 0


def check(ok, message):
    global ASSERTIONS
    ASSERTIONS += 1
    if not ok:
        raise RuntimeError(message)


def request(path, method="GET", body=None, token=None, api_key=None, prefer=None):
    data = json.dumps(body).encode() if body is not None else None
    headers = {
        "Content-Type": "application/json",
        "apikey": api_key,
        "Authorization": f"Bearer {token or api_key}",
    }
    if prefer:
        headers["Prefer"] = prefer
    req = urllib.request.Request(API + path, data=data, headers=headers, method=method)
    try:
        response = HTTP.open(req, timeout=12)
    except urllib.error.HTTPError as error:
        response = error
    raw = response.read()
    try:
        decoded = json.loads(raw) if raw else None
    except (ValueError, UnicodeDecodeError):
        decoded = None
    return response.code, decoded


def main():
    status = subprocess.run(
        ["supabase", "status", "-o", "json"], capture_output=True, text=True, timeout=20
    )
    check(status.returncode == 0, "local Supabase status unavailable")
    config = json.loads(status.stdout)
    check(config.get("API_URL") == API, "refusing a nonlocal Supabase endpoint")
    anon, admin = config.get("ANON_KEY"), config.get("SERVICE_ROLE_KEY")
    check(bool(anon and admin), "local test keys unavailable")
    run = secrets.token_hex(6)
    created = []

    def admin_request(path, method="POST", body=None):
        return request(path, method, body, token=admin, api_key=anon)

    def make_user(label):
        email = f"cp008-{run}-{label}@example.invalid"
        password = secrets.token_urlsafe(32)
        code, user = admin_request(
            "/auth/v1/admin/users",
            body={"email": email, "password": password, "email_confirm": True},
        )
        check(code in (200, 201) and isinstance(user, dict), "synthetic user setup failed")
        user_id = user.get("id")
        check(isinstance(user_id, str), "synthetic identity missing")
        created.append(user_id)
        code, session = request(
            "/auth/v1/token?grant_type=password",
            "POST",
            body={"email": email, "password": password},
            api_key=anon,
        )
        check(code == 200 and isinstance(session, dict) and session.get("access_token"),
              f"real local sign-in failed (HTTP {code}: {session.get('msg', session.get('message', 'no token')) if isinstance(session, dict) else 'invalid response'})")
        return user_id, session["access_token"]

    user_a = user_b = None
    try:
        user_a = make_user("a")
        user_b = make_user("b")
        a_id, a_token = user_a
        _, b_token = user_b
        row = {
            "user_id": a_id,
            "module_order": ["plans", "bucket_list", "important_dates"],
            "visible_modules": ["plans", "important_dates"],
        }
        code, saved = request(
            "/rest/v1/user_dashboard_preferences?on_conflict=user_id",
            "POST", row, token=a_token, api_key=anon,
            prefer="resolution=merge-duplicates,return=representation",
        )
        check(code in (200, 201) and isinstance(saved, list) and len(saved) == 1,
              f"authenticated owner could not save preferences (HTTP {code}: {saved if isinstance(saved, dict) else 'unexpected response'})")

        query = urllib.parse.urlencode({"user_id": f"eq.{a_id}", "select": "*"})
        code, own = request(f"/rest/v1/user_dashboard_preferences?{query}",
                            token=a_token, api_key=anon)
        check(code == 200 and len(own) == 1 and own[0]["module_order"] == row["module_order"],
              "preferences did not persist for owner")

        code, other = request(f"/rest/v1/user_dashboard_preferences?{query}",
                              token=b_token, api_key=anon)
        check(code == 200 and other == [], "another account read private preferences")

        changed = {"visible_modules": ["bucket_list"]}
        code, _ = request(f"/rest/v1/user_dashboard_preferences?{query}", "PATCH", changed,
                          token=b_token, api_key=anon, prefer="return=representation")
        check(code in (200, 204), "cross-account update did not complete as RLS-filtered no-op")
        code, after = request(f"/rest/v1/user_dashboard_preferences?{query}",
                              token=a_token, api_key=anon)
        check(code == 200 and after[0]["visible_modules"] == row["visible_modules"],
              "cross-account update changed owner data")

        forged = {"user_id": a_id, "module_order": row["module_order"],
                  "visible_modules": ["bucket_list"]}
        code, _ = request("/rest/v1/user_dashboard_preferences", "POST", forged,
                          token=b_token, api_key=anon)
        check(code >= 400, "another account inserted preferences for owner")

        invalid = {"user_id": a_id, "module_order": ["plans", "unknown", "bucket_list"],
                   "visible_modules": []}
        code, _ = request("/rest/v1/user_dashboard_preferences", "POST", invalid,
                          token=a_token, api_key=anon,
                          prefer="resolution=merge-duplicates,return=representation")
        check(code >= 400, "database accepted an unknown dashboard module")

        code, anon_rows = request(f"/rest/v1/user_dashboard_preferences?{query}", api_key=anon)
        check(code >= 400 or anon_rows == [], "anonymous request read private preferences")

        code, _ = request(f"/rest/v1/user_dashboard_preferences?{query}", "PATCH",
                          {"user_id": user_b[0]}, token=a_token, api_key=anon)
        check(code >= 400, "authenticated client changed the preference owner")
        print("PASS: authenticated owner saves and reloads server-backed preferences")
        print("PASS: cross-account read/write, anonymous access, and invalid module data denied")
        print(f"ASSERTIONS: {ASSERTIONS} completed checks.")
    finally:
        for user_id in created:
            admin_request(f"/auth/v1/admin/users/{user_id}", method="DELETE")


if __name__ == "__main__":
    main()
