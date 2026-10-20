"""db/migrations/0757, EXECUTED: a bay seat that finished early is done.

WHY THIS EXISTS. The bay release (ottoq.ottoq_release_vacated_spaces, its calendar step (c)) judged an active bay booking by
its booked minutes alone: a car that left its bay before 80% of its booked window, and at least 2 minutes early, was filed
interrupted and the booking purpose's atoms were reopened, done ones included. But the only exit that credits bay work is
the service flow's STEP 1, which lets a car out when its timer has run out or a completion was reported, so an early STEP 1
exit is work that took less time than its booking, and the release undid it (G474, db/checks/0451 §20). 0757 puts a dial
on it. Executed here, on the scratch PostgreSQL, against the live release and everything it calls
(tests/fixtures/bay_release_stub.sql, md5 asserted as read on 2026-10-18), with 0757 run whole, its P0-P2, V1-V3 included:
  - before 0757, and after it at the dial's default, 2d2c46af's seat (48 minutes booked, 35.5 held, the PM credited) is
    filed interrupted, its PM reopened, and the interruption emitted, exactly as on arm 82;
  - with the dial the same seat is done, its why says the minutes it held against the minutes booked, its PM stays done
    and nothing is reopened or emitted; a robotic wash done in 5 of its 9 booked minutes, the same;
  - with the dial, a seat with no completion (a bay fault), on a null timer, completed before the booking began, completed
    in another run, or recorded before the booking was made, is judged by its booked minutes and reopened as before;
  - arm 88's detail booking, left from a wash bay with its wash credited: at the default its wash is reopened, as on arm
    88; with the dial the booking stays interrupted, its interior work stays due, and its wash stays done;
  - a seat that ran its full window is done with no note, and a no-show is released, with or without the dial;
  - 0757 applies, leaves the body it was written to leave (the body less its changes is its pre-image), stores the
    pre-image, catalogues the dial and sets it on the six cells, and refuses a second apply, a release it did not read, a
    service flow that does not emit the event as read, another function naming the event, a sweep with an arm run, and a
    database without 0746 and 0747.
A module template carries the base stub and the two fixtures, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import hashlib
import json
import os
import re
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server, the Db helper and the base stub)

ROOT = base.ROOT
ACT_FIXTURE = os.path.join(ROOT, "tests", "fixtures", "bay_activation_stub.sql")
FIXTURE = os.path.join(ROOT, "tests", "fixtures", "bay_release_stub.sql")
M0757 = os.path.join(ROOT, "db", "migrations", "0757_a_bay_seat_that_finished_early_is_done.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000757"
OTHER_RUN = "a0000000-0000-0000-0000-00000000757b"
REL = "ottoq.ottoq_release_vacated_spaces(uuid,uuid,timestamp with time zone)"
FLOW = "twin.ottoq_sim_advance_service_flow(uuid,timestamp with time zone,numeric,uuid)"
# the live bodies the fixture carries (md5 of prosrc, read from the live catalog on 2026-10-18)
LIVE = {
    REL: "ec00f54181136bc0b6d4d34a1129f096",
    "public.ottoq_reopen_visit_atoms(uuid,text[],timestamp with time zone,text,timestamp with time zone)":
        "36b5c7b598119a4cb6f58abc97eac6cf",
    "ottoq.ottoq_emit_booking_interrupted(uuid,uuid,uuid,uuid,uuid,text,timestamp with time zone,text,numeric,numeric,"
    "integer,integer,text)": "445b00938b6cd778fd3c4aefd0b85e35",
    "ottoq.ottoq_booking_interrupted(text,numeric,numeric)": "aa7c9cce9ed7cb398ccabbdabf2ebad2",
    "ottoq.ottoq_is_bay_purpose(text)": "a51158600424acd4e15550ad45f67a36",
    "ottoq.ottoq_occupancy_cut_short(numeric,numeric)": "bebe8c24b7568dd5fd43408135fa4ced",
    "ottoq.ottoq_bay_purpose_atoms(text)": "84bc5c3630789622deecabd563636051",
    "ottoq.ottoq_bay_purpose_leg_types(text)": "a85ac638b77ae7830ca672a7f5dc4636",
    "public.ottoq_throughput_sweep_cells_control()": "acaab7a09cafadff05abe5858b275226",
    "ottoq.ottoq_activate_due_bay_reservations(uuid,uuid,timestamp with time zone)": "4fb04e0a5f2d5d16b24fda2f9990f2d1",
}
LIVE_DEF = "362e66f84bf215ca68e5113a77fb367b"   # the release's pg_get_functiondef
AFTER_0757 = "0f666b832925fd0cd53c5fab1c827883"
# what STEP 1 says a bay can do, by the state the car leaves
CAPS = {"in_wash_bay": ["exterior_wash", "sensor_clean"],
        "in_detail_bay": ["interior_deep_clean", "exterior_wash", "interior_tidy"],
        "in_service_bay": ["mechanical_pm", "sensor_calibration", "fault_repair", "cosmetic_repair"]}
SWEEPS = ("robowash_normal_2026_10_18", "uptimefirst_busy_2026_10_18")

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0757-{name}"))


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_brt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, ACT_FIXTURE, FIXTURE):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_br_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0757)
    assert rc == 0, f"0757 did not apply: {err}"


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _text(d, expr):
    """A many-line text whole (Db.val keeps the last line of the output only)."""
    import base64
    b64 = d.val(f"SELECT replace(encode(convert_to(({expr}), 'UTF8'), 'base64'), E'\\n', '')")
    return base64.b64decode(b64).decode()


def _world(d, clock):
    """The twin depot's bays and staging, and a running run whose clock is the release's."""
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_start, sim_clock_current)
              VALUES ('{RUN}', '{DEPOT}', 'running', now() - interval '1 hour', '2026-09-01 11:00+00', '{clock}')""")
    for i, (code, kind) in enumerate([("SVC-1", "service_bay"), ("SVC-2", "service_bay"), ("WSH-1", "wash_bay"),
                                       ("WSH-2", "wash_bay"), ("STG-1", "staging"), ("STG-2", "staging")]):
        d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_code, stall_type, display_name, status, distance_from_entrance)
                  VALUES ('{_id(code)}', '{DEPOT}', '{code}', '{kind}', '{code}', 'available', {i})""")


def _left_bay(d, name, bay, clock):
    """A car STEP 1 has just let out of its bay: staged, still pointing at the bay, which still points at it."""
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, current_stall_id,
                                           last_state_change, config)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', 'staged_awaiting_service', '{_id(bay)}', '{clock}',
                      '{{"svc_step": "need_deploy", "service_ends_at": null}}')""")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{vid}', status = 'occupied' WHERE id = '{_id(bay)}'")
    return vid


