# lab/safety: the synthesized post-cell supervisor (E3 v0)

`docs/FRONTIER_PLAN_2026-11-03.md` (branch `claude/frontier-plan-certified-intelligence`) asks for E3's first
deliverable. It is the G506 cell: one robotic DC fast-charging post with its charge arm and its cabin-cleaning arm,
requirements R1–R6, a synthesized supervisor, and monitors replayed on demo run `8c0b2e04`. This directory is that
deliverable. It is research-wing work: it reads evidence and changes nothing in the engine (rule 10). Every database
read was a SELECT.

## What is here

| path | what |
|---|---|
| `models/post_cell_plant.cif` | the plant: 8 automata, 13 controllable and 12 uncontrollable events, with each element mapped to its SQL function, migration or renderer file |
| `models/post_cell_requirements_base.cif` | R1, R3a–R3d, R4, R5 (both variants) |
| `models/post_cell.cif` | the cell with R2: the requirement set as built after 0792 |
| `models/post_cell_pre0792.cif` | the same cell without R2: the hold 0760 added, which ignored why the charge ended |
| `models/post_cell_strict_r2.cif` | a sensitivity variant: R2 read literally (no hold at all on an out-of-service post) |
| `synthesize.sh` | reruns synthesis and the explicit state-space explorations into `synthesis/` |
| `synthesis/*.sup.cif`, `*.synth.log` | the controlled systems (cifdatasynth output) and their console logs |
| `synthesis/*.statespace.cif` | explicit state spaces (cifexplorer) of each controlled system, of the bare plant, and of the plant restricted by its requirements alone |
| `analyze_synthesis.py` → `synthesis/summary.json`, `SUMMARY.md` | what each supervisor disables, re-checked from the state spaces |
| `extract_trace.sql` | the read-only extraction of the traces |
| `fixtures/8c0b2e04/` | the six faulted posts' traces, the run's tick clock, and `MD5SUMS` (each file matched the md5 the database computed over the same text) |
| `monitor.py` | the R1/R2 monitor over one post's trace (primary) |
| `replay.py` | replays each car's visit through a synthesized supervisor's state space |
| `tests/test_post_cell_supervisor.py` | pytest; the three tests that run ESCET skip without it |

## ESCET

Eclipse ESCET **v13.0**. The tools report `13.0.0.v20260930-072049`. It was downloaded on 2026-11-03 from
https://download.eclipse.org/escet/v13.0/eclipse-escet-v13.0-linux.gtk.x86_64.tar.gz, which is listed on
https://eclipse.dev/escet/download.html (the latest release there, published 2026-09-30). The file is 303,164,708
bytes. Its SHA-512 is `d82848f6…cf619256`, which matches the checksum Eclipse publishes at
https://www.eclipse.org/downloads/sums.php?file=/escet/v13.0/eclipse-escet-v13.0-linux.gtk.x86_64.tar.gz&type=sha512.
It is unpacked under `/home/user/escet/v13.0/` and was run headless with the container's OpenJDK 21. The tools used
are `cifdatasynth` (data-based synthesis: BDD-based, maximally permissive, controllable, nonblocking) and
`cifexplorer`.

## The model (what it covers)

There is one post and one car's visit, from "assigned to this post" to "gone".

- **Charger** (`ottoq_ocpp_chargers.station_state`): Available, Occupied, Faulted, UnderRepair.
  - `OutOfService` = Faulted or UnderRepair. The engine's single `'Faulted'` covers both.
  - A dead charger can still be *commanded* to mate. R1 is what forbids it.
- **ChargeArm** (the `arm.*` events): Stowed → Approach → Insert → Latched → Unlatch → Extract → Retract → Stowed.
  - There is an abort while mating.
  - `c_emergency_release` models the stop path's re-queue branch.
  - The connector is never pulled while a session is open.
- **CleanArm** (the `interior_tidy` atom `performed_by 'stall_cabin_robot'`): Home → DoorsOpen → OverCar → Returning → Home.
  - It follows the renderer's `home | doors_open | out over the car | doors_close` chain.
  - `c_clean_abort` ends the step early, with no credit.
