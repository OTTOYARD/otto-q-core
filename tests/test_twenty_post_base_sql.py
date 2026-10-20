"""db/migrations/0759, EXECUTED: canopy B is re-striped for ten more robotic fast chargers.

WHY THIS EXISTS. 0567's dcfc20 converts NASH-L2-STALL-01..10 in place, on the standard rows' 8.4-unit pitch, where a robotic
charger's pedestal (5.9 units from its car's centreline) would stand inside the next car (its flank 5.27 units away). The
buildable 20 re-stripes canopy B as canopy A: ten posts on the 14-unit pitch where fifteen standard spaces stood. 0759 makes
that the twin depot's base (20 fast chargers, 15 standard) and is a FILE ONLY, never applied: applying it is Chase's call.
Executed here, on the scratch PostgreSQL, against the live build-out apply, restore, census and commit guard, the live
throughput scorecard, the live geometry checks and the live stall triggers (tests/fixtures/twenty_post_base_stub.sql, md5
asserted as read on 2026-10-19), with the depot's rows as read that day, and 0759 run whole:
  - the fixture is the live bodies, and the depot reproduces 0759's premise digests;
  - before 0759 every build-out applies and restores to the depot as built;
  - 0759 lays canopy B out at the layout seed's points (NASH-DCFC-STALL-11..20, west x 215.0738 at heading 60, east x
    237.0522 at heading 300, canopy A's rows), re-rates and renames their chargers, flips their capabilities, retires
    NASH-L2-STALL-11..15 (no position, no charger, nothing active, chargers decommissioned), sets the depot's power,
    layout counts and canopy B's structure, moves nothing else, passes the geometry checks, and signs one event per moved
    space as migration_script 0759, to no run;
  - after 0759 every build-out round-trips to the new depot exactly; dcfc10 is the old depot row for row, and dcfc15,
    dcfc20_in_place (the old dcfc20) and the dcfc40 family are the days they were; dcfc30 lays canopy C out as canopy B;
  - the scorecard reads a run as it ran: three stored days score the same after 0759, the old scorecard body would not,
    and a day run on dcfc10 after 0759 is scored from its receipt's stall types;
  - the base history is append-only and ottoq_stall_type_at answers the type a space had;
  - the new apply refuses a stall set it may not apply, a build-out with a set still cannot commit unrestored, and the
    restore refuses a capability it did not put back;
  - 0759 refuses while a sweep or a dial experiment is active, a rig is in flight or a run is live; refuses a body it did
    not read, a car on canopy B, a depot not as read and a database without 0758; and refuses a second apply.
A module template carries the fixture, and each test clones it. It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

ROOT = base.ROOT
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "twenty_post_base_stub.sql")
M0759 = os.path.join(ROOT, "db", "migrations", "0759_canopy_b_is_restriped_for_ten_more_robotic_fast_chargers.sql")
DEPOT = base.DEPOT
LIVE = {"public.ottoq_site_buildout_apply(uuid,text)": "cb079839be8f1193989f2ad088f0ab8b",
        "public.ottoq_site_buildout_restore(uuid)": "2c0df4dcab28c428977be901033a2eda",
        "public.ottoq_site_buildout_census(uuid)": "a2663c6fd8bdc090b82f17b981e8785b",
        "public.ottoq_site_buildout_must_not_commit()": "4becb79612000a453dc5e31431324acb",
        "public.ottoq_throughput_scorecard(uuid)": "a591253c15105520d4b6d612059bb2fb",
        "public.ottoq_check_stall_overlap(uuid)": "725e099f3e62f9c8f63c09b167f5563d",
        "public.ottoq_check_fence_containment(uuid)": "6bab817c468c5f803d72dbb39eceb732",
        "public.ottoq_stalls_state_change()": "1b5668fda6c5e0f9eb8565db822180b9",
        "public.ottoq_trg_reassignment_guard()": "b45ed80258565075f6cacc1e841d76c4",
        "public.ottoq_stall_seat_is_exclusive()": "7ce8d314e45733b164b7ad183990f043",
        "public.update_timestamp()": "da5ac28a58c8b4bb30209bf0d3d7082c",
        "public.ottoq_jsonb_diff(jsonb,jsonb)": "00a3c3972f0e06de74310717083c6be2",
        "ottoq.ottoq_active_sim_run_id()": "fa6094556ceb566d485333c5358a9bca"}
# the depot as read on live, 2026-10-19 (0759's P1 digests)
DIGESTS = {"charger_stalls": "26a57f16af59039fd2aba53e83e8a8ae", "other_stalls": "c535463737f7dba1dbbda50b707e0615",
           "chargers": "a626f9ab4d43d011c08be094113b3927", "charger_caps": "f9e774f2c9b9a11b14810c38d908bcf7",
           "buildouts": "4b96d9863b168138c9f655fd69080a54"}
OLD_CODES = ["dcfc10", "dcfc15", "dcfc20", "dcfc20_grid_today", "dcfc40", "dcfc40_cab2400", "dcfc40_grid_dcfc20",
             "dcfc40_grid_today"]
UNIT_FT = 0.4785 / 0.3048
# the layout seed's points for canopy A's pattern at canopy B (render x 143 / 157, rows 88..144), 4 decimals
WEST_X, EAST_X = 215.0738, 237.0522
ROWS_Y = [185.2461, 163.2677, 141.2894, 119.3110, 97.3327]

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _script(d, sql):
    """A multi-statement script on one connection (psql reads it from stdin), every result printed."""
    p = subprocess.run(["psql", *base._conn_args(), "-d", d.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-f", "-"],
                       input=sql, capture_output=True, text=True)
    return p.returncode, [ln for ln in p.stdout.splitlines() if ln.strip()], p.stderr


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        rc, err = d.file(FIXTURE)
        assert rc == 0, f"the fixture did not load: {err}"
        d.val("""INSERT INTO public.ottoq_cert_lineage (name, forces_recert, forces_dial_restart, note, classified_at)
                 VALUES ('0758_a_fast_chargers_cleaning_arm_cleans_the_cabin_while_the_car_charges', false, false,
                         'test premise', now())""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_scr_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0759)
    assert rc == 0, f"0759 did not apply: {err}"
    return err


