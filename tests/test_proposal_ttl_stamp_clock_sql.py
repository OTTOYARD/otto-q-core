"""db/migrations/0756, EXECUTED: a proposal ages on the clock it was stamped in.

WHY THIS EXISTS. A proposal's created_at is its transaction's start (the column defaults to now()), its readers keep it
while GREATEST(expires_at, created_at + 35 minutes) >= now(), and the disposer applied the same test to clock_timestamp().
In one transaction (a sweep arm, a dial pair) the reader therefore kept a proposal the disposer had already expired, and
past the transaction's 35th minute every new proposal was expired in the tick it was made, so an arm's decisions followed
the machine's speed (G473, db/checks/0451 §19). 0756 reads the TTL on now(), as 0122 wrote it. Executed here, on the
scratch PostgreSQL, against the live disposer and readers (tests/fixtures/proposal_ttl_stub.sql, md5 asserted), with
0756 run whole, its P0-P2, V1 and V2 included, and the same probe run in one transaction before it and after it:
  - before 0756 a proposal whose 35 minutes end after the transaction began is kept by the reader and expired by the
    disposer; after it the two agree, across the 35th minute, and it stays pending;
  - a proposal past its 35 minutes on both clocks still expires as ttl_elapsed, its disposed_at on the machine's clock;
  - a proposal stamped now stays pending, a stall proposal naming no stall is still refused, the finalizer still expires
    every pending proposal;
  - the body less its changes is its pre-image, and the pre-image is stored;
  - 0756 refuses a disposer it did not read, and a second apply.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import base64
import hashlib
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "proposal_ttl_stub.sql")
M0756 = os.path.join(ROOT, "db", "migrations", "0756_a_proposal_ages_on_the_clock_it_was_stamped_in.sql")
DEPOT = base.DEPOT
DISPOSER = "public.ottoq_dispose_external_proposals(uuid,bigint,timestamp with time zone,boolean)"
LIVE = {DISPOSER: "13b31d984569d7d1336a3a99aa76fef7",
        "public.ottoq_l2_external_proposal(uuid,text,text,uuid)": "97764998a612044544d7e0f40c365bf4",
        "public.ottoq_cuopt_defer_hold(uuid,uuid,bigint)": "f6146663badc26c219a575a5719ba61f"}
LIVE_DEF = "5ed4b74688e95d22736f3e4c6123e6a6"   # the disposer's pg_get_functiondef
# where each probe proposal's 35 minutes end, as a fraction of how far the machine's clock is past the transaction's start
EDGES = {"before_start": -0.5, "at_start": 0.0, "quarter": 0.25, "half": 0.5, "three_quarters": 0.75}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# One transaction, as a sweep arm is one: a run, a pause so the machine's clock moves past the transaction's start,
# proposals stamped so their 35 minutes end at EDGES of that gap, one past them on both clocks (36 minutes old), one
# stamped now and a stall proposal naming no stall; the reader's verdict on each, then the disposer, then the outcome.
PROBE = """
CREATE OR REPLACE FUNCTION public.t0756_probe() RETURNS jsonb LANGUAGE plpgsql AS $f$
DECLARE
  v_run uuid := gen_random_uuid(); v_gap interval; v_out jsonb := '{}'::jsonb; k record; v_car uuid; v_id uuid;
  v_cars jsonb := '{}'::jsonb; v_fresh boolean; r record;
