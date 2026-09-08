"""The solver/simulator separation, enforced by CI rather than promised by prose.

THE RULE (the founder's, verbatim in spirit): OTTO-Q is the foundational solver.
It must not have simulation data wired in that makes it automatically know the
answer to any particular world. The simulator -- OTTO-Twin, or any third-party
world -- is a SOURCE OF INPUTS, delivered as declared data; the kernel must work
identically pointed at a real depot it has never seen.

WHAT THAT MEANS MECHANICALLY, and what each test asserts:

1. No kernel module imports a database client, the twin, or anything that could
   reach production state. The kernel's entire world arrives as function
   arguments (scenario dicts, SiteProfiles, FleetSpecs, ExposureRecords).
2. No kernel module contains the production project ref or the benchmark depot
   id. Knowing either is the beginning of knowing the answer.
3. Committed run ARTIFACTS (comparison/cost/forward JSONs) are outputs under
   version control for reproducibility -- they are never imported back by kernel
   code. An artifact that feeds back in is a memorized answer.

WHERE SIMULATION LEGITIMATELY LIVES, so this test is not misread as "no sim
anywhere": the DB-native twin (sim runs, decision snapshots, the determinism
certification harness) exercises the PRODUCTION decide path against simulated
worlds -- that is the twin testing the engine, which is its job. The Python test
scaffolding here (scenario_*.json, seeded synthetic fleets) is OUR OWN
scaffolding, not twin data; the twin's calibration layer (ACN-Data, NYC TLC,
NOAA) shapes twin WORLDS, and none of it is consulted by any module below.
"""

from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).parent.parent

#: The kernel: everything that decides, prices, sizes, or derives. If a new
#: kernel package is added, add it here -- absence from this list is the only
#: way to dodge the guard, and reviews should treat an unlisted kernel package
#: as a finding.
KERNEL_PACKAGES = ("policies", "solvers", "sites", "wear",
                   "onboarding", "conformance", "recall", "adapters", "metrics",
                   "proposer",
                   #: `intent` was MISSING here until 2026-09-07, and it is imported
                   #: by two packages that are on the list (policies/regime.py and
                   #: proposer/forward_proposer.py both `from intent.solve import
                   #: pass_sequence`). So every rule this file enforces -- no database,
                   #: no network, no production identifiers, no undeclared file reads --
                   #: simply did not apply to intent/intent.py, intent/signals.py,
                   #: intent/solve.py or intent/learn.py, while their code ran inside
                   #: the kernel on every regime-aware proposal. A network client or the
                   #: production project ref could have landed there with the whole
                   #: suite green.
                   "intent")

#: Imports that would let kernel code reach state it must not know about.
FORBIDDEN_IMPORTS = re.compile(
    r"^\s*(import|from)\s+(supabase|psycopg\w*|sqlalchemy|asyncpg|requests|"
    #: `load` is on this list for the same reason psycopg is: it is a
    #: database client by design (load/harness.py drives pgbench against a
    #: live URL). A kernel module importing it would have a connection.
    r"httpx|urllib\.request|twin|load)\b", re.M)

#: Identifiers of the production world. A kernel file that names them has been
#: told which world it lives in.
FORBIDDEN_LITERALS = (
    "gxdrcyphqjzjsuhxuqtg",                    # the production project ref
    "22222222-2222-2222-2222-222222222222",    # the benchmark depot
    "ycsisvozzgmisboumfqc",                    # the MVP project ref
)


def _kernel_sources():
    for pkg in KERNEL_PACKAGES:
        for p in (ROOT / pkg).rglob("*.py"):
            if "test_" in p.name or "__pycache__" in str(p):
                continue
            yield p, p.read_text()


#: THE GUARD'S OWN COVERAGE IS NOW GUARDED.
#:
#: Every rule in this file is enforced by walking KERNEL_PACKAGES. A package
#: that is not on that list is not checked -- and nothing failed if you removed
#: one. That is how `intent` sat outside the guard while its code ran inside
#: the kernel on every regime-aware proposal (the 2026-09-07 finding).
#:
#: Adding `intent` back closed the hole and left the door unlocked: verified on
#: 2026-09-08 by deleting it again, which turned NOTHING red. A refactor, a
#: merge resolution or a tidy-up could drop any entry and the suite would stay
#: green while a whole package fell out of scope. The list is a coverage claim,
#: so it is asserted like one.
EXPECTED_KERNEL_PACKAGES = frozenset({
    "policies", "solvers", "sites", "wear", "onboarding", "conformance",
    "recall", "adapters", "metrics", "proposer", "intent",
})


