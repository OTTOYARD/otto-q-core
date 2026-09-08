"""The magenta audit's coverage number is DERIVED from the document, not asserted in it.

`docs/MAGENTA_AUDIT.md` opens with a coverage figure. For three passes that figure was
counted by hand out of prose outcome rows — six of which name their finding by its
sentence and not its id, and two of which use a numbering the master list does not
share — while all 87 findings carried an identical, never-ticked checklist. The
recounts went 31, then 36, then 76. Nobody could check any of them.

So the checklists became one `**Disposition:**` line per finding, and this file turns
the header number into a consequence of those lines. It fails if:

  * the document does not hold exactly 87 findings,
  * a finding has no disposition, or two,
  * a disposition uses a word outside the vocabulary,
  * a FIXED finding names a guard whose FILE or FUNCTION does not exist,
  * a DUPLICATE names an id that is missing, or that is itself OPEN,
  * the header's "Coverage is N of 87" disagrees with the dispositions below it.

The last one is the point. Everything else is scaffolding that keeps it honest.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
#: the two repos this audit spans; a guard path is resolved against their shared parent
WORKSPACE = ROOT.parent
DOC = ROOT / "docs" / "MAGENTA_AUDIT.md"

TOTAL_FINDINGS = 87
VOCABULARY = {"FIXED", "CORRECTED", "DUPLICATE", "BY_CONSTRUCTION", "REFUTED", "OPEN"}
#: a finding is CLOSED unless it is OPEN. REFUTED counts as closed on purpose: a
#: finding that was reproduced and found not to be a defect needs no further work,
#: and hiding it in the open column would understate the audit exactly as surely as
#: counting an unfixed one would overstate it.
OPEN_DISPOSITIONS = {"OPEN"}

HEADING = re.compile(r'^### ([SGLD]-\d\d) · ', re.M)
DISPOSITION = re.compile(r'^\*\*Disposition: ([A-Z_]+)\*\* — (.*)$', re.M)
GUARD = re.compile(r'([A-Za-z0-9_./-]+\.py)::(test_[A-Za-z0-9_]+)')
BARE_FILE = re.compile(r'\b([A-Za-z0-9_./-]+/[A-Za-z0-9_./-]+\.py)\b')
COVERAGE = re.compile(r'\*\*Coverage is (\d+) of (\d+),')


def _findings():
    """(id, disposition, detail) per finding, in document order."""
    text = DOC.read_text()
    marks = list(HEADING.finditer(text))
    out = []
    for i, m in enumerate(marks):
        end = marks[i + 1].start() if i + 1 < len(marks) else len(text)
        body = text[m.end():end]
        found = DISPOSITION.findall(body)
        assert len(found) == 1, (
            f"{m.group(1)} has {len(found)} disposition lines; it must have exactly one")
        out.append((m.group(1), found[0][0], found[0][1]))
    return out


def test_the_document_holds_every_finding_exactly_once():
    ids = [f[0] for f in _findings()]
    assert len(ids) == TOTAL_FINDINGS, f"expected {TOTAL_FINDINGS} findings, found {len(ids)}"
    dupes = sorted({i for i in ids if ids.count(i) > 1})
    assert not dupes, f"these ids appear more than once: {dupes}"


def test_every_disposition_is_in_the_vocabulary():
    bad = [(i, d) for i, d, _ in _findings() if d not in VOCABULARY]
    assert not bad, f"dispositions outside {sorted(VOCABULARY)}: {bad}"


def test_every_named_guard_exists():
    """A guard that does not exist is worse than no guard: it reads as evidence.

    Both the file and the function are checked, because a renamed test leaves the
    path valid and the claim false — which is the same shape as the tautological
    assertions this audit was convened to find.
    """
    missing = []
    for fid, disp, detail in _findings():
        for path, fn in GUARD.findall(detail):
            p = WORKSPACE / path
            if not p.exists():
                missing.append(f"{fid}: no such file {path}")
            elif not re.search(rf'^def {re.escape(fn)}\(', p.read_text(), re.M):
                missing.append(f"{fid}: {path} defines no {fn}")
        #: gate scripts and artifacts are named without a ::test, and must still exist
        for path in BARE_FILE.findall(detail):
            if f"{path}::" in detail:
                continue
            if not (WORKSPACE / path).exists():
                missing.append(f"{fid}: no such file {path}")
    assert not missing, missing


def test_every_fixed_finding_names_a_guard():
    naked = [fid for fid, disp, detail in _findings()
             if disp == "FIXED" and not GUARD.search(detail) and not BARE_FILE.search(detail)]
    assert not naked, (
        "these findings claim FIXED without naming what fails if the fix is reverted, "
        f"which is the audit's own standard of proof: {naked}")


def test_every_duplicate_points_at_a_closed_finding():
    by_id = {fid: (disp, detail) for fid, disp, detail in _findings()}
    bad = []
    for fid, disp, detail in _findings():
        if disp != "DUPLICATE":
            continue
        m = re.match(r'([SGLD]-\d\d)\b', detail)
        if not m:
            bad.append(f"{fid}: DUPLICATE names no id")
            continue
        target = m.group(1)
        if target not in by_id:
            bad.append(f"{fid}: DUPLICATE of {target}, which is not a finding")
        elif by_id[target][0] in OPEN_DISPOSITIONS:
            bad.append(f"{fid}: DUPLICATE of {target}, which is itself open")
        elif by_id[target][0] == "DUPLICATE":
            bad.append(f"{fid}: DUPLICATE of {target}, which is itself a duplicate")
    assert not bad, bad


def test_the_header_coverage_equals_the_dispositions_below_it():
    """The one assertion this file exists for.

    Editing the headline number without changing a disposition — or closing a finding
    without touching the headline — turns this red. The figure stops being a claim and
    becomes a measurement of the document it sits on top of.
    """
    findings = _findings()
    closed = sum(1 for _, d, _ in findings if d not in OPEN_DISPOSITIONS)
    m = COVERAGE.search(DOC.read_text())
    assert m, "the header no longer states coverage in the form '**Coverage is N of M,'"
    stated, total = int(m.group(1)), int(m.group(2))
    assert total == len(findings) == TOTAL_FINDINGS, (
        f"the header says {total} findings; the document holds {len(findings)}")
    assert stated == closed, (
        f"the header claims {stated} of {total} closed; the dispositions below it say "
        f"{closed}. Open: {sorted(fid for fid, d, _ in findings if d in OPEN_DISPOSITIONS)}")
