"""Tests for lab/safety (E3 v0): the post-cell monitor on demo run 8c0b2e04's fixtures, the supervisor replay, the
committed synthesis results, and, when Eclipse ESCET is installed, a fresh synthesis that must reproduce them.

CI (.github/workflows/verify.yml, `python3 -m pytest -q`) has no ESCET, so the tests that run it skip there; every
other test reads only committed files. Point ESCET_BIN at ESCET's bin/ directory to run them.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
import sys
from datetime import timedelta
from pathlib import Path

import pytest

SAFETY = Path(__file__).resolve().parents[1]
FIX = SAFETY / "fixtures" / "8c0b2e04"
SYN = SAFETY / "synthesis"
sys.path.insert(0, str(SAFETY))

import analyze_synthesis  # noqa: E402
import monitor  # noqa: E402
import replay  # noqa: E402

POSTS = ["NASH-DCFC-STALL-02", "NASH-DCFC-STALL-11", "NASH-DCFC-STALL-13",
         "NASH-DCFC-STALL-18", "NASH-DCFC-STALL-22", "NASH-DCFC-STALL-29"]
CAR_22 = "2cd2cbf3-9de8-48c0-9bd8-935aedb744d7"
CAR_02 = "ca2624fc-c97d-4033-af1b-bf97756d3ad9"


def ticks():
    return monitor.read_ticks(FIX / "ticks.csv")


def report(post, rows=None, tk=None):
    rows = monitor.read_trace(FIX / f"{post}.csv") if rows is None else rows
    return monitor.check(rows, ticks() if tk is None else tk, post)


# ── the fixtures are the database's rows, byte for byte ─────────────────────────────────────────────────────────────

def test_fixtures_match_their_md5_manifest():
    lines = (FIX / "MD5SUMS").read_text(encoding="utf-8").split("\n")
    entries = [ln.split("  ") for ln in lines if ln]
    assert sorted(name for _md5, name in entries) == sorted([f"{p}.csv" for p in POSTS] + ["ticks.csv"])
    for md5, name in entries:
        assert hashlib.md5((FIX / name).read_bytes()).hexdigest() == md5, name


def test_every_vehicle_id_in_the_fixtures_is_a_full_uuid():
    for p in POSTS:
        for row in monitor.read_trace(FIX / f"{p}.csv"):  # read_trace refuses a short id
            assert row.vehicle == "" or len(row.vehicle) == 36


# ── acceptance: DCFC-22 and DCFC-02 flagged with db/checks/0474's delays, the other four not ────────────────────────

def test_monitor_flags_exactly_dcfc22_and_dcfc02():
    flagged = {p for p in POSTS if report(p)["violations"]}
    assert flagged == {"NASH-DCFC-STALL-22", "NASH-DCFC-STALL-02"}


@pytest.mark.parametrize("post,car,held,due,left,past_due", [
    ("NASH-DCFC-STALL-22", CAR_22, 339.1, "2026-11-02T14:04:37.354314Z", "2026-11-02T14:09:54.597624Z", 317.2),
    ("NASH-DCFC-STALL-02", CAR_02, 309.2, "2026-11-02T14:04:57.332223Z", "2026-11-02T14:09:54.597624Z", 297.3),
])
def test_r2_violation_matches_0474(post, car, held, due, left, past_due):
    (v,) = report(post)["violations"]
    assert v["requirement"] == "R2" and v["vehicle_id"] == car
    assert abs(v["facts"]["held_from_fault_s"] - held) < 1.0       # 0474 section 1: 339.1 s and 309.2 s
    assert v["start_sim"] == due and v["end_sim"] == left and v["seconds"] == past_due
    assert v["facts"]["release_path"] == "demate"
    assert v["facts"]["clean_in_progress_at_fault"] and v["facts"]["clean_outcome"] == "done"
    assert v["facts"]["left_at_first_tick_after_clean_end"] is True  # the release waited for the clean
    assert v["start_wall_utc"] is not None and v["end_wall_utc"] == "2026-11-03T03:40:26.277891Z"


@pytest.mark.parametrize("post,held,path", [
    ("NASH-DCFC-STALL-18", 11.7, "demate"),
    ("NASH-DCFC-STALL-11", 0.0, "emergency_release"),
    ("NASH-DCFC-STALL-29", 0.0, "emergency_release"),
    ("NASH-DCFC-STALL-13", 0.0, "emergency_release"),
])
def test_the_other_four_posts_release_on_time(post, held, path):
    r = report(post)
    assert r["violations"] == [] and r["undecidable"] == []
    (f,) = r["faults"]
    assert f["held_from_fault_s"] == held and f["release_path"] == path
    assert f["left_sim"] == f["release_due_sim"]


def test_advisories_are_the_engine_abstractions_and_only_those():
    adv = {p: sorted(a["facts"]["what"].split(":")[0] for a in report(p)["advisories"]) for p in POSTS}
    em = "arm.emergency_release"
    assert adv["NASH-DCFC-STALL-11"] == sorted([em, "the car left the post while the post's cleaning-arm cycle was "
                                                    "recorded in progress (started 2026-11-02T14"])
    assert adv["NASH-DCFC-STALL-13"] == [em] and adv["NASH-DCFC-STALL-29"] == [em]
    assert adv["NASH-DCFC-STALL-18"] == [] and adv["NASH-DCFC-STALL-22"] == [] and adv["NASH-DCFC-STALL-02"] == []


def test_no_r1_violation_and_the_next_mates_follow_the_derived_repair():
    for p in POSTS:
        assert [v for v in report(p)["violations"] if v["requirement"] == "R1"] == []
    f02 = report("NASH-DCFC-STALL-02")["faults"][0]
    f11 = report("NASH-DCFC-STALL-11")["faults"][0]
    assert f02["out_of_service_to"] == "2026-11-02T14:20:58.775196Z"   # first tick >= 14:04:45.39 + 16 min
    assert f11["out_of_service_to"] == "2026-11-02T14:23:04.305363Z"   # first tick >= 14:09:00.91 + 14 min


def test_calibration_every_unheld_demate_in_the_fixtures_leaves_at_its_clear():
    """The zero-tolerance R2 rule rests on: no hold -> the car leaves at the demate_cleared instant."""
    seen = 0
    for p in POSTS:
        rows = monitor.read_trace(FIX / f"{p}.csv")
        for d in (x for x in rows if x.event == "demate_started"):
            cleared = next(x for x in rows if x.vehicle == d.vehicle and x.event == "demate_cleared" and x.t >= d.t)
            cleans = [c for c in monitor.cleans_of(rows, d.vehicle) if monitor.in_progress(c, cleared.t)]
            left = next(x for x in rows if x.vehicle == d.vehicle and x.event == "car_left" and x.t >= d.t)
            if not cleans:
                assert left.t == cleared.t, (p, d.vehicle)
                seen += 1
    assert seen == 2   # DCFC-18's faulted car and DCFC-29's b2222222 (a normal end)


# ── the R2 and R1 rules on edited traces (each edit is a case the rule must decide; nothing is fitted) ─────────────

def edited(post, drop=(), shift=None):
    rows = [r for r in monitor.read_trace(FIX / f"{post}.csv") if r.event not in drop]
    if shift:
        ev, dt = shift
        for r in rows:
            if r.event == ev:
                r.t = r.t + dt
    rows.sort(key=lambda r: r.t)
    for i, r in enumerate(rows, 1):
        r.seq = i
    return rows


def test_a_car_one_tick_late_off_a_faulted_post_is_flagged():
    rows = edited("NASH-DCFC-STALL-18")
    tk = ticks()
    left = next(r for r in rows if r.event == "car_left")
    left.t = tk.first_at_or_after(left.t + timedelta(microseconds=1))   # the next tick
    (v,) = report("NASH-DCFC-STALL-18", rows, tk)["violations"]
    assert v["requirement"] == "R2" and v["start_sim"] == "2026-11-02T14:06:43.747986Z"
    assert v["end_sim"] == "2026-11-02T14:06:56.912970Z"


def test_without_demate_cleared_the_due_tick_comes_from_the_tick_clock_or_is_undecidable():
    rows = edited("NASH-DCFC-STALL-22", drop=("demate_cleared",))
    (v,) = report("NASH-DCFC-STALL-22", rows)["violations"]
    assert v["start_sim"] == "2026-11-02T14:04:37.354314Z"     # first tick >= 14:04:15.48 + 11.5 s
    r = report("NASH-DCFC-STALL-22", rows, monitor.Ticks())
    assert r["violations"] == [] and len(r["undecidable"]) == 1


def test_a_hold_after_the_charger_is_repaired_is_not_r2():
    rows = edited("NASH-DCFC-STALL-02")
    tk = ticks()
    fault = next(r for r in rows if r.event == "charger_faulted")
    fault.detail["repair_minutes"] = "2"                         # 14:04:45.39 + 2 min = 14:06:45.39
    (v,) = report("NASH-DCFC-STALL-02", rows, tk)["violations"]
    assert v["end_sim"] == "2026-11-02T14:06:56.912970Z"        # tick 21, the first at or after it: clipped at the
                                                                 # repair, not at the release (14:09:54.60)


def test_a_mate_inside_the_out_of_service_window_is_r1():
    rows = edited("NASH-DCFC-STALL-02", shift=("mate_started", timedelta(0)))
    second = [r for r in rows if r.event == "mate_started"][1]
    second.t = monitor.ts("2026-11-02T14:20:43.323537Z")       # the tick before the derived repair
    rows.sort(key=lambda r: r.t)
    for i, r in enumerate(rows, 1):
        r.seq = i
    r1 = [v for v in report("NASH-DCFC-STALL-02", rows)["violations"] if v["requirement"] == "R1"]
    assert len(r1) == 1 and r1[0]["vehicle_id"] == "77ecd026-12cb-458e-900a-4602511728d8"


def test_cli_exit_status_and_json():
    out = subprocess.run([sys.executable, "-I", str(SAFETY / "monitor.py"), "--all", str(FIX), "--json"],
                         capture_output=True, text=True)
    assert out.returncode == 1
    reps = json.loads(out.stdout)
    assert {r["post"] for r in reps if r["violations"]} == {"NASH-DCFC-STALL-22", "NASH-DCFC-STALL-02"}
    ok = subprocess.run([sys.executable, "-I", str(SAFETY / "monitor.py"), str(FIX / "NASH-DCFC-STALL-18.csv"),
                         "--ticks", str(FIX / "ticks.csv")], capture_output=True, text=True)
    assert ok.returncode == 0


# ── the replay through the synthesized supervisors (committed state spaces; no ESCET needed) ───────────────────────

def first_disallowed(variant):
    out = {}
    for p in POSTS:
        for v in replay.replay_post(FIX / f"{p}.csv", FIX / "ticks.csv", variant)["visits"]:
            d = v.get("first_disallowed")
            out[(p, v["vehicle_id"][:8])] = None if d is None else (d["model_event"], d["sim"], tuple(d["forbidden_by"]))
    return out


def test_replay_against_the_r2_supervisor_disallows_the_two_g506_holds():
    got = first_disallowed("post_cell")
    assert got[("NASH-DCFC-STALL-22", "2cd2cbf3")] == (
        "c_hold", "2026-11-02T14:04:37.354314Z", ("R2_no_hold_for_clean_on_out_of_service",))
    assert got[("NASH-DCFC-STALL-02", "ca2624fc")] == (
        "c_hold", "2026-11-02T14:04:57.332223Z", ("R2_no_hold_for_clean_on_out_of_service",))
    assert got[("NASH-DCFC-STALL-18", "c3333333")] is None
    # every other disallowed step is an engine abstraction the README explains (R3d emergency release, R3b demate)
    others = {k: v for k, v in got.items() if v and v[0] != "c_hold"}
    assert {v[0] for v in others.values()} == {"c_emergency_release", "c_unlatch"}
    assert got[("NASH-DCFC-STALL-29", "ebd4669f")][2] == ("R3b_no_unlatch_while_cleaning",)


def test_replay_against_the_pre0792_supervisor_allows_what_the_engine_did_on_22_and_02():
    got = first_disallowed("post_cell_pre0792")
    assert got[("NASH-DCFC-STALL-22", "2cd2cbf3")] is None
    assert got[("NASH-DCFC-STALL-02", "ca2624fc")] is None
    with_r2 = first_disallowed("post_cell")
    assert {k for k in got if got[k] != with_r2[k]} == {("NASH-DCFC-STALL-22", "2cd2cbf3"),
                                                          ("NASH-DCFC-STALL-02", "ca2624fc")}


# ── the committed synthesis results (read from synthesis/; no ESCET needed) ─────────────────────────────────────────

def test_committed_synthesis_results():
    res = analyze_synthesis.analyze()
    v = res["variants"]
    assert (v["post_cell"]["states"], v["post_cell"]["transitions"]) == (302, 831)
    assert (v["post_cell_pre0792"]["states"], v["post_cell_pre0792"]["transitions"]) == (302, 839)
    assert (v["post_cell_strict_r2"]["states"], v["post_cell_strict_r2"]["transitions"]) == (170, 393)
    for name, r in v.items():
        assert r["controllable_ok"] and r["nonblocking_ok"], name
        assert r["synth_log_controlled_states"] == r["states"], name
    assert v["post_cell"]["derived_by_synthesis_total"] == 0 and v["post_cell"]["supervisor_guards_not_true"] == {}
    assert res["supervisor_equals_requirements_only"]["same_states"]
    assert res["supervisor_equals_requirements_only"]["same_transitions"]
    d = res["r2_difference"]
    assert len(d["transitions_only_without_r2"]) == 8 and d["all_extra_are_g506_holds"]
    assert d["transitions_only_with_r2"] == 0 and d["states_only_without_r2"] == 0
    assert v["post_cell"]["g506_hold_transitions"] == 0 and v["post_cell_pre0792"]["g506_hold_transitions"] == 8
    assert "c_hold" in v["post_cell_strict_r2"]["events_never_enabled"]
    assert v["post_cell_strict_r2"]["supervisor_guards_not_true"]["c_unlatch"] == "CleanArm.Home"


def test_committed_summary_is_current():
    committed = json.loads((SYN / "summary.json").read_text(encoding="utf-8"))
    assert committed == json.loads(json.dumps(analyze_synthesis.analyze(), sort_keys=True))


# ── a fresh synthesis must reproduce the committed one (needs ESCET; skips without it) ──────────────────────────────

def escet_bin():
    """ESCET's bin/: $ESCET_BIN when set (and then only it), else the lab install, else cifdatasynth on PATH."""
    if os.environ.get("ESCET_BIN"):
        cand = Path(os.environ["ESCET_BIN"])
        return cand if (cand / "cifdatasynth").exists() else None
    lab = Path("/home/user/escet/v13.0/eclipse-escet-v13.0/bin")
    if (lab / "cifdatasynth").exists():
        return lab
    found = shutil.which("cifdatasynth")
    return Path(found).parent if found else None


