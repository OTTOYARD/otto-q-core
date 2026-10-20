"""db/migrations/0737, EXECUTED: a held site powers the cars due first.

WHY THIS EXISTS. 0737 lets a test day whose fast chargers share one DC pool (0726) divide a bound pool by need: each
fast charge whose car has a due time gets its full demand, earliest due first, while the pool lasts, and the charges
with no due share the rest as 0726 shares it. Every charge still runs to its target (rule 9); a slower charge is
queueing, never a shorter one. Every claim in its header that a test can execute is executed here, on a scratch
PostgreSQL, with tests/fixtures/dc_pool_by_need_stub.sql carrying 0726's division, the dial reader and 0729's pool plan
(the live bodies and the live pre-image, md5 asserted):
  - it applies whole, its checks run, it leaves the live bodies, and a second apply is refused;
  - with no due among the charges it is 0726's division exactly, on random demands and pools;
  - with dues, by a hand computation: the due charges earliest first, each the lesser of its demand and what is left,
    then 0726's water-filling over the rest;
  - only a car's newest open visit in this run sets its due; another run's, a closed one and a key that names no
    session set nothing;
  - no charge ever gets more than it asks, and the total is the lesser of the pool and the demand;
  - the pool plan calls the division only under the dial, and its grants are the server's.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import random
import shutil
import subprocess
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
STUB = os.path.join(ROOT, "tests", "fixtures", "dc_pool_by_need_stub.sql")
M0737 = os.path.join(ROOT, "db", "migrations", "0737_a_held_site_powers_the_cars_due_first.sql")
RUN = "e7d5824c-2186-4e2c-a2aa-99ba7d89c3bd"                    # arm 83's run, as 0737's V2 reads it
OTHER_RUN = "a0000000-0000-0000-0000-000000000737"
DEPOT = "11111111-1111-1111-1111-111111111111"
BY_NEED = "twin.ottoq_sim_dc_pool_shares_by_need(uuid,jsonb,numeric)"
SHARES = "twin.ottoq_sim_dc_pool_shares(jsonb,numeric)"
PLAN = "twin.ottoq_sim_dc_pool_plan(uuid,timestamp with time zone,bigint)"
LIVE = {PLAN: "34830619d8873790b83a008a139dbc05", BY_NEED: "7952e2a3f94a7fbbb5af32edcf0c2d51",
        SHARES: "864684e0f91776c1dde33710089e7b51"}


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


def _admin(sql):
    subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1", "-c", sql],
                   check=True, capture_output=True)


@pytest.fixture()
def db():
    name = f"ottoq_bn_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    _admin(f"CREATE DATABASE {name}")
    d = Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"dc_pool_by_need_stub.sql did not load: {err}"
        yield d
    finally:
        _admin(f"DROP DATABASE IF EXISTS {name} WITH (FORCE)")


def _apply(d):
    rc, err = d.file(M0737)
    assert rc == 0, f"0737 did not apply: {err}"
    return err


def _md5(d, fn):
    return d.val(f"SELECT md5(prosrc) FROM pg_proc WHERE oid = to_regprocedure('{fn}')")


def _by_need(d, demand, pool, run=RUN):
    return {k: float(v) for k, v in d.json(
        f"SELECT twin.ottoq_sim_dc_pool_shares_by_need('{run}', $j${json.dumps(demand)}$j$::jsonb, {pool})").items()}


def _shares(d, demand, pool):
    return {k: float(v) for k, v in d.json(
        f"SELECT twin.ottoq_sim_dc_pool_shares($j${json.dumps(demand)}$j$::jsonb, {pool})").items()}


def _water_fill(demand, pool):
    """0726 by hand: smallest demand first, each the lesser of its demand and an equal share of what is left."""
    left, out = max(0.0, pool), {}
    items = sorted(((max(0.0, float(v)), k) for k, v in demand.items()))
    for i, (dem, k) in enumerate(items):
        fair = left / (len(items) - i)
        g = dem if dem <= fair else fair
        out[k] = g
        left -= g
    return out


def _by_need_hand(demand, pool, dues):
    """0737 by hand: the keys with a due, earliest first (then by key), each the lesser of its demand and what is left;
    0726's water-filling over the rest."""
    left, out, rest = max(0.0, pool), {}, {}
    for k in sorted(demand, key=lambda k: (dues.get(k) is None, dues.get(k) or "", k)):
        dem = max(0.0, float(demand[k]))
        if dues.get(k) is not None:
            out[k] = min(dem, left)
            left -= out[k]
        else:
            rest[k] = dem
    out.update(_water_fill(rest, left))
    return out


