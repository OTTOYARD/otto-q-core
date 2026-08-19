# policies/ — C5 Policy Consolidation & Baselines

One interface — `AssignmentPolicy { name; decide(state, arrivals) -> [Assignment] }` —
over the four comparable policies:

| name | what it is |
|---|---|
| `fifo` | strict arrival order, earliest-free capable point |
| `greedy` | myopic: the point minimizing this vehicle's charge end |
| `otto_q_asis` | AS-IS reduction of the live cursor: `ottoq_decide_tick` (3) ordering (urgency, lowest SoC, id) + dcfc_first plug-target preference, transcribed from `db/fn_current/` (md5-stamped). The production disposer remains the SQL function. |
| `cpsat` | the C4 prototype as a policy: one joint solve, assignments read off the plan |
| `waymo_staging` | **PARKED** stub — compiles, refuses to run; TODO references US 12,545,288 B2 |

## CRN / seed discipline (the ottoq_ab_runs spine, preserved exactly)

One deterministic scenario draw per seed, shared verbatim by every policy; the
policies consume no randomness of their own. Per-asset numbers are therefore
paired differences. The committed comparison is keyed by seed **424242**.

## The committed comparison run

`comparison_seed424242.json` — regenerable byte-for-byte:

    python3 policies/run_comparison.py          # verify (prints MATCHES/DIFFERS)
    python3 policies/test_policies.py           # full battery incl. byte-equality

Headline (seed 424242, reduced canonical scenario; read WITH the caveats below):

| policy | total_tardy_min | p95_wait | peak_kw | moves | makespan |
|---|---|---|---|---|---|
| fifo | 621 | 0 | 340 | 9 | 636 |
| greedy | 0 | 22 | 402 | 9 | 227 |
| otto_q_asis | 395 | 74 | 392 | 9 | 551 |
| cpsat | 118 | 84 | 436 | 9 | 458 |

**Read honestly:** the policies optimize different objectives. `greedy` minimizes
each vehicle's finish and ignores energy price and peak entirely; `cpsat`
minimizes the C4 multi-term objective (tardiness ×10, on-peak kW-minutes, peak
excursion ×20, moves ×15) and deliberately trades tardiness minutes for keeping
charge out of the 240–420 on-peak window; `otto_q_asis` is the transcription of
the live cursor's ordering rules into this reduced harness, NOT the full engine
(no shield, no needs-card routing, no reservations). None of these numbers is a
throughput claim about the production engine — `SOLVER_STATE.md` §4 records that
`ottoq_ab_runs` currently holds zero rows, and the full-engine A/B regeneration
is C6/C8 work on the twin, keyed by run IDs. This directory's job is the
interface, the CRN spine, and the reproducibility contract.
