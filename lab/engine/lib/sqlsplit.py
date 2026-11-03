"""Split a PostgreSQL script into top-level statements.

Used only for the baseline files (db/baseline/tables.sql, rls_policies.sql,
cron_jobs.sql). Migrations are NOT split: they are run whole through psql,
which is the reference implementation of psql-file semantics (meta-commands,
\\set, and so on).

The lexer knows the five places a ';' does not end a statement:
  '...'   standard string ('' escapes a quote; backslash is literal,
          standard_conforming_strings = on, as on the engine)
  E'...'  escape string (backslash escapes)
  "..."   quoted identifier ("" escapes a quote)
  $tag$ ... $tag$   dollar quote (tag empty or an identifier; $1 is a
          parameter, not a quote)
  -- ... end of line, and /* ... */ (nested, as PostgreSQL nests them)
"""
import re

_TAG = re.compile(r"\$([A-Za-z_\x80-￿][A-Za-z0-9_\x80-￿]*)?\$")


def split(sql: str):
    """Return [(statement_text, first_line_number)], comments kept inside."""
    out = []
    i, n = 0, len(sql)
    code_start = 0
    line = 1
    start_line = 1
    seen_code = False  # has the current statement any non-comment text?

    def emit(end):
        nonlocal seen_code
        text = sql[code_start:end].strip()
        if seen_code and text:
            out.append((text, start_line))
        seen_code = False

    while i < n:
        c = sql[i]
        if c == "\n":
            line += 1
            i += 1
            continue
        if c in " \t\r\f":
            i += 1
            continue
        if c == "-" and sql.startswith("--", i):
            j = sql.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and sql.startswith("/*", i):
            depth, i = 1, i + 2
            while i < n and depth:
                if sql.startswith("/*", i):
                    depth += 1
                    i += 2
                elif sql.startswith("*/", i):
                    depth -= 1
                    i += 2
                else:
                    if sql[i] == "\n":
                        line += 1
                    i += 1
            continue
        if not seen_code:
            # a statement starts at its first character that is not blank or comment
            seen_code = True
            start_line = line
            code_start = i
        if c == ";":
            emit(i + 1)
            i += 1
            continue
        if c in "eE" and i + 1 < n and sql[i + 1] == "'" and (i == 0 or not (sql[i - 1].isalnum() or sql[i - 1] == "_")):
            i += 2
            while i < n:
                if sql[i] == "\\":
                    i += 2
                    continue
                if sql[i] == "'":
                    if i + 1 < n and sql[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                if sql[i] == "\n":
                    line += 1
                i += 1
            continue
        if c == "'":
            i += 1
            while i < n:
                if sql[i] == "'":
                    if i + 1 < n and sql[i + 1] == "'":
                        i += 2
                        continue
                    i += 1
                    break
                if sql[i] == "\n":
                    line += 1
                i += 1
            continue
        if c == '"':
            i += 1
            while i < n:
                if sql[i] == '"':
                    if i + 1 < n and sql[i + 1] == '"':
                        i += 2
                        continue
                    i += 1
                    break
                if sql[i] == "\n":
                    line += 1
                i += 1
            continue
        if c == "$":
            prev = sql[i - 1] if i else " "
            m = _TAG.match(sql, i)
            if m and not (prev.isalnum() or prev == "_"):
                tag = m.group(0)
                j = sql.find(tag, m.end())
                if j < 0:
                    j = n - len(tag)
                line += sql.count("\n", i, j + len(tag))
                i = j + len(tag)
                continue
            i += 1
            continue
        i += 1
    emit(n)
    return out


def split_marked(sql: str, marker=re.compile(r"^-- ===== (.+?) =====\s*$", re.M)):
    """Split a pg_get_functiondef() dump on its '-- ===== name =====' markers.

    The baseline function files hold one definition per marker and no ';'
    between definitions, so the generic splitter cannot be used on them.
    Returns [(name, definition_text, first_line_number)].
    """
    marks = list(marker.finditer(sql))
    out = []
    for k, m in enumerate(marks):
        end = marks[k + 1].start() if k + 1 < len(marks) else len(sql)
        body = sql[m.end():end].strip("\n")
        first_line = sql.count("\n", 0, m.end()) + 2
        out.append((m.group(1), body.rstrip() + "\n", first_line))
    return out
