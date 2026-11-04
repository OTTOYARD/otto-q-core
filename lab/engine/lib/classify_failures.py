#!/usr/bin/env python3
"""Sort the build's migration failures by what stopped them (a heuristic over first errors).

  classify_failures.py reports/build_<date>_migrations.tsv

Writes <same prefix>_classified.tsv (one row per file, with a `cause` column) and
prints the counts. Causes, in the order they are tested:

  missing_object      SQLSTATE 42P01/42883/42703/42704/3F000: the file named a table,
                      function, column, type or schema the lab does not have.
  guard_body_lineage  the file's own guard refused because a function body is not the
                      one it was written against (md5 pin, pre-image, anchor count,
                      expected phrase). The lab's lineage has diverged from production's.
  guard_prerequisite  the file's own guard refused because an earlier migration's object
                      is absent ("apply NNNN first", "X does not exist").
  guard_data_premise  the file's own guard asserted something about production's ROWS
                      (a depot, its stalls, rule rows, catalog rows, ledgers, evidence,
                      a cron job id) and the empty lab cannot satisfy it.
  other_<SQLSTATE>    anything else (syntax errors, cardinality, null EXECUTE strings).

This is a reading of error text, not a proof. The per-file first error is in the
output so every classification can be checked by eye.
"""
import collections
import csv
import json
import re
import sys

MISSING_STATES = {"42P01", "42883", "42703", "42704", "3F000"}
LINEAGE = re.compile(
    r"md5|pre-?image|post-image|drift|pinned|\bpin\b|not the body|not the \S+ body|body is \S+ \(|moved under|"
    r"moved from the measured|not stored as patched|anchor|matches \d+ times|not the audited|written against|"
    r"hotfix|changed since it was measured|no longer|not the one certified|is not the start this wraps|"
    r"privileges or settings changed|the grants moved|does not occur exactly once|occurrences, found|"
    r"derive function carrying|discarding PERFORM|does not cover|a wall clock appears|"
    r"fragment does not look like|query-driven FOR loop|lost its \S+ guard|is missing its \S+ blocks|"
    r"target functions in public", re.I)
PREREQ = re.compile(
    r"not found|does not exist|is missing|are missing|is absent|must be applied|apply \S+ first|must land first|"
    r"not applied|has not been applied|missing instrument|patch target is missing|required functions are missing|"
    r"door this file routes to is missing|not both present|found 0 of|overload, found 0|"
    r"reads or writes columns that do not exist|reads columns that do not exist|calls functions that do not exist|"
    r"machinery is missing|expected exactly 1 \S+, found 0|expected all .* found 0|is not 0482", re.I)


def cause(row):
    if row["status"] in ("ok", "ok_bodies_unchecked", "skipped_pending"):
        return row["status"]
    st, err = row["sqlstate"], row["first_error"]
    if st in MISSING_STATES:
        return "missing_object"
    if st.startswith("P0") or st == "22023":
        if LINEAGE.search(err):
            return "guard_body_lineage"
        if PREREQ.search(err):
            return "guard_prerequisite"
        return "guard_data_premise"
    return "other_" + (st or "unknown")


def main():
    src = sys.argv[1]
    rows = list(csv.DictReader(open(src, encoding="utf-8"), delimiter="\t"))
    out = src.replace(".tsv", "_classified.tsv")
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("seq\tfile\tversion\tstatus\tcause\tsqlstate\tfirst_error\n")
        for r in rows:
            fh.write(f"{r['seq']}\t{r['file']}\t{r['version']}\t{r['status']}\t{cause(r)}\t{r['sqlstate']}\t"
                     f"{r['first_error']}\n")
    by = collections.Counter(cause(r) for r in rows)
    by_hdr = collections.defaultdict(collections.Counter)
    for r in rows:
        hdr = "ledger" if re.fullmatch(r"\d{14}", r["version"] or "") else r["version"]
        by_hdr[hdr][cause(r)] += 1
    print(json.dumps({"by_cause": dict(by.most_common()), "by_header": {k: dict(v) for k, v in by_hdr.items()}},
                     indent=1))


if __name__ == "__main__":
    main()
