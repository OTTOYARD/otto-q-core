"""db/migrations/0707, EXECUTED: the engine notices when a channel goes dark.

WHY THIS EXISTS. Nothing in the engine read cron.job_run_details, nothing called pg_notify, and the agent's dispatches
never read their own pg_net replies, so a dark channel (a starved cron beat, a stalled tick, an agent or CP-SAT that
stopped answering, a refused credential) was only ever found by someone reading tables by hand (0707 §1). Executed here
on a stub carrying the live column names:
  - a healthy world reads green on every channel, and a timed-out agent dispatch alone does not make pg_net amber;
  - each channel goes amber and red at the thresholds the header states, and names what went dark;
  - with no run, the run-scoped channels read idle, and an unarmed agent reads idle, not red;
  - the watchdog writes one row per channel, then nothing until a status changes, and the record is append-only.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import os
import subprocess
import sys
import uuid

import pytest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
STUB = os.path.join(ROOT, "tests", "fixtures", "channel_watchdog_stub.sql")
M0707 = os.path.join(ROOT, "db", "migrations", "0707_the_engine_notices_when_a_channel_goes_dark.sql")
RUN = "0707aaaa-0000-0000-0000-000000000001"
DEPOT = "11111111-1111-1111-1111-111111111111"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


@pytest.fixture()
def db():
    name = f"ottoq_watch_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, err = d.file(STUB)
        assert rc == 0, f"stub did not load: {err}"
        rc, err = d.file(M0707)
        assert rc == 0 and "0707 V1-V4 PASSED" in err, err
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _job(d, name, schedule, ago_s, every_s=None, failed_ago_s=None):
    """A cron job and its runs: one start every `every_s` back over the last hour, the newest `ago_s` ago."""
    jid = d.val(f"""INSERT INTO cron.job (jobname, schedule, command) VALUES ('{name}', '{schedule}', 'SELECT 1')
                    ON CONFLICT (jobname) DO UPDATE SET schedule = EXCLUDED.schedule RETURNING jobid""")
    every_s = every_s or 60
    d.val(f"""INSERT INTO cron.job_run_details (jobid, start_time, end_time, status)
              SELECT {jid}, now() - make_interval(secs => {ago_s} + g * {every_s}),
                     now() - make_interval(secs => {ago_s} + g * {every_s}) + interval '1 second', 'succeeded'
                FROM generate_series(60 * 60 / {every_s}, 0, -1) g""")
    if failed_ago_s is not None:
        d.val(f"""INSERT INTO cron.job_run_details (jobid, start_time, end_time, status, return_message)
                  VALUES ({jid}, now() - make_interval(secs => {failed_ago_s}), now(), 'failed',
                          'ERROR:  canceling statement due to user request')""")
    return jid


def _healthy(d, armed=True):
    # the watchdog's own job, scheduled by the migration, has run too
    _job(d, "ottoq-channel-watchdog", "* * * * *", 10)
    _job(d, "ottoq-depot-tick", "*/2 * * * *", 30, every_s=120)
    _job(d, "ottoq-demo-metronome", "* * * * *", 20)
    _job(d, "ottoq-run-purge-nightly", "0 9 * * *", 3600 * 5, every_s=3600)
    d.val(f"""INSERT INTO public.ottoq_sim_runs (sim_run_id, depot_id, status, tick_count, started_at, last_tick_at,
                                                 next_tick_due_at, run_by)
              VALUES ('{RUN}', '{DEPOT}', 'running', 73, now() - interval '30 minutes', now() - interval '3 seconds',
                      now() + interval '2 seconds', 'operator_demo')""")
    if armed:
        d.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
                  VALUES ('run', '{RUN}', 'agent_solver_chain_enabled', 1, 'test')""")
    d.val(f"""INSERT INTO public.ottoq_agent_pass_evidence (sim_run_id, consulted, model_answered, attempts, total_ms,
                                                            recorded_at)
              SELECT '{RUN}', g % 5 = 0, CASE WHEN g % 5 = 0 THEN 'nvidia/nemotron-3-super-120b-a12b' END,
                     CASE WHEN g % 5 = 0 THEN '[{{"status":503}},{{"status":"ok"}}]'::jsonb END, 40000,
                     now() - make_interval(secs => 20 + g * 50)
                FROM generate_series(0, 30) g""")
    d.val(f"""INSERT INTO public.ottoq_model_call_ledger (sim_run_id, provider, http_status, outcome, called_at)
              SELECT '{RUN}', 'cpsat_service', 200, 'answered', now() - make_interval(secs => 15 + g * 50)
                FROM generate_series(0, 30) g""")
    d.val("""INSERT INTO net._http_response (status_code, timed_out, error_msg, created)
             SELECT 200, false, NULL, now() - make_interval(secs => g * 20) FROM generate_series(0, 30) g""")
    # an agent dispatch that outlived pg_net's 20 s timeout (and completed): counted, not judged
    d.val("""INSERT INTO net._http_response (status_code, timed_out, error_msg, created)
             VALUES (NULL, true, 'Timeout of 20000 ms reached.', now() - interval '2 minutes')""")


