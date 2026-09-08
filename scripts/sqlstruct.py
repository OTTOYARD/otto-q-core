"""Segment PostgreSQL text into code / comment / literal regions.

WHY THIS EXISTS
---------------
`FINDINGS.md` G12 records a file-only lint that was tried and **rejected**:
flag `LIMIT 1` with no `ORDER BY` in a migration's own SQL. On `0220` all five
hits were the string ``'LIMIT 1'`` inside literals and error messages, and the
entry concludes:

    "telling code from literal here needs a real plpgsql parser because the
     bodies are dollar-quoted. A noisy gate gets disabled, so the answer is the
     database, not a regex."

The first half of that is right and the second half is too strong. A *parser* is
not needed to tell code from literal — a **tokenizer** is, and a tokenizer is a
hundred lines. What cannot be done without one is exactly what was attempted:
regex over raw file text.

So this module does the one thing the rejected lint lacked, and nothing more. It
does not understand SQL grammar, statements, or plpgsql. It knows where the
literals are.

WHAT IT DOES NOT SOLVE, stated up front so it is not oversold
-------------------------------------------------------------
None of the three defects found in the 2026-09-08 apply window would have been
caught by this, or by any file-only check, or by running the SQL against an
empty cluster in CI:

  * 0225's P3 was dry-run and passed — against the wrong recert floor. Needs the
    live catalog AND live data.
  * 0226's A1 asserted the wrong property. Needs the live lineage table.
  * 0225's A2 contradicted its own A5. Needs reading comprehension.

They were caught by `scripts/APPLYING.md` step 3b(ii) — dry-running each
precondition against the state its predecessors will have created. That is a
process, not a gate. This module is for the *other* class: transcription and
splice damage, which is real (0225 was spliced five times by hand today and its
dollar-quote balance was verified by eye) and which a machine should check.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterator, Literal

Kind = Literal["code", "line_comment", "block_comment", "string", "ident", "dollar"]

_DOLLAR_OPEN = re.compile(r"\$([A-Za-z_][A-Za-z0-9_]*)?\$")


@dataclass(frozen=True)
class Region:
    kind: Kind
    start: int
    end: int          # exclusive
    text: str
    tag: str | None = None   # dollar-quote tag, without the $ delimiters


class UnterminatedRegion(ValueError):
    """A string, comment or dollar-quoted body that never closes."""


def segment(sql: str) -> list[Region]:
    """Split `sql` into non-overlapping regions covering the whole string.

    Handles, because PostgreSQL does:
      * ``--`` line comments
      * ``/* */`` block comments, which **nest** in PostgreSQL
      * ``'...'`` strings with ``''`` as the escape
      * ``E'...'`` strings, where a backslash escapes the next character
      * ``"..."`` quoted identifiers with ``""`` as the escape
      * ``$tag$...$tag$`` dollar quotes, terminated only by their own tag
    """
    out: list[Region] = []
    i, n = 0, len(sql)
    code_start = 0

    def flush_code(upto: int) -> None:
        if upto > code_start:
            out.append(Region("code", code_start, upto, sql[code_start:upto]))

    while i < n:
        ch = sql[i]

        # -- line comment
        if ch == "-" and sql.startswith("--", i):
            flush_code(i)
            j = sql.find("\n", i)
            j = n if j == -1 else j
            out.append(Region("line_comment", i, j, sql[i:j]))
            i = code_start = j
            continue

        # /* block comment */, nesting
        if ch == "/" and sql.startswith("/*", i):
            flush_code(i)
            depth, j = 1, i + 2
            while j < n and depth:
                if sql.startswith("/*", j):
                    depth += 1
                    j += 2
                elif sql.startswith("*/", j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            if depth:
                raise UnterminatedRegion(f"block comment opened at offset {i} never closes")
            out.append(Region("block_comment", i, j, sql[i:j]))
            i = code_start = j
            continue

        # E'...' — backslash escapes
        if ch in "Ee" and i + 1 < n and sql[i + 1] == "'":
            flush_code(i)
            j = i + 2
            while j < n:
                if sql[j] == "\\":
                    j += 2
                elif sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                    else:
                        j += 1
                        break
                else:
                    j += 1
            else:
                raise UnterminatedRegion(f"E-string opened at offset {i} never closes")
            out.append(Region("string", i, j, sql[i:j]))
            i = code_start = j
            continue

        # '...' — '' escapes
        if ch == "'":
            flush_code(i)
            j = i + 1
            while j < n:
                if sql[j] == "'":
                    if j + 1 < n and sql[j + 1] == "'":
                        j += 2
                    else:
                        j += 1
                        break
                else:
                    j += 1
            else:
                raise UnterminatedRegion(f"string opened at offset {i} never closes")
            out.append(Region("string", i, j, sql[i:j]))
            i = code_start = j
            continue

        # "..." — quoted identifier, "" escapes
        if ch == '"':
            flush_code(i)
            j = i + 1
            while j < n:
                if sql[j] == '"':
                    if j + 1 < n and sql[j + 1] == '"':
                        j += 2
                    else:
                        j += 1
                        break
                else:
                    j += 1
            else:
                raise UnterminatedRegion(f"quoted identifier at offset {i} never closes")
            out.append(Region("ident", i, j, sql[i:j]))
            i = code_start = j
            continue

        # $tag$ ... $tag$
        if ch == "$":
            m = _DOLLAR_OPEN.match(sql, i)
            if m:
                tag = m.group(1) or ""
                closer = m.group(0)
                j = sql.find(closer, m.end())
                if j == -1:
                    raise UnterminatedRegion(
                        f"dollar quote {closer} opened at offset {i} never closes"
                    )
                flush_code(i)
                end = j + len(closer)
                out.append(Region("dollar", i, end, sql[i:end], tag))
                i = code_start = end
                continue

        i += 1

    flush_code(n)
    return out



def _is_sql(region: Region, parent: str) -> bool:
    """Does this dollar-quoted body tokenize as SQL?

    A function body does; a dollar-quoted string literal carrying an unbalanced
    apostrophe (0221) does not. Used to decide whether to recurse, so the answer
    only ever has to be safe: a body wrongly treated as a literal is blanked and
    a lint sees less, which is a miss; a literal wrongly treated as SQL raises
    on valid input, which is a false alarm on a correct file. Misses are the
    cheaper error here.
    """
    tag_len = len(region.tag or "") + 2
    body = parent[region.start + tag_len : region.end - tag_len]
    try:
        segment(body)
    except UnterminatedRegion:
        return False
    return True


def code_only(sql: str, *, recurse_dollar: bool = True) -> str:
    """Return `sql` with every comment and literal blanked to spaces.

    Offsets and line numbers are preserved exactly, so a match found in the
    result can be reported against the original file without translation.

    `recurse_dollar=True` re-segments the *body* of each dollar-quoted region,
    which is what makes this usable on this repo: every function body here is
    dollar-quoted, so treating dollar quotes as opaque literals would blank the
    very code a lint wants to read. The delimiters themselves are blanked; the
    body is processed as SQL in its own right.

    **But a dollar-quoted region is not always SQL**, and that is not a corner
    case — `db/migrations/0221` writes

        IF position($$COALESCE(b.sim_run_id,'00000000$$ in v_flat) <> 0

    which is a *string literal* carrying an unbalanced apostrophe, and is
    perfectly valid PostgreSQL: dollar quoting exists so that apostrophes need
    no escaping. Nothing syntactic distinguishes a function body from a string
    that happens to be dollar-quoted.

    So the rule is fail-safe rather than clever: **recurse only if the body
    tokenizes; if it does not, it is not SQL, and it is treated as an opaque
    literal.** The first version of this function recursed unconditionally and
    raised on 0221 — a guard firing on correct input, which is the exact failure
    0221's own comment three lines above the offending literal warns about.
    """
    buf = list(sql)

    def blank(a: int, b: int) -> None:
        for k in range(a, b):
            if buf[k] != "\n":
                buf[k] = " "

    def walk(text: str, base: int) -> None:
        for r in segment(text):
            if r.kind == "code":
                continue
            if r.kind == "dollar" and recurse_dollar and _is_sql(r, text):
                tag_len = len(r.tag or "") + 2
                blank(base + r.start, base + r.start + tag_len)
                blank(base + r.end - tag_len, base + r.end)
                walk(text[r.start + tag_len : r.end - tag_len], base + r.start + tag_len)
            else:
                blank(base + r.start, base + r.end)

    walk(sql, 0)
    return "".join(buf)


def dollar_tag_balance(sql: str) -> dict[str, int]:
    """Count dollar-quote delimiters per tag, ignoring comments and strings.

    A balanced file has an even count for every tag. This is the check that was
    done by eye on 0225 after five hand splices; doing it by eye is how a
    seventh splice eventually ships broken.
    """
    counts: dict[str, int] = {}

    def walk(text: str) -> None:
        for r in segment(text):
            if r.kind == "dollar":
                tag = r.tag or ""
                counts[tag] = counts.get(tag, 0) + 2
                if _is_sql(r, text):
                    tag_len = len(tag) + 2
                    walk(text[r.start + tag_len : r.end - tag_len])

    walk(sql)
    return counts


def iter_code_lines(sql: str) -> Iterator[tuple[int, str]]:
    """Yield (1-based line number, code-only text) for every line."""
    for n, line in enumerate(code_only(sql).splitlines(), start=1):
        yield n, line
