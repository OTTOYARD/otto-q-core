"""The three key lists migration 0266 created must not drift apart.

WHY THIS FILE EXISTS, AND WHAT IT HONESTLY DOES NOT DO.

Migration 0266 split the certification canon's end-state atom in two. Before it,
ottoq_cert_matrix hashed the whole `endst` object:

    md5((p.j->'arm_a'->'endst')::text)

which covers every key the fingerprint emits BY CONSTRUCTION -- it cannot miss
one, because it never names one. After 0266 there are two digests that each
ENUMERATE their keys: seven paths in ottoq_cert_matrix (the run's own end state)
and four in ottoq_cert_residue (other runs' residue). That is what splitting
required, and db/checks/0197 §5 records the cost in full: an enumerated list is
exactly the thing that drifts, and if public.ottoq_boot_state_fingerprint ever
grows an eighth top-level key, that atom is streaked by NEITHER instrument and
leaves the canon silently while ottoq_determinism_pair goes on enforcing it.

THE RISK HAS FOUR PARTIES and this file can see only three of them:

    (a) public.ottoq_boot_state_fingerprint  -- what is actually emitted
    (b) ottoq_cert_matrix's c_endst list     -- the own half
    (c) ottoq_cert_residue's c_fgn list      -- the foreign half
    (d) db/checks/0198's expected arrays     -- the standing check

(a) lives only in the database. There is no live anchor for it in this repo:
db/baseline/functions_public.sql is a snapshot from 2026-08-26 that does not
contain the function at all, so a test against the baseline would be testing a
stale artefact and would pass while lying. Migration 0266's assertion A8 pins the
fingerprint's md5 AT APPLY TIME, and db/checks/0198 re-derives the shape from
recorded pairs -- but nothing RUNS db/checks today (grep: no workflow, no script,
no test invokes them; tests/test_migration_hygiene.py only enumerates the
directory). That is a future task, and until G12 lands the (a)
corner is guarded by discipline, not by machinery. Saying so is the point:
db/checks/0198 must not be quoted as a guard that runs.

WHAT THIS FILE DOES COVER is the failure that is both likelier and cheaper to
catch -- (b), (c) and (d) drifting apart from EACH OTHER. Someone extends the
split for a new key, edits one of the three lists, and misses the others. That
needs no database, so CI catches it on the push that introduces it.

EVERY TEST BELOW WAS PROVEN TO FAIL BEFORE IT WAS COMMITTED, because the whole
reason this file exists is that db/checks/0197 caught a suite of assertions that
could not fail. The mutations run, and what each one broke:

    drop 'world' from ottoq_cert_matrix's own list      -> 2 tests fail
    add a fifth section to ottoq_cert_residue's list    -> 2 tests fail
    make 0198 stop checking one section's sub-keys      -> 1 test fails
    strip 'G12' from this docstring                     -> 1 test fails
    strip the "nothing RUNS db/checks" admission        -> 1 test fails

AND TWO EARLIER MUTATION ATTEMPTS PROVED NOTHING, which is the part worth
keeping. Replacing 'G12' everywhere in the FILE rewrote the string literal inside
the assertion as well as the docstring, so the test compared the mutated text to
itself and passed. A mutation that moves the subject and the check together
measures nothing -- it is the same defect as the tautological assertion this file
was written in response to, wearing the clothes of a test of a test. The
mutations above therefore edit ONLY the module docstring (lines 1 to the closing
quotes) and leave every assertion untouched.
"""
import re
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[1]
MIGRATION = ROOT / "db" / "migrations" / (
    "0266_the_canon_stops_being_hostage_to_another_runs_leftovers.sql")
CHECK = ROOT / "db" / "checks" / (
    "0198_the_split_enumerates_keys_so_the_shape_must_be_watched.sql")

#: The shape as measured on 2026-09-13 over all 30 post-floor pairs and stated in
#: 0266's A9. A change here is a deliberate act that must move all four parties.
OWN_KEYS = ["bookings", "calibration", "chargers", "dispatches", "legs",
            "visit_needs", "world"]
FGN_KEYS = ["bookings", "dispatches", "legs", "visit_needs"]
SECTIONS = ["bookings", "dispatches", "legs", "visit_needs"]


pytestmark = pytest.mark.skipif(
    not MIGRATION.exists() or not CHECK.exists(),
    reason="0266/0198 not present")


