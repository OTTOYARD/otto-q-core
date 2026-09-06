# Round 14 canons — 2026-09-04 (fired 2:06–3:30 PM CT)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0193** (0192 and 0193 applied 10:00 AM and 12:23 PM CT). Six pairs,
one per column. **One pair failed**: busy_day/314159/12t — the carrier 0195 named
and removed the next round (a bay-queue order drawn fresh each run).

> Written 2026-09-06 from the verdict rows, not at the end of the round as the
> README requires. Rounds 14–18 were never committed here; this file and the four
> after it close that gap. Values are the verdicts' own; the two retro columns are
> computed on 2026-09-06 with 0199's `ottoq_hash_proposals` / `ottoq_hash_deferrals`
> over the rows the arms wrote.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | vs r13 |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `80183641` | `6e116d5b` | `b1d72a62` | `625014b7` | moved (0192/0193) |
| busy_day | 314159 | 12 | `cf74d080` | `1788ee1c` | `eaff0912` | `4afd1004` | **failed** — arm A shown |
| normal_day | 171717 | 12 | `af8b5e6d` | `3a8719f8` | `2c7e0a3a` | `de3b353e` | moved (0192/0193) |
| busy_day | 424242 | 12 | `63f1dbe1` | `a0f541c2` | `5a227276` | `0cac7e0b` | moved (0192/0193) |
| busy_day | 171717 | 24 | `38465601` | `09769827` | `3b52ea78` | `7606aaf2` | moved (0192/0193) |
| busy_day | 424242 | 24 | `ec2fd827` | `e8367a52` | `f283c927` | `e30295d3` | moved (0192/0193) |

Every canon moved from round 13: 0192 and 0193 were forces_recert changes to the
decide path, so this round is a new baseline, not a comparison. The 314159 pair
failed on the pair's own hashes; its retro `h_prop` also differs between arms.

| scenario | seed | ticks | h_evt | endst (md5) | boot chargers | h_prop (retro) | h_defr (retro) |
|---|---|---|---|---|---|---|---|
| busy_day | 171717 | 12 | `4f8b2970` | `959e364a` | `bce038e9` | `142ee120` | `d41d8cd9` |
| busy_day | 314159 | 12 | `25cf62c5` | `f11217ca` | `bb34f348` | `b32df53d` (arms differ) | `d41d8cd9` |
| normal_day | 171717 | 12 | `7872892a` | `80dce053` | `fcff0017` | `83527ba2` | `d41d8cd9` |
| busy_day | 424242 | 12 | `0cd28481` | `7a12fea5` | `0c369653` | `f77e42b1` | `d41d8cd9` |
| busy_day | 171717 | 24 | `5c9a64cd` | `6926ed85` | `dacf601f` | `142ee120` | `d41d8cd9` |
| busy_day | 424242 | 24 | `ce532fe2` | `fc05187d` | `0a0a8f49` | `5f0d8281` | `d41d8cd9` |

Six different boot fingerprints in one round: the world the arms booted from was
not the same world column to column. 0194 (three wall clocks in the world the
fingerprint hashes) is the fix; see round 15 and 16. `d41d8cd9` is md5 of the
empty string — no deferral rows in any arm, as the 0152 quiesce intends.
