"""Every open item a check file leaves behind must be tracked where someone will read it.

WHY THIS TEST EXISTS, in Chase's words (2026-09-20): *"When you identify things I need to be
addressed. Do not lose track with them or pass over them. Either address them immediately or
immediately make note and continue working where you were. We can't afford to come across
something that needs to get fixed and then lose track of it because we're going down another
rabbit hole."*

MEASURED BEFORE BUILDING IT, because the leak was real and predates the instruction. Scanning
`db/checks/*.sql` for open-question prose found 18 files, of which **13 were referenced nowhere in
FINDINGS.md**. Four of those 13 turned out to say the question was ANSWERED later in the same file
-- so a prose regex over-reports, which is precisely the loose-predicate error this repo keeps
paying for (`0289`'s `offerable`, `0392`'s `resolved_action_context`, `0294` §2's own confound: a
field or phrase that answers one question read as answering a stricter one).

SO THE MARKER IS EXPLICIT, NOT INFERRED. A check file that leaves something open writes

    -- OPEN-ITEM: <one line saying what is open>

and this test requires that file's number to be referenced from FINDINGS.md (as `checks/NNNN`) or
listed in `db/checks/OPEN_ITEMS_BACKLOG.md`. Declared rather than derived -- the same discipline as
`ottoq_enactment_branches` and `ottoq_kpi_touch_actor_types`. No prose is parsed for meaning, so
there are no false positives to teach anyone to ignore this test.

WHAT IT CANNOT DO, said plainly: it cannot tell whether an item was written down honestly, and it
cannot make anyone fix one. It closes exactly one failure mode -- an item noted in a check file and
then lost because nothing downstream referenced it.
"""
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CHECKS = ROOT / "db" / "checks"
FINDINGS = ROOT / "FINDINGS.md"
BACKLOG = CHECKS / "OPEN_ITEMS_BACKLOG.md"

MARKER = re.compile(r"^\s*--\s*OPEN-ITEM:\s*(?P<text>\S.*)$", re.MULTILINE)


def _open_items() -> dict[str, list[str]]:
    """{check number: [item text, ...]} for every declared OPEN-ITEM."""
    found: dict[str, list[str]] = {}
    for path in sorted(CHECKS.glob("*.sql")):
        number = path.name[:4]
        if not number.isdigit():
            continue
        items = [m.group("text").strip() for m in MARKER.finditer(path.read_text())]
        if items:
            found[number] = items
    return found


def test_every_open_item_is_tracked_somewhere_a_reader_will_look():
    items = _open_items()
    assert items, ("no OPEN-ITEM markers found at all. Either no check file has left anything "
                   "open -- unlikely -- or the marker convention has drifted and this test has "
                   "quietly stopped guarding anything.")
    findings = FINDINGS.read_text()
    backlog = BACKLOG.read_text() if BACKLOG.exists() else ""
    untracked = {
        number: texts for number, texts in items.items()
        if f"checks/{number}" not in findings and number not in backlog
    }
    assert not untracked, (
        "these check files declare an OPEN-ITEM that nothing tracks. Add the item to FINDINGS.md "
        "(referencing db/checks/<number>) or, if it is not yet triaged, list it in "
        f"db/checks/OPEN_ITEMS_BACKLOG.md:\n" +
        "\n".join(f"  {n}: {t[0][:120]}" for n, t in sorted(untracked.items())))


def test_an_open_item_says_something():
    """A marker with no text is a marker nobody can act on."""
    for number, texts in _open_items().items():
        for text in texts:
            assert len(text) >= 25, (
                f"check {number} has an OPEN-ITEM shorter than 25 characters ({text!r}). "
                "The point of the marker is that the next reader knows what is open without "
                "reading the whole file.")


def test_the_backlog_file_is_not_a_dumping_ground():
    """A backlog entry must name its check number AND say what is open.

    The failure this guards is the obvious way to defeat the test above: paste thirteen numbers
    into the backlog and call them tracked.
    """
    if not BACKLOG.exists():
        return
    for line in BACKLOG.read_text().splitlines():
        m = re.match(r"^\s*[-*]\s*\*\*(?P<n>\d{4})\*\*\s*(?P<rest>.*)$", line)
        if not m:
            continue
        assert len(m.group("rest").strip()) >= 40, (
            f"backlog entry for {m.group('n')} says too little: {m.group('rest')!r}. "
            "Name what is open, not just the file.")
