"""db/migrations/0721, EXECUTED on the stub engine: a signed-in owner changes production under their own name, and every
owner command says which door it came through (OTTO-Command as the filter and executor, Chase 2026-10-14).

WHY THIS EXISTS. 0721 lets an owner's agent change settings on a PRODUCTION run for the first time, which is exactly where
CLAUDE.md rules 9 and 10 bind hardest. None of what it promises is visible to a compile check:

  * the bodies it patches are byte for byte the live ones (md5), and so are the four reads OTTO-Command now offers and
    production's world step that applies what an owner sets (0718);
  * BEFORE it, reproduced: a signed-in owner is refused on a production run (no_live_demo), no command names a person or
    a door, and the dispatcher never passes its transport;
  * AFTER it: production takes an agent signed in to its owner's account, and only one; a passcode session, an issued
    key and a connection whose account is no longer linked are refused with why and what to do; every command records
    acting_person and via; the engine reads the confirmed limit; the run's end lifts it; demo runs work as before;
  * THE BINDING (rule 9): on production a lowering (a lower limit, or an undo that puts one back) applies only as the
    confirm of a preview the same principal recorded on the same run within 15 minutes. Unbound, it is recorded as a
    preview and answered confirm_required; bound, it applies once (a second confirm, a confirm older than 15 minutes,
    one by another principal and a hash with no recorded preview all apply nothing); raising, clearing, holds, service
    orders and cancelling the owner's own unstarted orders stay one call, and cancel never takes an engine-found need;
  * via is set by the database, never by an argument: 'ottocommand' when a model called the tool, 'confirm' exactly when
    the row confirms a recorded preview (confirms_command_id, by CHECK, whichever transport sent it), 'direct' otherwise;
    a model's call never confirms;
  * the person, the door and the preview are immutable, an applied production command without a person and a confirm
    of anything but such a preview cannot be written by anyone, no client role reaches anything new, and the run-scope
    registry stays clean;
  * §9-§13 (Chase 2026-10-14, 12:35 PM CT: an owner's settings persist per vehicle): a signed-in owner's charge limit and
    every-return orders are saved to the car and carried onto every new demo and production run (once per run, inside
    the contract, only the owner's cars, never onto an arm), the run's end lifts them from the run and not from the car,
    holds, one-time orders and anything set without a person stay per run, a person's lower limit is confirmed on every
    run, undo on a later run says the setting is saved; the owner tables refuse rows no applied command set (item 10);
    the demo passcode opens and serves nothing while production is live (item 11); every OTTO-Command model call is
    ledgered through a service-role-only door that refuses text;
  * the review of 2026-10-14 (rule 9): a person's clear, limit at the ceiling and cancel end what is saved whatever row
    the run holds (a passcode session's, or none because the carry skipped it), as an applied change of its own, so the
    next production run carries nothing back; a person's limit is saved even when the run already held that value; and a
    passcode session or an issued key reads no `saved` block and no person's email.
  * §14: with no run live a signed-in owner still saves to the cars: a charge limit (set, raised, at the ceiling,
    cleared; a lowering only as the bound confirm of its own preview made with no run, which a run starting in between
    invalidates) and every-return orders (saved, withdrawn), written to the saved table only, recorded with no run, the
    person and outcome 'saved' (held by CHECK), and carried onto the next demo and production run as any saved row; a
    hold, a one-time order and an undo are refused needs_a_live_run, and a passcode session or an issued key no_live_demo
    with why (it names no person).
  * the review, round 1 (the evening of 2026-10-14): the owner tables refuse every write that does not come from the
    functions that make owner settings (each named for its own call by ottoq.owner_settings_writer): a plain INSERT,
    UPDATE, DELETE or TRUNCATE on either table, as postgres and as service_role, and a write right after an owner command
    in its own transaction; with the writer setting forged, each move is still refused unless it is that writer's own
    (G1-G5); a one-time order never ends a saved every-return order (a new demo and a new production run carry it, and on
    the run it is back once the one-time order is done); and the anon-readable cockpit boards show no production run's
    settings or commands, no person's command made with no run live, no person's note, and no such command's id on a
    demo run's carried setting.

Loads the stub engines, 0559, 0560, 0605-0608, tests/fixtures/agent_signin_stub_auth.sql, 0700 and
tests/fixtures/model_call_ledger_stub.sql (the live model ledger's bodies, md5-asserted) from their files, and
production's world step as 0718 left it (tests/fixtures/world_advance_stub.sql with 0718 applied in a scratch database:
md5 546fa1ab9bedd29f7169ee6b4e7c090b, the live definition). SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess

import pytest

from test_owner_agent_sql import (  # noqa: F401  (pytestmark: skip without a scratch server)
    AV041, AV045, M0559, M0560, M0605, M0606, ROOT, RT003, SEED, STUB_0559, STUB_0605, TESLA, TWIN,
    _conn_args, _drop, _new_db, pytestmark, q,
)
from test_owner_agent_sql import fresh_run as _fresh_run
from test_passcode_door_sql import M0607, M0608, PASSCODE, pcall, unlock
from test_agent_signin_sql import CHASE, M0700, STUB_AUTH, connect, sha

M0718 = os.path.join(ROOT, "db", "migrations", "0718_production_runs_the_world_phases_the_twin_certifies.sql")
M0721 = os.path.join(ROOT, "db", "migrations", "0721_a_signed_in_owner_changes_production_under_their_own_name.sql")
WORLD_STUB = os.path.join(ROOT, "tests", "fixtures", "world_advance_stub.sql")
#: the live evidence ledger of model calls (0340/0341/0415), which 0721 §13 writes OTTO-Command's calls into
LEDGER_STUB = os.path.join(ROOT, "tests", "fixtures", "model_call_ledger_stub.sql")
CHAIN = (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608, STUB_AUTH, M0700, LEDGER_STUB)
LINEAGE = "0721_a_signed_in_owner_changes_production_under_their_own_name"
EMAIL = "chase@ottoyard.com"

#: md5(pg_get_functiondef()) read from the LIVE catalog (gxdrcyphqjzjsuhxuqtg) on 2026-10-14, 14:54 UTC.
LIVE_MD5 = {
    # the five bodies 0721 replaces
    "public.ottoq_agent_call(text,text,jsonb,text,jsonb)": "ae935f897ee25b6db3eacfbb9215797d",
    "public.ottoq_owner_command(ottoq_agent_principals,text,jsonb)": "533b275b976b5287f1f48b245132139f",
    "public.ottoq_owner_command_reply(ottoq_owner_commands,boolean)": "bd0c86d127a2a84903fa2fb812ee1ac5",
    "public.ottoq_agent_read_whoami(ottoq_agent_principals)": "53aa8a6690ecc6274e4cd1dc73972006",
    "public.ottoq_owner_commands_guard()": "758eff5a6a274b176573c6674840dc55",
    # the four reads OTTO-Command now offers, and the scope test two of them use
    "public.ottoq_agent_read_depot(ottoq_agent_principals)": "9c3ef3ebfdfc1452d430e922aedd6370",
    "public.ottoq_agent_read_vehicle(ottoq_agent_principals,jsonb)": "a19d1d66275fd3e459fb3ec4263634e5",
    "public.ottoq_agent_read_decisions(ottoq_agent_principals,jsonb)": "7d1f7e652d8c840b95b52286d78cbae4",
    "public.ottoq_agent_read_stalls(ottoq_agent_principals,jsonb)": "17156c4b0f42b11af1ec3d0e9d511b03",
    "public.ottoq_agent_vehicle_in_scope(ottoq_agent_principals,uuid)": "339598e6cad0c62d1d62aabdde5ded52",
    # production's world step, as 0718 left it
    "twin.ottoq_world_advance()": "546fa1ab9bedd29f7169ee6b4e7c090b",
    # §9-§13 (read 2026-10-14 between 17:59 and 18:17 UTC): the run's end, the passcode door, my_settings' read, and the
    # model ledger's writer, its guard and its classifier (tests/fixtures/model_call_ledger_stub.sql)
    "public.ottoq_tg_lift_owner_settings_on_terminal()": "e7d0a3f35a057175f7de8ffc88c98b99",
    "public.ottoq_agent_public_call(text,jsonb,text,jsonb,timestamp with time zone)": "222ec84d178ea9063e820347b71a9c3f",
    "public.ottoq_owner_read(ottoq_agent_principals,text,jsonb)": "69bd022e5af9e79fc6f15d5de21edc8f",
    "public.ottoq_log_model_call(text,text,text,uuid,uuid,bigint,timestamp with time zone,text,text,text,integer,integer,integer,boolean,jsonb,text)":
        "482dcde3ae386e07da3e8ebcf5188373",
    "public.ottoq_model_call_ledger_append_only()": "43eeb790fe779fb15bd06158f5e1ea16",
    "public.ottoq_model_call_outcome_class(text)": "05ce85781fc4c45a6cc991b9cea9dc25",
    # §15 (the review, round 1; read 2026-10-14 21:03:34 UTC): the two cockpit boards, EXECUTE for anon
    "public.ottoq_owner_board(uuid,uuid,uuid)": "84e756310bb785ea99bd434662fba37d",
    "public.ottoq_depot_owner_board(uuid,integer)": "deb3c6e8b686ac79a6419099314fb3ae",
    # §10 (the review, round 1; read 2026-10-14 23:09:53 UTC): the tick, named a writer of the owner tables, body unchanged
    "ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)": "5f01d0881bd65d80b155dba04033e09f",
}


def _psql(dbname, *args):
    return subprocess.run(["psql", *_conn_args(), "-d", dbname, "-q", "-X", "-v", "ON_ERROR_STOP=1", *args],
                          capture_output=True, text=True)


def world_advance_def():
    """twin.ottoq_world_advance as production runs it: the 2026-10-13 body (world_advance_stub.sql) with 0718 applied."""
    d = _new_db()
    try:
        for path in (WORLD_STUB, M0718):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        return d.text("SELECT pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)")
    finally:
        _drop(d)


def build(apply_0721):
    d = _new_db()
    for path in CHAIN:
        rc, err = d.file(path)
        assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
    p = _psql(d.name, "-c", "SET check_function_bodies = off;\n" + world_advance_def() + ";")
    assert p.returncode == 0, p.stderr
    d.run(SEED)
    d.run(f"INSERT INTO auth.users (id, email) VALUES ('{CHASE}', 'Chase@OTTOYARD.com')")
    assert d.json(f"SELECT ottoq_owner_account_link({q(EMAIL)}, '{TESLA}', 'the founder')")["ok"]
    assert d.json(f"SELECT ottoq_agent_set_passcode({q(PASSCODE)})")["ok"]
    if apply_0721:
        rc, err = d.file(M0721)
        assert rc == 0, f"0721 did not apply: {err}"
    return d


@pytest.fixture(scope="module")
def pre():
    d = build(False)
    try:
        yield d
    finally:
        _drop(d)


@pytest.fixture(scope="module")
def post():
    d = build(True)
    try:
        yield d
    finally:
        _drop(d)


def tcall(db, token, tool, args=None, transport="mcp"):
    return pcall(db, sha(token), tool, args or {}, transport=transport)


def forget_saved(db):
    """§9 carries what a signed-in owner saved onto every new run, so a test that is not about saving starts with nothing
    saved: earlier tests' saved settings are ended (the owner ledger's unlock, as a migration would name it)."""
    db.run("DO $f$ BEGIN IF to_regclass('public.ottoq_owner_saved_settings') IS NOT NULL THEN "
           "PERFORM set_config('ottoq.agent_ledger_unlock', 'on', true); "
           "UPDATE ottoq_owner_saved_settings SET status = 'ended', ended_at = now(), ended_reason = 'test reset' "
           "WHERE status = 'active'; END IF; END $f$")


def fresh_run(db, clock="2026-09-27 12:00:00+00", keep_saved=False):
    """test_owner_agent_sql's fresh demo run, starting from nothing saved unless keep_saved."""
    if not keep_saved:
        forget_saved(db)
    return _fresh_run(db, clock)


def production_run(db, status="running", keep_saved=False):
    """A twin-depot run with the cars' visits, as production_live (fresh_run ends whatever was live first)."""
    run = fresh_run(db, keep_saved=keep_saved)
    db.run(f"UPDATE ottoq_sim_runs SET run_by = 'production_live', status = '{status}' WHERE sim_run_id = '{run}'")
    return run


def command(db, command_id):
    return db.rows(f"SELECT outcome, coalesce(acting_person, '-'), coalesce(via, '-') FROM ottoq_owner_commands "
                   f"WHERE command_id = '{command_id}'")[0]


def confirm(db, token, receipt, transport="confirm"):
    """Send back the confirm object a receipt carries, as the gateway's confirm door does (transport 'confirm')."""
    c = receipt["data"]["confirm"]
    return tcall(db, token, c["tool"], c["args"], transport=transport)


def target(db, car=AV041):
    return db.val(f"SELECT round(ottoq_effective_target_soc_at('{car}', now()))")


def age(db, command_id, interval):
    """Make a recorded command older (its created_at is guarded; the ledger unlock lets a test move it)."""
    db.run(f"SET ottoq.agent_ledger_unlock = 'on'; UPDATE ottoq_owner_commands SET created_at = now() - interval '{interval}' "
           f"WHERE command_id = '{command_id}'")


# ───────────────────────────────────────────────────────────────────────── the premises: live, byte for byte ──

def test_every_body_0721_reads_is_the_live_one(pre):
    for fn, want in LIVE_MD5.items():
        assert pre.val(f"SELECT md5(pg_get_functiondef('{fn}'::regprocedure))") == want, fn


def test_0721_needs_0700():
    d = _new_db()
    try:
        for path in CHAIN[:-2]:
            assert d.file(path)[0] == 0
        rc, err = d.file(M0721)
        assert rc != 0 and "0721 P1: 0700" in err, err
    finally:
        _drop(d)


def test_0721_refuses_a_body_it_did_not_measure_and_a_production_world_that_ignores_owners(pre):
    d = build(False)
    try:
        src = d.text("SELECT pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure)")
        assert _psql(d.name, "-c", src.replace("is immutable", "is immutable!") + ";").returncode == 0
        rc, err = d.file(M0721)
        assert rc != 0 and "0721 P1: not the body this file was written against" in err and "ottoq_owner_commands_guard" in err, err
        # put the guard back as live has it, then take the owner step out of production's world step
        assert _psql(d.name, "-c", pre.text("SELECT pg_get_functiondef('public.ottoq_owner_commands_guard()'::regprocedure)") + ";").returncode == 0
        wa = d.text("SELECT pg_get_functiondef('twin.ottoq_world_advance()'::regprocedure)")
        cut = wa.replace("PERFORM ottoq.ottoq_owner_orders_tick(v_run.sim_run_id, v_now);", "NULL;")
        assert cut != wa
        assert _psql(d.name, "-c", "SET check_function_bodies = off;\n" + cut + ";").returncode == 0
        rc, err = d.file(M0721)
        assert rc != 0 and "0721 P1: production's world step does not apply owner settings" in err, err
    finally:
        _drop(d)


