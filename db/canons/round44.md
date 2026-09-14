# Round 44 — the recert round for the outbound/forecast window (0320–0324)

**Status: PRE-ROUND.** Written before the apply window opens, because a prediction
recorded after the result is not a prediction. The judgement goes below the line.

## What this round certifies

| | what it does | forces_recert |
|---|---|---|
| `0320` one function writes the return ETA and writes its label with it | creates `public.ottoq_refresh_return_eta`; no existing function replaced | **TRUE** |
| `0321` each writer states its own provenance, and active vehicles get a forecast | substitutes into 4 live functions; ~36 dispatch rows per run gain an ETA that was NULL | **TRUE** |
| `0322` the ETA and its provenance move together or the write is refused | two BEFORE triggers + `ottoq_assert_eta_provenance` | **TRUE** |
| `0323` nothing that starts a run ever armed the agentic layer | arms `ottoq_agentic_arm` from BOTH run doors, guarded `p_run_by <> 'cert_harness'` | see P2 |
| `0324` the one-world guard says "this depot" and has no depot predicate | RAISE text only | false |

## P1 — every column passes twice and goes green.

The falsifier is the same one round 43 used and it is not a formality: `0321` puts a
*computed* value where a constant stood, on a path that runs inside every certification.
A computed ETA that reads anything unseeded — a wall clock, a random id, an unscoped
row — is exactly the `0319` defect class, and this is the round that would expose it.

## P2 — which atoms move, named in advance.

**`endst` MOVES on every flagship column.** `ottoq_vehicle_dispatches` is inside
`endst.dispatches.vis`, and `0321` gives ~36 previously-NULL rows per run a real ETA.
A column where `endst` does NOT move means `0321` never reached the certified path.

**`dec` and `cmd` MOVE wherever a changed ETA changed what the decide path did**, and
may legitimately hold where it did not. Unlike `endst`, this one is not predicted on
every column.

**`fp` HOLDS on every column, and this is the sharp one.** Measured from the live
bodies rather than assumed:

  * `twin.ottoq_sim_prime_deployment` is called directly by `ottoq_determinism_pair`,
    at source position 2097 — *before* `ottoq_boot_state_fingerprint` at 2367. So the
    fingerprint is taken AFTER prime has written its dispatch rows.
  * `ottoq_boot_state_fingerprint` **does** read `ottoq_vehicle_dispatches`, and
    **does not** read `return_eta_minutes`.

`0321` changes the VALUES prime writes into those rows, not WHICH rows it writes.
So `fp` must hold. **If `fp` moves, `0321` changed the set of dispatch rows rather
than their ETA, and that is a defect, not a canon update.** That is the falsifier
this prediction exists for — and it is the prediction round 43 failed to make
explicit about `fp` and had to explain afterwards.

**`cal` HOLDS.** No calibration prior is refitted by any file in this window.

**`0323` moves NOTHING, and this is a second falsifier.** Its arming block is gated
`IF COALESCE(p_run_by,'') <> 'cert_harness'`, and every certification run is
`run_by='cert_harness'` — measured: 40 of 40 runs in the three hours before this
round. `ottoq_agentic_arm` independently RAISEs 42501 on a `cert_harness` run. So
`0323` is inert inside a pair by two mechanisms. **Any canon movement attributable to
0323 means the cert harness is not identifying itself the way both guards assume**,
which would be a much larger finding than the migration.

**`0324` moves nothing.** It rewrites a RAISE string.

## P3 — the recert floor moves exactly once, to the last file applied.

Round 43 closed at floor `2026-09-14 17:18:45.095549+00` with ten green columns and
zero determinism failures. This window applies five files, so the floor moves to
`0324`'s stamp and every column returns to `consecutive_passes = 0`. Nothing may be
applied once lane 1 fires; `0325` (the energy dock) is deliberately held behind this
round for exactly that reason.

## The operational rule this round inherits from round 43

**A twin run anywhere on the instance is a certification outage.** `ottoq_sim_start_run`'s
guard is global, with no depot predicate. I started a demo run mid-round 43 and it
refused two pairs. No twin run, on any depot, while lane 1 or lane 2 is in flight.

