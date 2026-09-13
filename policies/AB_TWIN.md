# The twin A/B — OTTO-Q vs FIFO vs greedy on the identical world (V1_DEMO_PLAN D2)

*Rig: `db/migrations/0261` (applied `20260912233647`). Reader: `db/checks/0185`. Status:
**live; first flagship comparison judged 2026-09-13 00:21 UTC** — results below, every number
with its run id; the full write-up is `db/canons/ab_busy_day_424242_12t.md`.*

## What "only the policy differs" means here, precisely

Read the live engine and OTTO-Q's stall policy is not inside the disposer. It is a
**proposer**: `ottoq_l2_optimize_assignments` (source `greedy_constrained`) writes
`ottoq_external_proposals` from `ottoq_sim_decide_and_dispatch` before `ottoq_decide_tick`
runs, and `ottoq_decide_tick` then reads the winning proposal, evaluates the 29-rule L1
shield on it, books through the stall calendar, emits the commands and the SDRs. So the
line `db/checks/0146` drew — *the shield is part of the problem definition, not the
policy* — is already where the code draws it:

    the POLICY is what proposes;   the KERNEL (disposer + shield + calendar) disposes.

A baseline policy is therefore a baseline **proposer**, seated in the same place, heard
through the same door, disposed by the same function:

