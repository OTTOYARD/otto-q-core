"""scripts/replay_charge_line.py, the rehearsal behind db/checks/0471 and db/migrations/0781 (G501), by hand.

WHY THIS EXISTS. 0471's figures for 0781 come from this script's within-owner exchange: a car whose turn in the bays is
far off yields its place only to its own owner's cars, and each owner's cars keep the places they hold in today's order
(CLAUDE.md rule 14). The same three-car line the SQL simulator is tested on (tests/test_charge_order_exit_first_sql.py)
is replayed here, so the rehearsal and the engine are held to one answer. Pure Python; no database.
"""
import os
import sys
from datetime import datetime, timedelta

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "scripts"))
import replay_charge_line as R  # noqa: E402

T0 = datetime(2026, 10, 7, 13, 0)


def _j(car, r=0.0, svc=False):
    return {"car": car, "_r": r, "svc": svc}


def _cars(order):
    return [j["car"] for j in order]


def test_within_owner_a_car_yields_only_to_its_own_owners_cars():
    order = [_j("g", svc=True), _j("e"), _j("h")]          # today's order: g, e, h; g's turn in the bays is far off
    gate = lambda j, t: j["car"] == "g"                     # noqa: E731
    assert _cars(R.within_owner(order, 0.0, gate, {"g": "W", "e": "W", "h": "W"})) == ["e", "h", "g"]
    # g and h one owner's, e another's: g and h trade their owner's places (first and third); e keeps its own
    assert _cars(R.within_owner(order, 0.0, gate, {"g": "W", "e": "T", "h": "W"})) == ["h", "e", "g"]
    # every car its own owner's: nothing moves
    assert _cars(R.within_owner(order, 0.0, gate, {"g": "W", "e": "T", "h": "Z"})) == ["g", "e", "h"]


def test_within_owner_a_car_past_the_floor_keeps_its_place():
    order = [_j("g", r=-100.0, svc=True), _j("e"), _j("h")]  # g has waited 100 minutes at t = 0
    gate = lambda j, t: j["car"] == "g"                     # noqa: E731
    assert _cars(R.within_owner(order, 0.0, gate, {"g": "W", "e": "W", "h": "W"})) == ["g", "e", "h"]


def _replay(gate, owner_of):
    """One post, down until minute 40; g, e and h come in at 0, 20 and 40 and each charges 30 minutes. At 40 today's
    order is g (waited 40), e (20), h (0)."""
    jobs = [dict(car=c, visit=c, arr=T0 + timedelta(minutes=m), p=30.0, svc=(c == "g")) for c, m in
            (("g", 0), ("e", 20), ("h", 40))]
    down = {"P1": [(T0, T0 + timedelta(minutes=40))]}
    res = R.replay(jobs, down, ["P1"], T0, 600.0, gate, owner_of)
    return [r["j"]["car"] for r in sorted(res, key=lambda r: r["s"])]


def test_the_replay_takes_back_a_place_once_its_owner_has_no_car_to_yield_to():
    gate = lambda j, t: j["car"] == "g"                     # noqa: E731
    assert _replay(None, None) == ["g", "e", "h"]          # today
    # one owner: e and h first; g past the floor at 100 minutes
    assert _replay(gate, {"g": "W", "e": "W", "h": "W"}) == ["e", "h", "g"]
    # g and h one owner's, e another's: h takes g's place at 40; at 70 g is its owner's only car waiting and goes
    # ahead of e, as the SQL simulator has it
    assert _replay(gate, {"g": "W", "e": "T", "h": "W"}) == ["h", "g", "e"]
    # across owners (not built): g yields to e as well
    assert _replay(gate, None) == ["e", "h", "g"]
