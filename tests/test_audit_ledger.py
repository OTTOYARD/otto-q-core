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

#: This audit spans two repositories, and CI checks out only this one. A guard
#: named in the sibling repo therefore CANNOT be verified from a CI run, and
#: pretending otherwise is the defect this whole file exists to prevent — so the
#: rule is: verify it when the sibling is on disk (it is in the build agent's
#: workspace, so renames are still caught there), report it as unverifiable when
#: it is not, and PIN THE COUNT so the exemption cannot quietly grow into a
#: place to hide a guard that does not exist.
THIS_REPO = "otto-q-core/"
SIBLING_REPOS = ("ottoq-intelligence/",)
CROSS_REPO_REFERENCES = 12

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


def _named_paths():
    """(finding, path, test_name or None) for every guard the document names."""
    for fid, _disp, detail in _findings():
        seen = set()
        for path, fn in GUARD.findall(detail):
            seen.add(path)
            yield fid, path, fn
        #: gate scripts and artifacts are named without a ::test and must still exist
        for path in BARE_FILE.findall(detail):
            if path not in seen:
                yield fid, path, None


def test_every_named_path_is_in_a_repository_this_audit_covers():
    """A path under neither repo is a typo, and a typo would be exempted below."""
    stray = sorted({(fid, path) for fid, path, _ in _named_paths()
                    if not path.startswith(THIS_REPO)
                    and not path.startswith(SIBLING_REPOS)})
    assert not stray, (
        f"these guard paths name neither {THIS_REPO!r} nor {SIBLING_REPOS}: {stray}")


def test_the_cross_repo_exemption_has_not_widened():
    """The count of guards this repo cannot check is pinned, deliberately.

    CI checks out otto-q-core alone, so a guard living in ottoq-intelligence
    cannot be verified from a CI run — and an exemption nobody counts is exactly
    where a guard that does not exist would come to rest. Twelve findings are in
    that position today (S-01..S-03 and the priors/forecast cluster). Adding a
    thirteenth turns this red and asks for the number to be moved on purpose.
    """
    cross = sorted({(fid, path) for fid, path, _ in _named_paths()
                    if path.startswith(SIBLING_REPOS)})
    assert len(cross) == CROSS_REPO_REFERENCES, (
        f"{len(cross)} cross-repo guard references, pinned at "
        f"{CROSS_REPO_REFERENCES}. If that is deliberate, move the pin in the "
        f"same commit: {cross}")


def test_every_named_guard_exists():
    """A guard that does not exist is worse than no guard: it reads as evidence.

    Both the file and the function are checked, because a renamed test leaves the
    path valid and the claim false — which is the same shape as the tautological
    assertions this audit was convened to find.

    In-repo guards are checked unconditionally. A guard in the sibling repo is
    checked WHEN THAT REPO IS ON DISK — it is in the build agent's workspace, so
    a rename there is still caught — and skipped when it is not, because CI
    checks out this repository alone and a check that fails for the absence of
    something it was never given is noise, not evidence. What stops that skip
    from becoming a hiding place is not this test but the pinned count in
    test_the_cross_repo_exemption_has_not_widened.
    """
    missing, unverifiable = [], []
    for fid, path, fn in _named_paths():
        p = WORKSPACE / path
        if not p.exists():
            if path.startswith(SIBLING_REPOS):
                unverifiable.append(f"{fid}: {path} (sibling repo not checked out)")
            else:
                missing.append(f"{fid}: no such file {path}")
            continue
        if fn and not re.search(rf'^def {re.escape(fn)}\(', p.read_text(), re.M):
            missing.append(f"{fid}: {path} defines no {fn}")
    assert not missing, missing
    if unverifiable:
        print(f"{len(unverifiable)} cross-repo guards not verified here "
              f"(count pinned at {CROSS_REPO_REFERENCES}): {unverifiable}")


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
