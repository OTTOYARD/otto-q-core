"""db/migrations/0722, the signing-key rotation, EXECUTED on a stub carrying the live bodies.

WHY THIS EXISTS. G428: from 0198 (2026-09-06) until 0701, any signed-in caller could read system:v1, the key that signs
every event, SDR and audit bundle. 0701 closes the door; 0722 rotates the key, so nothing new is signed with a key that may
have been read, while every row v1 signed still verifies. A rotation cannot be proved by reading it, so this suite runs
0701 and then 0722 on a stub whose five signing writers, two verifiers, payload hash and append-only guard are the LIVE
definitions byte for byte (md5-asserted first), with a Vault stand-in that reports every read of a secret, and shows:

  * 0722 refuses before 0701 is applied (a signed-in caller would read the new key the moment it existed), and as
    committed, until Chase's go-ahead is in it (FINDINGS G428 leaves the rotation to him);
  * after it, new events, SDRs, audit bundles, audit reports and the attribution trigger's event sign with system:v2 and
    verify; every row v1 signed before still verifies; v1's signatures did not move; v2's differ from v1's;
  * no secret is ever selected: the file's code names no decrypted secret and never calls the resolver, every Vault read
    during the apply came through the resolver inside a signer, and neither secret appears in anything the apply printed,
    wrote, or left in its session;
  * the five functions keep their grants, the browser roles still cannot read the new key, and ottoq_events was only
    appended to by the test itself (the probe event rolled back);
  * it refuses a hotfixed function, an existing v2 row or Vault secret, another function naming v1, a v1 that is not the
    active Vault-backed unrotated key, a certification in flight and a second run; its restore statements put the v1
    defaults back while v2's rows keep verifying.

Loads tests/fixtures/signing_grants_stub.sql, then tests/fixtures/signing_rotation_stub.sql. SKIPS where no scratch
PostgreSQL is reachable.
"""
import atexit
import os
import re
import subprocess
import sys
import tempfile

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import _conn_args, _drop, _new_db, _server_up  # noqa: E402

GRANTS_STUB = os.path.join(ROOT, "tests", "fixtures", "signing_grants_stub.sql")
ROTATION_STUB = os.path.join(ROOT, "tests", "fixtures", "signing_rotation_stub.sql")
M0701 = os.path.join(ROOT, "db", "migrations",
                     "0701_a_signed_in_user_cannot_read_the_signing_key_or_call_the_signers_or_purge.sql")
M0722 = os.path.join(ROOT, "db", "migrations",
                     "0722_the_engine_signs_with_a_new_key_and_every_old_signature_still_verifies.sql")

#: the line the lead replaces with Chase's words, in both files; the committed files carry it unedited
PLACEHOLDER = "$chase$PENDING$chase$"
#: a stand-in, so the rest of each file can be exercised; it says what it is
STAND_IN = '2026-01-01, 12:00 PM CT: "test fixture, not Chase\'s words"'


def _with_go_ahead(path, said=STAND_IN):
    """A copy of a migration with its P0a line filled in; the committed file is never edited."""
    src = open(path, encoding="utf-8").read()
    assert src.count(PLACEHOLDER) == 1, f"{os.path.basename(path)}'s P0a placeholder is not there exactly once"
    fd, out = tempfile.mkstemp(prefix=os.path.basename(path)[:4] + "_go_ahead_", suffix=".sql")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(src.replace(PLACEHOLDER, "$chase$" + said + "$chase$"))
    atexit.register(lambda: os.path.exists(out) and os.remove(out))
    return out


M0701_OK = _with_go_ahead(M0701)
M0722_OK = _with_go_ahead(M0722)

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")

TWIN = "11111111-1111-1111-1111-111111111111"
CAR = "22222222-0000-4000-8000-000000000722"
OPERATOR = "33333333-0000-4000-8000-000000000722"
V1_SECRET = "stub-signing-secret-0701"

