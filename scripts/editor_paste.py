#!/usr/bin/env python3
"""
editor_paste.py — the text a person pastes into the Supabase SQL editor to apply one migration file.

WHY THIS EXISTS. When the database connector holds every write for a confirmation the session cannot show, a person
applies the file from the dashboard's SQL editor (APPLYING.md §4 c). On 2026-10-23 that path delivered 0765 with
Windows line endings, and its first anchor matched nothing (the transaction rolled back, nothing changed); and the editor
appends a line of its own after the file's COMMIT for each table it sees the script create, which on a temporary table
fails with a red error after the work is saved. This wraps the file so that what runs is the file, or nothing:

  - the file's text goes inside one dollar-quoted string, so it reaches the database whatever the editor does to the
    lines around it, and the editor's scan for created tables, which blanks dollar-quoted text first (Supabase Studio,
    apps/studio/lib/sql-event-parser.ts, read 2026-10-23 at
    https://github.com/supabase/supabase/blob/master/apps/studio/lib/sql-event-parser.ts), sees none;
  - every carriage return is removed before it runs, so the engine gets the file's own line endings;
  - the text's md5 is checked against the file's before anything runs, so a paste changed in any other way is refused
    whole, with nothing changed;
  - it runs as one transaction: the file's own BEGIN; and COMMIT; lines are taken out and the paste carries one pair,
    around a single EXECUTE of the rest of the file, header comments and all.

The md5 checked is that of the file with its top-level `BEGIN;` and `COMMIT;` lines removed (printed with -v).

Usage:  python3 scripts/editor_paste.py db/migrations/NNNN_name.sql [MORE.sql ...] [--then [NNNN=]STATEMENTS.sql]
                                       [-o OUT.sql] [-v]
        Several files make one paste, each its own transaction, in the order given; the first that fails stops the
        rest, and those before it stay committed. --then appends statements (a dial switched on at the twin depot, say)
        after file NNNN's COMMIT (NNNN= may be left out when there is one file), in their own transaction, so they run
        only once that file has committed. They must open with a `BEGIN;` line and end with a `COMMIT;` line.
Exit 1: the file is not one top-level `BEGIN;` ... `COMMIT;` with only comments outside it, it already holds a
        carriage return, or it holds one of the wrapper's dollar-quote tags.
Never contacts the database.
"""
import argparse
import hashlib
import pathlib
import sys

OUTER = "$ottoq_editor_paste$"
INNER = "$ottoq_file_text$"


class NotWrappable(Exception):
    pass


def _outside_is_comments(lines):
    return all(not ln.strip() or ln.lstrip().startswith("--") for ln in lines)


def body_of(text, name="file"):
    """The file's text with its one top-level BEGIN; and COMMIT; lines removed."""
    if "\r" in text:
        raise NotWrappable(f"{name}: holds a carriage return; save it with bare newlines first")
    for tag in (OUTER, INNER):
        if tag in text:
            raise NotWrappable(f"{name}: holds the wrapper's own tag {tag}")
    lines = text.split("\n")
    begins = [i for i, ln in enumerate(lines) if ln == "BEGIN;"]
    commits = [i for i, ln in enumerate(lines) if ln == "COMMIT;"]
    if len(begins) != 1 or len(commits) != 1 or begins[0] > commits[0]:
        raise NotWrappable(f"{name}: wants exactly one top-level `BEGIN;` line before exactly one `COMMIT;` line "
                           f"(found {len(begins)} and {len(commits)})")
    b, c = begins[0], commits[0]
    if not _outside_is_comments(lines[:b]) or not _outside_is_comments(lines[c + 1:]):
        raise NotWrappable(f"{name}: has a statement outside its BEGIN; ... COMMIT;")
    return "\n".join(lines[:b] + lines[b + 1:c] + lines[c + 1:])


def paste_for(path, then_text=None):
    """(paste text, md5 of the file's body, md5 of the file) for one migration file."""
    path = pathlib.Path(path)
    text = path.read_bytes().decode("utf-8")   # not read_text: it would turn CRLF into LF unseen
    body = body_of(text, path.name)
    num = path.name.split("_", 1)[0]
    body_md5 = hashlib.md5(body.encode("utf-8")).hexdigest()
    file_md5 = hashlib.md5(text.encode("utf-8")).hexdigest()
    out = [
        f"-- {path.name}, for the Supabase SQL editor (scripts/editor_paste.py; the file's md5 {file_md5}).",
        "-- The file runs whole, in one transaction, exactly as written: Windows line endings are removed, and a paste",
        f"-- that arrives changed in any other way is refused before anything runs (md5 {body_md5}).",
        "BEGIN;",
        f"DO {OUTER}",
        "DECLARE",
        f"  v_sql text := substr(replace({INNER}",
        f"{body}{INNER}, chr(13), ''), 2);",
        "BEGIN",
        f"  IF md5(v_sql) IS DISTINCT FROM '{body_md5}' THEN",
        f"    RAISE EXCEPTION '{num}: the pasted text is not the file as written (md5 %, not {body_md5}); nothing was "
        "changed', md5(v_sql);",
        "  END IF;",
        "  EXECUTE v_sql;",
        f"END {OUTER};",
        "COMMIT;",
    ]
    if then_text is not None:
        if "\r" in then_text:
            raise NotWrappable("--then: holds a carriage return")
        t = then_text.strip("\n").split("\n")
        firsts = [ln for ln in t if ln.strip() and not ln.lstrip().startswith("--")]
        if not firsts or firsts[0] != "BEGIN;" or firsts[-1] != "COMMIT;":
            raise NotWrappable("--then: must open with a `BEGIN;` line and end with a `COMMIT;` line")
        out += ["", "-- Then, in its own transaction, so it runs only once the file above has committed:"] + t
    return "\n".join(out) + "\n", body_md5, file_md5


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("migrations", nargs="+")
    ap.add_argument("--then", dest="then", action="append", default=[], metavar="[NNNN=]STATEMENTS.sql")
    ap.add_argument("-o", dest="out")
    ap.add_argument("-v", action="store_true", help="print the md5s to stderr")
    a = ap.parse_args(argv)
    nums = [pathlib.Path(m).name.split("_", 1)[0] for m in a.migrations]
    then = {}
    for t in a.then:
        key, _, path = t.rpartition("=")
        if not key and len(nums) == 1:
            key = nums[0]
        if key not in nums:
            print(f"editor_paste: --then {t}: name the file it follows (NNNN=) from {', '.join(nums)}", file=sys.stderr)
            return 1
        then[key] = pathlib.Path(path).read_bytes().decode("utf-8")
    parts = []
    try:
        for m, n in zip(a.migrations, nums):
            text, body_md5, file_md5 = paste_for(m, then.get(n))
            parts.append(text)
            if a.v:
                print(f"{n}: file md5 {file_md5}  body md5 {body_md5}  paste md5 "
                      f"{hashlib.md5(text.encode()).hexdigest()}", file=sys.stderr)
    except NotWrappable as e:
        print(f"editor_paste: {e}", file=sys.stderr)
        return 1
    text = "\n".join(parts)
    if a.out:
        pathlib.Path(a.out).write_text(text, encoding="utf-8")
    else:
        sys.stdout.write(text)
    if a.v and len(parts) > 1:
        print(f"all: paste md5 {hashlib.md5(text.encode()).hexdigest()}  {len(text.encode())} bytes", file=sys.stderr)
    return 0


if __name__ == "__main__":
    sys.exit(main())
