"""db/migrations/0763, EXECUTED: canopy C is re-striped and the twin depot has no standard chargers.

WHY THIS EXISTS. Chase, 2026-10-21: swap out all of the L2s for robotic fast chargers, each with its charging arm and
overhead robovac. 0759 re-stripes canopy B; 0763 re-stripes canopy C, so the depot holds thirty robotic posts (the site's
ceiling at this arm design) and no standard charger, on today's 2.5 MW service with the posts sharing 2.4 MW of DC
cabinets (arm 112's cell). Executed here, on the scratch PostgreSQL, over 0759's fixture (the live bodies and the depot's
rows as read on 2026-10-19, tests/fixtures/twenty_post_base_stub.sql), with 0759 applied first and 0763 run whole:
  - 0763 lays canopy C out at the layout seed's points (NASH-DCFC-STALL-21..30, west x 288.8583 at heading 60, east x
    310.8366 at heading 300, canopy A's rows), re-rates and renames their chargers, flips their capabilities, retires
    NASH-L2-STALL-31..35, sets the depot's power, layout counts and canopy C's structure, writes the four settings under
    Chase's name, moves nothing else, passes the geometry checks, and signs one event per moved space as
    migration_script 0763, to no run;
  - after 0763 every build-out round-trips to the new depot exactly; every old one is the day it was, column by column;
    dcfc10 is the depot as built before 0759 row for row, dcfc20 the 20-post depot 0759 built row for row, and dcfc30
    and dcfc30_cab2400 the new depot on their grids;
  - the scorecard reads a run as it ran: days before 0759 and a day on the 20-post depot score the same after 0763;
  - ottoq_stall_type_at answers the type a space had across both base changes;
  - 0763 refuses before 0759, while a sweep or a dial experiment is active, a run is live or a rig is in flight; refuses a
    body 0759 does not leave, a car or an open booking on canopy C, a run that named dcfc30, and a second apply.
STAND-INS, beyond 0759's fixture: the policy catalog and params tables, and public.ottoq_policy_set as the live door's
write alone (no shield probe, no clamp): enough to test that 0763 writes the four settings through the door and checks
them, not the door itself. A module template carries the fixture, and each test clones it. It SKIPS where no scratch
PostgreSQL is reachable.
"""
import json
import os
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)
import test_twenty_post_base_sql as tp  # noqa: E402  (0759's fixture, image and day helpers)