#: the live definitions the stub carries, read from the live catalog 2026-10-14 (md5 of pg_get_functiondef)
LIVE_MD5 = {
    "public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,integer,text,text,text,uuid)":
        "6d3eafdb8d582a05c6d0af2b90bbb8ff",
    "public.ottoq_emit_sdr(text,text,text,uuid,uuid,uuid,uuid,uuid,uuid,uuid,uuid,timestamptz,timestamptz,numeric,numeric,text)":
        "8158e4bf2fdac5a8e0495d65c43b891a",
    "public.ottoq_generate_audit_bundle(uuid,uuid[],text,timestamptz,timestamptz,text,text,bigint,text,text,text,text,timestamptz)":
        "23c0bda2f0c9ce64b02c9c25699cf412",
    "public.ottoq_complete_audit_report(uuid,jsonb,bigint,bigint,bigint,bigint,bigint,bigint,bigint,boolean,numeric,text)":
        "b0ec150fae0619d75af4e32bafe37bc0",
    "public.ottoq_trg_attribution_attach()": "9a89bcd66a2319d734828bb601b539a0",
    "public.ottoq_verify_event_signature(uuid)": "e30eeef88da501303c546c6e6ba8c121",
    "public.ottoq_verify_audit_bundle(uuid)": "40afdf347eda12d04441c65456ab039c",
    "public.ottoq_compute_event_hash(jsonb)": "a870ab4db2effd0fb825eb8ba94173a0",
    "public.ottoq_canonicalize_payload(jsonb)": "e06c86021e88731f019c857f1f872adb",
    "public.ottoq_events_block_mutation()": "ad4622dbfa8d1ca8414a8f914a2b0916",
}
FIVE = list(LIVE_MD5)[:5]
#: what 0722 makes of the five: the same definitions with 'system:v1' -> 'system:v2' in one place each
POST_MD5 = {
    FIVE[0]: "593dd0b01cba27b98bd217f5896df4d0",
    FIVE[1]: "40d49d125de6aad894729aa20cc84856",
    FIVE[2]: "b60b9e865167da6b77b2a592f9cfa95f",
    FIVE[3]: "3d5140303b22240f1e988c8b36a516c4",
    FIVE[4]: "3898824f6f54bdd10268c655182f19be",
}


def _md5s(d, sigs):
    return {s: d.val(f"SELECT md5(pg_get_functiondef('{s}'::regprocedure))") for s in sigs}


def _acls(d):
    return {s: d.val(f"SELECT coalesce(proacl::text, 'null') FROM pg_proc WHERE oid = '{s}'::regprocedure") for s in FIVE}


SIGN_EVENT = ("public.ottoq_sign_event('00000000-0000-4000-8000-000000000722', '2026-10-14 00:00:00+00', 'system', "
              "'probe.0722', 'probe', NULL, md5('0722'), '{key}')")

#: rows signed through the live writers: an event, an SDR with its sdr_issued event, the attribution trigger's event,
#: an audit bundle and a completed audit report
SEED = f"""
SELECT public.ottoq_record_event(p_actor_type => 'system', p_event_type => 'stub.seed', p_entity_type => 'depot',
                                 p_entity_id => '{TWIN}', p_payload => jsonb_build_object('seed', '{{tag}}'),
                                 p_depot_id => '{TWIN}', p_data_source => 'twin');
INSERT INTO public.schedule_tasks (id, schedule_id) VALUES ('{{task}}', '{{sched}}');
SELECT public.ottoq_emit_sdr('kernel_test', 'dc_fast_charge', 'robotaxi', '{CAR}', NULL, NULL, '{{task}}', NULL, NULL, NULL,
                             '{TWIN}', now() - interval '30 minutes', now(), 30.5, 120);
INSERT INTO public.ottoq_visit_cost_attribution (schedule_id, vehicle_id, fleet_operator_id, depot_id, total_cost_usd)
VALUES ('{{sched}}', '{CAR}', '{OPERATOR}', '{TWIN}', 12.5);
SELECT public.ottoq_generate_audit_bundle('{OPERATOR}', ARRAY[]::uuid[], 'bundle-{{tag}}', now() - interval '1 day', now());
INSERT INTO public.ottoq_audit_reports (report_id, report_type, fleet_operator_id, depot_id, window_start, window_end)
VALUES ('{{report}}', 'daily', '{OPERATOR}', '{TWIN}', now() - interval '1 day', now());
SELECT public.ottoq_complete_audit_report('{{report}}', jsonb_build_object('seed', '{{tag}}'));
"""


def _seed(d, tag, n):
    d.run(SEED.format(tag=tag, task=f"44444444-0000-4000-8000-00000000000{n}",
                      sched=f"55555555-0000-4000-8000-00000000000{n}", report=f"66666666-0000-4000-8000-00000000000{n}"))


