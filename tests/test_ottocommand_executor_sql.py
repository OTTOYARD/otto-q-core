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
    ledgered through a service-role-only door that refuses text.

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
    chase = connect(post)["access_token"]
    post.run("UPDATE ottoq_sim_runs SET status = 'completed' WHERE status IN ('running', 'paused')")
    none = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90, "mode": "preview"})
    assert none["error"]["code"] == "no_live_demo"
    assert none["error"]["message"].startswith("No demo run is live at the twin depot.")
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
               "public.ottoq_owner_settings_read(ottoq_agent_principals,jsonb)"):
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
                                             if k.startswith(("public.ottoq_tg_lift_owner_settings_on_terminal", "public.ottoq_agent_public_call"))]
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
        rc, _, err = post.run(ins.format(run=run, depot=depot, fleet=fleet, car=car, pct=pct, cmd=cmd), check=False)
        assert rc != 0 and ("is not what an applied owner command set" in err or "violates foreign key" in err), (why, err)
    # on another run, only as the carry of a saved row this very command made
    other = fresh_run(post, keep_saved=True)
    rc, _, err = post.run(f"INSERT INTO ottoq_owner_settings (sim_run_id, depot_id, fleet_operator_id, vehicle_id, kind, "
                          f"charge_limit_pct, command_id, set_at_sim) VALUES ('{other}', '{TWIN}', '{TESLA}', '{AV041}', "
                          f"'charge_limit', 85, '{cid}', now())", check=False)
    assert rc != 0 and "is not what an applied owner command set" in err, err
    sid = post.val(f"SELECT setting_id FROM ottoq_owner_settings WHERE sim_run_id = '{other}' AND vehicle_id = '{AV041}' AND kind = 'charge_limit'")
    for sql, why in ((f"UPDATE ottoq_owner_settings SET charge_limit_pct = 50 WHERE setting_id = '{sid}'", "what was set is immutable"),
                     (f"UPDATE ottoq_owner_settings SET status = 'withdrawn', closed_at = now(), closed_reason = 'x' WHERE setting_id = '{sid}'",
                      "replaced or withdrawn only by an applied owner command"),
                     (f"DELETE FROM ottoq_owner_settings WHERE setting_id = '{sid}'", "DELETE refused")):
        rc, _, err = post.run(sql, check=False)
        assert rc != 0 and why in err, (sql, err)
    rc, _, err = post.run(f"UPDATE ottoq_owner_settings SET status = 'active' WHERE status = 'lifted' AND sim_run_id = '{run}'", check=False)
    assert rc != 0 and "is not a change an owner command, the tick or the run's end makes" in err, err
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
        rc, _, err = post.run(sql, check=False)
        assert rc != 0 and why in err, (sql, err)
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
