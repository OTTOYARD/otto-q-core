"""db/migrations/0607 and 0608, EXECUTED on the stub engine: any agent is welcomed, and the demo passcode opens the fleet
until the run ends; the crew and the twin see what every owner's agent set, with its confirmation code.

WHY THIS EXISTS. 0607 lets a caller with no key into the agent door (welcome, enter_passcode), turns a passcode into a
session that can change what a fleet's cars need, ends those sessions when a demo run ends, and puts a confirmation
code on every accepted change. Each of those is a security or a demo promise, and none is visible to a compile check:

  * the welcome says what the passcode opens, and nothing about keys; the door is OFF until a passcode is set;
  * the passcode is a bcrypt hash; wrong passcodes are refused in plain English and throttled per caller from the
    ledger; the right one opens a session that is exactly an owner key with an expiry (capabilities pinned by CHECK);
  * a session's accepted change carries "Confirmation code: OQ-XXXX-XXXX." above its OrchestrAV link, the same code
    in my_commands, in a replay, in OrchestrAV's board and in the crew's board; a refused one carries none;
  * a demo run's end revokes every passcode session at the depot (pause does not; a non-demo run does not); an ended or
    expired session is told so in plain English; an issued key is unaffected;
  * the crew's board (0608) shows every owner's settings with codes and agents, and never a key or a principal id.

Loads tests/fixtures/agent_gateway_stub_engine.sql and tests/fixtures/owner_agent_stub_engine.sql, then 0559, 0560,
0605, 0606, 0607 and 0608. SKIPS where no scratch PostgreSQL is reachable, like the 0559 and 0605 suites.
"""
import hashlib
import json
import os
import re

import pytest

from test_owner_agent_sql import (  # noqa: F401  (pytestmark: skip without a scratch server)
    AV001, AV041, AV045, M0559, M0560, M0605, M0606, ROOT, RT003, STUB_0559, STUB_0605, TESLA, TWIN, WAYMO, SEED,
    _drop, _new_db, fresh_run, pytestmark, q,
)

M0607 = os.path.join(ROOT, "db", "migrations", "0607_any_agent_is_welcomed_and_the_demo_passcode_opens_the_fleet_until_the_run_ends.sql")
M0608 = os.path.join(ROOT, "db", "migrations", "0608_the_crew_and_the_twin_see_what_every_owners_agent_set_with_its_confirmation_code.sql")
PASSCODE = "harbor-quartz-42"
CODE_RE = re.compile(r"^OQ-[0-9A-F]{4}-[0-9A-F]{4}$")


def h(token):
    return hashlib.sha256(token.encode()).hexdigest()


def pcall(db, token_hash, tool, args=None, transport="mcp", ip="203.0.113.7"):
    """ottoq_agent_call with meta the way the gateway sends it (the caller's IP is what the throttle counts)."""
    th = "NULL" if token_hash is None else f"'{token_hash}'"
    meta = json.dumps({"ip": ip, "http_method": "POST", "path": "/mcp"})
    return db.json(f"SELECT ottoq_agent_call({th}, '{tool}', {q(json.dumps(args or {}))}::jsonb, '{transport}', {q(meta)}::jsonb)")


def unlock(db, agent="Grok", ip="203.0.113.7", passcode=PASSCODE):
    r = pcall(db, None, "enter_passcode", {"passcode": passcode, "agent": agent}, ip=ip)
    assert r["http_status"] == 201, r
    return r


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.run(SEED)
        yield d
    finally:
        _drop(d)


@pytest.fixture(scope="module")
def door(db):
    """The passcode set, once, for the tests that need the door on."""
    r = db.json(f"SELECT ottoq_agent_set_passcode({q(PASSCODE)})")
    assert r["ok"] and r["enabled"], r
    return r


# ─────────────────────────────────────────────────────────────────────────────────────── the premises ──

