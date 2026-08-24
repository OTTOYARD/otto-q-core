# The controlled residue experiment — residue does not explain 14 vs 61

**Run 2026-08-24, on the benchmark depot `22222222-…`, with the harness fixed by migrations
0071 + 0072.** This is the experiment that `docs/RUN_ISOLATION_FINDING.md` said was blocked.
It is now unblocked, it has been run, and it answers the question it was designed to answer.

**Verdict: leftover data from prior runs does not change the benchmark score.** Not the
headline number, not throughput, not peak power. The hypothesis that residue explains the
14-vs-61 discrepancy is dead — first on mechanism (PR #76), now on measurement.

---

## Design

Three arms, run back to back, every input pinned identical: **seed 424242, policy `otto_q`,
A/B group `…424266`, 0 fault chargers, 20 ticks (1+7+6+6)**. The only thing that varied was
how much prior-run data sat in the shared tables at the moment each arm armed.

The depot happened to be completely clean when this started — every earlier cert run had been
purged — so arm A got a genuinely empty depot, and each arm then left its own residue for the
next. Each run books exactly 708 stalls, which makes the residue axis exact rather than
approximate.

| arm | run id | stall bookings present at arm | prior runs present |
|---|---|---|---|
| A | `b4aaa44e` | **0** | 0 |
| B | `5313a8f7` | **708** | 1 |
| C | `bd44f721` | **1416** | 2 |

Every step returned the full tick count it was asked for. Under 0071 a short advance now
raises, so "20 ticks" is asserted by the engine rather than assumed by me.

## Result — the score is flat

| metric | A (0 residue) | B (708) | C (1416) |
|---|---|---|---|
| **charge_sessions** | **61** | **61** | **61** |
| trips_completed | 92 | 92 | 92 |
| vehicles_cycled | 92 | 92 | 92 |
| enacted_total | 916 | 916 | 916 |
| energy_peak_kw | 589.30 | 589.30 | 589.30 |
| gate_backlog | 20 | 20 | 20 |
| safety_violations | 1 | 1 | 1 |
| stall bookings written | 708 | 708 | 708 |
| decisions_total | 1296 | 1297 | 1298 |
| vehicles_turned_around | 27 | 27 | 26 |
| fleet_ready_pct | 27.00 | 27.00 | 26.00 |

Across a residue sweep from zero to 1,416 foreign bookings, **the headline score does not move
at all**, and neither does throughput, cycling, enactment, peak kW, backlog or safety.

## What residue *does* do — small, late, and honest about it

Two things move, and they move monotonically with residue, so they are real effects and not
noise:

- `decisions_total` rises by exactly **one per prior run present** — 1296 / 1297 / 1298.
- At the heaviest residue, **one vehicle** ends in a different state (turned-around 27→26,
  ready 27%→26%).

The determinism verdict locates it:

| pair | ticks compared | identical | divergent | first divergence |
|---|---|---|---|---|
| A vs B | 20 | 19 | 1 | sim-min **570** (tick 19) |
| A vs C | 20 | 18 | 2 | sim-min **570** (tick 19) |

So residue perturbs the last one or two ticks of a twenty-tick run and nothing before them.
That is consistent in position with the pre-existing tick-18 divergence recorded in the 0070
addendum, which was found *before* this experiment and under different conditions.

**I cannot cleanly separate the two here, and I am not going to pretend otherwise.** A and B
differ in exactly one input — residue — so that single late divergence is either residue-caused
or the known residual non-determinism surfacing. No pair of runs can ever have *identical*
residue (each run creates its own), so this design cannot separate them. What the sweep does
establish is a bound: whatever that late perturbation is, it does not move any headline number.

## So what did cause 14 vs 61?

The runs that scored 14 have been **purged** — `ottoq_sim_runs`, their snapshots and their
sessions are gone (finding §5 of the isolation document, now demonstrated rather than
predicted). They cannot be examined. What follows is inference, labelled as such.

The score is steeply dependent on **how many ticks ran**. Cumulative sessions in arm A:

| tick | 1–8 | 9 | 10 | 11 | 12 | 13 | 14 | 15 | 16 | 17 | 18 | 19 | 20 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sessions so far | 0 | 1 | 17 | 23 | 31 | 36 | 37 | 39 | 39 | 44 | 52 | 53 | **61** |

Nothing happens for eight ticks — the fleet is out on shift — and then the overnight wave
lands. **A score of 14 is reachable only partway through tick 10.** It is not a value a
completed 20-tick run produces; 61 is, and 61 reproduced three times out of three here under
wildly different residue.

Set beside the defect 0071 fixed — a run that was asked for 8 ticks, advanced 0, returned 0 and
raised nothing — the parsimonious reading is that **the 14-runs were short runs that the harness
did not report as short.** That is inference, not proof, and the evidence needed to confirm it
no longer exists. It is recorded here as the leading explanation, at that strength.

**What is proven:** the score is a function of ticks completed far more than of anything else,
and until 0071 the harness could complete fewer ticks silently. Both halves of that sentence are
measured, and together they are sufficient to explain the discrepancy without invoking residue.

## Consequences

1. **`docs/RUN_ISOLATION_FINDING.md` recommended fix 1 stays withdrawn.** Clearing residue is
   hygiene — it removes an uncontrolled variable and would tidy the two small effects above. It
   is not the cause of anything that mattered, and must never be presented as such.
2. **Recommended fix 3 is now the urgent one.** The purge destroying run evidence is what made
   14-vs-61 permanently undiagnosable. That is a real cost, paid once already.
3. **Scoring on rows remains wrong** (fix 4) — but note it is not what produced the
   discrepancy; the row count was faithfully reporting a shorter run.
4. **The benchmark is now reproducible on demand:** same seed → 61, three times, with residue
   varying by 1,416 rows. That is the property the sliders model requires, and it holds.

## Reproducing

```sql
-- per arm, mid-minute, one execute_sql call:
SELECT public.ottoq_cert_arm_start(424242::bigint,'otto_q',
       'c7dece97-0000-4000-8000-000000424266'::uuid, 0);
UPDATE ottoq_sim_runs SET run_by='cert_harness', next_tick_due_at=now()+interval '6 hours'
 WHERE status='running' AND depot_id='22222222-2222-2222-2222-222222222222';
-- then steps of 1, 7, 6, 6; then ottoq_score_run(); then ottoq_cert_arm_finish().
```

Run ids: A `b4aaa44e-8ba9-407a-9cd7-bcd7b518caf8` · B `5313a8f7-df4c-4847-b164-d848ee1e564b` ·
C `bd44f721-f8ca-4117-999c-5a8dc4e184ce`. Scores in `ottoq_ab_runs`; frames in
`ottoq_decision_snapshots` until the next purge reaches them.
