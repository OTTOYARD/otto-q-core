"""db/migrations/0736 and 0739, EXECUTED: a realistic promise at arrival, and the cars still waiting.

WHY THIS EXISTS. 0736 tells an owner, when their car arrives, when it will really be ready, as a median and a 90th
percentile: its charge on the charge line's own simulator, plus what the run's earlier cars needed after their charge.
0739 counts the cars still waiting in that second part (Kaplan-Meier), draws the promise from the world instead of the
run's minted id, and reads it from 128 draws instead of 16. 0741 records, beside each promise, what the owner app says
("Planned to be ready around ..."), and grades both on the same cars. Every claim in the two headers that a test can execute is
executed here, on the scratch PostgreSQL and the miniature depot of tests/test_agent_charge_order_sql.py taken through
0642 as tests/test_charge_order_floor_sql.py takes it, whose charge-line state, simulator, charge clock and hash draws are
the live bodies (md5 asserted below as read on 2026-10-17); tests/fixtures/ready_promise_stub.sql adds 0735's tick (the
live pre-image, md5 asserted) and the two sweeps 0736 reads:
  - 0736 applies whole, its checks run, it leaves the live bodies, and a second apply is refused;
  - a car in the line is promised its seat in the expected future, and its ready time by arithmetic over the simulator's
    sampled futures and the prior's draws; a car charging, one holding a charger, a visit with nothing to charge and one
    OTTO-Q has not planned each get their own situation;
  - the recorder writes each open visit once, the ledger refuses an update and a delete, and the grade reads promises
    against the readiness check, a car not ready leaving the count until its promise has passed;
  - 0739 applies, its checks run, and a second apply is refused; Kaplan-Meier agrees with a hand computation on random
    samples; two runs of one world give a car one promise (0736 gave it two); a run with no random_seed draws from its
    own id; cars still waiting turn the run's allowance into a lower bound where its curve does not reach (0736 ignored
    them); a promise is read from 128 draws, by arithmetic; and the recorder no longer re-estimates a car whose older open
    visit can never be promised;
  - 0741 applies on the owner app's live functions (tests/fixtures/owner_ready_by_stub.sql, md5 asserted), its checks
    run, a second apply is refused and its rollback restores both bodies; the recorder records, beside each promise, the
    time the owner app says the car will be ready, exactly as the app's own function answers it, and the promise is
    otherwise what 0739 records; a failing owner app leaves the promises written; and the grade scores the app's time
    beside the promise on the same cars, by hand.
A module template carries the miniature depot through 0642 and the stub, and each test clones it.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import hashlib
import json
import math
import os
import random
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the 0614-0618 world and helpers, shared on purpose)
import test_agent_arbiter_sql as arb  # noqa: E402
import test_charge_order_floor_sql as fl  # noqa: E402  (0619-0642, the chain to the live charge line)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "ready_promise_stub.sql")
M0736 = os.path.join(ROOT, "db", "migrations", "0736_a_realistic_promise_at_arrival_and_its_grade.sql")
M0739 = os.path.join(ROOT, "db", "migrations", "0739_a_promise_counts_the_cars_still_waiting.sql")
M0741 = os.path.join(ROOT, "db", "migrations", "0741_the_promise_is_graded_beside_what_the_owner_app_says.sql")
OWNER_STUB = os.path.join(ROOT, "tests", "fixtures", "owner_ready_by_stub.sql")
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
RUN2 = "a0000000-0000-0000-0000-000000000736"                    # a second run on the same world
_vid = base._vid

EST = "public.ottoq_ready_promise(uuid,uuid,timestamp with time zone,uuid[],integer)"
REC = "twin.ottoq_sim_record_ready_promises(uuid,timestamp with time zone)"
GRADE = "public.ottoq_ready_promise_grade(uuid)"
KM = "public.ottoq_km_quantiles(double precision[],boolean[],double precision[])"
TICK = "public.ottoq_sim_advance_tick(uuid)"

# the live bodies the chain must reproduce (md5 of prosrc, read from the live catalog on 2026-10-17)
LIVE_LINE = {
    "public.ottoq_charge_line_state(uuid,uuid,timestamp with time zone)": "c05f29bc7da1068acf1dfc1bad362ba5",
    "public.ottoq_charge_line_schedule(jsonb,jsonb,integer,text,boolean)": "0c4c8d2c5ecdcb84fd97d78dfa4c85a5",
    "public.ottoq_charge_clock(jsonb,text,jsonb,numeric,numeric,numeric,numeric,numeric,jsonb)": "d45b3008e1c48363a5f2f86bda01812a",
    "public.ottoq_charge_clock_model(uuid)": "5639032d8ff9013b59a5aaa0c2ed6aff",
    "public.ottoq_charge_clock_run_evidence(jsonb,uuid,timestamp with time zone)": "9df21d259d1cce00d8679415625977cf",
    "public.ottoq_hash_normal(text)": "f960726705c6269efe16c595ba7135d0",
    "public.ottoq_hash_uniform(text)": "3fd3597574654daa8fbb8cd039d93dda",
}
LIVE_0736 = {TICK: "b8f1ea6ddfdd75b64f3a106473e09971", EST: "6806434948562e087193c3bbed65e1f6",
             REC: "7ba930bccc14b6b2f003ce1decd17c26", GRADE: "36a7250943264056b352c4b94b7d28f1"}
AFTER_0739 = {EST: "bc718022c00bd26ae3072f463dcd6ead", REC: "9a733c10d0a553a1f34d54eafcc887e3",
              KM: "836b85ae64802e3b5651d9f6f3e8b9ed", GRADE: "36a7250943264056b352c4b94b7d28f1",
              TICK: "b8f1ea6ddfdd75b64f3a106473e09971"}
# the owner app's own functions, read from the live catalog on 2026-10-17 (md5 of prosrc), and the two bodies after 0741
OWNER_LIVE = {
    "public.ottoq_owner_car(vehicles,uuid,numeric)": "683bf45b15f8e68aa4ae64b67e5263d7",
    "public.ottoq_owner_clock(timestamp with time zone,boolean,boolean)": "18f217209ef01e60d6583855a2a92f69",
    "public.ottoq_owner_state_phrase(text)": "0d23bab3def7a5e8ce7c1bc1ee4fa387",
    "public.ottoq_owner_state_group(text)": "ce2af49062888cf4ef99c3e43c8a80f4",
}
AFTER_0741 = {REC: "a5cd09d49ae31a6adebc875b7a329cfd", GRADE: "9058f3a5e684fcc52bc9e50bb1984a99", EST: AFTER_0739[EST], KM: AFTER_0739[KM], TICK: AFTER_0739[TICK]}
PRIOR = {"after_no_bay": (10, 20), "after_bay": (45, 130), "door_chg_no_bay": (105, 330), "door_chg_bay": (150, 400),
         "door_nochg_no_bay": (40, 55), "door_nochg_bay": (75, 95)}

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _admin(sql):
    subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_rpt_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        fl._through_0642(d)
        rc, err = d.file(STUB)
        assert rc == 0, f"ready_promise_stub.sql did not load: {err}"
        yield name
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


@pytest.fixture()
def db(template):
    name = f"ottoq_rp_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    try:
        yield base.Db(name)
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d, path):
    rc, err = d.file(path)
    assert rc == 0, f"{os.path.basename(path)} did not apply: {err}"
    return err


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _promise(d, run=RUN, clock=T, cars=None, futures=16):
    arr = "NULL" if cars is None else "ARRAY[" + ", ".join(f"'{c}'::uuid" for c in cars) + "]"
    rows = d.json(f"""SELECT COALESCE(jsonb_agg(to_jsonb(rp) ORDER BY rp.vehicle_id), '[]')
                        FROM public.ottoq_ready_promise('{run}', '{DEPOT}', '{clock}', {arr}, {futures}) rp""")
    return {base.NAMES.get(r["vehicle_id"], r["vehicle_id"]): r for r in rows}


def _hash_normal(key):
    """ottoq_hash_normal, in Python: Box-Muller over the first two 32-bit words of md5(key)."""
    h = hashlib.md5(key.encode()).hexdigest()
    u1 = (int(h[:8], 16) + 1) / 4294967297.0
    u2 = int(h[8:16], 16) / 4294967296.0
    return math.sqrt(-2.0 * math.log(u1)) * math.cos(2.0 * math.pi * u2)


def _pct(xs, q):
    """percentile_cont: linear interpolation between the order statistics."""
    xs = sorted(xs)
    pos = q * (len(xs) - 1)
    lo = math.floor(pos)
    hi = min(lo + 1, len(xs) - 1)
    return xs[lo] + (xs[hi] - xs[lo]) * (pos - lo)


def _seats(d, seed, car, n=16, run=RUN, clock=T):
    """The car's ready minutes r in the expected future (0) and sampled futures 1..n, from the simulator itself."""
    rows = d.json(f"""SELECT jsonb_agg((x ->> 'r')::float8 ORDER BY s)
                        FROM generate_series(0, {n}) s
                        CROSS JOIN LATERAL jsonb_array_elements(public.ottoq_charge_line_schedule(
                              public.ottoq_charge_line_state('{run}', '{DEPOT}', '{clock}'), NULL, s, '{seed}', true)
                              -> 'seats') x
                       WHERE x ->> 'id' = '{car}'""")
    return rows


