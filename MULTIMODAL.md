# MULTIMODAL.md — three modalities, one cap, and who can run the morning rush

The hero shot's backend, built and measured: **eVTOLs land and turn around on pads above;
ground robotaxis stage, charge and get serviced below; cargo drones opportunity-charge at the
edge — every modality drawing on one electrical service that cannot carry them all at once.**

The claim is not that OTTO-Q schedules aircraft. It is that **the kernel never learned what an
aircraft is** — and scheduled them anyway.

## What made it possible

The separation audit (SEPARATION.md) found the last sector vocabulary baked into the kernel:
`model.py` hardcoded the point kinds `"dcfc"`/`"l2"`, DCFC's cooldown, and two literal
durations. All are now **data**:

- an asset class declares `charge_kinds` — the ordered list of point kinds that can serve it;
- a service point declares `min_gap_min` — a pad's clearance interval, a swap dock's reload,
  DCFC's cooldown, all the same mechanism (CLAUDE.md 2.5's min-gap-on-the-point);
- a scenario may declare its fleet **explicitly** (`assets_spec.explicit`) — how a multimodal
  world states exactly which aircraft and vehicles arrive when, with no generator opinions;
- legacy defaults preserve every committed artifact **byte-for-byte** (verified: plan,
  comparison, cost, forward, 24h shas all unchanged).

A CI test now asserts the words `pad_charge`, `swap_dock`, `drone_pad`, `evtol`, `vertiport`
appear **nowhere in the solver source**. They live in one place: the scenario JSON.

## The scenario

`solvers/cpsat/scenario_vertiport.json` — 4 eVTOLs, 2 cargo drones, 8 robotaxis arriving in a
**commuter-peak rush** (eVTOLs within a 40-minute window; robotaxi shift-change overlapping —
the demand pattern vertiports exist for; a politely staggered fleet would test nothing).

Points: 2× 300 kW pads (6-min clearance gap), 1× 450 kW swap dock, 3× drone pads, 4× DCFC,
2× L2, wash, service bay. **Nameplate 1,690 kW on an 800 kW service — oversubscribed 2.11:1**,
inside R-4's observed band, so the cap genuinely binds.

## The result

| policy | tardy min | peak kW | vs the 800 kW service | monthly $ |
|---|---:|---:|---|---:|
| fifo | 154 | 890 | **CANNOT RUN** (+90 kW) | 16,449 |
| greedy | 0 | 890 | **CANNOT RUN** (+90 kW) | 16,363 |
| **forward** | **0** | **300** | **runs** | **8,548** |

> In the morning rush, the myopic policies exceed the site's physical service capacity — in
> the real world, a tripped main or a brownout mid-turnaround, not a worse score. **The joint
> solve turns every aircraft and vehicle around on time at 300 kW** — under half the myopic
> peak, at roughly half the bill. Provable ideal peak for this world: 138.2 kW.

**Scope of the claim, so it is never overquoted:** *myopic per-asset policies with no site
view* exceed the service. It does not say no other algorithm could stay under — staying under
while meeting deadlines requires seeing every modality's demand at once, and a policy that
does so has become a site-level coordinator, which is the product.

Both solver passes reach **OPTIMAL in ~2 seconds**. eVTOL pad turnarounds come out at ~20
minutes — charge physics, not an assumption.

`otto_q_asis` is excluded with its reason stated: it is a faithful reduction of the live
robotaxi cursor, which has no multi-class capability concept; including it would book
aircraft onto car chargers and score noise.

## Labeled assumptions (all scenario data, none solver code)

1. **The swap dock is expressed as a 450 kW transfer**, not a true fixed-duration swap —
   fixed-duration operations are part of the finishing-chain generalization, the known
   remaining vocabulary debt (wash/inspect are still named ops with data-driven durations).
2. **eVTOL and drone turnaround parameters are engineering placeholders** — battery, charge
   power, pad clearance, schedule slack. **R-7 is filed** to replace them with sourced
   figures (Joby/Archer/Beta specs, FAA EB-105 pad guidance, announced route block times).
   Correcting them edits the JSON; the solver does not change.
3. Billing uses NES GSA-3; the power cap is the scenario's own 800 kW service.

## What feeds the rendering side

The plan already carries everything a renderer needs per asset: point, start, end, segments —
`(entity, point, t_start, t_end)` is the playback-timeline shape the twin exports (CLAUDE.md
2.8). The artifact `policies/multimodal_seed424242.json` is deterministic and hashed; the
scene above it — pads overhead, stalls below, arms working the line — is presentation of a
solved schedule, never a source of one.