def _visit(d, car, atoms):
    """The car's visit as STEP 1 leaves it: the atoms it credited done at the exit."""
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, status, atoms, meta)
              VALUES ('{car}', '{RUN}', '{DEPOT}', '2026-09-01 11:00+00', 'v-{car[:8]}', 'in_progress',
                      '{json.dumps(atoms)}'::jsonb, '{{}}')""")


def _booking(d, car, bay, purpose, lo, hi, state="active", booked="now() - interval '1 hour'"):
    return d.val(f"""INSERT INTO public.ottoq_stall_bookings (sim_run_id, stall_id, vehicle_id, purpose, during, state,
                                                              booked_at, booked_by, booked_at_sim)
                     VALUES ('{RUN}', '{_id(bay)}', '{car}', '{purpose}', tstzrange('{lo}', '{hi}', '[)'), '{state}',
                             {booked}, 'otto_q', '{lo}')
                     RETURNING booking_id""")


def _completion(d, car, at, bay_state, credited, self_healed=False, run=RUN, occurred="now()"):
    """The event STEP 1 writes as it lets the car out (its payload's keys as live)."""
    caps = CAPS[bay_state]
    payload = {"from": bay_state, "self_healed": self_healed, "bay_capable": caps, "credited": credited,
               "suppressed_n": len(caps) - len(credited), "flag_cleared": None, "fault_repaired": None}
    d.val(f"""INSERT INTO public.ottoq_events (occurred_at, event_type, entity_type, entity_id, depot_id, payload, data_source,
                                               sim_run_id, sim_clock_at)
              VALUES ({occurred}, 'twin.service_completed', 'vehicle', '{car}', '{DEPOT}', '{json.dumps(payload)}'::jsonb,
                      'twin', '{run}', '{at}')""")


def _dial(d, value=1):
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              VALUES ('run', '{RUN}', 'bay_release_reads_the_work', {value}, 'test', now())""")


def _release(d, clock):
    """The release, which swallows its own errors as warnings: a test that passes on a warning has measured nothing."""
    rc, out, err = d.run(f"SELECT ottoq.ottoq_release_vacated_spaces('{RUN}', '{DEPOT}', '{clock}')")
    assert rc == 0 and "WARNING" not in err, err
    return int(out[-1])


def _booking_row(d, bid):
    return d.json(f"""SELECT jsonb_build_object('state', state, 'reason', release_reason, 'why', why,
                                                'lo', to_char(lower(during) AT TIME ZONE 'UTC', 'HH24:MI:SS'),
                                                'hi', to_char(upper(during) AT TIME ZONE 'UTC', 'HH24:MI:SS'))
                        FROM public.ottoq_stall_bookings WHERE booking_id = '{bid}'""")


def _atoms(d, car):
    return d.json(f"""SELECT jsonb_object_agg(a ->> 'svc', jsonb_build_object('status', a ->> 'status',
                                                                         'reopen_reason', a ->> 'reopen_reason'))
                        FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a WHERE n.vehicle_id = '{car}'""")


def _events(d):
    return d.val("SELECT COALESCE(string_agg(event_type, ',' ORDER BY n), '') FROM public.test_bay_events")


# ── 2d2c46af on arm 82: 48 minutes booked from 1:59:30 PM CT sim, out at 2:35 on its timer, its PM credited ──
PM_LO, PM_HI, PM_T = "2026-09-01 18:59:30+00", "2026-09-01 19:47:30+00", "2026-09-01 19:35:00+00"


def _pm_seat(d):
    _world(d, PM_T)
    car = _left_bay(d, "car-PM", "SVC-1", PM_T)
    _visit(d, car, [{"svc": "mechanical_pm", "status": "done", "done_at": PM_T, "must_do": True},
                    {"svc": "exterior_wash", "status": "pending", "must_do": True}])
    bid = _booking(d, car, "SVC-1", "service", PM_LO, PM_HI)
    _completion(d, car, PM_T, "in_service_bay", ["mechanical_pm"])
    return car, bid


def _filed_interrupted_and_reopened(d, car, bid, lo, hi, svc):
    got = _booking_row(d, bid)
    assert got["state"] == "interrupted" and got["reason"] == "bay_exit_before_planned_end", got
    assert got["why"] is None, got
    assert got["hi"] == hi[11:19] and got["lo"] == lo[11:19], got        # clipped to the exit
    atoms = _atoms(d, car)
    assert atoms[svc] == {"status": "open", "reopen_reason": "bay_session_interrupted"}, atoms
    assert _events(d) == "ottoq.visit_reopened,ottoq.booking_interrupted"


def test_the_fixture_is_the_live_bodies(db):
    for fn, md5 in LIVE.items():
        assert _md5(db, fn) == md5, fn
    assert db.val(f"SELECT md5(pg_get_functiondef('{REL}'::regprocedure))") == LIVE_DEF


def test_before_0757_a_seat_the_service_flow_completed_early_is_reopened(db):
    car, bid = _pm_seat(db)
    _release(db, PM_T)
    _filed_interrupted_and_reopened(db, car, bid, PM_LO, PM_T, "mechanical_pm")
    payload = db.json("SELECT payload FROM public.test_bay_events WHERE event_type = 'ottoq.booking_interrupted'")
    assert (payload["planned_min"], payload["actual_min"], payload["atoms_reopened"]) == (48.0, 35.5, 1), payload


def test_after_0757_at_the_default_the_release_decides_as_before(db):
    _apply(db)
    car, bid = _pm_seat(db)
    _release(db, PM_T)
    _filed_interrupted_and_reopened(db, car, bid, PM_LO, PM_T, "mechanical_pm")


def test_with_the_dial_a_seat_the_service_flow_completed_is_done_however_early(db):
    _apply(db)
    car, bid = _pm_seat(db)
    _dial(db)
    _release(db, PM_T)
    got = _booking_row(db, bid)
    assert got == {"state": "done", "reason": "bay_exit_transition", "lo": "18:59:30", "hi": "19:35:00",
                   "why": "0757: the service flow completed the work; held 35.5 of 48.0 booked minutes"}, got
    assert _atoms(db, car)["mechanical_pm"] == {"status": "done", "reopen_reason": None}
    assert _atoms(db, car)["exterior_wash"] == {"status": "pending", "reopen_reason": None}   # what it did not do stays due
    assert _events(db) == ""
    assert db.val(f"SELECT status FROM public.ottoq_visit_needs WHERE vehicle_id = '{car}'") == "in_progress"
    # the bay is free and the car points at nothing, as at the default
    assert db.val(f"SELECT current_vehicle_id IS NULL AND status = 'available' FROM public.stalls WHERE id = '{_id('SVC-1')}'") == "t"
    assert db.val(f"SELECT current_stall_id IS NULL FROM public.vehicles WHERE id = '{car}'") == "t"


def test_with_the_dial_a_robotic_wash_done_in_5_of_9_booked_minutes_is_done(db):
    """0746's robotic lane: a 9-minute wash booking, the robot done at 4.6 minutes, out at the next 5-minute tick."""
    t, lo, hi = "2026-09-01 15:05:00+00", "2026-09-01 15:00:00+00", "2026-09-01 15:09:00+00"
    _apply(db)
    _world(db, t)
    car = _left_bay(db, "car-RW", "WSH-1", t)
    _visit(db, car, [{"svc": "exterior_wash", "status": "done", "done_at": t, "must_do": True}])
    bid = _booking(db, car, "WSH-1", "wash", lo, hi)
    _completion(db, car, t, "in_wash_bay", ["exterior_wash"])
    name = f"ottoq_br_rw_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {db.name}")
    try:
        d = base.Db(name)
        _dial(d)
        _release(d, t)
        got = _booking_row(d, bid)
        assert got["state"] == "done" and got["reason"] == "bay_exit_transition", got
        assert got["why"] == "0757: the service flow completed the work; held 5.0 of 9.0 booked minutes", got
        assert _atoms(d, car)["exterior_wash"]["status"] == "done"
        assert _events(d) == ""
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
    # the same seat at the default: 56% of its booking, interrupted, and the wash done again
    _release(db, t)
    _filed_interrupted_and_reopened(db, car, bid, lo, t, "exterior_wash")


