"""db/migrations/0834, EXECUTED: an agent's directive is graded against the wake brief it answered.

WHY THIS EXISTS. db/checks/0492 (2) replayed a stored pass through the agent's fallback model: its directive named
every car and post the brief named and paired them wrongly, and 0823's coverage view scored it 4 of 4. 0492 (6)(b):
"Nothing grades whether a directive is right." 0834 adds a pure function that checks four kinds of claim about a
charge a fault cut against the brief, and a view of every stored directive graded. Executed here on a minimal stand-in
(the lineage table, the in-flight stand-in and the evidence table's columns the view reads, as live has them on
2026-11-14):
  - 0492's wrong pairing is contradicted, on the post and on "charging again";
  - a directive that agrees with its brief is consistent, across a sentence that carries its subject;
  - a claim is graded only where its subject is certain: one car a sentence, that car a cut charge;
  - an instruction or a negation is not a claim ("Check charging again on available DCFC." read as one 16 times on the
    stored passes before the pattern was narrowed);
  - a percentage at the cut, a place in the line and the post a car charges on again are each caught when wrong and
    passed when right, and a car cut twice agrees if either entry does;
  - a post or a car the brief does not name is still recognised as one by its shape;
  - it never raises and reads no table; no browser role runs it or reads the view;
  - the view grades each directive of a consulted, answered pass whose brief lists a cut charge, and no other;
  - 0834 applies as declared, refuses a second apply and a database without 0823;
  - 0835 takes by_fallback_model out of the view (a stored answer never carries it) and keeps every row.
It SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess
import uuid

import pytest

import test_agent_charge_order_sql as base  # noqa: E402  (the scratch-server helpers, shared on purpose)

ROOT = base.ROOT
NAME = "0834_an_agents_directive_is_graded_against_the_brief_it_answered"
M0834 = os.path.join(ROOT, "db", "migrations", NAME + ".sql")
NAME35 = "0835_the_grades_view_drops_a_mark_a_stored_answer_never_carries"
M0835 = os.path.join(ROOT, "db", "migrations", NAME35 + ".sql")
L0823 = "0823_the_agent_is_told_why_it_was_woken_and_what_it_said_last"
DEPOT = "11111111-1111-1111-1111-111111111111"
RUN = "a0000000-0000-0000-0000-000000000834"

pytestmark = pytest.mark.skipif(not base._server_up(),
                                reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

STUB = f"""
DO $$ BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'anon') THEN CREATE ROLE anon NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'authenticated') THEN CREATE ROLE authenticated NOLOGIN; END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN CREATE ROLE service_role NOLOGIN BYPASSRLS; END IF;
END $$;
CREATE FUNCTION public.ottoq_certification_in_flight(boolean DEFAULT true) RETURNS integer LANGUAGE sql AS 'SELECT 0';
CREATE TABLE public.ottoq_cert_lineage (name text PRIMARY KEY, forces_recert boolean NOT NULL, note text NOT NULL,
  classified_at timestamptz NOT NULL, forces_dial_restart boolean);
INSERT INTO public.ottoq_cert_lineage VALUES ('{L0823}', false, 'stand-in for the test', now(), false);
CREATE TABLE public.ottoq_agent_pass_evidence (pass_id bigserial PRIMARY KEY, sim_run_id uuid, depot_id uuid,
  recorded_at timestamptz DEFAULT now(), sim_clock timestamptz, agent_version text, source_kind text,
  model_answered text, wake jsonb, answer jsonb, consulted boolean);