def _fn_body(sql: str, name: str) -> str:
    """The text of one CREATE OR REPLACE FUNCTION body in a migration file."""
    start = sql.index(f"CREATE OR REPLACE FUNCTION public.{name}(")
    body_start = sql.index("AS $function$", start)
    body_end = sql.index("$function$;", body_start + len("AS $function$"))
    return sql[body_start:body_end]


def _built_keys(body: str, marker: str) -> list[str]:
    """Keys of the jsonb_build_object whose first key is `marker`.

    Read off the source rather than hand-maintained: the point of the test is
    that the list in the FILE is the thing checked, not a copy of it here.
    """
    i = body.index(marker)
    # the object runs to the matching ')::text)'
    j = body.index(")::text)", i)
    return sorted(set(re.findall(r"'([a-z_]+)',\s*(?:p\.j|q\.e|r\.)", body[i:j])))


def test_the_matrix_own_half_names_exactly_the_seven_keys():
    body = _fn_body(MIGRATION.read_text(), "ottoq_cert_matrix")
    keys = _built_keys(body, "'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'vis'")
    assert keys == OWN_KEYS, (
        f"ottoq_cert_matrix's c_endst enumerates {keys}; expected {OWN_KEYS}. "
        f"If the fingerprint gained or lost a key, ALL of: this list, "
        f"ottoq_cert_residue's c_fgn list, db/checks/0198's arrays and the "
        f"constants in this test must move together -- and the new atom is "
        f"promoted MEASURED-then-ENFORCED (CLAUDE.md 2.9a), not just added.")


def test_the_residue_foreign_half_names_exactly_the_four_sections():
    body = _fn_body(MIGRATION.read_text(), "ottoq_cert_residue")
    keys = _built_keys(body, "'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'fgn'")
    assert keys == FGN_KEYS, (
        f"ottoq_cert_residue's c_fgn enumerates {keys}; expected {FGN_KEYS}")


def test_the_two_halves_partition_the_object_and_do_not_overlap():
    """Every own key is either a section (whose fgn the residue takes) or a world
    key the residue must NOT take. If the residue ever mentions a world key the
    split has been drawn twice and one digest is double-counting."""
    mig = MIGRATION.read_text()
    own = _built_keys(_fn_body(mig, "ottoq_cert_matrix"),
                      "'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'vis'")
    fgn = _built_keys(_fn_body(mig, "ottoq_cert_residue"),
                      "'visit_needs', p.j->'arm_a'->'endst'->'visit_needs'->'fgn'")
    assert set(fgn) < set(own), "the foreign half names a key the own half does not"
    world = sorted(set(own) - set(fgn))
    assert world == ["calibration", "chargers", "world"], (
        f"the world keys are {world}; the own half is supposed to carry exactly "
        f"chargers, calibration and world beyond the four sections")


def test_the_standing_check_expects_the_same_shape():
    """db/checks/0198's ARRAY literals must agree with both function bodies.
    Nothing runs 0198 today (see this module's docstring and task G12), so this
    is the only thing keeping it honest."""
    text = CHECK.read_text()
    top = re.search(r"ARRAY\[((?:'[a-z_]+',?)+)\]\s*\n?\s*OR|"
                    r"IS DISTINCT FROM ARRAY\[((?:'[a-z_]+',\s*)+'[a-z_]+')\]", text)
    assert "ARRAY['bookings','calibration','chargers','dispatches','legs','visit_needs','world']" in text, (
        "db/checks/0198 no longer expects the seven-key top level that "
        "ottoq_cert_matrix enumerates")
    assert text.count("IS DISTINCT FROM ARRAY['fgn','vis']") == 4, (
        "db/checks/0198 must check {fgn,vis} under each of the four sections; "
        f"found {text.count(chr(39).join(['IS DISTINCT FROM ARRAY[', 'fgn', ',', 'vis', ']']))}")
    for s in SECTIONS:
        assert f"e->'{s}'" in text, f"0198 does not look at section {s}"


def test_this_test_names_what_it_cannot_see():
    """A guard that overstates its reach is worse than no guard. The module
    docstring must keep saying that the fingerprint function itself is outside
    this test's reach and that G12 is what would close it."""
    doc = __doc__ or ""
    assert "G12" in doc and "ottoq_boot_state_fingerprint" in doc
    assert "nothing RUNS db/checks today" in doc
