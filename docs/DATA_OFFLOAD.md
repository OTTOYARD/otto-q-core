# Data offload as a depot service

**Status:** design, 2026-10-10 (about 1:30 AM CT; the stall points read 2:03-2:12 AM CT). Part A, item 3 of the twin data contract review: *"The AV view of a
depot visit ... No such service exists in the engine."* **Chase, 2026-10-09:** model it as a timing sequence while the
car charges or during a service-bay stop. This file sets out how, what it costs, and what the twin will measure before
anything changes the default world. Nothing here is built yet.

## What is known, and from where

| Claim | Source | Date | URL |
|---|---|---|---|
| *"A single highly automated vehicle generates one to five terabytes (1-5TB) of raw data per hour"*; *"Operating at 14 to 16 hours per day means as much as 50 terabytes per vehicle per day"* | Renovo and EdgeConneX, press release (a vendor claim) | 2018-06-12, read 2026-10-10 | https://www.edgeconnex.com/news/press-releases/renovo-and-edgeconnex-announce-collaboration-on-edge-data-infrastructure-to-enable-automated-mobility-systems-at-scale/ |
| The release does not say how data leaves the car (no drive swap, no uplink, no depot transfer is described). Its only mention of depots: *"edge computing infrastructure collocated with the operational hubs for staging, charging, cleaning and maintenance will grow rapidly"* | same | same | same |
| Data offload, 10-40 minutes, in parallel with other work | the robotaxi operation catalog, CLAUDE.md 2.4 | — | — |
| A fast charge at the twin depot lasts a median 30 minutes (10th percentile 10, 25th 20); 39.0% end in under 30. An L2 charge lasts a median 65 minutes; 18.9% end in under 30 | measured, 17,563 sessions of the twin depot's runs of the 7 days to 2026-10-10 | 2026-10-10 | `ocpp_sessions` joined to `stalls` |

No public dataset gives a robotaxi fleet's offload volume per visit or a depot's uplink rate. Both are declared
assumptions below, not fits.

## The model

- **When it is raised:** at each visit of a car that was out at work (any of the three AV fleets; the retail cars
  carry no AV logger), sized by the hours it was out since its last completed offload.
- **How long it takes:** minutes = hours out x data per hour / stall uplink rate, between 10 and 40 (the catalog's
  range). Declared: **1 TB an hour kept for offload** (the bottom of the vendor's raw range, because fleets triage on
  the car) and **10 Gbps per uplink stall** (4.5 TB an hour). So 2 hours out is 2 TB and about 27 minutes; 45 minutes
  out is the 10-minute floor.
- **Where it runs:** only while the car sits on a stall with an uplink: a charger (DCFC or L2) or a service bay, as
  Chase decided. Not on staging stalls and not in the wash bays. It needs no technician (it is a digital-lane task).
- **If the car moves before it finishes:** the transfer stops and resumes on the next uplink stall, keeping what was
  sent (the atom keeps its minutes done, not a fresh clock). The engine's completion step today closes any in-progress
  atom once its end time passes, wherever the car is; that is wrong for a stall-bound transfer and has to change with
  it.