def _prior_draw(key, z):
    p50, p90 = PRIOR[key]
    return p50 * math.exp(math.log(p90 / p50) / 1.2816 * z)


def _epoch(d, clock=T):
    return d.val(f"SELECT floor(extract(epoch FROM '{clock}'::timestamptz))::bigint")


def _second_run(d, seed):
    """RUN2: the same world as RUN (same depot, clock, cars and visits), its own id; both carry `seed`."""
    d.val(f"UPDATE public.ottoq_sim_runs SET random_seed = {seed} WHERE sim_run_id = '{RUN}'")
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, sim_clock_current, started_at,
                                                 run_by, policy, random_seed)
              SELECT '{RUN2}', depot_id, status, tick_count, sim_clock_current, started_at, run_by, policy, random_seed
                FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'""")
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, status, urgency,
                                                    dispatch_due_at, target_soc, atoms, created_at)
              SELECT vehicle_id, '{RUN2}', depot_id, arrived_at, visit_key, status, urgency, dispatch_due_at, target_soc,
                     atoms, created_at
                FROM public.ottoq_visit_needs WHERE sim_run_id = '{RUN}'""")
    d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by, updated_at)
              SELECT scope_type, '{RUN2}', param_key, param_value, updated_by, updated_at
                FROM public.ottoq_policy_params WHERE scope_type = 'run' AND scope_id = '{RUN}'""")


