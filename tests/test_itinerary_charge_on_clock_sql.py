"""db/migrations/0745, EXECUTED: the itinerary plans each charge on a charger the depot has, timed on its learned clock.

WHY THIS EXISTS. The itinerary planner (public.ottoq_plan_visit_itinerary) chose a car's charge by a fixed rule, a fast
charge at 100 kW below 45% and an L2 at 11 kW above it, whatever chargers the depot has. On forty robotic posts and no L2
it planned 124 L2 charges for 92 cars that were never served, each ending a mean 219 minutes after the real charge, and
every bay hold, reconcile test and ready-by time after them read the phantom (G459). Every claim in 0745's header that a
test can execute is executed here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py
taken through 0642, whose charge clock, plug test and charge line are the live bodies (md5 asserted), with the planner and
the physics it times a charge by (tests/fixtures/itinerary_plan_stub.sql, md5 asserted as read on 2026-10-17):
  - before 0745, a depot with no L2 still gets an L2 charge in the plan, at 11 kW, and the wash waits behind it;
  - 0745 applies, its checks run, it leaves the body it was written to leave, a second apply is refused, and it refuses a
    body it was not written against;
  - at the dial's default every car's plan is the rule's, leg for leg and basis for basis, on both depots;
  - with the dial, a depot with only fast chargers plans a fast charge timed exactly as the depot's clock times it, and
    the wash follows that charge's end;
  - with the dial, a depot with both kinds keeps the rule's kind and takes its length from the clock;
  - with no clock, the physics runs on the depot's own power; a failing clock leaves the rule's plan;
  - the pre-image in ottoq_schema_snapshots puts the live body back.
A module template carries the miniature depot, the promise stub and the planner stub, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
import test_charge_order_floor_sql as fl  # noqa: E402  (0619-0642, the chain to the live charge line)
import test_ready_promise_sql as rp  # noqa: E402  (its stub and its record of the live clock)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "itinerary_plan_stub.sql")
M0745 = os.path.join(ROOT, "db", "migrations", "0745_the_itinerary_plans_each_charge_on_a_charger_the_depot_has.sql")
NAME = "0745_the_itinerary_plans_each_charge_on_a_charger_the_depot_has"
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T

PLAN = "public.ottoq_plan_visit_itinerary(uuid,uuid,timestamp with time zone)"
LIVE = {
    PLAN: "990e9481a4917ae0d23dc78e205896aa",
    "public.ottoq_estimate_charge_minutes(numeric,numeric,numeric,numeric,numeric,numeric,numeric,numeric)":
        "24de68cf451063110a7e4d5b5892d146",
    "public.ottoq_sim_compute_charge_rate(numeric,numeric,numeric,numeric,numeric,numeric,numeric,bigint,text)":
        "b0a5b152955721efceace9b1b95abf75",
    "twin.ottoq_sim_seeded_random(bigint,text)": "237b754ac865e17e0876a5df7af979b2",
    "twin.ottoq_sim_lane_capacity(uuid,text,integer)": "ef28379b407a30e118837a3b6cb618e4",
    "public.ottoq_svc_to_leg_type(text)": "fb647f626379333f103a8e36f690a36e",
    "public.ottoq_charge_kind_compatible(uuid,uuid,text)": "65c6bbcb114cfdad942e9391ffe0daa7",
    "public.ottoq_charge_clock_who(uuid,text,text,text)": "9d3ad3572c4d5d1dd36db772ff7402d4",
}
CLOCK = {k: v for k, v in rp.LIVE_LINE.items() if "charge_clock" in k}
AFTER_0745 = "b18eef1a0b1b9b8f855c939f37cd00b3"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_itct_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    rp._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        fl._through_0642(d)
        for path in (rp.STUB, STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        yield name
    finally:
        rp._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_itc_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    rp._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        rp._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0745)
    assert rc == 0, f"0745 did not apply: {err}"
    return err


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _dial(d, value):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'itinerary_charge_on_clock', {value}, 'test', now())""")


def _no_l2(d):
    """Forty robotic posts in miniature: every L2 space becomes a fast charger, as 0724's build-outs convert them."""
    d.val("UPDATE public.stalls SET stall_type = 'dcfc', connector_max_kw = 180 WHERE stall_type = 'l2'")


def _plan(d, names=None):
    where = "" if names is None else "WHERE v.display_name IN (" + ", ".join(f"'{n}'" for n in names) + ")"
    d.val(f"SELECT count(public.ottoq_plan_visit_itinerary('{RUN}', v.id, '{T}')) FROM public.vehicles v {where}")