def _load(apply_0701=True, extra_sql=None):
    d = _new_db()
    for path in (GRANTS_STUB, ROTATION_STUB):
        rc, err = d.file(path)
        assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
    if apply_0701:
        rc, err = d.file(M0701_OK)
        assert rc == 0, f"0701 did not apply on the stub: {err}"
    _seed(d, "v1", 1)
    if extra_sql:
        d.run(extra_sql)
    return d


def _apply(d, path, after_sql=None):
    """psql -f in one session, stdout and stderr both kept; after_sql runs in the same session after the file."""
    run = path
    if after_sql:
        fd, run = tempfile.mkstemp(prefix="0722_wrap_", suffix=".sql")
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            fh.write(f"\\i {path}\n{after_sql}\n")
    try:
        p = subprocess.run(["psql", *_conn_args(), "-d", d.name, "-v", "ON_ERROR_STOP=1", "-f", run],
                           capture_output=True, text=True)
    finally:
        if run != path:
            os.remove(run)
    return p.returncode, p.stdout, p.stderr


def _as(d, role, sql):
    rc, out, err = d.run(f"BEGIN; SET LOCAL ROLE {role}; {sql}; ROLLBACK;", check=False)
    return rc == 0, out, (err or out)


def _state(d):
    """Everything 0722 changes, for 'nothing changed' assertions."""
    return (
        _md5s(d, FIVE),
        d.val("SELECT string_agg(key_id || ':' || is_active::text || ':' || coalesce(rotated_at::text, '-'), ' ' ORDER BY key_id) "
              "FROM public.ottoq_signing_keys"),
        d.val("SELECT string_agg(name, ' ' ORDER BY name) FROM vault.secrets"),
        d.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0722%'"),
        d.val("SELECT count(*) FROM public.ottoq_schema_snapshots WHERE label = '0722_pre'"),
    )


@pytest.fixture(scope="module")
def db():
    d = _load()
    try:
        d.before = {
            "md5": _md5s(d, LIVE_MD5),
            "resolver_src": d.val("SELECT md5(prosrc) FROM pg_proc WHERE oid = 'public.ottoq_resolve_signing_secret(text)'::regprocedure"),
            "acl": _acls(d),
            "sig_v1": d.val("SELECT " + SIGN_EVENT.format(key="system:v1")),
            "events": int(d.val("SELECT count(*) FROM public.ottoq_events")),
            "max_seq": int(d.val("SELECT max(event_seq) FROM public.ottoq_events")),
            # the defect: after 0701 the engine still signs every new row with system:v1, a key that may have been read
            "seed_keys": d.val("SELECT string_agg(DISTINCT signature_key_id, ',') || '|' || "
                               "(SELECT string_agg(DISTINCT signature_key_id, ',') FROM public.ottoq_service_detail_records) || '|' || "
                               "(SELECT string_agg(DISTINCT signature_key_id, ',') FROM public.ottoq_audit_bundles) || '|' || "
                               "(SELECT string_agg(DISTINCT signature_key_id, ',') FROM public.ottoq_audit_reports) "
                               "FROM public.ottoq_events"),
        }
        rc, out, err = _apply(d, M0722_OK, after_sql=(
            "SELECT 'AFTER|' || coalesce(current_setting('ottoq.sigcache_' || md5('system:v1'), true), '') || '|'"
            " || coalesce(current_setting('ottoq.sigcache_' || md5('system:v2'), true), '');"))
        assert rc == 0, f"0722 did not apply on the stub: {err}"
        d.out, d.err = out, err
        d.v2_secret = d.val("SELECT secret FROM vault.secrets WHERE name = 'ottoq_signing_key_system_v2'")
        d.after = {"events": int(d.val("SELECT count(*) FROM public.ottoq_events"))}
        yield d
    finally:
        _drop(d)


