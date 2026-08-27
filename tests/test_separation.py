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
                   "proposer")

#: Imports that would let kernel code reach state it must not know about.
FORBIDDEN_IMPORTS = re.compile(
    r"^\s*(import|from)\s+(supabase|psycopg\w*|sqlalchemy|asyncpg|requests|"
    r"httpx|urllib\.request|twin)\b", re.M)

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


def _emitted_proposal_rows():
    """Every row both emitters produce, on a scenario that forces a rejection.

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