def _judged_by_its_minutes(d, setup):
    """With the dial, a service seat out at 2:35 that the case's completion does not answer: as before 0757."""
    _apply(d)
    _world(d, PM_T)
    car = _left_bay(d, "car-X", "SVC-1", PM_T)
    _visit(d, car, [{"svc": "mechanical_pm", "status": "done", "done_at": PM_T, "must_do": True}])
    bid = _booking(d, car, "SVC-1", "service", PM_LO, PM_HI)
    setup(d, car)
    _dial(d)
    _release(d, PM_T)
    _filed_interrupted_and_reopened(d, car, bid, PM_LO, PM_T, "mechanical_pm")


def test_with_the_dial_an_exit_with_no_completion_is_judged_by_its_minutes(db):
    _judged_by_its_minutes(db, lambda d, car: None)        # a bay fault or a vehicle exception: no STEP 1 event


def test_with_the_dial_an_exit_on_a_null_timer_is_judged_by_its_minutes(db):
    _judged_by_its_minutes(db, lambda d, car: _completion(d, car, PM_T, "in_service_bay", ["mechanical_pm"],
                                                          self_healed=True))


def test_with_the_dial_a_completion_before_the_booking_began_does_not_count(db):
    _judged_by_its_minutes(db, lambda d, car: _completion(d, car, "2026-09-01 18:55:00+00", "in_service_bay",
                                                          ["mechanical_pm"]))