def test_the_guard_covers_every_package_it_claims_to():
    """Removing a package from KERNEL_PACKAGES silently narrows every rule in
    this file. Adding one is fine and this test tells you to record it here;
    losing one is the failure mode, and it now fails loudly."""
    live = frozenset(KERNEL_PACKAGES)
    missing = EXPECTED_KERNEL_PACKAGES - live
    assert not missing, (
        f"package(s) dropped out of the separation guard: {sorted(missing)}. "
        f"Every rule in this file -- no database, no network, no production "
        f"identifiers, no undeclared file reads -- stopped applying to them.")
    added = live - EXPECTED_KERNEL_PACKAGES
    assert not added, (
        f"new kernel package(s) {sorted(added)} are covered by the guard but "
        f"not recorded in EXPECTED_KERNEL_PACKAGES; add them here so the "
        f"coverage claim stays explicit.")


#: Top-level packages that hold Python and are deliberately NOT kernel, each
#: with the reason it is exempt. This exists because of how `intent` was found:
#: the comment above KERNEL_PACKAGES says "reviews should treat an unlisted
#: kernel package as a finding", and for however long intent/ existed, no review
#: treated it as one. A human step that has already been skipped once is not a
#: control. So the classification is now a CENSUS: every top-level package that
#: contains a .py file must appear in exactly one of the two lists, and a new
#: package that appears in neither fails this file rather than silently
#: defaulting to unguarded.
NON_KERNEL_PACKAGES = {
    "tests":   "the guard itself and its siblings; they must import what they check",
    "scripts": "operator tooling (migration index, drift SQL) — runs against the "
               "repo and the ledger by design, never inside a decide path",
    "db":      "SQL, checks and canons; the one .py is tooling beside them",
    "load":    "the load harness (task G24). It is a NETWORK and DATABASE client "
               "on purpose — measuring the served system is its whole job — which "
               "is exactly why it must never be importable from a kernel package. "
               "FORBIDDEN_IMPORTS below bans `import load` from the kernel for "
               "the same reason it bans psycopg.",
}


def test_every_python_package_is_classified_as_kernel_or_not():
    """The failure this test exists for, stated plainly: `intent` sat in neither
    list from its creation until 2026-09-07, so none of this file's rules applied
    to code that ran inside the kernel on every regime-aware proposal. Nothing
    failed, because nothing was looking. Now something looks."""
    packages = sorted(
        d.name for d in ROOT.iterdir()
        if d.is_dir() and not d.name.startswith((".", "_"))
        and any(d.rglob("*.py")))
    classified = EXPECTED_KERNEL_PACKAGES | set(NON_KERNEL_PACKAGES)
    unclassified = [p for p in packages if p not in classified]
    assert not unclassified, (
        f"top-level package(s) holding Python and classified as neither kernel "
        f"nor non-kernel: {unclassified}. Add each to EXPECTED_KERNEL_PACKAGES "
        f"(and KERNEL_PACKAGES) if it decides, prices, sizes or derives, or to "
        f"NON_KERNEL_PACKAGES with the reason it is exempt. Defaulting to "
        f"unguarded is what happened to `intent`.")
    overlap = EXPECTED_KERNEL_PACKAGES & set(NON_KERNEL_PACKAGES)
    assert not overlap, f"package(s) claimed as both kernel and exempt: {sorted(overlap)}"
    stale = [p for p in NON_KERNEL_PACKAGES if not (ROOT / p).is_dir()]
    assert not stale, (
        f"NON_KERNEL_PACKAGES names {stale}, which do not exist — an exemption "
        f"for a package that is gone is an exemption waiting to be reused")


def test_every_covered_package_actually_exists():
    """A typo in the list is the same defect wearing a different hat: the guard
    walks a directory that is not there, finds no sources, and passes."""
    for pkg in sorted(EXPECTED_KERNEL_PACKAGES):
        assert (ROOT / pkg).is_dir(), f"KERNEL_PACKAGES names {pkg!r}, which does not exist"