# ── 0736: it applies whole on the live bodies ─────────────────────────────────────────────────────────────────────────

def test_0736_applies_whole_on_the_live_bodies_and_refuses_a_second_apply(db):
    for fn, want in LIVE_LINE.items():
        assert _md5(db, fn) == want, fn                       # the chain is the live charge line
    assert _md5(db, TICK) == "34173eb6eea02369ad32360c47c38fa2"   # 0735's tick, as 0736's P1 requires
    _apply(db, M0736)
    for fn, want in LIVE_0736.items():
        assert _md5(db, fn) == want, fn                       # 0736 leaves exactly the live bodies
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0736_a_realistic_promise_at_arrival_and_its_grade'") == "falsefalse"
    rc, err = db.file(M0736)
    assert rc != 0 and "0736 P1" in err, err


# ── 0736: what each car is promised ───────────────────────────────────────────────────────────────────────────────────

def test_0736_a_car_in_the_line_is_its_seat_plus_what_follows_by_arithmetic(db):
    _apply(db, M0736)
    p = _promise(db)
    seed = f"{RUN}:promise:{_epoch(db)}"
    for name in ("A", "B", "C", "D", "I", "P"):
        r = p[name]
        assert r["situation"] == "in_line" and r["bundle"] == "bay", r
        assert r["detail"]["after"] == "after_bay" and r["detail"]["after_src"] == "prior", r
        assert r["detail"]["seed"] == seed and r["detail"]["futures"] == 16, r
        seats = _seats(db, seed, _vid(name))
        assert len(seats) == 17, seats
        assert float(r["plan_charge_min"]) == pytest.approx(seats[0], abs=0.006)     # the expected future's seat
        sums = [seats[s] + max(_prior_draw("after_bay", _hash_normal(f"{seed}:{s}:{_vid(name)}:after")), 0)
                for s in range(1, 17)]
        assert float(r["ready_p50_min"]) == pytest.approx(_pct(sums, 0.5), abs=0.011), (name, r)
        assert float(r["ready_p90_min"]) == pytest.approx(max(_pct(sums, 0.9), _pct(sums, 0.5)), abs=0.011), (name, r)
        assert float(r["ready_p90_min"]) >= float(r["ready_p50_min"]) >= 0
    assert float(p["I"]["due_min"]) == 40.0                    # the owner's ask, beside the promise


def test_0736_charging_holding_no_charge_and_unplanned_each_get_their_own_situation(db):
    _apply(db, M0736)
    f1 = db.val("SELECT id FROM public.stalls WHERE stall_code = 'F1'")
    l1 = db.val("SELECT id FROM public.stalls WHERE stall_code = 'L1'")
    # D plugs into F1: charging, timed by what the state says F1 has left
    db.val(f"UPDATE public.vehicles SET current_state = 'charging_dcfc', current_stall_id = '{f1}' WHERE id = '{_vid('D')}'")
    db.val(f"UPDATE public.stalls SET current_vehicle_id = '{_vid('D')}' WHERE id = '{f1}'")
    db.val(f"""INSERT INTO public.ocpp_sessions (depot_id, stall_id, vehicle_id, charge_point_id, transaction_id, evse_id,
                                                 connector_id, status, started_at, soc_start, sim_run_id)
               VALUES ('{DEPOT}', '{f1}', '{_vid('D')}', 'F1', 'tx-d', 1, 1, 'active', '{T}'::timestamptz - interval '5 minutes',
                       80, '{RUN}')""")
    # B holds L1, reserved for it: timed on L1's kind on the charge clock
    db.val(f"""UPDATE public.stalls SET reserved_by = '{_vid('B')}', reservation_expires_at = '{T}'::timestamptz + interval '20 minutes'
               WHERE id = '{l1}'""")
    # C has nothing left to charge; A's charge is pending but A is in a wash bay, so the line does not hold it
    db.val(f"""UPDATE public.ottoq_visit_needs SET atoms = '[{{"svc":"charge","status":"done"}},
                                                           {{"svc":"exterior_wash","concurrency":"bay"}}]'
               WHERE vehicle_id = '{_vid('C')}'""")
    db.val(f"UPDATE public.vehicles SET current_state = 'in_wash_bay' WHERE id = '{_vid('A')}'")
    p = _promise(db)
    state = db.json(f"SELECT public.ottoq_charge_line_state('{RUN}', '{DEPOT}', '{T}')")
    f1_free = [c for c in state["chargers"] if c["id"] == f1][0]["free"]
    assert p["D"]["situation"] == "charging" and float(p["D"]["plan_charge_min"]) == pytest.approx(float(f1_free), abs=0.006)
    assert p["D"]["detail"]["stall"] == f1
    assert p["B"]["situation"] == "holds_charger" and p["B"]["detail"]["stall"] == l1, p["B"]
    assert float(p["B"]["plan_charge_min"]) > 0
    assert p["C"]["situation"] == "no_charge" and p["C"]["detail"]["after"] == "door_nochg_bay", p["C"]
    assert p["C"]["plan_charge_min"] is None
    assert p["A"]["situation"] == "unplanned" and p["A"]["detail"]["after"] == "door_chg_bay", p["A"]
    for r in p.values():
        assert float(r["ready_p90_min"]) >= float(r["ready_p50_min"]) >= 0, r


