# Round 24 — 2026-09-08 (fired 2:29 and 2:49 AM CT / 07:29 and 07:49 UTC)

Flagship depot `11111111-…`, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced,
arm budget 900 s. Engine as of **0209–0212** and **0214/0215**.

The round was cut short deliberately. Two pairs ran on one column; the second was scheduled to
settle a performance question, and the answer it gave sent the work somewhere else. The
remaining five columns were never scheduled.

## The two pairs

Both `busy_day / 314159 / 12 ticks`, flagship, and **both passed**.

| | 07:29 pair | 07:49 pair (re-measurement) |
|---|---|---|
| arm a run | `ba2d2b6e` | `53317e05` |
| arm b run | `1d31b2ee` | `ea855128` |
| wall clock | 797 s | 801 s |
| verdict | passed | passed |

Every atom identical across the two pairs and across the four arms:

| atom | value | vs round 22 |
|---|---|---|
| `fp` | `803698f3` | **same** |
| `h_cmd` | `109e340b` | **same** |
| `h_dec` | `9abdb4af` | **same** |
| `h_evt` | `9c631343` | **same** |
| `h_bkg` | `174b8835` | **same** |
| `h_nrg` | `a9c6b693` | **same** |
| `h_prop` | `a79c1095` | **same** |
| `h_defr` | `d41d8cd9` (empty) | **same** |
| `h_cal` | `11a24626` | **same** |
| `h_rcl` | `0e67b89a` | **same** |
| `h_rule` | `fc69953b` | moved from `333cf172`, as 0208 requires |

Seven canon values reproduced round 22 exactly and only `h_rule` moved, which is what 0208 was
built to do. **That is the certification evidence that 0209, 0210, 0211 and 0212 moved nothing
on the real depot.** Recert floor unchanged.

## The reading that ended the round: there was never a regression

0214 was written to fix a performance regression that does not exist. Its header cited a
"historical 438–454 s" for this column against 797 s under 0211. That baseline was real but it
was not this column's recent history — it was the 09-01/09-02 regime. The full run-details
history for `determinism_pair(314159, 12, busy_day, flagship)`:

| date | pair durations (s) |
|---|---|
| 09-01 | 389 |
| 09-02 | 308, 327, 413, 421, 500 |
| 09-03 | 431, 513, 523, 528, 595, 606, 614 |
| 09-04 | 512, 652 |
| 09-05 | 545, 681, 697, 744 |
| 09-06 | 688, 724, 741, 804, 804 |
| 09-07 | 643, 758, 822 |
| 09-08 | **797, 801** |

Monotone drift across seven days on a fixed seed, fixed tick count, fixed scenario and fixed
depot. Not a step change on 09-07 when 0209–0212 landed — 09-06 already reached 804 s with none
of them applied. 797 s and 801 s sit inside the previous day's range.

So the honest accounting of 0214 and 0215: **0214's premise was false**, its change broke a
standing refusal, 0215 restored the behaviour, and the pair of them is behaviourally a no-op —
which the two pairs above prove atom by atom. The cost was one broken-then-fixed invariant and
about forty minutes. What it bought was the duration history above, and that turned out to be
worth more than the thing it was looking for.

## What the drift actually is

The shape — linear in calendar time, on an unchanged workload — is accumulating table size, not
a code change. Convicted in `db/checks/0123`: `ottoq_stall_bookings.leg_id` has no index, and
two hot paths filter on it.

- `ottoq_trg_leg_done_sdr` — the SDR terminus, `AFTER UPDATE OF status … WHEN new.status='done'`.
  Fires **433 times per 12-tick arm** on this column.
- `ottoq_itin_leg_open` — the `NOT EXISTS … bz.leg_id = v_leg` guard, once per leg opened
  (685 legs per arm).

Measured plan for the trigger's lookup, on the live table (774,482 rows):

```
Limit (actual time=960.775..965.092 rows=0 loops=1)
  Buffers: shared hit=236 read=50769
  ->  Gather … Parallel Seq Scan on ottoq_stall_bookings
        Filter: (leg_id = '…'::uuid)
        Rows Removed by Filter: 387241
Execution Time: 965.175 ms
```

≈2,236 sequential scans of a 774k-row table per pair, and the table grows with every run ever
archived. That is the drift, and it is the same defect class as `db/checks/0098`: a query whose
cost is set by history rather than by the run.

## The second finding, which matters more

Chasing the index turned up a live nondeterminism the certification cannot see. The SDR trigger
binds its settlement record to a booking with:

```sql
SELECT b.booking_id, b.visit_id INTO v_booking, v_visit
  FROM ottoq_stall_bookings b WHERE b.leg_id = NEW.leg_id LIMIT 1;
```

`LIMIT 1`, no `ORDER BY`, and within one run **33 of 433 done-legs carry more than one booking**
(up to 7). Measured on the 07:49 pair's own committed rows, comparing the two arms by the
booking's *content* rather than its id:

| | arm a | arm b |
|---|---|---|
| SDRs | 284 | 284 |
| SDR core content hash | `16d2dce1…` | `16d2dce1…` — identical |
| booking-attribution hash | `9f074e65…` | `ecf6e4d2…` — **different** |
| SDRs binding to a different booking | — | **23 of 284 (8.1%)** |

A pair that passed all thirteen atoms wrote 23 settlement records per arm that attribute to a
different calendar claim on a replay of the same seed. It passed because there is no `h_sdr`:
`ottoq_service_detail_records` is not in the verdict, and `ottoq_emit_sdr`'s signed event payload
omits `booking_id` and `visit_id`, so the divergence never reaches `h_evt` either.

Two consequences recorded, one fixed now and one not:

1. **Fixed in 0216** — the pick gets a total order and `leg_id` gets its index.
2. **Not fixed, named** — the SDR is signed over a payload that excludes the booking and visit
   it settles. The signature does not cover the attribution. Putting them in the payload moves
   `payload_hash` on every future SDR and therefore `h_evt` on every column, so it is a full
   six-column recert and belongs with G10 (task #71), not here.

## Standing

The flagship 314159/12t column has two consecutive passes at the current floor. The other five
columns are unrun for round 24 and are the first thing round 25 does, after 0216 and 0217.