def test_with_the_dial_a_completion_in_another_run_does_not_count(db):
    _judged_by_its_minutes(db, lambda d, car: _completion(d, car, PM_T, "in_service_bay", ["mechanical_pm"],
                                                          run=OTHER_RUN))


def test_with_the_dial_a_completion_recorded_before_the_booking_was_made_does_not_count(db):
    _judged_by_its_minutes(db, lambda d, car: _completion(d, car, PM_T, "in_service_bay", ["mechanical_pm"],
                                                          occurred="now() - interval '2 hours'"))


DT_T, DT_LO, DT_HI = "2026-09-01 12:00:00+00", "2026-09-01 11:57:36+00", "2026-09-01 12:18:36+00"


def _detail_from_a_wash_bay(d):
    """Arm 88: a detail booked from 11:57:36 for 21 minutes; the twin seated the car in a wash bay at 11:55 and let it
    out at 12:00 with an exterior wash credited. A wash bay cannot finish a detail."""
    _apply(d)
    _world(d, DT_T)
    car = _left_bay(d, "car-DT", "WSH-1", DT_T)
    _visit(d, car, [{"svc": "exterior_wash", "status": "done", "done_at": DT_T, "must_do": True},
                    {"svc": "interior_deep_clean", "status": "pending", "must_do": True}])
    bid = _booking(d, car, "WSH-1", "detail", DT_LO, DT_HI)
    _completion(d, car, DT_T, "in_wash_bay", ["exterior_wash"])
    return car, bid


