# R-14 — Hour-of-day congestion profile and return-trip ETA, for a Nashville-area depot

**Filed:** 2026-09-14 by Claude Code (build track)
**Blocking:** partially. Migration 0314 ships a computed ETA now, using a THREE-REGIME
speed model with a labelled `ASSUMPTION — pending R-14` on the intra-regime shape. A
sourced hourly curve replaces that assumption without changing any call site.

## Why this is being asked

`ottoq_return_eta_minutes` returned a policy constant (30 minutes) for every vehicle in
every run — it took a vehicle id and a depot id and ignored both. All 123,665 dispatch
rows carrying `return_eta_minutes` hold the single value 30. That constant is the time
axis of the engine's forward demand curve, so the curve could say how MUCH energy was
inbound but not WHEN. 0314 replaces it with distance ÷ effective speed.

Effective speed needs an hour-of-day profile. Two internal sources were checked and
both were rejected, deliberately:

- **`ottoq_calibration_distributions`** holds `nyc_tlc / trip_duration_minutes` fitted
  over 3,503,651 samples, but at `segment='global'` only. There is no hourly segment,
  and the raw TLC rows are not in the database — only the fitted grid.
- **Our own `ottoq_telemetry_packets.speed_kmh`** (394,334 packets) varies by hour over
  a band of only ±6% (31.5 to 37.2 km/h), and the sample sizes are wildly unequal —
  126,626 packets at 02:00 UTC against 179 at 08:00 — because 1,082 of 1,110 sim runs
  start at 21:00 CT. Fitting a congestion curve to that would be circular (the twin
  generated the speeds) and thin. Rejected rather than used.

## What was found by direct search, and what it does not cover

TomTom Traffic Index, Nashville TN, 2025 edition
(https://www.tomtom.com/traffic-index/city/nashville-tn/, read 2026-09-14):
- city-wide average speed **27.5 km/h**
- **57 hours** lost in rush hour during 2025, 5 h 06 min more than 2024

Those are real and citable. The page's hour-by-hour table is rendered client-side and
was not retrievable as text; the page exposes only the buckets "24/7", "All days",
"Morning rush hour", "Evening rush hour". So the peak/off-peak CONTRAST is sourced and
the SHAPE WITHIN each regime is not.

## Questions — precise, answerable

1. For Nashville-Davidson County (or the closest published metro), what is the average
   travel speed or congestion delay index **for each hour of the day, 0–23**, on
   weekdays and on weekends separately? Give the value, its units, the year, and a URL
   per figure. TomTom Traffic Index and INRIX Global Traffic Scorecard both publish
   this shape; FHWA's Traffic Monitoring Guide publishes hourly volume distribution,
   which is acceptable as a second-best if speed by hour is unavailable — say which
   you used.
2. What exact clock hours does the source treat as **morning rush** and **evening
   rush** for that metro? 0314 currently assumes 07:00–09:00 and 16:00–18:00 LOCAL
   (`ASSUMPTION — pending R-14`).
3. What is the published **free-flow** (uncongested) average speed for that metro, so
   the ratio of peak to free-flow can be computed rather than assumed?
4. How much does **precipitation** reduce average urban travel speed? We hold NOAA
   GHCN daily precipitation for Nashville (station USW00013897, 1991–2020, 10,956 rows)
   and can condition on it, but need a published speed-reduction factor — ideally
   percent speed reduction per mm/day or per rain/snow category, with a source.
5. For a **robotaxi or AV fleet** specifically, is there any published figure for how
   far from base such vehicles typically operate — a service-radius or
   distance-from-depot distribution? 0314 currently derives the trip radius from
   planned trip duration × mean speed, which is internally consistent but unsourced.

## What a good answer looks like

A table of 24 hourly factors normalised to the daily mean, with the metro, the year,
the units and a URL; plus explicit answers to 2–5. If the hourly curve exists only for
a different metro, say so and name the metro — a sourced curve from a comparable city,
clearly labelled, beats an invented Nashville one.
