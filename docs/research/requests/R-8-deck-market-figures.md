# R-8 — Market figures for the pitch deck (slide 4 and slide 14)

**Filed:** 2026-08-25 by the build track (Claude Code)
**Blocks:** nothing — the deck ships with `[TBD]` brackets where these are missing; this
request converts brackets into attributed figures. Deck guardrail: every market figure needs a
verified current source with a mono attribution line, and stale figures must not be reused.

## Q1 — Data-center competition for the same megawatts (slide 4, stat 3)

The deck's claim: data centers are outbidding everyone for the same electrons fleet depots
need. Needed, with source and date:
1. Current total or projected US data-center load growth (GW, with year range) from a primary
   or near-primary source (EIA, LBNL, EPRI, a major utility IRP, or a top-tier grid operator).
2. Any figure connecting interconnection queue congestion to data-center demand (queue GW by
   customer type, or a utility statement that large-load queues are dominated by data centers).
3. If available: a $/MW-month or $/kW premium signal (what large-load customers now pay or
   commit to for firm capacity vs. 2–3 years ago).

## Q2 — Interconnection queue duration, one clean citable number (slide 4, stat 1)

R-4 gave RMI's "several months to several years." For a deck stat we need the tightest
defensible single figure: median or typical **large-load (not generator) interconnection /
service-upgrade timeline** in months, from a named source with a year. If only generator-queue
medians exist (e.g., LBNL's ~5 years), say so — we will not misapply a generator figure to a
load interconnection without labeling.

## Q3 — MW per site at fleet scale (slide 4, stat 2)

Best available public figures for robotaxi or AV-fleet depot power at scale: any disclosed
depot MW (Tesla, Waymo, Zoox facility filings, utility case studies), or charging-hub
interconnection sizes from public filings. 2–20 MW class. Named sites preferred.

## Q4 — Modality sizing figures (slide 14, only if used)

Current-year fleet/unit counts or growth figures for: robotaxi (vehicles in commercial
service), AV freight (trucks in revenue service), last-mile delivery robots, commercial UAS
deliveries/year, autonomous mining haulage units, port/yard automation units, defense unmanned
systems (fielded counts if public). One number per modality, sourced and dated; NOT FOUND is a
fine answer per cell.

## Answer format
`docs/research/answers/R-8-deck-market-figures.md`, conventions as R-1..R-7: units + source URL
per figure, primary-first, `NOT FOUND` where no defensible number exists.
