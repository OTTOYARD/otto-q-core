"""db/migrations/0660, EXECUTED on the stub engine: an owner signs in, and connects their own agent.

WHY THIS EXISTS. 0660 lets a person with an OTTOYARD account approve their own agent on a sign-in page, and the agent
then holds tokens that reach exactly what an owner key reaches. Every one of these is a security promise no compile
check can see:

  * only a signed-in account linked to a fleet can approve, and only by the code the agent showed; wrong codes are
    throttled per account; an account not linked is told so and can do nothing;
  * a registration is not a credential; public clients only; redirect URIs are https or loopback;
  * a device code connects once, after approval, polled no faster than its interval; denied and expired are told so;
  * a browser authorization needs PKCE S256, returns its state and OTTOYARD's issuer, and a replayed code closes what it
    opened;
  * a connection is an ottoq_agent_principals row with an owner key's scope (a CHECK), reached by hashed access tokens;
    the run's end does not end it, the owner's disconnect does, at once;
  * refresh tokens rotate and are single-use: a retry inside a minute is forgiven, a reuse after that closes the
    connection; revoking a refresh token closes the connection, revoking an access token ends only that token;
  * the owner tools, receipts and boards serve a signed-in agent unchanged and say "signed in";
  * no client role reaches a sign-in table; the gateway's door is service_role's, the person's doors authenticated's;
  * the ledger records every call and never a raw secret.

Loads the stub engines, 0559, 0560, 0605-0608, tests/fixtures/agent_signin_stub_auth.sql (auth.users) and 0660.
SKIPS where no scratch PostgreSQL is reachable, like the 0559, 0605 and 0607 suites.
"""
import base64
import hashlib
import json
import os
import re
import uuid

import pytest

from test_owner_agent_sql import (  # noqa: F401  (pytestmark: skip without a scratch server)
    AV041, AV045, M0559, M0560, M0605, M0606, ROOT, RT003, SEED, STUB_0559, STUB_0605, TESLA, TWIN, WAYMO,
    _drop, _new_db, fresh_run, pytestmark, q,
)
from test_passcode_door_sql import M0607, M0608, PASSCODE, pcall

M0660 = os.path.join(ROOT, "db", "migrations", "0660_an_owner_signs_in_and_connects_their_own_agent.sql")
STUB_AUTH = os.path.join(ROOT, "tests", "fixtures", "agent_signin_stub_auth.sql")
DEVICE = "urn:ietf:params:oauth:grant-type:device_code"
CHASE = "c4a5e000-0000-4000-8000-00000000c4a5"
KIM = "c4a5e000-0000-4000-8000-0000000000b1"      # an account with no fleet link
RESOURCE = "https://gxdrcyphqjzjsuhxuqtg.supabase.co/functions/v1/ottoq-agent-gateway/account/mcp"
LOOPBACK = "http://127.0.0.1:8420/callback"
USER_CODE = re.compile(r"^[BCDFGHJKLMNPQRSTVWXZ]{4}-[BCDFGHJKLMNPQRSTVWXZ]{4}$")


def sha(t):
    return hashlib.sha256(t.encode()).hexdigest()


def s256(verifier):
    return base64.urlsafe_b64encode(hashlib.sha256(verifier.encode()).digest()).decode().rstrip("=")


def oauth(db, op, args, ip="203.0.113.7"):
    return db.json(f"SELECT ottoq_agent_oauth({q(op)}, {q(json.dumps(args))}::jsonb, {q(json.dumps({'ip': ip}))}::jsonb)")


def person(db, uid, sql):
    """A door called the way the sign-in page calls it: as role authenticated, with the person's JWT claims."""
    claims = json.dumps({"sub": uid, "role": "authenticated"})
    return db.json(f"SELECT set_config('request.jwt.claims', {q(claims)}, false); SET ROLE authenticated; {sql}")


_IPS = iter(range(1, 60000))


def register(db, grants=(DEVICE, "refresh_token"), uris=(LOOPBACK,), name="Hermes Agent", ip=None):
    """Each registration from its own address unless one is given: the per-caller throttle is tested on its own."""
    if ip is None:
        n = next(_IPS)
        ip = f"10.66.{n // 256}.{n % 256}"
    r = oauth(db, "register", {"client_name": name, "redirect_uris": list(uris), "grant_types": list(grants),
                               "response_types": [], "token_endpoint_auth_method": "none"}, ip=ip)
    assert r["http_status"] == 201, r
    return r["body"]["client_id"]


