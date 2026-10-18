"""db/migrations/0752, EXECUTED: a service reported done ends in its itinerary leg and its service record.

WHY THIS EXISTS. In production a robot or a technician reports the work it finished through
public.ottoq_ingest_service_complete, with the list of services done, and the seam only marked the atoms and credited
wear: no leg was closed, so no SDR was issued, and no completion was judged at task_completion. The twin's own completion
of the same work does both and runs only where the twin feeds the depot, so a real feed would have left the work done in
place with no service record (G466, db/checks/0456). 0752's public.ottoq_close_reported_work_legs, called by the seam
before it marks the atoms, closes them. Every claim in 0752's header about it is executed here, on the scratch
PostgreSQL, against the helper exactly as 0752 writes it and the seam exactly as 0752 patches it, through the live seam,
atom marker, atom leg close, leg helpers, leg trigger and SDR emitter (tests/fixtures/reported_work_stub.sql and
tests/fixtures/bay_exit_leg_stub.sql, md5 asserted):
  - at the dial's default a report marks its atoms and credits wear as before, closes nothing, and its reply and event
    are today's;
  - with the dial on, each reported service done in place closes its planned leg with the atom's start and the
    report's clock, the leg trigger issues its SDR (production's at a depot a real feed drives), it is judged at
    task_completion, and the reply and the event carry the records;
  - a bay service and a charge are left to their own doors, and named as left;
  - only what the visit still has outstanding is closed, and a service with no planned leg closes nothing;
  - the readiness check closes its leg and is not probed, as the twin's readiness branch;
  - a failure in the records never fails the report, and with no live run nothing is closed;
  - no API role but service_role can call the helper.
The seam's patch is proven on its live body by 0752's V1 at apply (and here, in the template's setup), and the whole path
on live by its V3. It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import sys
import tempfile
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
LEGS = os.path.join(ROOT, "tests", "fixtures", "bay_exit_leg_stub.sql")
STUB = os.path.join(ROOT, "tests", "fixtures", "reported_work_stub.sql")
M0752 = os.path.join(ROOT, "db", "migrations", "0752_a_service_reported_done_ends_in_its_leg_and_its_service_record.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000752"
T = "2026-09-01 15:00:00+00"
LIVE = {"ottoq_ingest_service_complete": "e64f53765109e6cad248150cc6f75bc3",
        "ottoq_mark_visit_atoms_done": "be7dc4f2393b0b451543e12450f2df88",
        "ottoq_close_atom_leg": "efd2dbb8701e59a2be02500e53c03191",
        "ottoq_itin_leg_close": "6c33d450e023f83882cbb95f0f4b150f", "ottoq_itin_leg_open": "69effd4b79c76a99b2cb019410172164",
        "ottoq_trg_leg_done_sdr": "8aa4c329836bdb7e0588defe75404498", "ottoq_emit_sdr": "25e9cbb1a3040668fa47125dd43d02c3"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0752-{name}"))


def _patch_sql():
    """0752's helper and its patch of the seam with V1, exactly as the migration writes them, in one transaction."""
    with open(M0752) as f:
        text = f.read()
    part = text[text.index("-- ── (b) the reported work closes its legs ──"):
                text.index("-- ── V2: at the dial's default")]
    return "BEGIN;\n" + part + "COMMIT;\n"


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_rwt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, LEGS, STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        for fn, md5 in LIVE.items():
            got = d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE proname = '{fn}'")
            assert got == md5, f"{fn} is not the live body read (md5 {got})"
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(_patch_sql())
            path = f.name
        try:
            rc, err = d.file(path)
        finally:
            os.remove(path)
        assert rc == 0, f"0752's helper and patch did not apply: {err}"
        d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start, sim_clock_current)
                  VALUES ('{RUN}', '{DEPOT}', 'running', '{T}'::timestamptz - interval '4 hours',
                          '{T}'::timestamptz - interval '4 hours', '{T}')""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_rw_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _dial(d, value=1):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'bay_exit_closes_its_leg', {value}, 'test', now())
              ON CONFLICT (scope_type, scope_id, param_key) DO UPDATE SET param_value = EXCLUDED.param_value""")


def _car(d, name, state="charging_dcfc"):
    vid = _id(name)
    sid = _id(name + "-stall")
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, display_name, status)
              VALUES ('{sid}', '{DEPOT}', 'dcfc', '{name}-S', '{name}-S', 'occupied')""")
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change,
                                           vehicle_class_code, current_stall_id)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{T}'::timestamptz - interval '1 hour',
                      'robotaxi', '{sid}')""")
    return vid, sid


def _visit(d, car, atoms, run=RUN):
    run_sql = "NULL" if run is None else f"'{run}'"
    return d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, atoms,
                                                           status, source)
                     VALUES ('{car}', {run_sql}, '{DEPOT}', '{T}'::timestamptz - interval '1 hour', 'v-{car}',
                             '{json.dumps(atoms)}'::jsonb, 'in_progress', 'test')
                     RETURNING visit_id""")


