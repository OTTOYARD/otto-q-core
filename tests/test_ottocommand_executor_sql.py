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
    registry stays clean.

Loads the stub engines, 0559, 0560, 0605-0608, tests/fixtures/agent_signin_stub_auth.sql and 0700 from their files, and
production's world step as 0718 left it (tests/fixtures/world_advance_stub.sql with 0718 applied in a scratch database:
md5 546fa1ab9bedd29f7169ee6b4e7c090b, the live definition). SKIPS where no scratch PostgreSQL is reachable.
"""
import json
import os
import subprocess

import pytest

from test_owner_agent_sql import (  # noqa: F401  (pytestmark: skip without a scratch server)
    AV041, AV045, M0559, M0560, M0605, M0606, ROOT, RT003, SEED, STUB_0559, STUB_0605, TESLA, TWIN,
    _conn_args, _drop, _new_db, fresh_run, pytestmark, q,
)
from test_passcode_door_sql import M0607, M0608, PASSCODE, pcall, unlock
from test_agent_signin_sql import CHASE, M0700, STUB_AUTH, connect, sha

M0718 = os.path.join(ROOT, "db", "migrations", "0718_production_runs_the_world_phases_the_twin_certifies.sql")
M0721 = os.path.join(ROOT, "db", "migrations", "0721_a_signed_in_owner_changes_production_under_their_own_name.sql")
WORLD_STUB = os.path.join(ROOT, "tests", "fixtures", "world_advance_stub.sql")
CHAIN = (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608, STUB_AUTH, M0700)
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


def production_run(db, status="running"):
    """A twin-depot run with the cars' visits, as production_live (fresh_run ends whatever was live first)."""
    run = fresh_run(db)
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
    assert "This lasts until the production run ends or you undo it." in done["data"]["summary"]
    assert done["data"]["expires"].startswith("Lasts until this production run ends")
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
    production_run(post)
    session = unlock(post, agent="Grok", ip="192.0.2.71")["data"]["session"]
    p = tcall(post, session, "request_service", {"vehicles": ["Tesla 41"], "service": "exterior_wash"})
    assert p["http_status"] == 422 and p["error"]["code"] == "production_needs_a_person", p
    assert "a passcode session can read your cars there but not change them" in p["error"]["message"]
    assert p["error"]["hint"].startswith("Sign your agent in to your OTTOYARD account")
    assert command(post, p["data"]["command"]["command_id"]) == ["refused", "-", "direct"]
    # reading works as it is
    assert tcall(post, session, "my_fleet")["ok"] is True
    key = post.json(f"SELECT ottoq_agent_issue_token('fleet-bot', 'personal', ARRAY['read','note','owner_settings'], "
                    f"'{TESLA}', '{TWIN}', NULL, 600, 20)")["token"]
    k = tcall(post, key, "hold_vehicle", {"vehicles": "all", "for_minutes": 30}, transport="rest")
    assert k["error"]["code"] == "production_needs_a_person" and "an issued key names no person" in k["error"]["message"], k
    gate = tcall(post, session, "whoami")["data"]["owner"]["changes"]
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
    chase = connect(post)["access_token"]
    c = tcall(post, chase, "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert c["data"]["outcome"] == "applied", c
    assert command(post, c["data"]["command"]["command_id"]) == ["applied", EMAIL, "direct"]
    who = tcall(post, chase, "whoami")["data"]["owner"]["changes"]
    assert who == {"allowed": True, "run_kind": "demo", "person": EMAIL,
                   "message": "A demo run is live: settings apply to it and lift when it ends."}


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
    assert post.val(f"SELECT count(*) FROM ottoq_owner_settings WHERE sim_run_id = '{run}' AND status = 'active'") == "0"
    assert post.val(f"SELECT round(ottoq_effective_target_soc_at('{AV041}', now()))") == "100"
    assert post.val(f"SELECT lifted_reason FROM ottoq_owner_commands WHERE command_id = '{done['data']['command']['command_id']}'") \
        == "the run ended (completed)"


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
               "public.ottoq_owner_commands_backstop()"):
        for role in ("anon", "authenticated", "service_role"):
            assert post.val(f"SELECT has_function_privilege('{role}', '{fn}', 'EXECUTE')") == "f", (fn, role)
    assert post.val("SELECT has_function_privilege('service_role', 'public.ottoq_agent_call(text,text,jsonb,text,jsonb)', 'EXECUTE')") == "t"


def test_the_registry_stays_clean_and_the_columns_are_evidence(post):
    assert post.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE severity = 'block'") == "0"
    assert post.val("SELECT count(*) FROM ottoq_check_run_scope_registry() WHERE table_name = 'ottoq_owner_commands'") == "0"
    assert post.val("SELECT class FROM ottoq_run_scope_registry WHERE table_name = 'ottoq_owner_commands'") == "evidence"


def test_the_snapshot_holds_every_body_0721_replaced(post):
    rows = post.rows("SELECT object_name, def_md5 FROM ottoq_schema_snapshots WHERE label = '0721_pre' ORDER BY object_name")
    assert rows == sorted([[k.split("(")[0].split(".")[1], v] for k, v in list(LIVE_MD5.items())[:5]])
