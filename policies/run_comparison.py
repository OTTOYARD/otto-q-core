"""C5 — generate the committed four-policy comparison (seed 424242).

    python3 policies/run_comparison.py            # regenerates + verifies
    python3 policies/run_comparison.py --write    # (re)writes the artifact

Byte-for-byte rule: the artifact contains no timestamps and is written with
sorted keys; regeneration from the committed scenario must reproduce
comparison_seed424242.json exactly (sha256 asserted by test_policies.py).
"""
import json
import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
from harness import run_comparison  # noqa: E402

SC = HERE.parent / "solvers" / "cpsat" / "scenario_canonical.json"
ARTIFACT = HERE / "comparison_seed424242.json"


def main():
    comp = run_comparison(SC)
    blob = json.dumps(comp, indent=1, sort_keys=True) + "\n"
    if "--write" in sys.argv:
        ARTIFACT.write_text(blob)
        print(f"wrote {ARTIFACT.name}  sha256={comp['comparison_sha256']}")
    else:
        committed = ARTIFACT.read_text()
        status = "MATCHES committed artifact" if committed == blob else "DIFFERS from committed artifact"
        print(f"regenerated sha256={comp['comparison_sha256']}  -> {status}")
    hdr = ["policy", "total_tardy_min", "p95_wait_min", "peak_kw", "turns", "moves", "makespan"]
    print(" | ".join(f"{h:>15}" for h in hdr))
    for r in comp["runs"]:
        mm = r["metrics"]
        print(" | ".join(f"{x:>15}" for x in [
            r["policy"], mm["total_tardy_min"], mm["p95_wait_to_first_op_min"],
            mm["peak_site_kw"], mm["charge_point_turns"], mm["total_moves"],
            mm["makespan_min"]]))
    return comp


if __name__ == "__main__":
    main()