def _itin(d, car, run=RUN):
    return d.val(f"""INSERT INTO public.ottoq_vehicle_itineraries (sim_run_id, depot_id, vehicle_id, created_by, sim_created_at)
                     VALUES ('{run}', '{DEPOT}', '{car}', 'flow_contract_m4', '{T}'::timestamptz - interval '1 hour')
                     RETURNING itinerary_id""")


def _leg(d, itin, car, seq, leg_type, atom, start_min=-30, end_min=-20, run=RUN):
    return d.val(f"""INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type,
                                                              planned_start_sim, planned_end_sim, planned_duration_s,
                                                              duration_basis, status)
                     VALUES ('{itin}', '{run}', '{car}', {seq}, '{leg_type}',
                             '{T}'::timestamptz + interval '{start_min} minutes',
                             '{T}'::timestamptz + interval '{end_min} minutes', {(end_min - start_min) * 60},
                             '{json.dumps({"kind": "flow_contract", "atom": atom})}'::jsonb, 'planned')
                     RETURNING leg_id""")


def _report(d, car, services):
    arr = "ARRAY[" + ",".join(f"'{s}'" for s in services) + "]::text[]"
    return json.loads(d.val(f"SELECT public.ottoq_ingest_service_complete('{car}', 'production', 'robot-07', {arr})"))


def _leg_row(d, leg):
    return d.val(f"""SELECT status || '|' || COALESCE(actual_start_sim::text, '-') || '|' || COALESCE(actual_end_sim::text, '-')
                            || '|' || COALESCE(deviation_s::text, '-') || '|' || COALESCE(to_stall_id::text, '-')
                     FROM public.ottoq_itinerary_legs WHERE leg_id = '{leg}'""")


def _sdr(d, leg):
    return d.val(f"""SELECT operation_code || '|' || COALESCE(started_at::text, '-') || '|' || ended_at::text || '|'
                            || COALESCE(duration_min::text, '-') || '|' || source_kind || '|' || data_source || '|'
                            || COALESCE(stall_id::text, '-')
                     FROM public.ottoq_service_detail_records WHERE leg_id = '{leg}'""")


def _calls(d, fn):
    return d.val(f"""SELECT COALESCE(string_agg(svc || '@' || COALESCE(started_at::text, '-') || '>' || COALESCE(ended_at::text, '-'),
                                                ',' ORDER BY n), '')
                     FROM public.reported_work_calls WHERE fn = '{fn}'""")


def _event(d, car):
    return json.loads(d.val(f"""SELECT payload FROM public.ottoq_events
                                WHERE event_type = 'ops.services_completed_reported' AND entity_id = '{car}'
                                ORDER BY event_seq DESC LIMIT 1"""))


def test_the_seam_is_patched_from_its_live_body(db):
    # V1 ran in the template's patch transaction and raised nothing: the seam less its edits is e64f5376
    assert db.val("""SELECT position('v_records := public.ottoq_close_reported_work_legs(' in prosrc) > 0
                            AND position('jsonb_build_object(''records'', v_records)' in prosrc) > 0
                       FROM pg_proc WHERE proname = 'ottoq_ingest_service_complete'""") == "t"