# ─────────────────────────────────────────────────────────────────────── BEFORE 0721: today's defects, reproduced ──

def test_before_a_signed_in_owner_is_refused_on_a_production_run(pre):
    chase = connect(pre)["access_token"]
    run = production_run(pre)
    r = tcall(pre, chase, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})
    assert r["http_status"] == 422 and r["error"]["code"] == "no_live_demo", r
    assert r["error"]["message"] == "The live run at the twin depot is not a demo run, and owner settings apply only to demo runs."
    assert pre.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}'") == "0"


def test_before_no_command_names_a_person_or_a_door(pre):
    cols = pre.rows("SELECT column_name FROM information_schema.columns WHERE table_name = 'ottoq_owner_commands' "
                    "AND column_name IN ('acting_person', 'via')")
    assert cols == []
    call = pre.text("SELECT pg_get_functiondef('public.ottoq_agent_call(text,text,jsonb,text,jsonb)'::regprocedure)")
    assert "ELSE public.ottoq_owner_command(v_agent, v_tool, v_args)\n" in call, "the dispatcher keeps its transport to itself"
    assert pre.val("SELECT count(*) FROM pg_proc WHERE proname = 'ottoq_owner_command'") == "1"


def test_before_a_lower_limit_is_one_call_on_a_demo_run(pre):
    chase = connect(pre)["access_token"]
    fresh_run(pre)
    r = tcall(pre, chase, "set_charge_limit", {"vehicles": "all", "percent": 85}, transport="ask")
    assert r["http_status"] == 201 and r["data"]["outcome"] == "applied", r


# ───────────────────────────────────────────────────────────────────────────────────────────── AFTER 0721 ──

def test_0721_refuses_a_second_apply_and_is_classified_for_no_recert_round(post):
    rc, err = post.file(M0721)
    assert rc != 0 and "0721 P1: already applied" in err, err
    assert post.rows(f"SELECT forces_recert, forces_dial_restart FROM ottoq_cert_lineage WHERE name = '{LINEAGE}'") == [["f", "f"]]


def test_production_takes_a_signed_in_owner_and_an_unbound_lowering_is_recorded_as_a_preview(post):
    chase = connect(post)["access_token"]
    run = production_run(post)
    who = tcall(post, chase, "whoami")["data"]["owner"]
    assert who["live_production_run"] == run and who["live_demo_run"] is None
    assert who["changes"]["allowed"] is True and who["changes"]["run_kind"] == "production"
    assert who["changes"]["person"] == EMAIL and who["changes"]["lower_limit_needs_preview"] is True
    assert who["changes"]["confirm_window_minutes"] == 15
    assert "only an agent signed in to its owner's OTTOYARD account" in who["rules"]
    assert "applies only as the confirm of a preview the same agent recorded in the last 15 minutes" in who["rules"]

    # one call that lowers: NOT applied. OTTO-Q records it as a preview under the person and answers confirm_required
    one = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert one["http_status"] == 422 and one["ok"] is False and one["error"]["code"] == "confirm_required", one
    assert one["error"]["message"].startswith("This is a production run, so lowering how full a car charges applies only "
                                              "as the confirm of a preview this agent recorded in the last 15 minutes.")
    assert "Nothing was applied." in one["error"]["message"]
    assert one["error"]["hint"].startswith("Show your person the plan.")
    data = one["data"]
    pid = data["command"]["command_id"]
    assert data["outcome"] == "previewed" and data["command"]["mode"] == "preview"
    assert data["refusal"]["reason"] == "not_named" and data["refusal"]["preview_command_id"] == pid
    assert data["summary"].startswith("Not applied yet: This is a production run")
    assert f'confirms_command_id "{pid}"' in data["summary"]
    assert data["confirm"]["args"]["confirms_command_id"] == pid
    assert data["confirm"]["args"]["expect_plan_hash"] == data["command"]["plan_hash"]
    assert command(post, pid) == ["previewed", EMAIL, "direct"]
    assert post.val(f"SELECT mode = 'preview' AND refusal IS NULL AND idempotency_key IS NULL AND confirms_command_id IS NULL "
                    f"FROM ottoq_owner_commands WHERE command_id = '{pid}'") == "t"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}'") == "0"
    assert post.rows(f"SELECT http_status, error_code, detail ->> 'outcome' FROM ottoq_agent_call_ledger WHERE call_id = {one['call_id']}") \
        == [["422", "confirm_required", "previewed"]]

    # its confirm, sent back through the confirm door: applied, bound to that preview, under the person
    done = confirm(post, chase, one)
    assert done["http_status"] == 201 and done["data"]["outcome"] == "applied", done
    cmd = done["data"]["command"]
    assert cmd["acting_person"] == EMAIL and cmd["via"] == "confirm" and cmd["confirms_command_id"] == pid
    assert command(post, cmd["command_id"]) == ["applied", EMAIL, "confirm"]
    assert post.val(f"SELECT transport FROM ottoq_agent_call_ledger WHERE call_id = {done['call_id']}") == "confirm"
    # §9: a signed-in owner's limit is saved to the cars, and the receipt says so
    assert "This is saved to your cars: it stays from run to run, production included, until you change it." in done["data"]["summary"]
    assert done["data"]["expires"].startswith("Saved to the cars: it stays from run to run")
    # the engine reads the owner's confirmed limit, and production's tick applies it to the cars
    assert target(post) == "90"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND kind = 'charge_limit' "
                    "AND status = 'active' AND charge_limit_pct = 90") == "4"
    # a stale hash is still plan_changed (0605), and is refused rather than recorded as a preview
    stale = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 85, "mode": "apply",
                                                   "expect_plan_hash": data["command"]["plan_hash"]})
    assert stale["error"]["code"] == "plan_changed" and stale["data"]["outcome"] == "refused", stale


def test_a_preview_confirms_one_apply_and_no_more(post):
    chase = connect(post)["access_token"]
    production_run(post)
    prev = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"}, transport="ask")
    assert prev["data"]["outcome"] == "previewed" and prev["data"]["command"]["via"] == "ottocommand"
    pid = prev["data"]["command"]["command_id"]
    first = confirm(post, chase, prev)
    assert first["data"]["outcome"] == "applied" and first["data"]["command"]["confirms_command_id"] == pid, first
    # undoing the lower limit raises it again: one call, and the same plan is on the table once more
    back = tcall(post, chase, "undo_command", {"command_id": first["data"]["command"]["command_id"]})
    assert back["data"]["outcome"] == "applied", back
    assert target(post) == "100"
    second = confirm(post, chase, prev)
    assert second["http_status"] == 422 and second["error"]["code"] == "confirm_required", second
    assert second["data"]["refusal"]["reason"] == "preview_already_confirmed"
    assert "That preview was already confirmed once, and a preview confirms one apply." in second["error"]["message"]
    assert second["data"]["outcome"] == "previewed" and target(post) == "100"
    # written straight into the table, a second apply naming the same preview is refused by the unique index
    rc, _, err = post.run(f"""INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id,
                                  sim_run_id, tool, mode, outcome, summary, plan_hash, acting_person, via, confirms_command_id)
                              SELECT principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, 'apply',
                                     'applied', 'x', plan_hash, acting_person, 'confirm', command_id
                                FROM ottoq_owner_commands WHERE command_id = '{pid}'""", check=False)
    assert rc != 0 and "ottoq_owner_commands_confirms_idx" in err, err
    # the preview the refusal recorded is new, and its own confirm applies it
    third = confirm(post, chase, second)
    assert third["data"]["outcome"] == "applied", third
    assert third["data"]["command"]["confirms_command_id"] == second["data"]["command"]["command_id"]
    assert target(post) == "90"


def test_a_confirm_older_than_15_minutes_is_refused(post):
    chase = connect(post)["access_token"]
    run = production_run(post)
    prev = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 85, "mode": "preview"})
    pid = prev["data"]["command"]["command_id"]
    age(post, pid, "16 minutes")
    late = confirm(post, chase, prev)
    assert late["http_status"] == 422 and late["error"]["code"] == "confirm_required", late
    assert late["data"]["refusal"]["reason"] == "preview_expired"
    assert "That preview is more than 15 minutes old." in late["error"]["message"]
    assert target(post) == "100"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}'") == "0"
    # the backstop refuses the same binding written straight into the table
    rc, _, err = post.run(f"""INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id,
                                  sim_run_id, tool, mode, outcome, summary, plan_hash, acting_person, via, confirms_command_id)
                              SELECT principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, 'apply',
                                     'applied', 'x', plan_hash, acting_person, 'confirm', command_id
                                FROM ottoq_owner_commands WHERE command_id = '{pid}'""", check=False)
    assert rc != 0 and "is not a preview this apply may confirm" in err, err
    # inside the window it binds
    fresh = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 85, "mode": "preview"})
    age(post, fresh["data"]["command"]["command_id"], "14 minutes")
    ok = confirm(post, chase, fresh)
    assert ok["data"]["outcome"] == "applied", ok
    assert ok["data"]["command"]["confirms_command_id"] == fresh["data"]["command"]["command_id"]
    assert target(post) == "85"


def test_a_confirm_by_another_principal_is_refused(post):
    # two agents signed in to the same person's account are two principals, and each confirms only its own previews
    hermes, grok = connect(post)["access_token"], connect(post)["access_token"]
    production_run(post)
    prev = tcall(post, hermes, "set_charge_limit", {"vehicles": "all", "percent": 85, "mode": "preview"})
    pid, plan = prev["data"]["command"]["command_id"], prev["data"]["command"]["plan_hash"]
    by_hash = tcall(post, grok, "set_charge_limit", {"vehicles": "all", "percent": 85, "expect_plan_hash": plan})
    assert by_hash["error"]["code"] == "confirm_required" and by_hash["data"]["refusal"]["reason"] == "no_recorded_preview", by_hash
    by_id = confirm(post, grok, prev)
    assert by_id["error"]["code"] == "confirm_required" and by_id["data"]["refusal"]["reason"] == "no_recorded_preview", by_id
    assert "This agent recorded no such preview on this run." in by_id["error"]["message"]
    assert target(post) == "100"
    # written straight into the table under the other principal, the backstop refuses it
    other = post.val(f"SELECT principal_id FROM ottoq_owner_commands WHERE command_id = '{by_id['data']['command']['command_id']}'")
    rc, _, err = post.run(f"""INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id,
                                  sim_run_id, tool, mode, outcome, summary, plan_hash, acting_person, via, confirms_command_id)
                              SELECT '{other}', principal_name, fleet_operator_id, depot_id, sim_run_id, tool, 'apply',
                                     'applied', 'x', plan_hash, acting_person, 'confirm', command_id
                                FROM ottoq_owner_commands WHERE command_id = '{pid}'""", check=False)
    assert rc != 0 and "is not a preview this apply may confirm" in err, err
    # the agent that previewed confirms it
    mine = confirm(post, hermes, prev)
    assert mine["data"]["outcome"] == "applied" and mine["data"]["command"]["confirms_command_id"] == pid, mine
    assert target(post) == "85"


def test_a_hash_only_confirm_without_a_recorded_preview_is_refused(post):
    chase = connect(post)["access_token"]
    run = production_run(post)
    # the plan hash is md5 of data the token can read, so an agent could compute it without previewing: stand that in
    # by recording a preview, keeping its hash, and taking the preview away
    prev = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 80, "mode": "preview"})
    plan = prev["data"]["command"]["plan_hash"]
    post.run(f"SET ottoq.agent_ledger_unlock = 'on'; DELETE FROM ottoq_owner_commands WHERE command_id = '{prev['data']['command']['command_id']}'")
    r = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 80, "expect_plan_hash": plan})
    assert r["http_status"] == 422 and r["error"]["code"] == "confirm_required", r
    assert r["data"]["refusal"]["reason"] == "no_recorded_preview" and r["data"]["outcome"] == "previewed"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}'") == "0"
    assert r["data"]["command"]["via"] == "direct", "the agent's own call, which confirmed nothing"
    # the preview that answer recorded is real, so the same hash now binds to it (by hash alone, through the typed tool),
    # and the row says what happened: the agent confirmed a recorded preview
    again = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 80, "expect_plan_hash": plan})
    assert again["http_status"] == 201 and again["data"]["outcome"] == "applied", again
    assert again["data"]["command"]["confirms_command_id"] == r["data"]["command"]["command_id"]
    assert again["data"]["command"]["via"] == "confirm"
    assert post.val(f"SELECT transport FROM ottoq_agent_call_ledger WHERE call_id = {again['call_id']}") == "mcp"
    assert target(post) == "80"


def test_an_undo_that_lowers_is_gated_the_same_way_and_one_that_raises_is_not(post):
    chase = connect(post)["access_token"]
    production_run(post)
    low = confirm(post, chase, tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 85, "mode": "preview"}))
    assert low["data"]["outcome"] == "applied" and target(post) == "85", low
    up = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 95}, transport="rest")
    assert up["http_status"] == 201 and up["data"]["command"]["via"] == "direct" and target(post) == "95", up
    # undoing the raise puts the 85 back: that lowers the car, so it is a preview until confirmed
    undo = tcall(post, chase, "undo_command", {"command_id": up["data"]["command"]["command_id"]})
    assert undo["http_status"] == 422 and undo["error"]["code"] == "confirm_required", undo
    assert undo["data"]["refusal"]["reason"] == "not_named" and undo["data"]["outcome"] == "previewed"
    assert undo["data"]["command"]["tool"] == "undo_command" and target(post) == "95"
    assert post.val(f"SELECT undone_at IS NULL FROM ottoq_owner_commands WHERE command_id = '{up['data']['command']['command_id']}'") == "t"
    done = confirm(post, chase, undo)
    assert done["data"]["outcome"] == "applied" and done["data"]["command"]["via"] == "confirm", done
    assert target(post) == "85"
    # undoing the confirmed lower limit puts the cars back to full: a raise, one call
    back = tcall(post, chase, "undo_command", {"command_id": low["data"]["command"]["command_id"]})
    assert back["http_status"] == 201 and back["data"]["outcome"] == "applied", back
    assert target(post) == "100"


