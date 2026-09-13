# CERTIFICATION_STATUS — the deterministic core is v1-certified and frozen

*Written 2026-09-12 23:29 UTC off `db/canons/round40.md`; **round 41 appended 2026-09-13
04:40 UTC off `db/canons/round41.md` — read §"Round 41" before quoting the matrix below,
because six flagship `endst` values in it are superseded.** This is D1's evidence page
(`V1_DEMO_PLAN.md` §3): same inputs, byte-identical outputs, verified across fourteen
independent atoms, on nine columns, in two consecutive rounds. Every number below has a run
id next to it.*

## The stopping rule, and how it was met

`V1_DEMO_PLAN.md` Phase 0: *"when all seven flagship columns agree across two consecutive
rounds once, the core is v1-certified. After that, certification is a regression gate that
runs on its own schedule. No new instruments. No new atoms."*

| | round 39 | round 40 |
|---|---|---|
| fired (UTC) | 17:40 → 19:55, ten pairs | 21:05 → 23:20, ten pairs |
| pairs passed internally | 10 / 10 | 10 / 10 |
| arm runs `validation_status = passed` | 20 / 20 | 20 / 20 |
| atoms moved, round over round, any column | — | **0 of 14, in every column** |
| the two 48t pairs agree with each other | yes (`0193` bar) | yes |
| `wsec` (MEASURED world sections) identical | — | yes, every column |
| 0176 §6.1: flagship `last_state_change` after the last pair | one value, 116 vehicles, sim domain | one value, 116 vehicles, sim domain |
| `ottoq_cert_coverage()` | 9 / 9 OK | 9 / 9 OK |

Judged in `db/canons/round39.md` and `db/canons/round40.md`; the predictions for round 39
were committed before it fired (`db/checks/0183`).

**Round 41** (`db/canons/round41.md`, fired 01:55 → 04:10 UTC on 2026-09-13, ten pairs):
10/10 pairs passed, 20/20 arms passed, the two 48t pairs agree with each other for the third
round running, and **thirteen of the fourteen atoms are byte-identical to round 40 in all
nine columns**. One atom moved, in the six flagship columns, by one number:
`endst.legs.fgn.n` went 13 → 9 — a count of *other runs'* itinerary legs left in live
states, which is in the fingerprint on purpose (`0125`, the cross-run hazard set). Nothing
the engine computes moved. See §"Round 41" below.

## What is under the certification

The recert floor is **`2026-09-12 16:50:23.319089`**, set by `0256` (`forces_recert TRUE`,
the last migration that changed a hashed value). Every canon below is above that floor.
Applied above the floor and measured by these two rounds:

| version | migration | forces_recert | measured by |
|---|---|---|---|
| 20260912165023 | `0256` the trigger re-stamps what the teardown fixed | **TRUE** (set the floor) | round 39 (P1–P3 confirmed), round 40 |
| 20260912165137 | `0257` the second floor ships as a count | FALSE | rounds 39–40: 0 atoms moved |
| 20260912165243 | `0258` the comment states the invariant and no code holds it | FALSE | rounds 39–40: 0 atoms moved |
| 20260912205202 | `0259` the proposer seat is declared data, not three literals | FALSE | round 40: 0 atoms moved vs round 39 |
| 20260912205301 | `0260` every proposer fire is a ledger row | FALSE | round 40: 0 atoms moved vs round 39 |
| 20260912233647 | `0261` the proposer seat (A/B pair rig, `p_policy`) | FALSE | round 41: `h_prop`/`h_defr` byte-identical in all 9 columns |
| 20260913011239 | `0262` the hold key the setter refused (`proposer_hold_enabled`) | FALSE | round 41: 0 engine atoms moved vs round 40 |

The certified tick path is the deterministic core alone: `cuopt_propose_enabled = 0` and
`cuopt_first_refusal_max_defers = 0` run-scoped inside every arm (`0152`); Posture A refuses
any proposer not in `ottoq_certified_proposers` (`0241`: `greedy_constrained`,
`ottoq_service_priority`, `cuopt`). A nondeterministic proposer reaches a certified run only
by record-and-replay (`0237`/`0239`).

## The matrix — canon per column, with the run ids that produced it

`SELECT * FROM ottoq_cert_matrix('2026-09-12 16:50:23.319089')`, read 23:29 UTC.
`consecutive_passes` counts pairs above the floor; the 48t column runs twice per round.

