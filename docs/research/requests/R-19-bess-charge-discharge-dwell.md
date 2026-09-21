# R-19 — Is there a required dwell between BESS charging and discharging?

**Filed** 2026-09-20 by the build track (Claude Code). **Not blocking** — the build decision is
already made and recorded in `db/checks/0295`; this request is to make a secondary-source reading
primary. **Status:** open.

## Why this is being asked

`SM.006.bess_transition_validity` is one of four `critical` rule codes with no caller. Its
description reads:

> A BESS unit may only change power state along the admissible transition matrix
> (**dwell-through-standby between charge and discharge**).

Measured on the twin depot (`db/checks/0285`): **3,426 of 23,730 BESS power-state transitions
(14.4%) are direct `charge` ↔ `discharge`**, which the parenthetical forbids. Wiring the rule as
written, at its declared `enforcement='block'`, would refuse 14.4% of live transitions — so the
rule's correctness has to be settled before it is enforced, not after.

## What I found already, and its limits

Searched 2026-09-20. **I did not read IEEE 1547-2018 itself** (paywalled; a university-hosted copy
surfaced and was deliberately not treated as authoritative). From institutional secondary summaries:

- IEEE 1547-2018 requires a DER mode transition to complete in **no greater than 30 seconds**, with
  smooth output transition over 5–300 s — [NREL fy20osti/75436](https://docs.nrel.gov/docs/fy20osti/75436.pdf),
  [IREC](https://irecusa.org/blog/regulatory-engagement/how-ieee-1547-1-2020-paves-the-way-for-more-energy-storage-a-smarter-grid/),
  [Sandia 2023](https://www.sandia.gov/app/uploads/sites/273/2023/11/2023_Vermont_Webinar_Vartanian1.pdf).
- That is a **ceiling on transition duration, not a floor requiring a rest in standby.** Nothing
  found imposes a minimum dwell or requires passing through standby.

**And a separate finding that matters more than the answer:** the twin's tick is **30 seconds**,
which equals IEEE 1547's own transition ceiling. So a fully compliant transition can complete
between two samples, and consecutive-snapshot `charge` → `discharge` is **not evidence that no
dwell occurred**. The 3,426 transitions are consistent with full compliance and with none.

## The questions

1. **Does IEEE 1547-2018 or IEEE 1547.1-2020 impose any MINIMUM time in a non-exporting state
   between active-power absorption and active-power injection?** Cite the clause number and the
   exact wording. A clear "no such clause exists" is a complete and useful answer.
2. **Do major grid-tied BESS inverter vendors document a required dwell, or a minimum
   charge↔discharge reversal interval?** Name the product, the firmware or document version, and
   the page. Tesla Megapack, Sungrow, SMA, Power Electronics and EPC would cover the field.
3. **Is there a quantified BATTERY-HEALTH basis for such a dwell — per chemistry (LFP vs NMC), in
   stated units** (seconds of rest, C-rate reversal limit, cycles-to-degradation)? If it exists we
   would parameterise a rule rather than assert one; if it is only qualitative, say so.
4. **What sampling interval would be needed to observe a transition at all** — i.e. what do vendors
   state as typical charge↔discharge reversal time? This decides whether the twin's 30-second tick
   can ever carry this rule, or whether the rule belongs at a different layer entirely.

## What will be done with the answer

Per `db/checks/0295` the decision is already: keep SM.006's transition-matrix half (observable,
enforceable, wire it), and remove the dwell clause from the `critical`/`block` rule. A primary
source saying a dwell IS required would reverse that and is the reason to ask. A primary source
confirming no dwell requirement lets the removal cite something better than three secondary
summaries.
