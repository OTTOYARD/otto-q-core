# The twin A/B — OTTO-Q vs FIFO vs greedy on the identical world (V1_DEMO_PLAN D2)

*Rig: `db/migrations/0261`. Reader: `db/checks/0185`. Status: **drafted 2026-09-12, not yet
applied** — 0261 waits for round 40 to be judged. Nothing below is a result until this
paragraph says so and a run id sits next to every number.*

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

**The one leak, measured rather than hidden.** `ottoq_decide_tick` keeps an in-tick
heuristic (`ottoq_l2_propose_stall_assignment`) as the fallback for a vehicle no proposer
covered. It is shared by every seat, and each arm's verdict carries `stall_sources`, the
count of enacted stall assignments by proposer. `local_heuristic` there is the share the
seat did **not** decide. Quote a difference only next to that share.

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

## Results

*None yet. This section is filled from `db/checks/0185` §2–§4 after 0261 is applied, with
the ab_group_id and both run ids on every row.*
