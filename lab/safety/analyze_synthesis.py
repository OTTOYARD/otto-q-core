"""lab/safety/analyze_synthesis.py -- what the E3 v0 supervisors disable, from their explicit state spaces.

Reads what synthesize.sh wrote (cifexplorer state spaces and the cifdatasynth outputs) and needs no ESCET itself.
Writes synthesis/summary.json and synthesis/SUMMARY.md. Run from anywhere:  python3 -I lab/safety/analyze_synthesis.py

For each variant (post_cell = R1-R6, post_cell_pre0792 = without R2, post_cell_strict_r2 = R2 read literally):
  * states and transitions of the controlled system, against the uncontrolled plant;
  * an independent re-check of the two synthesis guarantees: controllability (no uncontrollable plant transition is
    missing from a controlled state) and nonblocking (every controlled state reaches a marked state);
  * every (state, controllable event) the plant allows and the controlled system does not, classified by whether a
    requirement invariant itself forbids it (the requirement text is parsed from the synthesized .sup.cif) or synthesis
    derived it (no requirement forbids it there: it is disabled to stay controllable and nonblocking);
  * the G506 decision: the sweep holding a car on an out-of-service post while its cleaning arm is still to clean.
"""
from __future__ import annotations

import json
import re
import sys
from collections import Counter, deque
from pathlib import Path

HERE = Path(__file__).resolve().parent
SYN = HERE / "synthesis"
VARIANTS = ("post_cell", "post_cell_pre0792", "post_cell_strict_r2")
PLANT_AUTS = ("Battery", "Cabin", "Car", "ChargeArm", "Charger", "CleanArm", "Tether")

STATE_RE = re.compile(r'^\s*@state\((.*)\)\s*$')
LOC_RE = re.compile(r'^\s*location (\w+):\s*$')
EDGE_RE = re.compile(r'^\s*edge (\w+)(?: goto (\w+))?;\s*$')
PAIR_RE = re.compile(r'(\w+): "([^"]*)"')


def load_statespace(path: Path) -> dict:
    """Parse a cifexplorer CIF output into states keyed by their plant locations."""
    states, init, marked, edges = {}, None, set(), []
    pending, cur = None, None
    for line in path.read_text(encoding="utf-8").splitlines():
        m = STATE_RE.match(line)
        if m:
            pending = tuple(sorted((k, v) for k, v in PAIR_RE.findall(m.group(1)) if k in PLANT_AUTS))
            continue
        m = LOC_RE.match(line)
        if m:
            cur = m.group(1)
            if pending is None:
                raise ValueError(f"{path}: location {cur} has no @state annotation")
            states[cur], pending = pending, None
            continue
        if cur is None:
            continue
        s = line.strip()
        if s == "initial;":
            init = cur
        elif s == "marked;":
            marked.add(cur)
        else:
            m = EDGE_RE.match(line)
            if m:
                edges.append((cur, m.group(1), m.group(2) or cur))
    trans = {(states[a], ev, states[b]) for a, ev, b in edges}
    return {"states": set(states.values()), "init": states[init], "marked": {states[x] for x in marked},
            "trans": trans, "n_edges": len(edges)}


def event_kinds(path: Path) -> dict[str, str]:
    kinds = {}
    for m in re.finditer(r'^(controllable|uncontrollable) (\w+);', path.read_text(encoding="utf-8"), flags=re.M):
        kinds[m.group(2)] = m.group(1)
    return kinds


# ── a tiny evaluator for the predicate subset the models use: Aut.Loc, an alg var, not / and / or, parentheses ──────
TOKEN_RE = re.compile(r'\s*(\(|\)|[A-Za-z_]\w*(?:\.\w+)?)')


def parse_pred(text: str):
    toks = TOKEN_RE.findall(text)
    if "".join(toks) != re.sub(r'\s+', '', text):
        raise ValueError(f"unsupported predicate: {text!r}")
    pos = 0

    def peek():
        return toks[pos] if pos < len(toks) else None

    def take(expect=None):
        nonlocal pos
        t = toks[pos]
        if expect is not None and t != expect:
            raise ValueError(f"expected {expect} in {text!r}")
        pos += 1
        return t

    def p_or():
        node = p_and()
        while peek() == "or":
            take()
            node = ("or", node, p_and())
        return node

    def p_and():
        node = p_not()
        while peek() == "and":
            take()
            node = ("and", node, p_not())
        return node

    def p_not():
        if peek() == "not":
            take()
            return ("not", p_not())
        if peek() == "(":
            take("(")
            node = p_or()
            take(")")
            return node
        return ("atom", take())

    tree = p_or()
    if pos != len(toks):
        raise ValueError(f"trailing tokens in {text!r}")
    return tree


