# Round 10 canons — 2026-09-03

Depot `11111111-1111-1111-1111-111111111111` (flagship), pinned sim start
`2026-09-01 02:00:00+00`, proposer quiesced by 0152. Engine as of **0179**.

**Six of six columns green.** Every column has **2 pairs**, every pair passed
with arms equal, and every pass-2 canon reproduced its pass-1 canon exactly.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | rec |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `04177a2a5d686032aa1c54fcac43f958` | `5328154a5f72e9e1bb6b10d177def459` | `0bf42b3cc1b2db78de9e91274d28b3df` | `8dcf8918702a18b9f20022b80dd24513` | 0 |
| busy_day | 314159 | 12 | `773fd6dc0792db84e02589dbeb41e190` | `ad4928916cedda511f2aa96c6d932694` | `4274369cba6d132e8c64d07f6d3a2c4c` | `2b271f2fdcc89ff8a01c2eaa9508b153` | 0 |
| normal_day | 171717 | 12 | `78ece09b4ba4f3fc8a3b9f07936e2666` | `c36a99c17661fac254bc824179fa29bb` | `2838c66cb92d17f165cf1dea72e5f292` | `5512b23743c4b1bd10b704cc5418c39c` | 0 |
| busy_day | 171717 | 24 | `ec5c38aad7638fedcf43db1bf2e8d2df` | `8221f656d94c997c9b36b9393c157116` | `096b099ef7c562e6e603c34bf3f2a8a9` | `da9c269cd90b18624af10b549b1f50f8` | 0 |
| busy_day | 424242 | 12 | `16aabc27463edb78ec972aa5f3d0b114` | **`f1224a98cf0a9f16967a7db1af8c199a`** | `5a2272760c4750ecf018d14eb13f3ee4` | `0cac7e0b0fc16c1b1b424ec88e1b4da0` | 3 |
| busy_day | 424242 | 24 | `ac1dc75720bbc699fb5835606a421df0` | **`3adcc2dc…`** | `37ed2670b0c59abe3a806c4597f25c54` | `c5ef0ab33cdb712a883f8f0654b20c66` | 14 |

**Bold** = the only two values that moved from round 8. Everything else in this
table is byte-identical to round 8.

## What moved, and why that is correct

**Four columns are untouched by 0169.** `171717/12t`, `314159/12t`,
`normal_day 171717/12t` and `171717/24t` reproduce round 8 on all four hashes,
with `recorder_rows = 0`. The seat batch does not bind on those seeds.

**Two columns carry a new `h_dec`, and only `h_dec`.** On seed 424242 the batch
*does* bind — 3 deferrals at 12 ticks, 14 at 24. Those rows did not exist in
round 8, so the decision stream legitimately hashes differently.

The load-bearing result is what did **not** move on those columns:

- `h_cmd` held → the same commands were issued.
- `h_bkg` held → **the same assets were seated on the same points at the same
  times.** The `CONTINUE` that 0169 introduced did not change a single
  assignment.
- `h_nrg` held → the energy path is untouched.

Before 0169, the `LIMIT 20` dropped candidates 21+ **silently**. After 0169 and
0179 they are skipped with a logged reason. *Same seating, richer record* — which
is exactly what 0169 was for, and exactly what was predicted in 0179's header
before either pair fired.

A worked example, from `context_frame` on the 12-tick column:

```json
{"lane":"wash_bay","seat_rank":21,"seat_batch":20,"stall_type":"wash_bay","seat_qualified":23}
```

23 assets qualified for the wash-bay lane at tick 12; the batch is 20; ranks
21, 22 and 23 were deferred with a reason instead of vanishing.

## How this round was reached — the part worth keeping

Round 9 certified 0169 a no-op on **one** column and published, in capitals,
that `decide_seat_batch` had never bound anywhere. That claim was false, and
`db/canons/round9.md` carries the correction beneath the original text.

0169 had shipped an INSERT whose `outcome_status` was not in the table's check
constraint. It was not dormant instrumentation — it was a **latent crash**, and
seed 424242 hit it four times overnight. `0179` added the missing value.

`db/checks/0085` §2 had recorded the exact caveat that named the gap:

> "0169's new branch has still NEVER EXECUTED, anywhere … not a tested code path
> either, and it must not be described as one."

The defect lived precisely there. **A green column is evidence about what it
exercised, and nothing else.** Four green columns did not make the fifth safe.

## What this table still does not cover

- Two pairs per column. `normal_day 171717/12t` is task #47's column and its
  proposed bar is **eight** passes; two do not meet it and it is not closed.
- One depot. The two-lane cadence remains blocked on `0177` (the cold-start
  guard reads every depot), which is written and committed but **not applied**.
- These canons are stable across **one** round boundary (8 → 10) for the four
  unchanged columns, and are **new** for the two 424242 columns — a first
  observation, not a stable one.