def _interrupted_payload(d):
    return d.json("SELECT payload FROM public.test_bay_events WHERE event_type = 'ottoq.booking_interrupted'")


def test_at_the_default_a_detail_booking_left_from_a_wash_bay_reopens_its_wash(db):
    car, bid = _detail_from_a_wash_bay(db)
    _release(db, DT_T)
    _filed_interrupted_and_reopened(db, car, bid, DT_LO, DT_T, "exterior_wash")      # as on arm 88
    p = _interrupted_payload(db)
    assert (p["planned_min"], p["actual_min"], p["atoms_reopened"]) == (21.0, 2.4, 1), p


def test_with_the_dial_a_detail_booking_left_from_a_wash_bay_stays_interrupted_and_its_wash_stays_done(db):
    car, bid = _detail_from_a_wash_bay(db)
    _dial(db)
    _release(db, DT_T)
    got = _booking_row(db, bid)
    assert got["state"] == "interrupted" and got["reason"] == "bay_exit_before_planned_end" and got["why"] is None, got
    atoms = _atoms(db, car)
    assert atoms["exterior_wash"] == {"status": "done", "reopen_reason": None}, atoms    # the wash bay did wash it
    assert atoms["interior_deep_clean"]["status"] == "pending", atoms                     # the detail's work is still due
    assert db.val(f"""SELECT a ->> 'cut_short_reason' FROM public.ottoq_visit_needs n, jsonb_array_elements(n.atoms) a
                      WHERE n.vehicle_id = '{car}' AND a ->> 'svc' = 'interior_deep_clean'""") == "bay_session_interrupted"
    assert db.val(f"SELECT status || ' ' || (meta ->> 'reopen_reason') FROM public.ottoq_visit_needs WHERE vehicle_id = '{car}'") \
        == "open bay_session_interrupted"
    assert _events(db) == "ottoq.visit_reopened,ottoq.booking_interrupted"
    p = _interrupted_payload(db)
    assert (p["planned_min"], p["actual_min"], p["atoms_reopened"], p["outstanding_restored"]) == (21.0, 2.4, 0, 1), p


def test_a_full_seat_is_done_without_a_note_and_a_no_show_is_released(db):
    _apply(db)
    t = PM_T
    _world(db, t)
    full = _left_bay(db, "car-FULL", "SVC-1", t)
    _visit(db, full, [{"svc": "mechanical_pm", "status": "done", "done_at": t, "must_do": True}])
    b_full = _booking(db, full, "SVC-1", "service", "2026-09-01 18:47:00+00", t)
    _completion(db, full, t, "in_service_bay", ["mechanical_pm"])
    away = _id("car-AWAY")
    db.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, config)
               VALUES ('{away}', '{DEPOT}', 'autonomous', 'car-AWAY', 'deployed', '{{}}')""")
    b_away = _booking(db, away, "SVC-2", "service", "2026-09-01 19:00:00+00", "2026-09-01 19:48:00+00", state="held")
    _dial(db)
    _release(db, t)
    assert _booking_row(db, b_full) == {"state": "done", "reason": "bay_exit_transition", "why": None,
                                        "lo": "18:47:00", "hi": "19:35:00"}
    got = _booking_row(db, b_away)
    assert got["state"] == "released" and got["reason"] == "no_show_grace_elapsed" and got["why"] is None, got
    assert (got["lo"], got["hi"]) == ("19:00:00", "19:48:00")     # a no-show keeps its window
    assert _events(db) == ""


def _patch_pairs():
    """The (old, new) anchors of 0757's patch table, as the file declares them."""
    sql = open(M0757).read()
    olds = dict(re.findall(r"\$o(\d)\$(.*?)\$o\1\$", sql, flags=re.S))
    news = dict(re.findall(r"\$n(\d)\$(.*?)\$n\1\$", sql, flags=re.S))
    assert sorted(olds) == sorted(news) == ["1", "2", "3", "4", "5", "6", "7"]
    return [(olds[k], news[k]) for k in sorted(olds)]


