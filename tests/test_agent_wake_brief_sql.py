"""db/migrations/0823, EXECUTED: the agent is told why it was woken, which cars and chargers are behind each reason,
and what it said last.

WHY THIS EXISTS. Since 0795 the agent is consulted on exceptions, and the wake gate knows why each consult happened, but
the model was sent its board alone: of 286 answered consults at the twin depot from 2026-11-05 to 2026-11-13, none of the
5 woken by an emergency mentions one, and none changed engine state (FINDINGS G540). 0823 adds a read-only brief the edge
function puts ahead of the board. Executed here over tests/fixtures/agent_scouts_wake_stub.sql with 0703-0711 applied and
the columns the brief reads added as live has them (information_schema, read 2026-11-13):
  - at the dial's default the brief is NULL, and with it on a run's first consult says what "new" means;
  - a charge a fault cut is listed when it is new since the last answer or its car is still in the charge line with no
    charge since, with where the car is now; a cut from before the last answer whose car charged again is not;
  - a faulted charger is new only if it faulted since the last answer; a decommissioned one is not listed;
  - a car in an emergency, the cars longest past their owner's contract wait, a new scout finding and a live
    demand-response call each appear on their case and not on their near-miss;
  - `changed` holds each count that moved, and `you_said` the directives of the last answered consult;
  - an error inside it comes back as {error}, never raised; it writes nothing; no browser role can run it;
  - the coverage view matches a whole name, any letter case, and not a longer name that contains it;
  - 0823 applies as declared, with Windows line endings too, and refuses a second apply.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import tempfile

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)
import test_agent_scouts_wake_sql as w  # noqa: E402  (the stub engine and its helpers)
from test_agent_scouts_wake_sql import db  # noqa: F401,E402  (the fixture: a fresh database with the stub loaded)

ROOT = base.ROOT
M0823 = os.path.join(ROOT, "db", "migrations", "0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last.sql")
L0823 = "0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last"
L0795 = "0795_the_agents_charge_order_becomes_a_background_challenger_and_the_agent_wakes_for_exceptions"
BRIEF = "public.ottoq_agent_wake_brief(uuid,jsonb)"
RUN, T, DEPOT, OP, _id = w.RUN, w.T, w.DEPOT, w.OP, w._id
LAST = "2026-10-13 14:30:00+00"     # the agent's last answered consult, 30 sim-minutes before T

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

# the columns and the table the brief reads that the stub lacks, as live has them (information_schema, 2026-11-13); and
# 0795's lineage row, which P1 asks for (0795 itself patches functions this stub does not carry)
LIVE_SHAPE = f"""
ALTER TABLE public.ottoq_ocpp_chargers ADD COLUMN ocpp_identifier text, ADD COLUMN last_fault_code text,
  ADD COLUMN last_fault_at timestamptz;
ALTER TABLE public.vehicles ADD COLUMN last_state_change timestamptz;
CREATE TABLE public.ocpp_sessions (id uuid PRIMARY KEY DEFAULT gen_random_uuid(), sim_run_id uuid, vehicle_id uuid,
  stall_id uuid, status text, started_at timestamptz, ended_at timestamptz, soc_end integer, stopped_reason text);
INSERT INTO public.ottoq_cert_lineage VALUES ('{L0795}', false, 'stand-in for the test', now(), false);
"""


def _ready(d, apply=True, dial=True):
    w._world(d)
    w._apply(d, "0703", "0704", "0705", "0710", "0711")
    for stmt in filter(None, (s.strip() for s in LIVE_SHAPE.split(";"))):
        d.val(stmt)
    if apply:
        rc, err = d.file(M0823)
        assert rc == 0, f"0823 did not apply: {err}"
    if apply and dial:
        d.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_wake_brief', 1, 'test', now())")


def _brief(d, wake=None):
    wake = wake if wake is not None else {"reasons": ["charger_fault"], "fingerprint": {}}
    out = d.val(f"SELECT COALESCE(public.ottoq_agent_wake_brief('{RUN}', '{json.dumps(wake)}'::jsonb)::text, 'null')")
    return json.loads(out)


def _answered(d, fp=None, said=("The service bays are the wall.",), clock=LAST, tick=70):
    """The agent's last answered consult: the decision row the wake gate reads (0710)."""
    applied = [{"type": "directive", "text": t, "severity": "info"} for t in said]
    d.val(f"""INSERT INTO ottoq_decisions (sim_run_id, tick_seq, sim_clock, action_context, resolved_action_context,
                                          outcome_status, context_frame, proposed_action, enacted_action)
              VALUES ('{RUN}', {tick}, '{clock}', 'task_start', 'orchestrator_agent', 'enacted',
                      jsonb_build_object('wake', jsonb_build_object('fingerprint', '{json.dumps(fp or {})}'::jsonb)),
                      '{{}}', jsonb_build_object('source', 'nemotron', 'applied', $j${json.dumps(applied)}$j$::jsonb))""")


