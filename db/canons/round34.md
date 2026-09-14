# Round 34 — clean, and the first honest streak of the night

**Six pairs, flagship depot, 2026-09-09 10:10–11:26 UTC (5:10–6:26 AM CT).**
The first round above the `09:46:27.088143` floor that `0246` set when it
repaired `0244`.

## The prediction, committed before the evidence

Written into the round-34 check-in at 09:52 UTC, before any pair fired:

> six of six PASS. `fp` moves from round 33's values on every column … `endst` now
> AGREES between arms on every column, which is the whole point of `0246` … and the
> engine atoms `h_evt` / `h_dec` / `h_bkg` / `h_nrg` / `h_rule` / `h_sdr` stay IDENTICAL to
> **ROUND 32** — name round 32 specifically, because round 33's arms disagreed on
> `endst` and round 33 certified nothing. **If any engine atom moved from round 32,
> `0246` did more than scrub identifiers and that is a real finding.**

## Verdicts

| fired | column | status | atoms differing between arms |
|---|---|---|---|
| 10:10 | `busy_day/314159/12t` | passed | none |
| 10:24 | `busy_day/171717/12t` | passed | none |
| 10:38 | `normal_day/171717/12t` | passed | none |
| 10:52 | `busy_day/424242/12t` | passed | none |
| 11:06 | `busy_day/171717/24t` | passed | none |
| 11:26 | `busy_day/424242/24t` | passed | none |

**Six of six passed. Zero of fourteen atoms differ between arms — `endst` included.**

## Against round 32 (named runs, not a window)

| column | `fp` vs r32 | engine atoms vs r32 |
|---|---|---|
| `busy_day/314159/12t` | moved | **identical** |
| `busy_day/171717/12t` | moved | **identical** |
| `normal_day/171717/12t` | moved | **identical** |
| `busy_day/424242/12t` | moved | **identical** |
| `busy_day/171717/24t` | moved | **identical** |
| `busy_day/424242/24t` | moved | **identical** |

`fp` moved everywhere, because `0246` scrubs identifiers out of the config term
and that changes the boot hash too. `h_evt`, `h_dec`, `h_bkg`, `h_nrg`, `h_rule`
and `h_sdr` are byte-identical to round 32 on all six columns.

**The prediction is confirmed on every point, and the alternative it named — "if
any engine atom moved from round 32, `0246` did more than scrub identifiers" —
did not occur.** Three migrations have now rewritten the fleet reset, the world
fingerprint and the end-state fingerprint, and the engine's decisions, events,
calendar, energy commands, rule evaluations and settlement records have not moved
once.

The seed-keyed `fp` property held again: three distinct `fp` values across six
columns, one per seed, exactly as round 32 first showed.

## Floor and streak

```
recert floor                       2026-09-09 09:46:27.088143   unmoved
forces_recert entries since 0246   0
```

Six columns above the floor at **streak 1**. `0193`'s bar is two consecutive
agreeing rounds, so **round 35 is scheduled (12:10–13:26 UTC)** and these are not
canons until it agrees with this one.

## What the night cost, counted honestly

Four rounds, three recerts:

| round | outcome | why |
|---|---|---|
| 31 | clean | the last round before any of this |
| 32 | clean | recert forced by `0243` — a real fix for a real defect (G43) |
| 33 | **failed 6/6** | recert forced by `0244`/`0245`; `0244` was wrong |
| 34 | clean | recert forced by `0246`, which repaired `0244` |

**Two of the three recerts were bought by one mistake of mine**: `0244` added a
new component to `endst`, an atom that was already ENFORCED, without the MEASURED
round `CLAUDE.md` 2.9a requires. Round 33 caught it within three hours. Had the
doctrine been followed, round 33 would have passed and reported a measured
disagreement, and the night would have cost one recert instead of three.

That is the case for the rule, written from the wrong side of it.
