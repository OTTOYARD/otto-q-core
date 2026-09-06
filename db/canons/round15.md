# Round 15 canons — 2026-09-04 (fired 4:02–5:28 PM CT)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0195** (0194 at 3:55 PM CT, 0195 at 4:00 PM CT). Seven pairs:
busy_day/171717/12t ran twice for the inter-pair bar. **One pair failed**:
busy_day/314159/12t, again.

> Written 2026-09-06 from the verdict rows (see round14.md). Retro columns computed
> with 0199's hash functions.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | vs r14 |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `80183641` | `6e116d5b` | `b1d72a62` | `625014b7` | identical (2 pairs, both) |
| busy_day | 314159 | 12 | `cf74d080` | `1788ee1c` | `eaff0912` | `4afd1004` | **failed** — arm A shown |
| normal_day | 171717 | 12 | `af8b5e6d` | `3a8719f8` | `2c7e0a3a` | `de3b353e` | identical |
| busy_day | 424242 | 12 | `adf745a2` | `05bc65e6` | `84a9b51c` | `0cac7e0b` | **moved** (0195) |
| busy_day | 171717 | 24 | `38465601` | `09769827` | `3b52ea78` | `7606aaf2` | identical |
| busy_day | 424242 | 24 | `997e2c37` | `fd484142` | `f597a790` | `f2b72ada` | **moved** (0195) |

0195 removed a bay-queue order drawn fresh each run. Both 424242 columns moved and
stayed there through round 18; the 171717 and normal_day columns did not move,
which is what a fix to one seed's coin should look like.

| scenario | seed | ticks | h_evt | endst (md5) | boot chargers | h_prop (retro) | h_defr (retro) |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `4f8b2970` | `8ce7d28e` | `c83d7288` | `142ee120` | `d41d8cd9` |
| busy_day | 314159 | 12 | `25cf62c5` | `15339abe` | `9c25b338` | `b32df53d` (arms differ) | `d41d8cd9` |
| normal_day | 171717 | 12 | `7872892a` | `987713b4` | `c83d7288` | `83527ba2` | `d41d8cd9` |
| busy_day | 424242 | 12 | `67ee1af6` | `99acbc31` | `c83d7288` | `f77e42b1` | `d41d8cd9` |
| busy_day | 171717 | 24 | `5c9a64cd` | `531abd81` | `c83d7288` | `142ee120` | `d41d8cd9` |
| busy_day | 424242 | 24 | `99b6ee3f` | `d78b6c2d` | `9c25b338` | `62b9301c` | `d41d8cd9` |

Two boot fingerprints instead of six (0194), not yet one. The 424242/24t retro
`h_prop` moved with its `h_cmd` (`5f0d8281` → `62b9301c`): the proposers saw the
same coin the disposer did.
