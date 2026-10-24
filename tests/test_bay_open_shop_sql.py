"""db/migrations/0782, EXECUTED: when every post is taken, a car whose energy is not critical takes a free bay first (G502).

WHY THIS EXISTS. 0782 widens the one exception decide section (4b) makes to "charge first": with bay_open_shop at 1,
any car that owes bay work, whose energy is not critical, may take a free bay when no charger is free right now, and
charge after. The decide tick is the live body (tests/fixtures/exit_first_decide_live.sql, md5 asserted), loaded into
the miniature depot of tests/test_charge_order_exit_first_sql.py with 0780's helper as 0780 wrote it. Executed here:
  - 0782 applies on the live decide tick and on the one 0781 leaves, its checks run, it is classified FALSE/FALSE, and
    it refuses a run running, a decide tick it was not written against, a world without 0780's helper and a second
    apply;
  - the predicate, cut from the patched decide tick itself and run over a stand-in needs card, admits at the dial's
    default exactly the cars it admitted before (no charge owed, or interrupted bay work with energy not critical and no
    charger free), and with the dial any car whose energy is not critical when no charger is free; a critical car never,
    and no car owing a charge while a charger is free;
  - the dial is read once, before the bays are counted, and a seat records bay_before_charge only with the dial;
  - the pre-image restores the decide tick.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import re
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch server and the Db helper)
import test_charge_order_exit_first_sql as xf  # noqa: E402  (the miniature depot through 0642 with the live decide)

ROOT = base.ROOT
M0780 = os.path.join(ROOT, "db", "migrations", "0780_a_car_that_owes_no_charge_is_ready_for_its_bay_whatever_its_plan_says.sql")
M0782 = os.path.join(ROOT, "db", "migrations", "0782_when_every_post_is_taken_a_car_takes_a_free_bay_first.sql")
NAME = "0782_when_every_post_is_taken_a_car_takes_a_free_bay_first"
TICK = xf.TICK
DEPOT, RUN, T = base.DEPOT, base.RUN, base.T
LIVE_TICK = "2b3d0cbf5cdb13ca24f0de788073dc46"
AFTER_0781_TICK = "24a499cae2ecdc50add27fb563dfdb57"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def _helper_sql():
    """0780's helper, exactly as 0780 creates it."""
    text = open(M0780).read()
    start = text.index("CREATE FUNCTION ottoq.ottoq_vehicle_owes_charge_now")
    end = text.index("$function$;", start) + len("$function$;")
    return "CREATE SCHEMA IF NOT EXISTS ottoq;\n" + text[start:end]


@pytest.fixture(scope="module")
def template():
    name = f"ottoq_x782_tpl_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    xf._admin(f"CREATE DATABASE {name}")
    d = base.Db(name)
    try:
        for path in (base.STUB, xf.arb.ARB_STUB):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        base._world(d)
        base._through_0618(d)
        xf.fl._through_0642(d)
        rc, err = d.file(xf.DECIDE)
        assert rc == 0, f"the live decide tick did not load: {err}"
        rc, out, err = d.run(_helper_sql())
        assert rc == 0, f"0780's helper did not load: {err}"
        d.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
        xf._admin(f"ALTER DATABASE {name} WITH IS_TEMPLATE true")
        yield name
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"ALTER DATABASE {name} WITH IS_TEMPLATE false"], capture_output=True)
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


@pytest.fixture()
def db(template):
    name = f"ottoq_x782_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    xf._admin(f"CREATE DATABASE {name} TEMPLATE {template}")
    d = base.Db(name)
    try:
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _apply(d):
    rc, err = d.file(M0782)
    assert rc == 0, f"0782 did not apply: {err}"
    return err


def _src(d):
    return d.json(f"SELECT to_json(prosrc) FROM pg_proc WHERE oid = '{TICK}'::regprocedure")


# ── it applies ────────────────────────────────────────────────────────────────────────────────────────────────────────