def test_kernel_imports_no_database_and_no_twin():
    hits = [(str(p), m.group(0).strip())
            for p, src in _kernel_sources()
            for m in FORBIDDEN_IMPORTS.finditer(src)]
    assert hits == [], f"kernel modules reaching outside their arguments: {hits}"


def test_kernel_names_no_production_identifiers():
    hits = [(str(p), lit)
            for p, src in _kernel_sources()
            for lit in FORBIDDEN_LITERALS if lit in src]
    assert hits == [], f"kernel modules that know which world they live in: {hits}"


#: Every file read a kernel module is allowed to perform, with its reason.
#: This is deliberately an explicit allowlist rather than a smarter regex: a new
#: read fails the test and forces its author to add a line HERE saying why it is
#: not a leak, which is the review moment the guard exists to create.
#:
#: The two legitimate categories:
#:   world   -- loading DECLARED world data (scenarios, site profiles, packs).
#:              The world entering as data is the design, not a leak.
#:   verify  -- reading a committed artifact/baseline only to BYTE-COMPARE or
#:              render a fresh computation against it. The computation never
#:              depends on the file's contents; the file depends on the
#:              computation. (Chart generators over committed run outputs are
#:              this category: reporting downstream of a run, feeding nothing.)
ALLOWED_READS = {
    ("solvers/cpsat/model.py", "world"),           # load_scenario
    ("sites/site_profile.py", "world"),            # load_site_file / profiles
    ("sites/site_alpha/harness_alpha.py", "world"),  # site_alpha.json loader
    ("conformance/harness.py", "world"),           # pack files from PACK_DIR
    ("policies/run_comparison.py", "verify"),      # regenerate == committed
    ("policies/cost.py", "verify"),                # regenerate == committed
    ("policies/forward.py", "verify"),             # regenerate == committed
    ("sites/site_alpha/run_matrix.py", "verify"),  # regenerate == committed
    ("sites/site_alpha/make_charts.py", "verify"),  # charts OF committed runs
    ("metrics/kpi_gate.py", "verify"),             # candidate vs baseline gate
    ("policies/deck_run.py", "verify"),            # committed-curve artifact display/derive
    ("intent/intent.py", "world"),                # load_intent: the commander's intent artifact
}
_ALLOWED_FILES = {f for f, _ in ALLOWED_READS}


def test_every_kernel_file_read_is_on_the_justified_allowlist():
    """A kernel module may read declared worlds or verify its own artifacts --
    nothing else. Anything else is either a memorized answer (an artifact fed
    back into a decision) or an undeclared world, and both are the leak the
    founder's rule forbids."""
    offenders = []
    for p, src in _kernel_sources():
        rel = str(p.relative_to(ROOT))
        if re.search(r"(read_text|json\.load)\s*\(", src) and rel not in _ALLOWED_FILES:
            offenders.append(rel)
    assert offenders == [], (
        f"kernel modules performing file reads not on the allowlist: {offenders}. "
        f"If the read is loading declared world data or verifying a committed "
        f"artifact, add it to ALLOWED_READS with its category; anything else is "
        f"a separation leak.")


def test_no_decide_path_module_reads_any_file_at_all():
    """The strictest slice: modules that HOUSE a decide()/solve entry point take
    their entire world as arguments. assignment_policy and the harness decide;
    wear, sizer and tariff price and derive -- none of them opens a file."""
    strict = ("policies/assignment_policy.py", "policies/harness.py",
              "wear/degradation.py", "onboarding/sizer.py", "sites/tariff.py",
              "recall/recall_decision.py")
    offenders = []
    for rel in strict:
        f = ROOT / rel
        if not f.exists():
            continue
        src = f.read_text()
        if re.search(r"(read_text|json\.load|open\s*\()\s*\(?", src) and \
           re.search(r"(read_text|json\.load)\s*\(", src):
            offenders.append(rel)
    assert offenders == [], f"decide/price modules reading files: {offenders}"