def test_the_stub_carries_the_live_definitions(db):
    # the ten definitions the stub copied, byte for byte as live; 0701 had replaced the resolver before 0722 ran
    assert db.before["md5"] == LIVE_MD5
    assert db.before["resolver_src"] == "ae44bc24121d3b33e6dcfc94b54b8c28"
    d = _load(apply_0701=False)
    try:
        assert _md5s(d, LIVE_MD5) == LIVE_MD5
        assert d.val("SELECT md5(pg_get_functiondef('public.ottoq_resolve_signing_secret(text)'::regprocedure))") \
            == "b92997a8bcbc41b3c825ad11407c1f66"
        assert d.val("SELECT secret_ref || ':' || is_active::text || ':' || coalesce(rotated_at::text, '-') "
                     "FROM public.ottoq_signing_keys") == "vault:ottoq_signing_key_system_v1:true:-"
    finally:
        _drop(d)


def test_the_file_reports_each_verification(db):
    for tag in ("0722 P2:", "0722 V1 PASSED", "0722 V2 PASSED", "0722 V3 PASSED", "0722 V4 PASSED", "0722 V5 PASSED"):
        assert tag in db.err, db.err
    # P2 read every kind of v1 row the seed made, and each verified before anything changed
    assert "newest v1 rows OLD|event true|sdr true|bundle true" in db.err, db.err


def test_it_refuses_before_0701():
    d = _load(apply_0701=False)
    try:
        # the reason it must: before 0701 a signed-in caller reads whatever key is active
        ok, out, _ = _as(d, "authenticated", "SELECT public.ottoq_resolve_signing_secret('system:v1')")
        assert ok and out == V1_SECRET
        before = _state(d)
        rc, _, err = _apply(d, M0722_OK)
        assert rc != 0 and "0722 P1: 0701 is not applied" in err, err
        assert _state(d) == before
        assert "stub vault read" not in err                                    # it read no secret on the way
        assert d.val("SELECT count(*) FROM vault.secrets WHERE name = 'ottoq_signing_key_system_v2'") == "0"
    finally:
        _drop(d)


def test_as_committed_it_refuses_until_chase_says_go():
    src = open(M0722, encoding="utf-8").read()
    assert src.count(PLACEHOLDER) == 1
    d = _load()
    try:
        before = _state(d)
        rc, err = d.file(M0722)
        assert rc != 0 and "0722 P0a: Chase's go-ahead is not in this file" in err, err
        assert _state(d) == before
        for said in ('go ahead', '2026-10-14: "rotate it"', '2026-10-14, 2:15 PM: "rotate it"',
                     '2026-10-14, 14:15 UTC: "rotate it"'):
            rc, err = d.file(_with_go_ahead(M0722, said))
            assert rc != 0 and "0722 P0a" in err, (said, err)
        assert _state(d) == before
    finally:
        _drop(d)


def test_the_five_defaults_are_v2_and_keep_their_grants(db):
    assert _md5s(db, FIVE) == POST_MD5
    assert _acls(db) == db.before["acl"]
    for s in FIVE[:4]:
        assert "DEFAULT 'system:v2'::text" in db.val(f"SELECT pg_get_function_arguments('{s}'::regprocedure)")
    assert db.val(f"SELECT strpos(prosrc, 'p_signing_key_id => ''system:v2'',') > 0 FROM pg_proc "
                  f"WHERE oid = '{FIVE[4]}'::regprocedure") == "t"
    assert db.val("SELECT count(*) FROM pg_proc WHERE prosrc ~ 'system:v1' OR pg_get_function_arguments(oid) ~ 'system:v1'") == "0"