def test_everything_but_lowering_stays_one_call_and_cancel_takes_only_the_owners_unstarted_orders(post):
    """Rule 9: no command can skip, defer or shorten a service OTTO-Q found needed. On production, cancel_service is
    0605's: an engine-found need stays, a started order finishes, only the owner's own unstarted orders come off."""
    chase = connect(post)["access_token"]
    run = production_run(post)
    one_call = []
    one_call.append(tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 30}))
    one_call.append(tcall(post, chase, "release_hold", {"vehicles": ["Tesla 45"]}))
    one_call.append(tcall(post, chase, "request_service", {"vehicles": "all", "service": "exterior_wash", "when": "every_return"}))
    post.tick(run, "2026-09-27 12:21+00")
    cancel = tcall(post, chase, "cancel_service", {"vehicles": "all", "service": "exterior_wash"})
    one_call.append(cancel)
    assert "3 have it taken off their plans" in cancel["data"]["summary"]
    assert "1 keeps it on this visit because OTTO-Q found it needed" in cancel["data"]["summary"]
    post.tick(run, "2026-09-27 12:22+00")
    left = post.rows(f"""SELECT n.vehicle_id, a::text FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                         WHERE n.sim_run_id = '{run}' AND a->>'svc' = 'exterior_wash'""")
    assert [r[0] for r in left] == [AV045] and "owner_setting_ids" not in left[0][1]
    # an owner's order already under way finishes when cancelled
    one_call.append(tcall(post, chase, "request_service", {"vehicles": ["RT-3"], "service": "software update"}))
    post.tick(run, "2026-09-27 12:23+00")
    post.run(f"""UPDATE ottoq_visit_needs SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = 'software_update' THEN a || '{{"status":"in_progress"}}' ELSE a END)
                                                        FROM jsonb_array_elements(atoms) a)
                 WHERE vehicle_id = '{RT003}' AND sim_run_id = '{run}'""")
    started = tcall(post, chase, "cancel_service", {"vehicles": ["RT-3"]})
    one_call.append(started)
    assert "is under way and finishes" in started["data"]["summary"]
    post.tick(run, "2026-09-27 12:24+00")
    assert post.val(f"""SELECT a->>'status' FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                        WHERE n.vehicle_id = '{RT003}' AND n.sim_run_id = '{run}' AND a->>'svc' = 'software_update'""") == "in_progress"
    # raising a confirmed limit and clearing it are one call each
    low = confirm(post, chase, tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 85, "mode": "preview"}))
    assert low["data"]["outcome"] == "applied", low
    one_call.append(tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 95}))
    one_call.append(tcall(post, chase, "clear_charge_limit", {"vehicles": "all"}))
    for r in one_call:
        assert r["http_status"] == 201 and r["data"]["outcome"] == "applied", r
        assert r["data"]["command"]["via"] == "direct" and r["data"]["command"]["acting_person"] == EMAIL
        assert "confirms_command_id" not in r["data"]["command"]
    assert target(post) == "100"


def test_via_comes_from_the_door_and_never_from_the_arguments(post):
    chase = connect(post)["access_token"]
    fresh_run(post)                # a demo run: every door applies there
    got = {}
    for i, transport in enumerate(("ask", "mcp", "rest", "smoke-signal")):
        r = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 30 + i, "via": "ottocommand"},
                  transport=transport)
        assert r["data"]["outcome"] == "applied", r
        got[transport] = (command(post, r["data"]["command"]["command_id"])[2],
                          post.val(f"SELECT transport FROM ottoq_agent_call_ledger WHERE call_id = {r['call_id']}"))
    assert got == {"ask": ("ottocommand", "ask"), "mcp": ("direct", "mcp"), "rest": ("direct", "rest"),
                   "smoke-signal": ("direct", "other")}
    # the confirm door applies only a recorded preview, on a demo run too: unnamed, it records a preview, and that row is
    # the agent's own ('direct'), because it confirmed nothing; the ledger keeps the transport
    bare = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 45}, transport="confirm")
    assert bare["error"]["code"] == "confirm_required" and bare["data"]["refusal"]["reason"] == "not_named", bare
    assert command(post, bare["data"]["command"]["command_id"]) == ["previewed", EMAIL, "direct"]
    assert post.val(f"SELECT transport FROM ottoq_agent_call_ledger WHERE call_id = {bare['call_id']}") == "confirm"
    ok = confirm(post, chase, bare)
    assert ok["data"]["outcome"] == "applied" and ok["data"]["command"]["via"] == "confirm", ok
    assert ok["data"]["command"]["confirms_command_id"] == bare["data"]["command"]["command_id"]
    # a typed tool that names a recorded preview is a confirm too, and is recorded as one
    typed_prev = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 40, "mode": "preview"}, transport="rest")
    assert command(post, typed_prev["data"]["command"]["command_id"]) == ["previewed", EMAIL, "direct"]
    typed = confirm(post, chase, typed_prev, transport="rest")
    assert typed["data"]["outcome"] == "applied" and typed["data"]["command"]["via"] == "confirm", typed
    assert typed["data"]["command"]["confirms_command_id"] == typed_prev["data"]["command"]["command_id"]
    # an OTTO-Command model never confirms: a call through 'ask' that names a preview is refused
    prev = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 50, "mode": "preview"})
    for extra in ({"expect_plan_hash": prev["data"]["command"]["plan_hash"]},
                  {"confirms_command_id": prev["data"]["command"]["command_id"]}):
        r = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "until": prev["data"]["confirm"]["args"]["until"], **extra},
                  transport="ask")
        assert r["http_status"] == 422 and r["error"]["code"] == "confirm_not_through_ottocommand", r
        assert command(post, r["data"]["command"]["command_id"]) == ["refused", EMAIL, "ottocommand"]
    bad = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 50, "mode": "preview",
                                              "confirms_command_id": prev["data"]["command"]["command_id"]})
    assert bad["http_status"] == 400 and "confirms_command_id is for mode apply" in bad["error"]["message"], bad
    # the two CHECKs make via 'confirm' and confirms_command_id one fact: a confirm row names its preview, and a row
    # that names a preview is a confirm (never a model's, never 'direct')
    pid = prev["data"]["command"]["command_id"]
    insert = f"""INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool,
                     mode, outcome, summary, plan_hash, acting_person, via, confirms_command_id)
                 SELECT principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, 'apply', 'applied', 'x',
                        plan_hash, acting_person, %s FROM ottoq_owner_commands WHERE command_id = '{pid}'"""
    rc, _, err = post.run(insert % "'confirm', NULL", check=False)
    assert rc != 0 and "ottoq_owner_commands_confirm_is_bound_check" in err, err
    for door in ("'ottocommand'", "'direct'"):
        rc, _, err = post.run(insert % f"{door}, command_id", check=False)
        assert rc != 0 and "ottoq_owner_commands_confirms_check" in err, (door, err)
    # and so it is on every row the doors wrote
    assert post.val("SELECT count(*) FROM ottoq_owner_commands WHERE (via = 'confirm') IS DISTINCT FROM (confirms_command_id IS NOT NULL) "
                    "AND via IS NOT NULL") == "0"


def test_production_refuses_a_passcode_an_issued_key_and_an_unlinked_account_with_why(post):
    # a passcode session opened while no run is live (a demo run's end would revoke it, 0607)
    forget_saved(post)
    post.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    session = unlock(post, agent="Grok", ip="192.0.2.71")["data"]["session"]
    run = production_run(post)
    # §12 (re-review item 11): while production is live, the session reads nothing and changes nothing, and is told why
    for tool, args in (("request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash"}), ("my_fleet", {}),
                       ("whoami", {}), ("handshake", {})):
        p = tcall(post, session, tool, args)
        assert p["http_status"] == 403 and p["error"]["code"] == "production_live", (tool, p)
        assert "the demo passcode opens nothing while it is" in p["error"]["message"]
        assert p["error"]["hint"].startswith("Sign your agent in to your OTTOYARD account")
        assert "data" not in p
    assert post.val(f"SELECT count(*) FROM ottoq_agent_call_ledger WHERE error_code = 'production_live' AND principal_id IS NOT NULL") == "4"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_commands WHERE sim_run_id = '{run}'") == "0"
    # and the door opens no new session while it is live, whatever the passcode (it is not even checked)
    for code in (PASSCODE, "not-the-passcode"):
        r = pcall(post, None, "enter_passcode", {"passcode": code, "agent": "Grok"}, ip="192.0.2.73")
        assert r["http_status"] == 403 and r["error"]["code"] == "production_live", r
        assert "Nothing was opened." in r["error"]["message"]
    assert post.val("SELECT count(*) FROM ottoq_agent_principals WHERE origin = 'passcode' AND created_at > now() - interval '1 minute' "
                    "AND display_name = 'Grok' AND status = 'active'") == "1", "only the session opened before production"
    # once production ends, the session works again (until it expires), and the door opens again
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    assert tcall(post, session, "my_fleet")["ok"] is True
    assert pcall(post, None, "enter_passcode", {"passcode": PASSCODE, "agent": "Grok"}, ip="192.0.2.74")["http_status"] == 201
    # an issued key names no person: refused at the gate in production
    production_run(post)
    key = post.json(f"SELECT ottoq_agent_issue_token('fleet-bot', 'personal', ARRAY['read','note','owner_settings'], "
                    f"'{TESLA}', '{TWIN}', NULL, 600, 20)")["token"]
    k = tcall(post, key, "hold_vehicle", {"vehicles": "all", "for_minutes": 30}, transport="rest")
    assert k["error"]["code"] == "production_needs_a_person" and "an issued key names no person" in k["error"]["message"], k
    gate = tcall(post, key, "whoami")["data"]["owner"]["changes"]
    assert gate["allowed"] is False and gate["code"] == "production_needs_a_person" and "person" not in gate
    # a connection whose account is no longer active names no one either (the principal itself is still connected)
    chase = connect(post)["access_token"]
    post.run(f"UPDATE ottoq_owner_accounts SET status = 'disabled', disabled_at = now() WHERE email = {q(EMAIL)}")
    try:
        u = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})
        assert u["error"]["code"] == "production_needs_a_person" and "is not linked to this fleet" in u["error"]["message"], u
    finally:
        post.run(f"UPDATE ottoq_owner_accounts SET status = 'active', disabled_at = NULL WHERE email = {q(EMAIL)}")


def test_a_demo_run_works_as_before_and_records_the_door_and_any_person(post):
    fresh_run(post)
    session = unlock(post, agent="Grok", ip="192.0.2.72")["data"]["session"]
    d = tcall(post, session, "set_charge_limit", {"vehicles": "all", "percent": 85}, transport="ask")
    assert d["data"]["outcome"] == "applied" and "acting_person" not in d["data"]["command"], d
    assert command(post, d["data"]["command"]["command_id"]) == ["applied", "-", "ottocommand"]
    assert "This lasts until the demo run ends or you undo it." in d["data"]["summary"]
    # a passcode session's change on a demo run is the run's, not saved
    assert post.val(f"SELECT count(*) FROM ottoq_owner_saved_settings WHERE command_id = '{d['data']['command']['command_id']}'") == "0"
    who_session = tcall(post, session, "whoami")["data"]["owner"]["changes"]
    assert who_session == {"allowed": True, "run_kind": "demo", "message": "A demo run is live: settings apply to it and lift when it ends."}
    # §9: a signed-in owner's lower limit is saved and carried into production, so on a demo run too it is confirmed the way
    # production confirms one
    chase = connect(post)["access_token"]
    c = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert c["http_status"] == 422 and c["error"]["code"] == "confirm_required", c
    assert c["error"]["message"].startswith("A lower charge limit you set while signed in is saved to your cars and carried "
                                            "into production, so it applies only as the confirm of a preview")
    assert command(post, c["data"]["command"]["command_id"]) == ["previewed", EMAIL, "direct"]
    ok = confirm(post, chase, c)
    assert ok["data"]["outcome"] == "applied" and ok["data"]["command"]["via"] == "confirm", ok
    who = tcall(post, chase, "whoami")["data"]["owner"]["changes"]
    assert who["allowed"] is True and who["run_kind"] == "demo" and who["person"] == EMAIL and who["saved"] is True
    assert who["lower_limit_needs_preview"] is True and who["confirm_window_minutes"] == 15
    assert who["message"].startswith(f"A demo run is live. You are signed in as {EMAIL}, so a charge limit or an "
                                     "every-return service you set is saved to your cars and stays from run to run")


def test_no_run_and_any_other_run_keep_0605s_words(post):
    """With no run live a session without a person keeps 0605's no_live_demo (§14 adds only a hint: it names no person, so
    it cannot save to the cars); a signed-in owner is the one who may save then (tested below). Any other run: 0605's words."""
    chase = connect(post)["access_token"]
    post.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    session = unlock(post, agent="Grok", ip="192.0.2.73")["data"]["session"]
    none = tcall(post, session, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})
    assert none["error"]["code"] == "no_live_demo"
    assert none["error"]["message"] == ("No demo run is live at the twin depot. Start one in OTTO-TWIN; what you set applies "
                                        "to that run and resets when it ends.")
    assert none["error"]["hint"].startswith("A passcode session names no person, so it cannot save a setting to your cars")
    run = fresh_run(post)
    post.run(f"UPDATE ottoq_sim_runs SET run_by = 'ab_harness' WHERE sim_run_id = '{run}'")
    other = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})
    assert other["error"]["code"] == "no_live_demo"
    assert other["error"]["message"] == "The live run at the twin depot is not a demo run, and owner settings apply only to demo runs."


def test_the_run_end_lifts_a_production_setting_and_puts_the_car_back(post):
    chase = connect(post)["access_token"]
    run = production_run(post)
    prev = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 80, "mode": "preview"}, transport="ask")
    done = confirm(post, chase, prev)
    assert done["data"]["outcome"] == "applied" and done["data"]["command"]["via"] == "confirm", done
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    # lifted from the run: with no run live nothing is in force, and the car is back to its baseline
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND status = 'active'") == "0"
    assert post.val(f"SELECT round(ottoq_effective_target_soc_at('{AV041}', now()))") == "100"
    # §9: but not from the car: the command is not stamped lifted, its saved row stands, and the next run carries it
    cid = done["data"]["command"]["command_id"]
    assert post.val(f"SELECT coalesce(lifted_reason, '-') FROM ottoq_owner_commands WHERE command_id = '{cid}'") == "-"
    assert post.rows(f"SELECT vehicle_id, charge_limit_pct, status FROM ottoq_owner_saved_settings WHERE command_id = '{cid}'") \
        == [[AV041, "80", "active"]]
    nxt = production_run(post, keep_saved=True)
    assert post.val(f"SELECT round(ottoq_effective_target_soc_at('{AV041}', now()))") == "80"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND saved_id IS NOT NULL") == "1"