**STALE AS OF ROUND 41, in one column only.** The last hash on every flagship row below is
`endst`, and round 41 rebased all six of them because `endst.legs.fgn.n` moved 13 → 9. The
round-41 `endst` values are, by column: busy/314159/12t `147e1b1ca4faf8e8b7f6f761d8888316`,
busy/171717/12t `11243f0b55301074b7cf87f37504ea8f`, normal/171717/12t
`b7baf8bdc1b0814f4e07300bba2db291`, busy/424242/12t `c3b0d1b55008f0b961ce5d85dcd5e633`,
busy/171717/24t `e55821cae2bafafe71c0c05e4b9d2816`, busy/424242/24t
`343bd724e48e2635de94f1148bf09261`, busy/171717/48t `063e6d957816da878083db1a3a900ddb`.
The two grid rows are unchanged. Every other hash on every row is unchanged.

| lane | column | consecutive_passes | green | history | round-40 runs (arm a / arm b) | canon: `fp` `h_cmd` `h_dec` `h_evt` `h_bkg` `h_nrg` `h_prop` `h_defr` `h_cal` `h_rule` `h_rcl` `h_sdr` `endst` |
|---|---|---|---|---|---|---|
| grid | grid_smoke/239001/6t | 2 | t | PP | b24d1483-cb55-4bac-a77d-602e667fe02d / 722a74d5-3254-4209-aee4-c8158222ecb5 | `66275ea7a5d8711f45be206faeae5e7c` `0c6eadd40b3e5991a7dbf5a00669d45a` `c16074c6a8f136965666c009a3176eb9` `162997d702edd557d45cb0470209f59b` `bff0499da0e21550020a60db1f7b2036` `93e74c9cc28d273007aa6c2f7f654092` `d41d8cd98f00b204e9800998ecf8427e` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `9ec9ff51c925e3d1344b40074dd9037a` `c0faa97c3f609b37798c24e7457c6b5c` `26c63b1e6e05e35dae80beb2ab413f2c` `fc792a7b0584d84740309c18f3c30cb6` |
| grid | grid_smoke/424242/6t | 2 | t | PP | 8195644a-9741-4eb9-b870-7fb46df3bca0 / 84580c44-9acf-4da2-b629-e667ba29ab96 | `4cac51f07219cfef534f5cebd1bfd015` `e4158c95dd63e8cdacfda45d72ba8b9e` `c37ba832579b2ff28717d8fa4e991da8` `79fa107a6ee78f6648173e576e95c83d` `2c955357cc2f86855f2f626a45b2df63` `beb1b3911be6686346188a62ab366ad3` `d41d8cd98f00b204e9800998ecf8427e` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `d62d9672ae4f573a3017f793790270ce` `f981b17b44688c7e69ac1506a0cc1fa2` `3155fc31a48dba1880da0535654f3573` `ef60bfa333221b6856084ebb9569e8db` |
| flagship | busy_day/171717/12t | 2 | t | PP | c3aca420-e553-472c-a432-43880d9ea7cf / bacd24c7-bb94-423e-a4fc-980cc26f2ba9 | `9c28854e976c8572f2cc1bf4717f85b0` `1ae7ba68df0af15ea6e8ee5e7a6cf23e` `cf2f44e29bd03549ea9f189ff135a675` `e16ad96493775bfb8606b33a6e658d8a` `7146a8e13e91370836301fbb95b2ec5f` `08f719afbd862a9fb7aad5ae15a6d8c8` `0046879e58222bc394d9beee36f4155b` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `3e57f511cb80f6edd1ea194e17874470` `0a4ca4d3c72a6515a437117709ac3783` `a2a35e035f4df12f3d5055800a3c5e09` `b250e8fa7bfb0ea8fc40e6b8a23f7b79` |
| flagship | busy_day/314159/12t | 2 | t | PP | bd8d0b0e-58c2-448d-aa54-bb1ff4fb2aba / 36e32de4-0f62-4a03-80c2-c5e91ddc3547 | `b8606125f1cbd5c820fc9be94c4c4a29` `109e340b04a1ebd5175f584269dd398c` `9abdb4afb2d172f50821158698fd26be` `9c631343c32cca7a861b17bc5bc8f4b7` `174b88355d034533c8e711efecffc1b3` `a9c6b69379127aa6e9dfa38dd8bf019b` `a79c109534aed71bd65ad0741e0c76d0` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `fc69953b7ea27f5b2217621a46cf68e6` `0e67b89a32cfb089d1ff827fbf928d9d` `a1f79c20a2ecd2ee7853d6c15836bc5e` `e46c7ff4cd58b5b95949716b1c641ab1` |
| flagship | busy_day/424242/12t | 2 | t | PP | 35c1a030-7fa2-4cdf-88dc-66e896693c66 / 642a1251-bd75-4140-8f16-5f088283973b | `7a14aa522a65cc196ca486309194573c` `76134009785a4644bdfd7904abb15893` `47757095390ee3acaf6fa4e28d802e8f` `6453c09bb1fc4693cf48acc3588a03b6` `8bc2877b48c42fcca3293ba516bb228f` `9917f7c3fd22d7386d666d08976bb5b9` `029cad7dc3b3d84246896d9f24914c17` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `d56e09a30bac411c464a7193b35c03d4` `f58ee562af9c85aed33d29b7171b0746` `6fd75365723a2e7ae39152175e9cb7c9` `349257e19901cf24cc3915d00402a04c` |
| flagship | normal_day/171717/12t | 2 | t | PP | e2856720-0cc3-4116-aa3a-76a406500be3 / fc8e219d-3298-406d-bd6f-3e55cb54025b | `9c28854e976c8572f2cc1bf4717f85b0` `5921ef70f7a01b353d4ffbbe044bd801` `37624cdd69a92b9ee806103655c5eb61` `ac672423a3478cd1b806cb11619d375f` `ed4a986ccb9198cf0601d968533876a4` `17c9b12bc49ad835876df2229ce78651` `779e5a7499c39487793784290ac900b1` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `5b1d1dfa9f391c64052705a0da471017` `e4e41e69c2db2ff3ca873a0a8a84f0db` `e0dfbbe8dddc208b6cb1061f718899df` `3b2744f4377f937e796bb9384f79f9f6` |
| flagship | busy_day/171717/24t | 2 | t | PP | a8cf7984-a17d-43bf-964a-8bb48acd6dc3 / f04be8ad-4bf1-4f96-8841-aaa011fc8333 | `9c28854e976c8572f2cc1bf4717f85b0` `050c46069e97d36938ae3202e02b2868` `0360adc952cfb784e70007cae3f08856` `b2230619d5eb5327c52d386894735fe4` `947a23169eeabde514b759a00b0b443c` `4c5035feb4367b2c582e715832be8fc0` `0046879e58222bc394d9beee36f4155b` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `9564b99852ab36b5d6ee13562c36ef8a` `fa8ab72cb953569216afea5182054f75` `957abcfbfdd8559a75e03f9037bf2ce3` `5e63d8f861cf8b34dc947d9f194e66fa` |
| flagship | busy_day/424242/24t | 2 | t | PP | 7a81cfbe-3f8d-495b-9a39-8bf98c65876d / 4df2377d-cd28-4259-b7eb-808ef8a6db18 | `7a14aa522a65cc196ca486309194573c` `8f23200140e3faa48568abea079e264c` `351480557c2a2683b5422006bedfcae0` `8dc37f824db7410f0d08cda0b2135fe2` `ea8a12e2b4ef3fde9a0ee6c976c8c11e` `c79957a5f9e17847156c8f777152afe5` `aabef458505fdd06bca8a81dc18a7cf7` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `726f6769385c8c01bba4bcd092053e70` `928262d2f500216934fce4c1908ce93f` `f2587dbcc6cad07788c7a0eb0934f7e6` `3550457a9a71acc53ed0d623a3640d17` |
| flagship | busy_day/171717/48t | 4 | t | PPPP | a340144d-c793-4426-9658-5c887ced583a / f8bd897c-271f-4c63-a505-639520ef3f6b | `9c28854e976c8572f2cc1bf4717f85b0` `5727d4463c4a43b06d31dcda148ffee6` `7a8ac80fe85632a4abbbf22681d0a4f9` `39b36da32d7dc62375cab8069f003d42` `a8910602872bdbb6571f8871787daf0e` `dd96089d0cbff031c6c347a6d74199f0` `f260e51f5f5020f43f0fbcc57632c7ff` `d41d8cd98f00b204e9800998ecf8427e` `11a246262ff7a2c929483b1ee0a7cd2d` `c8ff19af57168281c33de1505ac531ac` `d66783aaa0228b3102aaf5b4ec63ebda` `262c354a31998a9aae9628414e6a067d` `02553f44c0facba44b179da7df0aa164` |

