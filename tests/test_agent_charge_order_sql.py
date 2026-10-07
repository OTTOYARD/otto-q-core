"""db/migrations/0614, EXECUTED: the agent can order the charge line, and the decide path disposes.

WHY THIS EXISTS. 0614 gives the agent a lever that changes who charges next and on which kind of charger, and it is
classified forces_recert FALSE on one claim: at the dial's default nothing on the tick path moves. That claim, and
every guard the header says holds by construction, are executed here against the live functions' own source
(tests/fixtures/agent_charge_order_stub.sql carries the five 0614 patches byte for byte):

  - at the default the cockpits' queue is the one before 0614;
  - under a live order the line is: immediate dispatch, then cars waited past the pin (kernel order), then the agent's
    ranking with the kind of charger free now first, then everyone else in the kernel's order;
  - the door records nothing when the dial is off, on a baseline seat, or on a run that is not running, and drops a
    duplicate, junk or a car not waiting with its reason;
  - an order expires after its ttl;
  - the stall pick takes the kind the order names, except for an immediate dispatch;
  - the usage read counts what the orders did.

It SKIPS where no scratch PostgreSQL is reachable, like tests/test_charge_batch_order_sql.py.
"""
import json
import os
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "agent_charge_order_stub.sql")
M0614 = os.path.join(ROOT, "db", "migrations",
                     "0614_the_agent_can_order_the_charge_line_and_the_decide_path_disposes.sql")
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000614"
OPERATOR = "33333333-3333-3333-3333-333333333333"
T = "2026-10-07 14:40:00+00"


def _conn_args():
    if os.environ.get("PGHOST"):
        return ["-h", os.environ["PGHOST"], "-p", os.environ.get("PGPORT", "5432"),
                "-U", os.environ.get("PGUSER", "postgres")]
    return ["-h", "/var/tmp", "-p", "55432", "-U", "postgres"]


def _server_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-Atc", "select 1"], capture_output=True, text=True)
    return p.returncode == 0


pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


class Db:
    def __init__(self, name):
        self.name = name

    def run(self, sql):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
                           capture_output=True, text=True)
        return p.returncode, [l for l in p.stdout.splitlines() if l.strip()], p.stderr

    def val(self, sql):
        rc, out, err = self.run(sql)
        if rc != 0:
            raise AssertionError(f"SQL failed: {err}\n--- sql ---\n{sql}")
        return out[-1] if out else ""

    def json(self, sql):
        return json.loads(self.val(sql))

    def file(self, path):
        p = subprocess.run(["psql", *_conn_args(), "-d", self.name, "-q", "-v", "ON_ERROR_STOP=1", "-f", path],
                           capture_output=True, text=True)
        return p.returncode, p.stderr


def _vid(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0614-{name}"))


NAMES = {}


def _stall(d, code, kind, kw):
    sid = _vid(code)
    d.val(f"""INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, station_state, last_heartbeat_at)
              VALUES ('{sid}', '{DEPOT}', 'Available', '{T}')""")
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, display_name, ocpp_charger_id, connector_type,
                                         supported_inlet_types, connector_max_kw, relative_y)
              VALUES ('{sid}', '{DEPOT}', '{kind}', '{code}', '{code}', '{sid}', 'Multi', ARRAY['NACS','CCS1'], {kw},
                      {len(code)})""")
    return sid


def _car(d, name, soc, wait_min, urgency="standard", state="arrived_at_gate", inlet="NACS"):
    vid = _vid(name)
    NAMES[vid] = name
    d.val(f"""INSERT INTO public.vehicles (id, fleet_operator_id, home_depot_id, category, display_name, current_soc,
                                           battery_capacity_kwh, inlet_type, inlet_max_kw, current_state, last_state_change)
              VALUES ('{vid}', '{OPERATOR}', '{DEPOT}', 'autonomous', '{name}', {soc}, 75, '{inlet}', 250, '{state}',
                      '{T}'::timestamptz - interval '{wait_min} minutes')""")
    due = f"'{T}'::timestamptz + interval '40 minutes'" if urgency == "immediate_dispatch" else "NULL"
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, visit_key, status, urgency, dispatch_due_at,
                                                    target_soc, atoms, created_at)
              VALUES ('{vid}', '{RUN}', '{DEPOT}', '{name}', 'open', '{urgency}', {due}, 100,
                      '[{{"svc":"charge","est_min":48}},{{"svc":"exterior_wash","est_min":12,"concurrency":"bay"}}]', '{T}')""")
    return vid