"""

# a brief as 0823 writes one: three cut charges (one charging again), a faulted post, a car past its contract wait
BRIEF = {"v": 1, "subjects": {
    "charges_cut_by_fault": {"count": 3, "cars": [
        {"car": "Tesla-AV-055", "post": "NASH-DCFC-STALL-28", "cut_at_soc": 74, "soc_now": 74, "target": 100,
         "waiting_in_line_pos": 1, "state": "staged_awaiting_service"},
        {"car": "Waymo-AV-004", "post": "NASH-DCFC-STALL-11", "cut_at_soc": 99, "soc_now": 48, "target": 100,
         "waiting_in_line_pos": 9, "state": "arrived_at_gate"},
        {"car": "Zoox-AV-093", "post": "NASH-DCFC-STALL-03", "cut_at_soc": 52, "target": 100,
         "charging_again_on": "NASH-DCFC-STALL-04", "again_after_min": 1}]},
    "chargers_faulted": {"count": 1, "chargers": [{"post": "NASH-DCFC-STALL-28", "charger": "NASH-DCFC-28"}]},
    "past_contract_wait": {"count": 1, "longest": [{"car": "Waymo-003", "line_pos": 4}]}}}


@pytest.fixture()
def db():
    name = f"ottoq_grade_{os.getpid()}_{uuid.uuid4().hex[:6]}"
    admin = ["psql", *base._conn_args(), "-d", "postgres", "-q", "-v", "ON_ERROR_STOP=1"]
    subprocess.run(admin + ["-c", f"CREATE DATABASE {name}"], check=True, capture_output=True)
    d = base.Db(name)
    try:
        rc, _, err = d.run(STUB)
        assert rc == 0, f"stub did not load: {err}"
        yield d
    finally:
        subprocess.run(["psql", *base._conn_args(), "-d", "postgres", "-q", "-c",
                        f"DROP DATABASE IF EXISTS {name} WITH (FORCE)"], capture_output=True)


def _q(s):
    return "'" + s.replace("'", "''") + "'"


def _apply(d):
    rc, err = d.file(M0834)
    assert rc == 0, err
    return err


def _grade(d, text, brief=BRIEF):
    return d.json(f"SELECT public.ottoq_agent_directive_grade({_q(json.dumps(brief))}::jsonb, {_q(text)})")


def _kinds(g):
    return sorted(c["kind"] for c in g["contradictions"])


def test_the_wrong_pairing_of_check_0492_is_contradicted(db):
    _apply(db)
    g = _grade(db, "NASH-DCFC-STALL-28's fault cut Waymo-AV-004 at 99% and the car is charging again.")
    assert g["verdict"] == "contradicted"
    assert _kinds(g) == ["again", "cut_post"]            # the percentage, 99, is the brief's own: not a contradiction
    post = next(c for c in g["contradictions"] if c["kind"] == "cut_post")
    assert post["car"] == "waymo-av-004" and post["said"] == ["nash-dcfc-stall-28"] and post["brief"] == ["NASH-DCFC-STALL-11"]


def test_a_directive_that_agrees_with_its_brief_is_consistent(db):
    _apply(db)
    g = _grade(db, "Zoox-AV-093 charge cut by fault at 52% on NASH-DCFC-STALL-03 (thermal_emergency, 6 min ago). "
                   "Resumed charging on NASH-DCFC-STALL-04 after 1 min. Full target 100% still required.")
    assert g["verdict"] == "consistent" and g["claims"] == 4 and g["contradictions"] == []
    # the second sentence names no car and is graded as the first one's: a wrong post there is caught
    g = _grade(db, "Zoox-AV-093 charge cut by fault at 52% on NASH-DCFC-STALL-03. Resumed charging on NASH-DCFC-STALL-09.")
    assert _kinds(g) == ["again_post"]
    # in one sentence too, the post after "resumed charging on" is where the car charges again, not where it was cut
    assert _kinds(_grade(db, "Zoox-AV-093 was cut at 52% and resumed charging on NASH-DCFC-STALL-09.")) == ["again_post"]
    assert _grade(db, "Zoox-AV-093 was cut at 52% and resumed charging on NASH-DCFC-STALL-04.")["verdict"] == "consistent"
    g = _grade(db, "Tesla-AV-055 charge cut by fault at NASH-DCFC-STALL-28 at 74% (target 100%). Car now staged, "
                   "waiting in line at position 1. Must complete charge to 100% on next available DCFC.")
    assert g["verdict"] == "consistent" and g["claims"] == 3


def test_a_claim_is_graded_only_where_its_subject_is_certain(db):
    _apply(db)
    # three cars in one sentence: whose "cut at 10%" is it? not graded
    g = _grade(db, "3 findings: Tesla-AV-055 (pos 2, 31 min), Waymo-AV-004 (pos 4), Zoox-AV-093 cut at 10%.")
    assert g["verdict"] == "no_claim" and g["claims"] == 0
    # one car, but not one whose charge was cut: not graded, and the next sentence does not inherit a subject
    g = _grade(db, "Waymo-003 was cut at 10% on NASH-DCFC-STALL-28. It is charging again.")
    assert g["verdict"] == "no_claim"
    # a car the brief does not name at all is still a car by its shape, so the sentence has two cars
    g = _grade(db, "Tesla-AV-055 was cut at 10% after Tesla-AV-999 left.")
    assert g["verdict"] == "no_claim"
    # a subject is not carried past a sentence that names another car
    g = _grade(db, "Tesla-AV-055 charge cut at 74%. Waymo-003 waits. It was cut at 10%.")
    assert g["verdict"] == "consistent" and g["claims"] == 1
    # a brief with no cut charge grades nothing
    assert _grade(db, "Tesla-AV-055 cut at 10%.", {"subjects": {"past_contract_wait": {"longest": [{"car": "Tesla-AV-055"}]}}})["verdict"] == "no_claim"


def test_an_instruction_or_a_negation_is_not_a_claim(db):
    _apply(db)
    for text in ("Tesla-AV-055 charge cut at 74% (target 100%), now waiting in line pos 1. Check charging again on available DCFC.",
                 "Tesla-AV-055 has not resumed charging.",
                 "Tesla-AV-055 must be charging again on NASH-DCFC-STALL-02 within 6 min.",
                 "Tesla-AV-055: confirm it resumed charging once a post is free.",
                 "Confirm Tesla-AV-055 is charging again."):
        g = _grade(db, text)
        assert "again" not in _kinds(g) and "again_post" not in _kinds(g), text
    # the statement itself is a claim, and it is wrong for a car the brief has waiting
    assert _kinds(_grade(db, "Tesla-AV-055 is charging again.")) == ["again"]
    assert _kinds(_grade(db, "Tesla-AV-055 resumed charging on NASH-DCFC-STALL-28.")) == ["again"]
    # and right for the one the brief has charging again
    assert _grade(db, "Zoox-AV-093 is now charging again.")["verdict"] == "consistent"


def test_the_percentage_the_place_and_the_post_are_each_caught_when_wrong(db):
    _apply(db)
    g = _grade(db, "Waymo-AV-004: charge cut by fault at NASH-DCFC-STALL-11 151 min ago at SoC 48%. Car waiting in line at pos 37.")
    assert _kinds(g) == ["cut_soc", "line_pos"]          # 48 is the car's charge now; it was cut at 99
    soc = next(c for c in g["contradictions"] if c["kind"] == "cut_soc")
    assert soc["said"] == 48 and soc["brief"] == [99]
    assert _grade(db, "Waymo-AV-004 charge cut at 98%, waiting in line pos 9.")["verdict"] == "consistent"   # one point
    assert _kinds(_grade(db, "Waymo-AV-004 charge cut at 97%.")) == ["cut_soc"]
    assert _kinds(_grade(db, "Waymo-AV-004 waiting in line pos 3.")) == ["line_pos"]          # a place ahead of its own
    # the first percentage after "cut" is the claim; a target later in the sentence is not
    assert _grade(db, "Tesla-AV-055 charge cut at 74%, target 100%.")["verdict"] == "consistent"
    # a post the brief names nowhere is a post by its shape, and is not where the charge was cut
    g = _grade(db, "Tesla-AV-055 charge cut on NASH-DCFC-STALL-19 at 74%.")
    assert _kinds(g) == ["cut_post"] and g["contradictions"][0]["said"] == ["nash-dcfc-stall-19"]
    # a place for a car the brief has charging again (no place in the line) is not graded
    assert _grade(db, "Zoox-AV-093 waits at pos 5.")["verdict"] == "no_claim"
    # "post" and "position" are not confused with a percentage
    assert _grade(db, "Tesla-AV-055 waiting at position 1 with 74% charge.")["verdict"] == "consistent"


def test_a_car_cut_twice_agrees_if_either_entry_does(db):
    _apply(db)
    twice = {"subjects": {"charges_cut_by_fault": {"cars": [
        {"car": "Zoox-AV-085", "post": "NASH-DCFC-STALL-12", "cut_at_soc": 99, "waiting_in_line_pos": 34, "state": "arrived_at_gate"},
        {"car": "Zoox-AV-085", "post": "NASH-DCFC-STALL-07", "cut_at_soc": 61, "waiting_in_line_pos": 34, "state": "arrived_at_gate"}]}}}
    assert _grade(db, "Zoox-AV-085 charge cut by fault at NASH-DCFC-STALL-12 at 99%, position 34.", twice)["verdict"] == "consistent"
    assert _grade(db, "Zoox-AV-085 charge cut by fault at NASH-DCFC-STALL-07 at 61%.", twice)["verdict"] == "consistent"
    assert _kinds(_grade(db, "Zoox-AV-085 charge cut by fault at NASH-DCFC-STALL-08 at 70%.", twice)) == ["cut_post", "cut_soc"]


def test_names_match_whole_and_in_any_letter_case(db):
    _apply(db)
    # TESLA-AV-0550 is not Tesla-AV-055: a different car by shape, so it is no cut charge and nothing is graded
    assert _grade(db, "TESLA-AV-0550 charge cut at 10%.")["verdict"] == "no_claim"
    assert _grade(db, "Tesla-AV-055b charge cut at 10%.")["verdict"] == "no_claim"            # nor is a longer name
    assert _grade(db, "Tesla-AV-055-B charge cut at 10%.")["verdict"] == "no_claim"
    assert _kinds(_grade(db, "tesla-av-055 CHARGE CUT AT 10%.")) == ["cut_soc"]
    assert _kinds(_grade(db, "Tesla-AV-055's charge was cut at 10%.")) == ["cut_soc"]


def test_it_never_raises_and_a_missing_argument_is_no_claim(db):
    _apply(db)
    for call in ("NULL, 'x'", "'{}'::jsonb, 'x'", "'[]'::jsonb, 'x'", "'\"s\"'::jsonb, 'x'",
                 f"{_q(json.dumps(BRIEF))}::jsonb, NULL", f"{_q(json.dumps(BRIEF))}::jsonb, '   '",
                 "'{\"subjects\":{\"charges_cut_by_fault\":{\"cars\":\"none\"}}}'::jsonb, 'x'",
                 "'{\"subjects\":{\"charges_cut_by_fault\":{\"cars\":[{\"car\":null},{\"car\":7},{}]}}}'::jsonb, 'x cut at 5%'"):
        g = db.json(f"SELECT public.ottoq_agent_directive_grade({call})")
        assert g["verdict"] == "no_claim" and g["claims"] == 0, call
    # a name full of regular-expression characters is escaped, not run
    odd = {"subjects": {"charges_cut_by_fault": {"cars": [{"car": "A(b.*[+?-1", "post": "P|^$-2", "cut_at_soc": 50}]}}}
    g = _grade(db, "A(b.*[+?-1 charge cut on P|^$-2 at 50%.", odd)
    assert g["verdict"] == "consistent" and g["claims"] == 2
    g = _grade(db, "A(b.*[+?-1 charge cut on P|^$-3 at 50%.", odd)
    assert _kinds(g) == ["cut_post"]


def test_it_is_pure_and_no_browser_role_runs_it_or_reads_the_view(db):
    _apply(db)
    assert db.val("SELECT provolatile::text || prosecdef::text FROM pg_proc "
                  "WHERE oid = 'public.ottoq_agent_directive_grade(jsonb,text)'::regprocedure") == "ifalse"
    for role in ("anon", "authenticated"):
        assert db.val(f"SELECT has_function_privilege('{role}', 'public.ottoq_agent_directive_grade(jsonb,text)', 'EXECUTE')") == "f"
        assert db.val(f"SELECT has_table_privilege('{role}', 'public.ottoq_agent_directive_grades', 'SELECT')") == "f"
    assert db.val("SELECT has_function_privilege('service_role', 'public.ottoq_agent_directive_grade(jsonb,text)', 'EXECUTE')") == "t"
    assert db.val("SELECT has_table_privilege('service_role', 'public.ottoq_agent_directive_grades', 'SELECT')") == "t"
    # the same arguments, the same answer, with every table gone from under it
    a = _grade(db, "Tesla-AV-055 charge cut at 10%.")
    db.val("DROP VIEW public.ottoq_agent_directive_grades; DROP TABLE public.ottoq_agent_pass_evidence")
    assert _grade(db, "Tesla-AV-055 charge cut at 10%.") == a


def _pass(d, model, actions, brief=BRIEF, consulted=True, answered=True):
    wake = json.dumps({"brief": brief} if brief is not None else {})
    answer = _q(json.dumps({"actions": actions})) + "::jsonb" if answered else "NULL"
    return d.val(f"""INSERT INTO ottoq_agent_pass_evidence (sim_run_id, depot_id, sim_clock, agent_version, source_kind,
                                                            model_answered, wake, answer, consulted)
                     VALUES ('{RUN}', '{DEPOT}', '2026-11-13 16:00:00+00', 'v33', 'live', '{model}',
                             {_q(wake)}::jsonb, {answer}, {str(consulted).lower()}) RETURNING pass_id""")


def test_the_view_grades_each_directive_of_a_pass_that_answered_a_cut_charge(db):
    _apply(db)
    good = _pass(db, "primary", [
        {"type": "directive", "text": "Tesla-AV-055 charge cut at 74% on NASH-DCFC-STALL-28, waiting in line pos 1."},
        {"type": "directive", "text": "34 cars past the 30-minute contract wait."}])
    bad = _pass(db, "fallback", [
        {"type": "directive", "by_fallback_model": "fallback",
         "text": "NASH-DCFC-STALL-28's fault cut Waymo-AV-004 at 99% and the car is charging again."},
        {"type": "directive", "text": ""}, {"type": "directive"}])
    _pass(db, "primary", [{"type": "directive", "text": "Tesla-AV-055 charge cut at 10%."}], consulted=False)
    _pass(db, "primary", [], answered=False)
    _pass(db, "primary", [{"type": "directive", "text": "Tesla-AV-055 charge cut at 10%."}], brief=None)
    _pass(db, "primary", [{"type": "directive", "text": "Tesla-AV-055 charge cut at 10%."}],
          brief={"subjects": {"charges_cut_by_fault": {"cars": []}}})
    rows = db.json("SELECT jsonb_agg(to_jsonb(g) ORDER BY g.pass_id, g.directive_no) FROM public.ottoq_agent_directive_grades g")
    assert [(r["pass_id"], r["directive_no"], r["verdict"], r["claims"]) for r in rows] == [
        (int(good), 1, "consistent", 3), (int(good), 2, "no_claim", 0), (int(bad), 1, "contradicted", 3)]
    assert rows[2]["model_answered"] == "fallback"
    assert sorted(c["kind"] for c in rows[2]["contradictions"]) == ["again", "cut_post"]
    # an answer whose actions is not a list is no row, not an error
    db.val(f"""INSERT INTO ottoq_agent_pass_evidence (sim_run_id, depot_id, wake, answer, consulted)
               VALUES ('{RUN}', '{DEPOT}', {_q(json.dumps({"brief": BRIEF}))}::jsonb, '{{"actions":"none"}}'::jsonb, true)""")
    assert db.val("SELECT count(*) FROM public.ottoq_agent_directive_grades") == "3"


def test_0834_applies_as_declared_and_refuses_a_second_apply(db):
    _pass(db, "fallback", [{"type": "directive", "text": "Tesla-AV-055 charge cut at 10%."}])
    err = _apply(db)
    assert "0834 V4 PASSED: 1 directives graded, 1 contradicted, 0 errors" in err
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{NAME}'") == "falsefalse"
    rc, err = db.file(M0834)
    assert rc != 0 and "0834 P2: already applied" in err


def test_0835_takes_the_mark_a_stored_answer_never_carries_out_of_the_view_and_keeps_every_row(db):
    """The edge function writes by_fallback_model on the directive it applies, not into the answer it stores, so
    0834's column was NULL on every row. 0835 re-creates the view without it; model_answered is the truth."""
    _apply(db)
    p = _pass(db, "fallback", [{"type": "directive", "text": "Tesla-AV-055 charge cut at 10%."},
                               {"type": "directive", "text": "Tesla-AV-055 charge cut at 74%."}])
    before = db.json("SELECT jsonb_agg(to_jsonb(g) - 'by_fallback_model' ORDER BY g.pass_id, g.directive_no) "
                     "FROM public.ottoq_agent_directive_grades g")
    assert "by_fallback_model" in db.json("SELECT to_jsonb(g) FROM public.ottoq_agent_directive_grades g LIMIT 1")
    rc, err = db.file(M0835)
    assert rc == 0, err
    assert "0835 V1 PASSED: 2 directives, 1 contradicted, before and after" in err
    after = db.json("SELECT jsonb_agg(to_jsonb(g) ORDER BY g.pass_id, g.directive_no) FROM public.ottoq_agent_directive_grades g")
    assert after == before and [r["verdict"] for r in after] == ["contradicted", "consistent"]
    assert after[0]["pass_id"] == int(p) and after[0]["model_answered"] == "fallback"
    for role in ("anon", "authenticated"):
        assert db.val(f"SELECT has_table_privilege('{role}', 'public.ottoq_agent_directive_grades', 'SELECT')") == "f"
    assert db.val("SELECT has_table_privilege('service_role', 'public.ottoq_agent_directive_grades', 'SELECT')") == "t"
    assert db.val(f"SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage WHERE name = '{NAME35}'") == "falsefalse"
    rc, err = db.file(M0835)
    assert rc != 0 and "0835 P1: already applied" in err


def test_0835_refuses_a_database_without_0834(db):
    rc, err = db.file(M0835)
    assert rc != 0 and "0835 P1: 0834 is not classified" in err


def test_0834_refuses_a_database_without_0823_or_without_a_column_the_view_reads(db):
    db.val("ALTER TABLE ottoq_agent_pass_evidence DROP COLUMN model_answered")
    rc, err = db.file(M0834)
    assert rc != 0 and "0834 P1: public.ottoq_agent_pass_evidence lacks: model_answered" in err
    db.val(f"DELETE FROM ottoq_cert_lineage WHERE name = '{L0823}'")
    rc, err = db.file(M0834)
    assert rc != 0 and "0834 P1: 0823 is not classified" in err
    assert db.val("SELECT to_regprocedure('public.ottoq_agent_directive_grade(jsonb,text)') IS NULL") == "t"