def test_the_person_and_the_door_are_immutable_and_no_applied_production_row_lacks_a_person(post):
    chase = connect(post)["access_token"]
    run = production_run(post)
    r = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 30}, transport="ask")
    assert r["data"]["outcome"] == "applied", r
    cid = r["data"]["command"]["command_id"]
    for col, val in (("acting_person", "'someone@else.com'"), ("via", "'direct'"), ("acting_person", "NULL"),
                     ("confirms_command_id", f"'{cid}'")):
        rc, _, err = post.run(f"UPDATE ottoq_owner_commands SET {col} = {val} WHERE command_id = '{cid}'", check=False)
        assert rc != 0 and "immutable" in err, (col, err)
    pid = post.val(f"SELECT principal_id FROM ottoq_owner_commands WHERE command_id = '{cid}'")
    rc, _, err = post.run(f"""INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id,
                              sim_run_id, tool, mode, outcome, summary)
                              VALUES ('{pid}', 'x', '{TESLA}', '{TWIN}', '{run}', 'release_hold', 'apply', 'applied', 'x')""",
                          check=False)
    assert rc != 0 and "needs the person it is recorded under" in err, err
    # a refusal without a person is still recorded (evidence), and a demo row without one too
    post.run(f"""INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool,
                 mode, outcome, refusal, summary) VALUES ('{pid}', 'x', '{TESLA}', '{TWIN}', '{run}', 'release_hold', 'apply',
                 'refused', '{{"code":"x"}}', 'x')""")
    rc, _, err = post.run("INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, tool, "
                          f"mode, outcome, summary, via) VALUES ('{pid}', 'x', '{TESLA}', '{TWIN}', 'release_hold', 'apply', "
                          "'applied', 'x', 'telepathy')", check=False)
    assert rc != 0 and "ottoq_owner_commands_via_check" in err, err
    # an undo is still recorded once, on a row that carries a person and a door
    undo = tcall(post, chase, "undo_command", {"command_id": cid})
    assert undo["data"]["outcome"] == "applied", undo
    assert post.val(f"SELECT undone_at IS NOT NULL FROM ottoq_owner_commands WHERE command_id = '{cid}'") == "t"


def test_the_three_argument_form_delegates_and_records_a_direct_call(post):
    production_run(post)
    chase = connect(post)["access_token"]
    pid = post.val(f"SELECT t.principal_id FROM ottoq_oauth_tokens t WHERE t.token_hash = {q(sha(chase))}")
    out = post.json(f"SELECT ottoq_owner_command(a, 'clear_charge_limit', '{{\"vehicles\":\"all\"}}'::jsonb) "
                    f"FROM ottoq_agent_principals a WHERE a.principal_id = '{pid}'")
    assert out["command"]["via"] == "direct" and out["command"]["acting_person"] == EMAIL, out
    body = post.text("SELECT pg_get_functiondef('public.ottoq_owner_command(ottoq_agent_principals,text,jsonb)'::regprocedure)")
    assert "RETURN public.ottoq_owner_command(p_agent, p_tool, p_args, NULL::text);" in body


def test_no_client_role_reaches_anything_new(post):
    for fn in ("public.ottoq_owner_command(ottoq_agent_principals,text,jsonb,text)",
               "public.ottoq_owner_command(ottoq_agent_principals,text,jsonb)",
               "public.ottoq_owner_write_gate(ottoq_agent_principals,jsonb)",
               "public.ottoq_owner_acting_person(ottoq_agent_principals)",
               "public.ottoq_owner_confirm_binding(ottoq_agent_principals,uuid,text,jsonb,text,text,uuid,boolean)",
               "public.ottoq_owner_commands_backstop()",
               # §9-§11
               "public.ottoq_owner_settings_save()", "public.ottoq_owner_settings_saved_follow()",
               "public.ottoq_owner_saved_carry(uuid)", "public.ottoq_tg_owner_saved_on_run_start()",
               "public.ottoq_owner_settings_guard()", "public.ottoq_owner_saved_settings_guard()",
               "public.ottoq_owner_settings_read(ottoq_agent_principals,jsonb)",
               "public.ottoq_owner_saved_effect(vehicles,text,text,numeric,numeric)"):
        for role in ("anon", "authenticated", "service_role"):
            assert post.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == "f", (fn, role)
    assert post.val("SELECT has_function_privilege('service_role', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE')") == "t"


def test_the_registry_stays_clean_and_the_columns_are_evidence(post):
    assert post.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE severity = 'block'") == "0"
    assert post.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE table_name = 'ottoq_owner_commands'") == "0"
    assert post.val("SELECT class FROM ottoq_run_scope_registry WHERE table_name = 'ottoq_owner_commands'") == "evidence"


def test_the_snapshot_holds_every_body_0721_replaced(post):
    rows = post.rows("SELECT object_name, def_md5 FROM ottoq_schema_snapshots WHERE label = '0721_pre' ORDER BY object_name")
    replaced = list(LIVE_MD5.items())[:5] + [(k, v) for k, v in LIVE_MD5.items()
                                             if k.startswith(("public.ottoq_tg_lift_owner_settings_on_terminal", "public.ottoq_agent_public_call",
                                                              "public.ottoq_owner_board", "public.ottoq_depot_owner_board",
                                                              "ottoq.ottoq_owner_orders_tick"))]
    assert rows == sorted([[k.split("(")[0].split(".")[1], v] for k, v in replaced])


# ─────────────────────────────────────────────── §9-§13: saved settings, the guards, the passcode door, the model ledger ──

def saved(db, car=None):
    """The active saved settings, as (vehicle, kind, value)."""
    where = f" AND vehicle_id = '{car}'" if car else ""
    return sorted((r[0], r[1], r[2]) for r in db.rows(
        "SELECT vehicle_id, kind, coalesce(charge_limit_pct::text, service) FROM ottoq_owner_saved_settings "
        f"WHERE status = 'active'{where}"))


def carried(db, run):
    return sorted((r[0], r[1], r[2]) for r in db.rows(
        "SELECT vehicle_id, kind, coalesce(charge_limit_pct::text, service) FROM ottoq_owner_settings "
        f"WHERE sim_run_id = '{run}' AND status = 'active' AND saved_id IS NOT NULL"))


def lower(db, token, args, transport="mcp"):
    """A lower limit, as a signed-in owner makes one: the preview OTTO-Q records, then its confirm."""
    prev = tcall(db, token, "set_charge_limit", {**args, "mode": "preview"}, transport=transport)
    assert prev["data"]["outcome"] == "previewed", prev
    done = confirm(db, token, prev)
    assert done["data"]["outcome"] == "applied", done
    return done


def test_a_signed_in_owners_limit_and_every_return_order_are_saved_and_carried_onto_every_new_run(post):
    """Chase 2026-10-14: a vehicle owner's settings persist per vehicle, the owner's by contract until the owner changes
    them. Holds and one-time orders belong to their run (a one-time order is consumed when served)."""
    chase = connect(post)["access_token"]
    run = fresh_run(post)
    lim = lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    wash = tcall(post, chase, "request_service", {"vehicles": "all", "service": "exterior_wash", "when": "every_return"})
    assert wash["data"]["outcome"] == "applied" and "This is saved to your cars" in wash["data"]["summary"], wash
    hold = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 60})
    once = tcall(post, chase, "request_service", {"vehicles": ["RT-3"], "service": "interior_tidy", "when": "next_return"})
    for r in (hold, once):
        assert r["data"]["outcome"] == "applied" and "This lasts until the demo run ends or you undo it." in r["data"]["summary"], r
    teslas = sorted(post.text(f"SELECT string_agg(id::text, ',' ORDER BY id) FROM vehicles WHERE fleet_operator_id = '{TESLA}' "
                              f"AND (home_depot_id = '{TWIN}' OR current_depot_id = '{TWIN}')").split(","))
    want = sorted([(AV041, "charge_limit", "85")] + [(v, "service", "exterior_wash") for v in teslas])
    assert saved(post) == want
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND saved_id IS NOT NULL") == str(len(want))
    # my_settings says what is saved, and no longer that everything lifts at the run's end
    ms = tcall(post, chase, "my_settings")["data"]
    assert len(ms["saved"]) == len(want) and all(x["saved_by"] == EMAIL for x in ms["saved"])
    assert "Saved to your cars for every run, production included: 1 car charges to at most 85%; " in ms["summary"]
    assert "Everything lifts when the run ends." not in ms["summary"]
    # the run ends: everything is lifted from the run, the hold and the one-time order with it; the saved commands are not
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND status = 'active'") == "0"
    lifted = dict(post.rows(f"SELECT command_id, coalesce(lifted_reason, '-') FROM ottoq_owner_commands WHERE command_id IN "
                            f"('{lim['data']['command']['command_id']}', '{wash['data']['command']['command_id']}', "
                            f"'{hold['data']['command']['command_id']}', '{once['data']['command']['command_id']}')"))
    assert lifted[lim["data"]["command"]["command_id"]] == "-" and lifted[wash["data"]["command"]["command_id"]] == "-"
    assert lifted[hold["data"]["command"]["command_id"]] == "the run ended (completed)"
    assert lifted[once["data"]["command"]["command_id"]] == "the run ended (completed)"
    none = tcall(post, chase, "my_settings")["data"]
    assert none["summary"].startswith("No run is live, so nothing is in force now. Saved to your cars for every run")
    # the next demo run carries them (and the visit opened on it already has the order), and so does production
    nxt = fresh_run(post, keep_saved=True)
    assert carried(post, nxt) == want
    assert target(post) == "85"
    assert post.val(f"""SELECT count(*) FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                        WHERE n.sim_run_id = '{nxt}' AND n.vehicle_id = '{AV041}' AND a ->> 'svc' = 'exterior_wash'
                          AND (a ->> 'owner_requested')::boolean""") == "1"
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND kind = 'hold'") == "0"
    # carried once: a pause and a resume carry nothing twice
    post.run(f"UPDATE ottoq_sim_runs SET status = 'paused' WHERE sim_run_id = '{nxt}'")
    post.run(f"UPDATE ottoq_sim_runs SET status = 'running' WHERE sim_run_id = '{nxt}'")
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND saved_id IS NOT NULL") == str(len(want))
    prod = production_run(post, keep_saved=True)
    assert carried(post, prod) == want and target(post) == "85"
    # a run that is neither demo nor production carries nothing (no arm ever sees an owner's setting)
    post.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    arm = str(__import__("uuid").uuid4())
    post.run(f"""INSERT INTO ottoq_sim_runs (sim_run_id, depot_id, status, started_at, sim_clock_current, sim_clock_end, run_by)
                 VALUES ('{arm}', '{TWIN}', 'running', clock_timestamp(), '2026-09-27 12:00+00', '2026-09-28 12:00+00', 'cert_harness')""")
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{arm}'") == "0"
    assert post.val(f"SELECT public.ottoq_owner_saved_carry('{arm}')") == "0"
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{arm}'")


def test_a_session_without_a_person_changes_only_its_run_and_never_what_is_saved(post):
    chase = connect(post)["access_token"]
    fresh_run(post)
    lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    nxt = fresh_run(post, keep_saved=True)
    session = unlock(post, agent="Grok", ip="192.0.2.81")["data"]["session"]
    up = tcall(post, session, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 90})
    assert up["data"]["outcome"] == "applied" and "This lasts until the demo run ends" in up["data"]["summary"], up
    assert target(post) == "90" and saved(post, AV041) == [(AV041, "charge_limit", "85")]
    gone = tcall(post, session, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    assert gone["data"]["outcome"] == "applied" and target(post) == "100", gone
    assert saved(post, AV041) == [(AV041, "charge_limit", "85")], "a passcode session's clear is the run's, not the car's"
    # an issued key on a demo run lowers in one call (no person: nothing is saved, so nothing reaches production)
    key = post.json(f"SELECT ottoq_agent_issue_token('fleet-bot-2', 'personal', ARRAY['read','note','owner_settings'], "
                    f"'{TESLA}', '{TWIN}', NULL, 600, 20)")["token"]
    k = tcall(post, key, "set_charge_limit", {"vehicles": ["Tesla 45"], "percent": 82}, transport="rest")
    assert k["data"]["outcome"] == "applied" and k["http_status"] == 201, k
    assert saved(post, AV045) == []
    # the next run carries the owner's 85, whatever the sessions did on this one
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{nxt}'")
    third = fresh_run(post, keep_saved=True)
    assert carried(post, third) == [(AV041, "charge_limit", "85")] and target(post) == "85"


def test_a_signed_in_owner_changes_withdraws_and_undoes_what_is_saved(post):
    chase = connect(post)["access_token"]
    fresh_run(post)
    low = lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    # a raise is one call, and replaces what is saved
    up = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 95})
    assert up["http_status"] == 201 and saved(post, AV041) == [(AV041, "charge_limit", "95")], up
    ended = post.rows(f"SELECT status, ended_reason, ended_by_command_id FROM ottoq_owner_saved_settings "
                      f"WHERE command_id = '{low['data']['command']['command_id']}'")
    assert ended == [["ended", "replaced by a new setting", up["data"]["command"]["command_id"]]]
    # undoing the raise puts the 85 back on the run (it lowers: a preview, then its confirm) and on the car
    undo = tcall(post, chase, "undo_command", {"command_id": up["data"]["command"]["command_id"]})
    assert undo["error"]["code"] == "confirm_required", undo
    back = confirm(post, chase, undo)
    assert back["data"]["outcome"] == "applied" and target(post) == "85", back
    assert saved(post, AV041) == [(AV041, "charge_limit", "85")]
    # clearing, and cancelling an every-return order, end what is saved
    tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"})
    clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    cnc = tcall(post, chase, "cancel_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash"})
    for r in (clr, cnc):
        assert r["data"]["outcome"] == "applied" and "This is saved to your cars" in r["data"]["summary"], r
    assert saved(post, AV041) == []
    nxt = fresh_run(post, keep_saved=True)
    assert carried(post, nxt) == [] and target(post) == "100"
    # an undo on a later run of a command whose setting is still saved says so, and what to do instead
    keep = lower(post, chase, {"vehicles": ["Tesla 45"], "percent": 88})
    later = fresh_run(post, keep_saved=True)
    assert carried(post, later) == [(AV045, "charge_limit", "88")]
    u = tcall(post, chase, "undo_command", {"command_id": keep["data"]["command"]["command_id"]})
    assert u["data"]["outcome"] == "refused" and u["error"]["code"] == "made_on_an_earlier_run", u
    assert "saved to your cars and still in force" in u["error"]["message"] and "clear_charge_limit" in u["error"]["message"]
    assert saved(post, AV045) == [(AV045, "charge_limit", "88")]