def _read(d, offset="0 seconds"):
    rows = d.json(f"""SELECT json_object_agg(channel, json_build_object('status', status, 'reason', reason,
                                                                         'observed', observed))
                        FROM public.ottoq_channel_health_read(now() + interval '{offset}')""")
    return rows


def test_0707_a_healthy_world_reads_green_and_a_timeout_alone_is_not_amber(db):
    _healthy(db)
    r = _read(db)
    assert {k: v["status"] for k, v in r.items()} == {
        "cron": "green", "run_tick": "green", "agent_passes": "green", "agent_model": "green", "cpsat": "green",
        "pg_net": "green"}, r
    assert r["pg_net"]["observed"]["timed_out"] == 1
    assert r["cron"]["observed"]["not_judged"] == ["ottoq-run-purge-nightly"], r["cron"]
    assert r["agent_model"]["observed"]["primary_failed_1h"] >= 1


def test_0707_cron_goes_amber_on_a_gap_and_red_when_a_beat_stops_and_names_the_job(db):
    _healthy(db)
    # the depot tick: a 7-minute hole 20 minutes ago, fresh now -> amber
    db.val("""DELETE FROM cron.job_run_details d USING cron.job j
               WHERE j.jobid = d.jobid AND j.jobname = 'ottoq-depot-tick'
                 AND d.start_time BETWEEN now() - interval '27 minutes' AND now() - interval '21 minutes'""")
    r = _read(db)
    assert r["cron"]["status"] == "amber" and "ottoq-depot-tick went" in r["cron"]["reason"], r["cron"]
    # the metronome: nothing for 6 minutes -> red, and red outranks the tick's amber
    db.val("""DELETE FROM cron.job_run_details d USING cron.job j
               WHERE j.jobid = d.jobid AND j.jobname = 'ottoq-demo-metronome' AND d.start_time > now() - interval '6 minutes'""")
    r = _read(db)
    assert r["cron"]["status"] == "red" and "ottoq-demo-metronome has not started" in r["cron"]["reason"], r["cron"]
    jobs = {j["job"]: j["status"] for j in r["cron"]["observed"]["not_green"]}
    assert jobs == {"ottoq-depot-tick": "amber", "ottoq-demo-metronome": "red"}, jobs


def test_0707_a_failed_cron_run_is_amber_with_its_message(db):
    _healthy(db)
    _job(db, "ottoq-recert-runner", "* * * * *", 5, failed_ago_s=600)
    r = _read(db)
    assert r["cron"]["status"] == "amber" and "canceling statement" in r["cron"]["reason"], r["cron"]


def test_0707_a_stalled_tick_and_a_silent_agent_and_solver_go_amber_then_red(db):
    _healthy(db)
    db.val(f"UPDATE public.ottoq_sim_runs SET next_tick_due_at = now() - interval '3 minutes' WHERE sim_run_id = '{RUN}'")
    assert _read(db)["run_tick"]["status"] == "amber"
    db.val(f"UPDATE public.ottoq_sim_runs SET next_tick_due_at = now() - interval '6 minutes' WHERE sim_run_id = '{RUN}'")
    r = _read(db)
    assert r["run_tick"]["status"] == "red" and "overdue" in r["run_tick"]["reason"], r["run_tick"]
    db.val("DELETE FROM public.ottoq_agent_pass_evidence WHERE recorded_at > now() - interval '4 minutes'")
    db.val("DELETE FROM public.ottoq_model_call_ledger WHERE called_at > now() - interval '4 minutes'")
    r = _read(db)
    assert r["agent_passes"]["status"] == "amber" and r["cpsat"]["status"] == "amber", r
    db.val("DELETE FROM public.ottoq_agent_pass_evidence WHERE recorded_at > now() - interval '11 minutes'")
    db.val("DELETE FROM public.ottoq_model_call_ledger WHERE called_at > now() - interval '11 minutes'")
    r = _read(db)
    assert r["agent_passes"]["status"] == "red" and "no agent pass for" in r["agent_passes"]["reason"], r
    assert r["cpsat"]["status"] == "red" and "no CP-SAT call for" in r["cpsat"]["reason"], r


