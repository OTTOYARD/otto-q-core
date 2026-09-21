-- migration-version: 20260920155947
-- migration-name:    a_column_named_for_a_fifteen_minute_quantity_that_is_a_running_peak_in_sim_and_not_even_that_in_production
--
-- 0382  G90: `site_energy_snapshots.peak_demand_kw_15min` IS NOT A 15-MINUTE QUANTITY.
--       COMMENTS ONLY — the column, its neighbour, and the KPI that gets it right.
--
-- `forces_recert` **FALSE**. Three `COMMENT ON` statements; no schema, no function, no
-- data. Safe to apply while a run is live, and one is: demo run `562bf027` was at tick
-- ~259 when this was written. That is why there is no no-live-run preflight here — the
-- other migrations in this series rewrite tick-path functions and must wait for a quiet
-- depot; a column comment cannot affect a running tick, and asserting otherwise would be
-- ceremony rather than safety.
--
-- ══ 1. WHY A COMMENT IS THE WHOLE FIX ══════════════════════════════════════
--
-- G90 is recorded as low severity and *"nothing ships wrong today"*, and that holds:
-- **KPI 3 is correct.** `ottoq_kpi_peak_site_kw` computes
-- `max()` over `avg(grid_import_kw) OVER (… RANGE '00:15:00' PRECEDING …)` — it derives
-- its own rolling mean and deliberately ignores the conveniently-named column. So the
-- defect is purely that a reader who trusts the NAME gets a number 79% too high, and the
-- proportionate fix is to make the column say what it is. Renaming it would mean a
-- migration plus a sweep of every reader for no benefit the comment does not deliver.
--
-- ══ 2. RE-MEASURED, AND G90's "NEVER LESS" NEEDS SPLITTING BY POPULATION ════
--
-- FINDINGS records *"it is `>= grid_import_kw` in **1,139 of 1,139**, equal in 54, never
-- less"*, measured on run `5b37ee46`. Measured again 2026-09-20 on the twin depot, the
-- claim holds where it was made and **fails elsewhere**, and the split is the finding:
--
--   population                                   snaps   peak >= import   peak < import
--   sim run 562bf027 (busy_day, armed)             259        **259**            **0**
--   run 35aa33e3, run_by='production_live'       4,050          3,059          **991**
--   production rows, sim_run_id IS NULL          2,455          2,252          **203**
--
-- **Within a sim run it behaves as a monotone running peak of instantaneous import — so
-- reading it as a 15-minute average overstates. In production data it is not even that**,
-- dropping below instantaneous import in roughly a quarter of the production-live run's
-- snapshots. Whatever maintains it there resets or lags; `billing_period_peak_kw` sitting
-- beside it suggests a billing-period reset is involved, and this file does not guess
-- further.
--
-- **An aggregate over both populations would have read "1,281 of 7,020 are less" and
-- looked like a flat contradiction of G90.** It is not — it is two populations with
-- different behaviour, and the unscoped number describes neither. Same shape as
-- `db/checks/0250` on depot scope and `0275` §5 on certification arms outvoting a demo
-- run: the first version of this measurement was unscoped, and scoping it is what turned
-- a contradiction into a refinement.

COMMENT ON COLUMN public.site_energy_snapshots.peak_demand_kw_15min IS
'G90 / 0382: NOT A 15-MINUTE QUANTITY, DESPITE THE NAME. Do not read it as the demand-billing figure -- it overstates by ~79% against the true 15-minute rolling mean (1,529.2 vs this column''s 2,738.8 on run 5b37ee46). In SIM runs it behaves as a monotone running peak of INSTANTANEOUS grid_import_kw: measured 2026-09-20, >= grid_import_kw in 259 of 259 snapshots on run 562bf027 and in 1,139 of 1,139 on 5b37ee46, never less. In PRODUCTION data it is not even that -- 991 of 4,050 snapshots on the production_live run 35aa33e3, and 203 of 2,455 rows with sim_run_id IS NULL, read BELOW instantaneous import, so something resets or lags it there (billing_period_peak_kw beside it suggests a billing-period reset; not established here). NOTE THE SCOPING TRAP: aggregated over both populations it reads "1,281 of 7,020 are less", which looks like a flat contradiction of the sim-only finding and describes neither population. THE CORRECT SOURCE for demand billing is KPI 3, public.ottoq_kpi_peak_site_kw, which computes max() over avg(grid_import_kw) OVER (RANGE 15 minutes PRECEDING) and deliberately ignores this column. Kept rather than renamed because the KPI does not depend on it and a rename would mean sweeping every reader for no gain a comment does not give.';