def test_0607_needs_0605_and_0606_and_0608_needs_0607():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605):
            assert d.file(path)[0] == 0
        rc, err = d.file(M0607)
        assert rc != 0 and "0607 P1: 0605 and 0606" in err, err
        assert d.file(M0606)[0] == 0
        rc, err = d.file(M0608)
        assert rc != 0 and "0608 P1: 0607" in err, err
        assert d.file(M0607)[0] == 0 and d.file(M0608)[0] == 0
    finally:
        _drop(d)


def test_both_refuse_a_second_apply(db):
    rc, err = db.file(M0607)
    assert rc != 0 and "0607 P1: already applied" in err, err
    rc, err = db.file(M0608)
    assert rc != 0 and "0608 P1: already applied" in err, err


def test_0607_refuses_a_dispatcher_it_did_not_measure():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606):
            assert d.file(path)[0] == 0
        d.run("""CREATE OR REPLACE FUNCTION public.ottoq_agent_resolve(p_token_hash text) RETURNS public.ottoq_agent_principals
                 LANGUAGE sql STABLE AS $$ SELECT NULL::public.ottoq_agent_principals $$""")
        rc, err = d.file(M0607)
        assert rc != 0 and "0607 P1: not the body this file was written against" in err and "ottoq_agent_resolve" in err, err
    finally:
        _drop(d)


def test_classified_for_no_recert_round(db):
    assert db.rows("SELECT forces_recert, forces_dial_restart FROM ottoq_cert_lineage "
                   "WHERE name LIKE '0607%' OR name LIKE '0608%' ORDER BY name") == [["f", "f"], ["f", "f"]]


def test_the_probe_left_nothing_behind_and_the_door_ships_off():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607):
            assert d.file(path)[0] == 0
        assert d.val("SELECT count(*) FROM ottoq_agent_principals") == "0"
        assert d.val("SELECT count(*) FROM ottoq_agent_call_ledger") == "0"
        assert d.rows("SELECT enabled, passcode_hash IS NULL, session_minutes, fleet_operator_id FROM ottoq_agent_demo_passcode") \
            == [["f", "t", "240", TESLA]]
    finally:
        _drop(d)


def test_the_session_trigger_fires_only_on_a_demo_runs_end(db):
    d = db.val("SELECT pg_get_triggerdef(oid) FROM pg_trigger WHERE tgname = 'ottoq_sim_runs_end_passcode_sessions'")
    assert "AFTER UPDATE OF status ON public.ottoq_sim_runs" in d and "(new.run_by = 'operator_demo'::text)" in d


# ─────────────────────────────────────────────────────────────────────────────── the welcome and the door ──

def test_the_welcome_without_a_key_names_no_key_and_says_the_door_is_off():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607):
            assert d.file(path)[0] == 0
        d.run(SEED)
        r = pcall(d, None, "welcome")
        assert r["ok"] and r["http_status"] == 200 and r["data"]["connected"] is False
        assert r["data"]["passcode"] == "off" and "fleet" not in r["data"] and "next" not in r["data"]
        assert r["data"]["summary"].startswith("Welcome to OTTOYARD. You have reached OTTO-Q")
        assert "not switched on right now" in r["data"]["summary"]
        assert not re.search(r"oq[as]_", json.dumps(r))
        off = pcall(d, None, "enter_passcode", {"passcode": PASSCODE, "agent": "Grok"})
        assert off["http_status"] == 503 and off["error"]["code"] == "passcode_off"
        assert off["error"]["message"].startswith("OTTOYARD's demo passcode is not switched on right now")
    finally:
        _drop(d)


def test_setting_the_passcode_stores_a_bcrypt_hash_and_never_returns_it(db, door):
    assert PASSCODE not in json.dumps(door)
    stored = db.val("SELECT passcode_hash FROM ottoq_agent_demo_passcode")
    assert stored.startswith("$2") and PASSCODE not in stored
    assert "opens Tesla Robotaxi TN's cars at the twin depot for 240 minutes" in door["message"]
    short = db.json("SELECT ottoq_agent_set_passcode('abc')")
    assert short["ok"] is False and short["error"] == "invalid_passcode"
    assert db.val("SELECT passcode_hash FROM ottoq_agent_demo_passcode") == stored