def test_new_rows_sign_with_v2_and_verify(db):
    # before 0722 (and after 0701) every writer signed with the old key
    assert db.before["seed_keys"] == "system:v1|system:v1|system:v1|system:v1"
    before = int(db.val("SELECT max(event_seq) FROM public.ottoq_events"))
    _seed(db, "v2", 2)
    events = db.val(f"""SELECT string_agg(e.event_type || ':' || e.signature_key_id || ':' || (e.signature ~ '^[0-9a-f]{{64}}$')::text
                                          || ':' || v.valid::text, ' ' ORDER BY e.event_seq)
                          FROM public.ottoq_events e CROSS JOIN LATERAL public.ottoq_verify_event_signature(e.event_id) v
                         WHERE e.event_seq > {before}""")
    assert events == ("stub.seed:system:v2:true:true sdr_issued:system:v2:true:true "
                      "sdr_costs_attached:system:v2:true:true audit.bundle_generated:system:v2:true:true "
                      "audit.report_completed:system:v2:true:true"), events
    sdr = db.val("""SELECT d.signature_key_id || ':' || (public.ottoq_sign_sdr(d.sdr_id, d.ended_at, d.vehicle_id, d.operation_code,
                                                                               d.payload_hash, d.signature_key_id) = d.signature)::text
                      FROM public.ottoq_service_detail_records d
                     WHERE d.schedule_task_id = '44444444-0000-4000-8000-000000000002'""")
    assert sdr == "system:v2:true"
    bundle = db.val("""SELECT b.signature_key_id || ':' || v.out_valid::text
                         FROM public.ottoq_audit_bundles b CROSS JOIN LATERAL public.ottoq_verify_audit_bundle(b.bundle_id) v
                        WHERE b.bundle_code = 'bundle-v2'""")
    assert bundle == "system:v2:true"
    report = db.val("""SELECT signature_key_id || ':' || (signature ~ '^[0-9a-f]{64}$')::text
                         FROM public.ottoq_audit_reports WHERE report_id = '66666666-0000-4000-8000-000000000002'""")
    assert report == "system:v2:true"


def test_every_v1_row_still_verifies(db):
    got = db.val("""SELECT count(*) || '/' || count(*) FILTER (WHERE v.valid)
                      FROM public.ottoq_events e CROSS JOIN LATERAL public.ottoq_verify_event_signature(e.event_id) v
                     WHERE e.signature_key_id = 'system:v1'""")
    assert got == "5/5", got
    sdr = db.val("""SELECT (public.ottoq_sign_sdr(d.sdr_id, d.ended_at, d.vehicle_id, d.operation_code, d.payload_hash,
                                                  d.signature_key_id) = d.signature)::text
                      FROM public.ottoq_service_detail_records d WHERE d.signature_key_id = 'system:v1'""")
    assert sdr == "true"
    bundle = db.val("""SELECT v.out_valid::text FROM public.ottoq_audit_bundles b
                         CROSS JOIN LATERAL public.ottoq_verify_audit_bundle(b.bundle_id) v WHERE b.signature_key_id = 'system:v1'""")
    assert bundle == "true"


def test_v2_signs_differently_and_v1_did_not_move(db):
    v1 = db.val("SELECT " + SIGN_EVENT.format(key="system:v1"))
    v2 = db.val("SELECT " + SIGN_EVENT.format(key="system:v2"))
    assert v1 == db.before["sig_v1"]
    assert re.fullmatch(r"[0-9a-f]{64}", v2) and v2 != v1


def test_the_registry_and_vault(db):
    v1 = db.val("""SELECT is_active::text || '|' || (rotated_at IS NOT NULL)::text || '|' || (rotation_reason ~ 'G428')::text
                          || '|' || secret_ref FROM public.ottoq_signing_keys WHERE key_id = 'system:v1'""")
    assert v1 == "true|true|true|vault:ottoq_signing_key_system_v1"
    v2 = db.val("""SELECT scope || '|' || coalesce(scope_id::text, '-') || '|' || algorithm || '|' || secret_ref || '|'
                          || is_active::text || '|' || (rotated_at IS NULL)::text || '|' || created_by
                     FROM public.ottoq_signing_keys WHERE key_id = 'system:v2'""")
    assert v2 == ("system|-|HMAC-SHA-256|vault:ottoq_signing_key_system_v2|true|true|"
                  "migration:0722_the_engine_signs_with_a_new_key_and_every_old_signature_still_verifies")
    assert re.fullmatch(r"[0-9a-f]{64}", db.v2_secret)                      # 32 random bytes, hex
    assert db.val("SELECT secret FROM vault.secrets WHERE name = 'ottoq_signing_key_system_v1'") == V1_SECRET   # untouched
    desc = db.val("SELECT description FROM vault.secrets WHERE name = 'ottoq_signing_key_system_v2'")
    assert "key_id=system:v2" in desc and "do NOT overwrite this one" in desc
    snaps = db.val("SELECT string_agg(object_kind, ',' ORDER BY snapshot_id) FROM public.ottoq_schema_snapshots "
                   "WHERE label = '0722_pre'")
    assert snaps == "function,function,function,function,function,registry_row"


def _code(path):
    """The file's executable text: comments stripped (none of its string literals holds a double hyphen)."""
    src = open(path, encoding="utf-8").read()
    return "\n".join(re.sub(r"--.*$", "", line) for line in src.splitlines())