def test_the_carry_keeps_to_the_contract_in_force_and_to_the_owners_cars(post):
    chase = connect(post)["access_token"]
    fresh_run(post)
    lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 82})
    tcall(post, chase, "request_service", {"vehicles": ["Tesla 45"], "service": "interior_tidy", "when": "every_return"})
    try:
        # the contract's minimum rose above the saved limit, and it now blocks the service: neither is carried
        post.run(f"UPDATE ottoq_fleet_operator_slas SET min_charge_target_pct = 85, blocked_services = ARRAY['interior_tidy'] "
                 f"WHERE fleet_operator_id = '{TESLA}'")
        nxt = fresh_run(post, keep_saved=True)
        assert carried(post, nxt) == [] and target(post) == "100"
        assert saved(post, AV041) == [(AV041, "charge_limit", "82")], "kept, for when the contract allows it again"
    finally:
        post.run(f"UPDATE ottoq_fleet_operator_slas SET min_charge_target_pct = 80, blocked_services = NULL "
                 f"WHERE fleet_operator_id = '{TESLA}'")
    again = fresh_run(post, keep_saved=True)
    assert carried(post, again) == sorted([(AV041, "charge_limit", "82"), (AV045, "service", "interior_tidy")])
    # a car that is no longer the owner's is not carried
    post.run(f"UPDATE vehicles SET fleet_operator_id = '22222222-2222-2222-2222-222222222222' WHERE id = '{AV045}'")
    try:
        third = fresh_run(post, keep_saved=True)
        assert carried(post, third) == [(AV041, "charge_limit", "82")]
    finally:
        post.run(f"UPDATE vehicles SET fleet_operator_id = '{TESLA}' WHERE id = '{AV045}'")


def test_a_persons_clear_ends_what_is_saved_when_a_session_without_a_person_holds_the_runs_limit(post):
    """The re-review (rule 9, (A)): the run's limit was set by a passcode session, so the run's row is not the saved one. A
    signed-in owner's clear still clears what is saved, and the next production run carries nothing."""
    chase = connect(post)["access_token"]
    fresh_run(post)
    lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    nxt = fresh_run(post, keep_saved=True)
    session = unlock(post, agent="Visitor", ip="192.0.2.94")["data"]["session"]
    assert tcall(post, session, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 90})["data"]["outcome"] == "applied"
    clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    assert clr["http_status"] == 201 and clr["data"]["outcome"] == "applied", clr
    summary = clr["data"]["summary"]
    assert "the limit saved to it cleared: it charges full on every run" in summary, summary
    assert "This is saved to your cars: it stays from run to run, production included, until you change it." in summary
    assert saved(post, AV041) == []
    ended = post.rows(f"SELECT ended_reason, ended_by_command_id FROM ottoq_owner_saved_settings "
                      f"WHERE vehicle_id = '{AV041}' AND kind = 'charge_limit' ORDER BY saved_at DESC LIMIT 1")
    assert ended == [["cleared by the owner", clr["data"]["command"]["command_id"]]]
    assert target(post) == "100"
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{nxt}'")
    prod = production_run(post, keep_saved=True)
    assert carried(post, prod) == [] and target(post) == "100"


def test_a_persons_clear_ends_what_is_saved_when_the_carry_skipped_it(post):
    """The re-review (rule 9, (B)): the contract's minimum rose above the saved limit, so it was not carried and the run has
    no limit row. The clear is applied (not no_change), and nothing comes back when the contract allows it again."""
    chase = connect(post)["access_token"]
    fresh_run(post)
    lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 82})
    try:
        post.run(f"UPDATE ottoq_fleet_operator_slas SET min_charge_target_pct = 85 WHERE fleet_operator_id = '{TESLA}'")
        nxt = fresh_run(post, keep_saved=True)
        assert carried(post, nxt) == [] and saved(post, AV041) == [(AV041, "charge_limit", "82")]
        clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
        assert clr["http_status"] == 201 and clr["data"]["outcome"] == "applied", clr
        keys = sorted(e["key"] for e in clr["data"]["command"]["effects"])
        assert keys == ["charge_limit", "saved:charge_limit"], keys
        assert saved(post, AV041) == []
    finally:
        post.run(f"UPDATE ottoq_fleet_operator_slas SET min_charge_target_pct = 80 WHERE fleet_operator_id = '{TESLA}'")
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{nxt}'")
    prod = production_run(post, keep_saved=True)
    assert carried(post, prod) == [] and target(post) == "100"
    # a second clear finds nothing saved and nothing on the run: no_change, as before
    again = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    assert again["data"]["outcome"] == "no_change", again


def test_a_persons_full_limit_and_cancel_end_what_is_saved_after_a_session_changed_the_run(post):
    """The re-review (rule 9, (D)): a passcode session set 90 and cancelled the carried wash on the run. The signed-in
    owner's limit at the ceiling and cancel of the every-return wash both end what is saved; production carries nothing."""
    chase = connect(post)["access_token"]
    run = fresh_run(post)
    lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"})
    session = unlock(post, agent="Visitor", ip="192.0.2.95")["data"]["session"]
    tcall(post, session, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 90})
    tcall(post, session, "cancel_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash"})
    assert saved(post, AV041) == [(AV041, "charge_limit", "85"), (AV041, "service", "exterior_wash")]
    full = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 100})
    assert full["http_status"] == 201 and full["data"]["outcome"] == "applied", full
    cnc = tcall(post, chase, "cancel_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash"})
    assert cnc["http_status"] == 201 and cnc["data"]["outcome"] == "applied", cnc
    assert "the every-return order for exterior wash saved to it is withdrawn, for every run" in cnc["data"]["summary"], cnc
    assert "This is saved to your cars" in cnc["data"]["summary"]
    assert saved(post, AV041) == []
    reasons = sorted(r[0] for r in post.rows(
        f"SELECT ended_reason FROM ottoq_owner_saved_settings WHERE vehicle_id = '{AV041}' "
        f"AND ended_by_command_id IN ('{full['data']['command']['command_id']}', '{cnc['data']['command']['command_id']}')"))
    assert reasons == ["cancelled by the owner", "cleared by the owner"], reasons
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    prod = production_run(post, keep_saved=True)
    assert carried(post, prod) == [] and target(post) == "100"


def test_a_persons_limit_is_saved_even_when_the_run_already_holds_that_value(post):
    """The same class from the other side: a passcode session set 88 on the run; the signed-in owner then sets 88. The run
    has nothing to change, and the saved 85 is replaced by 88 (a raise, one call), so the next run carries what they set."""
    chase = connect(post)["access_token"]
    fresh_run(post)
    lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    nxt = fresh_run(post, keep_saved=True)
    session = unlock(post, agent="Visitor", ip="192.0.2.96")["data"]["session"]
    tcall(post, session, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 88})
    same = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 88})
    assert same["http_status"] == 201 and same["data"]["outcome"] == "applied", same
    assert "88% is saved to it for every run, in place of 85%" in same["data"]["summary"] or \
           "has 88% saved to it for every run" in same["data"]["summary"], same["data"]["summary"]
    assert saved(post, AV041) == [(AV041, "charge_limit", "88")]
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{nxt}'")
    third = fresh_run(post, keep_saved=True)
    assert carried(post, third) == [(AV041, "charge_limit", "88")] and target(post) == "88"
    # and the plain case is untouched: the carried row is the saved one, and a clear withdraws it with one effect
    clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    assert [e["key"] for e in clr["data"]["command"]["effects"]] == ["charge_limit"], clr
    assert saved(post, AV041) == []


def test_a_passcode_session_reads_no_saved_settings_and_no_persons_email(post):
    """The re-review: what is saved is the account holder's, bound for production, and names the person. A demo passcode
    session and an issued key get no `saved` block and no line about it; the signed-in owner still does."""
    chase = connect(post)["access_token"]
    fresh_run(post)
    lim = lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    session = unlock(post, agent="Visitor", ip="192.0.2.97")["data"]["session"]
    key = post.json(f"SELECT ottoq_agent_issue_token('fleet-bot-3', 'personal', ARRAY['read','note','owner_settings'], "
                    f"'{TESLA}', '{TWIN}', NULL, 600, 20)")["token"]
    for token, transport in ((session, "mcp"), (key, "rest")):
        ms = tcall(post, token, "my_settings", transport=transport)
        blob = json.dumps(ms)
        assert ms["http_status"] == 200, ms
        assert "saved" not in ms["data"], ms["data"]
        # (0605's in-force list names each setting's command id, as it always has, to every principal of the fleet; an id
        # opens nothing: undo and my_commands are per principal. The person's email appears nowhere.)
        assert EMAIL not in blob.lower(), blob
        assert "Saved to your cars" not in ms["data"]["summary"] and "production included" not in ms["data"]["summary"]
        assert "In force on this run: 1 car charges to at most 85%." in ms["data"]["summary"], ms["data"]["summary"]
    own = tcall(post, chase, "my_settings")["data"]
    assert [(x["saved_by"], x["command_id"]) for x in own["saved"]] == [(EMAIL, lim["data"]["command"]["command_id"])]
    assert "Saved to your cars for every run, production included: 1 car charges to at most 85%." in own["summary"]


def _refused(db, sql, why):
    rc, _, err = db.run(sql, check=False)
    assert rc != 0 and why in err, (sql, err)


PLAIN_WRITE = "never by a plain write"


def _refused_both(db, sql, why, writer="owner_command"):
    """Refused twice over (§10): as a plain write, by the writer rule; and with the writer setting forged in the session, as
    a writer function would carry it (a bug in a writer, or a session that sets it by hand), still by the per-move check."""
    _refused(db, sql, PLAIN_WRITE)
    _refused(db, f"SET ottoq.owner_settings_writer = '{writer}';\n{sql}", why)


def test_the_settings_guard_refuses_what_no_applied_command_set(post):
    """Re-review item 10: below the door, whoever writes (the SQL editor and the Management API are postgres)."""
    chase = connect(post)["access_token"]
    run = fresh_run(post)
    done = lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    cid = done["data"]["command"]["command_id"]
    refused = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 60})
    rid = refused["data"]["command"]["command_id"]
    ins = ("INSERT INTO ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, "
           "command_id, set_at_sim) VALUES ('{run}', '{depot}', '{fleet}', '{car}', 'charge_limit', {pct}, '{cmd}', now())")
    for depot, fleet, car, pct, cmd, why in (
            (TWIN, TESLA, AV041, 50, cid, "a value the command did not set"),
            (TWIN, TESLA, AV045, 85, cid, "a car the command did not name"),
            (TWIN, TESLA, AV041, 85, rid, "a refused command"),
            (TWIN, "22222222-2222-2222-2222-222222222222", AV041, 85, cid, "another fleet"),
            (TWIN, TESLA, AV041, 85, "00000000-0000-0000-0000-00000000c0de", "no command at all")):
        sql = ins.format(run=run, depot=depot, fleet=fleet, car=car, pct=pct, cmd=cmd)
        _refused(post, sql, PLAIN_WRITE)
        rc, _, err = post.run(f"SET ottoq.owner_settings_writer = 'owner_command';\n{sql}", check=False)
        assert rc != 0 and ("is not what an applied owner command set" in err or "violates foreign key" in err), (why, err)
    # on another run, only as the carry of a saved row this very command made
    other = fresh_run(post, keep_saved=True)
    for writer in ("owner_command", "carry"):
        _refused_both(post, f"INSERT INTO ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, "
                            f"charge_limit_pct, command_id, set_at_sim) VALUES ('{other}', '{TWIN}', '{TESLA}', '{AV041}', "
                            f"'charge_limit', 85, '{cid}', now())", "is not what an applied owner command set", writer)
    sid = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{other}' AND vehicle_id = '{AV041}' AND kind = 'charge_limit'")
    for sql, why in ((f"UPDATE ottoq_owner_settings SET charge_limit_pct = 50 WHERE setting_id = '{sid}'", "what was set is immutable"),
                     (f"UPDATE ottoq_owner_settings SET status = 'withdrawn', closed_at = now(), closed_reason = 'x' WHERE setting_id = '{sid}'",
                      "replaced or withdrawn only by the applied owner command"),
                     (f"DELETE FROM ottoq_owner_settings WHERE setting_id = '{sid}'", "DELETE refused")):
        if sql.startswith("DELETE"):
            _refused(post, sql, why)
        else:
            _refused_both(post, sql, why)
    _refused_both(post, f"UPDATE ottoq_owner_settings SET status = 'active' WHERE status = 'lifted' AND sim_run_id = '{run}'",
                  "is not a change an owner command, the tick or the run's end makes")
    # the purge (ottoq.retention) still clears a run's settings, as ottoq_purge_prior_runs does
    rc, _, err = post.run(f"SET ottoq.retention = 'on'; DELETE FROM ottoq_owner_settings WHERE sim_run_id = '{run}'", check=False)
    assert rc == 0, err
    # the saved table: no row without a person's applied command, nothing edited, nothing deleted or truncated
    session = unlock(post, agent="Grok", ip="192.0.2.82")["data"]["session"]
    sess = tcall(post, session, "set_charge_limit", {"vehicles": ["Tesla 45"], "percent": 90})
    assert sess["data"]["outcome"] == "applied", sess
    for sql, why in (
            (f"INSERT INTO ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, command_id, "
             f"acting_person) VALUES ('{TWIN}', '{TESLA}', '{AV045}', 'charge_limit', 90, '{sess['data']['command']['command_id']}', "
             f"'{EMAIL}')", "not what an applied command recorded under a person set"),
            (f"UPDATE ottoq_owner_saved_settings SET charge_limit_pct = 50 WHERE command_id = '{cid}'", "what was saved is immutable"),
            (f"UPDATE ottoq_owner_saved_settings SET status = 'ended', ended_at = now(), ended_reason = 'x' WHERE command_id = '{cid}'",
             "ended only by an applied owner command recorded under a person"),
            (f"DELETE FROM ottoq_owner_saved_settings WHERE command_id = '{cid}'", "DELETE refused"),
            ("TRUNCATE ottoq_owner_saved_settings CASCADE", "TRUNCATE")):
        if sql.startswith(("DELETE", "TRUNCATE")):
            _refused(post, sql, why)
        else:
            _refused_both(post, sql, why)
    assert saved(post, AV041) == [(AV041, "charge_limit", "85")]


