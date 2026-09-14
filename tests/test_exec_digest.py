"""Tests for scripts/exec-digest.py — the "did I submit the real SQL?" prover.

WHY THIS TOOL EXISTS. APPLYING.md step 4 allows a long migration header to be
condensed at the apply call ONLY if the executable SQL is proven identical by
digest (the 0224 precedent). The tool turns that proof into one command.

WHY THESE TESTS EXIST, AND IT IS NOT HYPOTHETICAL. The tool's FIRST version was
unsafe and was used unsafely within minutes of being written:

  * 0252 was applied with four comment-only lines stripped from inside a
    $function$ body, so the stored ottoq_cert_coverage body was 1385 bytes
    against the file's 1708 -- file-vs-database drift of exactly the kind G18
    exists to prevent.
  * and the digest check run at the time reported MATCH, because it compared the
    comment-STRIPPED file against the comment-STRIPPED live body. It was
    structurally incapable of detecting the single deviation it was there to
    catch.

So `--check` was added: a comment inside a body the database STORES is not a
comment on the migration, it is part of a stored definition, and such a file must
be submitted whole. The tests below pin that distinction, in both directions --
a $$ DO block is exempt because it executes once and is never stored.

The last test runs --check over every committed migration, so the tool cannot
silently stop parsing the corpus it is meant to police.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
TOOL = REPO / "scripts" / "exec-digest.py"
MIGRATIONS = REPO / "db" / "migrations"


def run(*args):
    proc = subprocess.run(
        [sys.executable, str(TOOL), *[str(a) for a in args]],
        capture_output=True, text=True,
    )
    return proc.returncode, proc.stdout + proc.stderr


def write(tmp_path, name, text):
    p = tmp_path / name
    p.write_text(text)
    return p


# --------------------------------------------------------------------------
# The digest itself
# --------------------------------------------------------------------------

def test_condensing_a_header_does_not_change_the_digest(tmp_path):
    """The whole point: prose differs, executable SQL does not."""
    long_header = write(tmp_path, "long.sql", """\
-- ====================================================
-- 0999  A VERY LONG HEADER INDEED
-- ====================================================
-- paragraphs and paragraphs of hard-won reasoning
-- about why this migration exists at all
SELECT 1;
""")
    short_header = write(tmp_path, "short.sql", """\
-- 0999 A VERY LONG HEADER INDEED (condensed)
SELECT 1;
""")
    rc, out = run(long_header, short_header)
    assert rc == 0, out
    assert "MATCH" in out


def test_changed_sql_is_caught_even_with_identical_prose(tmp_path):
    a = write(tmp_path, "a.sql", "-- same comment\nSELECT 1;\n")
    b = write(tmp_path, "b.sql", "-- same comment\nSELECT 2;\n")
    rc, out = run(a, b)
    assert rc == 1, out
    assert "DIFFER" in out


def test_reindentation_is_not_a_deviation(tmp_path):
    a = write(tmp_path, "a.sql", "SELECT 1,\n       2;\n")
    b = write(tmp_path, "b.sql", "SELECT 1,    2;\n")
    rc, out = run(a, b)
    assert rc == 0, out
    assert "MATCH" in out


def test_a_trailing_comment_is_never_stripped(tmp_path):
    """`--` can appear inside a string literal, so only FULL-line comments go.

    If trailing comments were stripped, these two would compare equal and a real
    difference in a string literal would be invisible.
    """
    a = write(tmp_path, "a.sql", "SELECT 'a -- b';\n")
    b = write(tmp_path, "b.sql", "SELECT 'a ';\n")
    rc, out = run(a, b)
    assert rc == 1, out


# --------------------------------------------------------------------------
# --check: the trap that 0252 fell into
# --------------------------------------------------------------------------

def test_check_refuses_a_comment_inside_a_function_body(tmp_path):
    """This is the 0252 defect, reduced. Exit 2, and the line is named."""
    f = write(tmp_path, "fn.sql", """\
CREATE OR REPLACE FUNCTION f() RETURNS int LANGUAGE sql AS $function$
  -- this line becomes part of the STORED body
  SELECT 1;
$function$;
""")
    rc, out = run("--check", f)
    assert rc == 2, out
    assert "UNSAFE TO CONDENSE" in out
    assert "$function$" in out
    assert "STORED body" in out


def test_check_refuses_a_comment_inside_a_procedure_body(tmp_path):
    """0251 had eight of these."""
    f = write(tmp_path, "proc.sql", """\
CREATE OR REPLACE PROCEDURE p() LANGUAGE plpgsql AS $procedure$
BEGIN
  -- stored, therefore load-bearing
  PERFORM 1;
END;
$procedure$;
""")
    rc, out = run("--check", f)
    assert rc == 2, out
    assert "$procedure$" in out


def test_check_exempts_an_anonymous_do_block(tmp_path):
    """A $$ DO block executes once and is never stored, so its comments are free."""
    f = write(tmp_path, "do.sql", """\
DO $$
BEGIN
  -- an assertion's reasoning, never stored anywhere
  ASSERT true;
END $$;
""")
    rc, out = run("--check", f)
    assert rc == 0, out
    assert "safe to condense" in out


def test_check_passes_a_body_with_no_comments_in_it(tmp_path):
    f = write(tmp_path, "clean.sql", """\
-- a header comment is fine, it is not inside a body
CREATE OR REPLACE FUNCTION f() RETURNS int LANGUAGE sql AS $function$
  SELECT 1;
$function$;
""")
    rc, out = run("--check", f)
    assert rc == 0, out
    assert "safe to condense" in out


# --------------------------------------------------------------------------
# Against the real corpus
# --------------------------------------------------------------------------

def test_check_parses_every_committed_migration():
    """Never crashes, and always answers, over the whole corpus.

    Exit 0 or 2 are both correct answers (2 just means some file carries comments
    inside a stored body, which most do and which is fine when submitted whole).
    Anything else means the tool broke on real input.
    """
    files = sorted(MIGRATIONS.glob("0*.sql"))
    assert len(files) > 50, f"expected the real corpus, found {len(files)}"
    rc, out = run("--check", *files)
    assert rc in (0, 2), f"tool failed on the real corpus: rc={rc}\n{out[:2000]}"
    for f in files:
        assert f.name in out, f"{f.name} got no verdict"


def test_0251_is_still_flagged_unsafe_and_0253_still_safe():
    """Pins the two real files the distinction was discovered on.

    0251 carries eight comment lines inside a $procedure$ body; 0253 carries none
    inside any stored body. If either verdict flips, the tool's notion of "stored"
    has changed and the APPLIED footers in both files are no longer true.
    """
    p0251 = next(MIGRATIONS.glob("0251_*.sql"))
    p0253 = next(MIGRATIONS.glob("0253_*.sql"))

    rc, out = run("--check", p0251)
    assert rc == 2, out
    assert "UNSAFE TO CONDENSE" in out

    rc, out = run("--check", p0253)
    assert rc == 0, out
    assert "safe to condense" in out