def _refused(d, needle):
    rc, err = d.file(M0759)
    assert rc != 0 and needle in err, err
    assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0759%'") == "0"
    assert d.val("SELECT count(*) FROM public.stalls WHERE stall_type = 'dcfc'") == "10"


def _sid(d, code):
    return d.val(f"SELECT id FROM public.stalls WHERE depot_id = '{DEPOT}' AND stall_code = '{code}'")


# A structural image of the depot: every stall, charger and capability row, the power limits. A space's state, its car,
# a charger's state and fault, the write times, and a build-out's own name in equipment_config are left out (they move
# every run, or name the build-out rather than the depot).
IMAGE = f"""SELECT jsonb_build_object(
  'stalls', (SELECT jsonb_object_agg(s.id, (to_jsonb(s) - 'updated_at' - 'created_at' - 'status' - 'current_vehicle_id'
                                            - 'reserved_by' - 'reserved_at' - 'reservation_expires_at' - 'equipment_config')
                                           || jsonb_build_object('equipment_config', s.equipment_config - 'buildout'))
               FROM public.stalls s WHERE s.depot_id = '{DEPOT}'),
  'chargers', (SELECT jsonb_object_agg(c.charger_id, to_jsonb(c) - 'updated_at' - 'created_at' - 'station_state'
                                       - 'station_state_changed_at' - 'last_heartbeat_at' - 'last_fault_code'
                                       - 'last_fault_at' - 'last_fault_payload' - 'connector_states')
                 FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = '{DEPOT}'),
  'caps', (SELECT jsonb_object_agg(k.stall_id || '|' || k.asset_class_code || '|' || k.operation_code, k.active)
             FROM public.ottoq_service_point_capabilities k),
  'power', (SELECT jsonb_build_array(dcfc_max_concurrent_kw, service_max_kw) FROM public.depots WHERE id = '{DEPOT}'))"""


def _image(d):
    return d.json(IMAGE)


def _applied_image(d, code):
    """The depot with a build-out applied, read and rolled back; and its receipt."""
    rc, out, err = _script(d, f"""BEGIN;
SELECT public.ottoq_site_buildout_apply('{DEPOT}', '{code}');
{IMAGE};
SELECT public.ottoq_site_buildout_restore('{DEPOT}')->>'restored';
{IMAGE};
ROLLBACK;""")
    assert rc == 0, err
    receipt, applied, restored, back = json.loads(out[0]), json.loads(out[1]), out[2], json.loads(out[3])
    assert restored == "true"
    return receipt, applied, back


