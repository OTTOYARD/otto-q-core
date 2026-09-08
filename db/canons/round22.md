# Round 22 canons — 2026-09-07 (fired 1:35–4:03 PM CT)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0204** (1:18 PM CT), **0205** (1:21 PM CT) and **0206** (1:27 PM CT, the
recertification floor). Nine pairs, same nine columns as round 21.

**Nine of nine passed.** Every arm carries `h_rcl`, 0206's new instrument, and the two arms
agree on it in all nine pairs.

**Every `h_cmd` reproduced round 21's canon exactly.** That was the standing question round 21
left open — a column that moved again would have meant 0207 left a second carrier — and the
answer is that it did not. Six columns, nine pairs, no movement.

| scenario | seed | ticks | h_cmd | vs r21 | h_evt | vs r21 | h_rcl (new) |
|---|---|---|---|---|---|---|---|
| busy_day | 314159 | 12 | `109e340b` | **same** | `9c631343` | moved (was `a41175ba`) | `0e67b89a` |
| busy_day | 171717 | 12 | `1ae7ba68` | **same** | `e16ad964` | moved (was `e15a20ab`) | `0a4ca4d3` |
| normal_day | 171717 | 12 | `5921ef70` | **same** | `ac672423` | moved (was `454e34a6`) | `e4e41e69` |
| busy_day | 424242 | 12 | `76134009` | **same** | `6453c09b` | moved (was `638655b3`) | `f58ee562` |
| busy_day | 171717 | 24 | `050c4606` | **same** | `b2230619` | moved (was `be8ee6cb`) | `fa8ab72c` |
| busy_day | 424242 | 24 | `8f232001` | **same** | `8dc37f82` | moved (was `67cb213b`) | `928262d2` |

`h_evt` moved on all six **by design**: 0204 added `sim_clock_at` to the event stream, so every
event row carries a new deterministic field and the stream hash necessarily moves. It moved
once, and each of the three columns that ran twice reproduced its new value exactly.

`h_dec`, `h_bkg`, `h_nrg`, `h_prop`, `h_defr`, `h_cal` and `h_rule` are unchanged from round 21
on every column. Boot fingerprints unchanged (`803698f3` / `92b02f8b` / `e418e4f0`). `h_cal` is
`11a246262ff7a2c929483b1ee0a7cd2d` on all eighteen arms; `h_defr` is `d41d8cd9` (empty).

## Standing at the 0206 floor

Green (two consecutive passes): 314159/12t, 171717/12t, normal_day/171717/12t.
One pass each: 424242/12t, 171717/24t, 424242/24t. Round 23 promotes those three.

## The finding: `h_rule` cannot see what the shield read

0205 promoted `h_rule` into the verdict on the strength of six agreeing pairs. Round 22's read
shows the instrument is narrower than the claim it was promoted to carry.

0204 (G15) stopped the L1 shield reading the wall clock inside the twin. On 171717/24t the
effect is visible and large:

| | round 21 (pre-0204) | round 22 (post-0204) |
|---|---|---|
| `TW.001.operational_hours` evaluations | 1,036 (518 per arm) | 1,036 (518 per arm) |
| distinct `result_payload->>'local_time'` | **1** | **24** (00:00–23:30) |
| `h_rule` | `62ed1a1e…` | `62ed1a1e…` — **unmoved** |

The evaluator went from judging every task against one frozen local time to judging each against
the run's own clock. That is the fix working. `h_rule` did not notice, because
`ottoq_hash_rule_evaluations` hashes rule_code, rule_version, action_context, entity_type,
entity_id, passed, severity, enforcement, enforcement_taken and `parameters_used` — and
`parameters_used` is `{}` on these rows. The local time the rule actually read lives in
`result_payload`, which is not hashed.

So `h_rule` as shipped answers *"did the same rules fire on the same entities and reach the same
verdicts"*. It does not answer *"did they read the same world"*. An engine change that fed every
evaluator a wrong clock — or a right one — passes the pair and moves no canon.

This does not weaken round 22's verdict: both arms of a pair are equally blind, they agreed, and
every other instrument moved or held as predicted. It is a **round-to-round** detection gap, the
same class 0139 closed for `endst` and 0199 closed for the proposal stream. `0208` closes it by
folding the deterministic part of `result_payload` into the hash.

## A correction to an earlier reading

Mid-session I recorded the G15 proof as *"TW.001 went from 1,162 evaluations at a single
local_time to 518 across 24 distinct local times."* The evaluation COUNT did not change: it is
1,036 per pair (518 per arm) in both rounds. Only the local_time did, from 1 distinct value to
24. The fix is real; the count half of that sentence was wrong.