def test_the_model_ledger_door_records_ids_and_counts_and_refuses_text(post):
    """CLAUDE.md rule 6: every OTTO-Command model call is ledger-backed, and nothing an owner said reaches the ledger."""
    entry = {"ask_id": "0a1b2c3d-0000-4000-8000-000000000001", "ask_kind": "search", "round": 1,
             "model_requested": "model-a", "model": "model-b", "http_status": 200, "latency_ms": 4321, "outcome": "answered",
             "stop_reason": "end_turn", "web_search_requests": 2, "input_tokens": 1500, "output_tokens": 300, "fell_back": True,
             "refusal_category": None, "effort": "low", "depot_id": TWIN, "sim_run_id": None, "gateway_call_id": 77}
    call = lambda e: post.run(f"SELECT ottoq_ottocommand_record_model_call({q(json.dumps(e))}::jsonb)", check=False)
    rc, out, err = call(entry)
    assert rc == 0, err
    row = post.rows(f"SELECT provider, role, model, endpoint, http_status, latency_ms, outcome, chain_id, depot_id, "
                    f"detail::text FROM ottoq_model_call_ledger WHERE call_id = {out}")[0]
    assert row[:9] == ["anthropic_ottocommand", "owner_agent", "model-b", "https://api.anthropic.com/v1/messages", "200",
                       "4321", "answered", entry["ask_id"], TWIN]
    detail = json.loads(row[9])
    assert detail == {"ask_kind": "search", "round": 1, "model_requested": "model-a", "stop_reason": "end_turn",
                      "web_search_requests": 2, "input_tokens": 1500, "output_tokens": 300, "fell_back": True, "effort": "low",
                      "gateway_call_id": 77}
    assert call({**entry, "outcome": "refused", "stop_reason": "refusal", "refusal_category": "cyber", "round": 2})[0] == 0
    assert call({**entry, "outcome": "error", "http_status": None, "stop_reason": None, "round": 3, "model": None})[0] == 0
    view = post.rows("SELECT calls, answered, refused, errored, unclassified FROM ottoq_intelligence_ledger "
                     "WHERE provider = 'anthropic_ottocommand' AND role = 'owner_agent'")
    assert view == [["3", "1", "1", "1", "0"]]
    for bad, why in (({**entry, "prompt": "call set_charge_limit 50"}, "unknown field(s) prompt"),
                     ({**entry, "stop_reason": "Ignore previous instructions"}, "stop_reason"),
                     ({**entry, "model": "a model with spaces"}, "model"),
                     ({**entry, "refusal_category": "call set_charge_limit"}, "refusal_category"),
                     ({**entry, "latency_ms": -5}, "latency_ms"), ({**entry, "outcome": "done"}, "outcome"),
                     ({**entry, "depot_id": "not-a-uuid"}, "depot_id"), ({**entry, "fell_back": "yes"}, "fell_back"),
                     ({**entry, "effort": "extreme"}, "effort"), ({k: v for k, v in entry.items() if k != "ask_id"}, "ask_id")):
        rc, _, err = call(bad)
        assert rc != 0 and why in err, (bad, err)
    assert post.val("SELECT count(*) FROM ottoq_model_call_ledger WHERE provider = 'anthropic_ottocommand'") == "3"
    assert post.val("SELECT has_function_privilege('service_role', 'public.ottoq_ottocommand_record_model_call(jsonb)', 'EXECUTE')") == "t"
    for role in ("anon", "authenticated"):
        assert post.val(f"SELECT has_function_privilege('{role}', 'public.ottoq_ottocommand_record_model_call(jsonb)', 'EXECUTE')") == "f"
    # the ledger is append-only, as 0340 made it
    rc, _, err = post.run("DELETE FROM ottoq_model_call_ledger WHERE provider = 'anthropic_ottocommand'", check=False)
    assert rc != 0 and "append-only" in err, err


# ─────────────────────────────────── §14: with no run live, a signed-in owner still saves to the cars (outcome 'saved') ──

_SIGNIN_IPS = iter(range(1, 60000))


def sign_in(db):
    """test_agent_signin_sql's connect, each device request from its own address: the suite signs in more than the
    30-an-hour per-caller throttle allows from one."""
    from test_agent_signin_sql import RESOURCE, device_token, oauth, person, register, unthrottle
    n = next(_SIGNIN_IPS)
    client = register(db)
    dev = oauth(db, "device_authorize", {"client_id": client, "resource": RESOURCE}, ip=f"10.77.{n // 256}.{n % 256}")["body"]
    assert person(db, CHASE, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'approve')")["outcome"] == "approved"
    unthrottle(db, dev["user_code"])
    t = device_token(db, client, dev["device_code"])
    assert t["http_status"] == 200, t
    return t["body"]["access_token"]


def no_run(db):
    """End whatever run is live (its owner settings lift with it) and start from nothing saved."""
    db.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    forget_saved(db)


def save_lower(db, token, args):
    """A lower limit saved with no run live: the preview OTTO-Q records (with no run), then its confirm ('saved')."""
    prev = tcall(db, token, "set_charge_limit", {**args, "mode": "preview"})
    assert prev["data"]["outcome"] == "previewed", prev
    assert db.val(f"SELECT sim_run_id IS NULL FROM ottoq_owner_commands WHERE command_id = '{prev['data']['command']['command_id']}'") == "t"
    done = confirm(db, token, prev)
    assert done["data"]["outcome"] == "saved" and done["http_status"] == 201, done
    return done


def settings_rows(db):
    return db.val("SELECT count(*) FROM ottoq_owner_settings")


def ended(db, command_id):
    """The saved rows a command ended: (vehicle, kind, value, ended_reason)."""
    return sorted((r[0], r[1], r[2], r[3]) for r in db.rows(
        "SELECT vehicle_id, kind, coalesce(charge_limit_pct::text, service), ended_reason FROM ottoq_owner_saved_settings "
        f"WHERE ended_by_command_id = '{command_id}'"))


def test_with_no_run_live_a_signed_in_owner_saves_a_charge_limit_set_raised_at_the_ceiling_and_cleared(post):
    no_run(post)
    chase = sign_in(post)
    rows_before = settings_rows(post)
    who = tcall(post, chase, "whoami")["data"]["owner"]
    assert who["live_demo_run"] is None and who["live_production_run"] is None
    ch = who["changes"]
    assert ch["allowed"] is True and ch["run_kind"] == "none" and ch["saved_only"] is True and ch["person"] == EMAIL
    assert ch["lower_limit_needs_preview"] is True and ch["confirm_window_minutes"] == 15
    assert ch["message"].startswith(f"No run is live at the twin depot. You are signed in as {EMAIL}, so you can still save")
    # a lower limit in one call is recorded as a preview, with no run, and answered confirm_required: nothing is saved
    low = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 85})
    assert low["http_status"] == 422 and low["error"]["code"] == "confirm_required", low
    assert low["data"]["refusal"]["reason"] == "not_named" and low["data"]["outcome"] == "previewed"
    prev_id = low["data"]["command"]["command_id"]
    assert post.rows(f"SELECT outcome, coalesce(sim_run_id::text, '-'), acting_person, via FROM ottoq_owner_commands "
                     f"WHERE command_id = '{prev_id}'") == [["previewed", "-", EMAIL, "direct"]]
    assert saved(post, AV041) == []
    # its confirm, from the same agent, saves 85% to the car and writes no run's settings
    done = confirm(post, chase, low)
    assert done["http_status"] == 201 and done["data"]["outcome"] == "saved", done
    cmd = done["data"]["command"]
    assert cmd["via"] == "confirm" and cmd["confirms_command_id"] == prev_id and cmd["acting_person"] == EMAIL
    assert post.rows(f"SELECT outcome, coalesce(sim_run_id::text, '-'), mode FROM ottoq_owner_commands "
                     f"WHERE command_id = '{cmd['command_id']}'") == [["saved", "-", "apply"]]
    assert saved(post, AV041) == [(AV041, "charge_limit", "85")]
    assert settings_rows(post) == rows_before, "a command with no run live writes the saved table only"
    assert done["data"]["summary"].startswith("Done. Tesla-AV-041: 85% is saved to it for every run.")
    assert "No run is live: this is saved to your cars, applies from the next demo or production run" in done["data"]["summary"]
    assert done["data"]["expires"].startswith("Made while no run was live: it changes what is saved to the cars")
    assert "confirmation_code" not in done["data"] and "undo" not in done["data"]
    assert post.rows(f"SELECT http_status, transport FROM ottoq_agent_call_ledger WHERE call_id = {done['call_id']}") == [["201", "confirm"]]
    # the same confirm again saves nothing more
    again = confirm(post, chase, low)
    assert again["data"]["outcome"] != "saved" and saved(post, AV041) == [(AV041, "charge_limit", "85")], again
    # a raise is one call and replaces what is saved; the same value again changes nothing
    up = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 95})
    assert up["http_status"] == 201 and up["data"]["outcome"] == "saved" and up["data"]["command"]["via"] == "direct", up
    assert saved(post, AV041) == [(AV041, "charge_limit", "95")]
    assert ended(post, up["data"]["command"]["command_id"]) == [(AV041, "charge_limit", "85", "replaced by a new setting")]
    same = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 95})
    assert same["http_status"] == 200 and same["data"]["outcome"] == "no_change", same
    assert same["data"]["summary"] == "Nothing to change. Tesla-AV-041 already has 95% saved to it for every run; nothing changes."
    # a limit at the ceiling is one call and clears what is saved: the car charges full on every run
    full = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 100})
    assert full["http_status"] == 201 and full["data"]["outcome"] == "saved", full
    assert saved(post, AV041) == []
    assert ended(post, full["data"]["command"]["command_id"]) == [(AV041, "charge_limit", "95", "cleared by the owner")]
    # clearing with nothing saved changes nothing; a lower limit again, then clear_charge_limit, ends it
    nothing = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    assert nothing["data"]["outcome"] == "no_change", nothing
    both = save_lower(post, chase, {"vehicles": ["Tesla 41", "Tesla 45"], "percent": 88})
    assert both["data"]["command"]["cars"] == 2
    assert saved(post) == [(AV041, "charge_limit", "88"), (AV045, "charge_limit", "88")]
    clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 41"]})
    assert clr["data"]["outcome"] == "saved" and saved(post) == [(AV045, "charge_limit", "88")], clr
    assert ended(post, clr["data"]["command"]["command_id"]) == [(AV041, "charge_limit", "88", "cleared by the owner")]
    # what is saved reads in my_settings with no run live
    ms = tcall(post, chase, "my_settings")["data"]
    assert ms["summary"] == ("No run is live, so nothing is in force now. Saved to your cars for every run, production "
                             "included: 1 car charges to at most 88%.")
    assert settings_rows(post) == rows_before


def test_with_no_run_live_a_lowering_binds_only_its_own_recent_preview_and_a_run_starting_in_between_changes_the_plan(post):
    no_run(post)
    chase = sign_in(post)
    other = sign_in(post)
    p = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 80, "mode": "preview"})
    # another agent signed in to the same account cannot confirm it
    o = confirm(post, other, p)
    assert o["error"]["code"] == "confirm_required" and o["data"]["refusal"]["reason"] == "no_recorded_preview", o
    assert o["error"]["message"].startswith("A lower charge limit you set while signed in is saved to your cars")
    assert "This agent recorded no such preview while no run was live." in o["error"]["message"]
    # older than 15 minutes, it binds nothing
    age(post, p["data"]["command"]["command_id"], "16 minutes")
    old = confirm(post, chase, p)
    assert old["error"]["code"] == "confirm_required" and old["data"]["refusal"]["reason"] == "preview_expired", old
    assert saved(post, AV041) == []
    # a preview made with no run, confirmed once a run is live, is a different plan (the run is in its hash)
    p2 = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 80, "mode": "preview"})
    run = fresh_run(post)
    late = confirm(post, chase, p2)
    assert late["data"]["outcome"] == "refused" and late["error"]["code"] == "plan_changed", late
    assert saved(post, AV041) == [] and target(post) == "100"
    # and one made on a run, confirmed after it ended, likewise
    p3 = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 80, "mode": "preview"})
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    after = confirm(post, chase, p3)
    assert after["data"]["outcome"] == "refused" and after["error"]["code"] == "plan_changed", after
    assert saved(post, AV041) == []


def test_with_no_run_live_an_every_return_order_is_saved_and_withdrawn_and_nothing_else_is_a_change(post):
    no_run(post)
    chase = sign_in(post)
    rows_before = settings_rows(post)
    wash = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41", "Tesla 45"], "service": "exterior_wash",
                                                  "when": "every_return"})
    assert wash["http_status"] == 201 and wash["data"]["outcome"] == "saved", wash
    assert saved(post) == [(AV041, "service", "exterior_wash"), (AV045, "service", "exterior_wash")]
    assert "on every return, from the next demo or production run on" in wash["data"]["summary"]
    again = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"})
    assert again["http_status"] == 200 and again["data"]["outcome"] == "no_change", again
    # a hold, a one-time order and an undo belong to a run
    for tool, args in [("hold_vehicle", {"vehicles": ["Tesla 41"], "for_minutes": 30}),
                       ("request_service", {"vehicles": ["Tesla 41"], "service": "interior_tidy", "when": "next_return"}),
                       ("request_service", {"vehicles": ["Tesla 41"], "service": "interior_tidy"}),
                       ("release_hold", {"vehicles": ["Tesla 41"]}),
                       ("undo_command", {"command_id": wash["data"]["command"]["command_id"]})]:
        r = tcall(post, chase, tool, args)
        assert r["http_status"] == 422 and r["error"]["code"] == "needs_a_live_run", (tool, r)
        assert r["error"]["message"].startswith("No run is live at the twin depot, and ")
        assert r["data"]["outcome"] == "refused"
    # withdrawing one car's saved order is one call, and ends only that row
    cnc = tcall(post, chase, "cancel_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash"})
    assert cnc["http_status"] == 201 and cnc["data"]["outcome"] == "saved", cnc
    assert saved(post) == [(AV045, "service", "exterior_wash")]
    assert ended(post, cnc["data"]["command"]["command_id"]) == [(AV041, "service", "exterior_wash", "cancelled by the owner")]
    none_left = tcall(post, chase, "cancel_service", {"vehicles": ["Tesla 41"]})
    assert none_left["data"]["outcome"] == "no_change", none_left
    assert settings_rows(post) == rows_before
    assert post.val("SELECT count(*) FROM ottoq_owner_commands WHERE outcome = 'saved' AND (sim_run_id IS NOT NULL OR acting_person IS NULL)") == "0"


def test_with_no_run_live_a_passcode_session_and_an_issued_key_name_no_person_and_save_nothing(post):
    no_run(post)
    session = unlock(post, agent="Grok", ip="192.0.2.74")["data"]["session"]
    key = post.json(f"SELECT ottoq_agent_issue_token('fleet-bot-14', 'personal', ARRAY['read','note','owner_settings'], "
                    f"'{TESLA}', '{TWIN}', NULL, 600, 20)")["token"]
    for token, hint in [(session, "A passcode session names no person, so it cannot save a setting to your cars while no run is live."),
                        (key, "An issued key names no person, so it cannot save a setting to your cars while no run is live.")]:
        who = tcall(post, token, "whoami")["data"]["owner"]["changes"]
        assert who["allowed"] is False and who["code"] == "no_live_demo" and who["hint"].startswith(hint), who
        for tool, args in [("set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 90}),
                           ("request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"}),
                           ("clear_charge_limit", {"vehicles": ["Tesla 41"]})]:
            r = tcall(post, token, tool, args)
            assert r["http_status"] == 422 and r["error"]["code"] == "no_live_demo" and r["error"]["hint"].startswith(hint), r
            assert command(post, r["data"]["command"]["command_id"]) == ["refused", "-", "direct"]
    assert saved(post) == []


