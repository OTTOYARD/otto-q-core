#!/usr/bin/env python3
"""G512 §4's open question: would the agent's charge orders help owners if each owner kept its places in the line?

Rule 14's own form for a rule added for the depot's sake: "may trade places only among one owner's own cars". 0781's
exit key does exactly that. Here the same projection is applied to each of the 370 graded agent orders (the decision set
of 0475/0476, in the lab's research schema): the kernel's own line at the order's moment is read from the check's own
simulator (the order in which the cars present get their first seat in the kernel's expected future); each owner keeps
the positions its cars hold in that line, and inside them its cars are re-ranked by the agent (the cars the agent
ranked first, in its order, then the rest in the kernel's). The projected order is then rolled forward exactly as the
check rolls an order (ottoq_charge_line_schedule: the expected future s=0 and the 11 sampled ones, the same seed), and in
hindsight (the realized window the grader stored, ottoq_charge_line_realize), against the kernel's own order, owner by
owner with ottoq_charge_line_compare. The baseline is the kernel's own line given as an explicit order through the same
path (each car the same kind on both sides), so the only difference between the two sides is the order: a first pass
against the kernel's own unordered path read 9 of the 22 orders the projection leaves unchanged as changed.

Writes research.owner_projection2 (order_id, s, owner, cmp, by) where s = -1 is hindsight, and research.
owner_projection2_orders (order_id, moved, projected order). Run with --worker N --workers 4, one per core, then report.sql.
LAB ONLY. Nothing here touches production.
"""
from __future__ import annotations

import argparse
import json
import os

import psycopg

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
DB = os.environ.get("LAB_DB", "ottoq_lab")
TWIN = "11111111-1111-1111-1111-111111111111"
PARTS = ["arrivals", "appeared", "charge_times", "running", "faults"]

DDL = """
CREATE TABLE IF NOT EXISTS research.owner_projection2 (
  order_id bigint NOT NULL, s int NOT NULL, owner text NOT NULL, cmp int, by text, PRIMARY KEY (order_id, s, owner));
CREATE TABLE IF NOT EXISTS research.owner_projection2_orders (
  order_id bigint PRIMARY KEY, n_line int, n_ranked int, moved int, projected jsonb);
"""

STATE_SQL = """
WITH own AS (
  SELECT COALESCE(jsonb_object_agg(ov.id::text, ov.fleet_operator_id), '{}'::jsonb) AS owners
    FROM public.vehicles ov WHERE ov.home_depot_id = %(depot)s AND ov.category = 'autonomous')
SELECT s.order_id, s.seed, s.futures, s.agent_order, g.realized,
       CASE WHEN COALESCE((s.state ->> 'owner_guard')::boolean, false) THEN s.state
            ELSE s.state || jsonb_build_object('owner_guard', true)
                         || CASE WHEN s.state ? 'owners' THEN '{}'::jsonb ELSE jsonb_build_object('owners', own.owners) END
       END AS state_o
  FROM research.ottoq_charge_order_snapshots s JOIN research.ottoq_charge_order_grades g USING (order_id), own
 WHERE s.order_id %% %(workers)s = %(worker)s
 ORDER BY s.order_id
"""


def project(state: dict, agent_order: dict, seats: list) -> tuple[dict, dict, int, int]:
    """The agent's order with every owner keeping the places its cars hold in the kernel's line."""
    present = [c["id"] for c in state.get("cars", [])]
    first = {x["id"]: x.get("s0") for x in seats if not x.get("inb")}
    idx = {cid: i for i, cid in enumerate(present)}
    line = sorted(present, key=lambda c: (first.get(c) is None, first.get(c) if first.get(c) is not None else 0, idx[c]))
    owners = state.get("owners") or {}
    pos = {}
    for i, c in enumerate(line):
        pos.setdefault(owners.get(c, "none"), []).append(i)
    proj = [None] * len(line)
    for o, places in pos.items():
        cars = [c for c in line if owners.get(c, "none") == o]
        cars.sort(key=lambda c: (0, agent_order[c]["rank"]) if c in agent_order else (1, line.index(c)))
        for p, c in zip(places, cars):
            proj[p] = c
    # both sides through the same path (an explicit order, each car with the same kind on both): the kernel's own
    # line as an order, and the projection; so an order the projection leaves as the kernel's reads as no change
    kind = {c: (agent_order[c]["kind"] if c in agent_order else "either") for c in line}
    order = {c: {"rank": r, "kind": kind[c]} for r, c in enumerate(proj, start=1)}
    base = {c: {"rank": r, "kind": kind[c]} for r, c in enumerate(line, start=1)}
    moved = sum(1 for a, b in zip(line, proj) if a != b)
    return order, base, len(line), moved


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--worker", type=int, default=0)
    ap.add_argument("--workers", type=int, default=1)
    a = ap.parse_args()
    conn = psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=DB, autocommit=True)
    conn.execute(DDL)
    rows = conn.execute(STATE_SQL, {"depot": TWIN, "workers": a.workers, "worker": a.worker}).fetchall()
    for order_id, seed, futures, agent_order, realized, state in rows:
        if conn.execute("SELECT 1 FROM research.owner_projection2_orders WHERE order_id = %s", (order_id,)).fetchone():
            continue
        st = json.dumps(state)
        seats = conn.execute("SELECT public.ottoq_charge_line_schedule(%s::jsonb, NULL, 0, %s, true) -> 'seats'",
                             (st, seed)).fetchone()[0] or []
        order, base, n_line, moved = project(state, agent_order or {}, seats)
        oj, bj = json.dumps(order), json.dumps(base)
        out = []
        full = conn.execute("SELECT public.ottoq_charge_line_realize(%s::jsonb, %s::jsonb, %s)",
                            (st, json.dumps(realized), PARTS)).fetchone()[0]
        for s_ in [-1] + list(range(0, int(futures or 12))):
            base_state = json.dumps(full) if s_ == -1 else st
            sc = 0 if s_ == -1 else s_
            k, p = conn.execute("""SELECT public.ottoq_charge_line_schedule(%(st)s::jsonb, %(b)s::jsonb, %(s)s, %(seed)s, false) -> 'by_owner',
                                          public.ottoq_charge_line_schedule(%(st)s::jsonb, %(o)s::jsonb, %(s)s, %(seed)s, false) -> 'by_owner'""",
                                {"st": base_state, "s": sc, "seed": seed, "o": oj, "b": bj}).fetchone()
            k, p = k or {}, p or {}
            for ow in sorted(set(k) | set(p)):
                kz = k.get(ow) or {key: 0 for key in (p.get(ow) or {})}
                pz = p.get(ow) or {key: 0 for key in (k.get(ow) or {})}
                c = conn.execute("SELECT public.ottoq_charge_line_compare(%s::jsonb, %s::jsonb)",
                                 (json.dumps(kz), json.dumps(pz))).fetchone()[0] or {}
                out.append((order_id, s_, ow, c.get("cmp"), c.get("by")))
        with conn.transaction():
            conn.cursor().executemany("INSERT INTO research.owner_projection2 VALUES (%s, %s, %s, %s, %s) "
                                      "ON CONFLICT DO NOTHING", out)
            conn.execute("INSERT INTO research.owner_projection2_orders VALUES (%s, %s, %s, %s, %s) ON CONFLICT DO NOTHING",
                         (order_id, n_line, len(agent_order or {}), moved, oj))
    print(f"worker {a.worker}: {len(rows)} orders", flush=True)


if __name__ == "__main__":
    main()