def _line(d, *cars):
    """The kernel's charge line: (car, wait_min) in order."""
    d.val(f"DELETE FROM stub_kernel_line WHERE sim_run_id = '{RUN}'")
    for k, (car, wait) in enumerate(cars):
        d.val(f"INSERT INTO stub_kernel_line VALUES ('{RUN}', '{_id(car)}', {k + 1}, {wait}, 50)")


def _session(d, car, stall, status, started, ended=None, soc_end=None, reason=None, run=RUN):
    e = f"'{ended}'" if ended else "NULL"
    s = soc_end if soc_end is not None else "NULL"
    r = f"'{reason}'" if reason else "NULL"
    d.val(f"""INSERT INTO ocpp_sessions (sim_run_id, vehicle_id, stall_id, status, started_at, ended_at, soc_end,
                                         stopped_reason)
              VALUES ('{run}', '{_id(car)}', '{_id(stall)}', '{status}', '{started}', {e}, {s}, {r})""")


def _cuts(b):
    return {c["car"]: c for c in b.get("subjects", {}).get("charges_cut_by_fault", {}).get("cars", [])}


def test_0823_applies_and_refuses_a_second_apply(db):
    _ready(db, dial=False)
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{L0823}'") == "falsefalse"
    assert db.val("SELECT default_value::text || '/' || agent_writable::text FROM ottoq_policy_param_catalog "
                  "WHERE param_key = 'agent_wake_brief'") == "0/false"
    # on at the twin depot, under a person's name (rule 12)
    assert db.val(f"SELECT param_value::text FROM ottoq_policy_params WHERE scope_type = 'depot' "
                  f"AND scope_id = '{DEPOT}' AND param_key = 'agent_wake_brief'") == "1"
    rc, err = db.file(M0823)
    assert rc != 0 and "0823 P2: already applied" in err


def test_0823_applies_with_windows_line_endings_to_the_same_body(db):
    _ready(db, apply=False)
    with open(M0823, newline="") as f:
        sql = f.read()
    assert "\r" not in sql
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False, newline="") as t:
        t.write(sql.replace("\n", "\r\n"))
    try:
        rc, err = db.file(t.name)       # V5 inside the file holds the body to the md5 the tests ran
        assert rc == 0, err
    finally:
        os.unlink(t.name)


def test_0823_probes_a_run_with_agent_passes_at_the_apply_and_leaves_no_setting(db):
    """V4: where a consulted pass exists, the file turns the dial on for that run inside a savepoint, reads a brief,
    and rolls the setting back."""
    _ready(db, apply=False)
    _session(db, "A", "F1", "faulted", "2026-10-13 14:20:00+00", "2026-10-13 14:50:00+00", 62, "fault.connector_cable")
    db.val(f"""INSERT INTO ottoq_agent_pass_evidence (chain_id, agent_version, sim_run_id, depot_id, consulted, sim_clock,
                                                      outcome_class)
               VALUES ('pre', 'v31', '{RUN}', '{DEPOT}', true, '{T}', 'advisory')""")
    rc, err = db.file(M0823)
    assert rc == 0, err
    assert f"0823 V4 PASSED on run {RUN}" in err and "charges_cut_by_fault" in err
    assert db.val("SELECT count(*) FROM ottoq_policy_params WHERE param_key = 'agent_wake_brief' AND scope_type = 'run'") == "0"
    assert _brief(db) is None       # the stub reads run scope only, and the probe's run setting is gone


def test_0823_refuses_a_database_without_0795(db):
    _ready(db, apply=False)
    db.val(f"DELETE FROM ottoq_cert_lineage WHERE name = '{L0795}'")
    rc, err = db.file(M0823)
    assert rc != 0 and "0823 P1: 0795 is not classified" in err