def test_0707_cpsat_answering_non_200_is_red_when_none_succeed(db):
    _healthy(db)
    db.val(f"""INSERT INTO public.ottoq_model_call_ledger (sim_run_id, provider, http_status, outcome, called_at)
               VALUES ('{RUN}', 'cpsat_service', 502, 'error', now() - interval '5 seconds')""")
    assert _read(db)["cpsat"]["status"] == "amber"
    db.val("UPDATE public.ottoq_model_call_ledger SET http_status = 503 WHERE called_at > now() - interval '15 minutes'")
    r = _read(db)
    assert r["cpsat"]["status"] == "red" and "none of the last" in r["cpsat"]["reason"], r["cpsat"]


def test_0707_the_model_red_when_nobody_answers_amber_when_a_quarter_fail(db):
    _healthy(db)
    db.val("UPDATE public.ottoq_agent_pass_evidence SET model_answered = NULL WHERE consulted AND pass_id % 2 = 0")
    assert _read(db)["agent_model"]["status"] == "amber"
    db.val("UPDATE public.ottoq_agent_pass_evidence SET model_answered = NULL WHERE consulted")
    r = _read(db)
    assert r["agent_model"]["status"] == "red" and r["agent_model"]["observed"]["answered_1h"] == 0, r["agent_model"]


def test_0707_pg_net_red_on_a_refused_credential_amber_on_a_server_error(db):
    _healthy(db)
    db.val("INSERT INTO net._http_response (status_code, timed_out, created) VALUES (500, false, now())")
    assert _read(db)["pg_net"]["status"] == "amber"
    db.val("INSERT INTO net._http_response (status_code, timed_out, created) VALUES (401, false, now())")
    r = _read(db)
    assert r["pg_net"]["status"] == "red" and "401/403" in r["pg_net"]["reason"], r["pg_net"]


def test_0707_no_run_is_idle_and_an_unarmed_agent_is_idle_not_red(db):
    _job(db, "ottoq-channel-watchdog", "* * * * *", 10)
    r = _read(db)
    assert [r[c]["status"] for c in ("run_tick", "agent_passes", "cpsat", "agent_model", "pg_net")] == ["idle"] * 5, r
    _healthy(db, armed=False)
    db.val("DELETE FROM public.ottoq_agent_pass_evidence")
    db.val("DELETE FROM public.ottoq_model_call_ledger")
    r = _read(db)
    assert r["agent_passes"]["status"] == "idle" and r["cpsat"]["status"] == "idle", r
    # armed, and no pass 30 minutes in: that is a dark agent, not an idle one
    db.val(f"""INSERT INTO public.ottoq_policy_params (scope_type, scope_id, param_key, param_value, updated_by)
               VALUES ('run', '{RUN}', 'agent_solver_chain_enabled', 1, 'test')""")
    r = _read(db)
    assert r["agent_passes"]["status"] == "red" and "since the run started" in r["agent_passes"]["reason"], r


def test_0707_the_watchdog_writes_on_change_only_and_the_record_is_append_only(db):
    # the migration's V3 wrote the first six rows on an empty world
    assert db.val("SELECT count(*) FROM public.ottoq_channel_health") == "6"
    _healthy(db)
    r = db.json("SELECT public.ottoq_channel_watchdog()")
    first = int(r["written"])
    assert first >= 1, r  # idle -> green on the run-scoped channels at least
    r = db.json("SELECT public.ottoq_channel_watchdog()")
    assert r["written"] == 0, r
    db.val(f"UPDATE public.ottoq_sim_runs SET next_tick_due_at = now() - interval '6 minutes' WHERE sim_run_id = '{RUN}'")
    r = db.json("SELECT public.ottoq_channel_watchdog()")
    assert r["written"] == 1 and r["run_tick"] == "red", r
    row = db.json("""SELECT row_to_json(n) FROM public.ottoq_channel_health_now n WHERE channel = 'run_tick'""")
    assert row["status"] == "red", row
    assert db.val("""SELECT prev_status FROM public.ottoq_channel_health WHERE channel = 'run_tick'
                      ORDER BY health_id DESC LIMIT 1""") == "green"
    rc, _, err = db.run("DELETE FROM public.ottoq_channel_health")
    assert rc != 0 and "append-only" in err, err