def test_the_welcome_says_what_the_passcode_opens_and_the_next_call(db, door):
    r = pcall(db, None, "welcome")
    data = r["data"]
    assert data["passcode"] == "required" and data["connected"] is False
    assert data["fleet"]["name"] == "Tesla Robotaxi TN" and data["fleet"]["cars"] == 4
    assert data["fleet"]["models"] == "3 Model Y and 1 Cybercab"
    assert "With OTTOYARD's demo passcode you can see and adjust Tesla Robotaxi TN's 4 cars here (3 Model Y and 1 Cybercab)" in data["summary"]
    assert data["next"]["tool"] == "enter_passcode" and set(data["next"]["arguments"]) == {"passcode", "agent"}
    assert any("set_charge_limit" in x for x in data["you_can"])
    assert "refused in plain English" in data["rules"] and "confirmation code" in data["rules"]
    led = db.rows("SELECT principal_id IS NULL, tool, ok, http_status FROM ottoq_agent_call_ledger ORDER BY call_id DESC LIMIT 1")
    assert led == [["t", "welcome", "t", "200"]]


def test_a_wrong_passcode_is_refused_in_plain_english_and_throttled_per_caller(db, door):
    ip = "198.51.100.23"
    first = pcall(db, None, "enter_passcode", {"passcode": "not-it", "agent": "Guesser"}, ip=ip)
    assert first["http_status"] == 403 and first["error"]["code"] == "wrong_passcode"
    assert first["error"]["message"].startswith("That passcode is not right, so nothing was opened. 4 more tries in the next 15 minutes.")
    for n in range(4):
        r = pcall(db, None, "enter_passcode", {"passcode": f"nope-{n}"}, ip=ip)
        assert r["error"]["code"] == "wrong_passcode", r
    assert "That was the last try for 15 minutes." in r["error"]["message"]
    # the sixth try is refused before the passcode is even checked -- the right one too
    blocked = pcall(db, None, "enter_passcode", {"passcode": PASSCODE, "agent": "Guesser"}, ip=ip)
    assert blocked["http_status"] == 429 and blocked["error"]["code"] == "too_many_attempts"
    assert re.match(r"^Too many wrong passcodes from here\. Nothing was opened; try again in 1[45] minutes\.$", blocked["error"]["message"])
    assert 840 <= blocked["error"]["retry_after_s"] <= 900
    # another caller is not held back by this one
    assert pcall(db, None, "enter_passcode", {"passcode": PASSCODE, "agent": "Elsewhere"}, ip="192.0.2.99")["http_status"] == 201
    # fifteen minutes on (the ledger moved back, with the override 0559 provides), the caller may try again
    db.run(f"""SET ottoq.agent_ledger_unlock = 'on';
               UPDATE ottoq_agent_call_ledger SET called_at = called_at - interval '16 minutes'
                WHERE tool = 'enter_passcode' AND detail ->> 'ip' = '{ip}'""")
    assert pcall(db, None, "enter_passcode", {"passcode": PASSCODE, "agent": "Guesser"}, ip=ip)["http_status"] == 201


def test_enter_passcode_takes_only_a_passcode_and_a_name(db, door):
    for bad in ({}, {"passcode": ""}, {"passcode": 42}, {"passcode": PASSCODE, "agent": "x" * 81},
                {"passcode": PASSCODE, "fleet": TESLA}):
        r = pcall(db, None, "enter_passcode", bad)
        assert r["http_status"] == 400 and r["error"]["code"] == "invalid_arguments", (bad, r)
        assert "enter_passcode takes" in r["error"]["message"]


