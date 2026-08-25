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

`solvers/cpsat/scenario_vertiport.json` — **real airframes now, via R-7's primary sources**:
2× Joby S4 (~125 kWh, GEACS ~300 kW; kWh flagged ±20%), 1× Archer Midnight (~75 kWh, 800 V,
~10–12-min turnarounds), 1× Beta ALIA (~220 kWh at **115 kW continuous — the slow charger, and
the scheduling tension**), 2 delivery drones, 8 robotaxis — arriving in a **commuter-peak rush**
(the demand pattern vertiports exist for; a politely staggered fleet would test nothing).

`ready_by` uses R-7's **demonstrated-capability band (~20–40 min slack)**: published block times
are 7–12 minutes (Joby/Delta JFK, Archer/United ORD filings) plus 10–12-minute charges — R-7
measured the earlier 65–85-min placeholder as ~3× too generous, and the founder's call was demo
realism.

Points: 2× 300 kW pads (6-min clearance gap), 3× drone pads, 4× DCFC, 2× L2, wash, service bay.
**The swap dock is REMOVED**: R-7 found swap is the *exception* among eVTOLs (Volocopter only,
pack size NOT FOUND), so the 450 kW shoehorn is resolved by deletion, not promotion — swap
returns when fixed-duration operations exist and a swap OEM has sourced numbers. **Nameplate
1,231 kW on an 800 kW service — oversubscribed 1.54:1**, inside R-4's observed band, so the cap
genuinely binds.

## The result

| policy | tardy min | peak kW | vs the 800 kW service | monthly $ |
|---|---:|---:|---|---:|
| fifo | 154 | 843 | **CANNOT RUN** (+43 kW) | 16,417 |
| greedy | 0 | 843 | **CANNOT RUN** (+43 kW) | 16,416 |
| **forward** | **0** | **300** | **runs** | **7,264** |

> In the morning rush, the myopic policies exceed the site's physical service capacity — in
> the real world, a tripped main or a brownout mid-turnaround, not a worse score. **The joint
> solve turns every aircraft and vehicle around on time at 300 kW** — at less than half the
> myopic bill. Provable ideal peak for this world: 178.5 kW.
>
> *(Reported honestly across revisions: on the pre-R-7 placeholders the myopic excess was
> +90 kW; on sourced airframes it is +43 kW. The wedge is smaller and real. Under the tighter
> demonstrated-capability deadlines FIFO also misses 154 tardy-minutes — serialized service
> cannot meet an air-taxi schedule.)*

**Scope of the claim, so it is never overquoted:** *myopic per-asset policies with no site
view* exceed the service. It does not say no other algorithm could stay under — staying under
while meeting deadlines requires seeing every modality's demand at once, and a policy that
does so has become a site-level coordinator, which is the product.

Both solver passes reach **OPTIMAL in ~2 seconds**. eVTOL pad turnarounds come out at ~20
minutes — charge physics, not an assumption.

`otto_q_asis` is excluded with its reason stated: it is a faithful reduction of the live
robotaxi cursor, which has no multi-class capability concept; including it would book
aircraft onto car chargers and score noise.

## What R-7 sourced, and what stays labeled (all scenario data, none solver code)

**Sourced (R-7, primary-first):** eVTOL batteries and charge powers per airframe (Joby GEACS
PDF, AIN/Archer press, beta.team/battery); turnaround times; block-time-derived `ready_by`;
swap-is-the-exception (Volocopter only). R-7's structural headline: **eVTOL turnaround is
dominated by energy transfer, not aircraft handling** — aircraft hover-taxi under their own
power, no tug — so the schedule is a charger/kW-allocation problem, which is exactly the
problem this kernel solves.

**Still labeled inference, per R-7's own NOT FOUNDs:**
1. **Pad `min_gap_min` = 6** — no regulator publishes a separation *time*; downwash criteria
   are velocity-distance (FAA 34.5 mph / EASA 60 km/h at 2D). Kept as labeled inference.
2. **Drone battery/charge (~2 kWh / ~3 kW)** — no vendor publishes kWh; derived from the
   10-min/10-mile energy budget. (The old `drone_cargo_m2` name is gone — R-7: the Matternet
   M2 *swaps* in <60 s; the generic charge-in-place drone matches Zipline P2 / Wing.)
3. **Charge-taper curves** — per-OEM acceptance curves are unpublished; generic taper kept.
4. Billing uses NES GSA-3; the power cap is the scenario's own 800 kW service.

## What feeds the rendering side

The plan already carries everything a renderer needs per asset: point, start, end, segments —
`(entity, point, t_start, t_end)` is the playback-timeline shape the twin exports (CLAUDE.md
2.8). The artifact `policies/multimodal_seed424242.json` is deterministic and hashed; the
scene above it — pads overhead, stalls below, arms working the line — is presentation of a
solved schedule, never a source of one.
