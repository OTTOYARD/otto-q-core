"""FINDINGS.md is the open-findings register. Its value is entirely in its links:
a register that points at a file that no longer exists is worse than no register,
because it reads as evidence. This keeps the links honest.

MIGRATION_LOG.md's index is generated, so its links are correct by construction --
which is exactly why it is cheap to assert, and why a generator bug would show up
here rather than in a reader's confusion.
"""
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LINK = re.compile(r"\]\((?!https?://|#)([^)]+)\)")


def _relative_links(name):
    path = ROOT / name
    assert path.exists(), f"{name} is missing"
    return sorted({m.group(1).split("#")[0] for m in LINK.finditer(path.read_text())})


def test_the_findings_register_exists_and_links_to_something():
    links = _relative_links("FINDINGS.md")
    assert links, "FINDINGS.md cites no evidence files at all"


def test_every_findings_link_resolves():
    missing = [t for t in _relative_links("FINDINGS.md") if not (ROOT / t).exists()]
    assert not missing, (
        "FINDINGS.md cites files that do not exist -- a register that points at "
        f"nothing reads as evidence and is not: {missing}"
    )


def test_every_migration_log_link_resolves():
    missing = [t for t in _relative_links("MIGRATION_LOG.md") if not (ROOT / t).exists()]
    assert not missing, f"MIGRATION_LOG.md cites files that do not exist: {missing}"
