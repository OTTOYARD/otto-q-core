# Round 25 — 2026-09-08 (in progress; first pair fired 3:25 AM CT / 08:25 UTC)

Flagship depot `11111111-…`, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced,
arm budget 900 s. Engine as of **0216** (the SDR booking pick + the `leg_id` index) and
**0217/0218** (h_sdr measured, h_rcl enforced).

## Pair 1 — busy_day / 314159 / 12 ticks — **PASSED**

Runs `5861ea1d` (arm a) and `98095daf` (arm b). Wall clock **812 s**.

**All eleven enforced atoms held, and every one reproduces round 24 exactly:**

| atom | round 25 | vs round 24 |
|---|---|---|
| `fp` | `803698f3` | same |
| `h_cmd` | `109e340b` | same |
| `h_dec` | `9abdb4af` | same |
| `h_evt` | `9c631343` | same |
| `h_bkg` | `174b8835` | same |
| `h_nrg` | `a9c6b693` | same |
| `h_prop` | `a79c1095` | same |
| `h_cal` | `11a24626` | same |
| `h_rule` | `fc69953b` | same |
| `h_rcl` | `0e67b89a` | same — **first round in which it could fail a pair** |
| `endst` | unchanged | same |

So 0216, 0217 and 0218 moved no canon, which is what all three predicted, and `h_rcl`'s
promotion from measured to enforced (0217) passed on its first outing.

## The new instrument found something on its first run

`h_sdr` — measured, not judged — differed: **`0df9a909` vs `65ec044e`**.

The carrier was the hash, not the engine. Matching the 284 SDRs across arms on
`(vin, operation_code, started_at)`, field by field:

| column | rows differing |
|---|---|
| `tariff_id` | 0 of 284 |
| `total_cost_usd` | 0 of 284 |
| `ended_at` | 0 of 284 |
| `duration_min` | 0 of 284 |
| `source_kind` | 0 of 284 |
| **`payload_hash`** | **284 of 284** |

`payload_hash` is `ottoq_compute_event_hash(v_payload)`, and `ottoq_emit_sdr` builds
`v_payload` with `'leg_id', p_leg_id` — a fresh uuid per run. 0217 called `h_sdr` id-blind and
then included a column that cannot be equal across two arms by construction. **0218 removes
it**, and the same expression without it reads `aad2d1be` on **both** arms.

Which is the result that matters: **0216 worked.** The booking attribution reproduces exactly
now. Before it, 23 of 284 SDRs per arm bound to a different calendar claim on a replay of the
same seed, inside a pair that passed.

0218's A3 also re-checks that the corrected hash still *separates* the pre-0216 arms
(`1cc8a3ef` vs `e1fe3504`) — the false positive is not being fixed by blinding the instrument.

## The speed claim, refuted

0216 added the missing `leg_id` index after measuring the trigger's own lookup at
**965.175 ms → 0.295 ms** (50,769 blocks → 25). That is real, and the scan it removes was
genuinely unbounded in history. **It did not make the pair faster.**

| | wall clock |
|---|---|
| pre-0216 (round 24, two pairs) | 797 s, 801 s |
| post-0216 (round 25, pair 1) | **812 s** |

812 s sits inside the previous days' range (688–822). The microbenchmark was cold-cache
(`read=50769`); in a real arm those pages are warm and each scan costs far less, so ~2,236 of
them do not add up to anything near the 800 s pair. The index is still correct — it removes a
cost that grows with total history rather than with the run — but it is **not** the drift.

**The drift is still open.** Refuted so far: the `ottoq_demo_metronome` cron job (flat at
20 ms/run all week), and missing `sim_run_id` indexes on the verdict-hash tables
(`ottoq_events`, `ottoq_decisions`, `ottoq_rule_evaluations`, `ottoq_energy_commands`,
`ottoq_recall_decisions`, `ottoq_external_proposals` all have one). At 24 ticks per pair and
812 s, the number to attack is ~33 s per tick, and `pg_stat_statements.track` is `top`, so the
tick's internals are invisible to it. Next instrument, not next guess.

## Remaining five columns

Scheduled 08:46, 09:02, 09:18, 09:34 and 10:00 UTC (3:46 – 5:00 AM CT), 16-minute spacing for
12-tick and 26 for 24-tick, from the 812 s / ~1300 s measurements. The round is complete when
all six columns have run; `h_sdr` is enforced by a later migration only if all six show the
arms agreeing, which is the same gate 0206 set for `h_rcl` and 0217 closed.