- **Tether** (`vehicles.robotic_tether_*`): None, Mate, Charging, Demate, Expired, Held.
  - The sweep `public.ottoq_release_expired_tethers` decides at Expired: either `c_release`, or `c_hold`, which keeps the car this tick (the hold 0760 added).
  - `u_tick` brings a held car back to the next sweep.
- **Sweep**: the model's one timing assumption. Once a demate tether has expired, the sweep decides within that tick, before anything uncontrollable moves.
- **Car** (`vehicles.current_stall_id`): Inbound, AtPost, OnCharger, Left, Ready (marked), Requeued (marked).
- **Battery** (Below, Full) and **Cabin** (Dirty, Clean) hold the car's needs (rule 9).

Controllable events are what the engine or the post's robot controller decides: admit, mate start or abort, stop a
charge, unlatch, emergency release, start, enter or abort a clean, hold, release, depart ready, re-queue.
Uncontrollable events are physics, time and the world: fault, repair start, repaired, the arm phases (at inlet,
latched, unlatched, extracted, cleared), charge complete, clean finished, clean home, and the tick.

| | requirement | stands for |
|---|---|---|
| R1 | `c_mate_start needs not OutOfService` | 0372's candidate source; `HW.002` at `charge_session_start` |
| R2 | `c_hold needs not OutOfService or CleanArm.Returning` | 0792: on an out-of-service post the sweep never keeps a car for a clean still to be done. It keeps it only while the cleaning arm withdraws, because R3d requires that. |
| R3a | `c_mate_start needs CleanArm.Home or DoorsOpen` | renderer `armSessionInput`: `cleanBlocksMate` |
| R3b | `c_unlatch needs CleanArm.Home or OutOfService` | renderer `holdForClean` (Chase, 2026-10-19), with the fault exception from ottoyarddepot-sim PR #154 (9c81f78, not yet in main) |
| R3c | `c_clean_enter needs ChargeArm.Stowed or Latched` | renderer `mayEnter` (the cleaning arm waits at doors_open) |
| R3d | `c_release` / `c_emergency_release need ChargeArm.Stowed and CleanArm.Home` | renderer `armGate.ts` and `cleanGate.ts` (no car moves with an arm at it) |
| R4 | `c_depart_ready needs Battery.Full and Cabin.Clean` | rule 9; `public.ottoq_departure_clear` (0543) |
| R5 | `c_stop_charge needs Battery.Full` | rule 9: a charge ends short only on a fault (`u_fault`) |
| R6 | nonblocking: the car Ready or Requeued, both arms home, no tether | enforced by synthesis |

**R3 is an ordering abstraction, not a collision proof.** The renderer's `cleanArmClearance.test.ts` reports at least
0.10 m between the two arms "whatever either is doing". R3 encodes the interlocks the code enforces, not geometry.
The engine enforces none of R3a–R3c.

## What the model does not cover

- **Time.** No clocks, only event order. "Released *when* the demate ends" rests on the Sweep assumption. With R2, a
  fault that lands during a legitimate hold leaves the car held mid-clean until the next tick (reachable, and bounded
  by one tick), exactly as 0792 behaves.
