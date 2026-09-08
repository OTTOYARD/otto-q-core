"""Site Alpha harness guards.

The harness itself is exercised by run_matrix.py, which byte-compares two
committed artifacts. What lives here is the property those artifacts cannot
show: that the SOLVE behind them is bounded by deterministic work alone.
"""

from __future__ import annotations

import sys
from pathlib import Path

HERE = Path(__file__).parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(HERE.parent.parent))

HARNESS = HERE / "harness_alpha.py"


def test_the_solve_binds_no_wall_clock(  ):
    """L-53: a wall clock that can decide a plan makes it a function of how
    loaded the box was — while every cell this harness writes is published
    under a seed and a run id as byte-reproducible, and nothing recorded that a
    clock had been bound.

    `max_deterministic_time` is already a hard cutoff in CP-SAT, so the
    600-second limit was redundant against a slow SEARCH; and it never covered
    the one thing a backstop would be for — a hang in model CONSTRUCTION, which
    happens before Solve() is called and which no solver parameter bounds.
    Removing it, rather than labelling its output, is the finding's own
    preferred fix. Proof it never bit: both committed artifacts still match
    byte-for-byte with it gone.
    """
    #: Comments stripped first: the comment explaining the removal names the
    #: parameter, and a scan that cannot tell a mention from a call proves
    #: nothing.
    src = "\n".join(l for l in HARNESS.read_text().splitlines()
                    if not l.lstrip().startswith("#"))
    assert "max_time_in_seconds" not in src, (
        "a wall-clock limit is back in the Site Alpha solve; a clock-truncated "
        "plan would be published under a run id as seed-reproducible")
    assert "max_deterministic_time" in src, (
        "the deterministic budget is the bound that must stay")