## Pre-round canon table — round 43's banked values, to diff against

First eight hex characters, depot `11111111` except where noted.

| column | fp | cmd | dec | rcl | endst | cal |
|---|---|---|---|---|---|---|
| 48t/171717/busy | 9c28854e | 700c0bd1 | 508e9323 | 38d46cee | e21d765c | 11a24626 |
| 24t/171717/busy | 9c28854e | aa851116 | cf474410 | 139af2f6 | 070d08f1 | 11a24626 |
| 24t/424242/busy | 7a14aa52 | 231293b7 | 7d901d85 | bf6e0fb8 | 584f6557 | 11a24626 |
| 12t/171717/busy | 9c28854e | e07b4d2f | 5e03ebd0 | e8062941 | 65f26efe | 11a24626 |
| 12t/314159/busy | b8606125 | 0c6a5fb5 | 69e6a60a | 4ee0187d | c847d9b8 | 11a24626 |
| 12t/424242/busy | 7a14aa52 | c5278b05 | 3670a7e2 | 86bf1c8f | 1bb3ed03 | 11a24626 |
| 12t/171717/normal | 9c28854e | 68dcd195 | 5a8a186d | 536db755 | d6257ac4 | 11a24626 |
| grid 239001/6 | 66275ea7 | 1b9920dc | bd7f4e92 | 3dc5aec9 | e4435c29 | 11a24626 |
| grid 424242/6 | 4cac51f0 | e4158c95 | 8671fb10 | bf98853e | 8fd0046c | 11a24626 |
| grid 171717/12 | 5f2e25bc | d2ee7186 | 322fac8d | 376b4991 | 604049ea | 11a24626 |

## The schedule as actually scheduled

Applied window, read back from `supabase_migrations.schema_migrations`:

| | stamp |
|---|---|
| `0320` | `20260914192115` |
| `0321` | `20260914192306` |
| `0322` | `20260914192410` |
| `0323` | `20260914192648` |
| `0324` | `20260914192738` |

Recert floor therefore **`2026-09-14 19:27:38.39239+00`**, and all ten columns
returned to `consecutive_passes = 0` — P3's first half, already confirmed.

Twenty pairs. Lane 1 (grid) runs first and cheapest, exactly as round 43 did,
so that a nondeterministic computed ETA shows on a 4-vehicle fixture in fifteen
minutes rather than on the flagship after two hours.

| job | fires UTC | CT | ticks |
|---|---|---|---|
| `r44_ga1` grid 239001 | 19:32 | 2:32 PM | 6 |
| `r44_gb1` grid 424242 | 19:35 | 2:35 PM | 6 |
| `r44_gc1` grid 171717 | 19:38 | 2:38 PM | 12 |
| `r44_ga2` / `gb2` / `gc2` | 19:42 / 19:45 / 19:48 | 2:42 / 2:45 / 2:48 PM | second pass |
| `r44_b1` busy 171717 | 19:52 | 2:52 PM | 12 |
| `r44_a1` busy 314159 | 19:57 | 2:57 PM | 12 |
| `r44_c1` normal 171717 | 20:02 | 3:02 PM | 12 |
| `r44_d1` busy 424242 | 20:07 | 3:07 PM | 12 |
| `r44_e1` busy 171717 | 20:12 | 3:12 PM | 24 |
| `r44_f1` busy 424242 | 20:20 | 3:20 PM | 24 |
| `r44_g1` busy 171717 | 20:28 | 3:28 PM | 48 |
| `r44_b2` … `r44_g2` | 20:43 – 21:19 | 3:43 – 4:19 PM | second pass |

Last pair ends about **21:28 UTC (4:28 PM CT)**. Slots are sized from round 43's
measured durations — 12t 125 s, 24t 231–246 s, 48t 507–511 s — not from the
stale constants in `scripts/schedule-round.sql`.

**Nothing may be applied until every one of these is unscheduled.** `0325` (the
energy dock) is committed PENDING and waits behind this round.

---

## THE JUDGEMENT

_(pending — written when the round lands)_