def _world(d):
    """A busy line in miniature. Kernel ratio order: I (immediate), P (waited 120, ratio 5.0), B 1.875, A 1.8, D 1.667,
    C 1.286. Two fast chargers and three L2 are free."""
    d.val(f"INSERT INTO public.fleet_operators (id, name) VALUES ('{OPERATOR}', 'Tesla Robotaxi TN')")
    d.val(f"""INSERT INTO public.ottoq_fleet_operator_slas (fleet_operator_id, status, version, effective_from,
                                                            max_queue_wait_minutes, max_charge_target_pct)
              VALUES ('{OPERATOR}', 'active', 1, '2026-01-01', 30, 100)""")
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, started_at,
                                                 run_by, policy)
              VALUES ('{RUN}', '{DEPOT}', 'running', 100, '{T}', now(), 'operator_demo', 'otto_q')""")
    _stall(d, "F1", "dcfc", 150)
    _stall(d, "F2", "dcfc", 150)
    for code in ("L1", "L2", "L3"):
        _stall(d, code, "l2", 19.2)
    _car(d, "A", 50, 40)
    _car(d, "B", 60, 35)
    _car(d, "C", 30, 20)
    _car(d, "D", 85, 10)
    _car(d, "P", 70, 120)
    _car(d, "I", 40, 5, urgency="immediate_dispatch")
    # a car out at work: not in the line
    _car(d, "X", 20, 0, state="deployed")


@pytest.fixture()
def db():
    name = f"ottoq_aco_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        _world(d)
        yield d
    finally:
        subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"],
                       capture_output=True)


def _apply(d):
    rc, err = d.file(M0614)
    assert rc == 0, f"0614 did not apply: {err}"
    return err


def _line(d):
    """The charge line as the cockpits read it, by car name."""
    rows = d.json(f"""SELECT COALESCE(jsonb_agg(q.vehicle_id ORDER BY q.queue_position), '[]')
                        FROM public.ottoq_depot_queue('{DEPOT}', '{RUN}') q WHERE q.queue_kind = 'charge'""")
    return [NAMES[v] for v in rows]


def _dial(d, key, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params VALUES ('run', '{RUN}', '{key}', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _order(d, cars, why="test"):
    payload = json.dumps({"cars": [{"vehicle_id": _vid(n) if len(n) <= 2 else n, "kind": k, "why": f"{n} {k}"}
                                   for n, k in cars], "why": why})
    return d.json(f"SELECT public.ottoq_agent_charge_order_record('{RUN}', 99, 'chain-t', 'test-model', $j${payload}$j$::jsonb)")


def _occupy(d, codes):
    """Put a car out at work on each named stall (the pointer gate), so only the others are free."""
    for code in codes:
        d.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('X')}' WHERE stall_code = '{code}'")


# ── the migration, with a live run present, so V4, V5 and V6 execute ──────────────────────────────────────────────────

def test_0614_applies_and_its_checks_run_on_a_live_run(db):
    err = _apply(db)
    assert "0614 V4/V5 on run" in err and "queue unchanged at the default" in err, err
    assert "0614 V6 (rolled back): v6_rollback:pass:" in err, err
    # V6 rolled itself back: no dial and no order outlived it
    assert db.val(f"SELECT count(*) FROM public.ottoq_policy_params WHERE param_key = 'agent_charge_order'") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_agent_charge_orders") == "0"
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name LIKE '0614_%'") == "falsefalse"


def test_at_the_default_nothing_moves(db):
    before = _line(db)
    _apply(db)
    assert _line(db) == before == ["I", "P", "B", "A", "D", "C"]
    # an order recorded anyway (it cannot be: the door refuses) would change nothing at 0
    assert _order(db, [("C", "either")])["skipped"] == "agent_charge_order is 0 for this run"
    assert _line(db) == before


# ── the line under a live order ───────────────────────────────────────────────────────────────────────────────────────

def test_the_line_follows_the_agent_after_immediate_and_pinned(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    r = _order(db, [("C", "either"), ("D", "either"), ("A", "either"), ("B", "either")])
    assert r["ok"] and r["status"] == "accepted" and r["accepted"] == 4, r
    # immediate dispatch first, then P (waited 120 >= the 90-minute pin) in the kernel's order, then the agent's order
    assert _line(db) == ["I", "P", "C", "D", "A", "B"]
    # the pin is a dial: at 150, P is just another car and goes where the agent ranks it (unranked: after the ranked)
    _dial(db, "agent_charge_order_pin_wait_min", 150)
    assert _line(db) == ["I", "C", "D", "A", "B", "P"]


def test_the_kind_of_charger_free_now_goes_first(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    _order(db, [("A", "l2"), ("C", "dcfc"), ("D", "l2"), ("B", "either")])
    # both kinds free: the agent's ranks
    assert _line(db) == ["I", "P", "A", "C", "D", "B"]
    # only fast chargers free: the cars named for one (or either) first, then the cars named for an L2
    _occupy(db, ["L1", "L2", "L3"])
    assert db.val(f"SELECT public.ottoq_agent_charge_order_mode('{RUN}', '{DEPOT}', '{T}')") == "dcfc"
    assert _line(db) == ["I", "P", "C", "B", "A", "D"]
    # only L2 free: the reverse
    db.val("UPDATE public.stalls SET current_vehicle_id = NULL")
    _occupy(db, ["F1", "F2"])
    assert _line(db) == ["I", "P", "A", "D", "B", "C"]


def test_an_order_expires_after_its_ttl(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    _order(db, [("C", "either")])
    live = lambda tick: db.json(f"SELECT public.ottoq_agent_charge_order_live('{RUN}', {tick})")
    assert _vid("C") in live(100) and _vid("C") in live(115)
    assert live(116) == {} and live(99) == {}
    _dial(db, "agent_charge_order_ttl_ticks", 3)
    assert live(103) != {} and live(104) == {}


# ── the door ──────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_door_keeps_only_cars_waiting_and_says_why(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    r = _order(db, [("C", "dcfc"), ("C", "l2"), ("X", "l2"), ("not-a-car", "dcfc"), ("A", "fast"), ("B", "L2")])
    assert r["status"] == "partial" and r["offered"] == 6 and r["accepted"] == 3, r
    reasons = sorted(x["reason"] for x in r["dropped"])
    assert reasons == ["duplicate", "not_a_vehicle_id", "not_waiting_for_a_charger"], r
    cars = db.json("SELECT cars FROM public.ottoq_agent_charge_orders ORDER BY order_id DESC LIMIT 1")
    assert [(NAMES[c["vehicle_id"]], c["rank"], c["kind"]) for c in cars] == [("C", 1, "dcfc"), ("A", 2, "either"), ("B", 3, "l2")]
    # an empty order is recorded as rejected, so the pass's failure is on the record
    assert _order(db, [])["status"] == "rejected"


def test_a_kind_the_car_cannot_plug_into_is_the_kernels_to_pick(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    db.val(f"UPDATE public.stalls SET supported_inlet_types = ARRAY['NACS'] WHERE stall_type = 'dcfc'")
    db.val(f"UPDATE public.vehicles SET inlet_type = 'J1772' WHERE id = '{_vid('A')}'")
    db.val(f"UPDATE public.stalls SET supported_inlet_types = ARRAY['NACS','J1772'] WHERE stall_type = 'l2'")
    _order(db, [("A", "dcfc")])
    cars = db.json("SELECT cars FROM public.ottoq_agent_charge_orders ORDER BY order_id DESC LIMIT 1")
    assert cars[0]["kind"] == "either"


def test_the_door_records_nothing_off_its_run(db):
    _apply(db)
    assert _order(db, [("C", "either")])["skipped"] == "agent_charge_order is 0 for this run"
    _dial(db, "agent_charge_order", 1)
    _dial(db, "proposer_seat", 1)
    assert _order(db, [("C", "either")])["skipped"] == "a baseline seat owns this run"
    _dial(db, "proposer_seat", 0)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    assert _order(db, [("C", "either")])["skipped"] == "run_not_running"
    assert db.val("SELECT count(*) FROM public.ottoq_agent_charge_orders") == "0"


def test_the_ledger_is_append_only(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    _order(db, [("C", "either")])
    rc, _, err = db.run("UPDATE public.ottoq_agent_charge_orders SET status = 'rejected'")
    assert rc != 0 and "append-only" in err
    rc, _, err = db.run("DELETE FROM public.ottoq_agent_charge_orders")
    assert rc != 0 and "append-only" in err


# ── what the agent sees, and what the orders did ──────────────────────────────────────────────────────────────────────

def test_the_board_carries_the_line_with_what_each_car_owes(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    _order(db, [("C", "dcfc")])
    b = db.json(f"SELECT public.ottoq_agent_charge_queue_board('{RUN}', '{DEPOT}', '{T}')")
    names = [c["name"] for c in b["cars"]]
    assert names == ["I", "P", "B", "A", "D", "C"]            # the kernel's own order: the agent sees the default
    c = b["cars"][names.index("C")]
    assert c["min_on_dcfc"] < c["min_on_l2"] and c["rule_kind"] == "dcfc" and c["kwh_owed"] == 52.5
    a = b["cars"][names.index("A")]
    assert a["over_limit_min"] == 10 and a["contract_wait_limit_min"] == 30 and a["rule_kind"] == "l2"
    assert a["other_work"] == [{"svc": "exterior_wash", "min": 12, "where": "bay"}]
    assert b["chargers"]["free"] == {"dcfc": 2, "l2": 3} and b["waiting"] == 6
    assert b["last_order"]["accepted"] == 1 and b["pin_wait_min"] == 90 and b["ttl_ticks"] == 15


def test_usage_counts_what_the_orders_did(db):
    _apply(db)
    _dial(db, "agent_charge_order", 1)
    oid = _order(db, [("C", "dcfc"), ("A", "l2")])["order_id"]

    def seat(car, tick, ctx, stall_type):
        db.val(f"""INSERT INTO public.ottoq_decisions (sim_run_id, tick_seq, action_context, entity_id, outcome_status,
                                                       context_frame, enacted_action)
                   VALUES ('{RUN}', {tick}, 'stall_assignment', '{_vid(car)}', 'enacted',
                           jsonb_build_object('agent_charge_order', '{json.dumps(ctx)}'::jsonb),
                           jsonb_build_object('stall_type', '{stall_type}'))""")
    seat("C", 101, {"order_id": oid, "rank": 1, "kind": "dcfc", "pinned": False, "kernel_pos": 6}, "dcfc")  # moved ahead
    seat("A", 102, {"order_id": oid, "rank": 2, "kind": "l2", "pinned": False, "kernel_pos": 1}, "dcfc")    # kernel's pick anyway
    seat("P", 102, {"order_id": oid, "rank": None, "kind": None, "pinned": True, "kernel_pos": 2}, "l2")    # the pin
    u = db.json(f"SELECT public.ottoq_agent_charge_order_usage('{RUN}', 5)")
    assert (u["orders"], u["seats_under_order"], u["seats_by_rank"], u["seats_pinned"], u["moved_ahead"]) == (1, 3, 2, 1, 1), u
    assert (u["kind_named"], u["kind_followed"]) == (2, 1), u
    assert u["by_order"][0]["seats"] == 3 and u["by_order"][0]["chain_id"] == "chain-t"
    # the learning read carries it while the dial is on, and not at all at the default
    learn = db.json(f"SELECT public.ottoq_run_learning('{RUN}', 20, true)")
    assert learn["agent_order"]["usage"]["seats_by_rank"] == 2 and learn["agent_order"]["order"]["order_id"] == oid
    _dial(db, "agent_charge_order", 0)
    assert "agent_order" not in db.json(f"SELECT public.ottoq_run_learning('{RUN}', 20, true)")


# ── the stall pick takes the kind the order names ─────────────────────────────────────────────────────────────────────

def _stand_ins_for_the_stall_pick(d):
    d.val("CREATE TABLE IF NOT EXISTS public.depots (id uuid PRIMARY KEY, service_max_kw numeric, dcfc_max_concurrent_kw "
          "numeric, dcfc_safety_margin_pct numeric, slug text)")
    d.val(f"INSERT INTO public.depots VALUES ('{DEPOT}', 2500, 1800, 10, 'twin') ON CONFLICT DO NOTHING")
    d.val("CREATE OR REPLACE FUNCTION public.ottoq_depot_current_demand_kw(uuid, timestamptz) RETURNS numeric "
          "LANGUAGE sql AS 'SELECT 0::numeric'")
    d.val("CREATE OR REPLACE FUNCTION public.ottoq_target_soc_cap(text, timestamptz) RETURNS numeric "
          "LANGUAGE sql AS 'SELECT 100::numeric'")
    d.val("CREATE OR REPLACE FUNCTION ottoq.ottoq_validate_assignment(uuid, uuid, text, timestamptz, uuid) RETURNS jsonb "
          "LANGUAGE sql AS $$SELECT '{\"ok\": true}'::jsonb$$")


def _pick(d, car, soc, kind=None):
    ctx = {"current_soc": soc, "now_ts": T}
    if kind:
        ctx["agent_charge_order"] = {"order_id": 1, "rank": 1, "kind": kind}
    got = d.json(f"SELECT public.ottoq_l2_propose_stall_assignment('{_vid(car)}', '{DEPOT}', $j${json.dumps(ctx)}$j$::jsonb)")
    return got.get("stall_type")


def test_the_stall_pick_takes_the_kind_the_order_names(db):
    _apply(db)
    _stand_ins_for_the_stall_pick(db)
    assert _pick(db, "A", 50) == "l2"                     # the rule: 50% wants an L2
    assert _pick(db, "A", 50, "dcfc") == "dcfc"           # the order names a fast charger
    assert _pick(db, "C", 30) == "dcfc"                   # the rule: below 45% wants a fast charger
    assert _pick(db, "C", 30, "l2") == "l2"               # the order names an L2
    assert _pick(db, "I", 40, "l2") == "dcfc"             # an immediate dispatch keeps its fast charger
    assert _pick(db, "A", 50, "either") == "l2"           # 'either' leaves the rule's answer
    # only the other kind free: the car still takes it (no charger idles for the order)
    _occupy(db, ["L1", "L2", "L3"])
    assert _pick(db, "A", 50, "l2") == "dcfc"


def test_the_decide_tick_reads_the_order_once_and_gates_both_keys(db):
    _apply(db)
    # one line through psql -At: the source as a JSON string, newlines escaped
    src = db.json("SELECT to_json(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_decide_tick(uuid)'::regprocedure")
    assert src.count("ottoq_agent_charge_order_live(") == 1
    assert src.count("CASE WHEN v_ao_on THEN public.ottoq_charge_wait_min(") == 1
    assert src.count("THEN public.ottoq_agent_charge_order_key(v_ao_order, v.id, v_ao_mode) END ASC NULLS LAST") == 1
    assert src.index("'immediate_dispatch' FROM ottoq_visit_needs vn") < src.index("CASE WHEN v_ao_on THEN")


# ── 0615: an operator's demo run is armed with the order; a sweep arm is not; a certification arm is still refused ──

M0615 = os.path.join(ROOT, "db", "migrations", "0615_an_operators_demo_run_takes_the_agents_charge_order.sql")
ARM_STUB = os.path.join(ROOT, "tests", "fixtures", "agentic_arm_stub.sql")
ARMED_KEYS = ["agent_asset_depth_enabled", "agent_board_grounding_enabled", "agent_review_enabled",
              "agent_solver_chain_enabled", "cuopt_first_refusal_max_defers", "cuopt_propose_enabled",
              "orchestrator_agent_enabled", "prearrival_charge_yields_to_solver", "proposer_frame_facts",
              "proposer_hold_enabled"]


def _with_arm(d):
    rc, err = d.file(ARM_STUB)
    assert rc == 0, f"arm stub did not load: {err}"
    for k in ARMED_KEYS:
        d.val(f"""INSERT INTO public.ottoq_policy_param_catalog (param_key, min_value, max_value, default_value, agent_writable)
                  VALUES ('{k}', 0, 10, 0, false) ON CONFLICT DO NOTHING""")


def _run(d, run_by):
    rid = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0615-{run_by}"))
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, started_at, run_by, policy)
              VALUES ('{rid}', '{DEPOT}', 'running', 1, '{T}', now(), '{run_by}', 'otto_q')""")
    return rid


