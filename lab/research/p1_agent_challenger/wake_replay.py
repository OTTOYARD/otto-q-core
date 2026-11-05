#!/usr/bin/env python3
"""How often the agent would be consulted with 0795 and the wake gate on, replayed on the twin depot's recent passes.

Reads production's own pass records (public.ottoq_agent_pass_evidence) through the read-only endpoint
(lab/engine/lib/prod_read.py). On those runs the gate was in shadow, so every pass consulted the model and each pass's
wake reasons were computed against the pass just before it. The replay walks each run's passes in order and wakes:
  - on any reason but the two order moments (charger_free, due_in_line), which 0795 stops waking for;
  - on the first pass of a run;
  - when the last replayed consult is at least the heartbeat (30 sim-minutes) behind.
It is an estimate, and says why: with fewer consults, the gate's onsets and jumps would be judged against an older
fingerprint than the one these passes recorded, so the exception count can move either way. The heartbeat count is
exact for the passes that happened.

Usage: python3 -I lab/research/p1_agent_challenger/wake_replay.py [--since 2026-10-20]
"""
from __future__ import annotations

import argparse
import datetime as dt
import os
import sys
from collections import defaultdict

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "engine", "lib"))
import prod_read  # noqa: E402

TWIN = "11111111-1111-1111-1111-111111111111"
MOMENTS = {"charger_free", "due_in_line"}


def parse(c: str | None):
    return dt.datetime.fromisoformat(c.replace(" ", "T")) if c else None


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--since", default="2026-10-20")
    a = ap.parse_args()
    rows = prod_read.query(f"""
      SELECT e.sim_run_id::text AS run, e.pass_id, e.sim_clock::text AS clock,
             COALESCE(e.wake -> 'reasons', '[]'::jsonb) AS reasons, (e.wake ->> 'heartbeat_sim_min')::numeric AS hb
        FROM public.ottoq_agent_pass_evidence e
       WHERE e.depot_id = '{TWIN}' AND e.recorded_at >= '{a.since}'
       ORDER BY e.sim_run_id, e.pass_id""")
    by = defaultdict(list)
    for r in rows:
        by[r["run"]].append(r)
    tot = defaultdict(float)
    print("run       passes  shadow-reasons  with-0795  heartbeat-only  exception-woken  sim-hours")
    for run, ps in sorted(by.items(), key=lambda kv: kv[1][0]["clock"] or ""):
        ps.sort(key=lambda r: r["pass_id"])
        built = new = hb_only = exc_n = 0
        last = None
        for r in ps:
            reasons = set(r["reasons"] or [])
            built += bool(reasons)
            clk = parse(r["clock"])
            hb = float(r["hb"] or 30)
            exc = reasons - MOMENTS - {"heartbeat"}
            if exc or last is None or (clk is not None and (clk - last).total_seconds() / 60 >= hb):
                new += 1
                if exc:
                    exc_n += 1
                elif last is not None:
                    hb_only += 1
                last = clk
        span = (parse(ps[-1]["clock"]) - parse(ps[0]["clock"])).total_seconds() / 3600
        print(f"{run[:8]}  {len(ps):6d}  {built:14d}  {new:9d}  {hb_only:14d}  {exc_n:15d}  {span:9.1f}")
        for k, v in (("passes", len(ps)), ("shadow", built), ("new", new), ("hb", hb_only), ("exc", exc_n), ("h", span)):
            tot[k] += v
    print(f"all       {int(tot['passes']):6d}  {int(tot['shadow']):14d}  {int(tot['new']):9d}  {int(tot['hb']):14d}  "
          f"{int(tot['exc']):15d}  {tot['h']:9.1f}")


if __name__ == "__main__":
    main()