def test_what_is_saved_with_no_run_live_is_carried_onto_the_next_demo_and_production_run(post):
    """The next operator_demo or production_live run carries a 'saved' command's rows exactly as it carries any saved row
    (§9): the engine reads the limit, the visit gets the order, the run's end lifts them from the run and not from the car."""
    no_run(post)
    chase = sign_in(post)
    lim = save_lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 85})
    wash = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"})
    assert wash["data"]["outcome"] == "saved", wash
    want = [(AV041, "charge_limit", "85"), (AV041, "service", "exterior_wash")]
    assert saved(post, AV041) == want
    demo = fresh_run(post, keep_saved=True)
    assert carried(post, demo) == want and target(post) == "85"
    assert post.val(f"""SELECT count(*) FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                        WHERE n.sim_run_id = '{demo}' AND n.vehicle_id = '{AV041}' AND a ->> 'svc' = 'exterior_wash'
                          AND (a ->> 'owner_requested')::boolean""") == "1"
    # each carried row names the 'saved' command that set it
    assert sorted(post.rows(f"SELECT c.outcome, coalesce(c.sim_run_id::text, '-') FROM ottoq_owner_settings o "
                            f"JOIN ottoq_owner_commands c ON c.command_id = o.command_id "
                            f"WHERE o.sim_run_id = '{demo}' AND o.saved_id IS NOT NULL")) == [["saved", "-"], ["saved", "-"]]
    # an undo of a 'saved' command on a run says it was made with no run live, and what to do instead
    u = tcall(post, chase, "undo_command", {"command_id": wash["data"]["command"]["command_id"]})
    assert u["data"]["outcome"] == "refused" and u["error"]["code"] == "made_with_no_run_live", u
    assert "clear_charge_limit" in u["error"]["message"] and "cancel_service" in u["error"]["message"]
    # the run ends: lifted from the run, not from the car, and the 'saved' commands are not stamped lifted
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{demo}'")
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{demo}' AND status = 'active'") == "0"
    assert post.rows(f"SELECT coalesce(lifted_reason, '-') FROM ottoq_owner_commands WHERE command_id IN "
                     f"('{lim['data']['command']['command_id']}', '{wash['data']['command']['command_id']}')") == [["-"], ["-"]]
    assert saved(post, AV041) == want
    # production carries it too, and a person's raise there ends the saved 85 (the carried row's command was 'saved')
    prod = production_run(post, keep_saved=True)
    assert carried(post, prod) == want and target(post) == "85"
    up = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 41"], "percent": 92})
    assert up["data"]["outcome"] == "applied" and target(post) == "92", up
    assert saved(post, AV041) == [(AV041, "charge_limit", "92"), (AV041, "service", "exterior_wash")]
    assert ended(post, up["data"]["command"]["command_id"]) == [(AV041, "charge_limit", "85", "replaced by a new setting")]
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{prod}'")


def test_the_saved_outcome_is_held_by_its_checks_and_the_guards_admit_it_only_where_they_admit_an_applied_one(post):
    no_run(post)
    chase = sign_in(post)
    s = save_lower(post, chase, {"vehicles": ["Tesla 45"], "percent": 86})
    cid = s["data"]["command"]["command_id"]
    pid = post.val(f"SELECT principal_id FROM ottoq_owner_commands WHERE command_id = '{cid}'")
    run = fresh_run(post, keep_saved=True)
    base = (f"INSERT INTO ottoq_owner_commands (principal_id, principal_name, fleet_operator_id, depot_id, sim_run_id, tool, "
            f"mode, outcome, summary, acting_person) VALUES ('{pid}', 'probe', '{TESLA}', '{TWIN}', ")
    # 'saved' is an apply with no run and a person, and nothing else
    for run_id, mode, person in [(f"'{run}'", "apply", f"'{EMAIL}'"), ("NULL", "apply", "NULL"), ("NULL", "preview", f"'{EMAIL}'")]:
        rc, _, err = post.run(base + f"{run_id}, 'set_charge_limit', '{mode}', 'saved', 'probe', {person})", check=False)
        assert rc != 0 and "violates check constraint" in err, (run_id, mode, person, err)
    defs = post.text("SELECT string_agg(pg_get_constraintdef(oid), ' | ' ORDER BY conname) FROM pg_constraint "
                     "WHERE conrelid = 'ottoq_owner_commands'::regclass AND conname IN "
                     "('ottoq_owner_commands_mode_outcome_check', 'ottoq_owner_commands_saved_check')")
    assert "'saved'::text" in defs and "sim_run_id IS NULL" in defs, defs
    # the saved table refuses a row a 'saved' command did not set (another car, another value)
    _refused_both(post, f"INSERT INTO ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, "
                        f"command_id, acting_person) VALUES ('{TWIN}', '{TESLA}', '{AV041}', 'charge_limit', 86, '{cid}', '{EMAIL}')",
                  "not what an applied command recorded under a person set")
    # and the run's settings refuse a row a 'saved' command names on a run other than as the carry of its saved row
    for writer in ("owner_command", "carry"):
        _refused_both(post, f"INSERT INTO ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, "
                            f"charge_limit_pct, command_id, set_at_sim) VALUES ('{run}', '{TWIN}', '{TESLA}', '{AV045}', "
                            f"'charge_limit', 86, '{cid}', now())", "not what an applied owner command set", writer)
    assert carried(post, run) == [(AV045, "charge_limit", "86")]
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")


# ───────────────────────────────────── the review, round 1: each owner-table move only from the writer that makes it ──

def test_no_plain_write_reaches_the_owner_tables_as_postgres_or_service_role(post):
    """The review, round 1, guidance (b): every write to the owner tables comes from a function that makes owner settings,
    named for its own call (ottoq.owner_settings_writer, a function-level setting). A plain INSERT, UPDATE, DELETE or
    TRUNCATE is refused on both tables as postgres (the SQL editor, the Management API) and as service_role, and the
    setting is not left on after an owner command returns: a write in the same transaction, right after the command, is
    refused too, though it names that very command (which every per-move check alone would have admitted)."""
    no_run(post)
    chase = sign_in(post)
    saved_cmd = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"})
    assert saved_cmd["data"]["outcome"] == "saved", saved_cmd
    run = production_run(post, keep_saved=True)
    lim = lower(post, chase, {"vehicles": ["Tesla 45"], "percent": 95})
    assert lim["data"]["outcome"] == "applied", lim
    cid = lim["data"]["command"]["command_id"]
    sid = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND vehicle_id = '{AV045}' "
                   f"AND kind = 'charge_limit' AND status = 'active'")
    svid = post.val(f"SELECT saved_id FROM ottoq_owner_saved_settings WHERE vehicle_id = '{AV045}' AND status = 'active'")
    assert sid and svid
    # the writers name themselves, and nothing else does
    assert sorted(tuple(r) for r in post.rows(
        "SELECT p.oid::regprocedure::text, c FROM pg_proc p CROSS JOIN LATERAL unnest(p.proconfig) c "
        "WHERE c LIKE 'ottoq.owner_settings_writer=%'")) == sorted([
            ("ottoq.ottoq_owner_orders_tick(uuid,timestamp with time zone)", "ottoq.owner_settings_writer=tick"),
            ("ottoq_owner_command(ottoq_agent_principals,text,jsonb,text)", "ottoq.owner_settings_writer=owner_command"),
            ("ottoq_owner_saved_carry(uuid)", "ottoq.owner_settings_writer=carry"),
            ("ottoq_tg_lift_owner_settings_on_terminal()", "ottoq.owner_settings_writer=run_end")])
    settings = {
        "INSERT": (f"INSERT INTO ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, "
                   f"command_id, set_at_sim) VALUES ('{run}', '{TWIN}', '{TESLA}', '{AV045}', 'charge_limit', 95, '{cid}', now())"),
        "UPDATE": f"UPDATE ottoq_owner_settings SET pending_reconcile = true WHERE setting_id = '{sid}'",
        "UPDATE status": (f"UPDATE ottoq_owner_settings SET status = 'withdrawn', closed_at = now(), closed_reason = 'x', "
                          f"closed_by_command_id = '{cid}' WHERE setting_id = '{sid}'"),
        "DELETE": f"DELETE FROM ottoq_owner_settings WHERE setting_id = '{sid}'",
        "TRUNCATE": "TRUNCATE ottoq_owner_settings",
    }
    saved_t = {
        "INSERT": (f"INSERT INTO ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, "
                   f"command_id, acting_person) VALUES ('{TWIN}', '{TESLA}', '{AV045}', 'charge_limit', 95, '{cid}', '{EMAIL}')"),
        "UPDATE": (f"UPDATE ottoq_owner_saved_settings SET status = 'ended', ended_at = now(), ended_reason = 'x', "
                   f"ended_by_command_id = '{cid}' WHERE saved_id = '{svid}'"),
        "DELETE": f"DELETE FROM ottoq_owner_saved_settings WHERE saved_id = '{svid}'",
        # a plain TRUNCATE of the saved table stops at the run settings' foreign key first; CASCADE reaches both triggers
        "TRUNCATE": "TRUNCATE ottoq_owner_saved_settings CASCADE",
    }
    want = {"INSERT": "never by a plain write", "UPDATE": "never by a plain write", "UPDATE status": "never by a plain write",
            "DELETE": "DELETE refused", "TRUNCATE": "TRUNCATE refused"}
    refused = 0
    for table, stmts in (("ottoq_owner_settings", settings), ("ottoq_owner_saved_settings", saved_t)):
        for op, sql in stmts.items():
            _refused(post, sql, want[op])
            rc, _, err = post.run(sql, role="service_role", check=False)
            assert rc != 0 and "permission denied" in err, (table, op, err)
            refused += 2
    assert refused == 18
    _refused(post, "TRUNCATE ottoq_owner_saved_settings", "cannot truncate a table referenced in a foreign key constraint")
    # the setting is the command's own call only: right after an owner command, in the same transaction, a write naming
    # that very command (which the per-move checks admit: applied, in this transaction, names the car, a tool that
    # withdraws a limit) is refused
    rc, _, err = post.run(f"""DO $t$ DECLARE r jsonb; BEGIN
        r := ottoq_agent_call({q(sha(chase))}, 'set_charge_limit', '{{"vehicles": ["Tesla 45"], "percent": 96}}'::jsonb, 'mcp', '{{}}'::jsonb);
        IF r #>> '{{data,outcome}}' IS DISTINCT FROM 'applied' THEN RAISE EXCEPTION 'setup: %', r; END IF;
        UPDATE ottoq_owner_settings SET status = 'withdrawn', closed_at = now(), closed_reason = 'x',
               closed_by_command_id = (r #>> '{{data,command,command_id}}')::uuid
         WHERE sim_run_id = '{run}' AND vehicle_id = '{AV045}' AND kind = 'charge_limit' AND status = 'active';
      END $t$""", check=False)
    assert rc != 0 and "never by a plain write" in err, err
    assert post.val("SELECT current_setting('ottoq.owner_settings_writer', true)") in (None, "", "None")
    # nothing moved: the limit, what is saved, and the carried order all stand
    assert post.val(f"SELECT charge_limit_pct FROM ottoq_owner_settings WHERE setting_id = '{sid}' AND status = 'active'") == "95"
    assert saved(post, AV045) == [(AV045, "charge_limit", "95")] and target(post, AV045) == "95"
    assert [c for c in carried(post, run) if c[0] == AV041] == [(AV041, "service", "exterior_wash")]
    # and the writers still write: the tick reconciles, a command withdraws, the run's end lifts
    post.val(f"SELECT ottoq.ottoq_owner_orders_tick('{run}', '2026-09-27 12:01+00')")
    clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 45"]})
    assert clr["data"]["outcome"] == "applied" and target(post, AV045) == "100", clr
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND status = 'active'") == "0"


def test_the_run_settings_guard_admits_each_move_only_from_the_writer_that_makes_it(post):
    """The review, round 1 (G4, G5, G3), with no unlock, as postgres (the SQL editor and the Management API): a person's
    raise cannot be undone by two bare UPDATEs that put the lower limit back (the next production run would carry it, rule
    9); an every-return order cannot be marked fulfilled; a one-time order only once its service is done, a hold only once
    its time has come, a lift only at the run's end; and TRUNCATE is refused."""
    chase = sign_in(post)
    run = production_run(post)
    lower(post, chase, {"vehicles": ["Tesla 45"], "percent": 82})
    up = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 45"], "percent": 95})
    assert up["data"]["outcome"] == "applied" and saved(post, AV045) == [(AV045, "charge_limit", "95")], up
    wash = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "every_return"})
    unrelated = wash["data"]["command"]["command_id"]
    r95 = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND vehicle_id = '{AV045}' "
                   f"AND kind = 'charge_limit' AND status = 'active'")
    r82 = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND vehicle_id = '{AV045}' "
                   f"AND kind = 'charge_limit' AND status = 'replaced'")
    withdraw = ("UPDATE ottoq_owner_settings SET status = 'withdrawn', closed_at = now(), closed_reason = 'x', "
                "closed_by_command_id = '{cmd}' WHERE setting_id = '{sid}'")
    # G4: withdrawn "by" an unrelated command of the fleet, and "by" the raise itself (it names the car, but recorded in an
    # earlier transaction); then the replaced 82 put back with no undo
    _refused_both(post, withdraw.format(cmd=unrelated, sid=r95), "replaced or withdrawn only by the applied owner command")
    _refused_both(post, withdraw.format(cmd=up["data"]["command"]["command_id"], sid=r95), "replaced or withdrawn only by the applied owner command")
    for writer in ("owner_command", "tick"):
        _refused_both(post, f"UPDATE ottoq_owner_settings SET status = 'active', closed_at = NULL, closed_reason = NULL, "
                            f"closed_by_command_id = NULL WHERE setting_id = '{r82}'", "put back only by an undo", writer)
    assert saved(post, AV045) == [(AV045, "charge_limit", "95")] and target(post, AV045) == "95"
    assert post.val("SELECT count(*) FROM ottoq_owner_commands WHERE tool = 'undo_command' AND outcome = 'applied' "
                    f"AND undoes_command_id = '{up['data']['command']['command_id']}'") == "0"
    # G3: TRUNCATE is refused, plain and cascading
    for sql in ("TRUNCATE ottoq_owner_settings", "TRUNCATE ottoq_owner_settings CASCADE"):
        _refused(post, sql, "TRUNCATE refused")
    nxt = production_run(post, keep_saved=True)
    assert [c for c in carried(post, nxt) if c[0] == AV045] == [(AV045, "charge_limit", "95")] and target(post, AV045) == "95"
    # G5: an every-return order is never fulfilled; a one-time order only once its service is done; a hold only once its
    # time has come; a lift only at the run's end
    every = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND vehicle_id = '{AV041}' "
                     f"AND kind = 'service' AND status = 'active'")
    _refused_both(post, f"UPDATE ottoq_owner_settings SET status = 'fulfilled', closed_at = now() WHERE setting_id = '{every}'",
                  "fulfilled only by the tick", "tick")
    once = tcall(post, chase, "request_service", {"vehicles": ["Tesla 45"], "service": "interior_tidy", "when": "now"})
    hold = tcall(post, chase, "hold_vehicle", {"vehicles": ["Tesla 45"], "for_minutes": 60})
    assert once["data"]["outcome"] == "applied" and hold["data"]["outcome"] == "applied", (once, hold)
    oid = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND vehicle_id = '{AV045}' "
                   f"AND kind = 'service' AND service = 'interior_tidy' AND status = 'active'")
    hid = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND vehicle_id = '{AV045}' "
                   f"AND kind = 'hold' AND status = 'active'")
    _refused_both(post, f"UPDATE ottoq_owner_settings SET status = 'fulfilled', closed_at = now() WHERE setting_id = '{oid}'",
                  "fulfilled only by the tick", "tick")
    _refused_both(post, f"UPDATE ottoq_owner_settings SET status = 'fulfilled', closed_at = now(), closed_at_sim = set_at_sim "
                        f"WHERE setting_id = '{hid}'", "fulfilled only by the tick", "tick")
    _refused_both(post, f"UPDATE ottoq_owner_settings SET status = 'lifted', closed_at = now() WHERE setting_id = '{every}'",
                  "lifted only when its run ends", "run_end")
    # and each move only from its own writer: the owner command cannot fulfil or lift, the tick cannot withdraw
    _refused(post, f"SET ottoq.owner_settings_writer = 'owner_command'; UPDATE ottoq_owner_settings SET status = 'fulfilled', "
                   f"closed_at = now(), closed_at_sim = hold_until_sim WHERE setting_id = '{hid}'", "fulfilled only by the tick")
    _refused(post, f"SET ottoq.owner_settings_writer = 'tick'; UPDATE ottoq_owner_settings SET status = 'withdrawn', closed_at = now(), "
                   f"closed_reason = 'x', closed_by_command_id = '{hold['data']['command']['command_id']}' WHERE setting_id = '{hid}'",
             "replaced or withdrawn only by the applied owner command")
    # the tick still does both: the order goes onto the visit, its service is done, and the hold's time comes
    assert int(post.val(f"SELECT ottoq.ottoq_owner_orders_tick('{nxt}', '2026-09-27 12:01+00')")) >= 1
    post.run(f"""UPDATE ottoq_visit_needs SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = 'interior_tidy' THEN a || '{{"status":"done"}}' ELSE a END)
                                                        FROM jsonb_array_elements(atoms) a)
                 WHERE vehicle_id = '{AV045}' AND sim_run_id = '{nxt}'""")
    post.val(f"SELECT ottoq.ottoq_owner_orders_tick('{nxt}', '2026-09-27 13:01+00')")
    assert post.rows(f"SELECT status FROM ottoq_owner_settings WHERE setting_id IN ('{oid}', '{hid}')") == [["fulfilled"], ["fulfilled"]]
    # and the run's end lifts the rest
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{nxt}'")
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{nxt}' AND status = 'active'") == "0"
    assert post.val(f"SELECT status FROM ottoq_owner_settings WHERE setting_id = '{every}'") == "lifted"


