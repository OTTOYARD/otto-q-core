"""db/migrations/0791, the run-control routines closed to the browser roles and the pause and resume doors that no longer
write over a stopped run, EXECUTED on a stub.

WHY THIS EXISTS. FINDINGS G493: public.ottoq_pause_run(uuid, text) and ottoq_resume_run(uuid) are SECURITY DEFINER and
EXECUTE-able by `authenticated`, and sign-up is open (G428), so anyone who signs up could pause or resume any run, a
production session included; three more definer doors (start-a-scenario, run-to-end, benchmark reset) did the same, and
twelve run-control routines that run as the caller carried PUBLIC's EXECUTE. And G492: the same two doors read the run's
status without a lock and update its row by sim_run_id alone, so one that waited behind a stop writes over the stopped
run. A grant change cannot be proved by reading it, and a race cannot be proved in one session, so this suite runs the
file on a stub carrying the seventeen LIVE definitions (md5-pinned) and their LIVE ACLs, the run table with its live
grants, policies and one-running-run-per-depot index, the callees production start and stop reach, and an event
stand-in with live's foreign key to the run, and asks the database, as each role and from two real sessions:

  * before: a signed-in caller pauses a running run and resumes it, a production session too, though it cannot update
    the run table itself (the defect, reproduced); a signed-in production start or stop is refused one call deeper, at
    a callee only service_role may run, and the public key at the table (db/checks/0448, re-read);
  * after: all seventeen refuse authenticated and anon with SQLSTATE 42501 naming the routine; service_role still
    pauses, resumes, starts and stops; only pause and resume moved, by their patch alone;
  * G492, two sessions: one holds the run's row FOR NO KEY UPDATE and completes the run (or aborts and deletes it, as
    the demo start does) and keeps its transaction open until the other, a pause or resume, is seen waiting on the row.
    Before 0791 the waiting door writes over the stopped run (or fails: 23505 when the stop started another run at the
    depot, 23503 when its event names a run that is gone); after it, the door updates nothing and answers that the run
    is no longer running or paused (or not found), and records no event;
  * the file refuses a second run, a hotfixed door, a moved ACL, a missing or extra overload, a new run-control door, a
    browser-reachable SECURITY INVOKER caller (direct, dynamic or a trigger), a view on a target, a census that has
    stopped finding a target, a routine that calls pause or resume (its FALSE/FALSE would be unproven), and a
    certification in flight; a mention in a comment is not a call; 0701's three are accepted open or closed; V5 fails
    when a predicate or the answer from the row count is missing from the patch;
  * the restore statements, the header's one-paste block and the snapshot rows alike, put every ACL and both
    definitions back; the lineage row is FALSE/FALSE.

Loads tests/fixtures/run_control_grants_stub.sql. SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import re
import subprocess
import sys
import time
import uuid

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import Db, _conn_args, _drop, _server_up  # noqa: E402

STUB = os.path.join(ROOT, "tests", "fixtures", "run_control_grants_stub.sql")
NAME = ("0791_a_signed_in_user_cannot_pause_resume_start_or_stop_a_run_and_a_pause_or_resume_never_writes_over_a_"
        "stopped_run")
MIG = os.path.join(ROOT, "db", "migrations", NAME + ".sql")

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

TWIN = "11111111-1111-1111-1111-111111111111"
SCENARIO = "5c000000-0000-4000-8000-000000000791"
NOBODY = "00000000-0000-4000-8000-0000000007f1"   # a run id no test creates
PUBLIC_ACL = "{=X/postgres,postgres=X/postgres,anon=X/postgres,authenticated=X/postgres,service_role=X/postgres}"
DEFINER_A = "{postgres=X/postgres,service_role=X/postgres,authenticated=X/postgres}"
DEFINER_B = "{postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}"
AFTER_ACL = "{postgres=X/postgres,service_role=X/postgres}"
PAUSE, RESUME = "ottoq_pause_run(uuid,text)", "ottoq_resume_run(uuid)"

#: the seventeen as read on live, 2026-10-15 13:14:57 UTC and again 2026-10-17 14:04:15 UTC (pause, resume and production
#: start once more at 14:25:16 UTC): pg_get_functiondef md5, ACL text, prokind, prosecdef, and a call that names each
#: routine (for the 42501 checks; it never runs a body)
LIVE = {
    PAUSE: ("1e3ec33aca6f4f3b008a0d83bff08c51", DEFINER_A, "f", True,
            f"SELECT public.ottoq_pause_run('{NOBODY}', 't')"),
    RESUME: ("b693dc33284db3914381f89bd7f21724", DEFINER_A, "f", True,
             f"SELECT public.ottoq_resume_run('{NOBODY}')"),
    "ottoq_sim_run_scenario(text,bigint,text,timestamp with time zone)": (
        "77452e4a4d02700ddea8a450f468daee", DEFINER_B, "f", True,
        "SELECT public.ottoq_sim_run_scenario('busy_day', 1::bigint, 'operator_demo', now())"),
    "ottoq_benchmark_reset(uuid,numeric,numeric)": ("17986725fa7566b0c6670c58af5f3d8f", DEFINER_A, "f", True,
                                                    "SELECT public.ottoq_benchmark_reset('22222222-2222-2222-2222-222222222222', 30, 80)"),
    "ottoq_run_policy_to_end(uuid,integer)": ("1b40f798b8f5f8326bff260d0002cc09", DEFINER_B, "f", True,
                                              f"SELECT * FROM public.ottoq_run_policy_to_end('{NOBODY}', 1)"),
    "ottoq_production_start(uuid)": ("ea2945cbb0435c58ce73b4f5e038c501", PUBLIC_ACL, "f", False,
                                     f"SELECT public.ottoq_production_start('{TWIN}')"),
    "ottoq_production_stop(text)": ("499ea8d51f65cd62463838ba940e075e", PUBLIC_ACL, "f", False,
                                    "SELECT public.ottoq_production_stop('test')"),
    "ottoq_cert_arm_start(bigint,text,uuid,integer)": ("9045e026e2c31eadca7d3bf311b063fa", PUBLIC_ACL, "f", False,
                                                       f"SELECT public.ottoq_cert_arm_start(1::bigint, 'otto_q', '{NOBODY}', 0)"),
    "ottoq_cert_arm_finish(uuid)": ("02beeffec29daad712b8e19271c9adf4", PUBLIC_ACL, "f", False,
                                    f"SELECT public.ottoq_cert_arm_finish('{NOBODY}')"),
    "ottoq_cert_arm(bigint,text,uuid,integer,timestamp with time zone,integer)": (
        "6d524d73fc1ea2f4fccaa36d9049c92c", PUBLIC_ACL, "p", False,
        f"CALL public.ottoq_cert_arm(1::bigint, 'otto_q', '{NOBODY}', 1, now(), 0)"),
    "ottoq_cert_arm_wave(bigint,text,uuid,integer,integer)": (
        "da8f1efa7c38c74dba996f7f75ea586f", PUBLIC_ACL, "p", False,
        f"CALL public.ottoq_cert_arm_wave(1::bigint, 'otto_q', '{NOBODY}', 1, 0)"),
    "ottoq_fr1_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,boolean)": (
        "2c7b9c06574bfff33de5bfe664deba56", PUBLIC_ACL, "p", False,
        f"CALL public.ottoq_fr1_cert_arm('{NOBODY}', 1::bigint, '{NOBODY}', 1, now(), false)"),
    "ottoq_safety_cert_arm(uuid,bigint,uuid,integer,timestamp with time zone,numeric)": (
        "6bc03eeafb83787966c53728e818798a", PUBLIC_ACL, "p", False,
        f"CALL public.ottoq_safety_cert_arm('{NOBODY}', 1::bigint, '{NOBODY}', 1, now(), 0.65)"),
    "ottoq_demo_metronome(integer)": ("d02b6af9e3fa622267247f7277ef7057", PUBLIC_ACL, "p", False,
                                      "CALL public.ottoq_demo_metronome(1)"),
    "ottoq_retention_purge_runs(integer,integer,interval,boolean)": (
        "890d2de189d638c1622a53efc863fb66", PUBLIC_ACL, "p", False,
        "CALL public.ottoq_retention_purge_runs(1, 1, interval '1 hour', true)"),
    "ottoq_retention_purge_worker(integer,integer,interval,text[])": (
        "dff3b880934e2b84d07f771118a3e884", PUBLIC_ACL, "p", False,
        "CALL public.ottoq_retention_purge_worker(1, 1, interval '1 hour', ARRAY['ottoq_events'])"),
    "ottoq_retention_purge_worker(integer,integer,interval)": (
        "3eff6dd057ff5af612ca9bd9c063ed13", PUBLIC_ACL, "p", False,
        "CALL public.ottoq_retention_purge_worker(1, 1, interval '1 hour')"),
}
#: the two definitions after 0791's patches, on this stub (pg_get_functiondef md5): what the file leaves on live, since
#: the patch is a replace on the definition P1 pins (0791 §5: the replaced texts' md5s on live, read 2026-10-17
#: 14:50:30 UTC, are these two)
PATCHED = {PAUSE: "28cba3966f9831f23705fb5c2341e691", RESUME: "3950a271cc07b6374a4fb2db70680e74"}
NAMES = sorted({sig.split("(")[0] for sig in LIVE})
_IN = ", ".join(f"'{n}'" for n in NAMES)

#: one line per routine: signature=md5 / signature=ACL / signature=kind:definer, in regprocedure text order
MD5S = f"""SELECT string_agg(p.oid::regprocedure::text || '=' || md5(pg_get_functiondef(p.oid)), ' '
                           ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.proname IN ({_IN})"""
ACLS = f"""SELECT string_agg(p.oid::regprocedure::text || '=' || coalesce(p.proacl::text, 'NULL'), ' '
                           ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.proname IN ({_IN})"""
KINDS = f"""SELECT string_agg(p.oid::regprocedure::text || '=' || p.prokind::text || ':' || p.prosecdef::text, ' '
                            ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.proname IN ({_IN})"""
#: who may EXECUTE what, as the catalog answers it for each role
PRIV = f"""SELECT string_agg(p.oid::regprocedure::text || '=' || has_function_privilege('anon', p.oid, 'EXECUTE')::text
                           || ',' || has_function_privilege('authenticated', p.oid, 'EXECUTE')::text
                           || ',' || has_function_privilege('service_role', p.oid, 'EXECUTE')::text, ' '
                           ORDER BY p.oid::regprocedure::text) FROM pg_proc p WHERE p.proname IN ({_IN})"""
#: who holds EXECUTE, as a set (a restored GRANT lands after service_role, so the ACL text's order may differ)
HOLDERS = f"""SELECT string_agg(h, ' ' ORDER BY h) FROM (
              SELECT p.oid::regprocedure::text || ':' || CASE WHEN a.grantee = 0 THEN 'PUBLIC' ELSE pg_get_userbyid(a.grantee) END AS h
                FROM pg_proc p CROSS JOIN LATERAL aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a
               WHERE p.proname IN ({_IN})) x"""

#: the claims PostgREST sets for a role's request (row security reads auth.role() from them): a person who has just
#: signed up, or the platform's service key. Set as PostgREST sets them, so no test leans on the scratch cluster's
#: service_role having BYPASSRLS (it is cluster-wide, and another suite's stub may have created it without)
def _claims(role):
    sub = ', "sub": "e0000000-0000-4000-8000-000000000791"' if role == "authenticated" else ""
    return "SET LOCAL request.jwt.claims TO '{\"role\": \"" + role + "\"" + sub + "}'"


def _expected(field, patched=False):
    return " ".join(f"{sig}={PATCHED[sig] if patched and field == 0 and sig in PATCHED else LIVE[sig][field]}"
                    for sig in sorted(LIVE))


def _psql_args(db):
    return ["psql", *_conn_args(), "-d", db.name, "-q", "-At", "-v", "ON_ERROR_STOP=1", "-v", "VERBOSITY=verbose"]


def _psql(db, sql):
    p = subprocess.run([*_psql_args(db), "-c", sql], capture_output=True, text=True)
    out = [l for l in p.stdout.splitlines() if l.strip()]
    return p.returncode == 0, (out[-1] if out else ""), p.stderr


def _as(db, role, sql, claims=False):
    """One statement as a role, rolled back; (ok, last line of output, stderr with the SQLSTATE)."""
    return _psql(db, f"BEGIN; SET LOCAL ROLE {role}; {_claims(role) + ';' if claims else ''} {sql}; ROLLBACK;")


def _as_commit(db, role, sql, claims=False):
    """One statement as a role, committed."""
    return _psql(db, f"BEGIN; SET LOCAL ROLE {role}; {_claims(role) + ';' if claims else ''} {sql}; COMMIT;")


def _refused_at(err, kind, name):
    """42501 naming exactly this routine (not a callee, not a table)."""
    return "42501" in err and f"permission denied for {kind} {name}" in err


def _run(db, run_by, status="running", depot=TWIN, payload="{}"):
    """A run row, as postgres; its id."""
    return db.val(f"INSERT INTO public.ottoq_sim_runs (scenario_id, scenario_code, sim_clock_start, sim_clock_current, "
                  f"sim_clock_end, depot_id, status, run_by, tick_count, payload) VALUES ('{SCENARIO}', "
                  f"'busy_day', now(), now(), now() + interval '1 day', '{depot}', '{status}', '{run_by}', 7, "
                  f"'{payload}') RETURNING sim_run_id")


def _state(db, run):
    return db.val(f"SELECT status || '|' || (next_tick_due_at IS NULL)::text || '|' || coalesce(payload->>'pause_reason', '-') "
                  f"FROM public.ottoq_sim_runs WHERE sim_run_id = '{run}'")


def _new():
    name = f"ottoq_rc0791_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    subprocess.run(["psql", *_conn_args(), "-d", "postgres", "-q", "-c", f"CREATE DATABASE {name}"], check=True,
                   capture_output=True)
    return Db(name)


def _load(extra_sql=None):
    d = _new()
    rc, err = d.file(STUB)
    assert rc == 0, f"stub did not load: {err}"
    if extra_sql:
        d.run(extra_sql)
    return d


def _restore_block():
    text = open(MIG).read()
    m = re.search(r"/\* 0791 RESTORE BEGIN\n(.*?)\n0791 RESTORE END \*/", text, re.S)
    assert m, "the header's restore block is missing"
    return m.group(1)


@pytest.fixture(scope="module")
def db():
    d = _load()
    try:
        b = d.before = {"md5": d.val(MD5S), "acl": d.val(ACLS), "kinds": d.val(KINDS), "priv": d.val(PRIV),
                        "holders": d.val(HOLDERS)}
        # the defect: a signed-in caller pauses and resumes a demo run, and pauses and resumes a production session
        # (one at a time: live's ottoq_one_running_run_per_depot admits one running run at the depot)
        demo = d.demo = _run(d, "operator_demo")
        b["pause_demo"] = _as_commit(d, "authenticated", f"SELECT public.ottoq_pause_run('{demo}', 'a signed-in caller')")
        b["demo_paused"] = _state(d, demo)
        b["resume_demo"] = _as_commit(d, "authenticated", f"SELECT public.ottoq_resume_run('{demo}')")
        b["demo_resumed"] = _state(d, demo)
        # the same caller cannot write the run table itself: the definer door is the only signed-in path to a status
        b["direct_update"] = _as(d, "authenticated", f"UPDATE public.ottoq_sim_runs SET status = 'paused' WHERE sim_run_id = '{demo}'",
                                 claims=True)
        d.run(f"UPDATE public.ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{demo}'")
        prod = d.prod = _run(d, "production_live")
        b["pause_prod"] = _as_commit(d, "authenticated", f"SELECT public.ottoq_pause_run('{prod}', 'a signed-in caller')")
        b["prod_paused"] = _state(d, prod)
        b["events"] = d.val("SELECT string_agg(event_type, ' ' ORDER BY recorded_at) FROM public.stub_events")
        # 0448 re-read: production start and stop run as the caller. A signed-in start reads the run and scenario tables
        # (it holds SELECT under policies it passes) and is refused at ottoq_world_yield_to_start; with a production
        # session running, a signed-in stop is refused at ottoq_sim_release_depot; the public key at the table.
        b["start_auth"] = _as(d, "authenticated", f"SELECT public.ottoq_production_start('{TWIN}')", claims=True)
        b["start_anon"] = _as(d, "anon", f"SELECT public.ottoq_production_start('{TWIN}')")
        b["resume_prod"] = _as_commit(d, "authenticated", f"SELECT public.ottoq_resume_run('{prod}')")
        b["prod_resumed"] = _state(d, prod)
        b["stop_auth"] = _as(d, "authenticated", "SELECT public.ottoq_production_stop('a signed-in caller')", claims=True)
        b["stop_anon"] = _as(d, "anon", "SELECT public.ottoq_production_stop('a signed-in caller')")
        b["runs_after_probes"] = d.val("SELECT count(*) FROM public.ottoq_sim_runs")
        rc, err = d.file(MIG)
        assert rc == 0, f"0791 did not apply on the stub: {err}"
        d.notices = err
        yield d
    finally:
        _drop(d)


def test_the_stub_carries_the_live_definitions_and_acls(db):
    assert db.before["md5"] == _expected(0)
    assert db.before["acl"] == _expected(1)
    assert db.before["kinds"] == " ".join(f"{s}={LIVE[s][2]}:{str(LIVE[s][3]).lower()}" for s in sorted(LIVE))
    assert len(LIVE) == 17 and len(NAMES) == 16


def test_before_every_browser_grant_is_as_read(db):
    expected = " ".join(f"{s}={'false' if LIVE[s][3] else 'true'},true,true" for s in sorted(LIVE))
    assert db.before["priv"] == expected     # anon on the twelve only; authenticated and service_role on all seventeen


def test_before_a_signed_in_caller_pauses_and_resumes_any_run_production_included(db):
    b = db.before
    for key in ("pause_demo", "resume_demo", "pause_prod", "resume_prod"):
        ok, _out, err = b[key]
        assert ok, f"{key}: {err}"
    assert json.loads(b["pause_demo"][1])["status"] == "paused"
    assert b["demo_paused"] == "paused|true|a signed-in caller"           # the tick's next due time cleared with it
    assert json.loads(b["resume_demo"][1])["clock_reanchored"] is True
    assert b["demo_resumed"] == "running|false|-"
    assert json.loads(b["pause_prod"][1])["status"] == "paused"
    assert b["prod_paused"] == "paused|true|a signed-in caller"           # a production session, by a signed-in caller
    assert b["prod_resumed"] == "running|false|-"
    assert b["events"].split() == ["twin.sim_run_paused", "twin.sim_run_resumed", "twin.sim_run_paused"]
    # the table refuses the same caller: the definer doors were its only way to a run's status
    ok, _out, err = b["direct_update"]
    assert not ok and "42501" in err and "permission denied for table ottoq_sim_runs" in err, err


def test_before_production_start_and_stop_are_refused_one_call_deeper_0448_reread(db):
    b = db.before
    ok, _out, err = b["start_auth"]
    assert not ok and _refused_at(err, "function", "ottoq_world_yield_to_start"), err
    ok, _out, err = b["stop_auth"]
    assert not ok and _refused_at(err, "function", "ottoq_sim_release_depot"), err
    for key in ("start_anon", "stop_anon"):
        ok, _out, err = b[key]
        assert not ok and "permission denied for table ottoq_sim_runs" in err, err
    # neither refusal left a run behind: the start never reached its insert
    assert b["runs_after_probes"] == "2"


def test_the_file_reports_each_verification(db):
    for tag in ("0791 P2: before: AS authenticated|user authenticated|pause answered|resume answered",
                "0791 V1 PASSED", "0791 V2 PASSED", "0791 V3 PASSED", "0791 V4 PASSED", "0791 V5 PASSED"):
        assert tag in db.notices, db.notices
    assert f"ottoq_pause_run (1e3ec33a, now {PATCHED[PAUSE][:8]}) and ottoq_resume_run (b693dc33, now " \
           f"{PATCHED[RESUME][:8]}) changed by their patch alone" in db.notices, db.notices


#: the three-argument retention worker cannot be called by name at all: every call that fits it also fits the text[]
#: overload, whose fourth argument has a default, so PostgreSQL refuses the call as ambiguous (42725) before it checks a
#: privilege, for every role (cron job 11 calls the four-argument one). Its grant is checked in the catalog (PRIV).
UNCALLABLE = "ottoq_retention_purge_worker(integer,integer,interval)"


def test_after_all_seventeen_refuse_the_browser_roles_42501(db):
    for sig, (_md5, _acl, kind, _definer, call) in LIVE.items():
        name = sig.split("(")[0]
        what = "procedure" if kind == "p" else "function"
        for role in ("authenticated", "anon"):
            ok, _out, err = _as(db, role, call, claims=(role == "authenticated"))
            if sig == UNCALLABLE:
                assert not ok and "42725" in err and f"procedure public.{name}(integer, integer, interval) is not unique" \
                    in err, err
                continue
            assert not ok and _refused_at(err, what, name), f"{role} may still call {sig}: {err}"
    ok, _out, err = _as(db, "postgres", LIVE[UNCALLABLE][4])
    assert not ok and "42725" in err, err                                 # the owner cannot call it by name either
    assert db.val(ACLS) == " ".join(f"{s}={AFTER_ACL}" for s in sorted(LIVE))
    assert db.val(PRIV) == " ".join(f"{s}=false,false,true" for s in sorted(LIVE))


def test_after_a_signed_in_caller_cannot_pause_the_running_production_session(db):
    assert _state(db, db.prod) == "running|false|-"
    ok, _out, err = _as(db, "authenticated", f"SELECT public.ottoq_pause_run('{db.prod}', 'a signed-in caller')")
    assert not ok and _refused_at(err, "function", "ottoq_pause_run"), err
    assert _state(db, db.prod) == "running|false|-"


def test_after_service_role_still_pauses_resumes_starts_and_stops(db):
    # stop the production session the before-phase left running, start a new one, pause and resume it, stop it
    ok, out, err = _as_commit(db, "service_role", "SELECT public.ottoq_production_stop('0791 suite')", claims=True)
    assert ok and json.loads(out)["ok"] is True and json.loads(out)["sim_run_id"] == db.prod, err
    assert _state(db, db.prod).startswith("completed|")
    ok, out, err = _as_commit(db, "service_role", f"SELECT public.ottoq_production_start('{TWIN}')", claims=True)
    assert ok, err
    started = json.loads(out)
    assert started["ok"] is True and started["run_by"] == "production_live", started
    run = started["sim_run_id"]
    ok, out, err = _as_commit(db, "service_role", f"SELECT public.ottoq_pause_run('{run}', 'the platform')")
    assert ok and json.loads(out)["status"] == "paused" and "noop" not in json.loads(out), err
    ok, out, err = _as_commit(db, "service_role", f"SELECT public.ottoq_resume_run('{run}')")
    assert ok and json.loads(out)["status"] == "running" and json.loads(out)["clock_reanchored"] is True, err
    # in one session the patched doors answer as before: a door asked for a state the run is already in is a no-op
    ok, out, err = _as_commit(db, "service_role", f"SELECT public.ottoq_resume_run('{run}')")
    assert ok and json.loads(out) == {"ok": True, "noop": True, "status": "running", "note": "run was not paused"}, err
    ok, out, err = _as_commit(db, "service_role", "SELECT public.ottoq_production_stop('0791 suite')", claims=True)
    assert ok and json.loads(out)["sim_run_id"] == run, err
    assert _state(db, run).startswith("completed|")
    ok, out, err = _as_commit(db, "service_role", f"SELECT public.ottoq_pause_run('{run}', 'the platform')")
    assert ok and json.loads(out) == {"ok": True, "noop": True, "status": "completed", "note": "run was not running"}, err
    # and the owner, as cron and the SQL editor run them, keeps every one
    assert db.val("SELECT bool_and(has_function_privilege('postgres', p.oid, 'EXECUTE')) FROM pg_proc p "
                  f"WHERE p.proname IN ({_IN})") == "t"


def test_only_pause_and_resume_moved_and_only_by_their_patch(db):
    assert db.val(MD5S) == _expected(0, patched=True)
    assert db.before["md5"] == _expected(0)
    # each patched door, comment-stripped: one UPDATE, carrying the status it read, then the answer from the row count
    for sig, sets, reads in ((PAUSE, "paused", "running"), (RESUME, "running", "paused")):
        flat = db.val("SELECT btrim(regexp_replace(regexp_replace(regexp_replace(prosrc, '/\\*.*?\\*/', '', 'g'), "
                      "'--[^\\n]*', '', 'g'), '\\s+', ' ', 'g')) "
                      f"FROM pg_proc WHERE oid = 'public.{sig}'::regprocedure")
        assert flat.count("UPDATE ottoq_sim_runs") == 1, sig
        assert (f"WHERE sim_run_id = p_sim_run_id AND status = '{reads}'; IF NOT FOUND THEN SELECT * INTO v_run FROM "
                f"ottoq_sim_runs WHERE sim_run_id = p_sim_run_id; IF NOT FOUND THEN RETURN jsonb_build_object('ok', "
                f"false, 'error', 'run not found'); END IF; RETURN jsonb_build_object('ok', true, 'noop', true, "
                f"'status', v_run.status, 'note', 'run was not {reads}'); END IF; PERFORM ottoq_record_event(") in flat, sig
        assert f"SET status = '{sets}'," in flat, sig


def test_it_refuses_a_second_run_and_classifies_itself_false_false(db):
    rc, err = db.file(MIG)
    assert rc != 0 and "0791 P1: 0791 has run already" in err, err
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM public.ottoq_cert_lineage "
                  f"WHERE name = '{NAME}'") == "falsefalse"
    assert db.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0791_pre'") == "43"
    names = db.val("SELECT string_agg(object_name, '|' ORDER BY snapshot_id) FROM public.ottoq_schema_snapshots "
                   "WHERE label = '0791_pre' AND object_kind = 'grant'").split("|")
    expected = []
    for sig in sorted(LIVE, key=lambda s: s.encode()):
        expected += [f"{sig}::authenticated"] if LIVE[sig][3] else [f"{sig}::PUBLIC", f"{sig}::anon", f"{sig}::authenticated"]
    assert names == expected and len(names) == 41
    # the two definitions, whole, as P1 pinned them, and before the grants
    assert db.val("SELECT string_agg(object_name || '=' || def_md5 || '=' || (md5(definition) = def_md5)::text, ' ' "
                  "ORDER BY snapshot_id) FROM public.ottoq_schema_snapshots WHERE label = '0791_pre' "
                  "AND object_kind = 'function'") == \
        f"ottoq_pause_run={LIVE[PAUSE][0]}=true ottoq_resume_run={LIVE[RESUME][0]}=true"
    assert db.val("SELECT max(snapshot_id) FILTER (WHERE object_kind = 'function') < min(snapshot_id) FILTER "
                  "(WHERE object_kind = 'grant') FROM public.ottoq_schema_snapshots WHERE label = '0791_pre'") == "t"


def test_the_header_block_and_the_snapshot_rows_each_put_every_acl_and_both_definitions_back():
    block = _restore_block()
    assert len([l for l in block.splitlines() if l.startswith("GRANT EXECUTE ON ")]) == 17
    assert block.splitlines()[-1].startswith("DO $restore$") and "object_kind = 'function'" in block.splitlines()[-1]
    for how in ("header", "snapshot"):
        d = _load()
        try:
            before = d.val(HOLDERS)
            rc, err = d.file(MIG)
            assert rc == 0, err
            assert d.val(HOLDERS) == " ".join(sorted(f"{s}:{g}" for s in LIVE for g in ("postgres", "service_role")))
            assert d.val(MD5S) == _expected(0, patched=True)
            if how == "header":
                d.run(block)
            else:
                d.run("""DO $restore$ DECLARE r record; BEGIN
                           FOR r IN SELECT definition FROM public.ottoq_schema_snapshots
                                     WHERE label = '0791_pre' ORDER BY snapshot_id LOOP
                             EXECUTE r.definition;
                           END LOOP; END $restore$""")
            assert d.val(HOLDERS) == before, how
            assert "authenticated" in before and d.val(PRIV) == " ".join(
                f"{s}={'false' if LIVE[s][3] else 'true'},true,true" for s in sorted(LIVE))
            assert d.val(MD5S) == _expected(0), how                     # both definitions back, byte for byte
            # a signed-in caller reaches the door again, exactly as before the file
            ok, out, err = _as(d, "authenticated", f"SELECT public.ottoq_pause_run('{NOBODY}', 't')")
            assert ok and json.loads(out)["error"] == "run not found", err
        finally:
            _drop(d)


@pytest.mark.parametrize("extra, expect", [
    # someone hotfixed a door in the SQL editor since the file was written
    ("CREATE OR REPLACE FUNCTION public.ottoq_pause_run(p_sim_run_id uuid, p_reason text DEFAULT 'operator_pause'::text) "
     "RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS 'SELECT ''{}''::jsonb'",
     "0791 P1: ottoq_pause_run is not the definition this file was written against"),
    # the ACL moved: anon was granted a door, so this file's premise and its restore statements are both wrong
    ("GRANT EXECUTE ON FUNCTION public.ottoq_pause_run(uuid, text) TO anon", "0791 P1: not as read"),
    ("REVOKE EXECUTE ON PROCEDURE public.ottoq_demo_metronome(integer) FROM anon", "0791 P1: not as read"),
    # a routine of these names the list does not carry, and one the list carries that is gone
    ("CREATE FUNCTION public.ottoq_pause_run(p_sim_run_id uuid) RETURNS jsonb LANGUAGE sql AS 'SELECT ''{}''::jsonb'",
     "0791 P1: the sixteen names have 18 routines, not 17"),
    ("DROP FUNCTION public.ottoq_production_stop(text)", "0791 P1: 16 of the 17 signatures exist"),
    # a new run-control door a browser role may execute: read it before revoking
    ("CREATE FUNCTION public.ottoq_new_run_stopper(p uuid) RETURNS void LANGUAGE sql SECURITY DEFINER AS "
     "$f$ UPDATE public.ottoq_sim_runs SET status = 'aborted' WHERE sim_run_id = p $f$",
     "run-control routine this file does not name; read it before revoking: ottoq_new_run_stopper(uuid)"),
    # a definer that reaches a writer through a door
    ("CREATE FUNCTION public.ottoq_new_door(p uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS "
     "$f$ SELECT public.ottoq_pause_run(p) $f$",
     "read it before revoking: ottoq_new_door(uuid)"),
    # a SECURITY INVOKER caller a browser role may execute: revoking would break it for that role
    ("CREATE FUNCTION public.ottoq_new_invoker(p uuid) RETURNS jsonb LANGUAGE sql AS $f$ SELECT public.ottoq_pause_run(p) $f$",
     "through a SECURITY INVOKER caller; read it before revoking: public.ottoq_new_invoker"),
    # by dynamic SQL too, where the name is in a string
    ("CREATE FUNCTION public.ottoq_new_dynamic(p uuid) RETURNS jsonb LANGUAGE plpgsql AS "
     "$f$ DECLARE r jsonb; BEGIN EXECUTE format('SELECT ottoq_resume_run(%L)', p) INTO r; RETURN r; END $f$",
     "public.ottoq_new_dynamic"),
    # a trigger on a table a signed-in caller may write
    ("CREATE TABLE public.stub_writable (x int); GRANT INSERT ON public.stub_writable TO authenticated; "
     "CREATE FUNCTION public.ottoq_new_trg() RETURNS trigger LANGUAGE plpgsql AS "
     "$f$ BEGIN PERFORM public.ottoq_pause_run(gen_random_uuid()); RETURN NEW; END $f$; "
     "CREATE TRIGGER t_new AFTER INSERT ON public.stub_writable FOR EACH ROW EXECUTE FUNCTION public.ottoq_new_trg()",
     "public.ottoq_new_trg"),
    # a view a browser role could query: it needs EXECUTE as the reader
    ("CREATE VIEW public.ottoq_new_view AS SELECT public.ottoq_resume_run(sim_run_id) AS r FROM public.ottoq_sim_runs",
     "0791 P1: an object depends on a run-control routine"),
    # the census stops finding a door: an instrument that finds nothing is not evidence that nothing is open
    ("DROP FUNCTION public.ottoq_sim_advance_tick(uuid)",
     "0791 P1: the census no longer finds ottoq_run_policy_to_end(uuid,integer)"),
    # a harness only the platform may run that pauses a run: §3's FALSE/FALSE rests on there being none
    ("CREATE FUNCTION twin.ottoq_new_pause_harness(p uuid) RETURNS jsonb LANGUAGE sql SECURITY DEFINER AS "
     "$f$ SELECT public.ottoq_pause_run(p, 'harness') $f$; "
     "REVOKE ALL ON FUNCTION twin.ottoq_new_pause_harness(uuid) FROM PUBLIC",
     "0791 P1: a routine calls ottoq_pause_run or ottoq_resume_run, so §3's FALSE/FALSE is not proven; read it first: "
     "twin.ottoq_new_pause_harness"),
    # a certification in flight
    ("UPDATE public.stub_in_flight SET n = 1", "0791 P0:"),
])
def test_it_refuses_when_the_world_is_not_what_it_was_written_against(extra, expect):
    d = _load(extra)
    try:
        acl, md5s = d.val(ACLS), d.val(MD5S)
        rc, err = d.file(MIG)
        assert rc != 0 and expect in err, err
        assert d.val(ACLS) == acl and d.val(MD5S) == md5s                 # nothing changed on the way to a refusal
        assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
        assert d.val("SELECT count(*) FROM public.ottoq_schema_snapshots") == "0"
    finally:
        _drop(d)


#: V5 is not decorative: the file with a predicate, or the answer from the row count, cut out of its own patch text
#: (so the patch still applies and V3's undo still matches) fails at V5 and leaves the stub as it was
MUTANTS = {
    "pause_without_its_predicate": ("   WHERE sim_run_id = p_sim_run_id\n     AND status = 'running';\n",
                                    "   WHERE sim_run_id = p_sim_run_id;\n",
                                    "0791 V5 FAILED: ottoq_pause_run(uuid,text)'s UPDATE does not carry AND status = 'running'"),
    "resume_without_its_predicate": ("   WHERE sim_run_id = p_sim_run_id\n     AND status = 'paused';\n",
                                     "   WHERE sim_run_id = p_sim_run_id;\n",
                                     "0791 V5 FAILED: ottoq_resume_run(uuid)'s UPDATE does not carry AND status = 'paused'"),
    "resume_answering_running": ("    RETURN jsonb_build_object('ok', true, 'noop', true, 'status', v_run.status,\n"
                                 "                              'note', 'run was not paused');\n",
                                 "    RETURN jsonb_build_object('ok', true, 'sim_run_id', p_sim_run_id, 'status', 'running');\n",
                                 "0791 V5 FAILED: ottoq_resume_run(uuid) does not answer from the row count"),
    "pause_without_the_row_count": ("  IF NOT FOUND THEN\n    SELECT * INTO v_run FROM ottoq_sim_runs WHERE sim_run_id = "
                                    "p_sim_run_id;\n    IF NOT FOUND THEN RETURN jsonb_build_object('ok', false, 'error', "
                                    "'run not found'); END IF;\n    RETURN jsonb_build_object('ok', true, 'noop', true, "
                                    "'status', v_run.status,\n                              'note', 'run was not running');"
                                    "\n  END IF;\n",
                                    "",
                                    "0791 V5 FAILED: ottoq_pause_run(uuid,text) does not answer from the row count"),
}


@pytest.mark.parametrize("mutant", sorted(MUTANTS))
def test_v5_fails_when_the_patch_loses_a_predicate_or_its_answer(mutant, tmp_path):
    old, new, expect = MUTANTS[mutant]
    text = open(MIG).read()
    assert text.count(old) == 1, f"{mutant}: the cut is not in the file exactly once"
    path = tmp_path / "0791_mutant.sql"
    path.write_text(text.replace(old, new))
    d = _load()
    try:
        acl, md5s = d.val(ACLS), d.val(MD5S)
        rc, err = d.file(str(path))
        assert rc != 0 and expect in err, err
        assert "0791 V3 PASSED" in err, err                                # the patch applied and V3 saw only it
        assert d.val(ACLS) == acl and d.val(MD5S) == md5s
        assert d.val("SELECT count(*) FROM public.ottoq_cert_lineage") == "0"
    finally:
        _drop(d)


def test_a_mention_in_a_comment_is_not_a_call():
    d = _load("""CREATE FUNCTION public.ottoq_mentions_them() RETURNS int LANGUAGE plpgsql AS $f$
                 BEGIN
                   -- the cockpit used to call ottoq_pause_run(run) and ottoq_resume_run(run) here
                   /* CALL ottoq_demo_metronome(50) is cron 12's job */
                   RETURN 1;
                 END $f$""")
    try:
        rc, err = d.file(MIG)
        assert rc == 0 and "0791 V4 PASSED" in err and "0791 V5 PASSED" in err, err
    finally:
        _drop(d)


#: stand-ins for 0701's three, shaped as live: SECURITY DEFINER, executable by authenticated, and in the census
O701 = """
CREATE FUNCTION public.ottoq_purge_prior_runs(p_keep uuid) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER AS $f$
BEGIN DELETE FROM public.ottoq_sim_runs WHERE sim_run_id <> p_keep AND status <> 'running'; RETURN '{}'::jsonb; END $f$;
CREATE FUNCTION public.ottoq_start_busy_run(p_speed numeric, p_minutes integer, p_seed bigint) RETURNS uuid LANGUAGE sql
SECURITY DEFINER AS $f$ SELECT public.ottoq_sim_run_scenario('busy_day', p_seed, 'operator_demo', now()) $f$;
CREATE FUNCTION public.ottoq_start_busy_run_once(p_tag text, p_speed numeric, p_minutes integer, p_seed bigint) RETURNS uuid
LANGUAGE sql SECURITY DEFINER AS $f$ SELECT public.ottoq_start_busy_run(p_speed, p_minutes, p_seed) $f$;
REVOKE ALL ON FUNCTION public.ottoq_purge_prior_runs(uuid), public.ottoq_start_busy_run(numeric, integer, bigint),
  public.ottoq_start_busy_run_once(text, numeric, integer, bigint) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.ottoq_purge_prior_runs(uuid), public.ottoq_start_busy_run(numeric, integer, bigint),
  public.ottoq_start_busy_run_once(text, numeric, integer, bigint) TO service_role, authenticated;
"""


@pytest.mark.parametrize("closed", [False, True])
def test_0701s_three_are_accepted_open_or_closed_and_left_to_0701(closed):
    extra = O701 + ("REVOKE EXECUTE ON FUNCTION public.ottoq_purge_prior_runs(uuid), public.ottoq_start_busy_run(numeric, "
                    "integer, bigint), public.ottoq_start_busy_run_once(text, numeric, integer, bigint) FROM authenticated"
                    if closed else "")
    d = _load(extra)
    try:
        rc, err = d.file(MIG)
        assert rc == 0, err
        if closed:
            assert "0791 V4 PASSED: no run-control routine a browser role may execute\n" in err + "\n" or \
                   "except 0701" not in err, err
        else:
            assert ("except 0701's, which 0701 closes: ottoq_purge_prior_runs(uuid), ottoq_start_busy_run(numeric,integer,bigint), "
                    "ottoq_start_busy_run_once(text,numeric,integer,bigint)") in err, err
        # this file does not touch them either way
        held = d.val("SELECT string_agg(has_function_privilege('authenticated', p.oid, 'EXECUTE')::text, ',' ORDER BY p.proname) "
                     "FROM pg_proc p WHERE p.proname IN ('ottoq_purge_prior_runs', 'ottoq_start_busy_run', 'ottoq_start_busy_run_once')")
        assert held == ("false,false,false" if closed else "true,true,true")
    finally:
        _drop(d)


# ── G492: a pause or resume that waited behind a stop, from two real sessions ──

#: the stop, as 0790's door and ottoq_sim_mark_stopped write it (tests/fixtures/tick_lock_stub.sql carries both live
#: bodies): a running run's row taken FOR NO KEY UPDATE first, then mark_stopped's UPDATE
STOP = ("SELECT 1 FROM public.ottoq_sim_runs WHERE sim_run_id = '{run}' FOR NO KEY UPDATE; "
        "UPDATE public.ottoq_sim_runs SET status = 'completed', ended_at = COALESCE(ended_at, now()), "
        "next_tick_due_at = NULL, failure_reason = COALESCE(failure_reason, 'operator_stop') "
        "WHERE sim_run_id = '{run}' AND status IN ('running', 'paused')")
#: the operator start's stop and start in one transaction (ottoq_sim_run_scenario: stop the depot's runs, insert a run)
STOP_AND_START = STOP + ("; INSERT INTO public.ottoq_sim_runs (sim_run_id, scenario_id, scenario_code, sim_clock_start, "
                         "sim_clock_current, sim_clock_end, depot_id, status, run_by) VALUES ('{new}', '" + SCENARIO + "', "
                         "'busy_day', now(), now(), now() + interval '1 day', '" + TWIN + "', 'running', 'operator_demo')")
#: the demo start's abort-then-purge (ottoq_start_demo_run, 0790 §3): the run marked aborted, its run-scoped rows
#: deleted, then its row
ABORT_PURGE = ("UPDATE public.ottoq_sim_runs SET status = 'aborted', ended_at = now(), next_tick_due_at = NULL "
               "WHERE sim_run_id = '{run}' AND status IN ('running', 'paused'); "
               "DELETE FROM public.stub_events WHERE sim_run_id = '{run}'; "
               "DELETE FROM public.ottoq_sim_runs WHERE sim_run_id = '{run}'")
#: the holder keeps its transaction open until the test has seen the door wait on the run's row
HELD = "DO $w$ BEGIN WHILE NOT EXISTS (SELECT 1 FROM public.t0791_release) LOOP PERFORM pg_sleep(0.02); END LOOP; END $w$"
CASES = {
    # case: (the run's status when the door reads it, the other session, the door)
    "pause_behind_a_stop": ("running", STOP, "pause"),
    "resume_behind_a_stop": ("paused", STOP, "resume"),
    "resume_behind_a_stop_that_starts_a_run": ("paused", STOP_AND_START, "resume"),
    "pause_behind_the_demo_start": ("running", ABORT_PURGE, "pause"),
    "resume_behind_the_demo_start": ("paused", ABORT_PURGE, "resume"),
}
DOOR = {"pause": "SELECT public.ottoq_pause_run('{run}', 'behind a stop')",
        "resume": "SELECT public.ottoq_resume_run('{run}')"}


def _bg(db, sql, app):
    return subprocess.Popen([*_psql_args(db), "-c", sql], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
                            env={**os.environ, "PGAPPNAME": app})


def _wait_for(db, predicate, what, timeout=30.0):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if db.val(predicate) == "t":
            return
        time.sleep(0.05)
    raise AssertionError(f"timed out waiting for {what}")


def _race(db, case):
    """The other session takes the run's row and stops (or aborts and deletes) the run, and holds its transaction; the
    door reads the run, waits on the row, and is seen waiting; then the other session commits and the door goes on."""
    status, other, door = CASES[case]
    payload = '{"paused_at": "2026-10-17T14:00:00+00:00", "pause_reason": "operator_pause"}' if status == "paused" else "{}"
    run = _run(db, "operator_demo", status=status, payload=payload)
    new = str(uuid.uuid4())
    db.run("CREATE TABLE IF NOT EXISTS public.t0791_release (x int); TRUNCATE public.t0791_release")
    holder = _bg(db, f"BEGIN; {other.format(run=run, new=new)}; {HELD}; COMMIT;", "t0791_other")
    _wait_for(db, "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 't0791_other' "
                  "AND wait_event = 'PgSleep')", "the other session to hold the run's row")
    waiter = _bg(db, f"BEGIN; SET LOCAL ROLE service_role; {DOOR[door].format(run=run)}; COMMIT;", "t0791_door")
    _wait_for(db, "SELECT EXISTS (SELECT 1 FROM pg_stat_activity WHERE application_name = 't0791_door' "
                  "AND wait_event_type = 'Lock')", "the door to wait on the run's row")
    db.run("INSERT INTO public.t0791_release VALUES (1)")
    h_out, h_err = holder.communicate(timeout=60)
    d_out, d_err = waiter.communicate(timeout=60)
    assert holder.returncode == 0, h_err
    lines = [l for l in d_out.splitlines() if l.strip()]
    answer = json.loads(lines[-1]) if waiter.returncode == 0 and lines else None
    row = db.val(f"SELECT status || '|' || (ended_at IS NOT NULL)::text || '|' || coalesce(failure_reason, '-') "
                 f"FROM public.ottoq_sim_runs WHERE sim_run_id = '{run}'") or "gone"
    events = db.val(f"SELECT coalesce(string_agg(event_type, ' '), '-') FROM public.stub_events WHERE sim_run_id = '{run}'")
    other_run = db.val(f"SELECT status FROM public.ottoq_sim_runs WHERE sim_run_id = '{new}'") or "-"
    return {"answer": answer, "rc": waiter.returncode, "err": d_err, "row": row, "events": events, "new": other_run}


#: before 0791, each as G492 reads it (or, for the demo start, as live's foreign key makes it)
BEFORE = {
    "pause_behind_a_stop": dict(answer_status="paused", row="paused|true|operator_stop", events="twin.sim_run_paused"),
    "resume_behind_a_stop": dict(answer_status="running", row="running|true|operator_stop", events="twin.sim_run_resumed"),
    "resume_behind_a_stop_that_starts_a_run": dict(sqlstate="23505", error="ottoq_one_running_run_per_depot",
                                                   row="completed|true|operator_stop", events="-", new="running"),
    "pause_behind_the_demo_start": dict(sqlstate="23503", error="fk_stub_events_sim_run", row="gone", events="-"),
    "resume_behind_the_demo_start": dict(sqlstate="23503", error="fk_stub_events_sim_run", row="gone", events="-"),
}
#: after 0791: the door updates nothing and says so, from the row as it is now, and records no event
AFTER = {
    "pause_behind_a_stop": dict(answer={"ok": True, "noop": True, "status": "completed", "note": "run was not running"},
                                row="completed|true|operator_stop", events="-"),
    "resume_behind_a_stop": dict(answer={"ok": True, "noop": True, "status": "completed", "note": "run was not paused"},
                                 row="completed|true|operator_stop", events="-"),
    "resume_behind_a_stop_that_starts_a_run": dict(
        answer={"ok": True, "noop": True, "status": "completed", "note": "run was not paused"},
        row="completed|true|operator_stop", events="-", new="running"),
    "pause_behind_the_demo_start": dict(answer={"ok": False, "error": "run not found"}, row="gone", events="-"),
    "resume_behind_the_demo_start": dict(answer={"ok": False, "error": "run not found"}, row="gone", events="-"),
}


@pytest.mark.parametrize("phase", ["before", "after"])
@pytest.mark.parametrize("case", sorted(CASES))
def test_g492_a_pause_or_resume_that_waited_behind_a_stop(case, phase):
    d = _load()
    try:
        if phase == "after":
            rc, err = d.file(MIG)
            assert rc == 0 and "0791 V5 PASSED" in err, err
        got = _race(d, case)
        want = (BEFORE if phase == "before" else AFTER)[case]
        if "sqlstate" in want:
            assert got["rc"] != 0 and want["sqlstate"] in got["err"] and want["error"] in got["err"], got
        elif "answer" in want:
            assert got["rc"] == 0 and got["answer"] == want["answer"], got
        else:
            assert got["rc"] == 0 and got["answer"]["ok"] is True and "noop" not in got["answer"] \
                and got["answer"]["status"] == want["answer_status"], got
        assert got["row"] == want["row"] and got["events"] == want["events"], got
        assert got["new"] == want.get("new", "-"), got
    finally:
        _drop(d)