BEGIN
  INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, depot_id, status, sim_clock_start,
                                     sim_clock_current, sim_clock_end)
  VALUES (v_run, gen_random_uuid(), 'normal_day', '%(depot)s', 'running', '2031-01-01 12:00+00', '2031-01-01 12:00+00',
          '2031-01-02 12:00+00');
  PERFORM pg_sleep(0.2);
  v_gap := clock_timestamp() - now();
  FOR k IN SELECT * FROM (VALUES %(edges)s) AS e(label, f) LOOP
    v_car := gen_random_uuid();
    INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                                 source, status, created_at, expires_at, tick_seq)
    VALUES (v_run, '%(depot)s', 'service_sequencing', 'vehicle', v_car, '{"verb": "admit_service"}', 't0756', 'pending',
            now() + k.f::float8 * v_gap - interval '35 minutes', now() + k.f::float8 * v_gap - interval '33 minutes', 1);
    v_cars := v_cars || jsonb_build_object(k.label, v_car);
  END LOOP;
  v_car := gen_random_uuid();
  INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                               source, status, created_at, expires_at, tick_seq)
  VALUES (v_run, '%(depot)s', 'service_sequencing', 'vehicle', v_car, '{"verb": "admit_service"}', 't0756', 'pending',
          now() - interval '36 minutes', now() - interval '34 minutes', 1);
  v_cars := v_cars || jsonb_build_object('old', v_car);
  v_car := gen_random_uuid();
  INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                               source, status, expires_at, tick_seq)
  VALUES (v_run, '%(depot)s', 'service_sequencing', 'vehicle', v_car, '{"verb": "admit_service"}', 't0756', 'pending',
          now() + interval '2 minutes', 1);
  v_cars := v_cars || jsonb_build_object('stamped_now', v_car);
  v_car := gen_random_uuid();
  INSERT INTO public.ottoq_external_proposals (sim_run_id, depot_id, action_context, entity_type, entity_id, proposal,
                                               source, status, expires_at, tick_seq)
  VALUES (v_run, '%(depot)s', 'stall_assignment', 'vehicle', v_car, '{"stall_id": "not-a-stall"}', 't0756', 'pending',
          now() + interval '2 minutes', 1);
  v_cars := v_cars || jsonb_build_object('no_stall', v_car);

  FOR k IN SELECT key AS label, value #>> '{}' AS car FROM jsonb_each(v_cars) LOOP
    v_fresh := CASE WHEN k.label = 'no_stall' THEN NULL
                    ELSE public.ottoq_l2_external_proposal(v_run, 'service_sequencing', 'vehicle', k.car::uuid) IS NOT NULL END;
    v_out := v_out || jsonb_build_object(k.label, jsonb_build_object('reader_keeps', v_fresh));
  END LOOP;

  PERFORM public.ottoq_dispose_external_proposals(v_run, 1, NULL, false);

  FOR r IN SELECT c.key AS label, p.status, p.disposition_reason, p.disposed_at > now() AS disposed_on_machine_clock
             FROM jsonb_each(v_cars) c JOIN public.ottoq_external_proposals p
               ON p.sim_run_id = v_run AND p.entity_id = (c.value #>> '{}')::uuid LOOP
    v_out := jsonb_set(v_out, ARRAY[r.label], (v_out -> r.label) || jsonb_build_object(
               'status', r.status, 'reason', r.disposition_reason, 'disposed_on_machine_clock', r.disposed_on_machine_clock));
  END LOOP;

  -- and the finalizer, on what is still pending
  PERFORM public.ottoq_dispose_external_proposals(v_run, 2, NULL, true);
  v_out := v_out || jsonb_build_object('finalized', (
    SELECT jsonb_build_object('pending', count(*) FILTER (WHERE status = 'pending'),
                              'run_finalized', count(*) FILTER (WHERE disposition_reason = 'run_finalized'))
      FROM public.ottoq_external_proposals WHERE sim_run_id = v_run));
  RETURN v_out;
END $f$;
""" % {"depot": DEPOT, "edges": ", ".join(f"('{k}', {v})" for k, v in EDGES.items())}


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = '{fn}'::regprocedure")


def _text(d, expr):
    """A many-line text whole (Db.val keeps the last line of the output only)."""
    b64 = d.val(f"SELECT replace(encode(convert_to(({expr}), 'UTF8'), 'base64'), E'\\n', '')")
    return base64.b64decode(b64).decode()


def _src(d):
    return _text(d, f"SELECT prosrc FROM pg_proc WHERE oid = '{DISPOSER}'::regprocedure")


def _world(d):
    rc, err = d.file(STUB)
    assert rc == 0, f"proposal_ttl_stub.sql did not load: {err}"
    for fn, md5 in LIVE.items():
        assert _md5(d, fn) == md5, f"{fn} is not the live body read"
    assert d.val(f"SELECT md5(pg_get_functiondef('{DISPOSER}'::regprocedure))") == LIVE_DEF
    # a completed run at the twin depot, whose scenario 0756's V2 copies for its probe run
    d.val(f"""INSERT INTO public.ottoq_sim_runs (scenario_id, scenario_code, depot_id, status, sim_clock_start,
                                                 sim_clock_current, sim_clock_end)
              VALUES ('{uuid.uuid5(uuid.NAMESPACE_DNS, "0756-scenario")}', 'normal_day', '{DEPOT}', 'completed',
                      '2026-09-01 11:00+00', '2026-09-01 23:00+00', '2026-09-01 23:00+00')""")
    d.val(PROBE)


@pytest.fixture(scope="module")
def db():
    name = f"ottoq_ttl_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        _world(d)
        d.before = d.json("SELECT public.t0756_probe()")
        rc, err = d.file(M0756)
        assert rc == 0, f"0756 did not apply: {err}"
        d.after = d.json("SELECT public.t0756_probe()")
        yield d
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def test_0756_patched_the_disposer_and_no_reader(db):
    assert _md5(db, DISPOSER) != LIVE[DISPOSER]
    src = _src(db)
    assert "0756 (G473)" in src and "v_ttl_now timestamptz := now();" in src
    assert src.count("< v_ttl_now") == 3 and "< v_wall" not in src
    assert "disposed_at = v_wall" in src, "the audit stamp still reads the machine's clock"
    for fn, md5 in LIVE.items():
        if fn != DISPOSER:
            assert _md5(db, fn) == md5, f"{fn} moved"


def test_before_0756_the_reader_keeps_what_the_disposer_expires(db):
    for label, f in EDGES.items():
        got = db.before[label]
        assert got["status"] == "expired" and got["reason"] == "ttl_elapsed", (label, got)
        # the reader read now(): a proposal whose 35 minutes end at or after the transaction's start was still fresh to it
        assert got["reader_keeps"] is (f >= 0), (label, got)


def test_after_0756_the_reader_and_the_disposer_agree_across_the_35th_minute(db):
    for label, f in EDGES.items():
        got = db.after[label]
        assert got["reader_keeps"] is (f >= 0), (label, got)
        if f >= 0:
            assert got["status"] == "pending" and got["reason"] is None, (label, got)
        else:
            assert got["status"] == "expired" and got["reason"] == "ttl_elapsed", (label, got)
        assert got["reader_keeps"] is (got["status"] == "pending"), (label, got)


def test_past_its_35_minutes_on_both_clocks_it_still_expires_on_the_machines_clock(db):
    for run in (db.before, db.after):
        got = run["old"]
        assert got["status"] == "expired" and got["reason"] == "ttl_elapsed", got
        assert got["reader_keeps"] is False
        assert got["disposed_on_machine_clock"] is True, "disposed_at no longer reads clock_timestamp()"


def test_a_proposal_stamped_now_stays_pending(db):
    for run in (db.before, db.after):
        got = run["stamped_now"]
        assert got["status"] == "pending" and got["reader_keeps"] is True, got


def test_a_stall_proposal_naming_no_stall_is_still_refused(db):
    for run in (db.before, db.after):
        got = run["no_stall"]
        assert got["status"] == "refused" and got["reason"] == "invalid_stall_id", got


def test_the_finalizer_still_expires_every_pending_proposal(db):
    assert db.before["finalized"] == {"pending": 0, "run_finalized": 1}      # only the one stamped now was left
    assert db.after["finalized"] == {"pending": 0, "run_finalized": 5}       # it and the four 0756 kept


def test_the_body_less_its_changes_is_its_pre_image_and_the_pre_image_is_stored(db):
    src = _src(db)
    head = "  v_wall  timestamptz := clock_timestamp();\n"
    i = src.index(head) + len(head)
    j = src.index("  v_ttl_now timestamptz := now();\n") + len("  v_ttl_now timestamptz := now();\n")
    assert src[i:j].startswith("  -- 0756 (G473):"), "something other than the comment and the declaration went in"
    back = (src[:i] + src[j:]).replace("< v_ttl_now", "< v_wall")
    assert hashlib.md5(back.encode()).hexdigest() == LIVE[DISPOSER]
    assert db.val("SELECT def_md5 FROM public.ottoq_schema_snapshots WHERE label = '0756_pre'") == LIVE_DEF


def test_0756_ran_its_live_check_and_left_nothing_behind(db):
    assert db.val("""SELECT forces_recert::text || '/' || forces_dial_restart::text FROM public.ottoq_cert_lineage
                     WHERE name = '0756_a_proposal_ages_on_the_clock_it_was_stamped_in'""") == "false/false"
    assert db.val("SELECT count(*) FROM public.ottoq_sim_runs WHERE run_by = '0756_v2_probe'") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_external_proposals WHERE source = '0756_probe'") == "0"


def test_0756_refuses_a_second_apply(db):
    before = _md5(db, DISPOSER)
    rc, err = db.file(M0756)
    assert rc != 0 and "0756 P1" in err, err
    assert _md5(db, DISPOSER) == before
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0756_pre'") == "1"


def test_0756_refuses_a_disposer_it_did_not_read():
    name = f"ottoq_ttl_p1_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        _world(d)
        defn = _text(d, f"SELECT pg_get_functiondef('{DISPOSER}'::regprocedure)")
        moved = defn.replace("  v_n     integer := 0;\n", "  v_n     integer := 0;  -- moved since it was read\n")
        assert moved != defn
        rc, out, err = d.run(moved)
        assert rc == 0, err
        rc, err = d.file(M0756)
        assert rc != 0 and "0756 P1" in err, err
        assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
        assert d.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"
        assert "< v_wall" in _src(d)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")
