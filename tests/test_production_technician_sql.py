"""db/migrations/0751, EXECUTED: in production only a person answers a technician's question.

WHY THIS EXISTS. OTTO-Q asks the crew two kinds of question, may this car take a top-off now and is this work
green-lit, and in the twin a simulated technician answers them in twin.ottoq_opportunistic_scan by a seeded draw, then
enacts an approved top-off. Both tick paths call the scan on every tick, the production one included, and the scan read
no feed mode, so at a depot a real feed drives the twin's technician would have answered for the crew and moved real
cars (G465, db/checks/0455). 0751 passes over a question nobody answered at such a depot. Every claim in 0751's header
about the scan is executed here, on the scratch PostgreSQL, against the scan patched exactly as 0751 patches it, from its
live body and the twin's live seeded draw (tests/fixtures/opportunistic_scan_stub.sql, md5 asserted):
  - at a depot the twin feeds the draw decides, and an approved top-off is enacted, as before;
  - at a depot a real feed drives a question nobody answered stays pending, nothing is enacted and the car stays put;
  - there a person's verdict is applied as before, in their name, and an approved top-off is enacted;
  - the expiry sweep still expires an unanswered question, in both modes;
  - a depot with no feed mode, or none on record, is the twin's;
  - the scan still asks OTTO-Q's planner for new questions in both modes.
The patch's body is proven on live by 0751's V1 at apply, and the whole path on live by its V2.
It SKIPS where no scratch PostgreSQL is reachable.
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
STUB = os.path.join(ROOT, "tests", "fixtures", "opportunistic_scan_stub.sql")
M0751 = os.path.join(ROOT, "db", "migrations", "0751_in_production_only_a_person_answers_a_technician_question.sql")
DEPOT = base.DEPOT
RUN = "a0000000-0000-0000-0000-000000000751"
T = "2026-09-01 15:00:00+00"
LIVE = {("twin", "ottoq_opportunistic_scan"): "fce0e0609ef96ad49de836f95620b1f1",
        ("twin", "ottoq_sim_seeded_random"): "237b754ac865e17e0876a5df7af979b2"}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _id(name):
    return str(uuid.uuid5(uuid.NAMESPACE_DNS, f"0751-{name}"))


def _patch_sql():
    """0751's patch of the scan and its V1, exactly as the migration writes them, in one transaction."""
    with open(M0751) as f:
        text = f.read()
    part = text[text.index("-- ── the scan: only a depot the twin feeds has a simulated technician ──"):
                text.index("-- ── V2: on live, rolled back by its own raise ──")]
    return "BEGIN;\n" + part + "COMMIT;\n"


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_tct_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        for (schema, fn), md5 in LIVE.items():
            got = d.val(f"""SELECT md5(p.prosrc) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
                            WHERE n.nspname = '{schema}' AND p.proname = '{fn}'""")
            assert got == md5, f"{schema}.{fn} is not the live body read (md5 {got})"
        with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as f:
            f.write(_patch_sql())
            path = f.name
        try:
            rc, err = d.file(path)
        finally:
            os.remove(path)
        assert rc == 0, f"0751's patch did not apply: {err}"
        d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, random_seed, started_at,
                                                    sim_clock_start, sim_clock_current)
                  VALUES ('{RUN}', '{DEPOT}', 'running', 42, '{T}'::timestamptz - interval '4 hours',
                          '{T}'::timestamptz - interval '4 hours', '{T}')""")
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_tc_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _feed(d, mode):
    d.val(f"UPDATE public.depots SET feed_mode = {'NULL' if mode is None else repr(mode)} WHERE id = '{DEPOT}'")


def _plan(d, **p):
    d.val("DELETE FROM public.scan_stub_plan")
    d.val(f"INSERT INTO public.scan_stub_plan (plan) VALUES ('{json.dumps(p)}'::jsonb)")


def _car(d, name, state="staged_awaiting_service"):
    vid = _id(name)
    d.val(f"""INSERT INTO public.vehicles (id, home_depot_id, category, display_name, current_state, last_state_change,
                                           current_soc, target_soc)
              VALUES ('{vid}', '{DEPOT}', 'autonomous', '{name}', '{state}', '{T}'::timestamptz - interval '1 hour',
                      84, 100)""")
    return vid


def _charger(d, code):
    sid = _id(code)
    d.val(f"""INSERT INTO public.stalls (id, depot_id, stall_type, stall_code, display_name, status)
              VALUES ('{sid}', '{DEPOT}', 'l2', '{code}', '{code}', 'available')""")
    return sid


def _ask(d, car, kind="tech_greenlight", verdict=None, expires_min=60, decide_min=-1):
    payload = {"verdict_probe": True}
    if verdict:
        payload["operator_verdict"] = {"verdict": verdict, "by": "pulse"}
    return d.val(f"""INSERT INTO public.ottoq_ops_approvals (approval_type, vehicle_id, sim_run_id, depot_id, payload,
                                                             requested_at, decide_after, expires_at)
                     VALUES ('{kind}', '{car}', '{RUN}', '{DEPOT}', '{json.dumps(payload)}'::jsonb,
                             '{T}'::timestamptz - interval '10 minutes', '{T}'::timestamptz + interval '{decide_min} minutes',
                             '{T}'::timestamptz + interval '{expires_min} minutes')
                     RETURNING approval_id""")


def _scan(d):
    return int(d.val(f"SELECT twin.ottoq_opportunistic_scan('{RUN}', '{T}')"))


def _row(d, ap):
    return d.val(f"""SELECT status || '|' || COALESCE(decided_by, '-') || '|' || COALESCE(decided_at::text, '-')
                     FROM public.ottoq_ops_approvals WHERE approval_id = '{ap}'""")


def _calls(d, fn):
    return int(d.val(f"SELECT count(*) FROM public.scan_stub_calls WHERE fn = '{fn}'"))


def test_the_patch_replays_to_the_live_body(db):
    # V1 ran inside the template's patch transaction and raised nothing, so the body less its insertions is fce0e060
    assert db.val("""SELECT position('CONTINUE WHEN NOT v_feed_sim AND v_rec.op_verdict IS NULL;' in prosrc) > 0
                            AND (length(prosrc) - length(replace(prosrc, 'v_feed_sim', ''))) / length('v_feed_sim') = 5
                       FROM pg_proc WHERE oid = 'twin.ottoq_opportunistic_scan(uuid,timestamptz)'::regprocedure""") == "t"


def test_a_twin_fed_depot_keeps_its_simulated_technician(db):
    _feed(db, "sim")
    car = _car(db, "AV-1")
    _plan(db, greenlight_approve_p=1.0)
    yes = _ask(db, car)
    _scan(db)
    assert _row(db, yes) == f"approved|twin_tech_sim|{T}"
    _plan(db, greenlight_approve_p=0.0)
    no = _ask(db, car)
    _scan(db)
    assert _row(db, no) == f"declined|twin_tech_sim|{T}"


def test_a_twin_fed_depot_enacts_the_top_off_its_technician_approved(db):
    _feed(db, "sim")
    car = _car(db, "AV-2")
    stall = _charger(db, "L2-01")
    db.val(f"INSERT INTO public.scan_stub_enact (vehicle_id, stall_id) VALUES ('{car}', '{stall}')")
    _plan(db, opportunistic_approve_p=1.0)
    ap = _ask(db, car, kind="opportunistic_charge")
    _scan(db)
    assert _row(db, ap) == f"approved|twin_tech_sim|{T}"
    assert _calls(db, "enact") == 1
    assert db.val(f"SELECT current_stall_id FROM public.vehicles WHERE id = '{car}'") == stall
    assert db.val(f"SELECT current_vehicle_id || '|' || status FROM public.stalls WHERE id = '{stall}'") == f"{car}|occupied"


def test_a_real_feed_leaves_an_unanswered_question_pending(db):
    _feed(db, "external")
    car = _car(db, "AV-3")
    stall = _charger(db, "L2-02")
    db.val(f"INSERT INTO public.scan_stub_enact (vehicle_id, stall_id) VALUES ('{car}', '{stall}')")
    _plan(db, greenlight_approve_p=1.0, opportunistic_approve_p=1.0)
    gl = _ask(db, car)
    top = _ask(db, car, kind="opportunistic_charge")
    _scan(db)
    assert _row(db, gl) == "pending|-|-"
    assert _row(db, top) == "pending|-|-"
    assert _calls(db, "enact") == 0 and _calls(db, "arm") == 0
    assert db.val(f"SELECT COALESCE(current_stall_id::text, '-') || '|' || current_state FROM public.vehicles "
                  f"WHERE id = '{car}'") == "-|staged_awaiting_service"
    assert db.val(f"SELECT COALESCE(current_vehicle_id::text, '-') || '|' || status FROM public.stalls "
                  f"WHERE id = '{stall}'") == "-|available"


def test_a_real_feed_applies_a_persons_verdict_in_their_name(db):
    _feed(db, "external")
    car = _car(db, "AV-4")
    stall = _charger(db, "L2-03")
    db.val(f"INSERT INTO public.scan_stub_enact (vehicle_id, stall_id) VALUES ('{car}', '{stall}')")
    _plan(db, greenlight_approve_p=1.0, opportunistic_approve_p=1.0)
    top = _ask(db, car, kind="opportunistic_charge", verdict="approved")
    gl = _ask(db, car, verdict="declined")
    _scan(db)
    assert _row(db, top) == f"approved|operator:pulse|{T}"
    assert _row(db, gl) == f"declined|operator:pulse|{T}"
    assert _calls(db, "enact") == 1
    assert db.val(f"SELECT current_stall_id FROM public.vehicles WHERE id = '{car}'") == stall


def test_an_unanswered_question_still_expires_in_both_modes(db):
    car = _car(db, "AV-5")
    for mode in ("external", "sim"):
        _feed(db, mode)
        ap = _ask(db, car, expires_min=0, decide_min=-5)
        _scan(db)
        assert _row(db, ap).startswith("expired|"), mode


def test_a_depot_with_no_feed_mode_is_the_twins(db):
    car = _car(db, "AV-6")
    _plan(db, greenlight_approve_p=1.0)
    _feed(db, None)
    ap = _ask(db, car)
    _scan(db)
    assert _row(db, ap) == f"approved|twin_tech_sim|{T}"
    db.val(f"DELETE FROM public.depots WHERE id = '{DEPOT}'")
    ap = _ask(db, car)
    _scan(db)
    assert _row(db, ap) == f"approved|twin_tech_sim|{T}"


def test_the_scan_still_asks_otto_qs_planner_in_both_modes(db):
    for i, mode in enumerate(("sim", "external")):
        _feed(db, mode)
        _scan(db)
        assert _calls(db, "plan") == i + 1, mode