def test_at_the_default_a_report_marks_and_credits_and_closes_nothing(db):
    car, _ = _car(db, "AV-1")
    _visit(db, car, [{"svc": "sensor_clean", "status": "in_progress", "started_at": "2026-09-01T14:45:00+00:00"}])
    itin = _itin(db, car)
    leg = _leg(db, itin, car, 1, "sensor_clean", "sensor_clean")
    reply = _report(db, car, ["sensor_clean"])
    assert reply == {"ok": True, "vehicle_id": car, "services_reported": ["sensor_clean"], "atoms_matched": 1,
                     "note": None}
    assert _leg_row(db, leg).startswith("planned|")
    assert db.val("SELECT count(*) FROM public.ottoq_service_detail_records") == "0"
    assert _calls(db, "wear").startswith("sensor_clean@") and _calls(db, "probe") == ""
    assert "records" not in _event(db, car)
    assert db.val(f"""SELECT a->>'status' FROM public.ottoq_visit_needs vn, jsonb_array_elements(vn.atoms) a
                      WHERE vn.vehicle_id = '{car}'""") == "done"


def test_a_report_closes_its_work_in_place_with_its_records(db):
    _dial(db)
    car, stall = _car(db, "AV-2")
    _visit(db, car, [{"svc": "sensor_clean", "status": "in_progress", "started_at": "2026-09-01T14:45:00+00:00"},
                     {"svc": "software_update", "status": "pending"}])
    itin = _itin(db, car)
    clean = _leg(db, itin, car, 1, "sensor_clean", "sensor_clean", -15, -9)
    update = _leg(db, itin, car, 2, "software_update", "software_update", -15, 15)
    reply = _report(db, car, ["sensor_clean", "software_update"])
    rec = reply["records"]
    assert reply["atoms_matched"] == 2 and reply["ok"] is True
    assert rec["legs_closed"] == 2 and rec["in_place"] == ["sensor_clean", "software_update"]
    assert rec["probed"] == ["sensor_clean", "software_update"]
    assert rec["left_to_the_bay_exit"] == [] and rec["left_to_the_charge"] == []
    assert _leg_row(db, clean) == f"done|2026-09-01 14:45:00+00|{T}|540|{stall}"
    assert _leg_row(db, update) == f"done|-|{T}|-900|{stall}"
    assert _sdr(db, clean) == f"sensor_clean|2026-09-01 14:45:00+00|{T}|15.00|itinerary_leg|twin|{stall}"
    assert _sdr(db, update) == f"software_update|-|{T}|-|itinerary_leg|twin|{stall}"
    sdrs = db.val(f"""SELECT string_agg(sdr_id::text, ',' ORDER BY sdr_seq) FROM public.ottoq_service_detail_records""")
    assert rec["service_records"] == sdrs.split(",")
    assert _calls(db, "probe") == f"sensor_clean@2026-09-01 14:45:00+00>{T},software_update@->{T}"
    assert _event(db, car)["records"] == rec


def test_a_depot_a_real_feed_drives_issues_production_records(db):
    _dial(db)
    db.val(f"UPDATE public.depots SET feed_mode = 'external' WHERE id = '{DEPOT}'")
    car, _ = _car(db, "AV-3", state="staged_awaiting_service")
    _visit(db, car, [{"svc": "interior_tidy", "status": "pending"}])
    leg = _leg(db, _itin(db, car), car, 1, "interior_tidy", "interior_tidy")
    assert _report(db, car, ["interior_tidy"])["records"]["legs_closed"] == 1
    assert _sdr(db, leg).split("|")[5] == "production"


def test_bay_work_and_a_charge_are_left_to_their_own_doors(db):
    _dial(db)
    car, _ = _car(db, "AV-4", state="staged_awaiting_service")
    _visit(db, car, [{"svc": "exterior_wash", "status": "pending"}, {"svc": "charge", "status": "pending"},
                     {"svc": "sensor_clean", "status": "pending"}])
    itin = _itin(db, car)
    wash = _leg(db, itin, car, 1, "wash", "exterior_wash")
    charge = _leg(db, itin, car, 2, "charge_dcfc", "charge")
    clean = _leg(db, itin, car, 3, "sensor_clean", "sensor_clean")
    reply = _report(db, car, ["exterior_wash", "charge", "sensor_clean"])
    assert reply["atoms_matched"] == 3
    assert reply["records"]["left_to_the_bay_exit"] == ["exterior_wash"]
    assert reply["records"]["left_to_the_charge"] == ["charge"]
    assert reply["records"]["legs_closed"] == 1 and reply["records"]["probed"] == ["sensor_clean"]
    assert _leg_row(db, wash).startswith("planned|") and _leg_row(db, charge).startswith("planned|")
    assert _leg_row(db, clean).startswith("done|")