def test_0736_the_same_run_and_clock_give_the_same_promise(db):
    _apply(db, M0736)
    assert _promise(db) == _promise(db)


# ── 0736: the recorder, the ledger and the grade ──────────────────────────────────────────────────────────────────────

def test_0736_the_recorder_writes_each_open_visit_once_and_the_ledger_is_append_only(db):
    _apply(db, M0736)
    n_open = int(db.val(f"SELECT count(*) FROM public.ottoq_visit_needs WHERE sim_run_id = '{RUN}' AND status = 'open'"))
    assert db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}')") == str(n_open)
    assert db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}')") == "0"      # once per visit
    assert db.val(f"SELECT count(*) FROM public.ottoq_ready_promises WHERE sim_run_id = '{RUN}'") == str(n_open)
    row = db.json(f"""SELECT to_jsonb(p) FROM public.ottoq_ready_promises p
                       WHERE p.vehicle_id = '{_vid('I')}' AND p.sim_run_id = '{RUN}'""")
    assert row["promised_at"].startswith("2026-10-07T14:40:00") and row["futures"] == 16
    assert row["situation"] == "in_line" and row["due_at"] is not None
    rc, _, err = db.run(f"UPDATE public.ottoq_ready_promises SET ready_p50_min = 0 WHERE sim_run_id = '{RUN}'")
    assert rc != 0 and "append-only" in err, err
    rc, _, err = db.run(f"DELETE FROM public.ottoq_ready_promises WHERE sim_run_id = '{RUN}'")
    assert rc != 0 and "append-only" in err, err
    # a run that does not exist, or no clock: nothing
    assert db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{uuid.uuid4()}', '{T}')") == "0"
    assert db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', NULL)") == "0"


def test_0736_the_grade_reads_each_promise_against_the_check(db):
    _apply(db, M0736)
    db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}')")
    pr = {base.NAMES[r["vehicle_id"]]: r for r in db.json(
        f"SELECT jsonb_agg(to_jsonb(p)) FROM public.ottoq_ready_promises p WHERE p.sim_run_id = '{RUN}'")}
    # A is ready one minute before its p50, B between its p50 and p90, C after its p90; the rest are not ready, and the
    # run ends before any of their promises has passed, so they leave the count
    def ready(name, minutes):
        db.val(f"""UPDATE public.ottoq_visit_needs
                      SET atoms = atoms || jsonb_build_array(jsonb_build_object('svc', 'readiness_check', 'status', 'done',
                                 'done_at', '{T}'::timestamptz + make_interval(secs => {minutes} * 60)))
                    WHERE sim_run_id = '{RUN}' AND vehicle_id = '{_vid(name)}'""")
    a50, b50, b90, c90 = (float(pr["A"]["ready_p50_min"]), float(pr["B"]["ready_p50_min"]),
                          float(pr["B"]["ready_p90_min"]), float(pr["C"]["ready_p90_min"]))
    ready("A", a50 - 1)
    ready("B", (b50 + b90) / 2)
    ready("C", c90 + 5)
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '1 minute' WHERE sim_run_id = '{RUN}'")
    g = db.json(f"SELECT public.ottoq_ready_promise_grade('{RUN}')")
    assert g["promises"] == len(pr) and g["ready"] == 3 and g["censored"] == len(pr) - 3, g
    assert g["graded_p50"] == 3 and g["by_p50"] == pytest.approx(1 / 3, abs=0.001), g
    assert g["graded_p90"] == 3 and g["by_p90"] == pytest.approx(2 / 3, abs=0.001), g
    # once the run has passed every promise, a car never ready is a miss
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '2 days' WHERE sim_run_id = '{RUN}'")
    g = db.json(f"SELECT public.ottoq_ready_promise_grade('{RUN}')")
    assert g["graded_p50"] == len(pr) and g["by_p50"] == pytest.approx(1 / len(pr), abs=0.001), g
    assert g["by_situation"]["in_line"]["promises"] == 6 and "unplanned" in g["by_situation"], g
    # I, the immediate dispatch, is the one visit with a due: never ready, it missed its due and its promise
    assert g["with_due"] == 1 and g["by_due"] == 0 and g["by_p90_of_those_with_due"] == 0, g


# ── 0739: it applies, and Kaplan-Meier ────────────────────────────────────────────────────────────────────────────────

def test_0739_applies_after_0736_and_refuses_a_second_apply(db):
    rc, err = db.file(M0739)
    assert rc != 0 and "0739 P1" in err, err                   # not before 0736
    _apply(db, M0736)
    _apply(db, M0739)
    for fn, want in AFTER_0739.items():
        assert _md5(db, fn) == want, fn
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0739_a_promise_counts_the_cars_still_waiting'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0739_pre'") == "2"
    rc, err = db.file(M0739)
    assert rc != 0 and "0739 P1" in err, err
    # the rollback restores 0736's bodies exactly
    db.val("DO $r$ DECLARE s record; BEGIN FOR s IN SELECT definition FROM public.ottoq_schema_snapshots "
           "WHERE label = '0739_pre' LOOP EXECUTE s.definition; END LOOP; END $r$")
    assert _md5(db, EST) == LIVE_0736[EST] and _md5(db, REC) == LIVE_0736[REC]


