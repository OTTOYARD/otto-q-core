"""C6 — the KPI regression gate.

    python3 metrics/kpi_gate.py                 # regenerate 24h comparison, compare vs baseline
    python3 metrics/kpi_gate.py --rebaseline    # write a new baseline (deliberate act)
    python3 metrics/kpi_gate.py --demo-regression   # prove the gate fires (exit 1)

The gate re-runs the 24-sim-hour seeded four-policy comparison
(solvers/cpsat/scenario_24h.json, seed 424242, CRN discipline) and FAILS THE
BUILD when any guarded metric regresses beyond its threshold vs the committed
baseline (metrics/baseline_24h_seed424242.json). Regression direction is
per-metric (higher-is-worse for all guarded metrics). Byte-identity of the
baseline itself is asserted separately by policies/test_policies.py for the
600-min artifact; the gate guards the 24h numbers.
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE.parent / "policies"))
sys.path.insert(0, str(HERE.parent / "solvers" / "cpsat"))

from harness import run_comparison  # noqa: E402

SC24 = HERE.parent / "solvers" / "cpsat" / "scenario_24h.json"
BASELINE = HERE / "baseline_24h_seed424242.json"

# metric -> allowed regression (absolute, in the metric's own unit).
# higher-is-worse for every guarded metric.
THRESHOLDS = {
    "total_tardy_min": 15,
    "p95_wait_to_first_op_min": 10,
    "peak_site_kw": 25,
    "makespan_min": 30,
}
GUARDED_POLICIES = ("cpsat", "otto_q_asis")


def main():
    comp = run_comparison(SC24)
    if "--rebaseline" in sys.argv:
        BASELINE.write_text(json.dumps(comp, indent=1, sort_keys=True) + "\n")
        print(f"baseline written: sha256 {comp['comparison_sha256']}")
        return 0
    base = json.loads(BASELINE.read_text())
    cand = {r["policy"]: r["metrics"] for r in comp["runs"]}
    if "--demo-regression" in sys.argv:
        cand["cpsat"] = {**cand["cpsat"],
                         "total_tardy_min": cand["cpsat"]["total_tardy_min"]
                         + THRESHOLDS["total_tardy_min"] + 50}
        print("[demo] injected +{} tardy minutes into cpsat".format(
            THRESHOLDS["total_tardy_min"] + 50))
    ref = {r["policy"]: r["metrics"] for r in base["runs"]}
    failures = []
    for pol in GUARDED_POLICIES:
        for metric, allow in THRESHOLDS.items():
            delta = cand[pol][metric] - ref[pol][metric]
            status = "FAIL" if delta > allow else "ok"
            print(f"{status:>4}  {pol:12s} {metric:28s} baseline={ref[pol][metric]:>7} "
                  f"candidate={cand[pol][metric]:>7} delta={delta:>+6} allowed=+{allow}")
            if delta > allow:
                failures.append((pol, metric, delta, allow))
    if failures:
        print(f"\nKPI GATE: FAILED — {len(failures)} regression(s) beyond threshold")
        return 1
    same = comp["comparison_sha256"] == base.get("comparison_sha256")
    print(f"\nKPI GATE: PASS ({'byte-identical to baseline' if same else 'within thresholds'})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