def eval_pred(tree, state: dict, algs: dict) -> bool:
    op = tree[0]
    if op == "or":
        return eval_pred(tree[1], state, algs) or eval_pred(tree[2], state, algs)
    if op == "and":
        return eval_pred(tree[1], state, algs) and eval_pred(tree[2], state, algs)
    if op == "not":
        return not eval_pred(tree[1], state, algs)
    name = tree[1]
    if name in ("true", "false"):
        return name == "true"
    if "." in name:
        aut, loc = name.split(".")
        return state[aut] == loc
    return eval_pred(algs[name], state, algs)


def load_requirements(sup_path: Path):
    text = sup_path.read_text(encoding="utf-8")
    algs = {m.group(1): parse_pred(m.group(2))
            for m in re.finditer(r'^alg bool (\w+) = (.*);\s*$', text, flags=re.M)}
    reqs = [(m.group(1), m.group(2), parse_pred(m.group(3)), m.group(3))
            for m in re.finditer(r'^supervisor invariant (\w+): (\w+) needs (.*);\s*$', text, flags=re.M)]
    sup_guards = {m.group(1): m.group(2)
                  for m in re.finditer(r'^\s*edge (\w+) when (.*);\s*$',
                                       text.split("supervisor automaton sup:")[1].split("\nend")[0], flags=re.M)}
    return algs, reqs, sup_guards


def reaches_marked(ss: dict) -> set:
    """States from which a marked state is reachable (backward search over the transitions)."""
    back = {}
    for a, _ev, b in ss["trans"]:
        back.setdefault(b, set()).add(a)
    seen, todo = set(ss["marked"]), deque(ss["marked"])
    while todo:
        x = todo.popleft()
        for y in back.get(x, ()):
            if y not in seen:
                seen.add(y)
                todo.append(y)
    return seen


def shortest_path(ss: dict, goal) -> list:
    """Events of a shortest path from the initial state to a state satisfying goal(state) (BFS, ordered edges)."""
    fwd = {}
    for a, ev, b in sorted(ss["trans"]):
        fwd.setdefault(a, []).append((ev, b))
    prev, todo = {ss["init"]: None}, deque([ss["init"]])
    while todo:
        x = todo.popleft()
        if goal(x):
            path = []
            while prev[x] is not None:
                p, ev = prev[x]
                path.append(ev)
                x = p
            return path[::-1]
        for ev, b in fwd.get(x, []):
            if b not in prev:
                prev[b] = (x, ev)
                todo.append(b)
    return []


def as_dict(state) -> dict:
    return dict(state)


def oos(s: dict) -> bool:
    return s["Charger"] in ("Faulted", "UnderRepair")


def g506_hold(src: dict, ev: str) -> bool:
    """The sweep keeps a car on an out-of-service post for a clean still to be done (G506)."""
    return ev == "c_hold" and oos(src) and src["CleanArm"] in ("DoorsOpen", "OverCar")


