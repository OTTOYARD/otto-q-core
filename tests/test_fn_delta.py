"""Tests for scripts/fn-delta.py — the pg_stat_user_functions differ.

Two of these pin behaviour that was WRONG on the first draft and was caught
only by running the tool against the real committed baseline:

  * overloads. `pg_stat_user_functions` is keyed by `funcid`, so one name can
    hold two rows. The first draft called that a duplicate and exited.
  * a counter going DOWN. That means `pg_stat_reset()` ran between the two
    captures, and the delta is not a measurement of anything.

The last test runs against `db/evidence/r28_g_fn_baseline.md` itself, so the
file that round 28's function diff depends on cannot silently stop parsing.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

import pytest

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "scripts" / "fn-delta.py"
BASELINE = REPO / "db" / "evidence" / "r28_g_fn_baseline.md"


def run(before: Path, after: Path, *extra):
    """Invoke the tool as a subprocess; return (returncode, stdout)."""
    proc = subprocess.run(
        [sys.executable, str(TOOL), str(before), str(after), *extra],
        capture_output=True, text=True, timeout=60,
    )
    return proc.returncode, proc.stdout + proc.stderr


def capture(tmp_path: Path, name: str, *rows: str) -> Path:
    """Write a capture file: prose the parser must ignore, then a fenced block."""
    path = tmp_path / name
    body = "\n".join(rows)
    path.write_text(
        f"# {name}\n\nprose the parser must ignore, including a|b|c|d\n\n"
        f"```\n{body}\n```\n",
        encoding="utf-8",
    )
    return path


def test_identical_captures_show_no_movement(tmp_path):
    a = capture(tmp_path, "a.md", "public|f|10|5.0", "twin|g|3|1.5")
    rc, out = run(a, a)
    assert rc == 0
    assert "0 function(s) moved" in out


def test_delta_is_after_minus_before(tmp_path):
    b = capture(tmp_path, "b.md", "public|f|10|5.0")
    a = capture(tmp_path, "a.md", "public|f|37|22.5")
    rc, out = run(b, a)
    assert rc == 0
    assert "1 function(s) moved" in out
    assert "27" in out and "17.5" in out


def test_function_absent_from_before_is_its_full_value_and_marked_new(tmp_path):
    b = capture(tmp_path, "b.md", "public|f|10|5.0")
    a = capture(tmp_path, "a.md", "public|f|10|5.0", "public|brand_new|55|3.5")
    rc, out = run(b, a)
    assert rc == 0
    assert "public.brand_new NEW" in out
    assert "55" in out


def test_overloaded_name_is_summed_not_rejected(tmp_path):
    """Two funcids, one name. The first draft exited here; summing is correct."""
    b = capture(tmp_path, "b.md", "public|frame|48|571.0", "public|frame|1|7.1")
    a = capture(tmp_path, "a.md", "public|frame|148|671.0", "public|frame|1|7.1")
    rc, out = run(b, a)
    assert rc == 0
    assert "were SUMMED" in out
    assert "2 row(s) before, 2 after" in out
    # 149 - 49 = 100 calls, 678.1 - 578.1 = 100.0 ms
    assert "100" in out


def test_counter_going_down_voids_the_whole_delta(tmp_path):
    b = capture(tmp_path, "b.md", "public|f|99|50.0")
    a = capture(tmp_path, "a.md", "public|f|10|5.0")
    rc, out = run(b, a)
    assert rc == 1, "a reset must be a non-zero exit, not a footnote"
    assert "VOID" in out
    assert "99 -> 10" in out


def test_self_time_going_down_alone_is_also_a_reset(tmp_path):
    """Calls can be equal while self_time drops -- still a reset, still void."""
    b = capture(tmp_path, "b.md", "public|f|10|50.0")
    a = capture(tmp_path, "a.md", "public|f|10|5.0")
    rc, out = run(b, a)
    assert rc == 1
    assert "VOID" in out


def test_function_present_in_before_and_gone_from_after_is_reported(tmp_path):
    b = capture(tmp_path, "b.md", "public|f|10|5.0", "public|vanished|9|1.0")
    a = capture(tmp_path, "a.md", "public|f|10|5.0")
    rc, out = run(b, a)
    assert rc == 0
    assert "public.vanished" in out
    assert "absent from AFTER" in out


def test_a_file_with_no_rows_is_refused(tmp_path):
    empty = tmp_path / "empty.md"
    empty.write_text("# nothing here\n\njust prose\n", encoding="utf-8")
    good = capture(tmp_path, "good.md", "public|f|10|5.0")
    rc, out = run(empty, good)
    assert rc != 0
    assert "no `schema|function|calls|self_ms` rows" in out


def test_rows_outside_a_fence_are_not_parsed(tmp_path):
    """A pipe-shaped line in prose must not become a data row."""
    path = tmp_path / "loose.md"
    path.write_text("public|f|10|5.0\n", encoding="utf-8")
    good = capture(tmp_path, "good.md", "public|f|10|5.0")
    rc, out = run(path, good)
    assert rc != 0, "an unfenced row must not be mistaken for a capture"


@pytest.mark.skipif(not BASELINE.exists(), reason="r28_g baseline not present")
def test_the_committed_r28_g_baseline_parses_and_self_diffs_clean():
    """The file round 28's function diff depends on must keep parsing."""
    rc, out = run(BASELINE, BASELINE)
    assert rc == 0
    assert "0 function(s) moved" in out
    # It has exactly one overloaded name; that is recorded in its addendum.
    assert "public.ottoq_build_decision_frame: 2 row(s) before, 2 after" in out
