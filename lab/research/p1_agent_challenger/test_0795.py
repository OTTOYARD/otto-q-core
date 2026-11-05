#!/usr/bin/env python3
"""0795 executed in the research lab, on a replica of production's engine and world.

What it shows, each as an assertion (the script exits non-zero on the first one that fails):
  1. 0795 applies to a replica of the lab (production's engine as of 2026-11-05, 0794 included), its checks pass and
     it is classified FALSE/FALSE.
  2. At the dial's default every patched function answers exactly as its pre-image does, on a real congested line of the
     twin depot (busy_day, seed 171717): the record's receipt and row, the board, the usage, the wake gate, the grade.
  3. With the dial on at the twin depot, an order the check takes is recorded 'shadow', never stands
     (ottoq_agent_charge_order_live answers {}), and the next tick decides, commands and books exactly as with no order
     at all; with the dial at 0 the same order is 'accepted' and does stand.
  4. An order the check refuses is still 'refused', with the check's own reason, whatever the dial.
  5. The grade of a shadow order is the check's take (taken = true) and its forecast errors read the kernel's side, the
     side the depot followed; the same order accepted reads the agent's side.
  6. The board says 'shadow': true with the dial on and is otherwise the same board; the usage counts orders_shadow.
  7. The wake gate, with the dial on, does not wake for charger_free or due_in_line and still counts both in its
     fingerprint; at 0 it wakes for them as before.

The check's verdict is replaced by a stub that takes every order only inside the savepoints of (3) and (5), so the
branch under test runs whether or not the real check would take the order at that moment; (4) uses the real check.

Usage (the lab server up, see lab/engine/README.md):
  /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p1_agent_challenger/test_0795.py [--keep]
Nothing here touches production.
"""
from __future__ import annotations

import json
import os
import subprocess
import sys
import time

import psycopg

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "lab", "engine", "lib"))
from lab_run import PER_TICK_SQL, Arm, TWIN, clone_database  # noqa: E402

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
TEMPLATE = os.environ.get("LAB_DB", "ottoq_lab")
REPLICA = "ottoq_lab_0795"
MIG = os.path.join(ROOT, "db", "migrations",
                   "0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions.sql")
NAME = "0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions"
FNS = {
    "record": "public.ottoq_agent_charge_order_record(uuid,bigint,text,text,jsonb)",
    "usage": "public.ottoq_agent_charge_order_usage(uuid,integer)",
    "board": "public.ottoq_agent_charge_queue_board(uuid,uuid,timestamp with time zone)",
    "wake": "public.ottoq_agent_wake(uuid)",
    "grade": "public.ottoq_charge_order_grade_compute(bigint,numeric)",
}
STUB_TAKE = """
CREATE OR REPLACE FUNCTION public.ottoq_charge_order_verdict_v2(p_rollout jsonb, p_win_frac numeric)
 RETURNS jsonb LANGUAGE sql IMMUTABLE AS $f$
  SELECT jsonb_build_object('take', true, 'reason', 'wins_most_futures', 'futures', 12, 'wins', 12, 'ties', 0,
                            'losses', 0, 'need', 10, 'win_frac', p_win_frac, 'stub', 'test_0795')
$f$"""
LOG: list[str] = []


def say(msg: str) -> None:
    print(msg, flush=True)
    LOG.append(msg)


def check(cond: bool, what: str) -> None:
    if not cond:
        say(f"FAIL  {what}")
        raise SystemExit(1)
    say(f"ok    {what}")


def connect(db: str, autocommit: bool = False) -> psycopg.Connection:
    return psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db, autocommit=autocommit)


def one(conn, sql, params=None):
    with conn.cursor() as c:
        c.execute(sql, params)
        r = c.fetchone()
        return r[0] if r else None


def rows(conn, sql, params=None):
    with conn.cursor() as c:
        c.execute(sql, params)
        return c.fetchall()


def install_pre_images(conn) -> dict:
    """Each 0795_pre definition, renamed to public.x0795_pre_<name>, so old and new can be asked the same question."""
    out = {}
    for name, defn in rows(conn, "SELECT object_name, definition FROM ottoq_schema_snapshots WHERE label = '0795_pre'"):
        renamed = defn.replace(f"FUNCTION public.{name}(", f"FUNCTION public.x0795_pre_{name}(", 1)
        assert renamed != defn, name
        with conn.cursor() as c:
            c.execute(renamed)
        out[name] = f"public.x0795_pre_{name}"
    return out


