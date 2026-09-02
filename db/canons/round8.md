# Round 8 canons — 2026-09-02

Depot `11111111-1111-1111-1111-111111111111` (flagship), pinned sim start
`2026-09-01 02:00:00+00`, proposer quiesced by 0152.

First full round after five `forces_recert` migrations applied the same day:
0155 (twin meter), 0156 (power-aware proposer), 0159 (downgrade policy),
0162/0163 (declared faults). Recert floor raised by those; every pair below is
at or above it.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg |
|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `04177a2a5d686032aa1c54fcac43f958` | `5328154a5f72e9e1bb6b10d177def459` | `0bf42b3cc1b2db78de9e91274d28b3df` | `8dcf8918702a18b9f20022b80dd24513` |
| busy_day | 171717 | 24 | `ec5c38aad7638fedcf43db1bf2e8d2df` | `8221f656d94c997c9b36b9393c157116` | `096b099ef7c562e6e603c34bf3f2a8a9` | `da9c269cd90b18624af10b549b1f50f8` |
| busy_day | 314159 | 12 | `773fd6dc0792db84e02589dbeb41e190` | `ad4928916cedda511f2aa96c6d932694` | `4274369cba6d132e8c64d07f6d3a2c4c` | `2b271f2fdcc89ff8a01c2eaa9508b153` |
| busy_day | 424242 | 12 | `16aabc27463edb78ec972aa5f3d0b114` | `bb7105f365191bea93590b96038fc502` | `5a2272760c4750ecf018d14eb13f3ee4` | `0cac7e0b0fc16c1b1b424ec88e1b4da0` |
| busy_day | 424242 | 24 | `ac1dc75720bbc699fb5835606a421df0` | `b7cbd48c68d375092e186a65bd4f9276` | `37ed2670b0c59abe3a806c4597f25c54` | `c5ef0ab33cdb712a883f8f0654b20c66` |
| normal_day | 171717 | 12 | `78ece09b4ba4f3fc8a3b9f07936e2666` | `c36a99c17661fac254bc824179fa29bb` | `2838c66cb92d17f165cf1dea72e5f292` | `5512b23743c4b1bd10b704cc5418c39c` |

## Confirmation state at the time of writing (5:45 PM CT)

Pass 2 (`s8a`..`s8e`) was still running when this file was written. Recorded
honestly rather than backfilled later:

| column | passes | green | note |
|---|---|---|---|
| busy_day 171717 12t | 2 | yes | pairs at 3:21 and 3:40 PM CT |
| busy_day 314159 12t | 2 | yes | pass 2 reproduced `773fd6dc` exactly |
| busy_day 424242 12t | 2 | yes | pass 2 reproduced `16aabc27` exactly |
| normal_day 171717 12t | 1 | no | pass 2 fired 5:49 PM CT |
| busy_day 171717 24t | 1 | no | pass 2 fired 6:01 PM CT |
| busy_day 424242 24t | 1 | no | pass 2 fired 6:19 PM CT |

The three confirmed columns each reproduced their pass-1 canon **exactly** on an
independently fired pair. That is the bar that matters: a pass-2 pair which is
internally equal but carries a *different* canon than pass 1 is an inter-pair
carrier and a failure, however green the verdict reads.

## What is comparable, and what is not

Only `busy_day/171717/12t` has a pre-round-8 canon in the repo (`db/checks/0075`
§4, round 7): `04177a2a / 1c9ace35 / 0bf42b3c / e6425186`.

Against it: `h_cmd` and `h_bkg` **held**, `h_dec` and `h_nrg` **moved**. That is
the predicted shape — 0156 adds `headroom_kw` / `fits_headroom` /
`power_downgrade` to the decision rationale (moves `h_dec`), and 0155 stopped the
twin meter reporting 0.00 kW (moves `h_nrg`). `h_bkg` holding says the
**assignments did not change** on that column, which is the honest reading of
today's engine work there.

The other five rows above are a baseline with nothing behind them. From round 9
onward every column is diffable, which is the entire point of this file.

## Final state — round 8 closed 6:40 PM CT

Pass 2 (`s8a`..`s8e`) completed. **Six of six columns green**, every column
`pairs_seen = 2`, `consecutive_passes = 2`, and every pass-2 canon reproduced
its pass-1 value **exactly** — all four hashes, all six columns. No canon above
moved; the table is final for this round.

Recorded as an addition rather than an edit: the 5:45 PM snapshot above is left
exactly as it was written, per the rule in this directory's README. Nothing in
it was wrong, only incomplete, and rewriting a point-in-time record to look
better in hindsight is the habit that rule exists to prevent.