def test_a_saved_row_comes_back_only_by_an_undo_and_is_never_written_again_from_an_old_command(post):
    """The review, round 1 (G1, G2): a person saved 82 with no run live and then cleared it. A bare UPDATE that ends the
    end, or an INSERT naming the old command, would put 82 back on the next production run (rule 9). Both are refused, and
    how a saved row ended is immutable."""
    no_run(post)
    chase = sign_in(post)
    ok = save_lower(post, chase, {"vehicles": ["Tesla 45"], "percent": 82})
    clr = tcall(post, chase, "clear_charge_limit", {"vehicles": ["Tesla 45"]})
    assert clr["data"]["outcome"] == "saved" and saved(post, AV045) == [], clr
    sid = post.val(f"SELECT saved_id FROM ottoq_owner_saved_settings WHERE command_id = '{ok['data']['command']['command_id']}'")
    _refused_both(post, f"UPDATE ottoq_owner_saved_settings SET status = 'active', ended_at = NULL, ended_reason = NULL, "
                        f"ended_by_command_id = NULL WHERE saved_id = '{sid}'", "put back only by an undo")
    _refused_both(post, f"UPDATE ottoq_owner_saved_settings SET ended_reason = 'x' WHERE saved_id = '{sid}'", "how it ended is immutable")
    _refused_both(post, f"INSERT INTO ottoq_owner_saved_settings (depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, "
                   f"command_id, acting_person) VALUES ('{TWIN}', '{TESLA}', '{AV045}', 'charge_limit', 82, "
                        f"'{ok['data']['command']['command_id']}', '{EMAIL}')", "not what an applied command recorded under a person set")
    # nor on a run: the command that set 82 cannot write it onto a run outside its own transaction
    prod = production_run(post, keep_saved=True)
    for writer in ("owner_command", "carry"):
        _refused_both(post, f"INSERT INTO ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, charge_limit_pct, "
                            f"command_id, set_at_sim) VALUES ('{prod}', '{TWIN}', '{TESLA}', '{AV045}', 'charge_limit', 82, "
                            f"'{ok['data']['command']['command_id']}', now())", "not what an applied owner command set", writer)
    assert saved(post, AV045) == [] and carried(post, prod) == [] and target(post, AV045) == "100"
    # the one way back is the undo the guard admits, which the owner door makes: on a run, a person's raise and its undo
    lim = lower(post, chase, {"vehicles": ["Tesla 45"], "percent": 85})
    up = tcall(post, chase, "set_charge_limit", {"vehicles": ["Tesla 45"], "percent": 95})
    undo = tcall(post, chase, "undo_command", {"command_id": up["data"]["command"]["command_id"]})
    back = confirm(post, chase, undo)
    assert back["data"]["outcome"] == "applied" and target(post, AV045) == "85", back
    assert saved(post, AV045) == [(AV045, "charge_limit", "85")]
    assert post.val(f"SELECT status FROM ottoq_owner_saved_settings WHERE command_id = '{lim['data']['command']['command_id']}'") == "active"
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{prod}'")


def test_a_one_time_order_is_an_extra_service_and_never_ends_a_saved_every_return_order(post):
    """The review, round 1 (rule 9 and 11): a person's every-return wash is saved to the car. On a later run they ask for a
    wash now, and for a tidy on the next return over a saved every-return tidy. Neither ends what is saved: a new demo run
    and a new production run carry both, the receipt says so, and on the run itself each every-return order is back once
    the one-time order is done. A passcode session doing the same leaves it saved too (unchanged)."""
    no_run(post)
    chase = sign_in(post)
    for svc in ("exterior_wash", "interior_tidy"):
        s = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": svc, "when": "every_return"})
        assert s["data"]["outcome"] == "saved", s
    want = [(AV041, "service", "exterior_wash"), (AV041, "service", "interior_tidy")]
    run = fresh_run(post, keep_saved=True)
    assert carried(post, run) == want
    now = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "now"})
    nxt = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "interior_tidy", "when": "next_return"})
    for r, svc in ((now, "exterior wash"), (nxt, "interior tidy")):
        assert r["data"]["outcome"] == "applied", r
        assert (f"The every-return order for {svc} stays: on this run it is back on the car once this one is done, and it stays "
                "saved to the car for every run.") in r["data"]["summary"], r["data"]["summary"]
        assert "This lasts until the demo run ends or you undo it." in r["data"]["summary"]
    assert saved(post, AV041) == want, "a one-time order does not end what is saved"
    # on the run: the wash done, the tick fulfils the one-time order and the every-return order is in force again
    post.val(f"SELECT ottoq.ottoq_owner_orders_tick('{run}', '2026-09-27 12:01+00')")
    post.run(f"""UPDATE ottoq_visit_needs SET atoms = (SELECT jsonb_agg(CASE WHEN a->>'svc' = 'exterior_wash' THEN a || '{{"status":"done"}}' ELSE a END)
                                                        FROM jsonb_array_elements(atoms) a)
                 WHERE vehicle_id = '{AV041}' AND sim_run_id = '{run}'""")
    post.val(f"SELECT ottoq.ottoq_owner_orders_tick('{run}', '2026-09-27 12:02+00')")
    active = sorted(tuple(r) for r in post.rows(f"SELECT service, service_when FROM ottoq_owner_settings WHERE sim_run_id = '{run}' "
                                                 f"AND vehicle_id = '{AV041}' AND kind = 'service' AND status = 'active'"))
    assert active == [("exterior_wash", "every_return"), ("interior_tidy", "next_return")], active
    # and the done wash is tagged with the every-return order, not done twice: one wash atom on the visit
    assert post.val(f"""SELECT count(*) FROM ottoq_visit_needs n CROSS JOIN LATERAL jsonb_array_elements(n.atoms) a
                        WHERE n.sim_run_id = '{run}' AND n.vehicle_id = '{AV041}' AND a ->> 'svc' = 'exterior_wash'""") == "1"
    # an undo of the next-return order puts the every-return tidy back at once (0605's undo, unchanged)
    u = tcall(post, chase, "undo_command", {"command_id": nxt["data"]["command"]["command_id"]})
    assert u["data"]["outcome"] == "applied", u
    assert post.val(f"SELECT service_when FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND vehicle_id = '{AV041}' "
                    f"AND service = 'interior_tidy' AND status = 'active'") == "every_return"
    # a passcode session's one-time order over the carried order leaves what is saved as it is
    session = unlock(post, agent="Visitor", ip="192.0.2.131")["data"]["session"]
    assert tcall(post, session, "request_service", {"vehicles": ["Tesla 41"], "service": "interior_tidy", "when": "now"})["data"]["outcome"] == "applied"
    assert saved(post, AV041) == want
    # the next demo run and the next production run carry both every-return orders
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    demo = fresh_run(post, keep_saved=True)
    assert carried(post, demo) == want
    prod = production_run(post, keep_saved=True)
    assert carried(post, prod) == want
    # in production, the same: a person's wash now does not end the saved order
    again = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash", "when": "now"})
    assert again["data"]["outcome"] == "applied" and "This lasts until the production run ends or you undo it." in again["data"]["summary"], again
    assert saved(post, AV041) == want
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{prod}'")
    third = fresh_run(post, keep_saved=True)
    assert carried(post, third) == want
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{third}'")


def test_the_cockpit_boards_show_no_production_owner_data_and_no_persons_words_to_anon(post):
    """The review, round 1: the two cockpit boards are EXECUTE for anon (0606, 0608, read live 2026-10-14). They show a
    demo run's settings and commands as before, but never a production run's settings, a production command, a person's
    command made with no run live, or the note (the person's own words) of any command recorded under a person."""
    no_run(post)
    chase = sign_in(post)
    saved_cmd = tcall(post, chase, "request_service", {"vehicles": ["Tesla 45"], "service": "exterior_wash", "when": "every_return",
                                                        "note": "PRIVATE saved note"})
    assert saved_cmd["data"]["outcome"] == "saved", saved_cmd
    # a demo run: a person's command and a passcode session's both listed; the person's note is not shown, the session's is
    demo = fresh_run(post, keep_saved=True)
    mine = tcall(post, chase, "request_service", {"vehicles": ["Tesla 41"], "service": "interior_tidy", "when": "now",
                                                   "note": "PRIVATE demo note: my kids ride at 7"}, transport="ask")
    session = unlock(post, agent="Visitor", ip="192.0.2.132")["data"]["session"]
    theirs = tcall(post, session, "hold_vehicle", {"vehicles": ["Tesla 41"], "for_minutes": 30, "note": "session note"})
    for r in (mine, theirs):
        assert r["data"]["outcome"] == "applied", r
    mid, tid = mine["data"]["command"]["command_id"], theirs["data"]["command"]["command_id"]
    board = post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', NULL)", role="anon")
    listed = [c["command_id"] for c in board["commands"]]
    assert mid in listed and tid in listed and saved_cmd["data"]["command"]["command_id"] not in listed, listed
    assert {s["kind"] for s in board["in_force"]} >= {"service", "hold"}
    assert "saved to the car and carried onto every run" in board["resets"]
    hl_mine = post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', '{mid}')", role="anon")["highlight"]
    hl_theirs = post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', '{tid}')", role="anon")["highlight"]
    assert "note" not in hl_mine["args"] and hl_mine["args"]["service"] == "interior_tidy", hl_mine
    assert hl_theirs["args"]["note"] == "session note"
    assert post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', '{saved_cmd['data']['command']['command_id']}')",
                     role="anon").get("highlight") is None
    depot = post.json(f"SELECT ottoq_depot_owner_board('{TWIN}', 30)", role="anon")
    assert mid in [c["command_id"] for c in depot["commands"]] and depot["in_force"], depot
    # a production run: its settings, its commands and the person's words are on neither board
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{demo}'")
    prod = production_run(post, keep_saved=True)
    pc = tcall(post, chase, "request_service", {"vehicles": ["Tesla 45"], "service": "interior_tidy", "when": "now",
                                                 "note": "PRIVATE prod note: bag left in Tesla 45, it has my passport"}, transport="ask")
    assert pc["data"]["outcome"] == "applied", pc
    pid = pc["data"]["command"]["command_id"]
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{prod}' AND status = 'active'") != "0"
    blobs = [post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', NULL)", role="anon"),
             post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', '{pid}')", role="anon"),
             post.json(f"SELECT ottoq_depot_owner_board('{TWIN}', 30)", role="anon")]
    blob = json.dumps(blobs)
    assert pid not in blob and "my passport" not in blob and "PRIVATE" not in blob and EMAIL not in blob.lower(), blob[:2000]
    assert blobs[0]["in_force"] == [] and blobs[2]["in_force"] == [] and blobs[1].get("highlight") is None
    # the owner still reads it all through their own signed-in agent
    own = tcall(post, chase, "my_settings")["data"]
    assert any(x.get("service") == "interior_tidy" for x in own["settings"]), own
    # what the person saves in production is carried onto the next demo run, where it shows, but never names the
    # production command that made it (its id or its confirmation code)
    keep = lower(post, chase, {"vehicles": ["Tesla 41"], "percent": 90, "note": "PRIVATE limit note"}, transport="ask")
    assert keep["data"]["outcome"] == "applied", keep
    kid = keep["data"]["command"]["command_id"]
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{prod}'")
    demo2 = fresh_run(post, keep_saved=True)
    assert (AV041, "charge_limit", "90") in carried(post, demo2)
    seen = [post.json(f"SELECT ottoq_owner_board('{TESLA}', '{TWIN}', NULL)", role="anon"),
            post.json(f"SELECT ottoq_depot_owner_board('{TWIN}', 30)", role="anon")]
    for b in seen:
        rows = [x for x in b["in_force"] if x.get("vehicle_id") == AV041 and x.get("kind") == "charge_limit"]
        assert len(rows) == 1 and "command_id" not in rows[0] and "confirmation_code" not in rows[0], rows
    blob = json.dumps(seen)
    assert kid not in blob and pid not in blob and "PRIVATE" not in blob, blob[:2000]
    post.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{demo2}'")