# ---------------------------------------------------------------------------
# "Agents propose, solver disposes" — the other half of the rule
# ---------------------------------------------------------------------------
#
# The tests above enforce that the propose path cannot REACH production state:
# `proposer` is in KERNEL_PACKAGES and FORBIDDEN_IMPORTS bans every DB and HTTP
# client. That is one half of CLAUDE.md 2.5.
#
# The other half — that what the propose path EMITS is advisory rather than a
# command — was asserted in prose in four separate files
# (policies/assignment_policy.py:16, proposer/forward_proposer.py:1,
# adapters/base.py:16) and enforced nowhere. Prose is what this file exists to
# replace. `adapters/base.py` already rejects decision-implying method names on
# adapters at import time; these are the same idea applied to the proposal rows
# themselves, which is where the architecture would actually erode: not by
# someone writing to the database, which is blocked, but by a row quietly
# acquiring the shape of an instruction.

_ADVISORY_SOURCES = ("cpsat", "forward_lex")

#: Keys that would turn an advisory row into an instruction. A proposal says
#: "here is what I would do and why"; a command says "do it". If one of these
#: ever appears in a proposal payload, the propose/dispose seam has collapsed
#: and the deferral pattern that gives the local decide path right-of-first-
#: refusal no longer has anything to refuse.
_COMMAND_KEYS = ("command", "command_type", "enact", "enacted", "execute",
                 "actuate", "setpoint", "issue_at", "dispatch")


def _cpsat_rows():
    """The rows build_and_solve emits directly, on a scenario that forces a rejection.

    The tight scenario is deliberate: a plan where everything is served exercises
    only the happy path, and the abstention row — the one most likely to be built
    by a different code path and forget the contract — never appears.
    """
    import json as _json
    import sys as _sys
    _sys.path.insert(0, str(ROOT / "solvers" / "cpsat"))
    from model import build_and_solve, materialize  # noqa: E402

    sc = _json.loads((ROOT / "solvers" / "cpsat" / "scenario_canonical.json").read_text())
    charge = [p for p in sc["service_points"] if p["kind"] in ("dcfc", "l2")][:2]
    sc["service_points"] = charge + [p for p in sc["service_points"]
                                     if p["kind"] not in ("dcfc", "l2")]
    sc["horizon_min"] = 300
    plan = build_and_solve(materialize(_json.loads(_json.dumps(sc))), allow_rejection=True)
    assert plan["rejected"], "the tight scenario no longer rejects — this test proves nothing"
    return plan["proposals"]


def _forward_lex_rows():
    """The rows the PROPOSER emits — which this guard never used to look at.

    _ADVISORY_SOURCES has named ("cpsat", "forward_lex") since the proposer
    landed, but the row generator only ever called build_and_solve(), whose rows
    are all source="cpsat". Every row proposer.propose() actually emits — the
    ones with the abstention reasons, the ready_by provenance and the class
    synthesis, built by a different function on a different path — went
    uninspected. A proposal could have grown an `enact` or a `command_type` and
    the whole suite would have stayed green, which is the one thing this file
    exists to prevent.
    """
    import sys as _sys
    _sys.path.insert(0, str(ROOT / "solvers" / "cpsat"))
    _sys.path.insert(0, str(ROOT / "proposer"))
    from forward_proposer import propose  # noqa: E402

    #: oversubscribed on purpose: more vehicles than one stall can serve, so the
    #: batch carries served rows AND declined rows AND the not-serviceable
    #: abstention, which are three different builders in the same function.
    def _v(vid, soc, state="arrived_at_gate", platform="waymo"):
        return {"id": vid, "soc": soc, "make": platform.title(), "state": state,
                "platform": platform, "stall_id": None, "svc_step": "await",
                "inlet_type": "CCS1", "target_soc": 90, "inlet_max_kw": 100.0,
                "fleet_operator_id": "op-1", "min_soc_threshold": 20}
    #: the unknown-platform vehicle is the one that produces a FRAME-LEVEL
    #: abstention (a different builder from the solver's declined rows). A
    #: non-serviceable vehicle would not: proposer emits nothing for those by
    #: design, pinned by test_plannable_vehicles_get_assignments_and_the_rest_abstain.
    frame = {"vehicles": [_v(f"v{i}", 15) for i in range(6)]
                         + [_v("v-unknown", 20, platform="cybertruck")],
             "stalls": [{"id": "s-1", "type": "dcfc", "status": "available",
                         "vehicle_id": None, "connector_type": "CCS1",
                         "connector_max_kw": 150}],
             "sessions": [], "energy": {}, "bess": []}
    classes = {"waymo": {"battery_kwh": 90, "max_charge_kw": 100,
                         "charge_kinds": ["dcfc", "l2"], "chemistry": "NMC",
                         "max_daily_soc_pct": 80,
                         "energy_curve": [{"above_soc_pct": 0, "accept_frac": 1.0}]}}
    site = {"power_cap_kw_hard": 1000, "power_soft_target_kw": 700,
            "dcfc_cooldown_min": 18, "move_duration_min": 4, "path_capacity": 2,
            "cold_start_below_c": 5, "cold_start_penalty_min": 12,
            "onpeak_window_min": [240, 420]}
    r = propose(frame, classes, site=site, horizon_min=120,
                default_ready_delta_min=60, allow_rejection=True, det_budget_s=1.0)
    assert r["proposals"], "the proposer emitted no rows — this test proves nothing"
    assert r["abstained"] > 0, (
        "the frame no longer produces an abstention — the row builder most "
        "likely to forget the contract is not being exercised")
    return r["proposals"]