- **Rule 9:** the data is the operator's, and once raised the offload is a required service: the car does not leave
  with it unfinished (0543's departure test already refuses that for every must-do atom). An operator that does not
  want it says so (`services_needed` in its arrival intent omits it), and that is the owner's requirement.

## What it costs, which is the point of measuring it

With offload only on chargers and bays, a car whose offload outlasts its charge **holds its charger** until the
transfer ends. Read against the sessions above: a 27-minute offload outlasts about 4 in 10 of today's fast charges,
so the depot's 10 fast chargers, its scarcest resource, carry data instead of electrons for part of their time. Rule 9
names *"freeing a charger the moment its car is done"* as an answer to site pressure, and an uplink on the staging
stalls would let a car finish its transfer off the charger. That is a depot design question with a measurable answer,
which is why the build is a dial and a pair, not a default.

**The risk the build has to close first: a rule-9 deadlock.** If the engine moves a charged car off its charger to
staging while its offload is unfinished, the car holds a required service it cannot do there, and nothing seats a car
on a charger that needs no charge, so it never leaves. The hold has to be explicit: a car with a pending or running
offload keeps its charger (or bay) until the transfer ends. Read 2026-10-10: `charge_complete_holding` is handled in
over 40 functions, among them `ottoq_decide_tick` (97,675 characters), `twin.ottoq_sim_advance_service_flow` and
`twin.ottoq_sim_stop_charge_session`, so the release paths are read one by one before anything is written. The first
read (2026-10-10): a charger is let go in one place, `twin.ottoq_sim_stop_charge_session` (its tether-guarded clear of
the stall's car, called from `twin.ottoq_sim_advance_charge_sessions` and `public.ottoq_twin_inject_charger_fault`);
among the functions that handle a `charge_complete_holding` car afterwards are `ottoq_decide_tick`,
`twin.ottoq_sim_advance_service_flow` and `twin.ottoq_opportunistic_scan` (found by name; which of them move the car is
not yet read). The hold goes at the first, and whichever of the others move a charged car must honour it; a charger
fault still ends the hold (rule 9's own exception: the car is re-queued, and its transfer resumes on the next uplink
stall).

## Where the transfer can stall, read 2026-10-10 2:03-2:12 AM CT

The hold and the way back were read in the live functions, comment-stripped, before anything was written:

- **What already holds a charged car on its charger.** `twin.ottoq_sim_advance_service_flow` STEP 1.5 (the
  deploy-pressure fast track) moves a `charge_complete_holding` car to staging only when no must-do atom other than the
  charge and the readiness check is open. A raised offload is must-do, so in the ordinary flow a car whose charge ends
  first keeps its charger until the transfer ends. That is the hold the design asks for, already there.
- **What moves a charged car off its charger for other work.** STEP 2 of the same function admits a
  `charge_complete_holding` car with a wash or deep clean open to the wash bay; `ottoq.ottoq_activate_due_bay_reservations`
  seats a car whose bay booking is due; and the emergency and fault handlers move cars by their own rules. Each of
  these would take a car with its transfer unfinished off the uplink.
- **What brings such a car back: nothing, today.** The charge cursor in `ottoq_decide_tick` takes a staged car only below
  its visit target minus 1 (0493). `twin.ottoq_sim_departure_recheck` (0543) routes an unfinished staged car to a
  charge, a service bay or the wash, and leaves digital work "to finish where the car is". A car whose battery is full
  and whose transfer is unfinished, off its charger, has no route back: the departure door keeps it (rule 9), and the
  readiness gate escalates it as stuck. This is the deadlock the design warned of, located.
- The completion step (`twin.ottoq_sim_advance_visit_atoms`) also restarts pending digital work each tick through the
  starter (`public.ottoq_start_concurrent_atoms`), which starts every digital atom at once, anywhere, with no
  technician; it is where a transfer pauses and resumes.

## The build (one migration after 0657, behind a dial, plus a pair)

1. `service_cadence_policy` row `data_offload` (lane `digital`, must-do once raised, declared in the vocabulary and
   the retirable set, so `ottoq_assert_service_vocabulary()` stays empty).
2. The visit deriver raises it, sized as above, at `twin_data_offload` 1 (a run's dial; 0, unset, changes nothing),
   and only on a visit that has a charge to do, so the car will stand on a charger anyway. A visit with no charge
   carries its hours to the next visit that has one.
3. The starter starts it only on a charger or a service bay, records `performed_by` `stall_uplink` and the stall, and
   resumes a paused transfer from the minutes it has left. The completion step pauses a running transfer whose car is
   no longer on its uplink stall, keeping the minutes done.
4. The hold: STEP 2's wash admission and the bay-booking activation leave a car whose transfer is running where it is
   until the transfer ends; the wash and the bay follow it.
5. The way back, for a car that leaves its uplink anyway (an emergency, a fault): the departure recheck and the
   readiness gate give an unfinished transfer the remedy `need_charge`, the recheck stops sending such a car back to
   the gate, and the decide tick's charge cursor takes a car with an unfinished transfer as needing a charger whatever
   its charge. A session opened for a full car completes with no energy on the next tick (the start function already
   handles that case), and STEP 1.5 then holds the car on the charger until the transfer ends.
6. The pair: `twin_data_offload` 0 against 1, busy_day at the twin depot, read for fast-charger hours spent holding a
   charged car for its offload, turnaround, the wait for a charger, deployed car hours, and any car the readiness gate
   escalates as stuck. A second question for the research wing after it: the same with uplink on the staging stalls.

Steps 3 and 5 patch `twin.ottoq_sim_advance_visit_atoms` as 0657 leaves it, so the migration is applied after 0657.
Ten patch sites in eight functions, two of them the largest in the engine (`ottoq_decide_tick`,
`twin.ottoq_sim_advance_service_flow`); each is md5-guarded and the probe exercises each piece on a stopped run.

The dial stays 0 until a person sets it, after the pair, as a certified change (rule 10: the research wing measures,
production does not experiment).
