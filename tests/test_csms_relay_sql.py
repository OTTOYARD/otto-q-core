"""db/migrations/0697, the charger back end's relay, EXECUTED on the v2 door's stub engine.

0697 extends 0649's source keys (a charger_backend key, registered by its hash so the key never reaches the database)
and gives such a key, on the twin's data source, its depot's station frames after a cursor and a place to report what a
real OCPP 2.0.1 back end did with them. Its V1 and V2 run here for real: the stub engine plus 0649, a charger log with
the twin depot's frames and another depot's, then 0697 itself. SKIPS where no scratch PostgreSQL is reachable.
"""
import hashlib
import json
import os
import sys

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sys.path.insert(0, os.path.join(ROOT, "tests"))
from test_v2_door_sql import MIG, SEED, STUB, TWIN, _drop, _new_db, _server_up, q  # noqa: E402

M0697 = os.path.join(ROOT, "db", "migrations", "0697_the_charger_back_end_hears_the_twins_chargers_through_a_relay.sql")
OTHER = "22222222-2222-2222-2222-222222222222"

pytestmark = pytest.mark.skipif(not _server_up(), reason="no scratch PostgreSQL reachable (PGHOST or /var/tmp:55432)")


def key(c):
    k = "ottow_" + c * 32
    return k, hashlib.sha256(k.encode()).hexdigest()


@pytest.fixture(scope="module")
def db():
    d = _new_db()
    try:
        for path in (STUB, SEED, MIG["0649"]):
            rc, err = d.file(path)
            assert rc == 0, f"{os.path.basename(path)} did not load: {err}"
        d.run(f"""
          INSERT INTO public.depots (id, name) VALUES ('{OTHER}', 'another depot') ON CONFLICT DO NOTHING;
          ALTER TABLE public.ottoq_ocpp_chargers ADD COLUMN IF NOT EXISTS vendor text, ADD COLUMN IF NOT EXISTS model text,
            ADD COLUMN IF NOT EXISTS serial_number text, ADD COLUMN IF NOT EXISTS firmware_version text,
            ADD COLUMN IF NOT EXISTS max_kw numeric, ADD COLUMN IF NOT EXISTS num_connectors int,
            ADD COLUMN IF NOT EXISTS decommissioned_at timestamptz;
          INSERT INTO public.ottoq_ocpp_chargers (charger_id, depot_id, ocpp_identifier, station_state, vendor, model,
                                                 firmware_version, max_kw, num_connectors) VALUES
            ('c0000000-0000-0000-0000-000000000001', '{TWIN}', 'NASH-L2-08', 'Available', 'ChargePoint', 'CT4000 Family', '5.105.1', 19.2, 1),
            ('c0000000-0000-0000-0000-000000000002', '{TWIN}', 'NASH-DCFC-04', 'Available', 'ABB', 'Terra HP 350', '1.4.2', 350, 1),
            ('c0000000-0000-0000-0000-000000000003', '{OTHER}', 'BENCH-L2-01', 'Available', 'ChargePoint', 'CT4000 Family', '5.105.1', 19.2, 1);
          CREATE TABLE public.ottoq_ocpp_messages (message_seq bigint PRIMARY KEY, charger_id uuid, sim_run_id uuid,
            sim_clock_at timestamptz, direction text NOT NULL, message_type text NOT NULL, payload jsonb NOT NULL,
            data_source text NOT NULL);
          INSERT INTO public.ottoq_ocpp_messages VALUES
            (101, 'c0000000-0000-0000-0000-000000000001', NULL, NULL, 'cs_to_csms', 'StatusNotification', '{{"evseId":1}}', 'twin'),
            (102, 'c0000000-0000-0000-0000-000000000003', NULL, NULL, 'cs_to_csms', 'StatusNotification', '{{"evseId":1}}', 'twin'),
            (103, 'c0000000-0000-0000-0000-000000000002', NULL, NULL, 'csms_to_cs', 'SetChargingProfile', '{{"evseId":1}}', 'twin'),
            (104, 'c0000000-0000-0000-0000-000000000002', NULL, NULL, 'cs_to_csms', 'TransactionEvent', '{{"seqNo":0}}', 'twin'),
            (105, 'c0000000-0000-0000-0000-000000000001', NULL, NULL, 'cs_to_csms', 'TransactionEvent', '{{"seqNo":0}}', 'production'),
            (106, 'c0000000-0000-0000-0000-000000000001', NULL, NULL, 'cs_to_csms', 'TransactionEvent', '{{"seqNo":1}}', 'twin');
        """)
        rc, err = d.file(M0697)
        assert rc == 0, f"0697 did not apply on the stub: {err}"
        yield d
    finally:
        _drop(d)


def register(db, c, source="charger_backend", data_source="twin", streams=("ocpp",)):
    k, h = key(c)
    db.json(f"SELECT ottoq_register_source_key_hash('{TWIN}', {q(source)}, {q('test ' + c)}, {q(h)}, {q(k[:14])}, "
            f"{q(data_source)}, ARRAY[{','.join(q(s) for s in streams)}]::text[])")
    return h