def _km_py(xs, ended, qs):
    """Kaplan-Meier quantiles by hand: at each distinct ended duration t, S *= 1 - d/n, n = durations >= t."""
    s, curve = 1.0, []
    for t in sorted({x for x, e in zip(xs, ended) if e}):
        d = sum(1 for x, e in zip(xs, ended) if e and x == t)
        n = sum(1 for x in xs if x >= t)
        s *= 1 - d / n
        curve.append((t, 1 - s))
    return [next((t for t, f in curve if f >= q - 1e-9), None) for q in qs]


def test_0739_kaplan_meier_agrees_with_a_hand_computation(db):
    _apply(db, M0736)
    _apply(db, M0739)
    rng = random.Random(739)
    qs = [i / 20 for i in range(21)]
    for _ in range(40):
        n = rng.randint(1, 30)
        xs = [float(rng.choice(range(5, 200, 5))) for _ in range(n)]      # ties on purpose
        ended = [rng.random() < 0.6 for _ in range(n)]
        got = db.json(f"""SELECT to_jsonb(public.ottoq_km_quantiles(ARRAY{xs}::float8[],
                                          ARRAY{[str(e).lower() for e in ended]}::boolean[], ARRAY{qs}::float8[]))"""
                      .replace("'", ""))
        assert got == _km_py(xs, ended, qs), (xs, ended, got)
    # no censoring: the empirical quantiles' lower step
    assert db.json("SELECT to_jsonb(public.ottoq_km_quantiles(ARRAY[10,20,30,40]::float8[], ARRAY[true,true,true,true], "
                   "ARRAY[0.5]::float8[]))") == [20]


# ── 0739: the promise is drawn from the world ─────────────────────────────────────────────────────────────────────────

def test_0739_two_runs_of_one_world_give_a_car_one_promise_where_0736_gave_it_two(db):
    _apply(db, M0736)
    _second_run(db, 424242)
    a, b = _promise(db, RUN), _promise(db, RUN2)
    assert set(a) == set(b) and len(a) == 7
    assert any(a[n]["ready_p90_min"] != b[n]["ready_p90_min"] for n in a), "0736 drew both runs alike"   # the defect
    _apply(db, M0739)
    a, b = _promise(db, RUN), _promise(db, RUN2)
    seed = f"world:424242:promise:{_epoch(db)}"
    for n in a:
        assert a[n]["detail"]["seed"] == b[n]["detail"]["seed"] == seed
        for k in ("situation", "plan_charge_min", "charge_p50_min", "charge_p90_min", "ready_p50_min", "ready_p90_min"):
            assert a[n][k] == b[n][k], (n, k, a[n], b[n])
        assert RUN not in a[n]["detail"]["seed"]


def test_0739_a_run_with_no_random_seed_draws_from_its_own_id(db):
    _apply(db, M0736)
    _apply(db, M0739)
    assert db.val(f"SELECT random_seed IS NULL FROM public.ottoq_sim_runs WHERE sim_run_id = '{RUN}'") == "t"
    p = _promise(db)
    assert p["I"]["detail"]["seed"] == f"world:{RUN}:promise:{_epoch(db)}"


# ── 0739: the cars still waiting ──────────────────────────────────────────────────────────────────────────────────────

def _history(d, ended, waiting, after_min=20, waited_min=200):
    """`ended` earlier cars whose check passed `after_min` minutes after their charge closed, and `waiting` cars whose
    charge closed `waited_min` minutes ago and are still waiting (bay work, an open visit). Their cars are not at the
    depot's line: only the run's allowance reads them."""
    for i in range(ended):
        chg = f"'{T}'::timestamptz - interval '{300 + i} minutes'"
        d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, status, atoms, created_at)
                  VALUES ('{uuid.uuid4()}', '{RUN}', '{DEPOT}', {chg} - interval '60 minutes', 'h{i}', 'complete',
                          jsonb_build_array(
                            jsonb_build_object('svc', 'charge', 'status', 'done', 'closed_at', {chg}),
                            jsonb_build_object('svc', 'exterior_wash', 'status', 'done', 'concurrency', 'bay'),
                            jsonb_build_object('svc', 'readiness_check', 'status', 'done',
                                               'done_at', {chg} + interval '{after_min} minutes')),
                          {chg} - interval '60 minutes')""")
    for i in range(waiting):
        chg = f"'{T}'::timestamptz - interval '{waited_min} minutes'"
        d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, status, atoms, created_at)
                  VALUES ('{uuid.uuid4()}', '{RUN}', '{DEPOT}', {chg} - interval '60 minutes', 'w{i}', 'open',
                          jsonb_build_array(
                            jsonb_build_object('svc', 'charge', 'status', 'done', 'closed_at', {chg}),
                            jsonb_build_object('svc', 'exterior_wash', 'status', 'pending', 'concurrency', 'bay'),
                            jsonb_build_object('svc', 'readiness_check', 'status', 'pending')),
                          {chg} - interval '60 minutes')""")