def test_at_the_default_there_is_no_brief(db):
    _ready(db, dial=False)
    _session(db, "A", "F1", "faulted", "2026-10-13 14:40:00+00", "2026-10-13 14:50:00+00", 62, "fault.connector_cable")
    assert _brief(db) is None
    # the stub's policy_get reads run scope only; the dial at 1 on the run turns it on
    db.val(f"INSERT INTO ottoq_policy_params VALUES ('run', '{RUN}', 'agent_wake_brief', 1, 'test', now())")
    assert _brief(db)["v"] == 1
    # an unknown run and a null run are NULL, not an error
    assert db.val("SELECT public.ottoq_agent_wake_brief('b0000000-0000-0000-0000-000000000000', '{}'::jsonb) IS NULL") == "t"
    assert db.val("SELECT public.ottoq_agent_wake_brief(NULL, '{}'::jsonb) IS NULL") == "t"


def test_a_first_consult_says_what_new_means_and_carries_the_reasons(db):
    _ready(db)
    b = _brief(db, {"reasons": ["first_consult"], "fingerprint": {"faulted_chargers": 0}})
    assert b["reasons"] == ["first_consult"]
    assert "first answer" in b["new_means"]
    assert "last_answer" not in b and "changed" not in b
    assert b["subjects"] == {}
    # a wake with no reasons array, or not an object at all, still gets a brief
    assert _brief(db, {"fingerprint": 3})["reasons"] == []
    assert db.val(f"SELECT public.ottoq_agent_wake_brief('{RUN}', 'null'::jsonb) ->> 'v'") == "1"
    assert db.val(f"SELECT public.ottoq_agent_wake_brief('{RUN}', NULL) ->> 'v'") == "1"


def test_a_cut_charge_is_listed_with_where_its_car_is_now(db):
    _ready(db)
    _answered(db)
    _line(db, ("D", 80), ("A", 12))
    # A: cut 10 minutes ago, still waiting, second in line -> new, waiting
    _session(db, "A", "F1", "faulted", "2026-10-13 14:20:00+00", "2026-10-13 14:50:00+00", 62, "fault.connector_cable")
    # B: cut 20 minutes ago, charging again 4 minutes later on L1 -> new, charging again
    _session(db, "B", "F1", "faulted", "2026-10-13 14:00:00+00", "2026-10-13 14:40:00+00", 75, "fault.thermal_emergency")
    _session(db, "B", "L1", "active", "2026-10-13 14:44:00+00")
    # C: cut before the last answer and charged again -> closed, not listed
    _session(db, "C", "F1", "faulted", "2026-10-13 13:00:00+00", "2026-10-13 13:20:00+00", 40, "fault.connector_cable")
    _session(db, "C", "L1", "completed", "2026-10-13 13:25:00+00", "2026-10-13 14:00:00+00", 100, "completed")
    # D: cut 5 hours ago, before the last answer, never charged since and still in line -> listed, not new, first
    _session(db, "D", "L1", "faulted", "2026-10-13 09:30:00+00", "2026-10-13 10:00:00+00", 55, "fault.communication_dropout")
    # E: cut before the last answer, no charge since, NOT in the line (it left or finished) -> not listed
    _session(db, "E", "F1", "faulted", "2026-10-13 12:00:00+00", "2026-10-13 12:30:00+00", 99, "fault.connector_cable")
    # G: a completed charge is not a cut; H: a cut on another run is not this run's
    _session(db, "G", "F1", "completed", "2026-10-13 14:35:00+00", "2026-10-13 14:55:00+00", 100, "completed")
    _session(db, "H", "F1", "faulted", "2026-10-13 14:35:00+00", "2026-10-13 14:55:00+00", 50, "fault.connector_cable",
             run="c0000000-0000-0000-0000-000000000001")
    b = _brief(db)
    sub = b["subjects"]["charges_cut_by_fault"]
    cuts = _cuts(b)
    assert sub["count"] == 3 and set(cuts) == {"Car-A", "Car-B", "Car-D"}
    # the cars still waiting come first, the longest wait first
    assert [c["car"] for c in sub["cars"]] == ["Car-D", "Car-A", "Car-B"]
    a = cuts["Car-A"]
    assert (a["new"], a["post"], a["fault"], a["cut_at_soc"], a["target"], a["min_ago"]) == \
        (True, "F1", "fault.connector_cable", 62, 100, 10)
    assert a["waiting_in_line_pos"] == 2 and a["state"] == "arrived_at_gate" and a["soc_now"] == 60
    assert "charging_again_on" not in a and a["owner"] == "Op"
    bb = cuts["Car-B"]
    assert (bb["new"], bb["charging_again_on"], bb["again_after_min"]) == (True, "L1", 4)
    assert "waiting_in_line_pos" not in bb and "state" not in bb
    dd = cuts["Car-D"]
    assert (dd["new"], dd["waiting_in_line_pos"], dd["min_ago"]) == (False, 1, 300)