# ── the fixture ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_the_fixture_is_the_live_bodies_and_the_depot_as_read(db):
    for fn, m in LIVE.items():
        assert db.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')") == m, fn
    got = db.json(f"""SELECT jsonb_build_object(
      'charger_stalls', (SELECT md5(string_agg(concat_ws('|', s.id, s.stall_code, s.stall_type, round(s.relative_x::numeric, 4),
                   round(s.relative_y::numeric, 4), s.heading_degrees, s.zone, COALESCE(s.ocpp_charger_id::text, '-'),
                   COALESCE(round(s.connector_max_kw, 1)::text, '-'), COALESCE(round(s.absolute_lat::numeric, 8)::text, '-'),
                   COALESCE(round(s.absolute_lng::numeric, 8)::text, '-'), COALESCE(s.display_name, '-'),
                   COALESCE(s.distance_from_entrance::text, '-'), COALESCE(s.equipment_config->>'canopy_side', '-'),
                   COALESCE(s.fiducial_marker_id, '-'), COALESCE(s.uwb_beacon_id, '-'), COALESCE(s.canopy_code, '-'),
                   COALESCE(s.stall_kind, '-')), ';' ORDER BY s.stall_code))
        FROM public.stalls s WHERE s.depot_id = '{DEPOT}' AND s.stall_type IN ('dcfc', 'l2')),
      'other_stalls', (SELECT md5(string_agg(concat_ws('|', s.id, s.stall_code, s.stall_type, round(s.relative_x::numeric, 4),
                   round(s.relative_y::numeric, 4), s.heading_degrees, s.zone, s.stall_kind), ';' ORDER BY s.stall_code))
        FROM public.stalls s WHERE s.depot_id = '{DEPOT}' AND s.stall_type NOT IN ('dcfc', 'l2')),
      'chargers', (SELECT md5(string_agg(concat_ws('|', c.charger_id, c.ocpp_identifier, c.vendor, c.model,
                   COALESCE(c.firmware_version, '-'), COALESCE(c.ocpp_protocol_version, '-'),
                   COALESCE(round(c.max_kw, 1)::text, '-'), c.num_connectors, COALESCE(c.installed_at::text, '-'),
                   COALESCE(c.decommissioned_at::text, '-')), ';' ORDER BY c.ocpp_identifier))
        FROM public.ottoq_ocpp_chargers c WHERE c.depot_id = '{DEPOT}'),
      'charger_caps', (SELECT md5(string_agg(concat_ws('|', k.stall_id, k.asset_class_code, k.pack_id, k.operation_code, k.active,
                   k.source), ';' ORDER BY k.stall_id, k.asset_class_code, k.operation_code))
        FROM public.ottoq_service_point_capabilities k JOIN public.stalls s ON s.id = k.stall_id
       WHERE s.depot_id = '{DEPOT}' AND s.stall_type IN ('dcfc', 'l2')),
      'buildouts', (SELECT md5(string_agg(concat_ws('|', b.buildout_code, b.dcfc_posts, array_to_string(b.convert_l2, ','),
                   round(b.dcfc_max_concurrent_kw, 1), round(b.service_max_kw, 1)), ';' ORDER BY b.buildout_code))
        FROM public.ottoq_site_buildouts b))""")
    assert got == DIGESTS


def test_before_0759_every_buildout_applies_and_restores_to_the_depot_as_built(db):
    built = _image(db)
    for code in OLD_CODES:
        receipt, applied, back = _applied_image(db, code)
        assert back == built, code
        assert sum(1 for s in applied["stalls"].values() if s["stall_type"] == "dcfc") == receipt["dcfc_posts"], code


# ── the base change ──────────────────────────────────────────────────────────────────────────────────────────────────

