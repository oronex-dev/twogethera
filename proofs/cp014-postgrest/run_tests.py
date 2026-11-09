#!/usr/bin/env python3
"""Local signed-JWT/PostgREST proof for the existing Private Beta couple.

This test intentionally creates one tagged Bucket List QA row, exercises the
authorized soft-delete/restore RPCs, and leaves the row active afterward.
Running it requires an explicit command-line opt-in and interactive consent.
Passwords are read with getpass; API keys and JWTs stay in process memory.
"""

from __future__ import annotations

import argparse
import base64
import getpass
import importlib.util
import json
import os
from pathlib import Path
import re
import secrets
import stat
import subprocess
import sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import ProxyHandler, Request, build_opener


ROOT = Path(__file__).resolve().parents[2]
API = "http://127.0.0.1:54321"
PROJECT_ID = "twogethera"
DB_CONTAINER = "supabase_db_twogethera"
DEFAULT_LOCAL_CONFIG = Path("/private/tmp/twogethera-local-auth.json")
CP013_RUNNER = ROOT / "proofs/cp013-private-beta/run_tests.py"


class ProofFailure(RuntimeError):
    pass


def check(condition: bool, message: str) -> None:
    if not condition:
        raise ProofFailure(message)


def command(args: list[str], timeout: int = 15) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=ROOT,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def local_auth_flag_enabled(value: object) -> bool:
    return value is True or (
        isinstance(value, str) and value.strip().lower() == "true"
    )


def local_api_key(config_path: Path) -> str:
    """Read only the local anon key; never call `supabase status` (which emits
    service-role and secret keys along with status fields).
    """
    key = os.environ.get("LOCAL_SUPABASE_ANON_KEY", "")
    api_url = os.environ.get("LOCAL_SUPABASE_URL", "")
    config: dict[str, object] = {}
    if not key or not api_url or "LOCAL_AUTH_ENABLED" not in os.environ:
        try:
            if stat.S_IMODE(config_path.stat().st_mode) & 0o077:
                raise ProofFailure("local define file permissions are not private")
            config = json.loads(config_path.read_text())
        except (OSError, json.JSONDecodeError):
            raise ProofFailure("private local Auth define file is unavailable") from None
    flag = os.environ.get("LOCAL_AUTH_ENABLED", config.get("LOCAL_AUTH_ENABLED"))
    check(local_auth_flag_enabled(flag), "local Auth is not enabled")
    key = key or config.get("LOCAL_SUPABASE_ANON_KEY", "")
    api_url = api_url or config.get("LOCAL_SUPABASE_URL", "")
    app_env = os.environ.get("APP_ENV", config.get("APP_ENV"))
    check(app_env not in {"staging", "production"}, "non-local app environment refused")

    check(api_url == API, "only the exact loopback Supabase API is permitted")
    check(isinstance(key, str) and bool(key), "local anon/publishable key is unavailable")
    if key.startswith("sb_publishable_"):
        return key
    if key.startswith("sb_secret_"):
        raise ProofFailure("secret API keys are not accepted")
    try:
        pieces = key.split(".")
        check(len(pieces) == 3, "API key is not a publishable/anon key")
        payload = pieces[1] + "=" * (-len(pieces[1]) % 4)
        claims = json.loads(base64.urlsafe_b64decode(payload.encode()))
    except (ValueError, json.JSONDecodeError, IndexError):
        raise ProofFailure("API key format is not accepted") from None
    check(claims.get("role") == "anon", "service or non-anonymous API key refused")
    return key


def verify_local_target() -> None:
    config = (ROOT / "supabase/config.toml").read_text()
    check(
        re.search(r'(?m)^project_id\s*=\s*"twogethera"\s*$', config) is not None,
        "repository is not the expected local Twogethera project",
    )
    context = command(["docker", "context", "show"])
    check(context.returncode == 0 and context.stdout.strip() == "orbstack", "OrbStack context required")
    endpoint = command(["docker", "context", "inspect", "--format", "{{json .Endpoints.docker}}"])
    check(endpoint.returncode == 0, "local Docker endpoint could not be verified")
    try:
        docker_endpoint = json.loads(endpoint.stdout)
    except json.JSONDecodeError:
        raise ProofFailure("Docker endpoint metadata is invalid") from None
    check(str(docker_endpoint.get("Host", "")).startswith("unix://"), "non-local Docker endpoint refused")

    labels = command(["docker", "inspect", "--format", "{{json .Config.Labels}}", DB_CONTAINER])
    state = command(["docker", "inspect", "--format", "{{json .State}}", DB_CONTAINER])
    check(labels.returncode == 0 and state.returncode == 0, "expected local database container unavailable")
    try:
        container_labels = json.loads(labels.stdout)
        container_state = json.loads(state.stdout)
    except json.JSONDecodeError:
        raise ProofFailure("database container metadata is invalid") from None
    check(
        container_labels.get("com.supabase.cli.project") == PROJECT_ID
        and Path(container_labels.get("com.supabase.cli.workdir", "/nonexistent")).resolve() == ROOT.resolve(),
        "database container does not match this repository",
    )
    check(container_state.get("Status") == "running", "local database container is not running")