def device_token(db, client, code):
    return oauth(db, "token", {"grant_type": DEVICE, "client_id": client, "device_code_hash": sha(code)})


def unthrottle(db, user_code):
    db.run(f"UPDATE ottoq_oauth_device_codes SET last_polled_at = now() - interval '10 seconds' WHERE user_code = {q(user_code)}")


def connect(db, uid=CHASE, client=None):
    """Register (unless given a client), ask for a device code, approve it as `uid`, exchange it: the token answer."""
    client = client or register(db)
    dev = oauth(db, "device_authorize", {"client_id": client, "resource": RESOURCE})["body"]
    assert person(db, uid, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'approve')")["outcome"] == "approved"
    unthrottle(db, dev["user_code"])
    t = device_token(db, client, dev["device_code"])
    assert t["http_status"] == 200, t
    return {**t["body"], "client_id": client}


def principal_of(db, access_token):
    return db.val(f"SELECT t.principal_id FROM ottoq_oauth_tokens t WHERE t.token_hash = {q(sha(access_token))}")


def call(db, token, tool, args=None):
    return pcall(db, sha(token), tool, args or {})


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608, STUB_AUTH, M0660):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.run(SEED)
        d.run(f"""INSERT INTO auth.users (id, email) VALUES ('{CHASE}', 'Chase@OTTOYARD.com'), ('{KIM}', 'kim@example.com')""")
        r = d.json(f"SELECT ottoq_owner_account_link('chase@ottoyard.com', '{TESLA}', 'the founder, for demos')")
        assert r["ok"], r
        yield d
    finally:
        _drop(d)


# ─────────────────────────────────────────────────────────────────────────────────────── the premises ──

def test_0660_needs_0607_and_0608():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606):
            assert d.file(path)[0] == 0
        rc, err = d.file(M0660)
        assert rc != 0 and "0660 P1: 0607 and 0608" in err, err
    finally:
        _drop(d)


def test_0660_refuses_a_second_apply(db):
    rc, err = db.file(M0660)
    assert rc != 0 and "0660 P1: already applied" in err, err


def test_0660_refuses_a_body_it_did_not_measure():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608):
            assert d.file(path)[0] == 0
        d.run("""CREATE OR REPLACE FUNCTION public.ottoq_agent_resolve(p_token_hash text) RETURNS public.ottoq_agent_principals
                 LANGUAGE sql STABLE AS $$ SELECT NULL::public.ottoq_agent_principals $$""")
        rc, err = d.file(M0660)
        assert rc != 0 and "0660 P1: not the body this file was written against" in err and "ottoq_agent_resolve" in err, err
    finally:
        _drop(d)


def test_classified_for_no_recert_round(db):
    assert db.rows("SELECT forces_recert, forces_dial_restart FROM ottoq_cert_lineage WHERE name LIKE '0660%'") == [["f", "f"]]


def test_the_probe_left_nothing_behind():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608, M0660):
            assert d.file(path)[0] == 0
        for t in ("ottoq_owner_accounts", "ottoq_oauth_clients", "ottoq_oauth_device_codes", "ottoq_oauth_auth_requests",
                  "ottoq_oauth_grants", "ottoq_oauth_tokens", "ottoq_agent_principals", "ottoq_agent_call_ledger"):
            assert d.val(f"SELECT count(*) FROM {t}") == "0", t
        assert d.val("SELECT count(*) FROM ottoq_schema_snapshots WHERE label = '0660_pre'") == "6"
    finally:
        _drop(d)


# ─────────────────────────────────────────────────────────────────────────────────────────── the grants ──

def test_no_client_role_reaches_a_sign_in_table(db):
    for role in ("anon", "authenticated"):
        rc, _, err = db.run(f"SET ROLE {role}; SELECT count(*) FROM ottoq_oauth_tokens", check=False)
        assert rc != 0 and "permission denied" in err, (role, err)