def test_0739_cars_still_waiting_make_the_allowance_a_lower_bound_where_0736_ignored_them(db):
    _apply(db, M0736)
    _history(db, ended=10, waiting=30)
    before = _promise(db)["A"]
    # 0736 learns from the ten that finished alone: twenty minutes after the charge, every draw
    assert before["detail"]["after_src"] == "run" and before["detail"]["after_n"] == 10
    assert float(before["ready_p50_min"]) == pytest.approx(float(before["charge_p50_min"]) + 20, abs=6)
    _apply(db, M0739)
    after = _promise(db)["A"]
    d = after["detail"]
    # Kaplan-Meier over 40: ten ended at 20 (the curve reaches a quarter), thirty still waiting at 200; the grid points
    # 0.30-1.00, fifteen of them, are lower bounds: at least the longest wait so far (200) or the prior's, whichever is more
    assert d["after_src"] == "run" and d["after_n"] == 40 and d["after_events"] == 10 and d["after_waiting"] == 30
    assert d["after_lb"] == 15, d
    # the allowance's median draw is the 200-minute bound (70% of draws are 200 or more, 30% climb from 20 to it), so the
    # promise's median sits about 200 minutes past the charge, where 0736 said 20
    gap = float(after["ready_p50_min"]) - float(after["charge_p50_min"])
    assert 180 <= gap <= 210, after
    assert float(after["ready_p50_min"]) >= float(before["ready_p50_min"]) + 150
    assert float(after["ready_p90_min"]) >= float(after["ready_p50_min"])
    # with nobody waiting, the run's allowance is what the finished cars took, as in 0736
    db.val(f"DELETE FROM public.ottoq_visit_needs WHERE sim_run_id = '{RUN}' AND visit_key LIKE 'w%'")
    calm = _promise(db)["A"]
    assert calm["detail"]["after_waiting"] == 0 and calm["detail"]["after_lb"] == 0
    assert float(calm["ready_p50_min"]) == pytest.approx(float(calm["charge_p50_min"]) + 20, abs=6)


def test_0739_a_promise_is_read_from_128_draws_by_arithmetic(db):
    _apply(db, M0736)
    _apply(db, M0739)
    p = _promise(db)
    seed = f"world:{RUN}:promise:{_epoch(db)}"
    for name in ("A", "I"):
        r = p[name]
        assert r["detail"]["draws"] == 128 and r["detail"]["futures"] == 16, r
        seats = _seats(db, seed, _vid(name))
        sums = [seats[s] + max(_prior_draw("after_bay", _hash_normal(f"{seed}:{s}:{k}:{_vid(name)}:after")), 0)
                for s in range(1, 17) for k in range(1, 9)]
        assert len(sums) == 128
        assert float(r["ready_p50_min"]) == pytest.approx(_pct(sums, 0.5), abs=0.011), (name, r)
        assert float(r["ready_p90_min"]) == pytest.approx(max(_pct(sums, 0.9), _pct(sums, 0.5)), abs=0.011), (name, r)


# ── 0739: the recorder ────────────────────────────────────────────────────────────────────────────────────────────────

def _calls_over_two_records(d):
    """How many times the estimator runs over two recorder calls in one transaction (track_functions on)."""
    out = d.val(f"""BEGIN;
                    SET LOCAL track_functions = 'all';
                    SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}');
                    SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}');
                    SELECT pg_stat_get_xact_function_calls('{EST}'::regprocedure);
                    COMMIT;""")
    return int(out)