def cp013_snapshotter():
    """Reuse CP-013's exact in-memory invariant snapshot; never run its SQL proof."""
    spec = importlib.util.spec_from_file_location("cp013_snapshot", CP013_RUNNER)
    check(spec is not None and spec.loader is not None, "CP-013 invariant helper unavailable")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    snapshot = module.snapshot(DB_CONTAINER)
    module.validate_prerequisites(snapshot)
    check(snapshot.get("migration_032_applied") is True, "migration 032 is not recorded locally")
    return module, snapshot


class LocalAPI:
    def __init__(self, anon_key: str):
        self.anon_key = anon_key
        self.http = build_opener(ProxyHandler({}))

    def request(self, path: str, *, method: str = "GET", body=None, token: str | None = None):
        url = API + path
        parsed = urlsplit(url)
        check(parsed.scheme == "http" and parsed.hostname == "127.0.0.1" and parsed.port == 54321,
              "request refused: non-local API target")
        headers = {"apikey": self.anon_key, "Accept": "application/json"}
        if token:
            headers["Authorization"] = "Bearer " + token
        data = None
        if body is not None:
            headers["Content-Type"] = "application/json"
            data = json.dumps(body, separators=(",", ":")).encode()
        if method in {"POST", "PATCH", "DELETE"}:
            headers["Prefer"] = "return=representation"
        req = Request(url, data=data, headers=headers, method=method)
        try:
            response = self.http.open(req, timeout=20)
        except HTTPError as error:
            response = error
        except URLError:
            raise ProofFailure("local Auth/PostgREST request failed to connect") from None
        raw = response.read()
        try:
            payload = json.loads(raw) if raw else None
        except (json.JSONDecodeError, UnicodeDecodeError):
            payload = None
        return response.code, payload


def signin(api: LocalAPI, label: str) -> dict[str, str]:
    email = getpass.getpass(f"{label} email (hidden): ")
    password = getpass.getpass(f"{label} password (hidden): ")
    try:
        status, session = api.request(
            "/auth/v1/token?grant_type=password",
            method="POST",
            body={"email": email, "password": password},
        )
    finally:
        password = ""
        email = ""
    check(status == 200 and isinstance(session, dict), f"{label} local Auth sign-in failed")
    token = session.get("access_token")
    user = session.get("user")
    check(isinstance(token, str) and isinstance(user, dict) and isinstance(user.get("id"), str),
          f"{label} Auth session response was invalid")
    return {"token": token, "user_id": user["id"]}


def rpc(api: LocalAPI, token: str, name: str, body: dict | None = None):
    return api.request("/rest/v1/rpc/" + name, method="POST", body=body or {}, token=token)


def read_item(api: LocalAPI, token: str | None, item_id: str):
    query = "/rest/v1/bucket_list_items?select=id,couple_id,revision&id=eq." + item_id
    return api.request(query, token=token)


