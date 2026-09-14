# Round 35 — the streak reaches 2, and six canons become real

**Six pairs, flagship depot, 2026-09-09 12:10–13:29 UTC (7:10–8:29 AM CT).**
The second consecutive clean round above the `09:46:27.088143` floor that `0246`
set when it repaired `0244`.

## The prediction, committed before the evidence

Written into the round-35 check-in before any pair fired: six of six PASS, and
**every atom identical to round 34** — not merely arms agreeing with each other,
but the whole fourteen-atom verdict byte-identical across two rounds two hours
apart, because no migration landed between them.

## Verdicts

| fired (UTC) | column | outcome | atoms differing between arms | atoms moved vs round 34 |
|---|---|---|---|---|
| 12:10 | `busy_day/314159/12t` | passed | 0 of 14 | **none** |
| 12:24 | `busy_day/171717/12t` | passed | 0 of 14 | **none** |
| 12:38 | `normal_day/171717/12t` | passed | 0 of 14 | **none** |
| 12:52 | `busy_day/424242/12t` | passed | 0 of 14 | **none** |
| 13:06 | `busy_day/171717/24t` | passed | 0 of 14 | **none** |
| 13:26 | `busy_day/424242/24t` | passed | 0 of 14 | **none** |

**Six of six. Zero of fourteen atoms differ between arms. Zero of fourteen moved
from round 34 on any column** — `fp` and `endst` included, which is stronger than
round 34's own result, where `fp` had moved because `0246` had just changed the
hash.

This is the distinction worth keeping straight: a pair passing proves the two
arms of ONE round agree. Six columns unchanged across TWO rounds proves the
engine agrees with **itself two hours ago**, on a database that ran production
ticks, a metronome and interactive sessions in between. That is inter-pair
reproducibility, and it is the property `0193` set a two-round bar for.

## The matrix, which is the authority

`ottoq_cert_matrix('2026-09-01')` after the last pair:

| column | pairs seen | consecutive passes | green | stale |
|---|---|---|---|---|
| `busy_day/314159/12t` | 59 | **2** | **true** | false |
| `busy_day/171717/12t` | 54 | **2** | **true** | false |
| `normal_day/171717/12t` | 47 | **2** | **true** | false |
| `busy_day/424242/12t` | 40 | **2** | **true** | false |
| `busy_day/171717/24t` | 43 | **2** | **true** | false |
| `busy_day/424242/24t` | 39 | **2** | **true** | false |

`recert_floor` `2026-09-09 09:46:27.088143`, unmoved. `forces_recert` entries
since `0246`: zero.

**Six flagship canons are green. It is the first time that has been true since
`0244`,** and two of the three recerts it cost were bought by my own error.

## What is NOT green, said plainly

The matrix has nine rows. Three are not green and none of them is covered by the
sentence above:

| column | streak | green | last pair | why |
|---|---|---|---|---|
| `busy_day/171717/48t` (flagship) | 0 | false | 2026-09-04 18:20 | **stale** — below the recert floor and not in the round rotation |
| `grid_smoke/239001/6t` (grid) | 1 | false | 2026-09-09 09:55 | one pass since the floor; needs a second |
| `grid_smoke/424242/6t` (grid) | 0 | false | 2026-09-08 07:04 | **stale** — not run since before the floor |

So the honest claim is **six of the seven flagship columns**, not "the flagship
matrix". The 48-tick column has not been run in five days; its 15-run `PfPPP`
history predates four fingerprint migrations and certifies nothing today. The
grid fixture needs one more pass on `239001` and a fresh pair on `424242`.

## The seed-keyed `fp` property, third round running

Three distinct `fp` values across six columns, one per seed, unchanged from
round 34:

```
314159  b8606125f1cbd5c820fc9be94c4c4a29
171717  9c28854e976c8572f2cc1bf4717f85b0
424242  7a14aa522a65cc196ca486309194573c
```

The start-of-run world depends on the seed and on nothing else — not on the
scenario, not on the tick count, not on the time of day. Round 32 first showed
it; rounds 34 and 35 have now held it across a fingerprint migration.

## What this unblocks

`0239`'s `replay_injected` and `0241`'s `foreign_proposals` have their first
promotion leg from `db/checks/0162` (the grid replay pair) and now a clean
flagship round behind them. `0247` — the engine-row purge — was held for this
round and is unblocked, though it is applied on its own evidence, not on this
round's.