def test_a_charge_started_after_the_runs_clock_does_not_close_a_cut(db):
    _ready(db)
    _answered(db)
    _line(db, ("A", 12))
    _session(db, "A", "F1", "faulted", "2026-10-13 14:20:00+00", "2026-10-13 14:50:00+00", 62, "fault.connector_cable")
    _session(db, "A", "L1", "active", "2026-10-13 15:05:00+00")       # after T: not yet
    _session(db, "B", "F1", "faulted", "2026-10-13 14:55:00+00", "2026-10-13 15:10:00+00", 62, "fault.connector_cable")
    cuts = _cuts(_brief(db))
    assert set(cuts) == {"Car-A"} and cuts["Car-A"]["waiting_in_line_pos"] == 1


def test_a_faulted_charger_is_new_only_since_the_last_answer(db):
    _ready(db)
    _answered(db)
    for code, fault_at, state, decom in (("N1", "2026-10-13 14:45:00+00", "Faulted", None),      # new
                                         ("O1", "2026-10-13 13:00:00+00", "Faulted", None),      # older
                                         ("X1", "2026-10-13 14:45:00+00", "Faulted", T),         # decommissioned
                                         ("R1", "2026-10-13 14:45:00+00", "Available", None)):   # repaired
        dec = f"'{decom}'" if decom else "NULL"
        db.val(f"""INSERT INTO ottoq_ocpp_chargers (charger_id, depot_id, station_state, decommissioned_at,
                                                    ocpp_identifier, last_fault_code, last_fault_at)
                   VALUES ('{_id(code)}', '{DEPOT}', '{state}', {dec}, 'CP-{code}', 'ConnectorLockFailure', '{fault_at}')""")
        db.val(f"INSERT INTO stalls VALUES ('{_id(code)}', '{DEPOT}', 'dcfc', 'POST-{code}', 'available', NULL, NULL, '{_id(code)}')")
    # a charger with no stall is named by its identifier; one faulted on an earlier day gives no minutes
    db.val(f"""INSERT INTO ottoq_ocpp_chargers (charger_id, depot_id, station_state, decommissioned_at, ocpp_identifier,
                                                last_fault_code, last_fault_at)
               VALUES ('{_id("Z1")}', '{DEPOT}', 'Faulted', NULL, 'CP-Z1', 'Old', '2026-10-12 09:00:00+00')""")
    f = _brief(db)["subjects"]["chargers_faulted"]
    assert (f["count"], f["new"]) == (3, 1)
    assert [c["post"] for c in f["chargers"]] == ["POST-N1", "POST-O1", "CP-Z1"]
    n1, o1, z1 = f["chargers"]
    assert (n1["new"], n1["min_ago"], n1["fault"], n1["charger"]) == (True, 15, "ConnectorLockFailure", "CP-N1")
    assert (o1["new"], o1["min_ago"]) == (False, 120)
    assert z1["new"] is False and "min_ago" not in z1