def test_0759_lays_canopy_b_out_as_canopy_a_and_retires_five_spaces(db):
    before = _image(db)
    notice = _apply(db)
    assert "0759 V5: 0 stored days" in notice
    census = dict(tuple(r.split("|")) for r in db.run(
        f"SELECT stall_type, count(*) FROM public.stalls WHERE depot_id = '{DEPOT}' GROUP BY 1")[1])
    assert census == {"dcfc": "20", "l2": "15", "parking": "5", "staging": "113", "wash_bay": "3", "service_bay": "2"}
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
         WHERE s.depot_id = '{DEPOT}' AND s.canopy_code = 'CANOPY-02' ORDER BY s.stall_code""")[1]]
    assert [p[0] for p in posts] == [f"NASH-DCFC-STALL-{n}" for n in range(11, 21)]
    for i, p in enumerate(posts):
        n, west = 11 + i, i < 5
        assert float(p[1]) == (WEST_X if west else EAST_X) and float(p[2]) == ROWS_Y[i % 5], p
        assert p[3] == ("60" if west else "300") and p[4] == f"CANOPY-02 {'W' if west else 'E'}-{n}", p
        assert p[5:9] == ["dcfc_zone", "350.0", f"FID-D2-{n}-A", f"UWB-D2-{n}"], p
        assert p[9:13] == ["W" if west else "E", "CANOPY-02", "t", "charging"] and float(p[13]) == 10, p
        assert float(p[14]) == 19.0276 and p[15] == f"NASH-DCFC-{n}", p
        assert p[16:21] == ["ABB", "Terra HP 350", "350", "1.4.2", "1.6J"] and p[21:] == ["t", "t", "7", "0"], p
    # the posts share canopy A's rows exactly, 14 units apart in a column
    a_rows = db.run(f"""SELECT DISTINCT relative_y FROM public.stalls WHERE depot_id = '{DEPOT}' AND canopy_code = 'CANOPY-01'
                         ORDER BY 1 DESC""")[1]
    assert [float(y) for y in a_rows] == ROWS_Y
    assert all(abs((ROWS_Y[i] - ROWS_Y[i + 1]) - 14 * UNIT_FT) < 0.001 for i in range(4))
    retired = [r.split("|") for r in db.run(f"""
        SELECT s.stall_code, s.stall_type, s.relative_x IS NULL AND s.relative_y IS NULL, s.ocpp_charger_id IS NULL,
               s.stall_kind, s.zone IS NULL, s.canopy_code IS NULL, s.covered,
               (SELECT count(*) FROM public.ottoq_service_point_capabilities k WHERE k.stall_id = s.id AND k.active),
               c.decommissioned_at IS NOT NULL, c.station_state
          FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.ocpp_identifier = replace(s.stall_code, '-STALL', '')
         WHERE s.depot_id = '{DEPOT}' AND s.stall_type = 'parking' ORDER BY s.stall_code""")[1]]
    assert retired == [[f"NASH-L2-STALL-{n}", "parking", "t", "t", "retired", "t", "t", "f", "0", "t", "Unavailable"]
                       for n in range(11, 16)]
    assert db.val(f"""SELECT count(*) FROM public.stalls WHERE depot_id = '{DEPOT}'
                       AND stall_code ~ '^NASH-L2-STALL-(0[1-9]|10)$'""") == "0"
    assert db.val(f"""SELECT dcfc_max_concurrent_kw || '/' || service_max_kw || '/' || (site_layout->>'dcfc_count') || '/'
                             || (site_layout->>'l2_count') FROM public.depots WHERE id = '{DEPOT}'""") == "3600/4363/20/15"
    assert db.val(f"""SELECT title || '|' || (properties->'chargers')::text || '|' || (properties->>'stall_capacity') || '|'
                             || (properties->>'solar_kw_dc') FROM public.ottoq_site_structures
                       WHERE depot_id = '{DEPOT}' AND structure_code = 'CANOPY-02'""") == 'Solar Canopy B (DCFC)|{"dcfc": 10}|10|180'
    assert db.val(f"SELECT public.ottoq_check_stall_overlap('{DEPOT}')->>'passed'") == "true"
    assert db.val(f"SELECT public.ottoq_check_fence_containment('{DEPOT}')->>'passed'") == "true"
    # nothing else moved: the other 143 spaces, their capabilities and the other 35 chargers, row for row
    after = _image(db)
    moved = {_sid(db, f"NASH-DCFC-STALL-{n}") for n in range(11, 21)} | {_sid(db, f"NASH-L2-STALL-{n}") for n in range(11, 16)}
    assert len(moved) == 15
    for sid, row in before["stalls"].items():
        if sid not in moved:
            assert after["stalls"][sid] == row, sid
    moved_chargers = {r for r in db.run(f"""SELECT charger_id FROM public.ottoq_ocpp_chargers
                                            WHERE ocpp_identifier ~ '^NASH-(DCFC-(1[1-9]|20)|L2-1[1-5])$'""")[1]}
    assert len(moved_chargers) == 15
    for cid, row in before["chargers"].items():
        if cid not in moved_chargers:
            assert after["chargers"][cid] == row, cid
    for key, active in before["caps"].items():
        if key.split("|")[0] not in moved:
            assert after["caps"][key] == active, key
    assert db.val("""SELECT forces_recert || '/' || forces_dial_restart FROM public.ottoq_cert_lineage
                      WHERE name = '0759_canopy_b_is_restriped_for_ten_more_robotic_fast_chargers'""") == "true/true"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0759_pre' AND object_kind = 'function'") == "3"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0759_pre' AND object_kind = 'rows'") == "3"


def test_0759_signs_one_event_per_moved_space_as_the_migration_to_no_run(db):
    _apply(db)
    rows = [r.split("|") for r in db.run("""
        SELECT e.actor_type, e.actor_id, e.event_type, e.sim_run_id IS NULL, e.data_source,
               e.payload->'diff' ? 'stall_type', count(*)
          FROM public.ottoq_events e WHERE e.actor_id = '0759' GROUP BY 1, 2, 3, 4, 5, 6 ORDER BY 1""")[1]]
    assert rows == [["migration_script", "0759", "stall.state_changed", "t", "twin", "t", "15"]]
    assert db.val("SELECT count(DISTINCT entity_id) FROM public.ottoq_events WHERE actor_id = '0759'") == "15"


# ── the build-outs after the base change ─────────────────────────────────────────────────────────────────────────────

def test_after_0759_every_buildout_round_trips_and_the_old_ones_are_the_days_they_were(db):
    old_base = _image(db)
    old = {code: _applied_image(db, code) for code in OLD_CODES}
    _apply(db)
    new_base = _image(db)
    assert new_base != old_base
    codes = [r for r in db.run("SELECT buildout_code FROM public.ottoq_site_buildouts ORDER BY 1")[1]]
    assert codes == sorted(OLD_CODES + ["dcfc20_in_place", "dcfc30"])
    for code in codes:
        receipt, applied, back = _applied_image(db, code)
        assert back == new_base, code
        was = {"dcfc20_in_place": "dcfc20"}.get(code, code)
        if code in ("dcfc20", "dcfc20_grid_today", "dcfc30"):
            continue
        old_receipt, old_applied, _ = old[was]
        assert applied == old_applied, code
        assert receipt["converted_stall_ids"] == old_receipt["converted_stall_ids"], code
        assert receipt["buildable"] is (code == "dcfc10"), code
        # the receipt names every space the day changed and its type that day: the set's fifteen and the conversions
        changed = {e["stall_id"] for e in receipt["stall_set"]} | set(receipt["converted_stall_ids"])
        assert len(receipt["stall_set"]) == 15 and set(receipt["stall_types"]) == changed, code
        assert all(receipt["stall_types"][i] == "dcfc" for i in receipt["converted_stall_ids"]), code
    # dcfc10 is the depot as it stood until 0759, row for row
    assert _applied_image(db, "dcfc10")[1] == old_base
    # dcfc20 is the new depot, dcfc20_grid_today the same on today's grid
    receipt, applied, _ = _applied_image(db, "dcfc20")
    assert applied == new_base and receipt["stall_set"] == [] and receipt["buildable"] is True
    receipt, applied, _ = _applied_image(db, "dcfc20_grid_today")
    assert {k: v for k, v in applied.items() if k != "power"} == {k: v for k, v in new_base.items() if k != "power"}
    assert applied["power"] == [1800, 2500]


def test_dcfc30_lays_canopy_c_out_as_canopy_b(db):
    _apply(db)
    rc, out, err = _script(db, f"""BEGIN;
SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'dcfc30')->>'buildable';
SELECT string_agg(stall_type || ':' || n, ',' ORDER BY stall_type) FROM (SELECT stall_type::text, count(*) n FROM public.stalls
  WHERE depot_id = '{DEPOT}' GROUP BY 1) z;
SELECT string_agg(s.stall_code || '@' || s.relative_x || ',' || s.relative_y || '/' || s.heading_degrees || '/' || c.ocpp_identifier,
                  ' ' ORDER BY s.stall_code)
  FROM public.stalls s JOIN public.ottoq_ocpp_chargers c ON c.charger_id = s.ocpp_charger_id
 WHERE s.depot_id = '{DEPOT}' AND s.canopy_code = 'CANOPY-03';
SELECT public.ottoq_check_stall_overlap('{DEPOT}')->>'passed';
SELECT dcfc_max_concurrent_kw || '/' || service_max_kw FROM public.depots WHERE id = '{DEPOT}';
ROLLBACK;""")
    assert rc == 0, err
    assert out[0] == "true"
    assert out[1] == "dcfc:30,parking:10,service_bay:2,staging:113,wash_bay:3"
    expect = " ".join(f"NASH-DCFC-STALL-{n}@{x},{ROWS_Y[(n - 21) % 5]}/{h}/NASH-DCFC-{n}"
                      for n, x, h in [(n, 288.8583 if n <= 25 else 310.8366, 60 if n <= 25 else 300) for n in range(21, 31)])
    assert out[2] == expect
    assert out[3] == "true" and out[4] == "5400/6226"


# ── the past ─────────────────────────────────────────────────────────────────────────────────────────────────────────

def _runs(d):
    """Three completed days before 0759: no receipt, dcfc10's, and old dcfc20's (L2-01..10 converted), each with
    charges on NASH-DCFC-STALL-01, NASH-L2-STALL-01, NASH-L2-STALL-12 and NASH-L2-STALL-16, and a few visits."""
    ids = {c: _sid(d, c) for c in ("NASH-DCFC-STALL-01", "NASH-L2-STALL-01", "NASH-L2-STALL-12", "NASH-L2-STALL-16")}
    conv = [_sid(d, f"NASH-L2-STALL-{n:02d}") for n in range(1, 11)]
    runs = {"none": None,
            "dcfc10": {"buildout_code": "dcfc10", "dcfc_posts": 10, "converted_stall_ids": [],
                       "dcfc_max_concurrent_kw": 1800, "service_max_kw": 2500},
            "dcfc20": {"buildout_code": "dcfc20", "dcfc_posts": 20, "converted_stall_ids": conv,
                       "dcfc_max_concurrent_kw": 3600, "service_max_kw": 4363}}
    out = {}
    for i, (kind, receipt) in enumerate(runs.items()):
        run = str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0759-run-{kind}"))
        payload = "'{}'::jsonb" if receipt is None else f"""'{json.dumps({"site_buildout": receipt})}'::jsonb"""
        d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, scenario_code, random_seed, tick_count, policy,
                                                     started_at, ended_at, sim_clock_start, sim_clock_current,
                                                     tick_interval_seconds, time_scale, payload)
                  VALUES ('{run}', '{DEPOT}', 'completed', 'normal_day', 42, 108, 'otto_q', now() - interval '{3 - i} days',
                          now() - interval '{3 - i} days', '2026-09-01 11:00+00', '2026-09-01 20:00+00', 300, 1, {payload})""")
        for j, (code, sid) in enumerate(ids.items()):
            d.val(f"""INSERT INTO public.ocpp_sessions (stall_id, started_at, ended_at, energy_delivered_kwh, avg_power_kw,
                                                        sim_run_id)
                      VALUES ('{sid}', '2026-09-01 12:00+00'::timestamptz + interval '{j * 20} minutes',
                              '2026-09-01 12:40+00'::timestamptz + interval '{j * 20} minutes', {30 + j}, {45 + 10 * j},
                              '{run}')""")
        for k in range(3):
            d.val(f"""INSERT INTO public._test_visit_outcomes (sim_run_id, visit_id, vehicle_id, tier_group, arrived_at, due_at,
                                                               departed_at, door_min, on_time, late_min, soc_out, target_soc,
                                                               needed_open_at_departure, cleared_by_triage,
                                                               done_without_time, in_depot_at_horizon)
                      VALUES ('{run}', gen_random_uuid(), gen_random_uuid(), 'standard', '2026-09-01 12:00+00',
                              '2026-09-01 14:00+00', '2026-09-01 13:{10 + k}:00+00', {70 + k}, true, NULL, 99, 100, 0, 0,
                              0, false)""")
        out[kind] = run
    return out