The 48t column's second round-40 pair (22:48 UTC) is `b65c84a8-5d3a-447f-8c30-7f001e604340` / `9f680f53-84e5-415a-a7de-65e0c59a5c8b`; round 39's pairs are named in `db/canons/round39.md`.

The fourteen atoms, by name: `fp` (the world fingerprint at run start), `h_cmd` (vehicle
commands), `h_dec` (decisions), `h_evt` (signed events), `h_bkg` (stall bookings), `h_nrg`
(energy commands), `h_prop` (proposals), `h_defr` (deferrals), `h_cal` (calibration priors
the arm booted on), `h_rule` (L1 rule evaluations), `h_rcl` (recall decisions), `h_sdr`
(service detail records), `ticks`, `endst` (the id-blind end-state fingerprint).
`d41d8cd9…` is the md5 of the empty string: no deferrals in any certified arm, no proposals
on the grid fixture.

## How to re-derive any line here

```sql
-- one pair, exactly as the rounds run it (a certification arm, both arms in one transaction):
SELECT public.ottoq_determinism_pair(171717, 12, 'busy_day',
         '11111111-1111-1111-1111-111111111111'::uuid, '2026-09-01 02:00:00+00'::timestamptz, 900);
-- the matrix above:
SELECT * FROM public.ottoq_cert_matrix('2026-09-12 16:50:23.319089'::timestamptz);
-- a round: scripts/schedule-round.sql lays out the ten slots from measured durations.
```