def pull(db, h, after, limit=200, chargers=False):
    return db.json(f"SELECT ottoq_csms_pull({q(h)}, {after}, {limit}, {str(chargers).lower()})")


def test_0697_ran_its_own_v1_and_v2_on_the_stub_and_classified_itself(db):
    assert db.val("SELECT forces_recert::text || forces_dial_restart::text FROM ottoq_cert_lineage "
                  "WHERE name = '0697_the_charger_back_end_hears_the_twins_chargers_through_a_relay'") == "falsefalse"
    assert "charger_backend" in db.val("SELECT pg_get_constraintdef(oid) FROM pg_constraint WHERE conname = 'ottow_api_keys_source_check'")
    assert db.val("SELECT count(*) FROM ottow_api_keys WHERE source = 'charger_backend'") == "0"   # V1's keys rolled back


def test_a_key_made_elsewhere_is_stored_by_its_hash_and_prefix_only(db):
    h = register(db, "e5")
    row = db.json("SELECT json_build_object('hash', key_hash, 'prefix', key_prefix, 'source', source, 'ds', data_source, "
                  f"'streams', streams) FROM ottow_api_keys WHERE key_hash = {q(h)}")
    assert row == {"hash": h, "prefix": "ottow_e5e5e5e5", "source": "charger_backend", "ds": "twin", "streams": ["ocpp"]}
    # and the key itself appears nowhere in the table
    assert db.val("SELECT count(*) FROM ottow_api_keys WHERE to_jsonb(ottow_api_keys)::text LIKE '%" + "e5" * 32 + "%'") == "0"


def test_the_twin_depots_station_frames_come_out_in_order_after_the_cursor(db):
    h = register(db, "f6")
    head = pull(db, h, -1, chargers=True)
    assert head["ok"] and head["rows"] == [] and head["next_after"] == 106
    assert [c["ocpp_identifier"] for c in head["chargers"]] == ["NASH-DCFC-04", "NASH-L2-08"]
    assert head["chargers"][1]["vendor"] == "ChargePoint" and head["chargers"][1]["firmware_version"] == "5.105.1"
    page = pull(db, h, 0)
    # not the other depot's charger (102), not the back end's own frame (103), not production's (105)
    assert [r["message_seq"] for r in page["rows"]] == [101, 104, 106] and page["next_after"] == 106 and page["more"] is False
    assert pull(db, h, 0, limit=2)["more"] is True and pull(db, h, 0, limit=2)["next_after"] == 104
    assert pull(db, h, 106)["rows"] == [] and pull(db, h, 106)["next_after"] == 106


def test_only_a_charger_backend_twin_key_with_the_ocpp_stream_reads_frames(db):
    assert pull(db, register(db, "a7", data_source="production"), 0)["reason"] == "pull_is_for_the_twin"
    assert pull(db, register(db, "b8", streams=("telemetry",)), 0)["reason"] == "stream_not_allowed"
    assert pull(db, register(db, "c9", source="fleet_api"), 0)["reason"] == "not_a_charger_backend_key"
    assert pull(db, "0" * 64, 0)["reason"] == "unknown_or_revoked_key"


def test_a_report_is_kept_as_counted_and_one_that_does_not_add_up_is_refused(db):
    h = register(db, "d0")
    ok = db.json(f"SELECT ottoq_csms_report({q(h)}, {q(json.dumps({'from_seq': 101, 'to_seq': 106, 'frames': 3, 'outcomes': {'accepted': 3}, 'by_action': {'TransactionEvent:accepted': 2, 'StatusNotification:accepted': 1}, 'transactions': {'transactions': 1, 'transactions_ended': 0}, 'bridge': {'ocpp': '2.1.0'}}))}::jsonb)")
    assert ok["ok"]
    assert db.val(f"SELECT accepted || '/' || frames || '/' || data_source FROM ottoq_csms_reports WHERE report_id = {ok['report_id']}") == "3/3/twin"
    bad = db.json(f"SELECT ottoq_csms_report({q(h)}, {q(json.dumps({'from_seq': 1, 'to_seq': 2, 'frames': 4, 'outcomes': {'accepted': 3}}))}::jsonb)")
    assert bad == {"ok": False, "reason": "report_does_not_add_up"}


def test_the_public_key_reaches_none_of_it(db):
    for f in ("public.ottoq_csms_pull(text,bigint,integer,boolean)", "public.ottoq_csms_report(text,jsonb)",
              "public.ottoq_register_source_key_hash(uuid,text,text,text,text,text,text[])"):
        assert db.val(f"SELECT has_function_privilege('anon', {q(f)}, 'EXECUTE')") == "f", f
        assert db.val(f"SELECT has_function_privilege('service_role', {q(f)}, 'EXECUTE')") == "t", f
    assert db.val("SELECT has_table_privilege('anon', 'public.ottoq_csms_reports', 'SELECT')") == "f"