def _score(d, run):
    return d.json(f"SELECT public.ottoq_throughput_scorecard('{run}')")


def test_the_scorecard_reads_a_day_as_it_ran_after_0759(db):
    runs = _runs(db)
    before = {k: _score(db, r) for k, r in runs.items()}
    assert [(before[k]["fast_chargers"]["sessions"], before[k]["l2_sessions"], before[k]["fast_chargers"]["at_depot"])
            for k in ("none", "dcfc10", "dcfc20")] == [(1, 3, 10), (1, 3, 10), (2, 2, 20)]
    notice = _apply(db)
    assert "0759 V5: 3 stored days, one of each kind, score the same after the base change" in notice
    for kind, run in runs.items():
        after = _score(db, run)
        assert after["scorecard_version"] == "0759"
        assert {k: v for k, v in after.items() if k != "scorecard_version"} == \
               {k: v for k, v in before[kind].items() if k != "scorecard_version"}, kind
    # without the patch the base change rewrites them: the scorecard as it stood before 0759, run on the new depot
    rc, out, err = _script(db, f"""BEGIN;
DO $$ BEGIN EXECUTE (SELECT definition FROM public.ottoq_schema_snapshots
                      WHERE label = '0759_pre' AND object_name = 'ottoq_throughput_scorecard'); END $$;
SELECT public.ottoq_throughput_scorecard('{runs["none"]}');
SELECT public.ottoq_throughput_scorecard('{runs["dcfc10"]}');
ROLLBACK;""")
    assert rc == 0, err
    stale_none, stale_dcfc10 = json.loads(out[0]), json.loads(out[1])
    assert (stale_none["fast_chargers"]["sessions"], stale_none["l2_sessions"], stale_none["fast_chargers"]["at_depot"]) == (2, 1, 20)
    assert (stale_dcfc10["fast_chargers"]["sessions"], stale_dcfc10["l2_sessions"]) == (2, 1)


