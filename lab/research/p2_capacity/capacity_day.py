#!/usr/bin/env python3
"""One lab depot-day at a chosen fleet size, run and scored the way the engine's own throughput sweep runs a day.

The day is ottoq_throughput_sweep_arm's (0568, 0572), statement for statement where it matters, in a fresh replica of
the lab (production's engine and the twin depot's world):
  - the fleet grown to N cars by lab.grow_fleet (grow_fleet.sql) BEFORE the reset, as 0572 borrows before the reset;
  - ottoq_tick_invariance_reset_fleet(depot, seed, sim_start), harness setup belonging to no run (0421);
  - the operator's door, ottoq_sim_run_scenario(scenario, seed, 'ab_harness', sim_start), at time_scale 2 x minutes per
    tick and 30-second ticks (0520's cadence);
  - the deterministic core alone: cuOpt and the orchestrator agent quiesced, OTTO-Q's seat (0152, 0112, 0261);
  - N ticks, each in its own subtransaction;
  - scored by ottoq_throughput_scorecard (0567) before anything is torn down, plus what a capacity question needs and
    the scorecard does not carry: each owner's charge waits against its contract's max_queue_wait_minutes, how many
    cars each owner got ready by their due time, and, every half hour of the day, which resource the engine's own
    constraint board (ottoq_depot_constraint, 0783) says is the depot's wall.
The run is committed and its replica kept (--keep) so the day can be read again (E5 reads finished days).

Usage:
  /var/tmp/ottoq_lab_venv/bin/python -I lab/research/p2_capacity/capacity_day.py --fleet 150 --scenario normal_day \
      --seed 171717 [--ticks 144] [--step 5] [--sim-start '2026-09-01 11:00:00+00'] [--keep] [--out results.jsonl]
Nothing here touches production.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time

import psycopg

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
sys.path.insert(0, os.path.join(ROOT, "lab", "engine", "lib"))
from lab_run import TWIN, clone_database  # noqa: E402

HOST, PORT = os.environ.get("LAB_HOST", "/var/tmp"), int(os.environ.get("LAB_PORT", "55433"))
TEMPLATE = os.environ.get("LAB_DB", "ottoq_lab")
HERE = os.path.dirname(os.path.abspath(__file__))

OWNER_SQL = """
WITH o AS (SELECT * FROM public.ottoq_visit_outcomes(%(run)s)),
     w AS (  -- each visit's first charge after it arrived, and when its car reached the gate
       SELECT o.visit_id, o.vehicle_id, o.arrived_at,
              (SELECT min(s.started_at) FROM ocpp_sessions s
                WHERE s.sim_run_id = %(run)s AND s.vehicle_id = o.vehicle_id AND s.started_at >= o.arrived_at
                  AND (o.departed_at IS NULL OR s.started_at <= o.departed_at)) AS plugged_at,
              -- 2026-11-06: a visit opens when its car is CALLED HOME, most of them while it drives; the contract's
              -- queue wait is the wait in the depot's charge queue, from the gate (the engine's own clock,
              -- ottoq_charge_wait_min, starts there). wait_* below keep the first measure, from the call; wait_gate_*
              -- and over_contract_wait_gate are the contract's. A car in the depot when its visit opened is at the gate.
              COALESCE((SELECT min(e.sim_clock_at) FROM ottoq_events e
                         WHERE e.entity_type = 'vehicle' AND e.entity_id = o.vehicle_id AND e.event_type = 'vehicle.state_changed'
                           AND COALESCE(e.payload->>'to', e.payload->'diff'->'current_state'->>'to') = 'arrived_at_gate'
                           AND e.sim_clock_at >= o.arrived_at AND (o.departed_at IS NULL OR e.sim_clock_at <= o.departed_at)),
                       CASE WHEN (SELECT COALESCE(e.payload->>'to', e.payload->'diff'->'current_state'->>'to')
                                    FROM ottoq_events e WHERE e.entity_type = 'vehicle' AND e.entity_id = o.vehicle_id AND e.event_type = 'vehicle.state_changed'
                                     AND e.sim_clock_at <= o.arrived_at AND (e.payload ? 'to' OR e.payload->'diff' ? 'current_state')
                                   ORDER BY e.sim_clock_at DESC, e.event_seq DESC LIMIT 1)
                                 NOT IN ('deployed', 'en_route_to_depot', 'en_route_to_deployment', 'offline', 'tow_requested')
                            THEN o.arrived_at END) AS gate_at
         FROM o),
     sla AS (
       SELECT DISTINCT ON (s.fleet_operator_id) s.fleet_operator_id, s.max_queue_wait_minutes
         FROM ottoq_fleet_operator_slas s WHERE s.status = 'active' ORDER BY s.fleet_operator_id, s.version DESC)