def test_the_gateways_door_is_service_roles_and_the_persons_doors_authenticated(db):
    rc, _, err = db.run("SET ROLE authenticated; SELECT ottoq_agent_oauth('register', '{}'::jsonb, '{}'::jsonb)", check=False)
    assert rc != 0 and "permission denied" in err, err
    rc, _, err = db.run("SET ROLE anon; SELECT ottoq_oauth_device_decide('BCDF-GHJK', 'approve')", check=False)
    assert rc != 0 and "permission denied" in err, err
    rc, _, err = db.run("SET ROLE authenticated; SELECT ottoq_owner_account_link('a@b.c', gen_random_uuid())", check=False)
    assert rc != 0 and "permission denied" in err, err
    assert db.val("SET ROLE service_role; SELECT (ottoq_agent_oauth('nope', '{}'::jsonb, '{}'::jsonb)) ->> 'http_status'") == "404"


# ─────────────────────────────────────────────────────────────────────────────────────── registration ──

def test_a_public_client_registers_and_gets_its_metadata_back(db):
    r = oauth(db, "register", {"client_name": "Hermes Agent", "redirect_uris": [LOOPBACK], "grant_types": [DEVICE, "refresh_token"],
                               "response_types": [], "token_endpoint_auth_method": "none", "application_type": "native"})
    b = r["body"]
    assert r["http_status"] == 201 and re.fullmatch(r"oqc_[0-9a-f]{32}", b["client_id"])
    assert b["token_endpoint_auth_method"] == "none" and b["redirect_uris"] == [LOOPBACK] and b["response_types"] == []
    assert sorted(b["grant_types"]) == sorted([DEVICE, "refresh_token"])


@pytest.mark.parametrize("reg, error", [
    ({"client_name": "x", "token_endpoint_auth_method": "client_secret_basic", "redirect_uris": [LOOPBACK]}, "invalid_client_metadata"),
    ({"client_name": "x", "redirect_uris": ["http://evil.example/cb"]}, "invalid_redirect_uri"),
    ({"client_name": "x", "redirect_uris": ["https://ok.example/cb#frag"]}, "invalid_redirect_uri"),
    ({"client_name": "x", "grant_types": ["authorization_code"]}, "invalid_redirect_uri"),
    ({"client_name": "x", "grant_types": ["client_credentials"]}, "invalid_client_metadata"),
    ({"client_name": "x", "grant_types": "authorization_code"}, "invalid_client_metadata"),
])
def test_a_registration_outside_the_rules_is_refused(db, reg, error):
    r = oauth(db, "register", reg, ip="198.51.100.1")
    assert r["http_status"] == 400 and r["body"]["error"] == error, r


def test_registrations_are_throttled_per_caller(db):
    ip = "198.51.100.20"
    for _ in range(20):
        register(db, ip=ip)
    r = oauth(db, "register", {"client_name": "one too many", "grant_types": [DEVICE]}, ip=ip)
    assert r["http_status"] == 429 and r["body"]["error"] == "temporarily_unavailable", r
    assert oauth(db, "register", {"client_name": "someone else", "grant_types": [DEVICE]}, ip="198.51.100.21")["http_status"] == 201


# ─────────────────────────────────────────────────────────────────────────────────────── the device code ──

def test_the_device_code_connects_once_after_approval(db):
    client = register(db)
    dev = oauth(db, "device_authorize", {"client_id": client, "resource": RESOURCE})["body"]
    assert USER_CODE.match(dev["user_code"]) and dev["expires_in"] == 600 and dev["interval"] == 5
    assert device_token(db, client, dev["device_code"])["body"]["error"] == "authorization_pending"
    assert device_token(db, client, dev["device_code"])["body"]["error"] == "slow_down"
    assert db.val(f"SELECT interval_s FROM ottoq_oauth_device_codes WHERE user_code = {q(dev['user_code'])}") == "10"
    looked = person(db, CHASE, f"SELECT ottoq_oauth_device_lookup({q(dev['user_code'].lower().replace('-', ' '))})")
    assert looked["ok"] and looked["agent"] == "Hermes Agent" and looked["fleet"]["name"] == "Tesla Robotaxi TN"
    assert any("cannot" not in c for c in looked["can"]) and looked["cannot"]
    assert person(db, CHASE, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'approve')")["outcome"] == "approved"
    db.run(f"UPDATE ottoq_oauth_device_codes SET last_polled_at = now() - interval '20 seconds' WHERE user_code = {q(dev['user_code'])}")
    t = device_token(db, client, dev["device_code"])
    assert t["http_status"] == 200 and t["body"]["token_type"] == "Bearer" and t["body"]["expires_in"] == 3600
    assert re.fullmatch(r"oqt_[0-9a-f]{64}", t["body"]["access_token"]) and re.fullmatch(r"oqr_[0-9a-f]{64}", t["body"]["refresh_token"])
    again = device_token(db, client, dev["device_code"])
    assert again["http_status"] == 400 and again["body"]["error"] == "invalid_grant"


