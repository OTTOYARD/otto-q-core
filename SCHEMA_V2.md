# SCHEMA_V2.md — Schema Mapping & Service Objects

**Run 2, Phase C3 deliverable.** 2026-08-19.
Artifacts: `db/migrations/0043_schema_v2_service_objects.sql` (the migration) +
`db/checks/0043_schema_v2_certification.sql` (the standing battery) + this document.
**Status: verified on a scratch instance; NOT yet applied to production** (§6, §7).

The instruction this phase executes: *migration path over what exists — not a rewrite, not a
parallel schema.* Every change below is classified **rename (view-wrap) / extend / new-object**,
and the strategic rule — **every completed operation terminates in a ServiceDetailRecord** — is
made structural, catalog-driven, and certified by a live-fire battery.

---

## 1. The mapping, change by change

| Kernel concept | Exists today as | 0043 does | Class |
|---|---|---|---|
| AssetClass | `ottoq_vehicle_classes` (7 classes) | + `pack_id`, + `energy_curve` (piecewise charge-acceptance, the 2.5 ">70% SoC" requirement as data), + `duty_cycle_profile`; v0 curve seeded where null | **extend** |
| Asset | `vehicles` | + `vehicle_class_code` FK — **the Asset→AssetClass binding did not exist at all**; nullable, heuristic backfill from `av_platform` (labeled in the column comment); `kernel_assets` view renames the vocabulary | **extend + view-wrap** |
| AssetProfile | `vehicle_need_profile`, `ottoq_vehicle_wear` | untouched; consumed as-is (formalized refs now live on the class row) | — |
| ServicePoint | `stalls` (427) | untouched; + `ottoq_service_point_capabilities` — the `(asset_class, operation)` pairs per point, seeded from `stall_type` × active classes with inlet-compatibility honored for charge operations; `kernel_service_points` view | **new-object (capabilities) + view-wrap** |
| Booking / calendar | `ottoq_stall_bookings` + EXCLUDE | **untouched — certified untouched** (battery A1) | — |
| Operations catalog | `service_definitions` (9), `service_cadence_policy` (15 svc codes), `ottoq_itinerary_legs.leg_type` CHECK (22 values), `ottoq_stall_bookings.purpose` CHECK (9 values) — four disjoint vocabularies | + `ottoq_operation_catalog`: one canonical operation vocabulary per pack, with **crosswalk columns** (`leg_type`, `booking_purpose`, `svc_code`) binding all four existing vocabularies; robotaxi pack = 23 rows (18 settleable + 5 movement/staging); flags: `parallel_with_charge`, `is_movement`, `energy_bearing`, `emits_sdr` | **new-object (pack data)** |
| Multi-tenant terms | `ottoq_fleet_operator_slas` | untouched; feeds ServiceToken seeding | — |
| Signed telemetry | `ottoq_events` + signing-key registry | untouched; **reused** — SDRs sign through the same `ottoq_resolve_signing_secret` machinery and emit `sdr_issued` / `sdr_costs_attached` events (both registered in `ottoq_event_types_catalog`) | — |
| Cost attribution | `ottoq_visit_cost_attribution` | untouched; **becomes the SDR's cost source** via an attach trigger (§3) | — |

Sector vocabulary (`vehicles`, `stalls`, wash/detail names) stays in the base tables; the kernel
naming layer is pure views (`kernel_assets`, `kernel_asset_classes`, `kernel_service_points`) —
rename-level generalization with zero data movement, exactly as 2.3 prescribes.

## 2. The six service objects (OCPI parallels in code comments, per the brief)

| Object | OCPI analogue | Implemented as | Why this shape |
|---|---|---|---|
| ServiceLocation | Location | **view** `service_locations` over `stalls`+`depots`+capabilities | The data already exists; a view can't drift from it |
| ServiceToken | Token | **table** `ottoq_service_tokens` (operator + asset scope + entitlements jsonb); seeded one per operator with an active SLA | Nothing held entitlements before |
| ServiceSession | Session | **view** `service_sessions` unifying `ottoq_stall_bookings` (twin/tick path) and `schedule_tasks` (production path) | Both session substrates already exist; "do not invent a parallel object" |
| **ServiceDetailRecord** | **CDR** | **table** `ottoq_service_detail_records` (§3) | The one genuinely new object the moat needs |
| ServiceTariff | Tariff | **table** `ottoq_service_tariffs` keyed `(pack, operation, asset_class, operator, window)`; house default per settleable operation seeded (price NULL = placeholder, link structural) | 2.6's key exactly; energy tariffs (`tariff_schedules`/`ottoq_depot_tariffs`) remain the utility-cost layer |
| ServiceProfile | ChargingProfile | **view** `service_profiles`: `site_power` rows from `ottoq_energy_plan` (the MPC plan, schedule-shaped — the 2.5 power-publication boundary observed) + `service_point` rows from forward bookings | The forward schedule already exists in two places; publishing is a projection |

