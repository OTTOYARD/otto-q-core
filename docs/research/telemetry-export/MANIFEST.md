# MANIFEST — OTTO-Q Telemetry Export (offline forecast fitting)

Export date: 2026-08-23. Source: `otto-q-core` engine, Supabase project ref `gxdrcyphqjzjsuhxuqtg` (us-east-1), read-only (`read_only=true`, postgres role). **No database writes were made.**

> ⚠️ The simulation engine was **actively running** during export, so row counts below drift slightly from the committed CSVs. Counts in this manifest are as-of-export; the CSV files themselves are the frozen artifact.

---

## Headline findings — read these before fitting anything

1. **Every energy series is simulation telemetry (`data_source='twin'`).** `site_energy_snapshots` — the site-level energy spine — is **100% `twin`**. There is no production energy telemetry in the engine at all. Per the standing rule ("we must never fit a model on sim output and call it grounded"), **none of the energy data is production-grounded**. The `data_source` column is preserved in every row so sim and (future) production rows stay separable.

2. **There is no genset.** No diesel / generator / fuel power column exists anywhere in the schema. `genset_kw` is empty in every row. (The `generator` columns in `ottoq_variability_catalog` and `ottoq_wave_plan` describe *arrival-wave* generation knobs, not power generation — do not confuse them.)

3. **The series is NOT continuous and NOT uniformly 5-minute.** It is sim-run telemetry: median inter-row gap ≈ **2 min** during active runs, with **multi-day gaps between runs** (largest observed gap ≈ 25 days). Raw timestamps are exported exactly as recorded — **nothing was interpolated, resampled, smoothed, or filled.** Gaps are present in the CSVs as gaps in time, not as filled rows.

4. **Solar IS separable.** Per-canopy AC/DC power lives in `ottoq_solar_output`; site-level `solar_generation_kw` lives in `site_energy_snapshots`. Static nameplate lives in `ottoq_site_structures` (`structure_kind='solar_canopy'`, `properties->>'solar_kw_dc'`).

5. **BESS state-of-charge and capacity are in a separate table** (`bess_snapshots`) at finer cadence than the energy spine, and are joined by exact timestamp (with dedup — see below).

6. **Timestamps are sim-clock, not wall-clock.** The twin advances its clock faster than real time (and can run into the "future"): `bess_snapshots` reaches 2026-09-11 even though this export ran 2026-08-23. Treat `ts_utc` as the twin's simulation clock; treat "seasonal span" accordingly.

---

## File 1 — `energy_timeseries.csv` (the primary ask)

**Source query** (one per sim depot, `11111111-…` and `22222222-…`):

```sql
SELECT e.depot_id, e.timestamp, e.solar_generation_kw, e.bess_output_kw,
       e.total_ev_charging_kw, e.building_load_kw, e.lighting_load_kw,
       e.grid_import_kw, e.grid_export_kw, e.data_source, e.sim_run_id,
       b.soc_percent, b.capacity_kwh
FROM site_energy_snapshots e
LEFT JOIN (
  SELECT DISTINCT ON (depot_id, timestamp) depot_id, timestamp, soc_percent, capacity_kwh
  FROM bess_snapshots ORDER BY depot_id, timestamp, id DESC
) b ON b.depot_id = e.depot_id AND b.timestamp = e.timestamp
WHERE e.depot_id = '<depot>'
ORDER BY e.timestamp;
```

**7,272 rows · span 2026-05-28T06:04:00Z → 2026-08-23T08:00:00Z (~87 days).** (Deduplicated from 7,479 raw rows — see inference notes.)

| CSV column | Source table.column | Notes |
|---|---|---|
| `site_id` | `site_energy_snapshots.depot_id` | UUID |
| `ts_utc` | `site_energy_snapshots.timestamp` | sim-clock, UTC, ISO-8601 `Z` |
| `generation_kw` | **computed** | `solar_generation_kw + GREATEST(bess_output_kw, 0)` — on-site generation = solar + BESS discharge. No genset exists, so this is the whole generation picture. |
| `load_kw` | **computed** | `total_ev_charging_kw + building_load_kw + lighting_load_kw` — controllable/customer load. BESS charging is *not* folded in; it is exposed as signed `bess_output_kw` so you can treat it either way. |
| `bess_soc` | `bess_snapshots.soc_percent` | **percent (0–100)**, joined on exact timestamp |
| `bess_capacity_kwh` | `bess_snapshots.capacity_kwh` | joined on exact timestamp |
| `solar_kw` | `site_energy_snapshots.solar_generation_kw` | separable solar |
| `genset_kw` | *(none)* | always empty — no genset exists |
| `grid_import_kw` / `grid_export_kw` | `site_energy_snapshots.grid_import_kw` / `.grid_export_kw` | raw |
| `bess_output_kw` | `site_energy_snapshots.bess_output_kw` | **signed**: positive = discharge, negative = charge. ~10.5% of rows are discharging. |
| `ev_charging_kw` | `.total_ev_charging_kw` | raw |
| `building_load_kw` / `lighting_load_kw` | `.building_load_kw` / `.lighting_load_kw` | raw |
| `data_source` | `.data_source` | **100% `twin`** (sim) |
| `sim_run_id` | `.sim_run_id` | NULL for rows predating run-attribution |

**Cadence / gaps (measured on the flagship depot):** 6,822 gaps; mean 17.9 min, **median 2.0 min**, min 0, **max 35,873 min (~24.9 days)**. The long gaps are run boundaries.

---