def test_an_emergency_the_contract_wait_a_scout_finding_and_a_dr_call(db):
    _ready(db)
    _answered(db)
    # emergencies: C in tow_requested for 9 minutes; a car at the gate is not one
    db.val(f"UPDATE vehicles SET current_state = 'tow_requested', last_state_change = '2026-10-13 14:51:00+00', "
           f"current_soc = 41.4 WHERE id = '{_id('C')}'")
    # the contract wait is 30 minutes (the stub's SLA): A 95 and B 31 are past it, D at 30 is not
    _line(db, ("A", 95), ("D", 30), ("B", 31))
    # scouts: one new stranded car, one found before the last answer, one contract breach (counted by the wait instead)
    for car, scout, sev, seen in (("E", "stranded_open_must_do", "high", "2026-10-13 14:40:00+00"),
                                  ("F", "stranded_open_must_do", "high", "2026-10-13 14:10:00+00"),
                                  ("G", "departed_below_target", "critical", "2026-10-13 14:35:00+00"),
                                  ("H", "contract_wait_breach", "medium", "2026-10-13 14:45:00+00")):
        db.val(f"""INSERT INTO ottoq_vehicle_scout_findings (sim_run_id, depot_id, vehicle_id, scout, severity,
                                                             episode_key, first_seen_sim_clock, first_seen_tick, detail)
                   VALUES ('{RUN}', '{DEPOT}', '{_id(car)}', '{scout}', '{sev}', '{car}-{scout}', '{seen}', 60,
                           '{{"visit_id":"x","open_must_do":["fault_repair"],"note":"n"}}')""")
    db.val(f"""INSERT INTO ottoq_dr_calls (depot_id, sim_run_id, call_status, expires_at, program, reason, required_load_cap_kw)
               VALUES ('{DEPOT}', '{RUN}', 'active', '2026-10-13 15:45:00+00', 'TVA-EDR', 'grid stress', 900),
                      ('{DEPOT}', '{RUN}', 'active', '2026-10-13 14:59:00+00', 'expired', 'over', 100)""")
    s = _brief(db, {"reasons": ["emergency", "contract_wait"], "fingerprint": {}})["subjects"]
    assert s["emergencies"] == [{"car": "Car-C", "owner": "Op", "state": "tow_requested", "soc": 41, "min_in_state": 9}]
    assert s["past_contract_wait"]["count"] == 2
    assert [(c["car"], c["over_min"], c["line_pos"], c["limit_min"]) for c in s["past_contract_wait"]["longest"]] == \
        [("Car-A", 65, 1, 30), ("Car-B", 1, 3, 30)]
    sf = s["scout_findings_new"]
    assert sf["count"] == 2
    assert [(f["scout"], f["car"], f["min_ago"]) for f in sf["findings"]] == \
        [("departed_below_target", "Car-G", 25), ("stranded_open_must_do", "Car-E", 20)]     # the critical one first
    assert sf["findings"][1]["detail"] == {"open_must_do": ["fault_repair"]}                 # ids and notes left out
    assert s["dr_call"] == {"program": "TVA-EDR", "reason": "grid stress", "status": "active",
                            "required_load_cap_kw": 900, "minutes_left": 45}


def test_changed_holds_what_moved_and_you_said_holds_the_last_directives(db):
    _ready(db)
    # an older answer, then the last one; a fallback pass after it does not count as an answer
    _answered(db, fp={"faulted_chargers": 9}, said=("older",), clock="2026-10-13 13:00:00+00", tick=40)
    _answered(db, fp={"faulted_chargers": 1, "emergencies": 0, "line_waiting": 14, "dr_active": False},
              said=("The service bays are the wall: 36 hours queued.", "Car-A has waited 40 minutes."))
    db.val(f"""INSERT INTO ottoq_decisions (sim_run_id, tick_seq, sim_clock, action_context, resolved_action_context,
                                           outcome_status, context_frame, proposed_action, enacted_action)
               VALUES ('{RUN}', 75, '2026-10-13 14:45:00+00', 'task_start', 'orchestrator_agent', 'noop_no_candidate',
                       '{{"wake":{{"fingerprint":{{"faulted_chargers":7}}}}}}', '{{}}',
                       '{{"source":"deterministic_fallback","applied":[{{"type":"directive","text":"not the model"}}]}}')""")
    b = _brief(db, {"reasons": ["charger_fault"],
                    "fingerprint": {"faulted_chargers": 3, "emergencies": 0, "line_waiting": 20, "dr_active": False,
                                    "chargers_free": 2}})
    assert b["changed"] == {"faulted_chargers": {"was": 1, "now": 3}, "line_waiting": {"was": 14, "now": 20}}
    assert b["last_answer"] == {"sim_min_ago": 30.0,
                                "you_said": ["The service bays are the wall: 36 hours queued.",
                                             "Car-A has waited 40 minutes."]}
    assert b["new_means"] == "since your last answer"


def test_an_error_inside_the_brief_comes_back_and_is_never_raised(db):
    _ready(db)
    db.val("ALTER TABLE ocpp_sessions RENAME TO ocpp_sessions_gone")
    b = _brief(db, {"reasons": ["charger_fault"]})
    assert b["v"] == 1 and "ocpp_sessions" in b["error"] and b["reasons"] == ["charger_fault"]
    assert "subjects" not in b