def test_the_right_passcode_opens_exactly_an_owner_key_with_an_expiry(db, door):
    r = unlock(db, agent="Chase's\tHermes\nv2")
    data = r["data"]
    key = data["session"]
    assert re.match(r"^oqs_[0-9a-f]{64}$", key)
    assert data["summary"].startswith("Welcome, Chase's Hermes v2. The passcode is right: you have Tesla Robotaxi TN's 4 cars at OTTOYARD Nashville Flagship until ")
    assert "or until the demo run ends, whichever comes first." in data["summary"]
    assert "Try: \"how are my cars doing?\"" in data["summary"]
    assert key not in data["summary"] and "do not show it" in data["session_use"]
    assert r["principal"]["capabilities"] == ["note", "owner_settings", "read"]
    row = db.rows(f"""SELECT origin, display_name, kind, fleet_operator_id, depot_id, capabilities::text, rate_limit_per_min,
                             token_prefix = left({q(key)}, 12), name ~ '^chase-s-hermes-v2\\.[0-9a-f]{{6}}$',
                             expires_at BETWEEN now() + interval '239 minutes' AND now() + interval '241 minutes'
                        FROM ottoq_agent_principals WHERE token_hash = '{h(key)}'""")
    assert row == [["passcode", "Chase's Hermes v2", "personal", TESLA, TWIN, "{note,owner_settings,read}", "30", "t", "t", "t"]]
    # the key itself is never stored
    assert db.val(f"SELECT count(*) FROM ottoq_agent_principals WHERE token_hash = {q(key)} OR name LIKE '%' || {q(key[4:20])} || '%'") == "0"
    led = db.rows(f"""SELECT tool, ok, http_status, detail ->> 'agent' FROM ottoq_agent_call_ledger l
                       JOIN ottoq_agent_principals a ON a.principal_id = l.principal_id WHERE a.token_hash = '{h(key)}'""")
    assert led == [["enter_passcode", "t", "201", "Chase's Hermes v2"]]


def test_an_agent_with_no_name_is_called_agent(db, door):
    r = pcall(db, None, "enter_passcode", {"passcode": PASSCODE})
    assert r["http_status"] == 201 and r["data"]["summary"].startswith("Welcome, Agent. ")
    assert re.match(r"^agent\.[0-9a-f]{6}$", r["principal"]["name"])


def test_a_session_cannot_be_widened_or_edited(db, door):
    key = unlock(db, agent="Widener")["data"]["session"]
    rc, _, err = db.run(f"""INSERT INTO ottoq_agent_principals (name, kind, fleet_operator_id, capabilities, token_hash, token_prefix,
                                origin, display_name, expires_at)
                            VALUES ('wide.000000', 'personal', '{TESLA}', ARRAY['note','owner_settings','read','request_ops_action'],
                                    repeat('a', 64), 'oqs_aaaaaaaa', 'passcode', 'Wide', now() + interval '1 hour')""", check=False)
    assert rc != 0 and "check constraint" in err
    rc, _, err = db.run(f"""INSERT INTO ottoq_agent_principals (name, kind, fleet_operator_id, capabilities, token_hash, token_prefix, origin)
                            VALUES ('forever.000000', 'personal', '{TESLA}', ARRAY['note','owner_settings','read'],
                                    repeat('b', 64), 'oqs_bbbbbbbb', 'passcode')""", check=False)
    assert rc != 0 and "check constraint" in err
    rc, _, err = db.run(f"UPDATE ottoq_agent_principals SET expires_at = expires_at + interval '1 day' WHERE token_hash = '{h(key)}'", check=False)
    assert rc != 0 and "scope is fixed at issue" in err


# ─────────────────────────────────────────────────────────────────────── a session at work, and its codes ──

def test_a_session_reads_and_is_welcomed_by_name(db, door):
    key = unlock(db, agent="Grok")["data"]["session"]
    who = pcall(db, h(key), "whoami")
    assert who["ok"] and who["data"]["principal"]["via"] == "passcode" and who["data"]["principal"]["display_name"] == "Grok"
    assert "or when the demo run ends" in who["data"]["principal"]["ends"]
    hello = pcall(db, h(key), "welcome")
    assert hello["ok"] and hello["data"]["connected"] is True and hello["data"]["agent"] == {"name": "Grok", "via": "passcode"}
    assert hello["data"]["summary"].startswith("You are connected to OTTOYARD as Grok, for Tesla Robotaxi TN's 4 cars at OTTOYARD Nashville Flagship, until ")
    fleet = pcall(db, h(key), "my_fleet")
    assert fleet["ok"] and fleet["principal"]["kind"] == "personal"