def _session(d, car, run=RUN):
    sid = str(uuid.uuid4())
    d.val(f"INSERT INTO public.ocpp_sessions (id, vehicle_id, sim_run_id) VALUES ('{sid}', '{car}', '{run}')")
    return sid


def _visit(d, car, due, run=RUN, status="open", arrived="2026-09-01 22:00+00", created=None):
    due_sql = "NULL" if due is None else f"'{due}'"
    d.val(f"""INSERT INTO public.ottoq_visit_needs (vehicle_id, sim_run_id, depot_id, arrived_at, visit_key, dispatch_due_at,
                                                    atoms, status, created_at)
              VALUES ('{car}', '{run}', '{DEPOT}', '{arrived}', 'v', {due_sql}, '[]', '{status}',
                      {f"'{created}'" if created else 'now()'})""")


def _close(a, b):
    assert set(a) == set(b), (a, b)
    for k in a:
        assert a[k] == pytest.approx(b[k], abs=1e-9), (k, a, b)


# ── it applies whole ──────────────────────────────────────────────────────────────────────────────────────────────────

def test_0737_applies_whole_on_the_live_bodies_and_refuses_a_second_apply(db):
    assert _md5(db, PLAN) == "6afd8ee25b35b580eb491cd94e252c3a"            # 0729's plan, as 0737's P1 requires
    assert _md5(db, SHARES) == LIVE[SHARES]
    _apply(db)
    for fn, want in LIVE.items():
        assert _md5(db, fn) == want, fn
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  "WHERE name = '0737_a_held_site_powers_the_cars_due_first'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_visit_needs WHERE source = '0737_v2'") == "0"   # V2 rolled back
    rc, err = db.file(M0737)
    assert rc != 0 and "0737 P1" in err, err


# ── the division ──────────────────────────────────────────────────────────────────────────────────────────────────────

def test_with_no_due_the_division_is_0726s_on_random_demand_and_pools(db):
    _apply(db)
    rng = random.Random(737)
    for _ in range(40):
        demand = {f"k{i}": round(rng.uniform(0, 300), 4) for i in range(rng.randint(1, 12))}
        pool = round(rng.uniform(0, sum(demand.values()) * 1.3), 1)
        got = _by_need(db, demand, pool)
        _close(got, _shares(db, demand, pool))
        _close(got, _water_fill(demand, pool))
    assert _by_need(db, {}, 400) == {}


def test_due_cars_get_their_demand_earliest_due_first_and_the_rest_water_fill(db):
    _apply(db)
    rng = random.Random(7370)
    for case in range(25):
        demand, dues = {}, {}
        for i in range(rng.randint(2, 10)):
            car = str(uuid.uuid4())
            sid = _session(db, car)
            demand[sid] = round(rng.uniform(5, 300), 4)
            if rng.random() < 0.5:
                due = f"2026-09-01 22:{rng.randint(10, 59):02d}:00+00"
                _visit(db, car, due)
                dues[sid] = due
            elif rng.random() < 0.5:
                _visit(db, car, None)                                     # an open visit with no due
        pool = round(rng.uniform(0, sum(demand.values())), 1)
        got = _by_need(db, demand, pool)
        _close(got, _by_need_hand(demand, pool, dues))
        assert sum(got.values()) <= pool + 1e-9
        assert all(got[k] <= demand[k] + 1e-9 for k in demand)
        assert sum(got.values()) == pytest.approx(min(pool, sum(demand.values())), abs=1e-6)