def test_no_secret_is_ever_selected(db):
    code = _code(M0722)
    # with its string literals emptied, so a quoted signature (P1's to_regprocedure lookups) is not taken for a call
    calls_only = re.sub(r"'(?:[^']|'')*'", "''", code)
    # the file names no decrypted secret, never calls the resolver, and never reads a secret column
    assert "decrypted" not in code
    assert not re.search(r"ottoq_resolve_signing_secret\s*\(", calls_only)
    assert not re.search(r"\.secret\b", code)
    # the new secret is made in the database: one call, its value an expression, never a literal
    calls = re.findall(r"vault\.create_secret\(\s*(.{0,48})", calls_only, re.S)
    assert len(calls) == 1 and calls[0].startswith("encode(extensions.gen_random_bytes(32), ''),"), calls
    # every read of a secret while it applied came through the resolver (inside a signer); v2 was read, by V3 and V4
    reads = re.findall(r"stub vault read: (\S+) \(through the resolver: (\w+)\)", db.err)
    assert reads and all(via == "true" for _, via in reads), reads
    assert {"ottoq_signing_key_system_v1", "ottoq_signing_key_system_v2"} <= {name for name, _ in reads}
    # and neither secret is in anything it printed, wrote, or left in its session
    for secret in (V1_SECRET, db.v2_secret):
        assert secret not in db.out and secret not in db.err
        assert db.val(f"SELECT count(*) FROM public.ottoq_cert_lineage WHERE note LIKE '%{secret}%'") == "0"
        assert db.val(f"SELECT count(*) FROM public.ottoq_schema_snapshots WHERE definition LIKE '%{secret}%'") == "0"
        assert db.val(f"SELECT count(*) FROM public.ottoq_signing_keys k WHERE k::text LIKE '%{secret}%'") == "0"
        assert db.val(f"SELECT count(*) FROM public.ottoq_events e WHERE e::text LIKE '%{secret}%'") == "0"
    assert "AFTER||" in db.out, db.out                                          # no signing cache outlived the apply


def test_the_read_instrument_sees_a_direct_select():
    # the NOTICE check above is only worth something if it would catch a file that DID read a secret: a copy of 0722
    # that peeks at the new secret directly is caught, and the value it read is what the output check looks for
    src = open(M0722_OK, encoding="utf-8").read()
    anchor = "INSERT INTO public.ottoq_cert_lineage"
    assert src.count(anchor) == 1
    peek = ("DO $peek$ BEGIN PERFORM (SELECT s.decrypted_secret FROM vault.decrypted_secrets s "
            "WHERE s.name = 'ottoq_signing_key_system_v2'); END $peek$;\n\n")
    fd, bad = tempfile.mkstemp(prefix="0722_peek_", suffix=".sql")
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(src.replace(anchor, peek + anchor))
    d = _load()
    try:
        rc, _, err = _apply(d, bad)
        assert rc == 0, err
        reads = re.findall(r"stub vault read: (\S+) \(through the resolver: (\w+)\)", err)
        assert ("ottoq_signing_key_system_v2", "false") in reads, reads
    finally:
        _drop(d)
        os.remove(bad)


def test_the_browser_roles_cannot_read_or_use_the_new_key(db):
    for role in ("authenticated", "anon"):
        for sql in ("SELECT public.ottoq_resolve_signing_secret('system:v2')", "SELECT " + SIGN_EVENT.format(key="system:v2")):
            ok, _, msg = _as(db, role, sql)
            assert not ok and "permission denied for function" in msg, (role, sql, msg)


def test_the_event_log_was_only_appended(db):
    # V4's probe event was written and rolled back; nothing was updated or deleted (the guard would have refused)
    assert db.after["events"] == db.before["events"]
    assert db.val("SELECT count(*) FROM public.ottoq_events WHERE event_type = 'migration.0722_probe'") == "0"
    assert db.val("SELECT count(*) FROM public.ottoq_events WHERE signature_key_id = 'system:v1'") == "5"


