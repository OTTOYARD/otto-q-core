#!/usr/bin/env python3
"""E1 acceptance test 1 -- fidelity (docs/FRONTIER_PLAN_2026-11-03.md, E1 "Done when" 1).

"A Lab pair agrees with itself on all 14 atoms. A Lab arm reproduces the atom digests recomputed from a surviving
production run's stored rows for the same scenario, seed and ticks."

What this script measures, and what it cannot:

  1. THE LAB PAIR. public.ottoq_determinism_pair, the engine's own instrument, unmodified, run in the lab database
     (both arms in one transaction, as in production). Its verdict is reported as the engine gives it; if the end
     state disagrees, the visit-need atoms are compared with the minted robot_leg_id set aside (lib/lab_run.py), so
     the report says whether the arms differ in anything else.
  2. THE WORLD. The twin depot's world fingerprint (ottoq.ottoq_world_fingerprint_sections, the engine's hash of
     vehicles, stalls, chargers, need profiles and BESS) in the lab, against production's read now through the
     read-only endpoint (--prod) and against the one recorded at export time (the data manifest).
  3. A PRODUCTION RUN'S DIGESTS: not measurable today, and the report says why. Production's newest pair verdict is
     2026-10-14 under another engine hash (rule 12 stopped certification on 2026-10-20), and its only run on today's
     engine is a live demo run (paced by real time, agent on), which an unpaced arm cannot reproduce without
     replaying its tick clock and its agent's orders.

The pair commits, as it does in production: its two runs are archived and torn down by the engine itself
(ottoq_sim_stop_and_reset), and its verdict lands in the lab's own ottoq_determinism_verdict_ledger. Rebuild the lab
(build_from_prod.sh) to start again from production's state.

    /var/tmp/ottoq_lab_venv/bin/python -I lab/engine/acceptance/fidelity.py --dsn DSN --data DIR --out FILE.json [--prod]
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
from datetime import datetime, timezone

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "lib"))
import psycopg  # noqa: E402
from lab_run import TWIN, VIS_STRIPPED_SQL  # noqa: E402


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dsn", required=True)
    ap.add_argument("--data", required=True, help="the reference data export (its manifest holds the export-time fingerprint)")
    ap.add_argument("--out", required=True)
    ap.add_argument("--seed", type=int, default=171717)
    ap.add_argument("--ticks", type=int, default=12)
    ap.add_argument("--scenario", default="busy_day")
    ap.add_argument("--prod", action="store_true", help="also read production's fingerprint now (read-only endpoint)")
    a = ap.parse_args()
    started = datetime.now(timezone.utc)
    out: dict = {"test": "E1 acceptance 1: fidelity", "started": started.isoformat(timespec="seconds"),
                 "seed": a.seed, "ticks": a.ticks, "scenario": a.scenario}

    with psycopg.connect(a.dsn, autocommit=True) as conn, conn.cursor() as c:
        # 2. the world, before the pair touches the fleet (the pair resets it from the seed)
        c.execute("SELECT ottoq.ottoq_world_fingerprint_sections(%s)", (TWIN,))
        lab_fp = c.fetchone()[0]
        c.execute("SELECT public.ottoq_engine_hash()")
        out["lab_engine_hash"] = c.fetchone()[0]
        # 1. the pair
        t0 = time.perf_counter()
        c.execute("SELECT public.ottoq_determinism_pair(%s, %s, %s, %s, '2026-09-01 02:00:00+00', 36000)",
                  (a.seed, a.ticks, a.scenario, TWIN))
        verdict = c.fetchone()[0]
        out["pair_wall_seconds"] = round(time.perf_counter() - t0, 1)
        arms = (verdict["arm_a"]["run"], verdict["arm_b"]["run"])
        # the end state's visit needs with robot_leg_id set aside, per arm (rows survive the arm's teardown)
        stripped = []
        for run in arms:
            c.execute(VIS_STRIPPED_SQL, {"run": run, "depot": TWIN})
            stripped.append(c.fetchone()[0])
        c.execute("""SELECT count(*) FROM ottoq_visit_needs t, jsonb_array_elements(t.atoms) e
                      WHERE t.sim_run_id = %s AND jsonb_typeof(t.atoms) = 'array' AND e ? 'robot_leg_id'""", (arms[0],))
        legs = c.fetchone()[0]

    ea, eb = verdict["arm_a"]["endst"], verdict["arm_b"]["endst"]
    sections = sorted(s for s in set(ea) | set(eb) if ea.get(s) != eb.get(s))
    vis_differs = ea.get("visit_needs", {}).get("vis") != eb.get("visit_needs", {}).get("vis")
    out["pair"] = {
        "outcome": verdict["outcome"], "equal": verdict["equal"], "complete": verdict["complete"],
        "disagreeing_atoms": verdict["disagreeing_atoms"], "null_atoms": verdict["null_atoms"],
        "atoms_agreeing": 14 - len(verdict["disagreeing_atoms"]),
        "end_state_sections_differing": sections,
        "robot_leg_ids_in_arm_a": legs,
        "end_state_equal_without_robot_leg_id": (sections in ([], ["visit_needs"])
                                                 and (not vis_differs or stripped[0] == stripped[1])
                                                 and ea.get("visit_needs", {}).get("fgn") == eb.get("visit_needs", {}).get("fgn")),
        "arm_runs": arms,
        "digests_arm_a": {k: verdict["arm_a"][k] for k in ("fp", "h_cmd", "h_dec", "h_evt", "h_bkg", "h_nrg", "h_prop",
                                                           "h_defr", "h_cal", "h_rule", "h_rcl", "h_sdr", "ticks")},
    }

    manifest = json.load(open(os.path.join(a.data, "manifest.json")))
    exp_fp = manifest["world_fingerprint"]["after"]
    exp_fp = exp_fp.get("jsonb_build_object", exp_fp)
    out["world"] = {"lab": lab_fp, "at_export": exp_fp, "lab_equals_export": lab_fp == exp_fp,
                    "export_read_at": manifest["world_fingerprint"]["after_read_at"]}
    if a.prod:
        import prod_read  # noqa: E402
        from export_reference_data import fingerprint_sql  # noqa: E402
        export_dir = os.path.dirname(os.path.abspath(a.data.rstrip("/")))
        fn_text = open(os.path.join(export_dir, "06_functions.sql"), encoding="utf-8").read()
        start = fn_text.index("CREATE OR REPLACE FUNCTION ottoq.ottoq_world_fingerprint_sections(p_depot uuid)")
        q = ("select pg_catalog.set_config('search_path', 'ottoq, public, extensions', true); "
             + fingerprint_sql(fn_text[start:fn_text.index("\n-- @@ ", start)]))
        row = prod_read.query(q)[0]
        prod_fp = row.get("jsonb_build_object", row)
        out["world"].update(prod_now=prod_fp, lab_equals_prod_now=lab_fp == prod_fp,
                            prod_read_at=prod_read.query("select now()::text as at")[0]["at"])

    out["production_run_digests"] = {
        "measured": False,
        "why": ("No production pair has run on this engine: the newest verdict in ottoq_determinism_verdict_ledger is "
                "2026-10-14 (engine hash 9b561d56...), certification has been off since 2026-10-20 (rule 12), and the "
                "only production run on this engine is a live demo run, whose tick lengths follow real time and whose "
                "agent orders arrive asynchronously. Reproducing it needs its tick clock and its agent's orders replayed."),
    }
    out["finished"] = datetime.now(timezone.utc).isoformat(timespec="seconds")
    with open(a.out, "w") as fh:
        json.dump(out, fh, indent=1, default=str)
        fh.write("\n")
    print(json.dumps({"pair": {k: out["pair"][k] for k in ("outcome", "atoms_agreeing", "disagreeing_atoms",
                                                            "end_state_sections_differing", "robot_leg_ids_in_arm_a",
                                                            "end_state_equal_without_robot_leg_id")},
                      "pair_wall_seconds": out["pair_wall_seconds"],
                      "world": {k: v for k, v in out["world"].items() if k.startswith("lab_equals")}}, indent=1))
    return 0


if __name__ == "__main__":
    sys.exit(main())