def test_only_this_runs_newest_open_visit_sets_a_due(db):
    _apply(db)
    a, b, c, e, f = (str(uuid.uuid4()) for _ in range(5))
    sa, sb, sc, se, sf = (_session(db, car) for car in (a, b, c, e, f))
    _visit(db, a, "2026-09-01 22:30+00")                                  # due: counts
    _visit(db, b, "2026-09-01 22:20+00", run=OTHER_RUN)                   # another run's due: nothing
    _visit(db, c, "2026-09-01 22:10+00", status="superseded")             # a closed visit's due: nothing
    _visit(db, e, "2026-09-01 22:05+00", arrived="2026-09-01 21:00+00")   # an older open visit with a due,
    _visit(db, e, None, arrived="2026-09-01 22:00+00")                    # and its newer one with none: nothing
    _visit(db, f, None, arrived="2026-09-01 21:00+00")                    # an older one with none,
    _visit(db, f, "2026-09-01 22:40+00", arrived="2026-09-01 22:00+00")   # its newer one with a due: counts
    demand = {sa: 100, sb: 100, sc: 100, se: 100, sf: 100, "not-a-session": 100, str(uuid.uuid4()): 100}
    got = _by_need(db, demand, 300)
    # a (22:30) then f (22:40) take 100 each; the other five water-fill the 100 left: 20 each
    assert got[sa] == 100 and got[sf] == 100, got
    for k in (sb, sc, se, "not-a-session"):
        assert got[k] == pytest.approx(20), (k, got)
    assert sum(got.values()) == pytest.approx(300)
    # and a car whose due is later than another's waits for it when the pool runs short
    got = _by_need(db, {sa: 250, sf: 250}, 300)
    assert got == {sa: 250, sf: 50}, got


def test_the_pool_plan_calls_the_division_only_under_the_dial_and_the_grants_are_the_servers(db):
    _apply(db)
    def count(needle):
        return int(db.val(f"""SELECT (length(prosrc) - length(replace(prosrc, $n${needle}$n$, ''))) / length($n${needle}$n$)
                                FROM pg_proc WHERE oid = '{PLAN}'::regprocedure"""))
    assert count("ottoq_policy_get(p_sim_run_id, 'dc_power_by_need', 0)") == 1
    assert count("twin.ottoq_sim_dc_pool_shares_by_need(p_sim_run_id, v_dc, v_pool)") == 1
    assert count("twin.ottoq_sim_dc_pool_shares(v_dc, v_pool)") == 1      # the dial-off branch, 0726's
    assert db.val("SELECT default_value::text || '/' || min_value || '/' || max_value || '/' || agent_writable::text "
                  "FROM public.ottoq_policy_param_catalog WHERE param_key = 'dc_power_by_need'") == "0/0/1/false"
    for role in ("anon", "authenticated"):
        assert db.val(f"SELECT has_function_privilege('{role}', '{BY_NEED}', 'EXECUTE')") == "f"
    assert db.val(f"SELECT has_function_privilege('service_role', '{BY_NEED}', 'EXECUTE')") == "t"
    # the sweep is arm 85's cell plus the dial, after 0732's seeds
    assert db.json("""SELECT c.fixed_params FROM public.ottoq_throughput_sweep_cells c
                        JOIN public.ottoq_throughput_sweeps s USING (sweep_id)
                       WHERE s.sweep_code = 'byneed_normal_2026_10_17'""") == {
        "dc_power_by_need": 1, "dc_power_managed": 1, "dc_power_sharing": 1, "deploy_peak_fraction": 0.90,
        "enforce_site_charge_cap": 0}