def test_0757_applies_and_leaves_the_body_it_was_written_to_leave(db):
    _apply(db)
    assert _md5(db, REL) == AFTER_0757
    src = _text(db, f"SELECT prosrc FROM pg_proc WHERE oid = '{REL}'::regprocedure")
    for old, new in reversed(_patch_pairs()):
        assert src.count(new) == 1
        src = src.replace(new, old)
    assert hashlib.md5(src.encode()).hexdigest() == LIVE[REL]
    assert db.val("SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0757_pre'") == LIVE_DEF
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0757_a_bay_seat_that_finished_early_is_done'""") == "false/false"
    assert db.val("""SELECT default_value || '/' || min_value || '/' || max_value || '/' || agent_writable
                       FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_release_reads_the_work'""") == "0/0/1/false"
    cells = db.json("""SELECT jsonb_object_agg(s.sweep_code || ':' || c.cell_code, c.fixed_params)
                         FROM public.ottoq_throughput_sweep_cells c JOIN public.ottoq_throughput_sweeps s USING (sweep_id)""")
    assert len(cells) == 7
    for key, params in cells.items():
        if key.split(":")[0] in SWEEPS:
            assert params["bay_release_reads_the_work"] == 1, key
        else:
            assert params == {"deploy_peak_fraction": 0.90}, key            # arm 84's own cell is untouched
    assert cells["robowash_normal_2026_10_18:dcfc40.otto_q.wash_robotic.uptime_first"] == {
        "deploy_peak_fraction": 0.90, "wash_lane_physics": 2, "bay_order_uptime_first": 1, "bay_release_reads_the_work": 1}
    for fn, md5 in LIVE.items():
        if fn != REL:
            assert _md5(db, fn) == md5, f"{fn} moved"


def test_0757_refuses_a_second_apply(db):
    _apply(db)
    rc, err = db.file(M0757)
    assert rc != 0 and "0757 P1" in err, err
    assert _md5(db, REL) == AFTER_0757
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0757_pre'") == "1"


def _refused(d, why):
    rc, err = d.file(M0757)
    assert rc != 0 and "0757 P1" in err and why in err, err
    assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0757%'") == "0"
    assert d.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"
    assert d.val("SELECT count(*) FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_release_reads_the_work'") == "0"
    assert d.val("SELECT count(*) FROM public.ottoq_throughput_sweep_cells WHERE fixed_params ? 'bay_release_reads_the_work'") == "0"


def test_0757_refuses_a_release_it_did_not_read(db):
    defn = _text(db, f"SELECT pg_get_functiondef('{REL}'::regprocedure)")
    moved = defn.replace("        v_activated int := 0;\n", "        v_activated int := 0;   -- moved since it was read\n")
    assert moved != defn
    rc, out, err = db.run(moved)
    assert rc == 0, err
    _refused(db, "is not the body read")


def test_0757_refuses_a_service_flow_that_does_not_emit_as_read(db):
    defn = _text(db, f"SELECT pg_get_functiondef('{FLOW}'::regprocedure)")
    moved = defn.replace("'bay_capable', to_jsonb(v_bay_caps), ", "")
    assert moved != defn
    rc, out, err = db.run(moved)
    assert rc == 0, err
    _refused(db, "does not emit twin.service_completed as read")


def test_0757_refuses_another_function_naming_the_event(db):
    db.val("""CREATE FUNCTION public.t0757_other() RETURNS text LANGUAGE sql
              AS $f$ SELECT 'twin.service_completed'::text $f$""")
    _refused(db, "other than the service flow")


def test_0757_refuses_a_sweep_with_an_arm_run(db):
    db.val("""INSERT INTO public.ottoq_throughput_sweep_arms (sweep_id, cell_id, seed, sim_run_id)
              SELECT s.sweep_id, c.cell_id, 686364201590009433, gen_random_uuid()
                FROM public.ottoq_throughput_sweeps s JOIN public.ottoq_throughput_sweep_cells c USING (sweep_id)
               WHERE s.sweep_code = 'robowash_normal_2026_10_18' AND c.ord = 1""")
    _refused(db, "has run")


def test_0757_refuses_a_database_without_0746_and_0747(db):
    db.val("DELETE FROM public.ottoq_cert_lineage WHERE name LIKE '0747%'")
    _refused(db, "are not both applied")