def test_denied_expired_unknown_and_anothers_device_code(db):
    client, other = register(db), register(db)
    dev = oauth(db, "device_authorize", {"client_id": client})["body"]
    assert person(db, CHASE, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'deny')")["outcome"] == "denied"
    unthrottle(db, dev["user_code"])
    assert device_token(db, client, dev["device_code"])["body"]["error"] == "access_denied"
    late = oauth(db, "device_authorize", {"client_id": client})["body"]
    db.run(f"UPDATE ottoq_oauth_device_codes SET expires_at = now() - interval '1 second' WHERE user_code = {q(late['user_code'])}")
    assert device_token(db, client, late["device_code"])["body"]["error"] == "expired_token"
    assert person(db, CHASE, f"SELECT ottoq_oauth_device_lookup({q(late['user_code'])})")["code"] == "expired_code"
    assert device_token(db, client, "oqd_" + "0" * 64)["body"]["error"] == "invalid_grant"
    mine = oauth(db, "device_authorize", {"client_id": client})["body"]
    assert device_token(db, other, mine["device_code"])["body"]["error"] == "invalid_grant"
    assert oauth(db, "device_authorize", {"client_id": "oqc_" + "f" * 32})["body"]["error"] == "invalid_client"
    browser_only = register(db, grants=("authorization_code", "refresh_token"))
    assert oauth(db, "device_authorize", {"client_id": browser_only})["body"]["error"] == "unauthorized_client"


def test_only_a_linked_signed_in_account_can_answer_a_code(db):
    client = register(db)
    dev = oauth(db, "device_authorize", {"client_id": client})["body"]
    assert person(db, KIM, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'approve')")["code"] == "not_linked"
    assert db.json(f"SELECT ottoq_oauth_device_lookup({q(dev['user_code'])})")["code"] == "not_signed_in"
    assert person(db, CHASE, "SELECT ottoq_oauth_device_lookup('NOPE')")["code"] == "invalid_code"
    assert person(db, CHASE, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'maybe')")["code"] == "invalid_decision"
    assert db.val(f"SELECT status FROM ottoq_oauth_device_codes WHERE user_code = {q(dev['user_code'])}") == "pending"


def test_wrong_codes_are_throttled_per_account():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608, STUB_AUTH, M0660):
            assert d.file(path)[0] == 0
        d.run(f"INSERT INTO auth.users (id, email) VALUES ('{CHASE}', 'chase@ottoyard.com')")
        d.json(f"SELECT ottoq_owner_account_link('chase@ottoyard.com', '{TESLA}')")
        for _ in range(10):
            assert person(d, CHASE, "SELECT ottoq_oauth_device_lookup('BCDF-BCDF')")["code"] == "unknown_code"
        assert person(d, CHASE, "SELECT ottoq_oauth_device_lookup('BCDF-BCDF')")["code"] == "too_many_tries"
    finally:
        _drop(d)


# ─────────────────────────────────────────────────────────────────────────────────────── the connection ──

def test_a_connection_is_an_owner_key_with_the_agents_name_and_no_expiry(db):
    t = connect(db)
    pid = principal_of(db, t["access_token"])
    row = db.rows(f"""SELECT origin, kind, fleet_operator_id, capabilities, display_name, token_prefix ~ '^oqt_[0-9a-f]{{8}}$',
                             expires_at IS NULL, status FROM ottoq_agent_principals WHERE principal_id = '{pid}'""")
    assert row == [["oauth", "personal", TESLA, "{note,owner_settings,read}", "Hermes Agent", "t", "t", "active"]]
    assert db.rows(f"SELECT account_id, email, created_via FROM ottoq_oauth_grants WHERE principal_id = '{pid}'") == \
        [[CHASE, "chase@ottoyard.com", "device_code"]]
    rc, _, err = db.run(f"UPDATE ottoq_agent_principals SET capabilities = ARRAY['read','note','owner_settings','request_recall'] WHERE principal_id = '{pid}'", check=False)
    assert rc != 0, "a connection's scope must be fixed"


