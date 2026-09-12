"""bridge/llm_proposer.py -- every path, no model.

FakeClient stands in for the provider. The digest, the answer->rows harness, the
cost meter, the cap, the failure modes and the SQL emission are all exercised
here; the only thing NOT exercised is the network call, which is the one thing
CI must never make.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

import pytest

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))

from bridge import llm_proposer as lp  # noqa: E402
from bridge import proposer_bridge as pb  # noqa: E402
from bridge.test_proposer_bridge import (  # noqa: E402
    DEPOT, RUN, S1, S2, S3, V1, V2, V3, _frame, _stall, _vehicle,
)

_DOOR = re.compile(r"SELECT public\.ottoq_submit_external_proposal\(")
_BATCH = re.compile(r"SELECT public\.ottoq_proposer_submit_batch\(")


def _answer(*items, rationale="fixture"):
    return {"proposals": list(items), "rationale": rationale}


def _p(vid, sid, reason="lowest soc to a fast plug", abstain=False):
    return {"vehicle_id": vid, "stall_id": sid, "abstain": abstain, "reason": reason}


GOOD = _answer(_p(V1, S1), _p(V2, S2), _p(V3, S3, "l2 only"))


def _fire(answer=GOOD, *, model="claude-sonnet-5", frame=None, usage=None, **kw):
    client = lp.FakeClient(answer, model=model, usage=usage)
    r = lp.fire_llm(frame or _frame(), client=client, model=model, sim_run_id=RUN,
                    depot_id=DEPOT, fired_at="2026-09-12T18:30:00+00:00", **kw)
    r["client"] = client
    return r


# ---- digest ---------------------------------------------------------------------

def test_digest_shows_serviceable_vehicles_lowest_soc_first_and_every_charge_stall():
    frame = _frame(vehicles=[_vehicle(V1, soc=40), _vehicle(V2, soc=25),
                             _vehicle(V3, soc=30, state="offline")],
                   stalls=[_stall(S1), _stall(S2, kind="l2", kw=19),
                           {"id": S3, "type": "staging", "status": "available", "vehicle_id": None,
                            "connector_type": None, "connector_max_kw": None,
                            "supported_inlet_types": None}])
    d = lp.frame_digest(frame)
    assert [v["id"] for v in d["vehicles"]] == [V2, V1]        # offline excluded, soc asc
    assert [s["id"] for s in d["stalls"]] == [S1, S2]          # staging excluded, dcfc first
    assert d["omitted"] == {"vehicles": 0, "stalls": 0}


def test_digest_keeps_occupied_stalls_visible_so_the_shield_can_refuse_them():
    occupied = _stall(S1); occupied["vehicle_id"] = V2; occupied["status"] = "occupied"
    d = lp.frame_digest(_frame(stalls=[occupied, _stall(S2)]))
    s1 = next(s for s in d["stalls"] if s["id"] == S1)
    assert s1["vehicle_id"] == V2 and s1["status"] == "occupied"


def test_digest_truncation_is_counted_not_silent():
    vs = [_vehicle(f"6e7d0b1c-0000-4000-8000-0000000000{i:02x}", soc=10 + i) for i in range(30)]
    d = lp.frame_digest(_frame(vehicles=vs), max_vehicles=24, max_stalls=2)
    assert len(d["vehicles"]) == 24 and d["omitted"]["vehicles"] == 6
    assert len(d["stalls"]) == 2 and d["omitted"]["stalls"] == 1


def test_prompts_are_byte_stable_and_carry_no_clock():
    d = lp.frame_digest(_frame())
    assert lp.user_prompt(d) == lp.user_prompt(json.loads(json.dumps(d)))
    assert "2026" not in lp.SYSTEM_PROMPT and RUN not in lp.SYSTEM_PROMPT


# ---- the harness: answer -> rows ------------------------------------------------------

def test_a_good_answer_becomes_one_door_row_per_vehicle_with_computed_kw():
    r = _fire()
    rows, rec = r["rows"], r["fire"]
    assert rec["status"] == "proposed" and rec["n_planned"] == 3 and rec["n_abstained"] == 0
    assert rec["n_harness_rejected"] == 0
    by = {x["entity_id"]: x["proposal"] for x in rows}
    assert by[V1]["stall_id"] == S1 and by[V1]["stall_type"] == "dcfc"
    assert by[V1]["requested_kw"] == 100.0           # min(stall 150, inlet 100)
    assert by[V3]["stall_id"] == S3 and by[V3]["stall_type"] == "l2"
    assert by[V3]["requested_kw"] == 19.0
    for p in by.values():
        assert p["verb"] == "assign_stall" and p["abstain"] is False
        assert p["rationale"]["optimizer"] == "llm_advisor"
        assert p["rationale"]["model"] == "claude-sonnet-5"
    assert all(x["source"] == "llm_advisor" for x in rows)


def test_requested_kw_is_never_taken_from_the_model():
    bad = _answer({**_p(V1, S1), "requested_kw": 9999})
    r = _fire(bad, frame=_frame(vehicles=[_vehicle(V1, soc=20)]))
    assert r["rows"][0]["proposal"]["requested_kw"] == 100.0


def test_an_unknown_stall_is_a_harness_abstention_not_a_row_the_tick_could_choke_on():
    r = _fire(_answer(_p(V1, "not-a-stall")), frame=_frame(vehicles=[_vehicle(V1)]))
    row = r["rows"][0]
    assert row["proposal"]["abstain"] is True
    assert "not in the digest" in row["proposal"]["rationale"]["reason"]
    assert row["proposal"]["rationale"]["abstained_by"] == "harness"
    assert r["fire"]["harness_rejections"][0]["kind"] == "unknown_stall"
    assert r["fire"]["status"] == "empty"


def test_a_stall_named_twice_serves_the_first_vehicle_only():
    r = _fire(_answer(_p(V1, S1), _p(V2, S1)), frame=_frame(vehicles=[_vehicle(V1), _vehicle(V2)]))
    by = {x["entity_id"]: x["proposal"] for x in r["rows"]}
    assert by[V1]["abstain"] is False and by[V1]["stall_id"] == S1
    assert by[V2]["abstain"] is True and "second vehicle" in by[V2]["rationale"]["reason"]
    assert [x["kind"] for x in r["fire"]["harness_rejections"]] == ["duplicate_stall"]


def test_a_vehicle_the_model_ignores_or_names_twice_or_invents_is_handled():
    frame = _frame(vehicles=[_vehicle(V1), _vehicle(V2)])
    ghost = "6e7d0b1c-0000-4000-8000-0000000000ff"
    r = _fire(_answer(_p(V1, S1), _p(V1, S2), _p(ghost, S3)), frame=frame)
    by = {x["entity_id"]: x["proposal"] for x in r["rows"]}
    assert by[V1]["stall_id"] == S1
    assert by[V2]["abstain"] is True and "no answer" in by[V2]["rationale"]["reason"]
    kinds = sorted(x["kind"] for x in r["fire"]["harness_rejections"])
    assert kinds == ["duplicate_vehicle", "unknown_vehicle"]
    assert set(by) == {V1, V2}


def test_a_model_abstention_keeps_its_reason():
    r = _fire(_answer(_p(V1, None, "site near cap", abstain=True)), frame=_frame(vehicles=[_vehicle(V1)]))
    p = r["rows"][0]["proposal"]
    assert p["abstain"] is True and p["rationale"]["reason"] == "site near cap"
    assert p["rationale"]["abstained_by"] == "model"


def test_unparseable_output_is_an_error_status_with_every_vehicle_abstained():
    r = _fire("I would suggest... (no JSON)")
    assert r["fire"]["error"].startswith("model returned no parseable JSON")
    assert len(r["rows"]) == 3 and all(x["proposal"]["abstain"] for x in r["rows"])
    assert r["fire"]["status"] == "empty"


def test_prose_wrapped_json_is_tolerated():
    text = "Here you go:\n" + json.dumps(GOOD) + "\nHope that helps."
    r = _fire(text)
    assert r["fire"]["status"] == "proposed" and r["fire"]["n_planned"] == 3


def test_a_refusal_is_an_error_with_no_rows():
    client = lp.FakeClient(GOOD, stop_reason="refusal")
    r = lp.fire_llm(_frame(), client=client, model="claude-sonnet-5", sim_run_id=RUN, depot_id=DEPOT)
    assert r["rows"] == [] and r["fire"]["status"] == "error"
    assert "refus" in r["fire"]["error"]


def test_a_client_exception_is_a_ledger_fact_not_a_crash():
    def boom(system, user, schema):
        raise RuntimeError("socket closed")
    r = lp.fire_llm(_frame(), client=boom, model="claude-sonnet-5", sim_run_id=RUN, depot_id=DEPOT)
    assert r["fire"]["status"] == "error" and "RuntimeError: socket closed" in r["fire"]["error"]


def test_no_serviceable_vehicle_means_no_call_and_an_empty_fire():
    r = _fire(frame=_frame(vehicles=[_vehicle(V1, state="offline")]))
    assert r["fire"]["status"] == "empty" and r["client"].calls == 0


# ---- cost and cap -------------------------------------------------------------------

def test_cost_uses_the_price_table_and_cache_multipliers():
    u = {"input_tokens": 4000, "output_tokens": 500, "cache_read_input_tokens": 2000,
         "cache_creation_input_tokens": 1000}
    # sonnet-5: 4000*2 + 500*10 + 2000*2*0.1 + 1000*2*1.25 = 8000+5000+400+2500 = 15900 / 1e6
    assert lp.cost_usd("claude-sonnet-5", u) == pytest.approx(0.0159)
    # opus-5: 4000*5 + 500*25 + 2000*5*0.1 + 1000*5*1.25 = 20000+12500+1000+6250 = 39750 / 1e6
    assert lp.cost_usd("claude-opus-5", u) == pytest.approx(0.03975)
    assert lp.cost_usd("nvidia/nemotron-3-ultra-550b-a55b", u) is None
    assert lp.cost_usd("claude-opus-5", None) is None


def test_the_fire_record_prices_the_call_and_accumulates_in_the_ledger(tmp_path):
    ledger = lp.SpendLedger(tmp_path / "spend.json")
    r1 = _fire(usage={"input_tokens": 5000, "output_tokens": 500}, ledger=ledger)
    assert r1["fire"]["usd"] == pytest.approx(0.015)                 # 5000*2 + 500*10 = 15000 / 1e6
    assert r1["fire"]["spent_before_usd"] == 0.0
    assert r1["fire"]["spent_after_usd"] == pytest.approx(0.015)
    assert r1["fire"]["price_source"].startswith("claude-api skill")
    again = lp.SpendLedger(tmp_path / "spend.json")                 # survives a new process
    assert again.spent(RUN) == pytest.approx(0.015)


def test_the_cap_refuses_before_the_model_is_called(tmp_path):
    ledger = lp.SpendLedger(tmp_path / "spend.json")
    ledger.add(RUN, 2.00)
    r = _fire(ledger=ledger, cap_usd=2.00)
    assert r["fire"]["status"] == "refused_cap" and r["client"].calls == 0
    assert r["rows"] == [] and "2.00 USD cap" in r["fire"]["error"]


def test_an_unpriced_model_is_refused_unless_allowed():
    r = _fire(model="nvidia/nemotron-3-ultra-550b-a55b")
    assert r["fire"]["status"] == "refused_unpriced" and r["client"].calls == 0
    r2 = _fire(model="nvidia/nemotron-3-ultra-550b-a55b", allow_unpriced=True)
    assert r2["fire"]["status"] == "proposed" and r2["fire"]["usd"] is None


# ---- SQL emission ----------------------------------------------------------------------

def test_rows_go_out_through_the_door_with_the_advisor_source():
    r = _fire()
    sql = pb.emit_sql(r, sim_run_id=RUN, depot_id=DEPOT, ttl_seconds=45)
    assert len(_DOOR.findall(sql)) == 3
    assert all(l.endswith(", 'llm_advisor', 45);") for l in sql.splitlines() if l.startswith("SELECT"))
    assert "insert" not in sql.lower()
    batch = pb.emit_sql(r, sim_run_id=RUN, depot_id=DEPOT, via="batch")
    assert len(_BATCH.findall(batch)) == 1 and "'llm_advisor'," in batch


def test_a_mixed_source_batch_is_refused():
    r = _fire()
    r["rows"][0]["source"] = "forward_lex"
    with pytest.raises(pb.BridgeError, match="one source"):
        pb.batch_call_sql(r["rows"], r["fire"], sim_run_id=RUN, depot_id=DEPOT)


def test_the_module_holds_no_key_no_insert_and_no_production_identifier():
    src = (HERE / "llm_proposer.py").read_text()
    assert "sk-ant-" not in src and "nvapi-" not in src
    assert "gxdrcyphqjzjsuhxuqtg" not in src and "ycsisvozzgmisboumfqc" not in src
    body = src.split('"""', 2)[2]
    assert "INSERT INTO" not in body.upper()


