"""C9 tests — the ladder, the swap proof, the event contract, the refusal path.

    python3 recall/test_recall.py
"""

from __future__ import annotations

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from recall_decision import (AssetState, FixedWindowRecall, NaiveThresholdRecall,
                             RecallEventLog, SiteForecast, WorkSideSignals,
                             make_recall, run_recall_cycle)

SITE = SiteForecast(sim_min_now=600, eta_min=12, free_capable_points=4,
                    inbound_assets=2)
WORK = WorkSideSignals(mission_active=True)
BASE = dict(asset_id="V-01", soc_pct=80, reserve_soc_pct=10,
            deploy_floor_pct=35, home_site="site_alpha")


def A(**kw):
    return AssetState(**{**BASE, **kw})


def test_ladder():
    n = NaiveThresholdRecall()
    # rung 0: reserve + burn guard (0.25 * (12+30) = 10.5 -> threshold 20.5)
    assert n.decide(A(soc_pct=20), WORK, SITE).trigger == "critical_reserve"
    # rung order: a safety fault on a low-SoC asset still reports the reserve
    # rung first (top-down, first hit wins — as live)
    assert n.decide(A(soc_pct=20, worst_fault_rank=0), WORK, SITE).trigger == "critical_reserve"
    assert n.decide(A(worst_fault_rank=0), WORK, SITE).trigger == "fault_safety_critical"
    assert n.decide(A(worst_fault_rank=1), WORK, SITE).trigger == "fault_major"
    assert n.decide(A(open_fault_count=3), WORK, SITE).trigger == "fault_major"
    assert n.decide(A(soc_pct=24), WORK, SITE).trigger == "low_soc_reserve"
    assert n.decide(A(comms_age_min=95), WORK, SITE).trigger == "comms_stale"
    assert n.decide(A(km_since_pm=8001), WORK, SITE).trigger == "service_interval_due"
    got = n.decide(A(hours_since_calibration=260), WORK, SITE)
    assert got.trigger == "service_interval_due" and "adas_calibration" in got.service_bundle
    assert n.decide(A(soil_index=0.4), WORK, SITE).trigger == "sensor_soil"
    assert not n.decide(A(), WORK, SITE).recall
    # routine rungs sit behind the contention gate; urgent rungs do not
    congested = SiteForecast(sim_min_now=600, eta_min=12, free_capable_points=0,
                             inbound_assets=9, congestion_wait_min=60)
    assert not n.decide(A(km_since_pm=8001), WORK, congested).recall
    assert n.decide(A(soc_pct=24), WORK, congested).trigger == "low_soc_reserve"
    # every issued recall names a target site, a bundle, and a ready time
    r = n.decide(A(soc_pct=24), WORK, SITE)
    assert r.target_site == "site_alpha" and r.service_bundle and r.target_ready_time
    assert r.service_bundle == ("dc_fast_charge",)   # <55 -> DCFC
    print("ladder: OK")


def test_swap_zero_call_site_changes():
    # THE call site, written once; only the config differs between runs.
    def cycle(config, asset):
        impl = make_recall(config)
        log = RecallEventLog(sim_run_id="test-run")
        out = run_recall_cycle(impl, log, asset, WORK, SITE,
                               work_side_accepts=lambda o: True,
                               resolve=lambda *_: None)
        return impl.name, out, log

    name1, out1, log1 = cycle({"implementation": "naive_threshold_v1"}, A(soc_pct=24))
    name2, out2, log2 = cycle({"implementation": "fixed_window_dummy",
                               "from_min": 500, "to_min": 700}, A(soc_pct=24))
    assert (name1, out1.trigger) == ("naive_threshold_v1", "low_soc_reserve")
    assert (name2, out2.trigger) == ("fixed_window_dummy", "fixed_window")
    assert log1.records[0]["payload"]["implementation"] == "naive_threshold_v1"
    assert log2.records[0]["payload"]["implementation"] == "fixed_window_dummy"
    print("swap proof: OK (identical call site, config-only switch)")


def test_event_contract():
    impl = NaiveThresholdRecall()
    log = RecallEventLog(sim_run_id="test-run")
    run_recall_cycle(impl, log, A(soc_pct=24), WORK, SITE,
                     work_side_accepts=lambda o: True, resolve=lambda *_: None)
    assert len(log.records) == 1
    rec = log.records[0]
    assert rec["event_type"] == "recall_issued"          # 0045 §4 vocabulary
    assert rec["payload"]["implementation"] == "naive_threshold_v1"
    assert rec["payload"]["inputs"]["asset"]["soc_pct"] == 24   # inputs snapshot
    assert rec["payload"]["decision"]["trigger"] == "low_soc_reserve"
    assert rec["content_hash"]
    # a no-recall decision emits nothing (stay-deployed is not an event)
    run_recall_cycle(impl, log, A(), WORK, SITE,
                     work_side_accepts=lambda o: True, resolve=lambda *_: None)
    assert len(log.records) == 1
    print("event contract: OK")


def test_refusal_is_first_class():
    impl = NaiveThresholdRecall()
    log = RecallEventLog(sim_run_id="test-run")
    resolves = []
    out = run_recall_cycle(
        impl, log, A(km_since_pm=8001),
        WorkSideSignals(mission_active=True, mission_min_remaining=90), SITE,
        work_side_accepts=lambda o: o.urgency in ("critical", "urgent"),
        resolve=lambda kind, ctx: resolves.append((kind, ctx)))
    assert not out.recall and out.trigger == "work_side_refusal"
    assert log.records[0]["event_type"] == "recall_refused"
    assert resolves == [("recall_refused",
                         {"asset_id": "V-01", "retry_after_min": 90})]
    # …but a critical recall is never refusable by this work side
    out2 = run_recall_cycle(
        impl, log, A(soc_pct=20),
        WorkSideSignals(mission_active=True, mission_min_remaining=90), SITE,
        work_side_accepts=lambda o: o.urgency in ("critical", "urgent"),
        resolve=lambda *_: None)
    assert out2.recall and log.records[-1]["event_type"] == "recall_issued"
    print("refusal path: OK (first-class event + re-solve hook, never an error)")


if __name__ == "__main__":
    test_ladder()
    test_swap_zero_call_site_changes()
    test_event_contract()
    test_refusal_is_first_class()
    print("all recall tests passed")
