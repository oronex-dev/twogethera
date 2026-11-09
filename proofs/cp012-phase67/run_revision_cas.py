#!/usr/bin/env python3
"""Focused local JWT/PostgREST compare-and-swap proof for CP-012."""
import run_tests as base
from concurrent.futures import ThreadPoolExecutor


def run():
    proof = base.LocalProof()
    proof.preflight()
    base.check(
        "20261102002400" in proof.sql(
            "SELECT version FROM supabase_migrations.schema_migrations"
        ),
        "revision CAS migration is not applied locally",
    )
    base.check(
        "20261102002500" in proof.sql(
            "SELECT version FROM supabase_migrations.schema_migrations"
        ),
        "milestone revision guard migration is not applied locally",
    )
    for user in ("a", "b", "c", "d"):
        proof.create_user(user)
    couple_ab = proof.pair("a", "b")
    proof.pair("c", "d")

    # Two legitimate partners collaborate with revisioned date-night writes.
    code, ideas = proof.rest("a", "date_night_ideas", "", "POST", {
        "couple_id": couple_ab, "title": "CAS date night", "description": "Before update",
    })
    base.check(code in (200, 201) and len(ideas) == 1, "date-night fixture failed")
    idea = ideas[0]
    code, result = proof.rpc("b", "update_date_night_idea", {
        "p_couple_id": couple_ab, "p_idea_id": idea["id"],
        "p_expected_revision": idea["revision"],
        "p_changes": {"description": "Updated by partner B"},
    })
    base.check(code == 200 and result == "updated", "partner B's current-revision update failed")
    code, result = proof.rpc("a", "update_date_night_idea", {
        "p_couple_id": couple_ab, "p_idea_id": idea["id"],
        "p_expected_revision": idea["revision"],
        "p_changes": {"description": "Stale overwrite"},
    })
    base.check(code == 200 and result == "conflict", "stale date-night update was not rejected")
    code, _ = proof.rest("a", "date_night_ideas", "?id=eq." + idea["id"], "PATCH", {
        "description": "Direct table bypass",
    })
    base.check(code in (401, 403), "authenticated role bypassed date-night CAS with direct UPDATE")
    code, result = proof.rpc("c", "update_date_night_idea", {
        "p_couple_id": couple_ab, "p_idea_id": idea["id"],
        "p_expected_revision": 2, "p_changes": {"title": "Cross-couple edit"},
    })
    base.check(code == 200 and result == "unavailable", "unrelated couple RPC update was not denied")
    code, rows = proof.rest("b", "date_night_ideas", "?select=description,revision,updated_by&id=eq." + idea["id"])
    base.check(code == 200 and rows == [{
        "description": "Updated by partner B", "revision": 2,
        "updated_by": proof.users["b"]["id"],
    }], "date-night conflict or denied writes modified data/actor attribution")

    # Force overlapping requests with one expected revision; only one may win.
    code, concurrent_ideas = proof.rest("a", "date_night_ideas", "", "POST", {
        "couple_id": couple_ab, "title": "Concurrent CAS date night",
    })
    base.check(code in (200, 201) and len(concurrent_ideas) == 1,
               "concurrency fixture failed")
    concurrent_idea = concurrent_ideas[0]
    def concurrent_update(user, title):
        return proof.rpc(user, "update_date_night_idea", {
            "p_couple_id": couple_ab, "p_idea_id": concurrent_idea["id"],
            "p_expected_revision": concurrent_idea["revision"],
            "p_changes": {"title": title},
        })
    with ThreadPoolExecutor(max_workers=2) as pool:
        results = list(pool.map(lambda pair: concurrent_update(*pair), (
            ("a", "Concurrent update A"), ("b", "Concurrent update B"),
        )))
    base.check(all(code == 200 for code, _ in results),
               "concurrent RPC requests did not complete")
    base.check(sorted(result for _, result in results) == ["conflict", "updated"],
               "concurrent same-revision updates did not yield exactly one winner")
    code, concurrent_rows = proof.rest("a", "date_night_ideas",
        "?select=title,revision&id=eq." + concurrent_idea["id"])
    base.check(code == 200 and len(concurrent_rows) == 1
               and concurrent_rows[0]["revision"] == 2
               and concurrent_rows[0]["title"] in ("Concurrent update A", "Concurrent update B"),
               "concurrent stale writer changed the winning record")

    code, goals = proof.rest("a", "shared_goals", "", "POST", {
        "couple_id": couple_ab, "title": "CAS goal", "description": "Before update",
    })
    base.check(code in (200, 201) and len(goals) == 1, "goal fixture failed")
    goal = goals[0]
    code, result = proof.rpc("a", "update_shared_goal", {
        "p_couple_id": couple_ab, "p_goal_id": goal["id"],
        "p_expected_revision": goal["revision"],
        "p_changes": {"description": "Updated by partner A"},
    })
    base.check(code == 200 and result == "updated", "partner A's current-revision goal update failed")
    code, result = proof.rpc("b", "update_shared_goal", {
        "p_couple_id": couple_ab, "p_goal_id": goal["id"],
        "p_expected_revision": goal["revision"],
        "p_changes": {"description": "Stale overwrite"},
    })
    base.check(code == 200 and result == "conflict", "stale goal update was not rejected")
    code, _ = proof.rest("b", "shared_goals", "?id=eq." + goal["id"], "PATCH", {
        "description": "Direct table bypass",
    })
    base.check(code in (401, 403), "authenticated role bypassed goal CAS with direct UPDATE")
    code, result = proof.rpc("c", "update_shared_goal", {
        "p_couple_id": couple_ab, "p_goal_id": goal["id"],
        "p_expected_revision": 2, "p_changes": {"title": "Cross-couple edit"},
    })
    base.check(code == 200 and result == "unavailable", "unrelated couple goal RPC update was not denied")
    code, rows = proof.rest("b", "shared_goals", "?select=description,revision,updated_by&id=eq." + goal["id"])
    base.check(code == 200 and rows == [{
        "description": "Updated by partner A", "revision": 2,
        "updated_by": proof.users["a"]["id"],
    }], "goal conflict or denied writes modified data/actor attribution")

    code, milestones = proof.rest("a", "shared_goal_milestones", "", "POST", {
        "couple_id": couple_ab, "goal_id": goal["id"], "title": "CAS milestone",
    })
    base.check(code in (200, 201) and len(milestones) == 1, "milestone fixture failed")
    milestone = milestones[0]
    code, result = proof.rpc("b", "update_shared_goal_milestone", {
        "p_couple_id": couple_ab, "p_goal_id": goal["id"],
        "p_milestone_id": milestone["id"],
        "p_expected_revision": milestone["revision"],
        "p_changes": {"title": "Updated by partner B"},
    })
    base.check(code == 200 and result == "updated", "partner B's current-revision milestone update failed: HTTP " + str(code) + ", result=" + repr(result))
    code, result = proof.rpc("a", "update_shared_goal_milestone", {
        "p_couple_id": couple_ab, "p_goal_id": goal["id"],
        "p_milestone_id": milestone["id"],
        "p_expected_revision": milestone["revision"],
        "p_changes": {"title": "Stale overwrite"},
    })
    base.check(code == 200 and result == "conflict", "stale milestone update was not rejected")
    code, _ = proof.rest("a", "shared_goal_milestones", "?id=eq." + milestone["id"], "PATCH", {
        "title": "Direct table bypass",
    })
    base.check(code in (401, 403), "authenticated role bypassed milestone CAS with direct UPDATE")
    code, result = proof.rpc("c", "update_shared_goal_milestone", {
        "p_couple_id": couple_ab, "p_goal_id": goal["id"],
        "p_milestone_id": milestone["id"], "p_expected_revision": 2,
        "p_changes": {"title": "Cross-couple edit"},
    })
    base.check(code == 200 and result == "unavailable", "unrelated couple milestone RPC update was not denied")
    code, rows = proof.rest("b", "shared_goal_milestones", "?select=title,revision,updated_by&id=eq." + milestone["id"])
    base.check(code == 200 and rows == [{
        "title": "Updated by partner B", "revision": 2,
        "updated_by": proof.users["b"]["id"],
    }], "milestone conflict or denied writes modified data/actor attribution")

    print(f"CP-012 revision CAS proof: {base.ASSERTIONS} assertions passed")


if __name__ == "__main__":
    run()