def test_only_what_the_visit_still_has_outstanding_is_closed(db):
    _dial(db)
    car, _ = _car(db, "AV-5", state="staged_awaiting_service")
    _visit(db, car, [{"svc": "sensor_clean", "status": "done", "done_at": "2026-09-01T14:30:00+00:00"},
                     {"svc": "item_retrieval", "status": "cancelled"},
                     {"svc": "remote_diagnostics", "status": "pending"},
                     {"svc": "software_update", "status": "pending"}])
    itin = _itin(db, car)
    clean = _leg(db, itin, car, 1, "sensor_clean", "sensor_clean")
    item = _leg(db, itin, car, 2, "item_retrieval", "item_retrieval")
    diag = _leg(db, itin, car, 3, "remote_diagnostics", "remote_diagnostics")
    update = _leg(db, itin, car, 4, "software_update", "software_update")
    reply = _report(db, car, ["sensor_clean", "item_retrieval", "remote_diagnostics", "triage_check"])
    assert reply["atoms_matched"] == 1
    assert reply["records"]["in_place"] == ["remote_diagnostics"] and reply["records"]["legs_closed"] == 1
    assert _leg_row(db, diag).startswith("done|")
    for leg in (clean, item, update):
        assert _leg_row(db, leg).startswith("planned|")


def test_a_reported_service_with_no_planned_leg_closes_nothing(db):
    _dial(db)
    car, _ = _car(db, "AV-6", state="staged_awaiting_service")
    _visit(db, car, [{"svc": "software_update", "status": "pending"}, {"svc": "sensor_clean", "status": "pending"}])
    leg = _leg(db, _itin(db, car), car, 1, "sensor_clean", "sensor_clean")
    reply = _report(db, car, ["software_update", "sensor_clean"])
    assert reply["records"]["in_place"] == ["software_update", "sensor_clean"]
    assert reply["records"]["legs_closed"] == 1 and len(reply["records"]["service_records"]) == 1
    assert _leg_row(db, leg).startswith("done|")


def test_the_readiness_check_closes_its_leg_and_is_not_probed(db):
    _dial(db)
    car, _ = _car(db, "AV-7", state="staged_for_departure")
    _visit(db, car, [{"svc": "readiness_check", "status": "pending"}])
    leg = _leg(db, _itin(db, car), car, 1, "inspect", "readiness_check")
    reply = _report(db, car, ["readiness_check"])
    assert reply["records"]["legs_closed"] == 1 and reply["records"]["probed"] == []
    assert _leg_row(db, leg).startswith("done|") and _sdr(db, leg).startswith("inspect|")
    assert _calls(db, "probe") == ""


def test_a_failure_in_the_records_never_fails_the_report(db):
    _dial(db)
    db.val("""CREATE OR REPLACE FUNCTION public.ottoq_close_atom_leg(p_sim_run_id uuid, p_vehicle uuid, p_svc text,
                                                                     p_started timestamptz, p_ended timestamptz)
              RETURNS void LANGUAGE plpgsql AS $$ BEGIN RAISE EXCEPTION 'leg close broke'; END $$""")
    car, _ = _car(db, "AV-8", state="staged_awaiting_service")
    _visit(db, car, [{"svc": "sensor_clean", "status": "pending"}])
    leg = _leg(db, _itin(db, car), car, 1, "sensor_clean", "sensor_clean")
    reply = _report(db, car, ["sensor_clean"])
    assert reply["ok"] is True and reply["atoms_matched"] == 1 and "records" not in reply
    assert _leg_row(db, leg).startswith("planned|") and _calls(db, "probe") == ""
    assert _calls(db, "wear").startswith("sensor_clean@")


def test_with_no_live_run_nothing_is_closed(db):
    _dial(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    car, _ = _car(db, "AV-9", state="staged_awaiting_service")
    _visit(db, car, [{"svc": "sensor_clean", "status": "pending"}], run=None)
    leg = _leg(db, _itin(db, car), car, 1, "sensor_clean", "sensor_clean")
    reply = _report(db, car, ["sensor_clean"])
    assert reply["atoms_matched"] == 1 and "records" not in reply
    assert _leg_row(db, leg).startswith("planned|")


def test_only_service_role_calls_the_helper(db):
    fn = "public.ottoq_close_reported_work_legs(uuid, uuid, text[], timestamptz)"
    for role, allowed in (("anon", "f"), ("authenticated", "f"), ("service_role", "t")):
        assert db.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == allowed, role
