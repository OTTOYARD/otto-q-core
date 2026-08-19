"""C8 — the full Site Alpha matrix + the anti-correlation sweep.

    python3 sites/site_alpha/run_matrix.py --write   # (re)write committed artifacts
    python3 sites/site_alpha/run_matrix.py           # regenerate + verify byte-equality

Everything is a pure function of site_alpha.json (seed 424242): the same seed
reproduces both artifacts byte-for-byte. Every cell carries a deterministic
run ID (sha over its own content) — the regeneration key.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from harness_alpha import POLICIES, load_site, run_cell, run_id_of  # noqa: E402

SCENARIOS = ["baseline", "blocked_point", "overstay", "immobile_asset",
             "mid_session_charger_fault", "zone_power_loss", "human_path_crossing",
             "swap_dock_jam", "tug_unavailable", "work_side_recall_refusal"]

MATRIX = HERE / "failure_matrix_seed424242.json"
CURVE = HERE / "anticorrelation_seed424242.json"


def build_matrix(site):
    cells = []
    for sc in SCENARIOS:
        for pol in POLICIES:
            cell = run_cell(site, sc, pol)
            cell["run_id"] = run_id_of(cell)
            cells.append(cell)
    return {"site": site["name"], "seed": site["seed"],
            "crn": "one draw per seed shared by every cell", "cells": cells}


def build_curve(site):
    configs = [
        ("A+B+C", None, None),
        ("A+B (no tenant C)", ["robotaxi_operator_A", "yard_logistics_B"], None),
        ("A+B+C phase-shifted (+240 min on C)", None, {"amr_fleet_C": 240}),
    ]
    rows = []
    for label, tenants, shift in configs:
        for pol in ("otto_q_asis", "cpsat_alpha"):
            cell = run_cell(site, "baseline", pol, tenants=tenants, phase_shift=shift)
            cell["config"] = label
            cell["run_id"] = run_id_of(cell)
            rows.append(cell)
    return {"site": site["name"], "seed": site["seed"],
            "question": "what does tenant C's anti-correlated (opportunity) load do to shared-site peak kW and point turns?",
            "rows": rows}


def main():
    site = load_site()
    matrix, curve = build_matrix(site), build_curve(site)
    mb = json.dumps(matrix, indent=1, sort_keys=True) + "\n"
    cb = json.dumps(curve, indent=1, sort_keys=True) + "\n"
    if "--write" in sys.argv:
        MATRIX.write_text(mb); CURVE.write_text(cb)
        print(f"wrote {MATRIX.name} ({len(matrix['cells'])} cells) and {CURVE.name}")
    else:
        ok1 = MATRIX.read_text() == mb
        ok2 = CURVE.read_text() == cb
        print(f"matrix: {'MATCHES' if ok1 else 'DIFFERS'}; curve: {'MATCHES' if ok2 else 'DIFFERS'}")
        if not (ok1 and ok2):
            raise SystemExit(1)
    hdr = ["scenario", "policy", "tardy", "p95wait", "peak_kw", "cap_viol", "turns"]
    print(" | ".join(f"{h:>26}" for h in hdr[:2]) + " | " + " | ".join(f"{h:>8}" for h in hdr[2:]))
    for c in matrix["cells"]:
        if c.get("status") == "not_applicable":
            print(f"{c['scenario']:>26} | {c['policy']:>26} | " + "not applicable".center(50))
            continue
        m = c["metrics"]
        print(f"{c['scenario']:>26} | {c['policy']:>26} | "
              + " | ".join(f"{m[k]:>8}" for k in
                           ("total_tardy_min", "p95_wait_min", "peak_site_kw",
                            "cap_violation_kw_min", "turns")))
    print()
    for r in curve["rows"]:
        m = r["metrics"]
        print(f"{r['config']:>38} | {r['policy']:>12} | peak={m['peak_site_kw']:>5} kW | "
              f"turns={m['turns']:>3} | tardy={m['total_tardy_min']:>5} | run={r['run_id']}")


if __name__ == "__main__":
    main()
