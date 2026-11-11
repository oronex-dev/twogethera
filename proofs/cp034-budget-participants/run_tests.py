#!/usr/bin/env python3
"""Run CP-034 participant-guard checks in a rollback-only local transaction."""

from __future__ import annotations

import json
import re
import secrets
import subprocess
import sys
from pathlib import Path
from typing import NoReturn


ROOT = Path(__file__).resolve().parents[2]
CONTAINER = "supabase_db_twogethera"
PROJECT_LABEL = "twogethera"
MIGRATION = ROOT / "supabase/migrations/20261102003400_budget_participant_order.sql"
PROOF = ROOT / "proofs/cp034-budget-participants/rollback_proof.sql"


def run(command: list[str], *, input_text: str | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=ROOT,
        input=input_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )


def fail(message: str) -> NoReturn:
    print(f"CP-034 BLOCKED: {message}", file=sys.stderr)
    raise SystemExit(1)


def psql(sql: str) -> subprocess.CompletedProcess[str]:
    return run(
        [
            "docker", "exec", "-i", CONTAINER,
            "psql", "-U", "postgres", "-d", "postgres",
            "-X", "-q", "-A", "-t", "-v", "ON_ERROR_STOP=1",
        ],
        input_text=sql,
    )


def read_invariants() -> dict[str, object]:
    query = r"""
SELECT jsonb_build_object(
  'allowlist_count', (SELECT count(*) FROM app_private.private_beta_allowlist),
  'allowlist_fingerprint', md5(coalesce((
    SELECT string_agg(slot::text || ':' || user_id::text, ',' ORDER BY slot)
    FROM app_private.private_beta_allowlist
  ), '')),
  'membership_count', (SELECT count(*) FROM public.couple_memberships),
  'membership_fingerprint', md5(coalesce((
    SELECT string_agg(couple_id::text || ':' || user_id::text || ':' || seat::text || ':' || state,
                      ',' ORDER BY couple_id, seat)
    FROM public.couple_memberships
  ), '')),
  'expense_count', (SELECT count(*) FROM public.couple_expenses),
  'recurring_count', (SELECT count(*) FROM public.recurring_expense_rules),
  'guard_fingerprint', md5(pg_get_functiondef('app_private.guard_financial_row()'::regprocedure)),
  'migration_max', (SELECT max(version) FROM supabase_migrations.schema_migrations)
)::text;
"""
    result = psql(query)
    if result.returncode != 0:
        fail("could not read local invariants; no test transaction was started")
    candidates = [line.strip() for line in result.stdout.splitlines() if line.strip().startswith("{")]
    if len(candidates) != 1:
        fail("local invariant result was missing or ambiguous")
    try:
        return json.loads(candidates[0])
    except json.JSONDecodeError:
        fail("local invariant result was malformed")


def main() -> None:
    status = run(["supabase", "status", "--output", "env"])
    if status.returncode != 0:
        fail("local Supabase status could not be verified")
    api_match = re.search(r'^API_URL="([^"]+)"$', status.stdout, re.MULTILINE)
    if not api_match or api_match.group(1) != "http://127.0.0.1:54321":
        fail("local Supabase API target is not exactly loopback port 54321")

    label = run([
        "docker", "inspect", "--format",
        '{{ index .Config.Labels "com.supabase.cli.project" }}', CONTAINER,
    ])
    health = run([
        "docker", "inspect", "--format", "{{.State.Health.Status}}", CONTAINER,
    ])
    if label.returncode != 0 or label.stdout.strip() != PROJECT_LABEL:
        fail("database container identity is not the expected local Twogethera project")
    if health.returncode != 0 or health.stdout.strip() != "healthy":
        fail("the expected local database container is not healthy")

    migration = MIGRATION.read_text()
    proof = PROOF.read_text()
    if not re.search(r"(?m)^BEGIN;\s*", migration):
        fail("migration transaction opening was not recognized")
    migration_body = re.sub(r"(?m)^BEGIN;\s*", "", migration, count=1)
    end = re.search(r"(?m)^COMMIT;\s*NOTIFY pgrst, 'reload schema';\s*$", migration_body)
    if not end:
        fail("migration transaction ending was not recognized")
    migration_body = migration_body[: end.start()]

    before = read_invariants()
    marker = "cp034_" + secrets.token_hex(12)
    proof = proof.replace("__CP034_MARKER__", marker)
    if "__CP034_MARKER__" in proof:
        fail("proof marker substitution was incomplete")

    final_check = f"""
RESET ROLE;
ROLLBACK;
SELECT CASE WHEN
  (SELECT count(*) FROM public.couple_expenses WHERE title LIKE '{marker}:%') = 0
  AND (SELECT count(*) FROM public.recurring_expense_rules WHERE title LIKE '{marker}:%') = 0
  AND md5(pg_get_functiondef('app_private.guard_financial_row()'::regprocedure)) = '{before['guard_fingerprint']}'
THEN 'CP034_ROLLBACK_CONFIRMED' ELSE 'CP034_ROLLBACK_FAILED' END;
"""
    sql = "BEGIN;\nSET LOCAL lock_timeout = '5s';\nSET LOCAL statement_timeout = '60s';\n"
    sql += migration_body + "\n" + proof + "\n" + final_check

    result = psql(sql)
    if result.returncode != 0:
        # Do not expose SQL text, rows, identities, or raw database diagnostics.
        states = sorted(set(re.findall(r"SQLSTATE\s+([0-9A-Z]{5})", result.stderr)))
        suffix = f" (SQLSTATE {', '.join(states)})" if states else ""
        fail(f"rollback-only participant proof failed{suffix}; database output was suppressed")
    if "CP034_ROLLBACK_CONFIRMED" not in result.stdout:
        fail("explicit rollback marker or post-rollback verification was missing")

    after = read_invariants()
    if before != after:
        fail("before/after local invariants differ")

    notices = result.stderr.count("NOTICE:  CP034 PASS:")
    if notices != 12:
        fail(f"expected 12 focused assertions but observed {notices}")
    print("CP-034 PASS: 12 focused participant checks passed (6 per expense table).")
    print("CP-034 PASS: explicit rollback confirmed; migration and test rows did not persist.")
    print("CP-034 PASS: allowlist, memberships, financial row counts, guard definition, and migration history unchanged.")


if __name__ == "__main__":
    main()
