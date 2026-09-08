"""Tests for scripts/sqlstruct.py — the code/literal separator.

The point of this module is that it can tell code from literal in files whose
function bodies are dollar-quoted. So the tests are mostly adversarial cases
where a naive regex gets the wrong answer, plus a live test against the very
file that caused `FINDINGS.md` G12 to reject a file-only lint.
"""
from __future__ import annotations

import glob
import re
import sys
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "scripts"))
import sqlstruct  # noqa: E402

REPO = Path(__file__).resolve().parents[1]


# --------------------------------------------------------------- offsets ----
def test_code_only_preserves_length_and_lines():
    src = "SELECT 1; -- a comment\n/* block */ SELECT 'lit';\n"
    out = sqlstruct.code_only(src)
    assert len(out) == len(src)
    assert out.count("\n") == src.count("\n")


def test_regions_cover_the_whole_string_without_gaps():
    src = "a --c\n'b' $x$d$x$ /*e*/ f"
    regions = sqlstruct.segment(src)
    assert regions[0].start == 0
    assert regions[-1].end == len(src)
    for a, b in zip(regions, regions[1:]):
        assert a.end == b.start, "regions must tile the input"


# ------------------------------------------------------- literals hidden ----
def test_keyword_inside_a_string_is_not_code():
    src = "RAISE EXCEPTION 'expected LIMIT 1 sites';"
    assert "LIMIT" not in sqlstruct.code_only(src)


def test_keyword_inside_a_line_comment_is_not_code():
    assert "LIMIT" not in sqlstruct.code_only("-- fixed one unordered LIMIT 1 today\n")


def test_keyword_inside_a_block_comment_is_not_code():
    assert "LIMIT" not in sqlstruct.code_only("/* LIMIT 1 */ SELECT 1;")


def test_doubled_quote_escape_does_not_end_the_string():
    src = "SELECT 'it''s LIMIT 1 here', x;"
    out = sqlstruct.code_only(src)
    assert "LIMIT" not in out
    assert "x" in out, "code after the string must survive"


def test_e_string_backslash_escape():
    src = r"SELECT E'a\' still LIMIT 1', y;"
    out = sqlstruct.code_only(src)
    assert "LIMIT" not in out
    assert "y" in out


def test_block_comments_nest_as_postgres_does():
    src = "/* outer /* inner */ still comment LIMIT 1 */ SELECT 2;"
    out = sqlstruct.code_only(src)
    assert "LIMIT" not in out
    assert "SELECT 2" in out


# --------------------------------------------------------- dollar quotes ----
def test_dollar_body_is_recursed_so_its_code_is_visible():
    src = "DO $mig$ BEGIN SELECT 1 LIMIT 1; END $mig$;"
    out = sqlstruct.code_only(src)
    assert "LIMIT 1" in out, "a function body is code, not an opaque literal"
    assert "$mig$" not in out, "the delimiters themselves are not code"


def test_literal_inside_a_dollar_body_is_still_hidden():
    src = "DO $mig$ BEGIN RAISE EXCEPTION 'LIMIT 1'; END $mig$;"
    assert "LIMIT" not in sqlstruct.code_only(src)


def test_nested_dollar_tags_close_on_their_own_tag():
    src = "$a$ outer $b$ inner $b$ outer $a$"
    regions = [r for r in sqlstruct.segment(src) if r.kind == "dollar"]
    assert len(regions) == 1
    assert regions[0].tag == "a"
    assert regions[0].end == len(src)


def test_anonymous_dollar_tag():
    src = "$$ body $$"
    regions = [r for r in sqlstruct.segment(src) if r.kind == "dollar"]
    assert len(regions) == 1 and regions[0].tag == ""


def test_dollar_tag_balance_counts_pairs():
    src = "DO $mig$ SELECT $a$x$a$, $a$y$a$; $mig$;"
    assert sqlstruct.dollar_tag_balance(src) == {"mig": 2, "a": 4}


def test_dollar_amount_is_not_a_quote():
    # $1 is a positional parameter, not a dollar-quote opener.
    src = "SELECT $1, $2;"
    assert [r.kind for r in sqlstruct.segment(src)] == ["code"]


