#!/usr/bin/env python3
"""Diff two pg_stat_user_functions captures.

Both inputs are files containing a fenced block of `schema|function|calls|self_ms`
lines (the format `db/evidence/*_fn_baseline.md` uses). Lines outside a fenced
block are ignored, so a capture can carry its own prose.

    scripts/fn-delta.py BEFORE.md AFTER.md [--top N] [--by calls|self]

Why a script and not a SQL join: the counters live in a view that is reset by
`pg_stat_reset()` and by nothing else, and the two captures are taken minutes
apart by different sessions. Holding both as committed text is what makes the
delta auditable after the fact -- `db/checks/0141` could not name a caller
because `r27_g`'s baseline was a hand-picked fourteen rows.

A function present in AFTER but absent from BEFORE is reported with its full
AFTER value and marked NEW; that is the correct delta, since absence from the
view means zero calls. A function whose counter went DOWN is reported as a
RESET and is a defect in the capture, not a measurement -- it means something
called `pg_stat_reset()` between the two, and the whole delta is void.

OVERLOADS. `pg_stat_user_functions` is keyed by `funcid`, so two overloads of
one name are two rows. `db/evidence/r28_g_fn_baseline.md` has two for
`public.ottoq_build_decision_frame` (48 calls and 1). Neither capture records
argument types, so this script SUMS rows sharing a schema and name and says so.
Summing is the right aggregation for "how many calls did this name receive";
what is lost is per-overload attribution, and that loss is named in the output
rather than hidden. A future capture should select `funcid` too.
"""
import argparse
import re
import sys

ROW = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)\|([^|]+)\|(\d+)\|([0-9.]+)$")


def parse(path):
    """Return ({(schema, funcname): (calls, self_ms)}, {name: n_overload_rows}).

    Rows sharing a schema and name are summed -- see OVERLOADS in the module
    docstring. The second return value names every key that took more than one
    row, so the caller can mark the aggregation instead of burying it.
    """
    rows = {}
    counts = {}
    in_fence = False
    with open(path, encoding="utf-8") as fh:
        for raw in fh:
            line = raw.rstrip("\n")
            if line.startswith("```"):
                in_fence = not in_fence
                continue
            if not in_fence or not line.strip():
                continue
            m = ROW.match(line.strip())
            if not m:
                continue
            key = (m.group(1), m.group(2))
            calls, self_ms = int(m.group(3)), float(m.group(4))
            prev_calls, prev_self = rows.get(key, (0, 0.0))
            rows[key] = (prev_calls + calls, prev_self + self_ms)
            counts[key] = counts.get(key, 0) + 1
    if not rows:
        sys.exit(f"{path}: no `schema|function|calls|self_ms` rows found in any fenced block")
    return rows, {k: v for k, v in counts.items() if v > 1}


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("before")
    ap.add_argument("after")
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--by", choices=("calls", "self"), default="calls")
    args = ap.parse_args()

    before, b_over = parse(args.before)
    after, a_over = parse(args.after)

    overloaded = set(b_over) | set(a_over)
    if overloaded:
        print(f"Note: {len(overloaded)} name(s) had multiple `funcid` rows (overloads) "
              "and were SUMMED.")
        print("      Per-overload attribution is not recoverable -- neither capture "
              "records argument types.")
        for schema, fn in sorted(overloaded):
            print(f"   {schema}.{fn}: "
                  f"{b_over.get((schema, fn), 1)} row(s) before, "
                  f"{a_over.get((schema, fn), 1)} after")
        print()


    resets = []
    deltas = []
    for key, (calls, self_ms) in after.items():
        b_calls, b_self = before.get(key, (0, 0.0))
        if calls < b_calls or self_ms < b_self - 0.05:
            resets.append((key, b_calls, calls))
            continue
        d_calls, d_self = calls - b_calls, self_ms - b_self
        if d_calls == 0 and d_self < 0.05:
            continue
        deltas.append((key, d_calls, d_self, key not in before))

    if resets:
        print("!! COUNTERS WENT DOWN -- pg_stat_reset() ran between the captures.")
        print("!! The delta below is VOID. Re-capture the baseline and re-run the pair.")
        for (schema, fn), b, a in resets:
            print(f"   {schema}.{fn}: {b} -> {a}")
        print()

    gone = sorted(k for k in before if k not in after)
    if gone:
        print(f"Note: {len(gone)} function(s) in BEFORE are absent from AFTER "
              "(dropped, or renamed):")
        for schema, fn in gone[:10]:
            print(f"   {schema}.{fn}")
        print()

    deltas.sort(key=lambda r: (r[1] if args.by == "calls" else r[2]), reverse=True)

    tot_calls = sum(r[1] for r in deltas)
    tot_self = sum(r[2] for r in deltas)
    print(f"{len(deltas)} function(s) moved. "
          f"Total {tot_calls:,} calls, {tot_self:,.1f} ms self time.")
    print()
    print(f"| {'function':<44} | {'Δ calls':>12} | {'Δ self ms':>11} | {'% calls':>7} |")
    print(f"|{'-'*46}|{'-'*14}|{'-'*13}|{'-'*9}|")
    for (schema, fn), d_calls, d_self, is_new in deltas[: args.top]:
        name = f"{schema}.{fn}" + (" NEW" if is_new else "")
        pct = (100.0 * d_calls / tot_calls) if tot_calls else 0.0
        print(f"| {name:<44} | {d_calls:>12,} | {d_self:>11,.1f} | {pct:>6.2f}% |")
    if len(deltas) > args.top:
        print(f"| ... {len(deltas) - args.top} more row(s) not shown "
              f"{'':<21} | {'':>12} | {'':>11} | {'':>7} |")

    return 1 if resets else 0


if __name__ == "__main__":
    sys.exit(main())