| seat | name | what proposes each decide tick |
|---|---|---|
| 0 | `otto_q` | reservation re-optimisation, the cuOpt gate + first refusal (quiesced in a pair, as in a certification), `greedy_constrained` (most-depleted first, DCFC-first with L2 overflow, distance tiebreak), `ottoq_service_priority` — **the pre-0261 text, verbatim** |
| 1 | `fifo` | one proposer: gate vehicles in **arrival order**, first free compatible plug in `stall_code` order, no type preference (`ottoq_fifo_tick`'s rule, now behind the shield) |
| 2 | `greedy` | one proposer: **most-depleted vehicle first**, the fastest plug it can take (highest `connector_max_kw`), myopic |

Held constant for every seat: `ottoq_decide_tick` (so the shield and its safe defaults, the
site power gate `0132`, the calendar and its EXCLUDE constraint, the SDR terminus), the
deploy path, the twin, the seed, the calibration priors, the scenario, the boot world, the
reservation-honour path (a vehicle arriving on a booking it already holds is placed on it
by every seat — that is the calendar, not the policy).

**Why the seat reaches three functions, not one — measured before building.** Over the
last four flagship 12-tick certification runs, of 796 enacted stall assignments the
pre-tick proposer `greedy_constrained` decided 204 (26%); the **in-tick heuristic**
`ottoq_l2_propose_stall_assignment` decided 426 (54%) — 154 at the gate and 224 for
vehicles re-queued from `staged_awaiting_service` when a plug freed; reservations
honoured 164 (21%). A seat that swapped only the pre-tick proposer would have left the
"FIFO" arm three-quarters OTTO-Q. So under a non-zero seat:

- the in-tick fallback returns the seat's own stall choice (`ottoq_l2_propose_stall_seat`)
  and stamps `source`, so `ottoq_decisions` attributes the assignment to the seat;
- the disposer's **queue order** for stall assignment carries the seat — which waiting
  vehicle gets a freed plug *is* the policy: fifo by arrival, greedy by depletion, seat 0
  unchanged. The need's `immediate_dispatch` urgency stays ahead of every seat's key; it
  is the work-side signal (CLAUDE.md 2.7), not the stall policy.

Each arm's verdict carries `stall_sources`, the count of enacted stall assignments by
source. Under a baseline seat every entry must be the seat or a `reservation_*` source,
and 0261's A5 asserts it; for seat 0, `local_heuristic` is OTTO-Q's own in-tick rule.

## The verdict is inverted

`ottoq_determinism_pair` passes when the arms are identical. `ottoq_ab_pair` is **valid**
when the arms are identical *on the world* — boot fingerprint and calibration hash
byte-equal, both arms complete — and then reports what the policy moved:

| outcome | meaning |
|---|---|
| `passed` | same seat on both arms and every atom byte-identical — **the self-test**; the rig is an instrument |
| `failed` | same seat, atoms diverged — the rig is not an instrument; nothing else it says counts |
| `invalid` | the arms did not boot from one world |
| `compared` | different seats, decision stream differs — a comparison exists |
| `indistinguishable` | different seats, identical atoms — a finding, not a failure |
| `inconclusive` | an arm did not reach its tick count inside its budget |

`validation_status` on an `ab_harness` arm therefore means *the instrument was valid*,
never *a policy won*. The certification matrix, Posture A and the metronome never see
these arms (`run_by = 'ab_harness'`, not `cert_harness`); the seat is a run-scoped policy
param that a CHECK constraint forbids at any other scope, so a certification arm cannot
inherit one.

## Scores

Every arm is scored by `ottoq_ab_score_run` (`0230`: outcome-based, coverage first) and
written to `ottoq_ab_runs` by `ottoq_ab_write_score` — the writer 0230 said would come
"once this has been run against real arms". With the shield held constant the rule-based
columns (`safety_violations`, `overrides_total`) are comparable for the first time; the
outcome columns (`energy_peak_kw`, `peak_demand_pct_of_cap`, `charge_sessions`) always
were. `incidents_open`, `productive_deploys`, `unsafe_deploys` stay NULL: this rig has no
honest definition for them and a NULL is not a zero.

The `ab_group_id` **is the comparison key** — `md5(seed, ticks, scenario, depot, clock,
seat_a, seat_b)` — so a re-run lands in the same group and `db/checks/0185` §4 can say
whether it came back byte-identical, which is Phase 1's stopping rule.

## How to run one

```sql
-- inside the migration: A4 (grid self-test, otto_q vs otto_q) and A5 (grid, otto_q vs fifo)
-- the flagship comparison, one-shot cron exactly as a certification pair is scheduled:
SET statement_timeout TO '25min';
SELECT public.ottoq_ab_pair(424242, 12, 'busy_day', '11111111-1111-1111-1111-111111111111'::uuid,
                            '2026-09-01 02:00:00+00'::timestamptz, 900, 'otto_q', 'fifo');
SELECT public.ottoq_ab_pair(424242, 12, 'busy_day', '11111111-1111-1111-1111-111111111111'::uuid,
                            '2026-09-01 02:00:00+00'::timestamptz, 900, 'otto_q', 'greedy');
```

Never overlapping a certification pair on the same depot; `pg_stat_activity` is the only
authority for in-flight.

## Results — busy_day / 424242 / 12t, Nashville Flagship (2026-09-13 00:21 UTC)

Full canon: `db/canons/ab_busy_day_424242_12t.md`. Instrument: the flagship self-test
(`otto_q`/`otto_q`, group `d025d7f9…`, runs `36caa0c4`/`6a8c9662`) is byte-identical on all
fifteen atoms; the `otto_q`/`fifo` comparison run twice (group `1e683534…`, runs
`b175aa13`/`0b92aa42` and `c4687665`/`64489387`) reproduces byte for byte per seat (0185 §4).
Same 116 arrivals in every arm (`h_arr` identical); under a baseline seat every non-reservation
charger assignment is the seat's (fifo 125, greedy 122, OTTO-Q heuristic 0).

| metric | otto_q | fifo | greedy |
|---|---|---|---|
| decisions / enacted | 1442 / 1175 | 1487 / 1221 | 1477 / 1211 |
| shield refusals (overrides / violations / critical) | 6 / 6 / 0 | 6 / 6 / 0 | 6 / 6 / 0 |
| peak kW (% of 2,500 cap) | 456.6 (18.3%) | 451.7 (18.1%) | 476.1 (19.0%) |
| vehicles turned around in 6 h | 47 | 45 | 49 |
| median turnaround, min | **150** | 180 | 180 |
| ready for departure at tick 12 (% of 116) | 42.2% | 40.5% | 44.0% |
| idling on a finished charger at tick 12 | **4** | 9 | 8 |

Reading: OTTO-Q turns a vehicle around 30 minutes faster at the median and leaves half as
many vehicles parked on finished chargers, with fewer decisions; greedy readies two more
vehicles by the end of the window at the highest peak; FIFO is slowest. Safety is identical
by construction. The separation on volume is small in a six-hour window with no redeploys;
longer horizons are the next measurement. Runs `otto_q` vs `greedy`: `6f8980fd`/`4c5de6a5`
(group `c7f1ae81…`).