def test_the_access_token_reaches_the_owner_door_and_says_signed_in(db):
    t = connect(db)
    who = call(db, t["access_token"], "whoami")
    assert who["ok"] and who["data"]["principal"]["via"] == "signed in"
    assert who["data"]["principal"]["account"] == "chase@ottoyard.com"
    assert "disconnects" in who["data"]["principal"]["ends"]
    hello = call(db, t["access_token"], "welcome")
    assert "signed in to chase@ottoyard.com's OTTOYARD account" in hello["data"]["summary"]
    assert "(an agent key)" not in hello["data"]["summary"]
    assert hello["data"]["agent"] == {"name": "Hermes Agent", "via": "signed in", "account": "chase@ottoyard.com"}
    fleet = call(db, t["access_token"], "my_fleet")
    assert fleet["ok"], fleet
    # a refresh token is not an access token
    assert call(db, t["refresh_token"], "whoami")["http_status"] == 401


def test_a_signed_in_agents_change_carries_its_code_and_the_boards_say_signed_in(db):
    run = fresh_run(db)
    t = connect(db)
    r = call(db, t["access_token"], "set_charge_limit", {"vehicles": "all", "percent": 90})
    assert r["ok"] and r["data"]["outcome"] == "applied", r
    assert re.fullmatch(r"OQ-[0-9A-F]{4}-[0-9A-F]{4}", r["data"]["confirmation_code"])
    board = db.json(f"SET ROLE anon; SELECT ottoq_owner_board('{TESLA}')")
    assert any(c.get("agent") == "Hermes Agent" and c.get("agent_via") == "signed in" for c in board["commands"]), board["commands"]
    depot = db.json("SET ROLE anon; SELECT ottoq_depot_owner_board()")
    hermes = [a for a in depot["agents"] if a["agent"] == "Hermes Agent"]
    assert hermes and all(a["via"] == "signed in" for a in hermes) and any(a["state"] == "connected" for a in hermes)
    for k in ("principal_id", "token", "token_prefix"):
        assert k not in json.dumps(depot["agents"])
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")


def test_the_runs_end_does_not_end_a_connection_but_still_ends_a_passcode_session(db):
    db.json(f"SELECT ottoq_agent_set_passcode({q(PASSCODE)})")
    run = fresh_run(db)
    t = connect(db)
    s = pcall(db, None, "enter_passcode", {"passcode": PASSCODE, "agent": "Grok"}, ip="203.0.113.99")
    session = s["data"]["session"]
    db.run(f"UPDATE ottoq_sim_runs SET status = 'completed' WHERE sim_run_id = '{run}'")
    assert call(db, t["access_token"], "whoami")["ok"]
    assert pcall(db, sha(session), "whoami")["error"]["code"] == "session_ended"
    db.json("SELECT ottoq_agent_set_passcode(NULL)")


# ─────────────────────────────────────────────────────────────────────────────────────────── refreshing ──

def test_refresh_rotates_and_a_retry_inside_a_minute_is_forgiven(db):
    t = connect(db)
    first = oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(t["refresh_token"])})["body"]
    assert first["refresh_token"] != t["refresh_token"]
    retry = oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(t["refresh_token"])})
    assert retry["http_status"] == 200, retry
    # the unused successor the retry replaced is retired; the retry's own pair works
    assert oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(first["refresh_token"])})["body"]["error"] == "invalid_grant"
    assert call(db, retry["body"]["access_token"], "whoami")["ok"]


def test_a_refresh_token_used_twice_after_the_grace_closes_the_connection(db):
    t = connect(db)
    nxt = oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(t["refresh_token"])})["body"]
    oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(nxt["refresh_token"])})
    reuse = oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(t["refresh_token"])})
    assert reuse["body"]["error"] == "invalid_grant" and "closed" in reuse["body"]["error_description"]
    pid = principal_of(db, t["access_token"])
    assert db.val(f"SELECT revoked_reason FROM ottoq_agent_principals WHERE principal_id = '{pid}'") == "refresh_token_reuse"
    assert call(db, nxt["access_token"], "whoami")["error"]["code"] == "disconnected"


def test_refresh_is_refused_for_another_client_or_an_expired_token(db):
    t = connect(db)
    other = register(db)
    assert oauth(db, "token", {"grant_type": "refresh_token", "client_id": other, "refresh_token_hash": sha(t["refresh_token"])})["body"]["error"] == "invalid_grant"
    db.run(f"UPDATE ottoq_oauth_tokens SET expires_at = now() - interval '1 second' WHERE token_hash = {q(sha(t['refresh_token']))}")
    assert oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(t["refresh_token"])})["body"]["error"] == "invalid_grant"
    assert oauth(db, "token", {"grant_type": "password", "client_id": t["client_id"]})["body"]["error"] == "unsupported_grant_type"