SELECT fo.name AS owner, count(*) AS visits,
       count(*) FILTER (WHERE o.departed_at IS NOT NULL) AS served,
       count(*) FILTER (WHERE o.in_depot_at_horizon) AS in_depot_at_horizon,
       count(*) FILTER (WHERE o.due_at IS NOT NULL) AS with_due,
       count(*) FILTER (WHERE o.on_time) AS on_time,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY o.door_min)::numeric, 1) AS door_p50_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY o.door_min)::numeric, 1) AS door_p95_min,
       count(w.plugged_at) AS charged,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (w.plugged_at - w.arrived_at)) / 60.0)::numeric, 1) AS wait_p50_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY extract(epoch FROM (w.plugged_at - w.arrived_at)) / 60.0)::numeric, 1) AS wait_p95_min,
       count(*) FILTER (WHERE extract(epoch FROM (w.plugged_at - w.arrived_at)) / 60.0 > sla.max_queue_wait_minutes) AS over_contract_wait,
       round(percentile_cont(0.5) WITHIN GROUP (ORDER BY extract(epoch FROM (w.plugged_at - COALESCE(w.gate_at, w.arrived_at))) / 60.0)::numeric, 1) AS wait_gate_p50_min,
       round(percentile_cont(0.95) WITHIN GROUP (ORDER BY extract(epoch FROM (w.plugged_at - COALESCE(w.gate_at, w.arrived_at))) / 60.0)::numeric, 1) AS wait_gate_p95_min,
       count(*) FILTER (WHERE extract(epoch FROM (w.plugged_at - COALESCE(w.gate_at, w.arrived_at))) / 60.0 > sla.max_queue_wait_minutes) AS over_contract_wait_gate,
       max(sla.max_queue_wait_minutes) AS contract_wait_min,
       sum(o.needed_open_at_departure) AS needed_open_at_departure,
       count(*) FILTER (WHERE o.departed_at IS NOT NULL AND o.soc_out < o.target_soc - 1) AS left_below_target
  FROM o JOIN vehicles v ON v.id = o.vehicle_id
  JOIN fleet_operators fo ON fo.id = v.fleet_operator_id
  LEFT JOIN w USING (visit_id)
  LEFT JOIN sla ON sla.fleet_operator_id = v.fleet_operator_id
 GROUP BY 1 ORDER BY 1
"""

RESOURCE_SQL = """
WITH st AS (SELECT s.id, s.stall_type::text AS kind FROM stalls s WHERE s.depot_id = %(depot)s),
     b AS (SELECT st.kind, sum(extract(epoch FROM (LEAST(upper(k.during), %(hi)s) - GREATEST(lower(k.during), %(lo)s)))) / 60.0 AS busy_min
             FROM ottoq_stall_bookings k JOIN st ON st.id = k.stall_id
            WHERE k.sim_run_id = %(run)s AND k.state IN ('active', 'done', 'interrupted')
              AND k.during && tstzrange(%(lo)s, %(hi)s)
            GROUP BY 1)
