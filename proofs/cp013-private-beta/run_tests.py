#!/usr/bin/env python3
"""Run the rollback-only Private Beta V1 proof against local Supabase only."""

from pathlib import Path
import json
import re
import subprocess
import sys
from urllib.parse import urlparse

ROOT = Path(__file__).resolve().parents[2]
SQL = Path(__file__).with_name("security_smoke.sql")
REQUIRED_PROOF_FRAGMENTS = (
    "DO $fixture$",
    "DO $paired_and_restore$",
    "DO $closure_and_allowlist$",
    "SET LOCAL ROLE authenticated;",
    "public.list_my_recoverable_shared_records()",
    "public.restore_my_shared_record('bucket_list_items',v_item)",
    "public.record_my_privacy_removal(",
    "v_first:=public.close_my_couple_space(v_operation);",
    "v_second:=public.close_my_couple_space(v_operation);",
    "RAISE EXCEPTION 'ordinary delete was not listed for recovery'",
    "RAISE EXCEPTION 'ordinary restore did not make the row visible'",
    "RAISE EXCEPTION 'privacy-removed content remained visible'",
    "RAISE EXCEPTION 'privacy-removed content was restorable'",
    "RAISE EXCEPTION 'the other active partner could not read shared data'",
    "RAISE EXCEPTION 'closure was not idempotent'",
    "RAISE EXCEPTION 'partner A retained shared planner read access after closure'",
    "RAISE EXCEPTION 'partner A wrote shared data after closure'",
    "RAISE EXCEPTION 'partner B retained shared planner read access after closure'",
    "RAISE EXCEPTION 'unrelated account or authenticated role reached private beta data'",
)
SNAPSHOT_SQL = """
SELECT pg_catalog.jsonb_build_object(
  'allowlist', COALESCE((
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(slot, user_id) ORDER BY slot
    )
    FROM app_private.private_beta_allowlist
  ), '[]'::jsonb),
  'active_members', COALESCE((
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(couple_id, user_id)
      ORDER BY couple_id, user_id
    )
    FROM public.couple_memberships
    WHERE state = 'active'
      AND user_id IN (SELECT user_id FROM app_private.private_beta_allowlist)
  ), '[]'::jsonb),
  'active_spaces', COALESCE((
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(space.id, space.state, space.closed_at)
      ORDER BY space.id
    )
    FROM public.couple_spaces AS space
    WHERE EXISTS (
      SELECT 1 FROM public.couple_memberships AS membership
      WHERE membership.couple_id = space.id
        AND membership.state = 'active'
        AND membership.user_id IN (
          SELECT user_id FROM app_private.private_beta_allowlist
        )
    )
  ), '[]'::jsonb),
  'unrelated_identities', COALESCE((
    SELECT pg_catalog.jsonb_agg(auth_user.id ORDER BY auth_user.created_at, auth_user.id)
    FROM auth.users AS auth_user
    WHERE NOT EXISTS (
      SELECT 1 FROM app_private.private_beta_allowlist AS allowlist
      WHERE allowlist.user_id = auth_user.id
    )
  ), '[]'::jsonb),
  'proof_markers', COALESCE((
    SELECT pg_catalog.jsonb_agg(
      pg_catalog.jsonb_build_array(id, couple_id, title) ORDER BY id
    )
    FROM public.bucket_list_items
    WHERE title = ANY(ARRAY[
      'CP013 rollback ordinary recovery',
      'CP013 rollback privacy removal',
      'CP013 denied after closure'
    ])
  ), '[]'::jsonb),
  'migration_032_applied', EXISTS (
    SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version = '20261102003200'
  )
)::text;
"""


def run(
    command: list[str], *, timeout: int, input_text: str | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        input=input_text,
        text=True,
        capture_output=True,
        check=False,
        timeout=timeout,
    )