def test_an_expired_access_token_is_told_why(db):
    t = connect(db)
    db.run(f"UPDATE ottoq_oauth_tokens SET expires_at = now() - interval '1 second' WHERE token_hash = {q(sha(t['access_token']))}")
    r = call(db, t["access_token"], "whoami")
    assert r["http_status"] == 401 and r["error"]["code"] == "token_expired" and "refresh token" in r["error"]["message"]


# ─────────────────────────────────────────────────────────────────────────────────────────── revocation ──

def test_revoking_an_access_token_ends_it_and_revoking_a_refresh_token_closes_the_connection(db):
    t = connect(db)
    assert oauth(db, "revoke", {"token_hash": sha(t["access_token"])})["http_status"] == 200
    assert call(db, t["access_token"], "whoami")["error"]["code"] == "token_revoked"
    fresh = oauth(db, "token", {"grant_type": "refresh_token", "client_id": t["client_id"], "refresh_token_hash": sha(t["refresh_token"])})["body"]
    assert call(db, fresh["access_token"], "whoami")["ok"]
    assert oauth(db, "revoke", {"token_hash": sha(fresh["refresh_token"])})["http_status"] == 200
    assert call(db, fresh["access_token"], "whoami")["error"]["code"] == "disconnected"
    assert oauth(db, "revoke", {"token_hash": sha("oqt_" + "0" * 64)})["http_status"] == 200


# ───────────────────────────────────────────────────────────────────────────── the browser authorization ──

def authorize(db, client, **over):
    args = {"client_id": client, "redirect_uri": LOOPBACK, "response_type": "code", "code_challenge": s256("v" * 50),
            "code_challenge_method": "S256", "state": "x y&z", "issuer": "https://www.ottoyard.com", "resource": RESOURCE}
    args.update(over)
    return oauth(db, "authorize", {k: v for k, v in args.items() if v is not None})


def test_the_browser_authorization_validates_before_it_ever_redirects(db):
    client = register(db, grants=("authorization_code", "refresh_token"))
    r = authorize(db, "oqc_" + "e" * 32)
    assert r["body"]["error"] == "invalid_client" and "redirect_uri" not in r
    r = authorize(db, client, redirect_uri="https://evil.example/cb")
    assert r["body"]["error"] == "invalid_request" and "redirect_uri" not in r
    r = authorize(db, client, response_type="token")
    assert r["body"]["error"] == "unsupported_response_type" and r["redirect_uri"] == LOOPBACK and r["state"] == "x y&z"
    r = authorize(db, client, code_challenge_method="plain")
    assert r["body"]["error"] == "invalid_request" and r["redirect_uri"] == LOOPBACK
    # RFC 8252 7.3: a loopback redirect on another port is the same redirect
    assert authorize(db, client, redirect_uri="http://127.0.0.1:59999/callback")["http_status"] == 200


def test_approved_the_code_comes_back_with_state_and_issuer_and_needs_the_verifier(db):
    client = register(db, grants=("authorization_code", "refresh_token"))
    req = authorize(db, client)["body"]["request_id"]
    look = person(db, CHASE, f"SELECT ottoq_oauth_request_lookup('{req}')")
    assert look["ok"] and look["agent"] == "Hermes Agent" and look["returns_to"] == "http://127.0.0.1:8420"
    dec = person(db, CHASE, f"SELECT ottoq_oauth_request_decide('{req}', 'approve')")
    to = dec["redirect_to"]
    assert to.startswith(LOOPBACK + "?code=oqg_") and "&state=x%20y%26z" in to and to.endswith("&iss=https%3A%2F%2Fwww.ottoyard.com")
    code = re.search(r"code=(oqg_[0-9a-f]{64})", to).group(1)
    bad = oauth(db, "token", {"grant_type": "authorization_code", "client_id": client, "code_hash": sha(code),
                              "code_challenge_s256": s256("w" * 50), "redirect_uri": LOOPBACK})
    assert bad["body"]["error"] == "invalid_grant" and "PKCE" in bad["body"]["error_description"]
    good = oauth(db, "token", {"grant_type": "authorization_code", "client_id": client, "code_hash": sha(code),
                               "code_challenge_s256": s256("v" * 50), "redirect_uri": LOOPBACK})
    assert good["http_status"] == 200, good
    assert call(db, good["body"]["access_token"], "whoami")["data"]["principal"]["via"] == "signed in"
    replay = oauth(db, "token", {"grant_type": "authorization_code", "client_id": client, "code_hash": sha(code),
                                 "code_challenge_s256": s256("v" * 50)})
    assert replay["body"]["error"] == "invalid_grant"
    assert call(db, good["body"]["access_token"], "whoami")["error"]["code"] == "disconnected"