def test_an_accepted_change_carries_its_confirmation_code_everywhere(db, door):
    run = fresh_run(db)
    key = unlock(db, agent="Grok")["data"]["session"]
    r = pcall(db, h(key), "set_charge_limit", {"vehicles": "all", "percent": 90, "idempotency_key": "grok-90"})
    assert r["http_status"] == 201 and r["data"]["outcome"] == "applied", r
    code = r["data"]["confirmation_code"]
    cmd = r["data"]["command"]["command_id"]
    assert CODE_RE.match(code) and code == db.val(f"SELECT ottoq_owner_confirmation_code('{cmd}')")
    lines = r["data"]["summary"].split("\n")
    assert lines[0].startswith("Done. All 4 Teslas charge to at most 90% instead of 100%.") or lines[0].startswith("Done.")
    i = lines.index(f"Confirmation code: {code}.")
    assert lines[i + 1].startswith("See it in OrchestrAV: https://") and f"command={cmd}" in lines[i + 1]
    # the same code in my_commands, in a replay of the same key, and in OrchestrAV's board
    mine = pcall(db, h(key), "my_commands", {"command_id": cmd})
    assert mine["data"]["commands"][0]["confirmation_code"] == code
    again = pcall(db, h(key), "set_charge_limit", {"vehicles": "all", "percent": 90, "idempotency_key": "grok-90"})
    assert again["data"]["duplicate"] is True and again["data"]["confirmation_code"] == code
    board = db.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', '{cmd}')", role="anon")
    assert board["highlight"]["confirmation_code"] == code
    assert board["highlight"]["agent"] == "Grok" and board["highlight"]["agent_via"] == "passcode"
    assert board["commands"][0]["confirmation_code"] == code
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")


def test_a_change_that_does_not_fit_is_refused_in_plain_english_with_no_code(db, door):
    fresh_run(db)
    key = unlock(db, agent="Grok")["data"]["session"]
    r = pcall(db, h(key), "set_charge_limit", {"vehicles": "all", "percent": 70})
    assert r["http_status"] == 422 and r["data"]["outcome"] == "refused"
    assert r["data"]["summary"].startswith("Not done: ") and "confirmation_code" not in r["data"]
    assert "Confirmation code" not in r["data"]["summary"] and "80" in r["data"]["summary"]
    tesla98 = pcall(db, h(key), "request_service", {"vehicles": ["Tesla 98"], "service": "mechanical_pm"})
    assert tesla98["data"]["outcome"] == "refused" and tesla98["error"]["message"].startswith('No car in your fleet matches "Tesla 98".')
    preview = pcall(db, h(key), "request_service", {"vehicles": "all", "service": "exterior_wash", "when": "every_return", "mode": "preview"})
    assert preview["data"]["outcome"] == "previewed" and "confirmation_code" not in preview["data"]


# ───────────────────────────────────────────────────────────────────────────── the run's end closes the door ──

def test_a_demo_runs_end_ends_every_passcode_session_and_says_so(db, door):
    run = fresh_run(db)
    s1 = unlock(db, agent="Grok")["data"]["session"]
    s2 = unlock(db, agent="Hermes", ip="192.0.2.10")["data"]["session"]
    issued = db.json(f"SELECT ottoq_agent_issue_token('end-key-{run[:6]}', 'personal', ARRAY['read','note','owner_settings'], '{TESLA}', '{TWIN}', NULL, 600, 20)")
    assert pcall(db, h(s1), "set_charge_limit", {"vehicles": ["RT-003"], "percent": 85})["data"]["outcome"] == "applied"
    # pause is not an end
    db.run(f"UPDATE ottoq_sim_runs SET status = 'paused' WHERE sim_run_id = '{run}'")
    assert pcall(db, h(s1), "whoami")["ok"]
    db.run(f"UPDATE ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{run}'")
    # the twin's Stop (ottoq_sim_mark_stopped writes running -> completed)
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    for s in (s1, s2):
        r = pcall(db, h(s), "my_fleet")
        assert r["http_status"] == 401 and r["error"]["code"] == "session_ended", r
        assert r["error"]["message"].startswith("This OTTOYARD session ended when the demo run ended: a stop or reset of the twin ends every passcode session")
        assert "enter_passcode again" in r["error"]["message"]
    assert db.rows(f"SELECT status, revoked_reason LIKE 'run_ended: demo run {run} ended (completed)%' FROM ottoq_agent_principals "
                   f"WHERE token_hash IN ('{h(s1)}', '{h(s2)}')") == [["revoked", "t"], ["revoked", "t"]]
    # an issued key is not a passcode session
    assert pcall(db, h(issued["token"]), "whoami")["ok"]
    # and the setting the session made was lifted with the run (0605)
    assert db.val(f"SELECT target_soc FROM vehicles WHERE id = '{RT003}'") == "100"