def test_the_brief_writes_nothing_and_no_browser_role_runs_it(db):
    _ready(db)
    _answered(db)
    _line(db, ("A", 95))
    _session(db, "A", "F1", "faulted", "2026-10-13 14:20:00+00", "2026-10-13 14:50:00+00", 62, "fault.connector_cable")
    census = """SELECT COALESCE(sum(n_tup_ins + n_tup_upd + n_tup_del), 0) FROM pg_stat_xact_all_tables
                 WHERE schemaname IN ('public', 'twin', 'ottoq')"""
    out = db.val(f"BEGIN; SELECT public.ottoq_agent_wake_brief('{RUN}', '{{\"reasons\":[\"heartbeat\"]}}'::jsonb) IS NOT NULL; {census}; ROLLBACK;")
    assert out == "0"
    assert db.val(f"SELECT provolatile FROM pg_proc WHERE oid = '{BRIEF}'::regprocedure") == "s"
    for role, may in (("anon", "f"), ("authenticated", "f"), ("service_role", "t")):
        assert db.val(f"SELECT has_function_privilege('{role}', '{BRIEF}', 'EXECUTE')") == may
        assert db.val(f"SELECT has_table_privilege('{role}', 'public.ottoq_agent_wake_brief_coverage', 'SELECT')") == may
    # the read-only transaction test: a STABLE function that wrote would fail here
    assert db.val(f"BEGIN READ ONLY; SELECT (public.ottoq_agent_wake_brief('{RUN}', '{{}}'::jsonb) ? 'error')::text; ROLLBACK;") == "false"


def _evidence(d, chain, brief, actions, consulted=True, answered=True):
    wake = {"reasons": ["charger_fault"], "brief": brief}
    ans = json.dumps({"actions": actions}) if answered else None
    a = f"$j${ans}$j$::jsonb" if ans else "NULL"
    d.val(f"""INSERT INTO ottoq_agent_pass_evidence (chain_id, agent_version, sim_run_id, depot_id, consulted, sim_clock,
                                                     wake, answer, outcome_class)
              VALUES ('{chain}', 'v32', '{RUN}', '{DEPOT}', {str(consulted).lower()}, '{T}',
                      $j${json.dumps(wake)}$j$::jsonb, {a}, 'advisory')""")


def test_the_coverage_view_matches_a_whole_name_and_nothing_longer(db):
    _ready(db)
    brief = {"subjects": {
        "charges_cut_by_fault": {"cars": [{"car": "Tesla-AV-05", "new": True}, {"car": "Zoox-AV-097", "new": True},
                                          {"car": "Waymo-AV-001", "new": False}]},
        "emergencies": [{"car": "Zoox-002"}],
        "chargers_faulted": {"chargers": [{"post": "NASH-DCFC-STALL-02", "new": True},
                                          {"post": "NASH-DCFC-STALL-09", "new": False}]},
        "scout_findings_new": {"findings": [{"car": "Car.X (1)"}]}}}
    actions = [{"type": "directive", "text": "Tesla-AV-055 was cut at 75%; zoox-av-097 is charging again on post 6."},
               {"type": "directive", "text": "Post NASH-DCFC-STALL-02 faulted.", "about": "Car.X (1)"},
               {"type": "directive", "text": "Zoox-AV-002 is not Zoox-0021 either."}]
    _evidence(db, "c1", brief, actions)
    _evidence(db, "c2", brief, actions, answered=False)          # no answer: no row
    _evidence(db, "c3", {"error": "x"}, actions)                 # a failed brief names nothing
    rows = db.json("""SELECT jsonb_object_agg(kind || ':' || name, addressed) FROM ottoq_agent_wake_brief_coverage""")
    assert rows == {"charge_cut:Tesla-AV-05": False,             # Tesla-AV-055 is a different car
                    "charge_cut:Zoox-AV-097": True,              # any letter case
                    "emergency:Zoox-002": False,                 # neither Zoox-AV-002 nor Zoox-0021
                    "charger_fault:NASH-DCFC-STALL-02": True,
                    "scout_finding:Car.X (1)": True}             # named in `about`; punctuation matched literally
    assert db.val("SELECT count(DISTINCT pass_id) FROM ottoq_agent_wake_brief_coverage") == "1"