def test_denied_the_browser_goes_back_with_access_denied(db):
    client = register(db, grants=("authorization_code", "refresh_token"))
    req = authorize(db, client)["body"]["request_id"]
    dec = person(db, CHASE, f"SELECT ottoq_oauth_request_decide('{req}', 'deny')")
    assert dec["outcome"] == "denied" and "error=access_denied" in dec["redirect_to"] and "code=" not in dec["redirect_to"]
    assert person(db, CHASE, f"SELECT ottoq_oauth_request_decide('{req}', 'approve')")["code"] == "stale_request"


# ──────────────────────────────────────────────────────────────────────────── the owner, on the account page ──

def test_the_owner_sees_and_disconnects_their_agents_and_no_one_elses(db):
    t = connect(db)
    me = person(db, CHASE, "SELECT ottoq_account_me()")
    assert me["linked"] and me["email"] == "chase@ottoyard.com"
    pid = principal_of(db, t["access_token"])
    assert any(c["id"] == pid and c["state"] == "connected" for c in me["connections"])
    assert person(db, KIM, f"SELECT ottoq_account_disconnect('{pid}')")["code"] == "not_found"
    assert person(db, KIM, "SELECT ottoq_account_me()")["linked"] is False
    off = person(db, CHASE, f"SELECT ottoq_account_disconnect('{pid}')")
    assert off["ok"] and "Hermes Agent is disconnected" in off["message"]
    r = call(db, t["access_token"], "whoami")
    assert r["http_status"] == 401 and r["error"]["code"] == "disconnected"
    assert any(c["id"] == pid and c["state"] == "disconnected" for c in person(db, CHASE, "SELECT ottoq_account_me()")["connections"])


def test_unlinking_an_account_closes_every_agent_it_connected():
    d = _new_db()
    try:
        for path in (STUB_0559, STUB_0605, M0559, M0560, M0605, M0606, M0607, M0608, STUB_AUTH, M0660):
            assert d.file(path)[0] == 0
        d.run(SEED)
        d.run(f"INSERT INTO auth.users (id, email) VALUES ('{CHASE}', 'chase@ottoyard.com')")
        assert d.json(f"SELECT ottoq_owner_account_link('nobody@ottoyard.com', '{TESLA}')")["error"] == "no_such_account"
        d.json(f"SELECT ottoq_owner_account_link('chase@ottoyard.com', '{TESLA}')")
        a, b = connect(d), connect(d)
        r = d.json("SELECT ottoq_owner_account_unlink('chase@ottoyard.com', 'test')")
        assert r["ok"] and r["connections_closed"] == 2
        assert call(d, a["access_token"], "whoami")["http_status"] == 401
        assert call(d, b["access_token"], "whoami")["http_status"] == 401
        dev = oauth(d, "device_authorize", {"client_id": register(d)})["body"]
        assert person(d, CHASE, f"SELECT ottoq_oauth_device_decide({q(dev['user_code'])}, 'approve')")["code"] == "not_linked"
    finally:
        _drop(d)


def test_the_ledger_holds_every_sign_in_call_and_never_a_secret(db):
    t = connect(db)
    text = db.val("SELECT string_agg(coalesce(detail::text, '') || coalesce(error_code, '') || coalesce(path, ''), ' ') "
                  "FROM ottoq_agent_call_ledger WHERE transport IN ('oauth', 'web')")
    for secret in (t["access_token"], t["refresh_token"]):
        assert secret not in text and secret[4:] not in text
    tools = {r[0] for r in db.rows("SELECT DISTINCT tool FROM ottoq_agent_call_ledger WHERE transport IN ('oauth', 'web')")}
    assert {"oauth.register", "oauth.device_authorize", "oauth.token", "oauth.device_decide"} <= tools