## 3. The SDR, and how the structural rule works

`ottoq_service_detail_records`: one **signed, tariffed, operator-attributed, asset-class-tagged**
record per completed operation. It *evolves from* the two footholds rather than replacing them:

- **From the signed event stream:** every SDR is hashed with `ottoq_compute_event_hash`, signed
  HMAC-SHA-256 through the same key registry (`ottoq_sign_sdr`), and its issuance is itself a
  signed `sdr_issued` event in `ottoq_events` (`sdr_event_id` links them).
- **From cost attribution:** costs are not guessed at completion time. When
  `ottoq_visit_cost_attribution` lands for a schedule, a trigger attaches
  `attribution_id`/`cost_components`/`total_cost_usd`/`billable_amount_usd` to that schedule's
  SDRs and emits a signed `sdr_costs_attached` event. **Two-phase by design**: the issuance
  signature covers the immutable operational core; the money attaches with its own signed event
  (mirrors how CDRs finalize after sessions close).

**"Every completed operation terminates in an SDR" — the enforcement chain:**
1. **Trigger, twin/tick path:** `ottoq_itinerary_legs` status → `done` fires `ottoq_emit_sdr` for
   any leg whose `leg_type` maps to a catalog row with `emits_sdr` — in the same transaction as
   the completion, so a completion cannot commit without its SDR.
2. **Trigger, production path:** `schedule_tasks` status → `completed`, mapped via
   `service_code`/`service_definitions.code` → catalog `svc_code`, falling back to
   `generic_service`.
3. **Catalog-driven scope:** movement/staging legs (arrive/taxi/settle/stage/depart) emit
   nothing — and that is a *data* decision (`emits_sdr=false`), not kernel code. A pack that
   wants settleable moves flips a row.
4. **Idempotent:** `UNIQUE(leg_id)` / `UNIQUE(schedule_task_id)` + emit-side checks; status churn
   cannot double-issue (battery B2).
5. **Backfill:** operations completed before 0043 receive SDRs labeled
   `backfill_leg`/`backfill_task`.
6. **The falsifier:** `ottoq_check_sdr_coverage()` returns every completed operation lacking an
   SDR. Empty = the claim holds. It is battery check A3 and demonstrably catches a deliberately
   induced miss (battery B5).

Why triggers and a coverage function rather than a CHECK constraint: the constraint form is
circular (the completing row cannot reference the record its own commit must create), while
same-transaction triggers + a standing falsifier give the identical guarantee and an audit trail.

## 4. Run-scope, purge, and data_source discipline

- `ottoq_service_detail_records.sim_run_id` is **registered in `ottoq_run_scope_registry` as
  class `engine`** (mirroring `ottoq_events`), with the FK to `ottoq_sim_runs` the purge's
  block-check demands. Battery A2: zero blocks, zero unregistered run-scoped columns.
- Purge semantics, certified live-fire (B6): a doomed run's SDRs die with the run
  (children-first, before the parent delete); the kept run's and production's SDRs survive.
- `data_source`: `'twin'` when `sim_run_id` present, `'production'` otherwise — set by the
  emitter, checked by battery A7. Sim and real SDRs co-exist in one table exactly like
  `ottoq_events` rows do; the metrics layer cannot tell them apart except by the column. 

## 5. What 0043 deliberately does NOT do

- No existing table dropped, no column altered or removed, no existing constraint touched.
  The only pre-existing-row writes: the labeled class backfill on `vehicles` (nullable column)
  and the v0 `energy_curve` default on classes lacking one.
- No RLS policy on the five new tables (RLS enabled, deny-by-default; service role and the
  SECURITY DEFINER kernel functions are unaffected). Anon read surfaces can be added when a
  cockpit needs them.
- No pricing: house tariffs are seeded structurally with NULL prices. Money numbers arrive with
  the settlement work; the *linkage* is what C3 makes structural.
- No changes to the decide path, proposers, or twin functions (C4+ territory).

## 6. Scratch verification (the "scratch branch" evidence)