def _dials(d, rid):
    return d.json(f"""SELECT COALESCE(jsonb_object_agg(param_key, param_value), '{{}}') FROM public.ottoq_policy_params
                       WHERE scope_type = 'run' AND scope_id = '{rid}'""")


def test_0615_arms_the_order_on_an_operators_run_and_nowhere_else(db):
    _with_arm(db)
    _apply(db)
    rc, err = db.file(M0615)
    assert rc == 0, f"0615 did not apply: {err}"
    demo, sweep, cert = _run(db, "operator_demo"), _run(db, "ab_harness"), _run(db, "cert_harness")

    out = db.json(f"SELECT public.ottoq_agentic_arm('{demo}', 'auto:operator_demo')")
    assert out["ok"] is True
    assert _dials(db, demo).get("agent_charge_order") == 1
    assert len(out["receipts"]) == len(ARMED_KEYS) + 1

    db.json(f"SELECT public.ottoq_agentic_arm('{sweep}', 'auto:ab_harness')")
    dials = _dials(db, sweep)
    assert "agent_charge_order" not in dials
    assert sorted(dials) == sorted(ARMED_KEYS)      # a sweep arm's dial set is the one before 0615

    rc, _, err = db.run(f"SELECT public.ottoq_agentic_arm('{cert}', 'auto:cert_harness')")
    assert rc != 0 and "certification arm" in err
    assert _dials(db, cert) == {}

    # the armed run's door now records an order (the dial reads 1 there)
    rec = db.json(f"""SELECT public.ottoq_agent_charge_order_record('{demo}', 1, 'c', 'm', '{{"cars":[]}}'::jsonb)""")
    assert rec.get("skipped") != "agent_charge_order is 0 for this run"


def test_0615_refuses_an_arm_it_was_not_written_against(db):
    _with_arm(db)
    _apply(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_agentic_arm(p_sim_run_id uuid, p_by text) RETURNS jsonb
              LANGUAGE sql AS $f$ SELECT '{}'::jsonb $f$""")
    rc, err = db.file(M0615)
    assert rc != 0 and "0615 P1" in err
