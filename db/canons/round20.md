# Round 20 canons — 2026-09-06 (fired 10:56 AM–12:52 PM CT)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0200** (applied 10:51 AM CT; the recertification floor) and **0201**
(10:40 AM CT, harness only). Nine pairs: 314159/12t, 171717/12t and normal_day/171717/12t
twice each. **Eight of nine passed. Pair 8, busy_day/171717/24t, FAILED: its arms
diverged at sim 11:30.** Convicted in `db/checks/0116`; fixed by 0207.

First round on the post-refit priors for 314159/12t and 171717/12t (their round-19 pairs
ran before the 11:05 PM CT ingest, see `db/checks/0115`), so those two moved once and then
agreed with themselves. The four columns that already had a post-refit pass reproduced
round 19 exactly, including arm A of the pair that failed.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | h_prop | h_defr | h_cal | vs r19 |
|---|---|---|---|---|---|---|---|---|---|---|
| busy_day | 314159 | 12 | `9fa71d19` | `1fa3e10e` | `c568aa7c` | `fec46a84` | `4469caa1` | `d41d8cd9` | `11a24626` | **moved once** (first post-refit pass; 2 pairs, both) |
| busy_day | 171717 | 12 | `93e895e6` | `c52f45a6` | `5510a9d0` | `2c2bef25` | `2574c54f` | `d41d8cd9` | `11a24626` | **moved once** (first post-refit pass; 2 pairs, both) |
| normal_day | 171717 | 12 | `634a8781` | `5a3da552` | `97056af3` | `b3a22762` | `940d3890` | `d41d8cd9` | `11a24626` | identical (2 pairs, both) |
| busy_day | 424242 | 12 | `adf745a2` | `05bc65e6` | `c4df69ab` | `481f8320` | `029cad7d` | `d41d8cd9` | `11a24626` | identical |
| busy_day | 171717 | 24 | `5dd1816d` (arm A) | `65136383` | `38ffdbe8` | `5b96f9b9` | `2574c54f` | `d41d8cd9` | `11a24626` | **FAILED**: arm B `e6cbbdeb` / `42a9c00e` / `3c29dd21`; nrg, prop, defr, cal equal |
| busy_day | 424242 | 24 | `997e2c37` | `fd484142` | `1e5f1875` | `fd6cfd0a` | `bea94486` | `d41d8cd9` | `11a24626` | identical |

| scenario | seed | ticks | h_evt | fp (boot) |
|---|---|---|---|---|
| busy_day | 314159 | 12 | `36bb019a` | `803698f3` |
| busy_day | 171717 | 12 | `efca8183` | `92b02f8b` |
| normal_day | 171717 | 12 | `66c2fcf1` | `92b02f8b` |
| busy_day | 424242 | 12 | `67ee1af6` | `e418e4f0` |
| busy_day | 171717 | 24 | `599d68db` (A) / `f33eb3ae` (B) | `92b02f8b` (both) |
| busy_day | 424242 | 24 | `2c51bb4c` | `e418e4f0` |

`h_cal` is `11a246262ff7a2c929483b1ee0a7cd2d` on all eighteen arms: the first round the
verdict names its priors, and the priors did not move (the ingest guard of 0201 stood; the
next ingest is Sunday 09-13). Pair wall time: 12-tick 9.0–12.6 min; 24-tick 19.6 and 18.0.

**The failure.** Arms b8f98769 / ab7c7139 booted the same world and agreed through tick 19.
At sim 11:30 the decide path issued two `proceed_to_stall` commands for vehicle 0d43459d to
the same staging stall; both were refused `target_occupied`; the refusal walk's ORDER BY
(`issued_at, vehicle_id, command_type, stall`) cannot tell them apart, so physical row order
decided which reroute survived, and the arms decided differently. One command carried
`new_state = staged_awaiting_service`; the other did not. Everything downstream of that
vehicle's state diverged. The tie occurred in 8 of the round's 18 arms and was resolved
alike in the other seven pairs by chance. 0207 adds `command_seq` (issuance order) as the
last key of that walk and of the three walks in the confirm pass.

**Standing.** At the 0200 floor: 314159/12t, 171717/12t and normal_day green; 424242/12t and
424242/24t one pass; 171717/24t failed. The floor moves again with 0202, 0203 and 0207
(round 21). Prediction for round 21 is in 0207's header: 171717/24t passes; the three
columns that carried a tie group in round 20 may move once; the other three must not.
