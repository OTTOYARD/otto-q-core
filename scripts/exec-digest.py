#!/usr/bin/env python3
"""exec-digest.py -- the executable half of a migration, digested.

APPLYING.md step 4 permits condensing a long header at the apply step ONLY if the
executable SQL is proven identical by digest (the 0224 precedent). This makes that
proof one command instead of a manual argument.

Comment-only lines (first non-space chars are --) are removed; every other line is
kept verbatim. Trailing comments are deliberately NOT stripped: `--` can appear
inside a string literal, and a stripper that cannot tell the difference would
silently alter executable SQL, which is the exact failure this tool exists to
prevent. Whitespace runs collapse to one space so reindentation is not a deviation.

  THE TRAP THIS TOOL REFUSES TO WALK INTO, found while applying 0251.
  A comment-only line inside a dollar-quoted FUNCTION or PROCEDURE body is not a
  comment on the migration -- it is part of a body that gets STORED. Strip it and
  the database holds a body that differs from the committed file, which is exactly
  the file-vs-database drift G18 exists to prevent, and scripts/check-drift.sql
  would be right to flag it. 0251 has 8 such lines inside a $procedure$ body.
  So: --check reports them and exits 2. Such a file must be submitted WHOLE.
  ($$ DO blocks are exempt -- they execute once and are never stored.)

usage:
  exec-digest.py FILE [FILE2]   digest each; with two, say whether they match
  exec-digest.py --check FILE   refuse files whose stored bodies carry comments
"""
import hashlib, re, sys

STORED_TAGS = ('$function$', '$procedure$', '$body$')


def bodies(text):
    """(start, end, tag) for each dollar-quoted region, outermost-first."""
    regions, depth = [], {}
    for m in re.finditer(r'\$[A-Za-z_]*\$', text):
        t = m.group(0)
        depth[t] = depth.get(t, 0) + 1
        if depth[t] % 2 == 1:
            regions.append([m.end(), None, t])
        else:
            for r in reversed(regions):
                if r[2] == t and r[1] is None:
                    r[1] = m.start()
                    break
    return [(a, b, t) for a, b, t in regions if b is not None]


def stored_body_comments(text):
    """Comment-only lines that live inside a body the database will STORE."""
    spans = [(a, b, t) for a, b, t in bodies(text) if t in STORED_TAGS]
    hits = []
    for m in re.finditer(r'(?m)^[ \t]*--.*$', text):
        for a, b, t in spans:
            if a <= m.start() < b:
                hits.append((text[:m.start()].count('\n') + 1, t, m.group(0).strip()))
                break
    return hits


def digest(text):
    kept = [ln for ln in text.splitlines() if not ln.lstrip().startswith('--')]
    norm = re.sub(r'\s+', ' ', ' '.join(kept)).strip()
    return hashlib.md5(norm.encode()).hexdigest(), len(norm)


def read(p):
    return sys.stdin.read() if p == '-' else open(p).read()


if __name__ == '__main__':
    args = sys.argv[1:]
    if not args:
        sys.exit(__doc__)

    if args[0] == '--check':
        bad = 0
        for p in args[1:]:
            hits = stored_body_comments(read(p))
            if hits:
                bad = 1
                print(f'UNSAFE TO CONDENSE: {p}')
                print(f'  {len(hits)} comment-only line(s) inside a stored body '
                      f'-- submit this file WHOLE, unedited:')
                for ln, tag, txt in hits[:10]:
                    print(f'    line {ln} in {tag}: {txt[:72]}')
            else:
                print(f'safe to condense: {p} (no comments inside stored bodies)')
        sys.exit(2 if bad else 0)

    out = []
    for p in args:
        h, n = digest(read(p))
        out.append((p, h, n))
        print(f'{h}  {n:>6} chars  {p}')
    if len(out) == 2:
        same = out[0][1] == out[1][1]
        print(('MATCH' if same else 'DIFFER') + ': executable SQL is '
              + ('identical' if same else 'NOT identical'))
        sys.exit(0 if same else 1)