def analyze() -> dict:
    kinds = event_kinds(HERE / "models" / "post_cell_plant.cif")
    plant = load_statespace(SYN / "post_cell_plant.statespace.cif")
    plant_out = {}
    for a, ev, b in plant["trans"]:
        plant_out.setdefault(a, set()).add((ev, b))
    out = {"plant": {"states": len(plant["states"]), "transitions": len(plant["trans"])}, "variants": {}}

    for v in VARIANTS:
        ss = load_statespace(SYN / f"{v}.statespace.cif")
        algs, reqs, sup_guards = load_requirements(SYN / f"{v}.sup.cif")
        log = (SYN / f"{v}.synth.log").read_text(encoding="utf-8")
        m = re.search(r'Controlled system: exactly ([\d,]+) states', log)
        own = {}
        for a, ev, b in ss["trans"]:
            own.setdefault(a, set()).add((ev, b))
        missing_unctrl, disabled = [], []
        for s in sorted(ss["states"]):
            for ev, b in sorted(plant_out.get(s, ())):
                if (ev, b) in own.get(s, set()):
                    continue
                if kinds[ev] == "uncontrollable":
                    missing_unctrl.append((s, ev))
                else:
                    sd = as_dict(s)
                    by = [name for name, rev, tree, _t in reqs if rev == ev and not eval_pred(tree, sd, algs)]
                    disabled.append((sd, ev, by))
        nonblocking = reaches_marked(ss)
        by_event = Counter(ev for _s, ev, _by in disabled)
        by_req = Counter(name for _s, _ev, by in disabled for name in by)
        derived = [(s, ev) for s, ev, by in disabled if not by]
        derived_by_event = Counter(ev for _s, ev in derived)
        g506 = [(dict(a), dict(b)) for a, ev, b in sorted(ss["trans"]) if g506_hold(dict(a), ev)]
        out["variants"][v] = {
            "synth_log_controlled_states": int(m.group(1).replace(",", "")) if m else None,
            "states": len(ss["states"]),
            "transitions": len(ss["trans"]),
            "marked_states": len(ss["marked"]),
            "controllable_ok": not missing_unctrl,
            "uncontrollable_missing": [[dict(s), ev] for s, ev in missing_unctrl][:5],
            "nonblocking_ok": nonblocking >= ss["states"],
            "blocking_states": len(ss["states"] - nonblocking),
            "supervisor_guards_not_true": {e: g for e, g in sup_guards.items() if g != "true"},
            "requirements": {name: f"{ev} needs {t}" for name, ev, _tr, t in reqs},
            "disabled_total": len(disabled),
            "disabled_by_event": dict(sorted(by_event.items())),
            "disabled_by_requirement": dict(sorted(by_req.items())),
            "derived_by_synthesis_total": len(derived),
            "derived_by_synthesis_by_event": dict(sorted(derived_by_event.items())),
            "derived_examples": [[s, ev] for s, ev in derived[:4]],
            "events_never_enabled": sorted(e for e, k in kinds.items()
                                           if k == "controllable" and not any(x[1] == e for x in ss["trans"])),
            "g506_hold_transitions": len(g506),
            "g506_hold_examples": [src for src, _dst in g506[:3]],
        }
        out["variants"][v]["_ss"] = ss

    base, pre, strict = (out["variants"][v]["_ss"] for v in VARIANTS)
    inp = load_statespace(SYN / "post_cell.input.statespace.cif")
    out["supervisor_equals_requirements_only"] = {
        "same_states": inp["states"] == base["states"], "same_transitions": inp["trans"] == base["trans"],
        "input_states": len(inp["states"]), "input_transitions": len(inp["trans"])}
    only_pre = sorted(pre["trans"] - base["trans"])
    out["r2_difference"] = {
        "states_only_without_r2": len(pre["states"] - base["states"]),
        "states_only_with_r2": len(base["states"] - pre["states"]),
        "transitions_only_without_r2": [{"from": dict(a), "event": ev, "to": dict(b)} for a, ev, b in only_pre],
        "transitions_only_with_r2": len(base["trans"] - pre["trans"]),
        "all_extra_are_g506_holds": all(g506_hold(dict(a), ev) for a, ev, _b in only_pre),
        "g506_witness_path_without_r2": shortest_path(
            {**pre, "trans": pre["trans"]},
            lambda s: any(a == s and g506_hold(dict(a), ev) for a, ev, _b in only_pre)) + ["c_hold"],
        "held_on_out_of_service_mid_clean_reachable_with_r2": any(
            dict(s)["Tether"] == "Held" and oos(dict(s)) and dict(s)["CleanArm"] in ("DoorsOpen", "OverCar")
            for s in base["states"]),
    }
    out["strict_r2_difference"] = {
        "states_lost_vs_r2": len(base["states"] - strict["states"]),
        "transitions_lost_vs_r2": len(base["trans"] - strict["trans"]),
    }
    for v in VARIANTS:
        del out["variants"][v]["_ss"]
    return out