Supabase preview branching is unusable on this project — the tracked migration history does not
replay (`MIGRATIONS_FAILED` on the first migration; documented in `ottoyarddepot-sim/
supabase/proposed/README.md`). The scratch branch was therefore a **local PostgreSQL 16
instance** loaded with live-parity DDL: the `db/baseline/` sections for all 26 touched/referenced
tables, all 27 live enum types, the live (0022-era, registry-driven) `ottoq_purge_prior_runs` +
`ottoq_check_run_scope_registry`, the live signing/event machinery
(`ottoq_record_event`, `ottoq_sign_event`, `ottoq_canonicalize_payload`,
`ottoq_resolve_signing_secret`), the live v3 EXCLUDE constraint on `ottoq_stall_bookings`, and
the 0022-era engine-table FKs to `ottoq_sim_runs` (post-baseline in production, added for
parity). Seeded: 1 operator, 1 depot, 3 classes, 2 vehicles, 5 stalls, 2 sim runs (one running,
one completed), itineraries + 5 legs across both runs, bookings under the EXCLUDE constraint, a
production schedule task, SLAs, tariffs, an MPC energy plan, and a signed seed event.

Battery result (full transcript in the session log; re-runnable via
`db/checks/0043_schema_v2_certification.sql` — Part A read-only anywhere, Part B guarded behind
`ottoq.cert_livefire=on`):

```
A1 exclude_constraints  PASS   (EXCLUDE present, untouched)
A2 run_scope_registry   PASS   (0 blocks, 0 warns after registration)
A3 sdr_coverage         PASS   (0 uncovered completions)
A4 sdr_integrity        PASS   (0 unhashed)
A5 service_objects      PASS   (all six exist)
A6 house_tariffs        PASS   (every settleable op has an active house tariff)
A7 data_source          PASS   (0 twin/production labeling violations)
B1 PASS: leg completion -> signed SDR (op=wash, tariff linked); signature re-verified
B2 PASS: idempotent under status churn (1 SDR after re-completion)
B3 PASS: movement completion emits no SDR (catalog-driven)
B4 PASS: task -> SDR (energy 41.7 kWh) -> costs attached ($14.50 billable) + signed event
B5 PASS: coverage check detects a deliberately-missed completion, then closes it
B6 PASS: purge swept doomed-run SDRs; kept-run + production SDRs survive; purge not refused
```

Existing data survives: the migration ran against the seeded instance with every pre-existing
row intact afterward (additive DDL only; row counts identical apart from the two labeled
backfills and the new objects' own rows).

## 7. Production apply checklist (for the post-merge apply, per scripts/APPLYING.md)

1. `git fetch` + apply **from the merged file**, `--project-ref gxdrcyphqjzjsuhxuqtg`.
2. Expected duration well under the 15 s outage threshold (additive DDL + small seeds; the
   capability seed is ~427 stalls × 7 classes × ops ≈ tens of thousands of small rows — if the
   tick engine is busy, pause the run first per house rule anyway).
3. The MCP migration runner mis-parses `$$` bodies — this file already uses `$fn$`/`$cert$`
   quoting throughout, per the AGENTS.md landmine.
4. Post-apply: run battery **Part A only** (read-only) on production — expect 7× PASS. Do NOT
   set `ottoq.cert_livefire` on production.
5. Add the MIGRATION_LOG.md row (six columns) in the same PR; regenerate
   `scripts/check-drift.sql` via `gen-drift-sql.sh` (0043 carries a proper
   `migration-version:` header).
6. Known follow-on (C6): KPI views will read SDRs; no consumer exists yet, so applying 0043 is
   behaviorally invisible to every cockpit and edge function until then — the triggers only add
   writes on completion events.

## 8. Decisions a reviewer should challenge (owed answers)

- **Two-phase SDR (issue-then-attach-costs)** vs. re-issuing a superseding signed record when
  costs land: chosen for CDR-parity and to keep the issuance signature immutable. The
  `sdr_costs_attached` event carries the money provenance. Revisit if settlement requires the
  billable amount inside the signed core.
- **Sim SDRs die with their run** (engine class): consistent with `ottoq_events`; a sim run's
  SDRs are regenerable from the archived seed. If sim SDRs should become durable evidence,
  reclass to `evidence` + drop the FK — one registry row + one constraint, no schema change.
- **Movement legs emit no SDR** (v0): moves are scheduled operations (2.3) but not settleable
  events; the catalog flag makes this reversible per pack.
- **`generic_service` fallback** on the production path: an unmapped `service_code` still
  produces an SDR rather than silently escaping the rule; the honest alternative (refuse the
  completion) was rejected as an outage vector. Coverage stays clean either way; the fallback is
  visible in the SDR's `operation_code`.