Never while another pair or a demo run holds the same depot; `pg_stat_activity` is the only
authority for in-flight.

## What "frozen" means from here

- Certification continues as a **regression gate**: a round after every migration that
  touches the tick path. **Round 41 measured `0261` and `0262` and acquitted both.**
  **Round 42 is not scheduled** until G46 (below) is decided — another round now would
  re-measure the same ambiguity rather than resolve it.
- Every migration carries a `forces_recert` classification in `ottoq_cert_lineage`; TRUE
  moves the floor and voids every canon; FALSE is a prediction the next round judges. A
  column that moves under a FALSE migration convicts the migration, not the round.
- No new certification instruments, no new atoms (Phase 0 rule). A blind spot found later
  is logged in `BUILD_QUEUE.md` and fixed in Phase 4 unless it breaks D1.

## Round 41 — and the one defect it exposed (G46)

Round 41 is the cleanest engine result yet and the first round that found a hole in the
*instrument*:

| | round 40 | round 41 |
|---|---|---|
| pairs passed internally | 10 / 10 | 10 / 10 |
| arm runs passed | 20 / 20 | 20 / 20 |
| engine atoms moved vs the previous round | 0 of 14 | **0 of 13** (`fp h_cmd h_dec h_evt h_bkg h_nrg h_prop h_defr h_cal h_rule h_rcl h_sdr ticks`) |
| `endst` moved | no | **yes, six flagship columns, one section** |
| `consecutive_passes`, flagship 12t/24t | 2, green | **1, not green** |
| `consecutive_passes`, 48t / grid | 4 / 2, green | 2 / 3, green |

**G46 — the canon rebases when another run's residue moves.** `endst` contains `fgn`
sections: other runs' rows still in live states, put there by `0125` because unscoped reads
of run-scoped tables (the `0145` class) are how foreign rows reach a run's decisions.
`ottoq_cert_matrix` takes the newest pair as canon and walks back while all atoms match, so
a change in a *foreign* row count breaks the streak and silently installs a new canon. Last
night's D2/D3 runs on the flagship depot did exactly that: 13 foreign live legs became 9
(four closed by a later run's supersede), and six columns went from green to streak 1 with
no engine change at all.

Three consequences, all measured in `db/canons/round41.md`:

1. Any demo or A/B run on the flagship depot can de-green every flagship column.
2. The canon now carries `fgn.n = 9` and will rebase again when that number next moves.
3. The residue is real and unowned: nine legs from a run that **completed on 2026-08-29**
   are still `planned`. Nothing closes a finished run's legs — G13's janitor gap, now
   measured on flagship.

The fix is not to stop measuring foreign residue. Two candidates are written up in the canon
(retire the residue then report non-zero residue as `inconclusive`; or judge the canon on the
run's own sections while reporting `fgn` loudly). Neither is applied; both need the
adversarial review that `0259`/`0261` got, and G25 is the warning about reported-not-judged
atoms.

## Known and deferred — listed, not hidden

From `V1_DEMO_PLAN.md` and `BUILD_QUEUE.md`: **G8** outbound command lifecycle, **G9** a
producer for the forward power schedule, **G10** SDR terminus binding, **G12** CI runs the
SQL, **G13** the Benchmark depot's phantom holds, **G14** calibration priors outside the
reproducibility key, **G26** production and the proof harness share one database, **G46** the canon rebases on
another run's residue (round 41, open), **4h/4i**
(the objective-function reconciliation and R-13). **S-01/S-02** (a committed shared secret;
the code half is fixed and pinned by a test, rotation is a founder action) remain open.

What this page does not claim: nothing about throughput, safety or cost. Those are D2's
numbers and come from the A/B pair (`policies/AB_TWIN.md`), each with its own run id.