def test_0739_the_recorder_no_longer_re_estimates_a_car_whose_older_visit_can_never_be_promised(db):
    _apply(db, M0736)
    # A also has an older open visit, from before this one
    db.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, status, atoms, created_at)
               VALUES ('{_vid('A')}', '{RUN}', '{DEPOT}', '{T}'::timestamptz - interval '3 hours', 'A-old', 'open',
                       '[{{"svc":"charge","status":"pending"}}]', '{T}'::timestamptz - interval '3 hours')""")
    db.val(f"UPDATE public.ottoq_visit_needs SET arrived_at = '{T}' WHERE vehicle_id = '{_vid('A')}' AND visit_key = 'A'")
    assert _calls_over_two_records(db) == 2                    # 0736: the second call estimates A again, for nothing
    old = db.val(f"SELECT count(*) FROM public.ottoq_ready_promises WHERE visit_id IN "
                 f"(SELECT visit_id FROM public.ottoq_visit_needs WHERE visit_key = 'A-old')")
    assert old == "0"                                          # and the older visit is never promised
    _apply(db, M0739)
    db.val("SET ottoq.ready_promises_unlock = 'on'; DELETE FROM public.ottoq_ready_promises")
    assert _calls_over_two_records(db) == 1                    # 0739: the second call has nothing to ask
    promised = db.json(f"""SELECT jsonb_agg(v.visit_key ORDER BY v.visit_key) FROM public.ottoq_ready_promises p
                             JOIN public.ottoq_visit_needs v ON v.visit_id = p.visit_id WHERE p.vehicle_id = '{_vid('A')}'""")
    assert promised == ["A"]                                   # A's newest visit, as the estimator answers it


# ── 0741: the promise beside what the owner app says ──────────────────────────────────────────────────────────────────

def _through_0741(d):
    _apply(d, M0736)
    _apply(d, M0739)
    rc, err = d.file(OWNER_STUB)
    assert rc == 0, f"owner_ready_by_stub.sql did not load: {err}"
    _apply(d, M0741)


def _leg(d, name, minutes, status="planned", run=RUN):
    """An itinerary leg of car `name` in `run`, planned to end `minutes` after T."""
    d.val(f"""INSERT INTO public.ottoq_itinerary_legs (itinerary_id, sim_run_id, vehicle_id, seq, leg_type, status,
                                                       planned_start_sim, planned_end_sim)
              VALUES ('{uuid.uuid5(uuid.NAMESPACE_DNS, "0741-" + name)}', '{run}', '{_vid(name)}', 1, 'inspect', '{status}',
                      '{T}'::timestamptz + make_interval(secs => {minutes} * 60 - 300),
                      '{T}'::timestamptz + make_interval(secs => {minutes} * 60))""")


def _owner_legs(d):
    """A: planned legs ending at T+50 and T+130, a done leg ending at T+500 and a planned leg of another run ending at
    T+900, so the app says T+130. B: an active leg ending at T+75. D: a planned leg that ended 30 minutes before T, from a
    plan that never caught up. The rest: no legs, so the app names no time."""
    _leg(d, "A", 50)
    _leg(d, "A", 130)
    _leg(d, "A", 500, status="done")
    _leg(d, "A", 900, run=RUN2)
    _leg(d, "B", 75, status="active")
    _leg(d, "D", -30)


def _owner_min(d, name):
    """Minutes after T of the time the owner app said, as recorded beside the car's promise (None when it named none)."""
    v = d.val(f"""SELECT extract(epoch FROM ((p.detail ->> 'owner_ready_by_sim')::timestamptz - '{T}'::timestamptz)) / 60
                    FROM public.ottoq_ready_promises p WHERE p.sim_run_id = '{RUN}' AND p.vehicle_id = '{_vid(name)}'""")
    return None if v == "" else float(v)


def _ready_at(d, name, minutes):
    """The car's readiness check passes `minutes` after T."""
    d.val(f"""UPDATE public.ottoq_visit_needs
                 SET atoms = atoms || jsonb_build_array(jsonb_build_object('svc', 'readiness_check', 'status', 'done',
                            'done_at', '{T}'::timestamptz + make_interval(secs => {minutes} * 60)))
               WHERE sim_run_id = '{RUN}' AND vehicle_id = '{_vid(name)}'""")


def test_0741_applies_on_the_live_owner_app_and_refuses_a_second_apply(db):
    rc, err = db.file(OWNER_STUB)
    assert rc == 0, err
    for fn, want in OWNER_LIVE.items():
        assert _md5(db, fn) == want, fn                       # the owner app's own functions, as live
    rc, err = db.file(M0741)
    assert rc != 0 and "0741 P1" in err, err                   # not before 0739
    _apply(db, M0736)
    _apply(db, M0739)
    _apply(db, M0741)
    for fn, want in AFTER_0741.items():
        assert _md5(db, fn) == want, fn                       # the estimator, Kaplan-Meier and the tick untouched
    for fn, want in OWNER_LIVE.items():
        assert _md5(db, fn) == want, fn                       # and the owner app too: it is called, not changed
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0741_the_promise_is_graded_beside_what_the_owner_app_says'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0741_pre'") == "2"
    rc, err = db.file(M0741)
    assert rc != 0 and "0741 P1" in err, err
    # the rollback restores 0739's recorder and 0736's grade exactly
    db.val("DO $r$ DECLARE s record; BEGIN FOR s IN SELECT definition FROM public.ottoq_schema_snapshots "
           "WHERE label = '0741_pre' LOOP EXECUTE s.definition; END LOOP; END $r$")
    assert _md5(db, REC) == AFTER_0739[REC] and _md5(db, GRADE) == AFTER_0739[GRADE]


