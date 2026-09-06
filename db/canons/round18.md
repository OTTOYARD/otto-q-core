# Round 18 canons — 2026-09-05 (fired 12:40–2:08 PM CT)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0197** (applied 12:35 PM CT, forces_recert). Seven pairs:
normal_day/171717/12t twice. **Seven of seven passed. Every cell identical to
rounds 16 and 17** — 0197 changed the decide path and moved nothing, as its footer
predicted.

> Written 2026-09-06 from the verdict rows (see round14.md). Retro columns computed
> with 0199's hash functions. From round 19 on, `h_prop` and `h_defr` are written
> by the pair itself and belong in the first table.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | vs r17 |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `80183641` | `6e116d5b` | `b1d72a62` | `625014b7` | identical |
| busy_day | 314159 | 12 | `cf74d080` | `1788ee1c` | `eaff0912` | `4afd1004` | identical |
| normal_day | 171717 | 12 | `af8b5e6d` | `3a8719f8` | `2c7e0a3a` | `de3b353e` | identical (2 pairs, both) |
| busy_day | 424242 | 12 | `adf745a2` | `05bc65e6` | `84a9b51c` | `0cac7e0b` | identical |
| busy_day | 171717 | 24 | `38465601` | `09769827` | `3b52ea78` | `7606aaf2` | identical |
| busy_day | 424242 | 24 | `997e2c37` | `fd484142` | `f597a790` | `f2b72ada` | identical |

| scenario | seed | ticks | h_evt | endst (md5) | boot chargers | h_prop (retro) | h_defr (retro) |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `4f8b2970` | `31887429` | `e06b403e` | `142ee120` | `d41d8cd9` |
| busy_day | 314159 | 12 | `25cf62c5` | `d0870a7a` | `e06b403e` | `b32df53d` | `d41d8cd9` |
| normal_day | 171717 | 12 | `0beff613` | `ccb2e2c1` | `e06b403e` | `83527ba2` | `d41d8cd9` |
| busy_day | 424242 | 12 | `67ee1af6` | `5ec725ad` | `e06b403e` | `f77e42b1` | `d41d8cd9` |
| busy_day | 171717 | 24 | `61d5ff27` | `9b986ebb` | `e06b403e` | `142ee120` | `d41d8cd9` |
| busy_day | 424242 | 24 | `2c51bb4c` | `7076e486` | `e06b403e` | `62b9301c` | `d41d8cd9` |

Standing after this round: canons for 171717/12t, normal_day and 171717/24t stable
r14–r18; 424242/12t and 424242/24t stable r15–r18; 314159/12t stable r16–r18.
Inter-pair reproducibility shown on three columns (171717/12t in r15 and r16,
314159/12t in r17, normal_day in r18). At the floor 0199 corrected (0197's apply),
this is the FIRST round; round 19 makes two.
