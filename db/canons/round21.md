# Round 21 canons — 2026-09-06 (fired 3:48–6:13 PM CT)

Flagship depot, pinned sim start `2026-09-01 02:00:00+00`, proposer quiesced.
Engine as of **0202** (3:37 PM CT), **0203** (3:39 PM CT) and **0207** (3:42 PM CT, the
recertification floor). Nine pairs: 171717/24t, 314159/12t, 171717/12t, normal_day/171717/12t
and 424242/12t, then repeats of the four 12-tick columns, then 424242/24t.

**Nine of nine passed.** Round 20's failure (171717/24t, the refusal-walk tie) is repaired.
Every arm carries `h_rule`, 0203's new instrument, and the two arms agree on it in all nine
pairs — the gate 0205 needs to promote it into the verdict.

**Every canon moved once**, and each of the four columns that ran twice reproduced its new
value exactly. That was not the prediction; see the correction below and `db/checks/0117`.

| scenario | seed | ticks | h_cmd | h_dec | h_bkg | h_nrg | h_prop | h_rule | h_defr | h_cal | vs r20 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| busy_day | 314159 | 12 | `109e340b` | `9abdb4af` | `174b8835` | `a9c6b693` | `a79c1095` | `333cf172` | `d41d8cd9` | `11a24626` | **moved once** (2 pairs, both) |
| busy_day | 171717 | 12 | `1ae7ba68` | `cf2f44e2` | `7146a8e1` | `08f719af` | `0046879e` | `5a6ee595` | `d41d8cd9` | `11a24626` | **moved once** (2 pairs, both) |
| normal_day | 171717 | 12 | `5921ef70` | `37624cdd` | `ed4a986c` | `17c9b12b` | `779e5a74` | `43cfd0a4` | `d41d8cd9` | `11a24626` | **moved once** (2 pairs, both) |
| busy_day | 424242 | 12 | `76134009` | `47757095` | `8bc2877b` | `9917f7c3` | `029cad7d` | `c3cca844` | `d41d8cd9` | `11a24626` | **moved once** (1 pair) |
| busy_day | 171717 | 24 | `050c4606` | `0360adc9` | `947a2316` | `4c5035fe` | `0046879e` | `62ed1a1e` | `d41d8cd9` | `11a24626` | **moved once**; round 20 FAILED here |
| busy_day | 424242 | 24 | `8f232001` | `35148055` | `ea8a12e2` | `c79957a5` | `aabef458` | `eb2fce86` | `d41d8cd9` | `11a24626` | **moved once** (1 pair) |

| scenario | seed | ticks | h_evt | fp (boot) |
|---|---|---|---|---|
| busy_day | 314159 | 12 | `a41175ba` | `803698f3` |
| busy_day | 171717 | 12 | `e15a20ab` | `92b02f8b` |
| normal_day | 171717 | 12 | `454e34a6` | `92b02f8b` |
| busy_day | 424242 | 12 | `638655b3` | `e418e4f0` |
| busy_day | 171717 | 24 | `be8ee6cb` | `92b02f8b` |
| busy_day | 424242 | 24 | `67cb213b` | `e418e4f0` |

The three boot fingerprints are unchanged from round 20, and `h_cal` is
`11a246262ff7a2c929483b1ee0a7cd2d` on all eighteen arms — the worlds booted identical and the
priors did not move (the next ingest is Sunday 09-13). `h_defr` is `d41d8cd9` (empty) on all
eighteen. `h_prop` moved on five of the six columns; 424242/12t's stayed `029cad7d`.
Pair wall time: 12-tick 9.9–13.4 min; 24-tick 21.1 and 22.0.

## The correction: 0207's prediction was right about the fix and wrong about its scope

0207's header predicted that only the three columns carrying a refusal tie in round 20
(314159/12t, 171717/24t, 424242/24t) could move, and that the other three **must not**. All six
moved. The migration was written from round 20's failure, which was a tie among *refused*
commands in `ottoq.ottoq_react_to_refusals` — a rare walk, 12 tied groups in round 20 and 8 in
round 21. But the same migration also replaced the sort keys of the three walks in
`twin.ottoq_sim_confirm_commands`, and those walk **every** same-tick same-stall duplicate
command, refused or not:

| | duplicate groups | of which refusal ties | arms | vehicles |
|---|---|---|---|---|
| round 20 | 244 | 12 | 18 | 32 |
| round 21 | 230 | 8 | 18 | 33 |

All of them are `proceed_to_stall`: the ordinary product of the decide path issuing a
`gate_intake` command and a staging command for one vehicle to one stall in one tick.

Measured on round 21's own rows: of its 230 duplicate groups, the **old** keys
(`payload::text`, then the random `command_id`) and the **new** key (`command_seq`) select a
different survivor in **214**, across all 18 arms. The old order was text order over the
payload; the new order is issuance order. That is why every canon moved, and the header should
have said so.

The engine is not worse for it. The surviving command is now the first one the decide path
issued — the intent it formed first — and the choice is a function of the run rather than of the
heap. But the prediction was wrong, and the honest reading of round 21 is *0207 moved every
canon, once, deterministically*, not *three columns may move*.

**First divergence traced.** 424242/12t moved `484900ed` → `af614e10`; the command streams first
differ at sim 02:30–03:30 (ticks 2–3), where round 21 enacts a `promote_ready` that round 20 held
as `hold_no_space`, and the reroute stall assignments differ from there. That is the signature of
a changed confirm-pass survivor one tick earlier: when the surviving command carries `new_state`,
the vehicle reaches `staged_awaiting_service` and is promotable; when it is the intake command,
the vehicle keeps `arrived_at_gate`. Round 20's `db/checks/0116` §3 describes the same mechanism
as the failure mode. 0207 made it a decision instead of a coin.

## Standing

At the 0207 floor: 314159/12t, 171717/12t and normal_day green (two consecutive passes);
424242/12t, 424242/24t and 171717/24t one pass each. **Round 22 must reproduce every h_cmd in the
table above.** A column that moves again has a second carrier and 0207 did not close it.

The floor moves again with 0204 (sim clock in the event stream and in the shield — `h_evt` moves
everywhere by design), 0205 (`h_rule` promoted into the verdict) and 0206 (the recall ledger,
`h_rcl` measured).