ROOT = base.ROOT
M0763 = os.path.join(ROOT, "db", "migrations", "0763_canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers.sql")
DEPOT = base.DEPOT
WEST_X, EAST_X = 288.8583, 310.8366
ROWS_Y = tp.ROWS_Y
SETTINGS = {"dc_power_sharing": "1", "dc_power_managed": "1", "dc_power_first_reading": "1", "enforce_site_charge_cap": "0"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

POLICY_STANDIN = """
CREATE TABLE public.ottoq_policy_param_catalog (param_key text PRIMARY KEY, default_value numeric, min_value numeric,
  max_value numeric);
INSERT INTO public.ottoq_policy_param_catalog VALUES
  ('dc_power_sharing', 0, 0, 1), ('dc_power_managed', 0, 0, 1), ('dc_power_first_reading', 0, 0, 1),
  ('enforce_site_charge_cap', 1, 0, 1), ('dc_power_by_need', 0, 0, 1), ('site_cap_gate_metered', 0, 0, 1);
CREATE TABLE public.ottoq_policy_params (scope_type text NOT NULL, scope_id uuid NOT NULL, param_key text NOT NULL,
  param_value numeric NOT NULL, updated_by text, updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (scope_type, scope_id, param_key));
-- the live door's write alone: refuse an unknown key, write the row under the name given, say what was applied
CREATE FUNCTION public.ottoq_policy_set(p_scope_type text, p_scope_id uuid, p_param_key text, p_param_value numeric,
                                        p_by text) RETURNS jsonb LANGUAGE plpgsql AS $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_policy_param_catalog WHERE param_key = p_param_key) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unknown_param', 'param', p_param_key);
  END IF;
  INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
  VALUES (p_scope_type, p_scope_id, p_param_key, p_param_value, p_by)
  ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value, updated_at = now(),
     updated_by = EXCLUDED.updated_by;
  RETURN jsonb_build_object('ok', true, 'param', p_param_key, 'requested', p_param_value, 'applied', p_param_value);
END $$;
"""


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    tp._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(tp.FIXTURE)
        assert rc == 0, f"the fixture did not load: {err}"
        d.val("""INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
                 VALUES ('0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges', false, false,
                         'test premise', now())""")
        rc, _, err = tp._script(d, POLICY_STANDIN)
        assert rc == 0, err
        yield name
    finally:
        tp._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    tp._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        tp._admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply_0759(d):
    rc, err = d.file(tp.M0759)
    assert rc == 0, f"0759 did not apply: {err}"


def _apply(d):
    rc, err = d.file(M0763)
    assert rc == 0, f"0763 did not apply: {err}"
    return err


def _refused(d, needle):
    rc, err = d.file(M0763)
    assert rc != 0 and needle in err, err
    assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0763%'") == "0"
    assert d.val(f"SELECT count(*) FROM public.stalls WHERE depot_id = '{DEPOT}' AND stall_type = 'l2'") in ("15", "30")


def _census(d):
    return dict(tuple(r.split("|")) for r in d.run(
        f"SELECT stall_type, count(*) FROM public.stalls WHERE depot_id = '{DEPOT}' GROUP BY 1")[1])


# ── the base change ──────────────────────────────────────────────────────────────────────────────────────────────────

def test_0763_lays_canopy_c_out_as_canopies_a_and_b_and_leaves_no_standard_charger(db):
    _apply_0759(db)
    before = tp._image(db)
    notice = _apply(db)
    assert "0763 V5: 0 stored days" in notice
    assert _census(db) == {"dcfc": "30", "parking": "10", "staging": "113", "wash_bay": "3", "service_bay": "2"}
    posts = [r.split("|") for r in db.run(f"""
        SELECT s.stall_code, s.relative_x, s.relative_y, s.heading_degrees, s.display_name, s.zone, s.connector_max_kw,
               s.fiducial_marker_id, s.uwb_beacon_id, s.equipment_config->>'canopy_side', s.canopy_code, s.covered,
               s.stall_kind, s.stall_width_ft, s.stall_depth_ft, c.ocpp_identifier, c.vendor, c.model, c.max_kw,
               c.firmware_version, c.ocpp_protocol_version, c.installed_at IS NOT NULL, c.decommissioned_at IS NULL,
               (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id
                   AND k.operation_code = 'charge_dcfc' AND k.active),
               (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id
                   AND k.operation_code = 'charge_l2')
          FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
         WHERE s.depot_id = '{DEPOT}' AND s.canopy_code = 'CANOPY-03' ORDER BY s.stall_code""")[1]]
    assert [p[0] for p in posts] == [f"NASH-DCFC-STALL-{n}" for n in range(21, 31)]
    for i, p in enumerate(posts):
        n, west = 21 + i, i < 5
        assert float(p[1]) == (WEST_X if west else EAST_X) and float(p[2]) == ROWS_Y[i % 5], p
        assert p[3] == ("60" if west else "300") and p[4] == f"CANOPY-03 {'W' if west else 'E'}-{n}", p
        assert p[5:9] == ["dcfc_zone", "350.0", f"FID-D3-{n}-A", f"UWB-D3-{n}"], p
        assert p[9:13] == ["W" if west else "E", "CANOPY-03", "t", "charging"] and float(p[13]) == 10, p
        assert float(p[14]) == 19.0276 and p[15] == f"NASH-DCFC-{n}", p
        assert p[16:21] == ["ABB", "Terra HP 350", "350", "1.4.2", "1.6J"] and p[21:] == ["t", "t", "7", "0"], p
    retired = [r.split("|") for r in db.run(f"""
        SELECT s.stall_code, s.stall_type, s.relative_x IS NULL AND s.relative_y IS NULL, s.ocpp_charger_id IS NULL,
               s.stall_kind, s.zone IS NULL, s.canopy_code IS NULL, s.covered,
               (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id AND k.active),
               c.decommissioned_at IS NOT NULL, c.station_state, s.equipment_config->>'retired_by'
          FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.ocpp_identifier = replace(s.stall_code, '-STALL', '')
         WHERE s.depot_id = '{DEPOT}' AND s.stall_type = 'parking' ORDER BY s.stall_code""")[1]]
    assert retired == ([[f"NASH-L2-STALL-{n}", "parking", "t", "t", "retired", "t", "t", "f", "0", "t", "Unavailable", "0759"]
                        for n in range(11, 16)]
                       + [[f"NASH-L2-STALL-{n}", "parking", "t", "t", "retired", "t", "t", "f", "0", "t", "Unavailable", "0763"]
                          for n in range(31, 36)])
    assert db.val(f"""SELECT dcfc_max_concurrent_kw || '/' || service_max_kw || '/' || (site_layout->>'dcfc_count') || '/'
                             || (site_layout->>'l2_count') FROM public.depots WHERE id = '{DEPOT}'""") == "2400/2500/30/0"
    assert db.val(f"""SELECT title || '|' || (properties->'chargers')::text || '|' || (properties->>'stall_capacity')
                        FROM public.ottoq_site_structures
                       WHERE depot_id = '{DEPOT}' AND structure_code = 'CANOPY-03'""") == 'Solar Canopy C (DCFC)|{"dcfc": 10}|10'
    assert db.val(f"SELECT public.ottoq_check_stall_overlap('{DEPOT}')->>'passed'") == "true"
    assert db.val(f"SELECT public.ottoq_check_fence_containment('{DEPOT}')->>'passed'") == "true"
    # the four settings, under Chase's name, and nothing else at the depot
    got = dict(tuple(r.split("|")[:2]) for r in db.run(f"""
        SELECT param_key, param_value::int, updated_by FROM public.ottoq_policy_params
         WHERE scope_type = 'depot' AND scope_id = '{DEPOT}' AND updated_by = 'Chase'""")[1])
    assert got == SETTINGS
    assert db.val("SELECT count(*) FROM public.ottoq_policy_params") == "4"
    # nothing else moved: the other 143 spaces, their capabilities and the other chargers, row for row
    after = tp._image(db)
    moved = {tp._sid(db, f"NASH-DCFC-STALL-{n}") for n in range(21, 31)} | {tp._sid(db, f"NASH-L2-STALL-{n}") for n in range(31, 36)}
    assert len(moved) == 15
    for sid, row in before["stalls"].items():
        if sid not in moved:
            assert after["stalls"][sid] == row, sid
    moved_chargers = set(db.run("""SELECT charger_id FROM public.ottoq_ocpp_chargers
                                    WHERE ocpp_identifier ~ '^NASH-(DCFC-(2[1-9]|30)|L2-3[1-5])$'""")[1])
    assert len(moved_chargers) == 15
    for cid, row in before["chargers"].items():
        if cid not in moved_chargers:
            assert after["chargers"][cid] == row, cid
    for key, active in before["caps"].items():
        if key.split("|")[0] not in moved:
            assert after["caps"][key] == active, key
    assert db.val("""SELECT forces_recert || '/' || forces_dial_restart FROM public.ottoq_cert_lineage
                      WHERE name = '0763_canopy_c_is_restriped_and_the_twin_depot_has_no_standard_chargers'""") == "true/true"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0763_pre' AND object_kind = 'rows'") == "4"


def test_0763_signs_one_event_per_moved_space_as_the_migration_to_no_run(db):
    _apply_0759(db)
    _apply(db)
    rows = [r.split("|") for r in db.run("""
        SELECT e.actor_type, e.actor_id, e.event_type, e.sim_run_id IS NULL, e.data_source,
               e.payload->'diff' ? 'stall_type', count(*)
          FROM public.ottoq_events e WHERE e.actor_id = '0763' GROUP BY 1, 2, 3, 4, 5, 6 ORDER BY 1""")[1]]
    assert rows == [["migration_script", "0763", "stall.state_changed", "t", "twin", "t", "15"]]


# ── the build-outs after the base change ─────────────────────────────────────────────────────────────────────────────

def test_after_0763_every_buildout_round_trips_and_the_old_ones_are_the_days_they_were(db):
    as_built = tp._image(db)
    _apply_0759(db)
    twenty = tp._image(db)
    codes_0759 = db.run("SELECT buildout_code FROM public.ottoq_site_buildouts ORDER BY 1")[1]
    old = {code: tp._applied_image(db, code) for code in codes_0759}
    _apply(db)
    thirty = tp._image(db)
    assert thirty != twenty
    codes = db.run("SELECT buildout_code FROM public.ottoq_site_buildouts ORDER BY 1")[1]
    assert codes == sorted(codes_0759 + ["dcfc30_cab2400"])
    for code in codes:
        receipt, applied, back = tp._applied_image(db, code)
        assert back == thirty, code
        if code in ("dcfc30", "dcfc30_cab2400"):
            assert {k: v for k, v in applied.items() if k != "power"} == {k: v for k, v in thirty.items() if k != "power"}, code
            assert receipt["stall_set"] == [] and receipt["converted_stall_ids"] == [] and receipt["buildable"] is True, code
            assert applied["power"] == ([5400, 6226] if code == "dcfc30" else [2400, 2500]), code
            continue
        old_receipt, old_applied, _ = old[code]
        assert applied == old_applied, code
        assert receipt["converted_stall_ids"] == old_receipt["converted_stall_ids"], code
        assert receipt["buildable"] is old_receipt["buildable"], code
        # the receipt names every space the day changed and its type that day: canopy C's fifteen besides 0759's set
        changed = {e["stall_id"] for e in receipt["stall_set"]} | set(receipt["converted_stall_ids"])
        assert len(receipt["stall_set"]) == (15 if code in ("dcfc20", "dcfc20_grid_today") else 30), code
        assert set(receipt["stall_types"]) == changed, code
    # dcfc10 is the depot as it stood before 0759, row for row; dcfc20 the 20-post depot 0759 built, row for row
    assert tp._applied_image(db, "dcfc10")[1] == as_built
    assert tp._applied_image(db, "dcfc20")[1] == twenty
    # and the base is dcfc30_cab2400 exactly
    assert thirty["power"] == [2400, 2500]


# ── the past ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_scorecard_reads_a_day_as_it_ran_across_both_base_changes(db):
    runs = tp._runs(db)  # three days before 0759, with charges on canopy A, canopy B and canopy C (NASH-L2-STALL-16)
    _apply_0759(db)
    # a day on the 20-post depot: a charge on canopy B's new post and on canopy C's standard charger
    run = str(uuid.uuid5(uuid.NAMESPACE_DNS, "0763-run-twenty"))
    b11, c16 = tp._sid(db, "NASH-DCFC-STALL-11"), tp._sid(db, "NASH-L2-STALL-16")
    db.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, scenario_code, random_seed, tick_count, policy,
                                                 started_at, ended_at, sim_clock_start, sim_clock_current,
                                                 tick_interval_seconds, time_scale, payload)
              VALUES ('{run}', '{DEPOT}', 'completed', 'normal_day', 42, 108, 'otto_q', now(), now(),
                      '2026-09-02 11:00+00', '2026-09-02 20:00+00', 300, 1, '{{}}'::jsonb)""")
    db.val(f"""INSERT INTO public.ocpp_sessions (stall_id, started_at, ended_at, energy_delivered_kwh, avg_power_kw, sim_run_id)
              VALUES ('{b11}', '2026-09-02 12:00+00', '2026-09-02 12:30+00', 40, 160, '{run}'),
                     ('{c16}', '2026-09-02 12:00+00', '2026-09-02 15:00+00', 33, 11, '{run}')""")
    runs["twenty"] = run
    before = {k: tp._score(db, r) for k, r in runs.items()}
    assert (before["twenty"]["fast_chargers"]["sessions"], before["twenty"]["l2_sessions"],
            before["twenty"]["fast_chargers"]["at_depot"]) == (1, 1, 20)
    notice = _apply(db)
    assert "0763 V5: 3 stored days, one of each kind, score the same after the base change" in notice
    for kind, r in runs.items():
        assert tp._score(db, r) == before[kind], kind


def test_ottoq_stall_type_at_reads_both_base_changes(db):
    _apply_0759(db)
    b11 = tp._sid(db, "NASH-DCFC-STALL-11")
    c16, c31 = tp._sid(db, "NASH-L2-STALL-16"), tp._sid(db, "NASH-L2-STALL-31")
    between = db.val("SELECT now()")
    _apply(db)
    c21 = tp._sid(db, "NASH-DCFC-STALL-21")
    assert c21 == c16
    for sid, at, want in [(b11, "now() - interval '1 day'", "l2"), (b11, f"'{between}'::timestamptz", None),
                          (c21, "now() - interval '1 day'", "l2"), (c21, f"'{between}'::timestamptz", "l2"),
                          (c21, "now() + interval '1 hour'", None), (c31, f"'{between}'::timestamptz", "l2")]:
        got = db.val(f"SELECT COALESCE(public.ottoq_stall_type_at('{sid}', {at}), '-')")
        assert got == (want or "-"), (sid, at)
    assert db.val("SELECT count(*) FROM public.ottoq_site_base_history WHERE change_code = '0763'") == "15"
    rc, _, err = db.run("UPDATE public.ottoq_site_base_history SET stall_type = 'dcfc' WHERE change_code = '0763'")
    assert rc != 0 and "append-only" in err, err


# ── what 0763 refuses ────────────────────────────────────────────────────────────────────────────────────────────────

def test_0763_refuses_before_0759(db):
    rc, err = db.file(M0763)
    assert rc != 0 and "0759 is not applied" in err, err
    assert _census(db)["l2"] == "30"


@pytest.mark.parametrize("setup, needle", [
    (f"INSERT INTO public.ottoq_throughput_sweeps (sweep_code, depot_id, status) VALUES ('s', '{DEPOT}', 'active')",
     "research sweeps are active at the twin depot"),
    (f"INSERT INTO public.ottoq_dial_experiments (depot_id, param_key, status) VALUES ('{DEPOT}', 'k', 'active')",
     "dial experiments are active at the twin depot"),
    (f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at)
         VALUES (gen_random_uuid(), '{DEPOT}', 'running', now())""", "a run is live at the twin depot"),
    ("ALTER DATABASE {name} SET test.in_flight = '1'", "is running right now"),
    ("""DO $$ BEGIN EXECUTE replace(pg_get_functiondef('public.ottoq_check_stall_overlap(uuid)'::regprocedure),
                                    'jsonb_build_object(', 'jsonb_build_object( '); END $$""", "not the bodies 0759 leaves"),
    (f"""UPDATE public.stalls SET current_vehicle_id = gen_random_uuid()
          WHERE depot_id = '{DEPOT}' AND stall_code = 'NASH-L2-STALL-33'""", "a car, a reservation or an open booking is on canopy C"),
    (f"""INSERT INTO public.ottoq_stall_bookings (stall_id, state)
         SELECT id, 'active' FROM public.stalls WHERE depot_id = '{DEPOT}' AND stall_code = 'NASH-L2-STALL-27'""",
     "a car, a reservation or an open booking is on canopy C"),
    (f"UPDATE public.depots SET dcfc_max_concurrent_kw = 1800 WHERE id = '{DEPOT}'", "not as 0759 declares it"),
    (f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, payload)
         VALUES (gen_random_uuid(), '{DEPOT}', 'completed', now(), '{{"site_buildout": {{"buildout_code": "dcfc30"}}}}')""",
     "a run has named dcfc30"),
    ("DELETE FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_managed'", "the four settings are not all catalogued"),
])
def test_0763_refuses_a_world_it_was_not_written_against(db, setup, needle):
    _apply_0759(db)
    db.val(setup.replace("{name}", db.name))
    _refused(db, needle)


def test_0763_refuses_a_second_apply(db):
    _apply_0759(db)
    _apply(db)
    rc, err = db.file(M0763)
    assert rc != 0 and ("0763 P1" in err or "0763 P2" in err), err
    assert db.val("SELECT count(*) FROM public.ottoq_site_base_history WHERE change_code = '0763'") == "15"