def test_0741_the_recorder_records_what_the_owner_app_says_beside_each_promise(db):
    _through_0741(db)
    _owner_legs(db)
    ids = db.val(f"""SELECT string_agg(quote_literal(vehicle_id::text) || '::uuid', ', ' ORDER BY vehicle_id)
                       FROM public.ottoq_visit_needs WHERE sim_run_id = '{RUN}' AND status = 'open'""")
    direct = {base.NAMES[r["vehicle_id"]]: r for r in db.json(
        f"""SELECT jsonb_agg(to_jsonb(rp)) FROM public.ottoq_ready_promise('{RUN}', '{DEPOT}', '{T}', ARRAY[{ids}], 16) rp""")}
    assert db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}')") == "7"
    rows = {base.NAMES[r["vehicle_id"]]: r for r in db.json(
        f"SELECT jsonb_agg(to_jsonb(p)) FROM public.ottoq_ready_promises p WHERE p.sim_run_id = '{RUN}'")}
    assert set(rows) == set(direct) and len(rows) == 7
    # the latest planned or active leg of the car's own run: done legs and other runs' legs are not what the app says
    assert _owner_min(db, "A") == pytest.approx(130.0)
    assert _owner_min(db, "B") == pytest.approx(75.0)
    assert _owner_min(db, "D") == pytest.approx(-30.0)         # a plan in the past is still what the app says
    for name, r in rows.items():
        assert r["detail"]["owner_read"] is True, (name, r["detail"])
        if name not in ("A", "B", "D"):
            assert "owner_ready_by_sim" in r["detail"] and r["detail"]["owner_ready_by_sim"] is None, (name, r["detail"])
        # exactly what the owner app's own function answers for the car now
        same = db.val(f"""SELECT (p.detail ->> 'owner_ready_by_sim')::timestamptz
                                   IS NOT DISTINCT FROM (public.ottoq_owner_car(v, '{RUN}', 100) ->> 'ready_by_sim')::timestamptz
                            FROM public.ottoq_ready_promises p JOIN public.vehicles v ON v.id = p.vehicle_id
                           WHERE p.sim_run_id = '{RUN}' AND p.vehicle_id = '{r["vehicle_id"]}'""")
        assert same == "t", name
        # and the promise is otherwise what 0739's recorder writes: the estimator's answer at that clock
        d = dict(r["detail"])
        d.pop("owner_read")
        d.pop("owner_ready_by_sim")
        assert d == direct[name]["detail"], name
        for k in ("situation", "bundle", "plan_charge_min", "charge_p50_min", "charge_p90_min", "ready_p50_min",
                  "ready_p90_min"):
            assert r[k] == direct[name][k], (name, k)


def test_0741_a_failing_owner_app_leaves_the_promises_written(db):
    _through_0741(db)
    db.val("DROP TABLE public.ottoq_itinerary_legs")             # the owner app's read now fails
    rc, out, err = db.run(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}')")
    assert rc == 0 and out[-1] == "7" and "0741 owner ready-by" in err, (out, err)
    unread = db.json(f"""SELECT jsonb_agg(DISTINCT jsonb_build_object('read', p.detail -> 'owner_read',
                                                                      'at', p.detail -> 'owner_ready_by_sim'))
                           FROM public.ottoq_ready_promises p WHERE p.sim_run_id = '{RUN}'""")
    assert unread == [{"read": False, "at": None}], unread
    g = db.json(f"SELECT public.ottoq_ready_promise_grade('{RUN}')")
    assert g["promises"] == 7 and g["with_owner"] == 0 and g["graded_owner"] == 0 and g["by_owner"] is None, g


def test_0741_the_grade_scores_the_owner_app_beside_the_promise_on_the_same_cars(db):
    _through_0741(db)
    _owner_legs(db)
    db.val(f"SELECT twin.ottoq_sim_record_ready_promises('{RUN}', '{T}')")
    pr = {base.NAMES[r["vehicle_id"]]: r for r in db.json(
        f"SELECT jsonb_agg(to_jsonb(p)) FROM public.ottoq_ready_promises p WHERE p.sim_run_id = '{RUN}'")}
    # A is ready at T+100, before the app's T+130; B at T+90, after the app's T+75; D is never ready and the app's time
    # had passed before it was read; the rest are never ready and the app named no time for them
    _ready_at(db, "A", 100)
    _ready_at(db, "B", 90)
    db.val(f"UPDATE public.ottoq_sim_runs SET sim_clock_current = '{T}'::timestamptz + interval '2 days' WHERE sim_run_id = '{RUN}'")
    g = db.json(f"SELECT public.ottoq_ready_promise_grade('{RUN}')")
    assert g["promises"] == 7 and g["with_owner"] == 3 and g["graded_owner"] == 3, g
    assert g["by_owner"] == pytest.approx(1 / 3, abs=0.0005), g
    assert g["owner_mae_min"] == pytest.approx(22.5, abs=0.05) and g["owner_bias_min"] == pytest.approx(-7.5, abs=0.05), g
    assert g["owner_min_median"] == pytest.approx(75.0) and g["owner_in_past"] == 1, g
    # the promise on the same three cars, by hand
    a50, b50 = float(pr["A"]["ready_p50_min"]), float(pr["B"]["ready_p50_min"])
    a90, b90 = float(pr["A"]["ready_p90_min"]), float(pr["B"]["ready_p90_min"])
    assert g["mae_p50_min_with_owner"] == pytest.approx(round((abs(100 - a50) + abs(90 - b50)) / 2, 1), abs=0.051), g
    assert g["by_p50_with_owner"] == pytest.approx(round(((100 <= a50) + (90 <= b50)) / 3, 3), abs=0.0005), g
    assert g["by_p90_with_owner"] == pytest.approx(round(((100 <= a90) + (90 <= b90)) / 3, 3), abs=0.0005), g
    # and in each part: A, B and D are all in the line, with bay work after their charge
    part = g["by_situation"]["in_line"]
    assert part["with_owner"] == 3 and part["by_owner"] == pytest.approx(1 / 3, abs=0.0005), part
    assert g["by_bundle"]["bay"]["owner_in_past"] == 1, g["by_bundle"]
    # the grade of the promise itself is what 0736's grade says
    assert g["graded_p50"] == 7 and g["ready"] == 2, g

