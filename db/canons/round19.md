# Round 19 canons — 2026-09-06 (fired 10:43 PM–12:11 AM CT, Sep 5/6)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0199** (0198 at 10:21 PM CT, 0199 at 10:39 PM CT; neither touches an
engine function — both pinned). Seven pairs: normal_day/171717/12t twice. **Seven of
seven passed.** First round with `h_prop` / `h_defr` written by the pair itself.

**The weekly calibration ingest ran at 11:05:25 PM CT, between pair 2 and pair 3**, and
re-fitted the NOAA ambient-temperature and precipitation grids and the EIA grid-demand
grid and shape. Pairs 1–2 ran on the round-18 priors; pairs 3–7 on the new ones. See
`db/checks/0115`.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | h_prop | h_defr | vs r18 |
|---|---|---|---|---|---|---|---|---|---|
| busy_day | 314159 | 12 | `cf74d080` | `1788ee1c` | `eaff0912` | `4afd1004` | `2b86847e` | `d41d8cd9` | identical (pre-refit) |
| busy_day | 171717 | 12 | `80183641` | `6e116d5b` | `b1d72a62` | `625014b7` | `2574c54f` | `d41d8cd9` | identical (pre-refit) |
| normal_day | 171717 | 12 | `634a8781` | `5a3da552` | `97056af3` | `b3a22762` | `940d3890` | `d41d8cd9` | **moved** (post-refit; 2 pairs, both) |
| busy_day | 424242 | 12 | `adf745a2` | `05bc65e6` | `c4df69ab` | `481f8320` | `029cad7d` | `d41d8cd9` | **bkg/nrg moved**, cmd/dec same (post-refit) |
| busy_day | 171717 | 24 | `5dd1816d` | `65136383` | `38ffdbe8` | `5b96f9b9` | `2574c54f` | `d41d8cd9` | **moved** (post-refit) |
| busy_day | 424242 | 24 | `997e2c37` | `fd484142` | `1e5f1875` | `fd6cfd0a` | `bea94486` | `d41d8cd9` | **bkg/nrg moved**, cmd/dec same (post-refit) |

| scenario | seed | ticks | h_evt | endst (md5) | boot chargers |
|---|---|---|---|---|---|
| busy_day | 314159 | 12 | `25cf62c5` | `d0870a7a` | `e06b403e` |
| busy_day | 171717 | 12 | `4f8b2970` | `31887429` | `e06b403e` |
| normal_day | 171717 | 12 | `66c2fcf1` | `e4543944` | `e06b403e` |
| busy_day | 424242 | 12 | `67ee1af6` | `0838b39d` | `e06b403e` |
| busy_day | 171717 | 24 | `599d68db` | `89d7b898` | `e06b403e` |
| busy_day | 424242 | 24 | `2c51bb4c` | `84fd8d3f` | `e06b403e` |

`h_prop` here is the first live proposal canon. The retro values in round14–18.md were
computed over rows written before 0198 added `declared_source`; they are not comparable
and are not canons. Note `h_prop` is identical for 171717/12t and 171717/24t: the
proposal stream for that seed is complete within the first twelve ticks.

**Standing.** The four moved columns have one pass at the new priors; 314159/12t and
171717/12t have none yet. Round 20 runs after 0201 (calibration fingerprint + ingest
guard) and 0200, with those two columns run twice. The certificate's honest sentence
today: the engine reproduces itself to the byte when its priors do not move, and the
instrument could not see the priors move. 0201 fixes the second half.
