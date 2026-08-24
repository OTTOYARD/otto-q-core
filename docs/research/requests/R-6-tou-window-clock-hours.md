# R-6 — Time-of-use window clock hours, and Georgia Power's hours-use energy blocks

**Filed:** 2026-08-24 by the build track (Claude Code)
**Blocks:** exactness of `sites/profiles/phoenix_aps_e35.json` and
`sites/profiles/atlanta_georgia_power.json`. Neither blocks the Site Profile object itself —
both gaps are labelled in the profiles and in `SITE_PROFILE.md`, and the harness runs today.

R-5 delivered demand-charge levels, bases and intervals, which was the hard part and is what the
tariff object was built around. Two specific gaps remain, both of which currently sit in the repo
as labelled assumptions rather than sourced facts.

## Q1 — On-peak / off-peak clock hours per schedule

For each schedule below, the **exact local clock hours** of each named time-of-use window, the
**days** it applies (weekdays only vs all days), whether the window **differs by season**, and
any **holiday exclusions**:

- APS E-35 Extra-Large General Service TOU (Arizona) — *currently assumed 16:00–19:00 weekdays*
- SCE TOU-8 (California) — on-peak and winter mid-peak
- LADWP A-2B — high-peak and low-peak
- NV Energy LGS-2 — summer on-peak
- NES GSA-3 and NES EVC (Nashville) — whether GSA-3 has any TOU window at all, and EVC's
  on-peak/off-peak boundaries

Please give hours in local time with the time zone named, e.g. `16:00–19:00 America/Phoenix,
weekdays, June–September`.

Why it matters, non-technically: our scheduler decides *when* to charge. If we believe the
expensive window is 4–7 pm and it is actually 2–8 pm, we will confidently move charging into
hours that are still expensive and report a saving that does not exist.

## Q2 — Georgia Power PLL-18 declining energy blocks

R-5 established that PLL-18 prices energy in declining blocks keyed to **hours-use of demand**,
so there is no single $/kWh. Needed to model it rather than approximate it:

1. The **block table**: each block's boundary (in kWh, or in hours-use-of-demand) and its $/kWh.
2. Whether blocks are **seasonal**.
3. The exact definition of **"hours use of demand"** in the tariff's own words (kWh ÷ billing
   demand for the period, or another formulation).
4. Whether the **minimum-bill demand** ($13.63/kW) interacts with the blocks or is additive.

If the block table is not publishable, say so — we will keep the placeholder and keep it labelled.

## Q3 — Confirming one figure R-5 flagged as third-party

R-5 marked **NV Energy LGS-2** $/kW as third-party (Nectar Climate) and recommended reading the
LGS-2 tariff PDF directly before seeding a Las Vegas profile. We have not seeded one; if the PDF
is reachable, the direct figures would let us add Las Vegas (it is the only observed **daily**
demand charge, which is a shape our object supports but has never been exercised against).

## Answer format

`docs/research/answers/R-6-tou-window-clock-hours.md`, same conventions as R-1..R-5: units, a
source URL per figure, `NOT FOUND` where no defensible answer exists. `NOT FOUND` is a useful
answer here — it tells us to keep the assumption labelled rather than quietly promote it.