# ---- providers without their packages --------------------------------------------------

def test_anthropic_client_names_the_missing_sdk(monkeypatch):
    monkeypatch.setitem(sys.modules, "anthropic", None)   # import raises ImportError
    with pytest.raises(pb.BridgeError, match="anthropic SDK"):
        lp.AnthropicClient("claude-opus-5")


def test_nvidia_client_needs_its_key_from_the_environment(monkeypatch):
    monkeypatch.delenv("NVIDIA_API_KEY_NEMOTRON", raising=False)
    with pytest.raises(pb.BridgeError, match="NVIDIA_API_KEY_NEMOTRON"):
        lp.OpenAICompatibleClient("nvidia/nemotron-3-ultra-550b-a55b")


# ---- CLI ---------------------------------------------------------------------------------

def test_cli_offline_with_a_canned_answer(tmp_path, capsys):
    frame_p, ans_p = tmp_path / "frame.json", tmp_path / "answer.json"
    frame_p.write_text(json.dumps(_frame()))
    ans_p.write_text(json.dumps(GOOD))
    out_sql, out_json, spend = tmp_path / "o.sql", tmp_path / "o.json", tmp_path / "spend.json"
    rc = lp.main(["--run", RUN, "--depot", DEPOT, "--frame", str(frame_p),
                  "--provider", "fake", "--answer", str(ans_p), "--model", "claude-sonnet-5",
                  "--cap-usd", "1.00", "--spend-file", str(spend),
                  "--emit-sql", str(out_sql), "--json-out", str(out_json)])
    assert rc == 0
    assert len(_DOOR.findall(out_sql.read_text())) == 3
    res = json.loads(out_json.read_text())
    assert res["fire"]["status"] == "proposed" and res["fire"]["usd"] == pytest.approx(0.004)
    assert json.loads(spend.read_text())[RUN] == pytest.approx(0.004)
    assert '"status": "proposed"' in capsys.readouterr().err


def test_cli_exit_code_signals_a_refused_fire(tmp_path):
    frame_p, ans_p = tmp_path / "frame.json", tmp_path / "answer.json"
    frame_p.write_text(json.dumps(_frame()))
    ans_p.write_text(json.dumps(GOOD))
    rc = lp.main(["--run", RUN, "--depot", DEPOT, "--frame", str(frame_p),
                  "--provider", "fake", "--answer", str(ans_p),
                  "--model", "some/unpriced-model", "--emit-sql", str(tmp_path / "o.sql")])
    assert rc == 3