def test_0782_applies_on_the_live_decide_tick_and_refuses_twice(db):
    assert xf._md5(db, TICK) == LIVE_TICK
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{RUN}'")
    rc, err = db.file(M0782)
    assert rc != 0 and "0782 P0: a run is running" in err, err
    db.val(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{RUN}'")
    err = _apply(db)
    assert f"0782 V1: the decide tick less its four replacements is its pre-image ({LIVE_TICK[:8]})" in err, err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0782_pre'") == "1"
    assert db.json("""SELECT jsonb_build_array(default_value, min_value, max_value, agent_writable)
                        FROM public.ottoq_policy_param_catalog WHERE param_key = 'bay_open_shop'""") == [0, 0, 1, False]
    rc, err = db.file(M0782)
    assert rc != 0 and "0782 P1: already applied" in err, err


def test_0782_applies_after_0781_too(db):
    xf._apply(db)
    assert xf._md5(db, TICK) == AFTER_0781_TICK
    err = _apply(db)
    assert f"0782 V1: the decide tick less its four replacements is its pre-image ({AFTER_0781_TICK[:8]})" in err, err
    src = _src(db)
    assert "(v_ok -> v.id::text ->> 2)::numeric ASC NULLS LAST" in src and "OR v_open_shop)" in src


def test_0782_refuses_a_decide_tick_it_was_not_written_against_and_a_world_without_0780(db):
    db.val("DROP FUNCTION ottoq.ottoq_vehicle_owes_charge_now(uuid, timestamp with time zone)")
    rc, err = db.file(M0782)
    assert rc != 0 and "0782 P1: 0780 is not applied" in err, err
    rc, out, err = db.run(_helper_sql())
    assert rc == 0, err
    src = db.json(f"SELECT to_json(pg_get_functiondef('{TICK}'::regprocedure))")
    rc, out, err = db.run(src.replace("v_seat int; /* 0261 */", "v_seat int; /* 0261 (edited) */", 1))
    assert rc == 0, err
    rc, err = db.file(M0782)
    assert rc != 0 and "0782 P1: the decide tick is not a body this file patches" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0782_pre'") == "0"


# ── the predicate, cut from the patched decide tick and executed ──────────────────────────────────────────────────────

def _predicate(src):
    head = "FROM public.ottoq_vehicle_needs_card c\n           WHERE c.depot_id = v_depot\n"
    start = src.index(head) + len(head)
    end = src.index("\n        ), spaced AS (", start)
    return src[start:end]


def _card(d):
    """A stand-in needs card for five of the miniature depot's cars, each one case of the exception."""
    d.val("""CREATE TABLE public._card (vehicle_id uuid, depot_id uuid, must_do_now text[], soc_pct numeric,
                                       rebook_owed boolean, energy_urgency text)""")
    rows = {
        "A": ("{}", 100, False, "ok"),                    # owes no charge: a bay, always
        "B": ("{charge,mechanical_pm}", 70, False, "due"),  # owes a charge: only the open shop
        "C": ("{charge,mechanical_pm}", 70, True, "due"),   # owes a charge and interrupted bay work: 0003
        "D": ("{charge,mechanical_pm}", 30, False, "critical"),  # critical: never
        "P": ("{charge,mechanical_pm}", 30, True, "critical"),   # critical, interrupted work too: never
    }
    for car, (mdn, soc, rb, eu) in rows.items():
        d.val(f"""INSERT INTO public._card VALUES ('{base._vid(car)}', '{DEPOT}', '{mdn}', {soc}, {str(rb).lower()}, '{eu}')""")


def _admitted(d, pred, open_shop):
    p = re.sub(r"\bv_depot\b", f"'{DEPOT}'::uuid", pred)
    p = re.sub(r"\bv_clock\b", f"'{T}'::timestamptz", p)
    p = re.sub(r"\bv_open_shop\b", "true" if open_shop else "false", p)
    names = d.json(f"""SELECT COALESCE(jsonb_agg(v.display_name ORDER BY v.display_name), '[]')
                         FROM public._card c JOIN public.vehicles v ON v.id = c.vehicle_id
                        WHERE c.depot_id = '{DEPOT}'
                        {p}""")
    return set(names)


def _all_posts_taken(d):
    car = base._vid("X")
    d.val(f"UPDATE public.stalls SET current_vehicle_id = '{car}' WHERE stall_type::text IN ('dcfc', 'l2')")


def test_the_predicate_at_the_default_is_the_one_before_0782(db):
    before = _predicate(_src(db))
    _apply(db)
    after = _predicate(_src(db))
    assert "OR v_open_shop" not in before and after.count("OR v_open_shop") == 1
    _card(db)
    for taken in (False, True):
        if taken:
            _all_posts_taken(db)
        assert _admitted(db, before, False) == _admitted(db, after, False), taken
    # with every post taken: the car owing no charge, and 0003's car owing interrupted work
    assert _admitted(db, after, False) == {"A", "C"}


def test_with_the_dial_any_car_not_critical_takes_a_free_bay_when_no_post_is_free(db):
    _apply(db)
    pred = _predicate(_src(db))
    _card(db)
    # a post is free: every car that owes a charge goes to it first, dial or no dial
    assert _admitted(db, pred, False) == {"A"}
    assert _admitted(db, pred, True) == {"A"}
    # every post taken: the open shop admits B too; D and P are critical and wait for a post
    _all_posts_taken(db)
    assert _admitted(db, pred, False) == {"A", "C"}
    assert _admitted(db, pred, True) == {"A", "B", "C"}
    # a post reserved for the car itself counts as free for it: it is that car's, so it charges first
    db.val(f"""UPDATE public.stalls SET current_vehicle_id = NULL, reserved_by = '{base._vid("B")}',
                                        reservation_expires_at = '{T}'::timestamptz + interval '10 minutes'
                WHERE stall_code = 'F1'""")
    assert _admitted(db, pred, True) == {"A", "C"}


# ── the dial's read and the record ────────────────────────────────────────────────────────────────────────────────────

def test_the_dial_is_read_once_before_the_bays_are_counted_and_the_seat_says_bay_before_charge(db):
    _apply(db)
    src = _src(db)
    assert src.count("'bay_open_shop'") == 1
    read = src.index("v_open_shop := COALESCE(public.ottoq_policy_get(p_sim_run_id, 'bay_open_shop', 0), 0) >= 1;")
    assert read < src.index("INTO v_wash_phys, v_svc_phys") < src.index("OR v_open_shop)")
    assert src.index("v_open_shop boolean := false;") < src.index("BEGIN")
    tag = src.index("THEN jsonb_build_object('bay_before_charge', true) ELSE '{}'::jsonb END;   -- 0782 (G502)")
    assert src.index("'uptime_key', to_jsonb(v_need.upf_key)) END   -- 0747") < tag
    assert "CASE WHEN v_open_shop AND ottoq.ottoq_vehicle_owes_charge_now(v_need.vehicle_id, v_clock)" in src


def test_the_pre_image_restores_the_decide_tick(db):
    _apply(db)
    rc, out, err = db.run(db.json("SELECT to_json(definition) FROM public.ottoq_schema_snapshots WHERE label = '0782_pre'"))
    assert rc == 0, err
    assert xf._md5(db, TICK) == LIVE_TICK