def local_database_target() -> tuple[str, str]:
    config_text = (ROOT / "supabase/config.toml").read_text()
    project_match = re.search(
        r'(?m)^project_id\s*=\s*"([a-z0-9_-]+)"\s*$', config_text
    )
    if project_match is None:
        raise RuntimeError("local Supabase project_id is missing or invalid")
    project_id = project_match.group(1)

    status = run(
        ["supabase", "status", "--output", "json"], timeout=20
    )
    if status.returncode != 0:
        raise RuntimeError("local Supabase status could not be verified")
    try:
        status_data = json.loads(status.stdout)
        api = urlparse(status_data["API_URL"])
    except (KeyError, TypeError, json.JSONDecodeError) as error:
        raise RuntimeError("local Supabase status was not valid JSON") from error
    if api.scheme != "http" or api.hostname not in {"127.0.0.1", "localhost"}:
        raise RuntimeError("Supabase API URL is not a loopback local endpoint")

    context_name = run(["docker", "context", "show"], timeout=10)
    if context_name.returncode != 0 or context_name.stdout.strip() != "orbstack":
        raise RuntimeError("Docker context is not the verified local OrbStack context")
    context = run(
        ["docker", "context", "inspect", "--format", "{{json .Endpoints.docker}}"],
        timeout=10,
    )
    if context.returncode != 0:
        raise RuntimeError("Docker context could not be verified")
    try:
        docker_endpoint = json.loads(context.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("Docker context endpoint was not valid JSON") from error
    if (
        not isinstance(docker_endpoint, dict)
        or not str(docker_endpoint.get("Host", "")).startswith("unix://")
    ):
        raise RuntimeError("Docker context is not a local Unix-socket endpoint")

    container = f"supabase_db_{project_id}"
    inspect = run(
        ["docker", "inspect", "--format", "{{json .Config.Labels}}", container],
        timeout=10,
    )
    running = run(
        ["docker", "inspect", "--format", "{{.State.Running}}", container],
        timeout=10,
    )
    if inspect.returncode != 0 or running.returncode != 0 or running.stdout.strip() != "true":
        raise RuntimeError("expected local Supabase database container is not running")
    try:
        labels = json.loads(inspect.stdout)
    except json.JSONDecodeError as error:
        raise RuntimeError("database container labels were not valid JSON") from error
    if not isinstance(labels, dict):
        raise RuntimeError("database container labels were missing")
    workdir = labels.get("com.supabase.cli.workdir")
    if (
        labels.get("com.supabase.cli.project") != project_id
        or not isinstance(workdir, str)
        or Path(workdir).resolve() != ROOT.resolve()
    ):
        raise RuntimeError("database container does not match this local repository")

    return project_id, container


def psql_command(container: str, *arguments: str) -> list[str]:
    return [
        "docker",
        "exec",
        "-i",
        container,
        "psql",
        "-X",
        "-v",
        "ON_ERROR_STOP=1",
        "-U",
        "postgres",
        "-d",
        "postgres",
        *arguments,
    ]


def snapshot(container: str) -> dict[str, object]:
    # The JSON contains account/couple UUIDs to compare identity exactly. Keep
    # it in process memory only; never print or persist the snapshot.
    result = run(
        psql_command(container, "-A", "-t", "-c", SNAPSHOT_SQL), timeout=15
    )
    if result.returncode != 0:
        raise RuntimeError("read-only local proof pre/post snapshot failed")
    try:
        parsed = json.loads(result.stdout.strip())
    except json.JSONDecodeError as error:
        raise RuntimeError("local proof snapshot was not valid JSON") from error
    if not isinstance(parsed, dict):
        raise RuntimeError("local proof snapshot had an unexpected shape")
    return parsed


def validate_prerequisites(state: dict[str, object]) -> None:
    allowlist = state.get("allowlist")
    active_members = state.get("active_members")
    if (
        not isinstance(allowlist, list)
        or len(allowlist) != 2
        or any(
            not isinstance(row, list)
            or len(row) != 2
            or not isinstance(row[0], int)
            or not isinstance(row[1], str)
            for row in allowlist
        )
    ):
        raise RuntimeError("the existing two-entry beta allowlist is not present")
    if {row[0] for row in allowlist} != {1, 2}:
        raise RuntimeError("the beta allowlist slots are not the expected pair")
    if (
        not isinstance(active_members, list)
        or len(active_members) != 2
        or any(
            not isinstance(row, list)
            or len(row) != 2
            or not isinstance(row[0], str)
            or not isinstance(row[1], str)
            for row in active_members
        )
    ):
        raise RuntimeError("the existing two-member active couple is not present")
    if {member[1] for member in allowlist} != {
        member[1] for member in active_members
    }:
        raise RuntimeError("the allowlisted identities do not match the active pair")
    if len({member[0] for member in active_members}) != 1:
        raise RuntimeError("the two active beta members are not in one couple")
    unrelated = state.get("unrelated_identities")
    if (
        not isinstance(unrelated, list)
        or not unrelated
        or any(not isinstance(user_id, str) for user_id in unrelated)
    ):
        raise RuntimeError("an unrelated test identity is unavailable")
    for key in ("active_spaces", "proof_markers"):
        if not isinstance(state.get(key), list):
            raise RuntimeError(f"the {key} invariant snapshot is malformed")
    active_spaces = state["active_spaces"]
    if (
        len(active_spaces) != 1
        or not isinstance(active_spaces[0], list)
        or len(active_spaces[0]) != 3
        or not isinstance(active_spaces[0][0], str)
        or active_spaces[0][1] != "paired"
        or active_spaces[0][2] is not None
    ):
        raise RuntimeError("the allowlisted couple is not in its expected active state")
    if state.get("migration_032_applied") is not True:
        raise RuntimeError("migration 032 must be applied before this proof runs")


def validate_proof_sql(sql_text: str) -> bool:
    # Strip full-line SQL comments so comments cannot satisfy the assertion
    # sentinels. The checked-in proof must remain one explicit transaction.
    sql_body = re.sub(r"(?m)^\s*--[^\n]*", "", sql_text)
    if (
        not sql_body.lstrip().startswith("BEGIN;")
        or not sql_body.rstrip().endswith("ROLLBACK;")
        or len(re.findall(r"(?im)^\s*ROLLBACK\s*;\s*$", sql_body)) != 1
        or re.search(r"(?im)^\s*COMMIT\b", sql_body)
    ):
        return False
    return all(fragment in sql_body for fragment in REQUIRED_PROOF_FRAGMENTS)


def main() -> int:
    try:
        sql_text = SQL.read_text()
    except OSError:
        print("Private Beta proof SQL file could not be read.", file=sys.stderr)
        return 2
    if not validate_proof_sql(sql_text):
        print(
            "Private Beta proof refused: transaction bounds or required "
            "assertions are missing.",
            file=sys.stderr,
        )
        return 2

    try:
        _, container = local_database_target()
        before = snapshot(container)
        validate_prerequisites(before)
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"Private Beta proof did not start: {error}", file=sys.stderr)
        return 2

    proof: subprocess.CompletedProcess[str] | None = None
    proof_timed_out = False
    try:
        proof = run(psql_command(container), timeout=90, input_text=sql_text)
    except (OSError, subprocess.TimeoutExpired):
        proof_timed_out = True

    try:
        after = snapshot(container)
    except (OSError, subprocess.TimeoutExpired, RuntimeError) as error:
        print(f"Private Beta post-check failed: {error}", file=sys.stderr)
        return 1

    if after != before:
        print(
            "Private Beta proof failed: before/after local invariants differ; "
            "raw database output suppressed.",
            file=sys.stderr,
        )
        return 1
    if proof_timed_out:
        print(
            "Private Beta proof timed out; before/after invariants match, "
            "but completion and explicit ROLLBACK were not confirmed.",
            file=sys.stderr,
        )
        return 1
    assert proof is not None
    if proof.returncode != 0:
        print(
            "Private Beta SQL proof failed; raw SQL output suppressed. "
            "The before/after invariants match.",
            file=sys.stderr,
        )
        return proof.returncode
    if "ROLLBACK" not in proof.stdout.splitlines():
        print(
            "Private Beta proof did not confirm its terminal ROLLBACK; "
            "raw SQL output suppressed.",
            file=sys.stderr,
        )
        return 1

    print("PASS: local-only target and existing proof prerequisites verified")
    print("PASS: transactional RLS, closure, privacy removal, and restore proof")
    print("PASS: explicit ROLLBACK and before/after invariants match")
    print("LIMITATION: JWT claims are simulated; this is not signed-JWT/PostgREST proof")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