def test_a_day_run_on_dcfc10_after_0759_is_scored_from_its_receipt(db):
    _apply(db)
    post11, post01 = _sid(db, "NASH-DCFC-STALL-11"), _sid(db, "NASH-DCFC-STALL-01")
    run = str(uuid.uuid5(uuid.NAMESPACE_DNS, "0759-run-after"))
    rc, out, err = _script(db, f"""BEGIN;
CREATE TEMP TABLE r ON COMMIT DROP AS SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'dcfc10') AS receipt;
SELECT stall_code || '/' || stall_type FROM public.stalls WHERE id = '{post11}';
INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, scenario_code, random_seed, tick_count, policy, started_at,
                                   ended_at, sim_clock_start, sim_clock_current, tick_interval_seconds, time_scale, payload)
SELECT '{run}', '{DEPOT}', 'completed', 'normal_day', 42, 108, 'otto_q', now(), now(), '2026-09-01 11:00+00',
       '2026-09-01 20:00+00', 300, 1, jsonb_build_object('site_buildout', r.receipt) FROM r;
INSERT INTO public.ocpp_sessions (stall_id, started_at, ended_at, energy_delivered_kwh, avg_power_kw, sim_run_id) VALUES
  ('{post11}', '2026-09-01 12:00+00', '2026-09-01 14:00+00', 35, 18, '{run}'),
  ('{post01}', '2026-09-01 12:00+00', '2026-09-01 12:30+00', 40, 160, '{run}');
SELECT public.ottoq_site_buildout_restore('{DEPOT}')->>'restored';
COMMIT;""")
    assert rc == 0, err
    assert out == ["NASH-L2-STALL-01/l2", "true"]
    sc = _score(db, run)
    assert (sc["fast_chargers"]["sessions"], sc["l2_sessions"], sc["fast_chargers"]["at_depot"]) == (1, 1, 10)
    assert sc["run"]["site_buildout"] == "dcfc10"
    assert db.json(f"SELECT payload->'site_buildout'->'stall_types' FROM public.ottoq_sim_runs WHERE sim_run_id = '{run}'")[post11] == "l2"


def test_the_base_history_is_append_only_and_answers_the_type_a_space_had(db):
    _apply(db)
    post11, retired, a01 = _sid(db, "NASH-DCFC-STALL-11"), _sid(db, "NASH-L2-STALL-12"), _sid(db, "NASH-DCFC-STALL-01")
    assert db.val(f"SELECT public.ottoq_stall_type_at('{post11}', now() - interval '1 hour')") == "l2"
    assert db.val(f"SELECT public.ottoq_stall_type_at('{retired}', now() - interval '1 hour')") == "l2"
    assert db.val(f"SELECT public.ottoq_stall_type_at('{post11}', now() + interval '1 hour') IS NULL") == "t"
    assert db.val(f"SELECT public.ottoq_stall_type_at('{a01}', now() - interval '1 hour') IS NULL") == "t"
    for sql in ("UPDATE public.ottoq_site_base_history SET stall_type = 'dcfc'",
                "DELETE FROM public.ottoq_site_base_history",
                "TRUNCATE public.ottoq_site_base_history"):
        rc, _, err = db.run(sql)
        assert rc != 0 and "append-only" in err, sql
    assert db.val("SELECT count(*) FROM public.ottoq_site_base_history WHERE change_code = '0759'") == "15"


# ── the new apply and restore ────────────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("entry, needle", [
    ('{{"stall_id": "{a}", "stall": {{"status": "closed"}}}}', "sets space columns a build-out may not set: status"),
    ('{{"stall_id": "{other}", "stall": {{"zone": "x"}}}}', "that is not at depot"),
    ('{{"stall_id": "{a}", "charger_id": "{a}", "charger": {{"max_kw": 1}}}}', "sets a charger"),
    ('{{"stall_id": "{a}", "capabilities": {{"operation_to": "charge_l2"}}}}', "sets a capability the way a build-out may not"),
])
def test_apply_refuses_a_stall_set_it_may_not_apply(db, entry, needle):
    _apply(db)
    a = _sid(db, "NASH-DCFC-STALL-01")
    db.val("INSERT INTO public.depots (id, feed_mode) VALUES ('22222222-2222-2222-2222-222222222222', 'sim')")
    other = db.val("""INSERT INTO public.stalls (depot_id, stall_code, stall_type)
                      VALUES ('22222222-2222-2222-2222-222222222222', 'OTHER-1', 'l2') RETURNING id""")
    db.val(f"""INSERT INTO public.ottoq_site_buildouts (buildout_code, depot_id, title, dcfc_posts, dcfc_max_concurrent_kw,
                                                        service_max_kw, basis, stall_set)
               VALUES ('bad', '{DEPOT}', 'bad', 20, 3600, 4363, '{{}}', '[{entry.format(a=a, other=other)}]'::jsonb)""")
    built = _image(db)
    rc, _, err = db.run(f"SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'bad')")
    assert rc != 0 and needle in err, err
    assert _image(db) == built


def test_apply_refuses_a_set_that_names_a_space_twice(db):
    _apply(db)
    a = _sid(db, "NASH-DCFC-STALL-01")
    db.val(f"""INSERT INTO public.ottoq_site_buildouts (buildout_code, depot_id, title, dcfc_posts, dcfc_max_concurrent_kw,
                                                        service_max_kw, basis, stall_set)
               VALUES ('twice', '{DEPOT}', 'twice', 20, 3600, 4363, '{{}}',
                       '[{{"stall_id": "{a}", "stall": {{"zone": "a"}}}}, {{"stall_id": "{a}", "stall": {{"zone": "b"}}}}]'::jsonb)""")
    rc, _, err = db.run(f"SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'twice')")
    assert rc != 0 and "sets a space twice" in err, err