COMMENT ON COLUMN public.site_energy_snapshots.billing_period_peak_kw IS
'0382, recorded beside peak_demand_kw_15min (G90) only to say what is NOT established: this column sits next to a mislabelled one and its own semantics have not been audited. Whether it is the demand-charge ratchet the tariff layer bills against, and whether it resets on a billing period, is unverified as of 2026-09-20. Do not infer its meaning from peak_demand_kw_15min''s, and do not infer from this comment that it is wrong -- only that nobody has checked.';

COMMENT ON COLUMN public.site_energy_snapshots.grid_import_kw IS
'The site''s TOTAL instantaneous grid import, and the trustworthy one. Asserted by 0374 P5 to equal GREATEST(total_ev_charging_kw - bess_output_kw + building_load_kw + lighting_load_kw - solar_generation_kw, 0) in 8,050 of 8,050 snapshots on the twin depot at a worst residual of 0.10 kW -- so it is the site total, not a component, and ottoq.ottoq_detect_site_power_excursion reads it rather than summing the parts itself. bess_output_kw is NEGATIVE when the battery charges, which is why it is subtracted. Prefer this column over peak_demand_kw_15min for any question about load, and KPI 3 over both for demand billing.';

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_description d
    JOIN pg_class c ON c.oid = d.objoid
    JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum = d.objsubid
   WHERE c.relname = 'site_energy_snapshots'
     AND a.attname IN ('peak_demand_kw_15min','billing_period_peak_kw','grid_import_kw')
     AND d.description IS NOT NULL AND length(d.description) > 0;
  IF v_n <> 3 THEN
    RAISE EXCEPTION '0382 P1: expected 3 column comments, found %', v_n;
  END IF;
  RAISE NOTICE '0382 P1: all three column comments present';
END $p1$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0382_a_column_named_for_a_fifteen_minute_quantity_that_is_a_running_peak_in_sim_and_not_even_that_in_production', false,
  'Documentation only -- three COMMENT ON COLUMN statements on site_energy_snapshots, no schema, '
  'no function, no data, so no canon is invalidated and it is safe to apply mid-run (demo run '
  '562bf027 was live at tick ~259). Closes G90 proportionately: peak_demand_kw_15min is not a '
  '15-minute quantity and overstates the demand-billing figure by ~79%, but KPI 3 '
  '(ottoq_kpi_peak_site_kw) derives its own rolling mean and ignores the column, so a comment is '
  'the whole fix and a rename would sweep every reader for no gain. RE-MEASURED AND SPLIT BY '
  'POPULATION: within sim runs it is a monotone running peak of instantaneous import (259 of 259 '
  'on 562bf027, 1,139 of 1,139 on 5b37ee46), but in production data it is not even that -- 991 of '
  '4,050 on the production_live run 35aa33e3 and 203 of 2,455 NULL-run rows read BELOW '
  'instantaneous import. Aggregated over both it reads "1,281 of 7,020 are less", which looks '
  'like a contradiction of G90 and describes neither population -- the same scoping trap as 0250 '
  'and 0275. Also comments grid_import_kw as the trustworthy total (0374 P5: reconstructs in '
  '8,050 of 8,050 at a 0.10 kW worst residual) and billing_period_peak_kw as explicitly '
  'unaudited, so nobody infers its meaning from its neighbour.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