needs_escet = pytest.mark.skipif(escet_bin() is None, reason="Eclipse ESCET (cifdatasynth) is not installed")


@needs_escet
@pytest.mark.parametrize("model,states", [("post_cell", 302), ("post_cell_pre0792", 302), ("post_cell_strict_r2", 170)])
def test_fresh_synthesis_reproduces_the_committed_supervisor(tmp_path, model, states):
    out = tmp_path / f"{model}.sup.cif"
    p = subprocess.run([str(escet_bin() / "cifdatasynth"), "--gui=off", "--forward-reach=yes",
                        "--stats=ctrl-sys-states", "-o", str(out), str(SAFETY / "models" / f"{model}.cif")],
                       capture_output=True, text=True, timeout=600)
    assert p.returncode == 0, p.stdout + p.stderr
    assert f"Controlled system: exactly {states} states." in p.stdout
    assert out.read_bytes() == (SYN / f"{model}.sup.cif").read_bytes()
    # ...and its explicit state space is the committed one the ESCET-free tests above read
    ss = tmp_path / f"{model}.statespace.cif"
    e = subprocess.run([str(escet_bin() / "cifexplorer"), "--gui=off", "--progress=off", "-o", str(ss), str(out)],
                       capture_output=True, text=True, timeout=600)
    assert e.returncode == 0, e.stdout + e.stderr
    assert ss.read_bytes() == (SYN / f"{model}.statespace.cif").read_bytes()