def write_markdown(res: dict) -> str:
    L = ["# E3 v0 synthesis summary (generated by analyze_synthesis.py; do not edit)", ""]
    L.append(f"Uncontrolled plant: {res['plant']['states']} states, {res['plant']['transitions']} transitions.")
    L.append("")
    L.append("| variant | controlled states (cifdatasynth) | states / transitions (explorer) | controllable | nonblocking "
             "| (state, event) pairs disabled | of which derived by synthesis | G506 hold transitions |")
    L.append("|---|---|---|---|---|---|---|---|")
    for v, r in res["variants"].items():
        L.append(f"| {v} | {r['synth_log_controlled_states']} | {r['states']} / {r['transitions']} | "
                 f"{'yes' if r['controllable_ok'] else 'NO'} | {'yes' if r['nonblocking_ok'] else 'NO'} | "
                 f"{r['disabled_total']} | {r['derived_by_synthesis_total']} | {r['g506_hold_transitions']} |")
    L.append("")
    se = res["supervisor_equals_requirements_only"]
    L.append(f"post_cell's controlled system equals the plant restricted by its requirements alone: states "
             f"{se['same_states']}, transitions {se['same_transitions']} ({se['input_states']} / "
             f"{se['input_transitions']}).")
    L.append("")
    for v, r in res["variants"].items():
        L.append(f"## {v}")
        L.append("")
        L.append("Disabled (state, event) pairs by event: " +
                 ", ".join(f"`{e}` {n}" for e, n in r["disabled_by_event"].items()))
        L.append("")
        L.append("Pairs each requirement forbids (a pair may be forbidden by more than one): " +
                 ", ".join(f"`{e}` {n}" for e, n in r["disabled_by_requirement"].items()))
        L.append("")
        if r["derived_by_synthesis_total"]:
            L.append("Derived by synthesis (no requirement forbids the event there): " +
                     ", ".join(f"`{e}` {n}" for e, n in r["derived_by_synthesis_by_event"].items()))
            L.append("")
        if r["supervisor_guards_not_true"]:
            L.append("Supervisor guards other than `true`:")
            L.append("")
            for e, g in r["supervisor_guards_not_true"].items():
                L.append(f"- `{e}` when `{g}`")
            L.append("")
        L.append("Controllable events never enabled: " + ", ".join(f"`{e}`" for e in r["events_never_enabled"]))
        L.append("")
    d = res["r2_difference"]
    L.append("## What R2 alone disables (post_cell_pre0792 against post_cell)")
    L.append("")
    L.append(f"Same {res['variants']['post_cell']['states']} states either way; "
             f"{len(d['transitions_only_without_r2'])} transitions exist only without R2, every one a G506 hold: "
             f"{d['all_extra_are_g506_holds']}. Transitions only with R2: {d['transitions_only_with_r2']}.")
    L.append("")
    for t in d["transitions_only_without_r2"]:
        f = t["from"]
        L.append(f"- `c_hold` from Charger={f['Charger']}, CleanArm={f['CleanArm']}, Tether={f['Tether']}, "
                 f"ChargeArm={f['ChargeArm']}, Battery={f['Battery']}, Cabin={f['Cabin']}")
    L.append("")
    L.append("Shortest path to the G506 decision without R2: " + " -> ".join(d["g506_witness_path_without_r2"]))
    L.append("")
    L.append(f"A car held on an out-of-service post mid-clean is still reachable WITH R2: "
             f"{d['held_on_out_of_service_mid_clean_reachable_with_r2']} (a fault during a legitimate hold, until the "
             f"next tick's sweep, which may not hold it again).")
    L.append("")
    s = res["strict_r2_difference"]
    L.append(f"Strict R2 loses {s['states_lost_vs_r2']} states and {s['transitions_lost_vs_r2']} transitions "
             f"against post_cell.")
    L.append("")
    return "\n".join(L)


def main() -> int:
    res = analyze()
    (SYN / "summary.json").write_text(json.dumps(res, indent=1, sort_keys=True) + "\n", encoding="utf-8")
    md = write_markdown(res)
    (SYN / "SUMMARY.md").write_text(md, encoding="utf-8")
    print(md)
    ok = all(r["controllable_ok"] and r["nonblocking_ok"] for r in res["variants"].values())
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