- **Other posts, other cars, the booking calendar** (0474 §2's freed booking), mate retries, the soc arithmetic of the
  re-queue threshold, vehicle emergencies, and the "mate coming" nuance of `mayEnter`.
- **Repair timing.** The trace carries no repair event (0474 §5(a)), so the monitor derives the repair from
  `twin.ottoq_sim_recover_chargers`'s rule.

## Synthesis results (`./synthesize.sh`, then `python3 -I analyze_synthesis.py`)

| variant | succeeded | controlled states | transitions | (state, event) pairs disabled | derived beyond the requirements |
|---|---|---|---|---|---|
| plant alone | – | 507 | 1,632 | – | – |
| `post_cell` (R1–R6) | yes | 302 | 831 | 132 | 0 |
| `post_cell_pre0792` (no R2) | yes | 302 | 839 | 124 | 0 |
| `post_cell_strict_r2` | yes | 170 | 393 | 138 | 56 |

`analyze_synthesis.py` re-checks controllability and nonblocking for every variant from the explicit state spaces.

**With R2.** The supervisor adds nothing beyond the requirements. Every added guard is `true`, and the controlled
state space equals the plant restricted by the nine requirement invariants alone (the same 302 states and the same
831 transitions). So the requirements are already controllable and nonblocking against this plant. What the
supervisor disables is what they disable, in (state, event) pairs:

- `c_release` 36 (R3d)
- `c_clean_enter` 26 (R3c)
- `c_emergency_release` 24: never enabled (R3d)
- `c_mate_start` 15 (R1 and R3a)
- `c_depart_ready` 9 (R4)
- `c_hold` 8 (R2)
- `c_unlatch` 8 (R3b)
- `c_stop_charge` 6: never enabled (R5)

**What R2 alone disables.** Both variants have the same 302 states. Without R2 there are exactly **8 more
transitions, and every one is the G506 decision**: `c_hold` at a just-expired demate tether while the charger is
Faulted or UnderRepair and the cleaning arm is at DoorsOpen or OverCar. The states are the same because a fault
during a legitimate hold reaches them too. The difference is whether the sweep may *keep* the car there.

**Strict R2.** This variant shows what the exception in R2 is for. Synthesis forbids every hold, even on a working
charger, because a fault can overtake any hold, and then the car may neither be held (strict R2) nor leave (R3d).
Synthesis also *derives* `c_unlatch when CleanArm.Home`: the connector may not let go while the cleaning arm is out,
**even on a faulted charger**. That is the renderer's interlock as it stood before PR #154, the one that drew G506's
picture. It also restricts `c_mate_abort` and `c_clean_start`.

## The monitor and its calibration

`monitor.py` applies R1 and R2 to a post's trace. For the demate path, the release is due at the car's
`demate_cleared`; the rule's derivation and all the edge cases are in its docstring.

The zero-tolerance comparison comes from the run itself, not from the two answers. On `8c0b2e04` (read-only census,
2026-11-03), all **38** demates cleared at the first tick at or after `demate_started + window_s`. All **31** with no
cleaning arm at work left the post at exactly that instant. The other 7 were held for a clean: 5 after a normal end
(0760's intended hold) and the two G506 cars.

## Results on run 8c0b2e04 (`python3 -I monitor.py --all fixtures/8c0b2e04`)

Sim times are as stored (UTC). Wall times are the tick's `occurred_at`, UTC, with CT (UTC−6) in brackets.

| post | fault (sim) | path | release due | left | held | verdict |
|---|---|---|---|---|---|---|
| DCFC-22 | 14:04:15.481 thermal_emergency (wall 03:38:33 UTC, 9:38 PM CT) | demate, clean in progress | 14:04:37.354 | 14:09:54.598 (wall 03:40:26 UTC, 9:40 PM CT) | **339.1 s** | **R2 violated** for 317.2 s, released at the first tick after the clean ended |
| DCFC-02 | 14:04:45.385 session_aborted_other (wall 03:38:43 UTC) | demate, clean in progress | 14:04:57.332 | 14:09:54.598 | **309.2 s** | **R2 violated** for 297.3 s, as above |
| DCFC-18 | 14:06:32.069 connector_cable | demate | 14:06:43.748 | 14:06:43.748 | 11.7 s | ok |
| DCFC-11 | 14:09:00.910 communication_dropout | emergency release | the fault | the fault | 0.0 s | ok on R1/R2; advisories below |
| DCFC-29 | 14:24:39.564 session_aborted_other | emergency release | the fault | the fault | 0.0 s | ok on R1/R2; advisory |
| DCFC-13 | 14:27:36.051 connector_cable | emergency release | the fault | the fault | 0.0 s | ok on R1/R2; advisory |

- **R1** holds on all six posts. The next mates on DCFC-02 and DCFC-11 came after the derived repairs (14:20:58.775 and 14:23:04.305).
- **Acceptance:** the 339.1 s and 309.2 s match `db/checks/0474` §1 exactly.
- **The advisories (R3d) are things the engine record cannot decide**, because the engine has no arm-home signal:
  - The three emergency releases clear the car's pointer at the fault instant with the connector latched.
  - On DCFC-11 the car also left while its clean was nominally in progress.
  - The renderer's depart gates (`armGate`, `cleanGate`) hold the drawn car in both cases. 0474 §5(c) and frontier-plan gap 5 already record this.

**`replay.py`** replays each visit through the synthesized supervisors. The mapping and its assumptions are in its
docstring.

- **Against `post_cell`:**
  - DCFC-22 and DCFC-02 are disallowed at 14:04:37.354 and 14:04:57.332 by **R2** (`c_hold` with Charger Faulted and the cleaning arm OverCar).
  - DCFC-11, -13 and -29's emergency releases are disallowed by **R3d**.
  - On DCFC-29, the first car's normal-end demate is disallowed by **R3b**. The engine demates while the cleaning arm works, and the renderer keeps the connector in. The car itself was held by 0760 until the clean was done.
  - DCFC-18 and the four other visits are allowed throughout.
- **Against `post_cell_pre0792`:** the same findings, except that DCFC-22 and DCFC-02 replay completely. The hold the engine performed is exactly what R2 forbids.

## The diff against the hand-written holds (E3's third output; v0 covers this cell only)

| hand-written | supervisor | verdict |
|---|---|---|
| 0372 / `HW.002`: no mate on a Faulted charger | R1 | same |
| 0760 + 0792: hold an expired demate tether while the arm works, unless Faulted | `c_hold` needs the arm at work (the plant) and R2 | same, except that the supervisor also lets a faulted post hold its car while the cleaning arm withdraws. The engine has no "withdrawing" state (gap 5). |
| 0792 releases on a Faulted post at the demate's end | `c_release` needs both arms home (R3d) | engine gap 5: no arm-home signal; the renderer's `cleanGate` bounds the drawn car |
| the stop path's re-queue branch (`v_requeue`) releases at the fault | `c_emergency_release` never enabled (R3d) | engine abstraction: the arm's exit is not modelled; the renderer's `armGate` holds the drawn car |
| the engine demates when the session ends | `c_unlatch` waits for the cleaning arm on a working charger (R3b) | the engine and the renderer disagree on when the connector comes out. Not a safety hole: 0760 holds the car. |
| 0543 departure test | R4 | same |
| rule 9 / 0539: no early stop | R5 | same |

## Rerun

```sh
# traces (read-only; only while 8c0b2e04 is the latest run, because the next demo run's start purges engine-class rows):
#   run extract_trace.sql's two statements against gxdrcyphqjzjsuhxuqtg; write one CSV per post, plus ticks.csv
(cd fixtures/8c0b2e04 && md5sum -c MD5SUMS)
ESCET_BIN=/home/user/escet/v13.0/eclipse-escet-v13.0/bin ./synthesize.sh
python3 -I analyze_synthesis.py
python3 -I monitor.py --all fixtures/8c0b2e04
python3 -I replay.py --all fixtures/8c0b2e04 --variant post_cell        # or post_cell_pre0792
python3 -m pytest -q tests/test_post_cell_supervisor.py                 # from lab/safety or the repo root
```

**Provenance.** The fixtures were read from otto-q-core between 15:41:02 and 16:33:18 UTC on 2026-11-03 (9:41 and
10:33 AM CT), after the run had ended. Run `8c0b2e04` was still the latest run, with 67 sessions, 6 of them faulted,
and 9,725 events. Each file equals, byte for byte, the text whose md5 the database computed (`MD5SUMS`). All vehicle
ids are full UUIDs. The live bodies read were:

- `public.ottoq_release_expired_tethers`, md5 `5a97f2dc` (0792's tested body)
- `twin.ottoq_sim_stop_charge_session`, md5 `877cf0bf`
- `twin.ottoq_sim_recover_chargers`, md5 `8790f9fe`

The renderer was read at ottoyarddepot-sim `9c81f78` (PR #154's branch) and at `origin/main` `7c28d10`.
