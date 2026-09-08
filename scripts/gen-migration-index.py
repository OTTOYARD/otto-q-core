#!/usr/bin/env python3
"""
gen-migration-index.py — refresh the INDEX block at the end of MIGRATION_LOG.md.

WHY THIS EXISTS. MIGRATION_LOG.md's narrative rows stop at 0133 (2026-08-31).
Eighty-two migrations after it went unlogged, including the whole G2..G17
series, so there was no single place that said what is in the engine. Writing
eighty-two narrative rows after the fact would mean inventing prose about work
whose reasoning already lives in the files. This does the honest thing instead:
it GENERATES an index from the files themselves — version, title line, and
whether the file records having been applied — and says plainly that it is an
index, not a log.

The narrative rows above the marker are hand-written and are never touched.

Usage:  python3 scripts/gen-migration-index.py
Safe:   rewrites only the block between the markers in MIGRATION_LOG.md.
        Never contacts the database.
Exit 1: a migration file has no version header (run scripts/gen-drift-sql.sh
        first — it reports the same thing and is the canonical complaint).
"""
import pathlib, re, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
MIG  = ROOT / "db" / "migrations"
LOG  = ROOT / "MIGRATION_LOG.md"

BEGIN = "<!-- >>> BEGIN GENERATED INDEX — do not edit by hand; run scripts/gen-migration-index.py -->"
END   = "<!-- <<< END GENERATED INDEX -->"

# The narrative rows cover these; the index starts after the last one.
INDEX_FROM = "0134"

TITLE_DASH   = re.compile(r"^--\s*(\d{3,4}\w?)\s*[—–-]+\s*(\S.*?)\s*$")
TITLE_BANNER = re.compile(r"^--\s*(\d{3,4}\w?)\s\s+(\S.*?)\s*$")

def title_of(text: str) -> str:
    lines = text.split("\n")[:40]
    for ln in lines:
        s = ln.rstrip()
        if s.startswith("-- migration-") or set(s.strip("- =")) <= {""}:
            continue
        m = TITLE_DASH.match(s) or TITLE_BANNER.match(s)
        if m and not m.group(2).startswith("="):
            t = m.group(2)
            # a banner title can wrap onto the next comment line
            return t.rstrip(".")
    # fall back to the first non-empty comment that is not scaffolding
    for ln in lines:
        s = ln.strip()
        if s.startswith("--") and len(s) > 6 and not s.startswith("-- migration-") \
           and set(s.strip("- =")) != set():
            return s.lstrip("- ").rstrip(".")
    return "(no title line in the file)"

def main() -> int:
    rows, missing = [], []
    for f in sorted(MIG.glob("*.sql")):
        m = re.match(r"^(\d{4})(\w?)_", f.name)
        if not m:
            continue
        num = m.group(1) + m.group(2)
        if num < INDEX_FROM:
            continue
        text = f.read_text(errors="replace")
        first = text.split("\n", 1)[0]
        if not first.startswith("-- migration-version:"):
            missing.append(f.name)
            continue
        ver = first.split(":", 1)[1].strip()
        # Derived from evidence, not from grepping for the word "APPLIED".
        # A real timestamp version means the ledger recorded the apply; that is
        # stronger than anything the file can say about itself.
        if re.fullmatch(r"\d{12,14}", ver):
            applied = "yes — ledger"
        elif ver == "APPLIED-NO-LEDGER-ROW":
            applied = "yes — file only"
        elif ver == "UNVERIFIED-NO-LEDGER-ROW":
            applied = "**unknown**"
        elif ver == "PENDING":
            applied = "no — pending"
        else:
            applied = "?"
        rows.append((num, ver, title_of(text), applied, f.name))

    if missing:
        print("FATAL: these migration files have no version header:", file=sys.stderr)
        for n in missing:
            print("  " + n, file=sys.stderr)
        print("Run scripts/gen-drift-sql.sh — it is the canonical complaint.", file=sys.stderr)
        return 1

    out = [BEGIN, "",
           f"## Index, {INDEX_FROM}–{rows[-1][0]} — GENERATED, not a log",
           "",
           "The rows above this marker are hand-written narrative and stop at 0133 (2026-08-31).",
           f"Everything from {INDEX_FROM} on went unlogged at the time. Rather than invent prose after the",
           "fact about work whose reasoning already lives in the migration files, this block is",
           "generated from those files by `scripts/gen-migration-index.py`. It answers *what is in the",
           "engine and where to read about it*; it does not pretend to answer *what was verified*, which",
           "is what the narrative column above is for. Each file's own header and APPLIED footer carry",
           "that.",
           "",
           "`applied` is `yes` when the file itself records having been applied, `—` when it says nothing",
           "either way. A version of `APPLIED-NO-LEDGER-ROW` or `UNVERIFIED-NO-LEDGER-ROW` means there is",
           "no `supabase_migrations` row for the file — see task G18 and Section E of",
           "`scripts/check-drift.sql`.",
           "",
           "| # | version | applied | what it does |",
           "|---|---|---|---|"]
    for num, ver, title, applied, fname in rows:
        t = title.replace("|", "\\|")
        out.append(f"| [{num}](db/migrations/{fname}) | `{ver}` | {applied} | {t} |")
    out += ["", f"{len(rows)} migrations indexed.", "", END]

    log = LOG.read_text()
    block = "\n".join(out)
    if BEGIN in log and END in log:
        pre  = log.split(BEGIN)[0]
        post = log.split(END, 1)[1]
        log = pre + block + post
    else:
        log = log.rstrip("\n") + "\n\n" + block + "\n"
    LOG.write_text(log)
    print(f"MIGRATION_LOG.md index refreshed: {len(rows)} migrations, {INDEX_FROM}–{rows[-1][0]}.")
    return 0

if __name__ == "__main__":
    sys.exit(main())
