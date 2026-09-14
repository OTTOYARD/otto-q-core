"""The compile-check linter must fail on the two bugs it was built for.

A linter nobody has seen fail is a linter nobody has tested -- the same argument
0322's A2 makes about a trigger. Both fixtures below are reconstructions of bugs
that actually shipped into PENDING migrations on 2026-09-14, plus a control that
must PASS so a linter that simply fails everything cannot satisfy the suite.

These tests SKIP rather than fail when no scratch server is listening, so CI
without a database stays green; the value is in running them where one exists,
which is what G12 is for.
"""
import os
import shutil
import subprocess
import tempfile

import pytest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CHECK = os.path.join(ROOT, "scripts", "compile-check.py")

# 0321: RAISE accepts a bare %, format() demands %s. RUNTIME error, so only the
# run pass sees it -- the block compiles cleanly.
BUG_FORMAT = """
DO $pre$
DECLARE v text; TPL CONSTANT text := '0321 P0: % not found';
BEGIN
  IF v IS NULL THEN RAISE EXCEPTION '%', format(TPL,'twin.some_fn'); END IF;
END $pre$;
"""

# 0322: '%%' is a literal percent, so three placeholders were fed four
# arguments. COMPILE-time error -- caught by either pass.
BUG_RAISE = """
DO $t$
DECLARE a int := 1; b int := 2; c int := 3; d int := 4;
BEGIN
  RAISE EXCEPTION 'dispatch % changes % -> %% without moving (still %)', a, b, c, d;
END $t$;
"""

GOOD = """
DO $t$
DECLARE a int := 1;
BEGIN
  RAISE NOTICE 'fine %', a;
END $t$;
"""


def _server_up():
    if not shutil.which("psql"):
        return False
    p = subprocess.run(
        ["psql", "-h", "/var/tmp", "-p", "55432", "-U", "postgres",
         "-d", "postgres", "-Atc", "select 1"],
        capture_output=True, text=True)
    return p.returncode == 0


def _run(sql):
    with tempfile.NamedTemporaryFile("w", suffix=".sql", delete=False) as fh:
        fh.write(sql)
        path = fh.name
    try:
        return subprocess.run(["python3", CHECK, path], capture_output=True, text=True)
    finally:
        os.unlink(path)


pytestmark = pytest.mark.skipif(
    not _server_up(), reason="no scratch PostgreSQL on /var/tmp:55432")


def test_it_catches_the_format_specifier_bug():
    """0321's bug. Only the RUN pass sees this one; the block compiles fine.

    This test is the reason the linter has two passes at all: an earlier version
    had only the compile pass, this fixture PASSED it, and the docstring's claim
    to catch this bug was false until the test disproved it."""
    r = _run(BUG_FORMAT)
    assert r.returncode == 1, f"linter passed a known-bad file:\n{r.stdout}"
    assert "unrecognized format() type specifier" in r.stdout
    assert "[run]" in r.stdout, "expected the run pass to be the one that caught it"


def test_it_catches_the_raise_arity_bug():
    """0322's bug, and the compile pass must be one of the finders -- that pass
    is what reaches blocks a failed precondition would otherwise skip."""
    r = _run(BUG_RAISE)
    assert r.returncode == 1, f"linter passed a known-bad file:\n{r.stdout}"
    assert "too many parameters specified for RAISE" in r.stdout
    assert "[compile block" in r.stdout, "the compile pass should have caught this"


def test_it_passes_a_correct_block():
    """The control. Without it, a linter that failed everything would satisfy
    both tests above."""
    r = _run(GOOD)
    assert r.returncode == 0, f"linter failed a correct file:\n{r.stdout}"
