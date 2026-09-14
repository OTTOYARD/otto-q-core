# Round 32 — the recert 0243 forced

**Six pairs, flagship depot, 2026-09-09 06:20–07:36 UTC (1:20–2:36 AM CT).**
The first round above the recert floor `2026-09-09 06:09:09.360796`, which
`0243` moved when it widened `ottoq.ottoq_world_fingerprint` and taught
`ottoq_tick_invariance_reset_fleet` to clear the robotic-tether family.

## The prediction, committed before the evidence

Written into the round-32 check-in prompt at **06:16 UTC** and revised at
**06:23**, both before any pair had completed (`r32_a` finished ~06:23:30):

> Expect every `fp` to differ from pre-`0243` values (`0243` widened the hash — that
> is why `forces_recert` is TRUE). The NEW `fp` for `busy_day/314159/12t` is
> `14fa5b5dd6d40b8142a5b58fd95bef0a`, measured by C4. `h_evt`
> `9c631343c32cca7a861b17bc5bc8f4b7` and `h_dec` `9abdb4afb2d172f50821158698fd26be`
> should be UNCHANGED for that column — `0243` changed what is hashed at boot and
> what the reset clears, not what the engine does. **If `h_dec` or `h_evt` moved on a
> clean world, `0243` did more than intended: investigate before writing anything down.**

## Verdicts

| fired | column | status | atoms moved |
|---|---|---|---|
| 06:20 | `busy_day/314159/12t` | passed | none |
| 06:34 | `busy_day/171717/12t` | passed | none |
| 06:48 | `normal_day/171717/12t` | passed | none |
| 07:02 | `busy_day/424242/12t` | passed | none |
| 07:16 | `busy_day/171717/24t` | passed | none |
| 07:36 | `busy_day/424242/24t` | passed | none |

**Six of six passed. Zero of fourteen atoms moved on any column.**

## Against round 31, atom by atom

Each round-32 column compared to **round 31's** run of that same column — r31
being the six firings at 03:42, 03:56, 04:10, 04:24, 04:38 and 04:58, the last
clean round before `0243`:

| column | `fp` | `h_evt` | `h_dec` | `h_bkg` | `h_nrg` | `h_rule` | `h_sdr` | `endst` |
|---|---|---|---|---|---|---|---|---|
| `busy_day/314159/12t` | **moved** | same | same | same | same | same | same | same |
| `busy_day/171717/12t` | **moved** | same | same | same | same | same | same | same |
| `normal_day/171717/12t` | **moved** | same | same | same | same | same | same | same |
| `busy_day/424242/12t` | **moved** | same | same | same | same | same | same | same |
| `busy_day/171717/24t` | **moved** | same | same | same | same | same | same | same |
| `busy_day/424242/24t` | **moved** | same | same | same | same | same | same | same |

**Prediction CONFIRMED, on all six columns.** `fp` moved everywhere, because it
now hashes four more columns per vehicle. Nothing else moved anywhere — not the
decisions, not the event stream, not the calendar, not the energy commands, not
the rule evaluations, not the settlement records, not the end state.

`0243` widened the instrument and left the engine alone. That was the claim; this
is the evidence for it, across six columns rather than the one C4 could speak to.

### A property worth noting that nobody predicted

`fp` is now shared across columns that share a seed:

```
314159  ->  14fa5b5dd6d40b8142a5b58fd95bef0a   (12t busy)
171717  ->  d1aac05298de038eb8e1b9c8434a91f5   (12t busy, 12t normal, 24t busy)
424242  ->  439a337fcf556aea5097929f03a2d51e   (12t busy, 24t busy)
```

That is correct and is a small piece of positive evidence for the reset: `fp` is
the *start-of-run* world, and `ottoq_tick_invariance_reset_fleet` is keyed on
(depot, seed, sim_start). Same seed → same starting world, whatever scenario or
horizon follows. If two same-seed columns had produced different `fp`, the reset
would not be seed-deterministic and the whole comparison would be built on sand.

## Floor and streaks

```
recert floor                              2026-09-09 06:09:09.360796   unmoved
forces_recert entries since the floor     0
```

All six columns now sit above the floor with a **streak of 1**. One passing round
is not a canon yet — `0193`'s bar is two consecutive agreeing rounds — and round
33 is scheduled to earn the second.

## The methodology error, again, and caught

Round 31 recorded: *"when comparing against 'the canon', name WHICH run you
mean."* My first round-32 comparison ignored my own rule. I selected r31 and r32
by a **time window** (03:41–07:40) instead of naming the runs, and the window
swallowed the four G43 controls — C1, C2, C3 and C4 all ran on
`busy_day/314159/12t`. The join cross-multiplied: that one column came back
**six times**, some rows showing `h_evt` and `h_dec` "moved", which would have
been reported as `0243` changing engine behaviour.

It was noise from comparing controls against each other. Re-run with the twelve
firing times named explicitly, one run per (round, column), the table above is
what the database actually says.

The lesson is not new, which is the uncomfortable part: **a window is not a
name.** Round 31 wrote that down and I did it anyway one round later. The
difference is that this time the shape of the wrong answer — one column appearing
six times — was visibly impossible, and impossible-looking output is the cheapest
error detector there is. Widening a window to "make sure I catch everything" is
precisely how a comparison stops being a comparison.

## Verdict

Round 32 is **clean**: six of six, zero atoms moved, prediction confirmed, and
`0243` demonstrated across the whole matrix to have changed only what it claimed
to change. The canons above the new floor are recorded with a streak of 1 and
need round 33 to become canons in the sense `0193` requires.