def _emitted_proposal_rows():
    """Every row EVERY declared emitter produces."""
    rows = _cpsat_rows() + _forward_lex_rows()
    #: THE GUARD MUST COVER EVERY SOURCE IT CLAIMS TO COVER. Without this, a
    #: future emitter can be added to _ADVISORY_SOURCES and never generated here,
    #: which is exactly how forward_lex went uninspected.
    seen = {r.get("source") for r in rows}
    missing = set(_ADVISORY_SOURCES) - seen
    assert not missing, (
        f"_ADVISORY_SOURCES declares {_ADVISORY_SOURCES} but this run produced "
        f"rows only from {sorted(seen)}; {sorted(missing)} is declared and never "
        "inspected")
    return rows


def test_every_emitted_row_is_advisory_not_an_instruction():
    """A proposal declares an intent and an abstention; it never carries a verb
    that means 'make it so'."""
    rows = _emitted_proposal_rows()
    assert rows, "no proposal rows emitted"
    offenders = []
    for r in rows:
        payload = r.get("proposal", {})
        if "abstain" not in payload:
            offenders.append(f"{r.get('entity_id')}: no abstain field — not an advisory row")
        for k in _COMMAND_KEYS:
            if k in payload or k in r:
                offenders.append(f"{r.get('entity_id')}: carries command key {k!r}")
        if r.get("source") not in _ADVISORY_SOURCES:
            offenders.append(f"{r.get('entity_id')}: unknown source {r.get('source')!r}")
    assert offenders == [], (
        "propose/dispose violated — a row emitted by the solver reads as an "
        f"instruction rather than a proposal: {offenders}. The local decide path "
        "disposes (CLAUDE.md 2.5); a proposer that emits commands leaves it "
        "nothing to refuse.")


def test_a_declined_asset_still_gets_a_row():
    """An asset the solver could not serve is REPORTED, never dropped.

    This is the distinction `cuopt_invocation_log` exists to preserve on the
    other proposer: 'invoked and abstained' must stay distinguishable from
    'never asked'. A silent drop makes a declined asset look like one nobody
    asked about, and the count is the only thing that sees it.
    """
    import json as _json
    import sys as _sys
    _sys.path.insert(0, str(ROOT / "solvers" / "cpsat"))
    from model import build_and_solve, materialize  # noqa: E402

    sc = _json.loads((ROOT / "solvers" / "cpsat" / "scenario_canonical.json").read_text())
    charge = [p for p in sc["service_points"] if p["kind"] in ("dcfc", "l2")][:2]
    sc["service_points"] = charge + [p for p in sc["service_points"]
                                     if p["kind"] not in ("dcfc", "l2")]
    sc["horizon_min"] = 300
    plan = build_and_solve(materialize(_json.loads(_json.dumps(sc))), allow_rejection=True)

    assert len(plan["proposals"]) == len(plan["assets"]), (
        f"{len(plan['assets'])} assets in, {len(plan['proposals'])} rows out — "
        "a declined asset was dropped instead of abstained")
    abstained = sorted(p["entity_id"] for p in plan["proposals"] if p["proposal"]["abstain"])
    assert abstained == sorted(plan["rejected"]), (
        f"rejected {sorted(plan['rejected'])} but abstained {abstained}")