def test_the_ledger_classifies_it_and_keeps_the_go_ahead(db):
    row = db.val("SELECT forces_recert::text || forces_dial_restart::text || '|' || note FROM public.ottoq_cert_lineage "
                 "WHERE name = '0722_the_engine_signs_with_a_new_key_and_every_old_signature_still_verifies'")
    assert row.startswith("falsefalse|G428, the rotation half (after 0701)")
    assert row.endswith("Chase's go-ahead (FINDINGS G428): " + STAND_IN), row


def test_it_refuses_a_second_run(db):
    rc, _, err = _apply(db, M0722_OK)
    assert rc != 0 and "0722 P1" in err, err
    assert db.val("SELECT count(*) FROM public.ottoq_cert_lineage WHERE name LIKE '0722%'") == "1"
    assert db.val("SELECT count(*) FROM vault.secrets WHERE name = 'ottoq_signing_key_system_v2'") == "1"


def test_the_restore_statements_put_the_v1_defaults_back():
    d = _load()
    try:
        rc, _, err = _apply(d, M0722_OK)
        assert rc == 0, err
        _seed(d, "v2", 2)                                                       # rows signed while v2 was the default
        d.run("""DO $restore$ DECLARE r record; BEGIN
                   FOR r IN SELECT definition FROM public.ottoq_schema_snapshots WHERE label = '0722_pre' ORDER BY snapshot_id LOOP
                     EXECUTE r.definition;
                   END LOOP; END $restore$""")
        assert _md5s(d, FIVE) == {s: LIVE_MD5[s] for s in FIVE}
        assert d.val("SELECT coalesce(rotated_at::text, '-') || coalesce(rotation_reason, '-') FROM public.ottoq_signing_keys "
                     "WHERE key_id = 'system:v1'") == "--"
        _seed(d, "v1b", 3)
        last = d.val("SELECT signature_key_id FROM public.ottoq_events ORDER BY event_seq DESC LIMIT 1")
        assert last == "system:v1"
        # v2 stays active, so what it signed still verifies
        got = d.val("""SELECT count(*) || '/' || count(*) FILTER (WHERE v.valid)
                         FROM public.ottoq_events e CROSS JOIN LATERAL public.ottoq_verify_event_signature(e.event_id) v
                        WHERE e.signature_key_id = 'system:v2'""")
        assert got == "5/5", got
    finally:
        _drop(d)


@pytest.mark.parametrize("extra, message", [
    # someone hotfixed a writer since the pin
    ("CREATE OR REPLACE FUNCTION public.ottoq_trg_attribution_attach() RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER "
     "AS $f$ BEGIN RETURN NEW; END $f$",
     "0722 P1: public.ottoq_trg_attribution_attach() is not the definition this file was written against"),
    # a v2 key half-made by hand: the registry row, or the Vault secret
    ("INSERT INTO public.ottoq_signing_keys (key_id, scope, secret_ref, is_active) "
     "VALUES ('system:v2', 'system', 'vault:ottoq_signing_key_system_v2', false)",
     "0722 P1: a system:v2 registry row exists already"),
    ("SELECT vault.create_secret('made-by-hand', 'ottoq_signing_key_system_v2', '')",
     "0722 P1: a Vault secret named ottoq_signing_key_system_v2 exists already"),
    # another function names the v1 key and would keep signing with it
    ("CREATE FUNCTION public.ottoq_new_writer() RETURNS text LANGUAGE sql AS $f$ SELECT 'system:v1'::text $f$",
     "0722 P1: functions other than the five name system:v1: ottoq_new_writer()"),
    # v1 is not the key this file was written against
    ("UPDATE public.ottoq_signing_keys SET secret_ref = 'env:OTTOQ_SIGNING' WHERE key_id = 'system:v1'",
     "0722 P1: system:v1 is not the active, Vault-backed, unrotated system key"),
    ("UPDATE public.ottoq_signing_keys SET rotated_at = now() WHERE key_id = 'system:v1'",
     "0722 P1: system:v1 is not the active, Vault-backed, unrotated system key"),
    # a certification in flight
    ("UPDATE public.stub_in_flight SET n = 1", "0722 P0: a pair, the recert runner"),
])
def test_it_refuses_a_world_it_was_not_written_against(extra, message):
    d = _load(extra_sql=extra)
    try:
        before = _state(d)
        rc, _, err = _apply(d, M0722_OK)
        assert rc != 0 and message in err, err
        assert _state(d) == before
    finally:
        _drop(d)