def test_a_buildout_with_a_set_still_cannot_commit_unrestored(db):
    _apply(db)
    built = _image(db)
    rc, _, err = db.run(f"SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'dcfc10')")
    assert rc != 0 and "is still applied to depot" in err, err
    assert _image(db) == built
    assert db.val("SELECT count(*) FROM public.ottoq_site_buildout_active") == "0"


def test_restore_refuses_a_capability_it_did_not_put_back(db):
    _apply(db)
    post11 = _sid(db, "NASH-DCFC-STALL-11")
    rc, _, err = _script(db, f"""BEGIN;
SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'dcfc15');
UPDATE public.ottoq_service_point_capabilities SET active = false
 WHERE stall_id = '{post11}' AND operation_code = 'sensor_clean' AND asset_class_code = 'generic_robotaxi';
SELECT public.ottoq_site_buildout_restore('{DEPOT}');
ROLLBACK;""")
    assert rc == 0, err  # an active flag the day changed is put back from the pre-image
    rc, _, err = _script(db, f"""BEGIN;
SELECT public.ottoq_site_buildout_apply('{DEPOT}', 'dcfc15');
DELETE FROM public.ottoq_service_point_capabilities
 WHERE stall_id = '{post11}' AND operation_code = 'sensor_clean' AND asset_class_code = 'generic_robotaxi';
SELECT public.ottoq_site_buildout_restore('{DEPOT}');
ROLLBACK;""")
    assert rc != 0 and "did not put back the capabilities of space" in err, err


# ── what 0759 refuses ────────────────────────────────────────────────────────────────────────────────────────────────

@pytest.mark.parametrize("setup, needle", [
    (f"INSERT INTO public.ottoq_throughput_sweeps (sweep_code, depot_id, status) VALUES ('s', '{DEPOT}', 'active')",
     "research sweeps are active at the twin depot"),
    (f"INSERT INTO public.ottoq_dial_experiments (depot_id, param_key, status) VALUES ('{DEPOT}', 'k', 'active')",
     "dial experiments are active at the twin depot"),
    (f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at)
         VALUES (gen_random_uuid(), '{DEPOT}', 'running', now())""", "a run is live at the twin depot"),
    ("ALTER DATABASE {name} SET test.in_flight = '1'", "is running right now"),
])
def test_0759_refuses_while_anything_is_queued_or_running(db, setup, needle):
    db.val(setup.format(name=db.name))
    _refused(db, needle)


def test_0759_lets_a_paused_sweep_and_a_concluded_experiment_stand(db):
    db.val(f"INSERT INTO public.ottoq_throughput_sweeps (sweep_code, depot_id, status) VALUES ('p', '{DEPOT}', 'paused')")
    db.val(f"INSERT INTO public.ottoq_dial_experiments (depot_id, param_key, status) VALUES ('{DEPOT}', 'k', 'concluded')")
    _apply(db)


@pytest.mark.parametrize("setup, needle", [
    ("""DO $$ BEGIN EXECUTE replace(pg_get_functiondef('public.ottoq_throughput_scorecard(uuid)'::regprocedure),
                                    $a$'scorecard_version', '0567'$a$, $b$'scorecard_version', '0567 '$b$); END $$""",
     "not the bodies this file was written against"),
    (f"""UPDATE public.stalls SET current_vehicle_id = gen_random_uuid()
          WHERE depot_id = '{DEPOT}' AND stall_code = 'NASH-L2-STALL-13'""", "a car, a reservation or an open booking is on canopy B"),
    (f"""INSERT INTO public.ottoq_stall_bookings (stall_id, state)
         SELECT id, 'held' FROM public.stalls WHERE depot_id = '{DEPOT}' AND stall_code = 'NASH-L2-STALL-02'""",
     "a car, a reservation or an open booking is on canopy B"),
    (f"UPDATE public.depots SET service_max_kw = 2600 WHERE id = '{DEPOT}'", "is not as read on 2026-10-19"),
    (f"""UPDATE public.stalls SET relative_y = relative_y + 1
          WHERE depot_id = '{DEPOT}' AND stall_code = 'NASH-L2-STALL-03'""", "is not as read on 2026-10-19"),
    ("DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0758%'", "0758 is not applied"),
    ("""CREATE FUNCTION public.ottoq_pick_parking() RETURNS text LANGUAGE sql AS $$ SELECT 'parking'::text $$""",
     "name the parking type"),
])
def test_0759_refuses_a_world_it_was_not_written_against(db, setup, needle):
    db.val(setup)
    _refused(db, needle)


def test_0759_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0759)
    assert rc != 0 and ("0759 P1" in err or "0759 P2" in err), err
    assert db.val("SELECT count(*) FROM public.ottoq_site_base_history") == "15"