# ------------------------------- a dollar body that is NOT SQL (0221) ----
def test_dollar_literal_with_unbalanced_apostrophe_is_treated_as_a_literal():
    """`db/migrations/0221` writes a dollar-quoted STRING whose content carries
    an unbalanced apostrophe — valid PostgreSQL, because dollar quoting exists
    so apostrophes need no escaping:

        IF position($$COALESCE(b.sim_run_id,'00000000$$ in v_flat) <> 0

    The first version of `code_only` recursed into every dollar body and raised
    on this. A guard that fires on correct input is worse than no guard, which
    is the lesson 0221's own comment three lines above states.
    """
    src = "IF position($$COALESCE(b.sim_run_id,'00000000$$ in v_flat) <> 0 THEN x; END IF;"
    out = sqlstruct.code_only(src)              # must not raise
    assert "COALESCE" not in out, "the literal body must be blanked, not read as code"
    assert "v_flat" in out and "THEN x" in out, "surrounding code must survive"
    assert len(out) == len(src)


def test_dollar_literal_does_not_break_tag_balance():
    src = "IF position($$a'b$$ in v) <> 0 THEN NULL; END IF;"
    assert sqlstruct.dollar_tag_balance(src) == {"": 2}


def test_the_real_0221_file_is_clean():
    path = glob.glob(str(REPO / "db" / "migrations" / "0221_*.sql"))
    assert path, "0221 not found; this test names a specific file on purpose"
    src = Path(path[0]).read_text(encoding="utf-8")
    counts = sqlstruct.dollar_tag_balance(src)
    assert all(c % 2 == 0 for c in counts.values()), counts


# ----------------------------------------------------------- unbalanced ----
@pytest.mark.parametrize("src", [
    "DO $mig$ BEGIN END;",          # dollar quote never closes
    "SELECT 'unterminated;",        # string never closes
    "/* never closed",              # block comment never closes
])
def test_unterminated_regions_raise(src):
    with pytest.raises(sqlstruct.UnterminatedRegion):
        sqlstruct.segment(src)


# ------------------------------------------- the repo's own files parse ----
SQL_FILES = sorted(
    glob.glob(str(REPO / "db" / "migrations" / "*.sql"))
    + glob.glob(str(REPO / "db" / "checks" / "*.sql"))
    + glob.glob(str(REPO / "scripts" / "*.sql"))
)


def test_there_are_sql_files_to_check():
    assert len(SQL_FILES) > 100, "the glob found nothing; the test would be vacuous"


@pytest.mark.parametrize("path", SQL_FILES, ids=lambda p: Path(p).name[:40])
def test_every_sql_file_segments_and_balances(path):
    """Every committed SQL file must tokenize, and every dollar tag must pair.

    This is the check that was done BY EYE on 0225 after five hand splices in
    one afternoon. Doing it by eye is how a sixth splice eventually ships with
    an unbalanced `$a$`.
    """
    src = Path(path).read_text(encoding="utf-8")
    counts = sqlstruct.dollar_tag_balance(src)          # raises if unterminated
    odd = {t: c for t, c in counts.items() if c % 2}
    assert not odd, f"unbalanced dollar tags in {Path(path).name}: {odd}"


# ----------------------------------------- G12's rejected lint, revisited ----
def test_code_only_removes_the_noise_that_killed_the_limit1_lint():
    """FINDINGS.md G12 rejected a `LIMIT 1` lint because it could not tell code
    from literal in dollar-quoted bodies. On 0220 the raw text matches many
    times and almost all of them are prose or error-message strings.

    This asserts the separation works on that exact file: strictly fewer hits
    in code than in raw text, and every surviving hit is real SQL.
    """
    path = glob.glob(str(REPO / "db" / "migrations" / "0220_*.sql"))
    assert path, "0220 not found; this test names a specific file on purpose"
    src = Path(path[0]).read_text(encoding="utf-8")
    pat = re.compile(r"\bLIMIT\s+1\b", re.I)

    raw_hits = len(pat.findall(src))
    code_hits = len(pat.findall(sqlstruct.code_only(src)))

    assert raw_hits >= 10, f"expected the raw file to be noisy, got {raw_hits}"
    assert code_hits < raw_hits, "the separator removed nothing"
    assert code_hits <= 5, f"expected only a handful of real sites, got {code_hits}"