def test_a_session_opened_before_a_run_ends_with_that_run(db, door):
    db.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    early = unlock(db, agent="Early Bird")["data"]["session"]
    hello = pcall(db, h(early), "welcome")
    assert "No demo run is live right now" in hello["data"]["summary"]
    run = fresh_run(db)
    assert pcall(db, h(early), "set_charge_limit", {"vehicles": ["AV-041"], "percent": 95})["data"]["outcome"] == "applied"
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    assert pcall(db, h(early), "whoami")["error"]["code"] == "session_ended"


def test_a_non_demo_runs_end_leaves_sessions_open(db, door):
    fresh_run(db)
    key = unlock(db, agent="Grok")["data"]["session"]
    other = "5e5e5e5e-0000-0000-0000-0000000000ce"
    db.run(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, sim_clock_current, run_by)
               VALUES ('{other}', '{TWIN}', 'running', now(), 'cert_harness')""")
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{other}'")
    assert pcall(db, h(key), "whoami")["ok"]


def test_an_expired_session_is_told_when(db, door):
    key = unlock(db, agent="Sleepy")["data"]["session"]
    db.run(f"""SET ottoq.agent_ledger_unlock = 'on';
               UPDATE ottoq_agent_principals SET expires_at = now() - interval '1 minute' WHERE token_hash = '{h(key)}'""")
    r = pcall(db, h(key), "whoami")
    assert r["http_status"] == 401 and r["error"]["code"] == "session_expired"
    assert re.match(r"^This OTTOYARD session expired at \d{1,2}:\d{2} [AP]M CT\. Call enter_passcode again", r["error"]["message"])


def test_no_key_is_told_how_to_connect_and_an_unknown_one_is_not(db):
    none = pcall(db, None, "my_fleet")
    assert none["http_status"] == 401 and none["error"]["code"] == "unauthenticated"
    assert none["error"]["message"].startswith("Connect first: call welcome, then enter_passcode")
    unknown = pcall(db, "f" * 64, "my_fleet")
    assert unknown["error"]["message"] == "The token is unknown or has been revoked."


def test_an_issued_key_is_welcomed_as_a_key(db):
    tok = db.json(f"SELECT ottoq_agent_issue_token('welcome-key', 'personal', ARRAY['read','note','owner_settings'], '{TESLA}', '{TWIN}', NULL, 600, 20)")
    r = pcall(db, h(tok["token"]), "welcome")
    assert r["ok"] and r["data"]["agent"] == {"name": "welcome-key", "via": "key"}
    assert r["data"]["summary"].startswith("You are connected to OTTOYARD as welcome-key (an agent key), for Tesla Robotaxi TN's 4 cars")
    assert "session_expires_local" not in r["data"]
    # and enter_passcode still opens a separate session for whoever sends the passcode
    assert pcall(db, h(tok["token"]), "enter_passcode", {"passcode": PASSCODE, "agent": "Twice"})["http_status"] in (201, 503)


# ──────────────────────────────────────────────────────────────────────────── the crew's and the twin's read ──

def test_the_depot_board_shows_every_owner_with_codes_and_agents_and_no_keys(db, door):
    run = fresh_run(db)
    key = unlock(db, agent="Grok")["data"]["session"]
    applied = pcall(db, h(key), "request_service", {"vehicles": ["AV-045"], "service": "exterior_wash", "when": "every_return"})
    assert applied["data"]["outcome"] == "applied", applied
    code = applied["data"]["confirmation_code"]
    pcall(db, h(key), "set_charge_limit", {"vehicles": "all", "percent": 70})          # refused: no code
    board = db.json("SELECT ottoq_depot_owner_board()", role="anon")
    assert board["ok"] and board["run"]["sim_run_id"] == run and board["run"]["demo"] is True
    wash = [s for s in board["in_force"] if s["kind"] == "service"]
    assert len(wash) == 1 and wash[0]["vehicle"] == "Tesla-AV-045" and wash[0]["fleet_operator"] == "Tesla Robotaxi TN"
    assert wash[0]["confirmation_code"] == code and wash[0]["agent"] == "Grok" and wash[0]["agent_via"] == "passcode"
    car = board["by_vehicle"][AV045]
    assert car["orders"] == [{"service": "exterior_wash", "name": car["orders"][0]["name"], "when": "every_return"}]
    assert car["confirmation_codes"] == [code] and car["agents"] == ["Grok"]
    top = board["commands"][0]
    assert top["outcome"] == "refused" and "confirmation_code" not in top and top["refusal"]
    hit = next(c for c in board["commands"] if c["command_id"] == applied["data"]["command"]["command_id"])
    assert hit["confirmation_code"] == code and hit["head"].startswith("Done.") and hit["vehicles"] == ["Tesla-AV-045"]
    assert any(a["agent"] == "Grok" and a["state"] == "connected" and a["via"] == "passcode" for a in board["agents"])
    assert board["counts"]["orders"] == 1 and board["counts"]["agents_connected"] >= 1
    assert not re.search(r"oq[as]_[0-9a-f]|principal_id|token", json.dumps(board))
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    after = db.json("SELECT ottoq_depot_owner_board()", role="anon")
    assert after["run"] is None and after["in_force"] == [] and after["by_vehicle"] == {}
    assert any(a["agent"] == "Grok" and a["state"] == "ended_with_run" for a in after["agents"])
    assert not any(a["state"] == "connected" and a["via"] == "passcode" for a in after["agents"])


def test_nothing_new_is_reachable_by_a_client_role_but_the_two_boards(db):
    for role in ("anon", "authenticated"):
        for fn in ("ottoq_agent_set_passcode(text,integer,uuid)", "ottoq_agent_public_call(text,jsonb,text,jsonb,timestamptz)",
                   "ottoq_agent_welcome_public(uuid)", "ottoq_agent_unauthenticated(text)", "ottoq_owner_confirmation_code(uuid)",
                   "ottoq_agent_call(text,text,jsonb,text,jsonb)"):
            assert db.val(f"SELECT has_function_privilege('{role}', 'public.{fn}', 'EXECUTE')") == "f", (role, fn)
        assert db.val(f"SELECT has_function_privilege('{role}', 'public.ottoq_depot_owner_board(uuid,integer)', 'EXECUTE')") == "t"
        assert db.val(f"SELECT has_table_privilege('{role}', 'public.ottoq_agent_demo_passcode', 'SELECT')") == "f"
    rc, _, err = db.run("SELECT * FROM ottoq_agent_demo_passcode", role="anon", check=False)
    assert rc != 0 and "permission denied" in err


def test_turning_the_passcode_off_shuts_the_door_but_not_open_sessions(db, door):
    fresh_run(db)
    key = unlock(db, agent="Stayer")["data"]["session"]
    off = db.json("SELECT ottoq_agent_set_passcode(NULL)")
    assert off["ok"] and off["enabled"] is False and "no new session can be opened" in off["message"]
    assert pcall(db, None, "enter_passcode", {"passcode": PASSCODE})["error"]["code"] == "passcode_off"
    assert pcall(db, h(key), "whoami")["ok"]
    assert db.json(f"SELECT ottoq_agent_set_passcode({q(PASSCODE)})")["enabled"] is True