def _legs(d):
    """Every planned leg as the plan wrote it, by car name: the columns a reader can see, not the minted ids."""
    return d.json("""SELECT COALESCE(jsonb_agg(jsonb_build_object('car', v.display_name, 'seq', l.seq, 'leg', l.leg_type,
                                                              'from', l.planned_start_sim, 'to', l.planned_end_sim,
                                                              'secs', l.planned_duration_s, 'basis', l.duration_basis,
                                                              'status', l.status, 'stall', l.to_stall_id)
                                             ORDER BY v.display_name, l.seq), '[]')
                       FROM public.ottoq_itinerary_legs l JOIN public.vehicles v ON v.id = l.vehicle_id""")


def _charge(d, name):
    return d.json(f"""SELECT jsonb_build_object('leg', l.leg_type, 'min', round(extract(epoch FROM l.planned_end_sim
                                                                                 - l.planned_start_sim) / 60, 1),
                                                'end', l.planned_end_sim, 'basis', l.duration_basis)
                        FROM public.ottoq_itinerary_legs l JOIN public.vehicles v ON v.id = l.vehicle_id
                       WHERE v.display_name = '{name}' AND l.leg_type LIKE 'charge%'""")


def _wash_start(d, name):
    return d.val(f"""SELECT l.planned_start_sim FROM public.ottoq_itinerary_legs l JOIN public.vehicles v ON v.id = l.vehicle_id
                      WHERE v.display_name = '{name}' AND l.leg_type = 'wash'""")


def _clock_min(d, name, kind, kw):
    """The depot's clock on this car, called exactly as the kernel's line calls it (ottoq_charge_order_minutes)."""
    return float(d.val(f"""SELECT (public.ottoq_charge_clock(m.ct, '{kind}',
                                     public.ottoq_charge_clock_who(v.id, v.vehicle_class_code, v.make, v.model),
                                     v.battery_capacity_kwh, v.current_soc, public.ottoq_effective_target_soc_at(v.id, '{T}'),
                                     {kw}, v.inlet_max_kw,
                                     public.ottoq_charge_clock_run_evidence(m.ct, '{RUN}', '{T}') -> '{kind}') ->> 'm')::numeric
                             FROM (SELECT public.ottoq_charge_clock_model('{DEPOT}') AS ct) m
                             CROSS JOIN public.vehicles v WHERE v.display_name = '{name}'"""))


def _physics_min(d, name, kw):
    return float(d.val(f"""SELECT public.ottoq_estimate_charge_minutes(v.current_soc, 100, {kw}, v.inlet_max_kw,
                                                                       v.battery_capacity_kwh, 20, 100, 1.0)
                             FROM public.vehicles v WHERE v.display_name = '{name}'"""))


def test_the_fixture_carries_the_live_bodies(db):
    for fn, want in {**LIVE, **CLOCK}.items():
        assert _md5(db, fn) == want, fn


def test_before_0745_a_depot_with_no_l2_still_plans_an_l2_charge(db):
    _no_l2(db)
    _plan(db, ["B"])
    c = _charge(db, "B")
    assert c["leg"] == "charge_l2" and c["basis"] == {"kind": "flow_contract", "charger_kw_assumed": 11}
    assert c["min"] == pytest.approx(_physics_min(db, "B", 11), abs=0.06)       # 60% at 11 kW: about 3.4 hours
    assert c["min"] > 200
    assert _wash_start(db, "B") == db.val(f"SELECT '{c['end']}'::timestamptz")    # the wash waits behind the phantom


def test_0745_applies_its_checks_run_and_a_second_apply_is_refused(db):
    _apply(db)
    assert _md5(db, PLAN) == AFTER_0745
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || COALESCE(agent_writable, false)
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'itinerary_charge_on_clock'""") == "0/0/1/false"
    cells = db.json("""SELECT jsonb_agg(jsonb_build_object('cell', c.cell_code, 'ord', c.ord, 'buildout', c.buildout_code,
                                                         'params', c.fixed_params, 'priority', s.priority,
                                                         'budget', s.arm_budget_s, 'seeds', s.seeds) ORDER BY c.ord)
                         FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                        WHERE s.sweep_code = 'itinclock_normal_2026_10_17'""")
    params = {"deploy_peak_fraction": 0.90, "itinerary_charge_on_clock": 1}
    assert cells == [
        {"cell": "dcfc40.otto_q.itinerary_on_clock", "ord": 1, "buildout": "dcfc40", "params": params, "priority": 16,
         "budget": 3000, "seeds": [686364201590009433]},
        {"cell": "dcfc10.otto_q.itinerary_on_clock", "ord": 2, "buildout": "dcfc10", "params": params, "priority": 16,
         "budget": 3000, "seeds": [686364201590009433]}]
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0745_pre'") == "1"
    rc, err = db.file(M0745)
    assert rc != 0 and "0745 P" in err


def test_0745_refuses_a_body_it_was_not_written_against(db):
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_plan_visit_itinerary(p_sim_run_id uuid, p_vehicle uuid,
                                                                         p_clock timestamp with time zone)
              RETURNS integer LANGUAGE sql AS $$ SELECT 0 $$""")
    rc, err = db.file(M0745)
    assert rc != 0 and "0745 P1" in err