def run_proof(api: LocalAPI) -> None:
    a = signin(api, "Partner A")
    b = signin(api, "Partner B")
    outsider = signin(api, "Unrelated account")
    qa_title = "CP014 signed-JWT QA " + secrets.token_hex(6)
    fixture_id: str | None = None
    couple_id: str | None = None
    soft_deleted = False
    restored = False
    try:
        code_a, context_a = rpc(api, a["token"], "account_context")
        code_b, context_b = rpc(api, b["token"], "account_context")
        check(code_a == 200 and isinstance(context_a, dict), "Partner A account context denied")
        check(code_b == 200 and isinstance(context_b, dict), "Partner B account context denied")
        check(context_a.get("user_id") == a["user_id"] and context_b.get("user_id") == b["user_id"],
              "Auth token identity did not match account context")
        spaces_a = context_a.get("spaces")
        spaces_b = context_b.get("spaces")
        check(isinstance(spaces_a, list) and len(spaces_a) == 1 and spaces_a[0].get("state") == "paired",
              "Partner A is not in exactly one paired space")
        check(isinstance(spaces_b, list) and len(spaces_b) == 1 and spaces_b[0].get("state") == "paired",
              "Partner B is not in exactly one paired space")
        couple_id = spaces_a[0].get("space_id")
        check(isinstance(couple_id, str) and couple_id == spaces_b[0].get("space_id"),
              "partners do not resolve to the same couple")

        outsider_context_status, _ = rpc(api, outsider["token"], "account_context")
        check(outsider_context_status in {401, 403}, "unrelated account reached private account context")

        insert_status, inserted = api.request(
            "/rest/v1/bucket_list_items",
            method="POST",
            body={"couple_id": couple_id, "title": qa_title},
            token=a["token"],
        )
        check(insert_status in {200, 201} and isinstance(inserted, list) and len(inserted) == 1,
              "tagged local QA Bucket List fixture could not be created")
        row = inserted[0]
        fixture_id = row.get("id")
        revision = row.get("revision")
        check(isinstance(fixture_id, str) and isinstance(revision, int), "QA fixture response was invalid")
        check(row.get("couple_id") == couple_id, "QA fixture was not scoped to the active couple")

        for label, token in (("Partner A", a["token"]), ("Partner B", b["token"])):
            status, rows = read_item(api, token, fixture_id)
            check(status == 200 and isinstance(rows, list) and len(rows) == 1,
                  f"{label} could not read the shared couple fixture")
            check(rows[0].get("couple_id") == couple_id, f"{label} received out-of-couple data")

        status, rows = read_item(api, outsider["token"], fixture_id)
        check((status == 200 and rows == []) or status in {401, 403},
              "unrelated account could read the shared QA record")
        status, rows = read_item(api, None, fixture_id)
        check((status == 200 and rows == []) or status in {401, 403},
              "anonymous request could read the shared QA record")

        delete_status, delete_error = api.request(
            "/rest/v1/bucket_list_items?id=eq." + fixture_id,
            method="DELETE",
            token=a["token"],
        )
        if delete_status not in {401, 403}:
            # If direct deletion unexpectedly succeeded, restore the test row
            # through the authorized RPC before stopping.
            if delete_status in {200, 204}:
                restore_code, restored_result = rpc(api, a["token"], "restore_my_shared_record",
                                                     {"p_table": "bucket_list_items", "p_record_id": fixture_id})
                restored = restore_code == 200 and restored_result is True
            raise ProofFailure("direct PostgREST DELETE was not denied")
        if isinstance(delete_error, dict) and delete_error.get("code") not in {None, "42501"}:
            raise ProofFailure("direct DELETE failed for an unexpected authorization reason")
        status, rows = read_item(api, a["token"], fixture_id)
        check(status == 200 and isinstance(rows, list) and len(rows) == 1,
              "record changed after denied direct DELETE")

        rpc_status, deleted = rpc(api, a["token"], "delete_bucket_list_item", {
            "p_couple_id": couple_id,
            "p_item_id": fixture_id,
            "p_expected_revision": revision,
        })
        check(rpc_status == 200 and deleted is True, "signed-JWT deletion RPC did not succeed")
        soft_deleted = True
        status, recoverable = rpc(api, a["token"], "list_my_recoverable_shared_records")
        check(status == 200 and isinstance(recoverable, list) and any(
            x.get("target_table") == "bucket_list_items" and x.get("target_id") == fixture_id
            for x in recoverable
        ), "deleted QA record was not recoverable")
        status, restore_result = rpc(api, a["token"], "restore_my_shared_record", {
            "p_table": "bucket_list_items", "p_record_id": fixture_id,
        })
        check(status == 200 and restore_result is True, "signed-JWT recovery RPC did not succeed")
        restored = True
        status, rows = read_item(api, a["token"], fixture_id)
        check(status == 200 and isinstance(rows, list) and len(rows) == 1,
              "restored QA record was not visible")
        print("PASS: signed local Auth tokens, partner access, outsider/anonymous isolation.")
        print("PASS: direct DELETE denied; revision-checked delete RPC and recovery succeeded.")
        print("NOTE: one tagged QA row remains active for safe local cleanup after separate approval.")
    finally:
        # Best-effort recovery only; never hard-delete or alter existing records.
        if fixture_id and soft_deleted and not restored:
            rpc(api, a["token"], "restore_my_shared_record", {
                "p_table": "bucket_list_items", "p_record_id": fixture_id,
            })
        a.clear()
        b.clear()
        outsider.clear()


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--authorize-persistent-qa-record",
        action="store_true",
        help="authorize creating and restoring one persistent local QA row",
    )
    parser.add_argument(
        "--local-config",
        type=Path,
        default=DEFAULT_LOCAL_CONFIG,
        help="private local Flutter define file (key values are never printed)",
    )
    args = parser.parse_args()
    if not args.authorize_persistent_qa_record:
        print("BLOCKED: this proof creates one persistent local QA row; explicit opt-in is required.", file=sys.stderr)
        return 2
    try:
        verify_local_target()
        anon = local_api_key(args.local_config)
        before_module, before = cp013_snapshotter()
        confirmation = input(
            "This signs into the three existing accounts and leaves one restored CP014 QA row. Type CP014 to continue: "
        )
        check(confirmation == "CP014", "operator did not confirm the persistent local QA record")
        api = LocalAPI(anon)
        run_proof(api)
        after = before_module.snapshot(DB_CONTAINER)
        check(after == before, "CP-013 account/couple/unrelated-identity/proof-marker invariants changed")
        print("PASS: exact CP-013 before/after account and couple invariants match.")
        return 0
    except (ProofFailure, OSError, subprocess.TimeoutExpired) as error:
        # Errors from HTTP/API bodies and credentials are never printed.
        message = str(error) if isinstance(error, ProofFailure) else "local prerequisite or request failed"
        print("FAIL:", message, file=sys.stderr)
        print("A tagged CP014 QA row may remain; inspect it locally before any cleanup.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