SELECT st.kind, count(*) AS units, round(COALESCE(max(b.busy_min), 0)::numeric, 0) AS busy_min,
       round((100.0 * COALESCE(max(b.busy_min), 0) / NULLIF(count(*) * extract(epoch FROM (%(hi)s::timestamptz - %(lo)s::timestamptz)) / 60.0, 0))::numeric, 1) AS busy_pct
  FROM st LEFT JOIN b USING (kind) GROUP BY st.kind ORDER BY 1
"""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--fleet", type=int, required=True)
    ap.add_argument("--scenario", default="normal_day")
    ap.add_argument("--seed", type=int, default=171717)
    ap.add_argument("--ticks", type=int, default=144)
    ap.add_argument("--step", type=float, default=5.0, help="sim minutes per tick")
    ap.add_argument("--sim-start", default="2026-09-01 11:00:00+00")
    ap.add_argument("--sample-every", type=int, default=6, help="ticks between constraint-board samples")
    ap.add_argument("--dial", action="append", default=[],
                    help="key=value, a run-scoped dial for this day (a lab arm's own variation, e.g. energy_reserve_shave=0)")
    ap.add_argument("--tag", default="", help="appended to the replica's name, to keep variations apart")
    ap.add_argument("--add-stall", action="append", default=[],
                    help="type=n: n more stalls of that type (a copy of the depot's last one of it), for this lab day "
                         "only, e.g. service_bay=1")
    ap.add_argument("--lab-sql", action="append", default=[],
                    help="a SQL file run on this day's replica before its first tick (a what-if change to the engine, "
                         "for this lab day only), recorded with its md5")
    ap.add_argument("--battery-lp", metavar="SHAPE_JSON",
                    help="plan the battery as a linear program over the rest of the day, every tick, on this forecast "
                         "shape (make_load_shape.py), and have the engine follow it (energy_mpc_follow = 1): battery_lp.py")
    ap.add_argument("--battery-lp-dr-kwh", type=float, default=600.0,
                    help="the demand-response reserve the linear program holds from 2 PM (the day plan's 600)")
    ap.add_argument("--battery-lp-learned", metavar="MODEL_JSON",
                    help="the planner forecasts the next four hours' EV charging with this learned model "
                         "(forecast_learn.py --save), the shape beyond (battery_lp.py)")
    ap.add_argument("--battery-lp-band-hh", type=int,
                    help="with --battery-lp-learned: the model's upper band only for the next N half hours, its mean beyond")
    ap.add_argument("--battery-lp-bill-from-min", type=float, default=0.0,
                    help="a second billing period from this many minutes after the start (set bess_plan_bill_from_min "
                         "to the same for the day plan)")
    ap.add_argument("--battery-lp-blend", action="store_true",
                    help="forecast each step at least at what the engine knows is coming (the day plan's known sessions, "
                         "returns and queue, its building profile and solar), the shape beyond it (battery_lp.py)")
    ap.add_argument("--log-forecast", metavar="JSONL",
                    help="after every tick, read the battery day plan's own forecast (ottoq_bess_day_plan, read-only) at the "
                         "run's clock and append it to this file, to grade it against what the depot then drew")
    ap.add_argument("--battery-lp-no-guard", action="store_true",
                    help="plan to the edge of the billed peak on the shape alone (the first cut, which ratcheted it)")
    ap.add_argument("--one-transaction", action="store_true",
                    help="run the whole day in one transaction, a savepoint a tick (the mode before 2026-11-06): its row "
                         "versions and subtransactions pile up and its late ticks slow. By default a day commits after "
                         "the set-up and after every tick, as production does; on normal_day 116 cars seed 424242 both "
                         "modes give the same four fingerprints (day_fingerprint.sql), in 414 s against 1,080 s")
    ap.add_argument("--commit-each-tick", action="store_true", help="the default; kept so older job lists still parse")
    ap.add_argument("--keep", action="store_true")
    ap.add_argument("--out", default=os.path.join(HERE, "results.jsonl"))
    a = ap.parse_args()

    db = f"ottoq_cap_{a.scenario}_{a.fleet}_{a.seed}" + (f"_{a.tag}" if a.tag else "")
    admin = psycopg.connect(host=HOST, port=PORT, user="postgres", dbname="postgres", autocommit=True)
    if admin.execute("SELECT count(*) FROM pg_database WHERE datname = %s", (db,)).fetchone()[0]:
        # FORCE: a day killed mid-run leaves its backend rolling back for minutes, holding the replica (2026-11-06)
        admin.execute(f"DROP DATABASE {db} WITH (FORCE)")
    clone_s = clone_database(admin, TEMPLATE, db)
    conn = psycopg.connect(host=HOST, port=PORT, user="postgres", dbname=db, autocommit=False)

    def one(sql, p=None):
        r = conn.execute(sql, p).fetchone()
        return r[0] if r else None

    conn.execute(open(os.path.join(HERE, "grow_fleet.sql")).read())
    grown = one("SELECT lab.grow_fleet(%s, %s)", (TWIN, a.fleet))
    added = {}
    added_kw = 0.0
    for kv in a.add_stall:   # a what-if site: more of one kind of stall, copied from the depot's own
        kind, _, nstr = kv.partition("=")
        # the source: the depot's last stall of that kind as built, never a lab copy (2026-11-06: with n > 1 the copies
        # used to copy the copy before; one service bay, as every earlier day added, is unchanged by this)
        src = one("SELECT s.id FROM stalls s WHERE s.depot_id = %(d)s AND s.stall_type::text = %(k)s "
                  "AND s.stall_code NOT LIKE '%%-LAB%%' ORDER BY s.stall_code DESC LIMIT 1", {"d": TWIN, "k": kind})
        if src is None:
            raise SystemExit(f"--add-stall {kv}: the depot has no {kind} to copy")
        for i in range(int(nstr)):
            p = {"i": i, "src": src}
            # 2026-11-06: a charging post is its stall and its own charger (each of the depot's 30 posts has one): the
            # charger is a copy of the source post's, with its own id and identifier, available and fault-free
            p["ch"] = None
            if kind in ("dcfc", "l2"):
                row = conn.execute("""INSERT INTO ottoq_ocpp_chargers
                                      SELECT (jsonb_populate_record(NULL::ottoq_ocpp_chargers, to_jsonb(c)
                                              || jsonb_build_object('charger_id', md5('lab-charger:' || c.charger_id || ':' || %(i)s)::uuid,
                                                                    'ocpp_identifier', c.ocpp_identifier || '-LAB' || (%(i)s + 1),
                                                                    'serial_number', COALESCE(c.serial_number, '') || '-LAB' || (%(i)s + 1),
                                                                    'station_state', 'Available', 'last_fault_code', NULL,
                                                                    'last_fault_at', NULL, 'last_fault_payload', NULL))).*
                                        FROM ottoq_ocpp_chargers c JOIN stalls s ON s.ocpp_charger_id = c.charger_id
                                       WHERE s.id = %(src)s
                                      RETURNING charger_id, max_kw""", p).fetchone()
                if row is None:
                    raise SystemExit(f"--add-stall {kv}: the source post has no charger to copy")
                p["ch"] = str(row[0])
                added_kw += float(row[1] or 0)
            new_id = one("""INSERT INTO stalls
                            SELECT (jsonb_populate_record(NULL::stalls, to_jsonb(s)
                                    || jsonb_build_object('id', md5('lab-stall:' || s.id || ':' || %(i)s)::uuid,
                                                          'stall_code', s.stall_code || '-LAB' || (%(i)s + 1),
                                                          'display_name', COALESCE(s.display_name, s.stall_code) || ' (lab)',
                                                          'relative_x', COALESCE(s.relative_x, 0) + 12 * (%(i)s + 1),
                                                          'ocpp_charger_id', %(ch)s::uuid,
                                                          'current_vehicle_id', NULL, 'reserved_by', NULL,
                                                          'reserved_at', NULL, 'reservation_expires_at', NULL,
                                                          'status', 'available'))).*
                              FROM stalls s WHERE s.id = %(src)s
                            RETURNING id""", p)
            # and its service-point capabilities, as the source's (read by the site build-outs only, kept faithful)
            conn.execute("""INSERT INTO ottoq_service_point_capabilities
                            SELECT (jsonb_populate_record(NULL::ottoq_service_point_capabilities, to_jsonb(k)
                                    || jsonb_build_object('stall_id', %(new)s::uuid, 'source', 'lab_capacity'))).*
                              FROM ottoq_service_point_capabilities k WHERE k.stall_id = %(src)s""",
                         {"new": str(new_id), "src": src})
        added[kind] = int(nstr)
    if added_kw > 0:
        # rule 13: a depot's power limits are what is installed; the added chargers are installed with their power
        conn.execute("UPDATE depots SET dcfc_max_concurrent_kw = COALESCE(dcfc_max_concurrent_kw, 0) + %(kw)s, "
                     "service_max_kw = COALESCE(service_max_kw, 0) + %(kw)s WHERE id = %(d)s", {"kw": added_kw, "d": TWIN})
        added["kw"] = added_kw
    one("SELECT set_config('ottoq.sim_run_id', 'none', true)")
    conn.execute("SELECT public.ottoq_tick_invariance_reset_fleet(%s, %s, %s)", (TWIN, a.seed, a.sim_start))
    one("SELECT set_config('ottoq.sim_run_id', '', true)")
    run = str(one("SELECT public.ottoq_sim_run_scenario(%s, %s, 'ab_harness', %s)", (a.scenario, a.seed, a.sim_start)))
    one("SELECT set_config('ottoq.sim_run_id', %s, true)", (run,))
    conn.execute("UPDATE ottoq_sim_runs SET time_scale = %s, tick_interval_seconds = 30, "
                 "payload = COALESCE(payload, '{}'::jsonb) || jsonb_build_object('lab_capacity', %s::jsonb) "
                 "WHERE sim_run_id = %s", (2 * a.step, json.dumps({"fleet": a.fleet, "grown": grown}), run))
    conn.execute("""INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
                    VALUES ('run', %(r)s, 'cuopt_propose_enabled', 0, 'lab_capacity'),
                           ('run', %(r)s, 'cuopt_first_refusal_max_defers', 0, 'lab_capacity'),
                           ('run', %(r)s, 'orchestrator_agent_enabled', 0, 'lab_capacity'),
                           ('run', %(r)s, 'proposer_seat', 0, 'lab_capacity')
                    ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
                      SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by""", {"r": run})
    dials = {}
    for kv in a.dial:
        k, _, v = kv.partition("=")
        dials[k] = float(v)
        conn.execute("""INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
                        VALUES ('run', %s, %s, %s, 'lab_capacity_variation')
                        ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
                          SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by""", (run, k, float(v)))
    lp = None
    if a.battery_lp:         # the battery planned as a linear program, followed through the MPC bridge (battery_lp.py)
        sys.path.insert(0, HERE)
        from battery_lp import BatteryLP, load_shape  # noqa: E402
        conn.execute("""INSERT INTO ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
                        VALUES ('run', %s, 'energy_mpc_follow', 1, 'lab_capacity_variation')
                        ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE
                          SET param_value = EXCLUDED.param_value, updated_by = EXCLUDED.updated_by""", (run,))
        dials["energy_mpc_follow"] = 1.0
        lp = BatteryLP(conn, run, a.step, a.ticks, load_shape(a.battery_lp), dr_kwh=a.battery_lp_dr_kwh,
                       guard=not a.battery_lp_no_guard, blend=a.battery_lp_blend, learned=a.battery_lp_learned,
                       band_hh=a.battery_lp_band_hh, bill_from_min=a.battery_lp_bill_from_min)
    patches = {}
    for f in a.lab_sql:      # a what-if change to the engine, on this replica only
        body = open(f).read()
        conn.execute(body)
        patches[os.path.basename(f)] = hashlib.md5(body.encode()).hexdigest()
    t0 = time.time()
    walls, err, ticks = [], None, 0
    commit_mode = not a.one_transaction
    if commit_mode:   # the set-up, the run and every what-if land before the first tick
        conn.commit()
    for k in range(a.ticks):
        st = conn.execute("SELECT status, tick_count, sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s",
                          (run,)).fetchone()
        if st[0] != "running":
            break
        if lp is not None:
            lp.plan_now(k)
        if commit_mode:
            try:
                conn.execute("SELECT count(*) FROM public.ottoq_sim_advance_tick(%s)", (run,))
                conn.commit()
                ticks += 1
            except psycopg.Error as e:
                conn.rollback()
                err = {"tick": st[1] + 1, "error": str(e)[:400]}
                break
        else:
            conn.execute("SAVEPOINT t")
            try:
                conn.execute("SELECT count(*) FROM public.ottoq_sim_advance_tick(%s)", (run,))
                conn.execute("RELEASE SAVEPOINT t")
                ticks += 1
            except psycopg.Error as e:
                conn.execute("ROLLBACK TO SAVEPOINT t")
                err = {"tick": st[1] + 1, "error": str(e)[:400]}
                break
        if a.log_forecast:   # the day plan's forecast as it stands after this tick (a STABLE read; changes nothing)
            fl = conn.execute("""SELECT r.sim_clock_current, public.ottoq_bess_day_plan(r.sim_run_id, %s, r.sim_clock_current, NULL)
                                   FROM ottoq_sim_runs r WHERE r.sim_run_id = %s""", (TWIN, run)).fetchone()
            if commit_mode:
                conn.commit()
            f = (fl[1] or {}).get("forecast") or {}
            # the known term's first loop alone (the cars on a charger now, each held at its starting rate until its
            # energy is in, ottoq_forecast_ev_known_kw loop 1, verbatim), to grade it apart from the second (cars coming
            # home, each charged from its arrival whether or not a post is free)
            act = [0.0] * len(f.get("ev_known_kw") or [])
            for rate, kwh in conn.execute("""
                    SELECT GREATEST(ottoq_sim_compute_charge_rate(
                             p_soc_pct := v.current_soc, p_battery_temp_c := COALESCE(s.ambient_temp_c,22)+5,
                             p_ambient_temp_c := COALESCE(s.ambient_temp_c,22), p_charger_max_kw := ch.max_kw,
                             p_vehicle_max_kw := v.inlet_max_kw, p_battery_capacity_kwh := v.battery_capacity_kwh,
                             p_battery_soh_pct := 95, p_noise_seed := 1, p_noise_salt := s.vehicle_id::text), 1),
                           GREATEST(0,(COALESCE(v.target_soc, public.ottoq_default_target_soc())-v.current_soc)/100.0
                                      *COALESCE(v.battery_capacity_kwh,75))
                      FROM ocpp_sessions s JOIN stalls st ON st.id=s.stall_id
                      JOIN ottoq_ocpp_chargers ch ON ch.charger_id=st.ocpp_charger_id
                      JOIN vehicles v ON v.id=s.vehicle_id
                     WHERE s.status='active' AND s.sim_run_id=%s""", (run,)).fetchall():
                dur = float(kwh) / float(rate) * 60.0
                for h in range(len(act)):
                    if h * 30.0 < dur:
                        act[h] += float(rate)
            if commit_mode:
                conn.commit()
            with open(a.log_forecast, "a") as fh:
                fh.write(json.dumps({"db": db, "run": run, "k": k + 1, "clock": str(fl[0]),
                                     **{key: f.get(key) for key in ("net_kw", "ev_kw", "ev_known_kw", "ev_queue_kw",
                                                                    "base_kw", "solar_kw")},
                                     "ev_active_kw": [round(x) for x in act],
                                     "ev_persist_kw": (fl[1] or {}).get("ev_persist_kw"),
                                     "mode": (fl[1] or {}).get("mode"), "level_kw": (fl[1] or {}).get("level_kw")}) + "\n")
        if (k + 1) % 12 == 0:
            print(f"tick {k + 1}/{a.ticks} at {time.time() - t0:.0f} s", flush=True)
        if (k + 1) % a.sample_every == 0:
            clock = one("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,))
            try:
                conn.execute("SAVEPOINT c")
                c = one("SELECT public.ottoq_depot_constraint(%s, %s, %s)", (run, TWIN, clock))
                conn.execute("RELEASE SAVEPOINT c")
                walls.append({"clock": str(clock), "wall": (c or {}).get("wall"),
                              "resources": (c or {}).get("resources")})
            except psycopg.Error as e:
                conn.execute("ROLLBACK TO SAVEPOINT c")
                walls.append({"clock": str(clock), "error": str(e)[:200]})
    wall_s = round(time.time() - t0, 1)
    lo, hi = one("SELECT sim_clock_start FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,)), \
        one("SELECT sim_clock_current FROM ottoq_sim_runs WHERE sim_run_id = %s", (run,))
    # 2026-11-06: the planner's statistics before the day's readers. A day's tables are written from a template's tiny
    # ones and autovacuum may not have analyzed them yet when the last tick commits; planned on those statistics the
    # owners' readers ran over eight minutes on a 24-hour day, against 0.6 s once analyzed
    if commit_mode:
        conn.commit()
        conn.autocommit = True
        for tbl in ("ottoq_events", "ottoq_visit_needs", "ocpp_sessions", "ottoq_stall_bookings", "ottoq_vehicle_dispatches"):
            conn.execute(f"ANALYZE {tbl}")
        conn.autocommit = False
    score = one("SELECT public.ottoq_throughput_scorecard(%s)", (run,))
    cols = None
    with conn.cursor() as cur:
        cur.execute(OWNER_SQL, {"run": run})
        cols = [d.name for d in cur.description]
        owners = [dict(zip(cols, r)) for r in cur.fetchall()]
        cur.execute(RESOURCE_SQL, {"run": run, "depot": TWIN, "lo": lo, "hi": hi})
        cols = [d.name for d in cur.description]
        resources = [dict(zip(cols, r)) for r in cur.fetchall()]
    conn.commit()
    conn.close()
    out = {"db": db, "run": run, "template": TEMPLATE, "scenario": a.scenario, "seed": a.seed, "fleet": a.fleet, "grown": grown,
           "dials": dials, "tag": a.tag, "added_stalls": added, "lab_sql": patches,
           "battery_lp": ({"shape": os.path.basename(a.battery_lp), "dr_kwh": a.battery_lp_dr_kwh, "plans": lp.plans,
                           "blend": a.battery_lp_blend, "learned": a.battery_lp_learned, "band_hh": a.battery_lp_band_hh, "bill_from_min": a.battery_lp_bill_from_min,
                           "guard": lp.guard}
                          if lp is not None else None),
           "ticks": ticks, "commit_each_tick": commit_mode, "step_min": a.step, "sim_start": a.sim_start, "wall_s": wall_s, "clone_s": round(clone_s, 1),
           "error": err, "scorecard": score, "owners": owners, "resources": resources, "walls": walls}
    with open(a.out, "a") as f:
        f.write(json.dumps(out, default=str) + "\n")
    if not a.keep:
        admin.execute(f"DROP DATABASE {db}")
    admin.close()
    tp = (score or {}).get("throughput", {})
    tl = (score or {}).get("timeliness", {})
    print(f"{a.scenario} fleet {a.fleet} seed {a.seed}: {ticks} ticks in {wall_s} s; visits {tp.get('visits')}, served "
          f"{tp.get('visits_served')}, in depot at horizon {tp.get('in_depot_at_horizon')}, on time "
          f"{tl.get('on_time')}/{tl.get('due_served')}; error {err}", flush=True)


if __name__ == "__main__":
    main()