def main() -> None:
    t0 = time.time()
    admin = connect("postgres", autocommit=True)
    if one(admin, "SELECT count(*) FROM pg_database WHERE datname = %s", (REPLICA,)):
        admin.execute(f"DROP DATABASE {REPLICA}")
    secs = clone_database(admin, TEMPLATE, REPLICA)
    say(f"replica {REPLICA} cloned from {TEMPLATE} in {secs:.1f} s")

    # ── 1. apply ──
    r = subprocess.run(["psql", "-h", HOST, "-p", str(PORT), "-U", "postgres", "-X", "-q", "-v", "ON_ERROR_STOP=1",
                        "-d", REPLICA, "-f", MIG], capture_output=True, text=True)
    check(r.returncode == 0, f"0795 applies to the replica ({r.stderr.strip()[:300] or 'no error'})")
    conn = connect(REPLICA)
    conn.autocommit = False
    lineage = rows(conn, "SELECT forces_recert, forces_dial_restart FROM ottoq_cert_lineage WHERE name = %s", (NAME,))
    check(lineage == [(False, False)], "classified FALSE/FALSE")
    check(one(conn, "SELECT default_value FROM ottoq_policy_param_catalog WHERE param_key = 'agent_charge_order_shadow'") == 0,
          "the dial is catalogued with default 0")
    pre = install_pre_images(conn)
    conn.commit()

    # ── a real line: busy_day 171717, an arm of the pair, ticked until cars wait for a charger ──
    arm = Arm(conn, 171717)
    run = arm.start()
    arm.set_run_dial("agent_charge_order", 1, "test_0795")   # an operator's run is armed with it (0615)
    for k in range(1, 13):
        arm.tick()
        q = one(conn, "SELECT count(*) FROM ottoq_charge_queue_kernel_order(%s, %s, (SELECT sim_clock_current FROM "
                      "ottoq_sim_runs WHERE sim_run_id = %s))", (run, TWIN, run))
        if q >= 6:
            break
    tick, clock = rows(conn, "SELECT tick_count, sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,))[0]
    kernel = [str(v) for (v,) in rows(conn, "SELECT vehicle_id FROM ottoq_charge_queue_kernel_order(%s, %s, %s) "
                                          "ORDER BY kernel_pos", (run, TWIN, clock))]
    check(len(kernel) >= 6, f"a line of {len(kernel)} cars waits at tick {tick} ({clock})")
    # the agent's order: the kernel's first six, reversed
    order = {"cars": [{"vehicle_id": v, "kind": "either", "why": "test"} for v in reversed(kernel[:6])], "why": "test_0795"}
    oj = json.dumps(order)

    def set_dial(v: int) -> None:
        one(conn, "SELECT ottoq_policy_set('depot', %s, 'agent_charge_order_shadow', %s, 'test_0795')", (TWIN, v))

    def record(fn: str):
        return one(conn, f"SELECT {fn}(%s, %s, 'test-chain', 'test-model', %s::jsonb)", (run, tick, oj))

    def last_row():
        return rows(conn, "SELECT status, projection - 'per', cars, n_offered, n_accepted FROM ottoq_agent_charge_orders "
                          "WHERE sim_run_id = %s ORDER BY order_id DESC LIMIT 1", (run,))[0]

    def next_tick() -> dict:
        """One tick, and its window's digests (events, decisions, commands), as the fork test reads them."""
        lo = one(conn, "SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,))
        one(conn, "SELECT count(*) FROM public.ottoq_sim_advance_tick(%s)", (run,))
        hi = one(conn, "SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,))
        r = rows(conn, PER_TICK_SQL, {"run": run, "lo": lo, "hi": hi})[0]
        return {"evt": r[0], "n_evt": r[1], "dec": r[2], "n_dec": r[3], "cmd": r[4], "n_cmd": r[5]}

    # ── 2. at the default every patched function answers as its pre-image ──
    conn.execute("SAVEPOINT s2")
    conn.execute("SAVEPOINT s2a")
    new_rec = record("public.ottoq_agent_charge_order_record")
    new_row = last_row()
    conn.execute("ROLLBACK TO SAVEPOINT s2a")
    old_rec = record(pre["ottoq_agent_charge_order_record"])
    old_row = last_row()
    nr, orr = dict(new_rec), dict(old_rec)
    for d in (nr, orr):
        d.pop("order_id", None)
    check(nr == orr and new_row == old_row,
          f"default: the record's receipt and row are the pre-image's (status {new_rec.get('status')}, "
          f"reason {(new_rec.get('projection') or {}).get('reason')})")
    for key, args in (("ottoq_agent_charge_queue_board", "(%s, %s, %s)"), ("ottoq_agent_charge_order_usage", "(%s, 3)"),
                      ("ottoq_agent_wake", "(%s)")):
        params = {"ottoq_agent_charge_queue_board": (run, TWIN, clock), "ottoq_agent_charge_order_usage": (run,),
                  "ottoq_agent_wake": (run,)}[key]
        # each asked from the same state: the wake gate's scouts write their findings as they scan
        conn.execute("SAVEPOINT s2b")
        a = one(conn, f"SELECT public.{key}{args}", params)
        conn.execute("ROLLBACK TO SAVEPOINT s2b")
        b = one(conn, f"SELECT {pre[key]}{args}", params)
        conn.execute("ROLLBACK TO SAVEPOINT s2b")
        if key == "ottoq_agent_wake":  # the scouts' scan reports its own milliseconds
            for w in (a, b):
                (w.get("scan") or {}).pop("ms", None)
        check(a == b, f"default: {key} answers as its pre-image")
    conn.execute("ROLLBACK TO SAVEPOINT s2")

    # ── 3. with the dial, an order the check takes is 'shadow' and never stands ──
    conn.execute("SAVEPOINT s3")
    conn.execute(STUB_TAKE)
    conn.execute("SAVEPOINT s3a")
    set_dial(0)
    rec0 = record("public.ottoq_agent_charge_order_record")
    live0 = one(conn, "SELECT ottoq_agent_charge_order_live(%s, %s)", (run, tick))
    check(rec0.get("status") in ("accepted", "partial") and live0 != {},
          f"dial 0: an order the check takes is {rec0.get('status')} and stands ({len(live0)} cars live)")
    conn.execute("ROLLBACK TO SAVEPOINT s3a")
    set_dial(1)
    rec1 = record("public.ottoq_agent_charge_order_record")
    st1 = last_row()[0]
    live1 = one(conn, "SELECT ottoq_agent_charge_order_live(%s, %s)", (run, tick))
    check(rec1.get("status") == "shadow" and st1 == "shadow" and live1 == {},
          "dial 1: the same order is recorded 'shadow' and does not stand (live = {})")
    usage = one(conn, "SELECT ottoq_agent_charge_order_usage(%s, 3)", (run,))
    check(usage.get("orders_shadow") == 1 and usage.get("orders_accepted") == 0,
          f"usage counts it as shadow ({usage.get('orders_shadow')}) and not accepted")
    board1 = one(conn, "SELECT ottoq_agent_charge_queue_board(%s, %s, %s)", (run, TWIN, clock))
    check((board1.get("check") or {}).get("shadow") is True, "the board's check block says shadow: true")
    set_dial(0)
    board0 = one(conn, "SELECT ottoq_agent_charge_queue_board(%s, %s, %s)", (run, TWIN, clock))
    b1 = json.loads(json.dumps(board1, default=str))
    b1["check"].pop("shadow", None)
    check(b1 == json.loads(json.dumps(board0, default=str)), "and is otherwise the same board")
    set_dial(1)
    # the next tick with the shadow order on record decides exactly as with no order at all
    conn.execute("SAVEPOINT s3b")
    with_shadow = next_tick()
    conn.execute("ROLLBACK TO SAVEPOINT s3b")
    set_dial(0)
    conn.execute("SAVEPOINT s3d")
    record("public.ottoq_agent_charge_order_record")
    with_accepted = next_tick()
    conn.execute("ROLLBACK TO SAVEPOINT s3d")
    conn.execute("ROLLBACK TO SAVEPOINT s3")
    conn.execute("SAVEPOINT s3c")
    no_order = next_tick()
    conn.execute("ROLLBACK TO SAVEPOINT s3c")
    keys = ("evt", "n_evt", "dec", "n_dec", "cmd", "n_cmd")
    check(all(with_shadow[k] == no_order[k] for k in keys),
          f"the next tick decides as with no order: {with_shadow['n_dec']} decisions, {with_shadow['n_cmd']} "
          f"commands, {with_shadow['n_evt']} events, digests equal")
    differs = [k for k in ("evt", "dec", "cmd") if with_accepted[k] != no_order[k]]
    say(f"note  the same order accepted (dial 0) changes the next tick's {', '.join(differs) or 'nothing'}"
        + ("" if differs else " (no charger came free for it this tick)"))

    # ── 4. an order the real check refuses is 'refused' with its reason, whatever the dial ──
    conn.execute("SAVEPOINT s4")
    set_dial(1)
    recr = record("public.ottoq_agent_charge_order_record")
    reason = (recr.get("projection") or {}).get("reason")
    if recr.get("status") == "shadow":
        say(f"note  the real check took this order (reason {reason}); 'refused' is shown on a second order")
        order2 = {"cars": [{"vehicle_id": v, "kind": "either"} for v in kernel[:6]], "why": "same as kernel"}
        recr = one(conn, "SELECT ottoq_agent_charge_order_record(%s, %s, 'c2', 'm', %s::jsonb)", (run, tick, json.dumps(order2)))
        reason = (recr.get("projection") or {}).get("reason")
    check(recr.get("status") == "refused" and reason not in (None, "wins_most_futures"),
          f"dial 1: an order the check refuses stays 'refused' (reason {reason})")
    conn.execute("ROLLBACK TO SAVEPOINT s4")

    # ── 5. the grade of a shadow order: the check's take, the kernel's side for its forecast and fidelity ──
    SIDES = """SELECT g.status, g.taken, g.outcome, g.forecast, g.fidelity,
                      public.ottoq_charge_order_forecast_errors(s.state, x.real, x.ek) AS f_kernel,
                      public.ottoq_charge_order_forecast_errors(s.state, x.real, x.ea) AS f_agent,
                      public.ottoq_charge_order_fidelity(x.hk, x.real) AS d_kernel,
                      public.ottoq_charge_order_fidelity(x.ha, x.real) AS d_agent,
                      to_jsonb(g) - 'graded_at' - 'code_md5' AS g_new,
                      to_jsonb({pre}(%(o)s, 90)) - 'graded_at' - 'code_md5' AS g_pre
                 FROM public.ottoq_charge_order_grade_compute(%(o)s, 90) g
                 JOIN ottoq_charge_order_snapshots s ON s.order_id = %(o)s
                 CROSS JOIN LATERAL (
                   SELECT r.real, public.ottoq_charge_line_schedule(s.state, NULL, 0, s.seed, true) AS ek,
                          public.ottoq_charge_line_schedule(s.state, s.agent_order, 0, s.seed, true) AS ea,
                          public.ottoq_charge_line_schedule(r.full, NULL, 0, s.seed, true) AS hk,
                          public.ottoq_charge_line_schedule(r.full, s.agent_order, 0, s.seed, true) AS ha
                     FROM (SELECT q.real, public.ottoq_charge_line_realize(s.state, q.real,
                                    ARRAY['arrivals', 'appeared', 'charge_times', 'running', 'faults']) AS full
                             FROM (SELECT public.ottoq_charge_order_realized(%(o)s, 90) AS real) q) r) x
            """.format(pre=pre["ottoq_charge_order_grade_compute"])

    def graded(dial: int) -> tuple:
        conn.execute(STUB_TAKE)
        set_dial(dial)
        o = record("public.ottoq_agent_charge_order_record")["order_id"]
        arm.tick(4)  # past the 90-minute window (30-minute ticks)
        return rows(conn, SIDES, {"o": o})[0]

    conn.execute("SAVEPOINT s5")
    g = graded(1)
    conn.execute("ROLLBACK TO SAVEPOINT s5")
    st, taken, outcome, fc, fd, f_k, f_a, d_k, d_a, g_new, g_pre = g
    check(st == "shadow" and taken is True and outcome in ("right_take", "neutral_take", "wrong_take"),
          f"a shadow order is graded as the check's take ({outcome})")
    check(fc == f_k and fd == d_k, "its forecast errors and fidelity are the kernel's side's, the side the depot followed")
    check(f_k != f_a or d_k != d_a,
          "and the two sides differ here (" + ", ".join(n for n, a, b in (("forecast", f_k, f_a), ("fidelity", d_k, d_a))
                                                     if a != b) + "), so the check above can fail")
    check(g_pre["taken"] is False and g_new["taken"] is True and g_pre["outcome"] in ("missed_win", "right_refusal"),
          f"the pre-image would have graded it as a refusal ({g_pre['outcome']}); 0795 grades it as the check's take")
    # the same order accepted (dial 0) reads the agent's side and is graded exactly as before
    conn.execute("SAVEPOINT s5b")
    gb = graded(0)
    conn.execute("ROLLBACK TO SAVEPOINT s5b")
    stb, takenb, _, fcb, fdb, f_kb, f_ab, d_kb, d_ab, g_newb, g_preb = gb
    check(stb == "accepted" and takenb is True and fcb == f_ab and fdb == d_ab and g_newb == g_preb,
          "an accepted order is graded exactly as before, its forecast and fidelity on the agent's side")

    # ── 7. the wake gate: with the dial on the two order moments are counted and do not wake ──
    conn.execute("SAVEPOINT s7")
    seen: dict = {}
    for k in range(16):
        one(conn, "SELECT set_config('ottoq.sim_run_id', %s, true)", (run,))
        # a previous answered consult, one sim minute ago, so the gate compares instead of waking on first_consult
        conn.execute("""INSERT INTO ottoq_decisions (sim_run_id, tick_seq, sim_clock, depot_id, action_context,
                          resolved_action_context, entity_type, entity_id, context_frame, proposed_action, enacted_action,
                          outcome_status)
                        SELECT r.sim_run_id, r.tick_count, r.sim_clock_current - interval '1 minute', r.depot_id,
                               'task_start', 'orchestrator_agent', 'depot', r.depot_id,
                               jsonb_build_object('wake', public.ottoq_agent_wake(r.sim_run_id)),
                               '{"solver":{"objective":"readiness_first"}}'::jsonb, '{"source":"nemotron"}'::jsonb, 'enacted'
                          FROM ottoq_sim_runs r WHERE r.sim_run_id = %s""", (run,))
        set_dial(0)
        w0 = one(conn, "SELECT ottoq_agent_wake(%s)", (run,))
        set_dial(1)
        w1 = one(conn, "SELECT ottoq_agent_wake(%s)", (run,))
        r0, r1 = set(w0.get("reasons") or []), set(w1.get("reasons") or [])
        for m in ("charger_free", "due_in_line"):
            if m in r0 and m not in seen:
                seen[m] = (w0, w1)
        check(not (r1 & {"charger_free", "due_in_line"}) and r1 == r0 - {"charger_free", "due_in_line"}
              and w0["fingerprint"] == w1["fingerprint"],
              f"tick {w0.get('tick')}: dial 0 wakes for {sorted(r0) or 'nothing'}, dial 1 for {sorted(r1) or 'nothing'}, "
              f"the same fingerprint (chargers_free {w1['fingerprint'].get('chargers_free')}, "
              f"due_in_line {w1['fingerprint'].get('due_in_line')})")
        if len(seen) == 2:
            break
        arm.tick()
    check(len(seen) >= 1, f"the order moments seen waking the gate at 0: {sorted(seen)}")
    if len(seen) < 2:
        say(f"note  {({'charger_free', 'due_in_line'} - set(seen)).pop()} did not occur in 16 ticks of this day")
    w0, w1 = next(iter(seen.values()))
    check(w1.get("order_moments_wake") is False and w0.get("order_moments_wake") is True,
          "the gate says whether the order moments wake it (order_moments_wake)")
    conn.execute("ROLLBACK TO SAVEPOINT s7")

    conn.rollback()
    conn.close()
    if "--keep" not in sys.argv:
        admin.execute(f"DROP DATABASE {REPLICA}")
    admin.close()
    say(f"all checks passed in {time.time() - t0:.0f} s")


if __name__ == "__main__":
    main()