## File 2 — `service_events.csv`

**Source query:**

```sql
SELECT depot_id, stall_id, vehicle_id, asset_class_code, operation_code,
       started_at, ended_at, energy_kwh, data_source
FROM ottoq_service_detail_records
ORDER BY depot_id, coalesce(started_at, ended_at);
```

**1,770 rows · span 2026-06-01 → 2026-08-23.** One row per completed service operation (this *is* the `ServiceDetailRecord`).

| CSV column | Source table.column |
|---|---|
| `site_id` | `depot_id` |
| `service_point_id` | `stall_id` |
| `asset_id` | `vehicle_id` |
| `asset_class` | `asset_class_code` (`tesla_model_y_robotaxi_2024`, `waymo_jaguar_ipace_2024`, `zoox_robotaxi_2024`) |
| `operation_type` | `operation_code` (12 distinct: `charge_dcfc`, `charge_l2`, `detail`, `generic_service`, `inspect`, `interior_tidy`, `item_retrieval`, `remote_diagnostics`, `sensor_clean`, `software_update`, `triage_check`, `wash`) |
| `started_at_utc` / `ended_at_utc` | `started_at` / `ended_at` |
| `energy_kwh` | `energy_kwh` (NULL where not recorded) |
| `data_source` | `data_source` — **`twin` (sim) and `production`** |

**Production caveat:** the 51 `production` rows are a **single June-1 batch of `wash` operations with `started_at = NULL`, `stall_id = NULL`, and `energy_kwh = NULL`** (ended_at 2026-06-01T02:17:58Z). They read as a seed/test import, not a genuine production telemetry feed. All other rows are `twin`. Do not treat those 51 rows as real production service energy.

---

## File 3 — `arrivals.csv`

**Source:** `ottoq_vehicle_dispatches` unpivoted — `dispatched_at` → `departure`, `actual_return_at` → `arrival` — joined to `vehicles` for `home_depot_id` and `vehicle_class_code`.

**2,938 rows · span 2026-06-24 → 2026-08-23 · 100% `twin`.**

| CSV column | Source |
|---|---|
| `site_id` | `vehicles.home_depot_id` (dispatches carry no depot_id) |
| `ts_utc` | `dispatched_at` (departure) / `actual_return_at` (arrival) |
| `asset_id` | `vehicle_id` |
| `asset_class` | `vehicle_class_code`, falling back to `vehicles.category` where class is absent |
| `event_type` | `departure` \| `arrival` |
| `data_source` / `sim_run_id` | `data_source` / `sim_run_id` |

**Semantics note:** `ottoq_vehicle_dispatches` is the return-to-base record (dispatched at, returned at). An alternative arrival signal is the event stream `ottoq_events` (`event_type='twin.vehicle_arrived'`, 165 rows) — a strict subset, not used here to avoid double-counting. `vehicle_state_log` (92k rows) also encodes arrival/departure via state transitions (`arrived_at_gate`, `en_route_to_deployment`, …) if you want a finer-grained source.

---

## File 4 — `site_static.csv`

**3 rows** — assembled from `depots` + `ottoq_site_structures` + `ottoq_bess_units`.

| site_id | name | solar_nameplate_kw | bess_capacity_kwh | bess_max_discharge_kw |
|---|---|---|---|---|
| `11111111-…` | OTTOYARD Nashville Flagship | 720 (4 canopies × 180 kW DC) | 3000 | 1500 |
| `22222222-…` | OTTOYARD Benchmark (CRN A/B) | 540 (3 canopies × 180 kW DC) | 3000 | 1500 |
| `d0000000-…` | OTTOYARD Hardware Lab | *(none)* | *(none)* | *(none)* |

- `timezone` = `America/Chicago` (all). `latitude`/`longitude` = 36.1397 / -86.7728 (Nashville) for the two sim depots; the Hardware Lab has no lat/lng.
- `genset_nameplate_kw` = empty (no genset).
- **`min_service_auth_soc` is not site-level.** It is recorded per-operator in `ottoq_fleet_operator_slas.min_soc_at_deployment_pct` (= **80** for all 4 operators; `preferred_soc_at_deployment_pct` = 90), and per-vehicle in `vehicles.min_soc_threshold`. The column is left empty in `site_static.csv` to avoid silently faking a site-level value.

---

## Inference notes (things I had to interpret)

- **`generation_kw` / `load_kw` are computed**, not native columns — formulas above. Raw components are also exported so nothing is lossy.
- **BESS sign convention:** `bess_output_kw` positive = discharge (10.5% of rows), negative = charge. Verified by energy balance: `grid_import_kw ≈ building_load_kw + ev_charging_kw + BESS charge` at a sample row (796.7 ≈ 46.7 + 0 + 750).
- **`bess_snapshots` has duplicate timestamps** (61,288 rows → 56,614 distinct `(depot_id,timestamp)`); the join uses `DISTINCT ON (depot_id, timestamp) ORDER BY id DESC` to keep the latest.
- **`site_energy_snapshots` has byte-identical duplicate rows too** (idempotent re-writes — up to 4 identical copies of one row, same values, same `sim_run_id`). These were deduplicated with `DISTINCT ON (depot_id, timestamp) ORDER BY id DESC` (7,479 → 7,272 rows). This is exact-duplicate removal, **not** interpolation/resampling — the raw shape and all genuine gaps are preserved.
- **`depot_id` is the site key** (3 depots: two sim + one external hardware lab). No separate "site" table; `depots` is the canonical site registry.