@pytest.mark.parametrize("converted", [False, True], ids=["both_kinds", "fast_only"])
def test_at_the_default_every_plan_is_the_rules_leg_for_leg(db, converted):
    if converted:
        _no_l2(db)
    _plan(db)
    before = _legs(db)
    assert len(before) >= 18                                      # six cars in the line, three legs each at least
    db.val("DELETE FROM public.ottoq_itinerary_legs; DELETE FROM public.ottoq_vehicle_itineraries")
    _apply(db)
    _plan(db)
    assert _legs(db) == before


def test_with_the_dial_a_depot_with_only_fast_chargers_plans_a_fast_charge_on_its_clock(db):
    _apply(db)
    _no_l2(db)
    _dial(db, 1)
    _plan(db, ["B", "C"])
    for car in ("B", "C"):
        c = _charge(db, car)
        assert c["leg"] == "charge_dcfc"
        assert c["min"] == pytest.approx(_clock_min(db, car, "dcfc", 180), abs=0.06)
        b = c["basis"]
        assert (b["charge_kind"], b["kind_basis"], b["charger_kw_assumed"], b["minutes_basis"], b["planned_by"]) == \
               ("dcfc", "the_only_kind_the_car_can_use_here", 180, "charge_clock", "0745")
        assert b["target_soc"] == 100 and b["clock_fit"] is not None
        assert _wash_start(db, car) == db.val(f"SELECT '{c['end']}'::timestamptz")   # the wash follows the real charge
    assert _charge(db, "B")["min"] < 60                           # B: an hour, not the rule's 3.4 hours on an L2


def test_with_the_dial_a_depot_with_both_kinds_keeps_the_rules_kind_on_the_clock(db):
    _apply(db)
    _dial(db, 1)
    _plan(db, ["B", "C"])
    b, c = _charge(db, "B"), _charge(db, "C")
    assert (b["leg"], c["leg"]) == ("charge_l2", "charge_dcfc")   # 60% and 30%: the rule's kinds
    assert b["min"] == pytest.approx(_clock_min(db, "B", "l2", 19.2), abs=0.06)
    assert c["min"] == pytest.approx(_clock_min(db, "C", "dcfc", 150), abs=0.06)
    assert {b["basis"]["kind_basis"], c["basis"]["kind_basis"]} == {"soc_rule"}
    assert (b["basis"]["charger_kw_assumed"], c["basis"]["charger_kw_assumed"]) == (19.2, 150)


def test_with_the_dial_and_no_clock_the_physics_runs_on_the_depots_own_power(db):
    _apply(db)
    _no_l2(db)
    _dial(db, 1)
    # a depot with no usable fit: the model reader answers NULL, as it does where nothing has been learned
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_clock_model(p_depot uuid) RETURNS jsonb
              LANGUAGE sql STABLE AS $$ SELECT NULL::jsonb $$""")
    _plan(db, ["B"])
    c = _charge(db, "B")
    assert c["leg"] == "charge_dcfc"
    assert c["min"] == pytest.approx(_physics_min(db, "B", 180), abs=0.06)
    assert (c["basis"]["minutes_basis"], c["basis"]["clock_fit"]) == ("physics", None)


def test_with_the_dial_a_failing_clock_leaves_the_rules_plan(db):
    _plan(db, ["B"])
    rule = _legs(db)
    db.val("DELETE FROM public.ottoq_itinerary_legs; DELETE FROM public.ottoq_vehicle_itineraries")
    _apply(db)
    _dial(db, 1)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_charge_clock(p_model jsonb, p_kind text, p_who jsonb, p_batt_kwh numeric,
                                                                  p_soc_from numeric, p_soc_to numeric, p_charger_kw numeric,
                                                                  p_inlet_kw numeric, p_run jsonb DEFAULT NULL::jsonb)
              RETURNS jsonb LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'clock down'; END $$""")
    rc, _, err = db.run(f"SELECT public.ottoq_plan_visit_itinerary('{RUN}', id, '{T}') FROM public.vehicles "
                        "WHERE display_name = 'B'")
    assert rc == 0 and "0745: the clock could not plan the charge" in err
    assert _legs(db) == rule


def test_the_pre_image_puts_the_live_body_back(db):
    _apply(db)
    db.val("""DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0745_pre'); END $$""")
    assert _md5(db, PLAN) == LIVE[PLAN]
