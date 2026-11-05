#!/usr/bin/env python3
"""Export the referee's graded decisions at the twin depot from production, read-only, for replay in the lab.

The referee (the check on the agent's charge orders, 0618/0620) and its grader (0621, 0630) are pure functions of
three things production keeps as evidence for every checked order:

  ottoq_charge_order_snapshots   the check's state at the decision, the agent's order, the seed of its futures
  ottoq_charge_order_grades      the grade, including `realized`: what actually happened in the window, as the grader
                                 read it before the run's own rows were purged
  ottoq_agent_charge_orders      the order itself: taken or not, and why (`projection`)

So the lab can re-grade any past decision without a run: ottoq_charge_line_realize(state, realized) and
ottoq_charge_line_schedule(...) are pure, and the lab holds them byte-identical to production's.

The decision set is 0475's and 0476's: graded at the twin depot since 2026-10-01, a decision (`decision`), a
probability (`p_win`), and one of the four decision outcomes. Rows travel as composite text (exact values) into
DIR/research.<table>.json, which lib/load_reference_data.py loads into the lab's `research` schema
(sql/40_research_schema.sql), never into the engine's own tables. Twin depot only (rule 8).

    python -I lab/engine/lib/export_decisions.py --out DIR
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from datetime import datetime, timezone

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import prod_read  # noqa: E402
from export_prod import SECRET_PATTERNS  # noqa: E402
from export_reference_data import SETTINGS, TWIN_LIT  # noqa: E402

DECISION_SET = (f"g.depot_id = {TWIN_LIT} AND g.decision AND g.p_win IS NOT NULL AND g.graded_at >= '2026-10-01' "
                "AND g.outcome IN ('missed_win', 'right_take', 'right_refusal', 'wrong_take')")
IDS = f"(SELECT g.order_id FROM public.ottoq_charge_order_grades g WHERE {DECISION_SET})"

TABLES = [
    ("public.ottoq_charge_order_grades", "research.ottoq_charge_order_grades", f"t.order_id IN {IDS}"),
    ("public.ottoq_charge_order_snapshots", "research.ottoq_charge_order_snapshots", f"t.order_id IN {IDS}"),
    ("public.ottoq_agent_charge_orders", "research.ottoq_agent_charge_orders", f"t.order_id IN {IDS}"),
]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True)
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    files = []
    for src, dst, flt in TABLES:
        q = (SETTINGS + "select pg_catalog.now()::text as read_at, coalesce(pg_catalog.json_agg(r order by r), "
             f"'[]'::json) as rows from (select (t.*)::text as r from {src} t where {flt}) q")
        res = prod_read.query(q)[0]
        rows = res["rows"] if isinstance(res["rows"], list) else json.loads(res["rows"])
        for r in rows:
            for pat in SECRET_PATTERNS:
                if pat.search(r):
                    raise SystemExit(f"refusing: a row of {src} matches a secret pattern ({pat.pattern})")
        doc = {"table": dst, "source": src, "filter": flt, "read_at": res["read_at"], "count": len(rows), "rows": rows}
        path = os.path.join(a.out, f"{dst}.json")
        with open(path, "w", encoding="utf-8") as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=0)
            fh.write("\n")
        data = open(path, "rb").read()
        files.append({"table": dst, "source": src, "rows": len(rows), "bytes": len(data),
                      "sha256": hashlib.sha256(data).hexdigest(), "read_at": res["read_at"]})
        print(f"  {src:<40} {len(rows):>6} rows  {len(data)/1e6:6.1f} MB", file=sys.stderr)
    with open(os.path.join(a.out, "manifest.json"), "w") as fh:
        json.dump({"exported_by": "lab/engine/lib/export_decisions.py", "decision_set": DECISION_SET,
                   "finished_at": datetime.now(timezone.utc).isoformat(timespec="seconds"), "tables": files}, fh, indent=1)
        fh.write("\n")
    return 0


if __name__ == "__main__":
    sys.exit(main())
