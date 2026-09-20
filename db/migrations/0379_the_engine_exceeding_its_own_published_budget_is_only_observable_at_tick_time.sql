-- migration-version: 20260920132449
-- migration-name:    the_engine_exceeding_its_own_published_budget_is_only_observable_at_tick_time
--
-- 0379  "EV LOAD EXCEEDED THE CAP IN FORCE" CANNOT BE ANSWERED BY ANY QUERY AFTER THE
--       RUN. MEASURE IT WHERE IT IS STILL TRUE.
--
-- `forces_recert` **TRUE** -- it changes what the tick-path detector reads and writes.
-- MEASURED ONLY: no assignment changes, no refusal, EN.001 untouched, and the cap stays
-- advisory.
--
-- ══ 1. WHY THIS IS NOT THE VIEW I SAID IT WOULD BE ══════════════════════════
--
-- `0378` deferred this finding with a specific reason: *"it pairs a cap against a LATER
-- snapshot, so it is not decidable from the inserted row... It belongs in a view over
-- two sources."* **That was wrong, and `db/checks/0271` §6 is why.** The engine reads
-- its cap through `ottoq_active_charge_cap_kw`, which filters `status = 'executed'`.
-- Measured on run `5b37ee46`:
--
--   charge_cap_kw commands       **1,260**
--   status = 'superseded'        **1,259**
--   status = 'executed'              **1**   <- and it is the FINAL command of the run
--
-- `status` is mutated in place by `twin.ottoq_sim_energy_controller` as each cap
-- replaces the last, so **only the last command of a run still reads `executed`.** A
-- view cannot reconstruct which cap was active at tick N no matter how it joins: the
-- column that would tell it has been overwritten 1,259 times.
--
-- I nearly recorded the opposite. Probing the accessor across all 1,260 snapshot clocks
-- returned non-NULL every time, which reads as "the cap was available throughout" and
-- is the reverse -- it returned that one surviving `executed` row, the final 1,031.4 kW
-- cap, for every tick, because its `issued_at + 15 min` is later than every earlier
-- clock. **A historical question asked with a present-tense predicate.** What caught it
-- was the answer being suspiciously clean.
--
-- ══ 2. WHY TICK TIME IS THE RIGHT PLACE, VERIFIED NOT ASSUMED ═══════════════
--
-- Checked against `pg_proc` rather than assumed, because G82 is what assuming a caller
-- costs. **Both** `ottoq_energy_orchestrate` (which publishes the cap) **and**
-- `twin.ottoq_sim_energy_controller` (which transitions its status) are called from
-- `ottoq_sim_advance_tick_world` -- which `ottoq_demo_metronome` invokes at its line
-- 100, before `ottoq_sim_decide_and_dispatch` at line 108. So when `0374`'s detector
-- runs, for this tick:
--
--   * the site energy snapshot exists  (already relied on by 0374)
--   * the charge cap is published AND status-transitioned
--   * `ottoq_active_charge_cap_kw` therefore returns the cap actually in force
--
-- That reading exists for the duration of one tick and is gone afterwards. Capturing it
-- is the only way the question becomes answerable at all -- which is a stronger reason
-- for a tick-time detector than the one `0374` had.
--
-- ══ 3. THE INVARIANT 0376 WROTE HAS TO CHANGE, AND THIS IS THE BUG AVOIDED ══
--
-- `0376` made the unique index `(snapshot_id) WHERE severity_tier <> 'armed'`, on the
-- stated invariant *"one row per metered instant"*. That was correct **while the tiers
-- were mutually exclusive** -- `excursion` and `high_water` come from one if/elsif and
-- cannot both fire.
--
-- **`ev_over_published_cap` is INDEPENDENT of both.** A tick can be over the site cap
-- and over the published EV cap at once, and under that index the second row would hit
-- `ON CONFLICT (snapshot_id) DO NOTHING` and **be silently dropped** -- the same class
-- of silent suppression `0376` itself was written to prevent, one tier later. So the
-- key becomes `(snapshot_id, severity_tier)`: one row per *instant per finding*, which
-- is the invariant that was actually wanted.
--
-- ══ 4. AND `excess_kw` IS NOT REUSED, DELIBERATELY ══════════════════════════
--
-- `excess_kw` means `total_import_kw - cap_kw` -- metered site total against the site
-- cap. For an `ev_over_published_cap` row the meaningful excess is a different
-- subtraction against a different cap, and putting it in the same column would make one
-- column mean two things depending on a neighbouring column's value. **That is exactly
-- G87 (`stranded_recharges`) and G90 (`peak_demand_kw_15min`)**, the two findings this
-- repo already carries about names that do not describe their contents, and the defect
-- `0375` corrected in my own code six migrations ago. A separate `ev_over_cap_kw`
-- column costs 8 bytes.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_live int;
BEGIN
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0379 P1: % sim run(s) live -- this rewrites a tick-path callee', v_live;
  END IF;
  IF to_regprocedure('ottoq.ottoq_detect_site_power_excursion(uuid,uuid,timestamptz,numeric)') IS NULL THEN
    RAISE EXCEPTION '0379 P1: 0374/0376''s detector is missing';
  END IF;
  IF to_regprocedure('public.ottoq_active_charge_cap_kw(uuid,uuid,timestamptz)') IS NULL THEN
    RAISE EXCEPTION '0379 P1: ottoq_active_charge_cap_kw is missing -- this file reads the '
                    'cap through the engine''s own accessor and must not define a second one';
  END IF;
  RAISE NOTICE '0379 P1: no live run; detector and accessor both present';
END $p1$;

DO $p2$
DECLARE v_def text;
BEGIN
  --: Assert 0376's index is keyed on snapshot_id ALONE before widening it, so the
  --: change is justified by the schema rather than by this file's description of it.
  SELECT pg_get_indexdef(i.indexrelid) INTO v_def
    FROM pg_index i
   WHERE i.indrelid = 'public.ottoq_site_power_excursion_ledger'::regclass
     AND i.indisunique
     AND pg_get_indexdef(i.indexrelid) LIKE '%(snapshot\_id)%';
  IF v_def IS NULL THEN
    RAISE EXCEPTION '0379 P2: no unique index keyed on (snapshot_id) alone -- 0376''s '
                    'shape has changed; reconcile before applying';
  END IF;
  RAISE NOTICE '0379 P2: confirmed -- % would drop an independent second finding on one '
               'snapshot', v_def;
END $p2$;

-- ══ 5. THE TIER, THE COLUMNS, THE KEY ═══════════════════════════════════════

ALTER TABLE public.ottoq_site_power_excursion_ledger
  DROP CONSTRAINT ottoq_site_power_excursion_ledger_severity_tier_check;

ALTER TABLE public.ottoq_site_power_excursion_ledger
  ADD CONSTRAINT ottoq_site_power_excursion_ledger_severity_tier_check
  CHECK (severity_tier IN ('excursion','high_water','armed','ev_over_published_cap'));

--: The cap the engine's own accessor returned at this tick. Not recoverable later --
--: see section 1. NULL on the tiers that do not read it.
ALTER TABLE public.ottoq_site_power_excursion_ledger
  ADD COLUMN published_cap_kw numeric;

--: A separate column rather than reusing excess_kw, per section 4.
ALTER TABLE public.ottoq_site_power_excursion_ledger
  ADD COLUMN ev_over_cap_kw numeric;

COMMENT ON COLUMN public.ottoq_site_power_excursion_ledger.published_cap_kw IS
'0379. The EV charge cap ottoq_active_charge_cap_kw returned AT THIS TICK, which is the only moment it is knowable: that accessor filters status = ''executed'', and twin.ottoq_sim_energy_controller rewrites each prior cap to ''superseded'' -- on run 5b37ee46, 1,259 of 1,260 commands read superseded and the single executed row is the final command of the run. No query after a run can reconstruct which cap was in force at tick N. NULL on tiers that do not read it.';

COMMENT ON COLUMN public.ottoq_site_power_excursion_ledger.ev_over_cap_kw IS
'0379. total_ev_charging_kw - published_cap_kw, populated only on the ev_over_published_cap tier. Deliberately NOT folded into excess_kw, which means total_import_kw - cap_kw (metered site total against the site cap): one column meaning two things depending on severity_tier would be G87/G90''s defect class, which 0375 already corrected once in this same instrument.';

--: PARTIAL AND COMPOSITE. 0376 keyed on snapshot_id alone on the invariant "one row per
--: metered instant", correct while excursion/high_water came from one if/elsif and could
--: not both fire. ev_over_published_cap is INDEPENDENT of both, so under the old key the
--: second finding on one snapshot would be silently dropped by ON CONFLICT DO NOTHING --
--: the suppression 0376 was itself written to prevent. One row per instant PER FINDING.
DROP INDEX public.ottoq_site_power_excursion_ledger_snapshot_uq;
CREATE UNIQUE INDEX ottoq_site_power_excursion_ledger_snapshot_uq
  ON public.ottoq_site_power_excursion_ledger (snapshot_id, severity_tier)
  WHERE severity_tier <> 'armed';

-- ══ 6. THE DETECTOR ═════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION ottoq.ottoq_detect_site_power_excursion(
  p_sim_run_id uuid,
  p_depot_id   uuid,
  p_sim_clock  timestamptz,
  p_warn_frac  numeric DEFAULT 0.60)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_cap       numeric;
  v_cap_src   text;
  v_warn      numeric;
  v_snap      public.site_energy_snapshots%ROWTYPE;
  v_tier      text;
  v_dom       text;
  v_charging  numeric;
  v_base      numeric;
  v_written   int := 0;
  v_armed     boolean := false;
  v_pubcap    numeric;
  v_ev_over   boolean := false;
BEGIN
  IF p_depot_id IS NULL THEN
    RETURN jsonb_build_object('skipped','no_depot');
  END IF;

  --: THE CAP IS READ, NEVER RE-DERIVED -- rule 5.
  v_cap := public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_sim_clock);

  --: NULL means no declared cap and is NOT zero (db/checks/0056).
  IF v_cap IS NULL THEN
    RETURN jsonb_build_object('skipped','no_declared_cap','depot_id',p_depot_id);
  END IF;

  v_cap_src := CASE
    WHEN v_cap < (SELECT d.service_max_kw FROM public.depots d WHERE d.id = p_depot_id)
      THEN 'dr_call' ELSE 'service_max_kw' END;
  v_warn := v_cap * p_warn_frac;

  --: advance_tick_world writes this before decide_and_dispatch runs (metronome lines
  --: 100 and 108), checked against pg_proc rather than assumed.
  SELECT s.* INTO v_snap
    FROM public.site_energy_snapshots s
   WHERE s.depot_id = p_depot_id
     AND (p_sim_clock IS NULL OR s.timestamp <= p_sim_clock)
     AND COALESCE(s.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
       = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
   ORDER BY s.timestamp DESC, s.id
   LIMIT 1;

  IF v_snap.id IS NULL THEN
    RETURN jsonb_build_object('skipped','no_snapshot_at_or_before_clock');
  END IF;

  -- ════════════════════════════════════════════════════════════════════════
  -- 0376: THE BEACON. Without it, "ran and found the site quiet" and "never ran"
  -- are the same observation -- G82, which 0374 reproduced in the code that fixed
  -- it. One row per run. EXISTS probe rather than INSERT … ON CONFLICT because
  -- nextval is non-transactional and a per-tick insert would burn a bigserial
  -- value each time (db/checks/0231's 28,262 absent ids).
  -- ════════════════════════════════════════════════════════════════════════
  IF NOT EXISTS (
        SELECT 1 FROM public.ottoq_site_power_excursion_ledger l
         WHERE l.severity_tier = 'armed'
           AND COALESCE(l.sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid)
             = COALESCE(p_sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid))
  THEN
    BEGIN
      INSERT INTO public.ottoq_site_power_excursion_ledger (
        sim_run_id, depot_id, snapshot_id, sim_clock, severity_tier,
        total_import_kw, cap_kw, excess_kw, warn_kw, cap_source, source_kind)
      VALUES (
        p_sim_run_id, p_depot_id, v_snap.id, COALESCE(p_sim_clock, v_snap.timestamp),
        'armed', v_snap.grid_import_kw, v_cap,
        round(v_snap.grid_import_kw - v_cap, 2), v_warn, v_cap_src, 'live');
      v_armed := true;
    EXCEPTION WHEN unique_violation THEN
      NULL;   --: another arm of the same pair beat us to it; not an error
    WHEN OTHERS THEN
      RAISE WARNING '0376 beacon: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  v_charging := GREATEST(-COALESCE(v_snap.bess_output_kw, 0), 0);
  v_base     := COALESCE(v_snap.building_load_kw,0) + COALESCE(v_snap.lighting_load_kw,0);

  --: NOTE, per 0375: the LARGEST load, not the marginal one. Read the view's
  --: excursions_bess_deferral_clears before acting on it.
  v_dom := CASE
    WHEN COALESCE(v_snap.total_ev_charging_kw,0) >= GREATEST(v_charging, v_base) THEN 'ev_charging'
    WHEN v_charging >= v_base THEN 'bess_charging'
    ELSE 'base_load' END;

  -- ════════════════════════════════════════════════════════════════════════
  -- 0379: DID THE SITE DRAW MORE EV LOAD THAN THE BUDGET IT PUBLISHED TO ITSELF?
  -- Read through the ENGINE'S OWN accessor, whose status='executed' filter makes
  -- this knowable for exactly one tick: twin.ottoq_sim_energy_controller rewrites
  -- every prior cap to 'superseded', so afterwards only the run's final command
  -- still reads executed and no query can reconstruct the rest. INDEPENDENT of the
  -- site-total tiers below -- a tick can be over both -- which is why 0376's
  -- unique key had to widen to (snapshot_id, severity_tier).
  -- ════════════════════════════════════════════════════════════════════════
  BEGIN
    v_pubcap := public.ottoq_active_charge_cap_kw(p_sim_run_id, p_depot_id, p_sim_clock);
    IF v_pubcap IS NOT NULL
       AND COALESCE(v_snap.total_ev_charging_kw, 0) > v_pubcap THEN
      INSERT INTO public.ottoq_site_power_excursion_ledger (
        sim_run_id, depot_id, snapshot_id, sim_clock, severity_tier,
        total_import_kw, cap_kw, excess_kw, warn_kw,
        ev_charging_kw, bess_output_kw, bess_charging_kw, base_load_kw, solar_kw,
        cap_source, dominant_component, published_cap_kw, ev_over_cap_kw, source_kind)
      VALUES (
        p_sim_run_id, p_depot_id, v_snap.id, COALESCE(p_sim_clock, v_snap.timestamp),
        'ev_over_published_cap',
        v_snap.grid_import_kw, v_cap, round(v_snap.grid_import_kw - v_cap, 2), v_warn,
        v_snap.total_ev_charging_kw, v_snap.bess_output_kw, v_charging, v_base,
        v_snap.solar_generation_kw, v_cap_src, v_dom,
        v_pubcap, round(COALESCE(v_snap.total_ev_charging_kw,0) - v_pubcap, 2), 'live')
      ON CONFLICT (snapshot_id, severity_tier) WHERE severity_tier <> 'armed' DO NOTHING;
      v_ev_over := true;
    END IF;
  EXCEPTION WHEN OTHERS THEN
    --: Its own handler: this reading is a measurement, and losing it must never cost
    --: the tick or the site-total finding below.
    RAISE WARNING '0379 ev_over_published_cap: % %', SQLSTATE, SQLERRM;
  END;

  IF v_snap.grid_import_kw > v_cap THEN
    v_tier := 'excursion';
  ELSIF v_snap.grid_import_kw > v_warn THEN
    v_tier := 'high_water';
  ELSE
    RETURN jsonb_build_object('tier',NULL,'armed',v_armed,
                              'ev_over_published_cap',v_ev_over,
                              'published_cap_kw',v_pubcap,
                              'total_kw',v_snap.grid_import_kw,'cap_kw',v_cap,
                              'headroom_kw',round(v_cap - v_snap.grid_import_kw,1));
  END IF;

  INSERT INTO public.ottoq_site_power_excursion_ledger (
    sim_run_id, depot_id, snapshot_id, sim_clock, severity_tier,
    total_import_kw, cap_kw, excess_kw, warn_kw,
    ev_charging_kw, bess_output_kw, bess_charging_kw, base_load_kw, solar_kw,
    cap_source, dominant_component, published_cap_kw, source_kind)
  VALUES (
    p_sim_run_id, p_depot_id, v_snap.id, COALESCE(p_sim_clock, v_snap.timestamp), v_tier,
    v_snap.grid_import_kw, v_cap, round(v_snap.grid_import_kw - v_cap, 2), v_warn,
    v_snap.total_ev_charging_kw, v_snap.bess_output_kw, v_charging, v_base,
    v_snap.solar_generation_kw, v_cap_src, v_dom, v_pubcap, 'live')
  ON CONFLICT (snapshot_id, severity_tier) WHERE severity_tier <> 'armed' DO NOTHING;

  v_written := CASE WHEN FOUND THEN 1 ELSE 0 END;

  IF v_tier = 'excursion' AND v_written = 1 THEN
    BEGIN
      PERFORM public.ottoq_record_event(
        p_actor_type   := 'ottoq_engine',
        p_actor_id     := 'site_power_excursion_detector',
        p_event_type   := 'ottoq.site_power_excursion',
        p_entity_type  := 'depot',
        p_entity_id    := p_depot_id,
        p_depot_id     := p_depot_id,
        p_payload      := jsonb_build_object(
                            'total_import_kw', v_snap.grid_import_kw,
                            'cap_kw', v_cap,
                            'cap_source', v_cap_src,
                            'excess_kw', round(v_snap.grid_import_kw - v_cap, 2),
                            'ev_charging_kw', v_snap.total_ev_charging_kw,
                            'bess_charging_kw', v_charging,
                            'base_load_kw', v_base,
                            'largest_component', v_dom,
                            'bess_deferral_would_clear',
                              (v_snap.grid_import_kw - v_charging) <= v_cap,
                            'published_cap_kw', v_pubcap,
                            'ev_over_published_cap', v_ev_over,
                            'snapshot_id', v_snap.id,
                            'sim_clock', p_sim_clock),
        p_severity     := 'critical',
        p_ingest_source := 'production',
        p_data_source  := CASE WHEN p_sim_run_id IS NULL THEN 'production' ELSE 'twin' END,
        p_sim_run_id   := p_sim_run_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING '0374 site_power_excursion alarm: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  RETURN jsonb_build_object('tier',v_tier,'written',v_written,'armed',v_armed,
                            'ev_over_published_cap',v_ev_over,
                            'published_cap_kw',v_pubcap,
                            'total_kw',v_snap.grid_import_kw,'cap_kw',v_cap,
                            'excess_kw',round(v_snap.grid_import_kw - v_cap,2),
                            'largest_component',v_dom,
                            'bess_deferral_would_clear',
                              (v_snap.grid_import_kw - v_charging) <= v_cap,
                            'snapshot_id',v_snap.id);
END;
$function$;

COMMENT ON FUNCTION ottoq.ottoq_detect_site_power_excursion(uuid,uuid,timestamptz,numeric) IS
'0374 (G89), beacon added by 0376, wording corrected by 0375, ev_over_published_cap added by 0379. Per-tick detector over this site''s power, writing to ottoq_site_power_excursion_ledger (class=evidence). MEASURED ONLY: no assignment changes, no refusal, EN.001 untouched, the published cap stays advisory. FOUR TIERS: excursion (metered total over the declared cap, raises ottoq.site_power_excursion), high_water (over p_warn_frac, so a purge cannot erase how close the site ran), armed (one row per run on first execution, because otherwise "ran and found the site quiet" is indistinguishable from "never ran" -- G82, which 0374 reproduced in the code that fixed it), and ev_over_published_cap (metered EV load above the cap ottoq_active_charge_cap_kw returned AT THIS TICK). THE LAST IS OBSERVABLE ONLY HERE: that accessor filters status = ''executed'' and twin.ottoq_sim_energy_controller rewrites each prior cap to ''superseded'', so on run 5b37ee46 1,259 of 1,260 commands read superseded and the one executed row is the run''s final command -- no query afterwards can reconstruct which cap was in force at tick N, which is why 0378''s plan to do this in a view was wrong. It is INDEPENDENT of the site-total tiers (a tick can be over both), so the ledger''s unique key is (snapshot_id, severity_tier): under 0376''s snapshot-only key the second finding would have been silently dropped by ON CONFLICT DO NOTHING, the exact suppression 0376 existed to prevent. Reads the STORED total and the cap from the engine''s own accessors rather than computing second opinions (db/checks/0264''s lesson). NULL site cap means no declared contract and is skipped, not zero (db/checks/0056).';

-- ══ 7. THE READER ═══════════════════════════════════════════════════════════

DO $p3$
DECLARE v_deps int;
BEGIN
  SELECT count(DISTINCT dependent.oid) INTO v_deps
    FROM pg_depend d
    JOIN pg_rewrite r ON r.oid = d.objid
    JOIN pg_class dependent ON dependent.oid = r.ev_class
   WHERE d.refobjid = 'public.ottoq_site_power_ledger'::regclass
     AND dependent.relname <> 'ottoq_site_power_ledger';
  IF v_deps > 0 THEN
    RAISE EXCEPTION '0379 P3: % object(s) depend on the view', v_deps;
  END IF;
  RAISE NOTICE '0379 P3: no dependents on the view';
END $p3$;

DROP VIEW public.ottoq_site_power_ledger;

CREATE VIEW public.ottoq_site_power_ledger AS
SELECT l.depot_id,
       count(*)                                                       AS readings,
       count(*) FILTER (WHERE l.severity_tier = 'excursion')          AS excursions,
       count(*) FILTER (WHERE l.severity_tier = 'high_water')         AS high_water,
       count(*) FILTER (WHERE l.severity_tier = 'armed')              AS detector_armed_runs,
       --: 0379. The engine drawing more than the budget it published to itself.
       count(*) FILTER (WHERE l.severity_tier = 'ev_over_published_cap')
                                                                      AS ev_over_published_cap,
       round(max(l.ev_over_cap_kw), 1)                                AS worst_ev_over_cap_kw,
       round(avg(l.ev_over_cap_kw), 1)                                AS mean_ev_over_cap_kw,
       --: 0341's lesson as a column rather than a promise, now over four tiers.
       (count(*) FILTER (WHERE l.severity_tier = 'excursion')
        + count(*) FILTER (WHERE l.severity_tier = 'high_water')
        + count(*) FILTER (WHERE l.severity_tier = 'armed')
        + count(*) FILTER (WHERE l.severity_tier = 'ev_over_published_cap')) = count(*)
                                                                      AS tiers_sum_to_readings,
       count(DISTINCT l.sim_run_id)                                   AS runs_seen,
       count(DISTINCT l.sim_run_id) FILTER (WHERE l.severity_tier = 'excursion')
                                                                      AS runs_with_excursion,
       max(l.cap_kw)                                                  AS cap_kw,
       round(max(l.total_import_kw), 1)                               AS worst_total_kw,
       round(max(l.excess_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_excess_kw,
       round(avg(l.total_import_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS mean_total_when_over,
       --: 0375: the LARGEST load, not the marginal one. Read the two counts below.
       mode() WITHIN GROUP (ORDER BY l.dominant_component)
         FILTER (WHERE l.severity_tier = 'excursion')                 AS largest_component,
       count(*) FILTER (WHERE l.severity_tier = 'excursion'
                          AND (l.total_import_kw - COALESCE(l.bess_charging_kw,0)) <= l.cap_kw)
                                                                      AS excursions_bess_deferral_clears,
       count(*) FILTER (WHERE l.severity_tier = 'excursion'
                          AND (l.total_import_kw - COALESCE(l.bess_charging_kw,0)) > l.cap_kw)
                                                                      AS excursions_needing_ev_action,
       round(max(l.bess_charging_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_bess_charging_kw,
       round(max(l.ev_charging_kw) FILTER (WHERE l.severity_tier = 'excursion'), 1)
                                                                      AS worst_ev_charging_kw,
       count(*) FILTER (WHERE l.source_kind = 'live')                 AS live_rows,
       count(*) FILTER (WHERE l.source_kind = 'backfill')             AS backfilled_rows,
       max(l.sim_clock)                                               AS last_reading_sim_clock,
       max(l.detected_at)                                             AS last_detected_at
  FROM public.ottoq_site_power_excursion_ledger l
 GROUP BY l.depot_id;

COMMENT ON VIEW public.ottoq_site_power_ledger IS
'0374, corrected by 0375, extended by 0376 and 0379. Four questions about this site''s power that no surviving table could answer before: how often the METERED total crossed the declared cap (excursions), how close it ran otherwise (high_water), whether the detector was even running (detector_armed_runs -- a run absent from it was never covered), and how often the engine drew more EV load than the budget it published to ITSELF (ev_over_published_cap). READ excursions_bess_deferral_clears AND excursions_needing_ev_action, NOT largest_component: 0374 shipped that column claiming it answered "what pushed us over" and it does not -- it reports the biggest load, which here is ev_charging (1,691.8 kW) while deferring the 968 kW BESS charge alone brings 2,738.8 under the 2,500 cap with 729 kW to spare. BOTH removals clear the cap there, so magnitude cannot pick; the discriminator is that a battery''s charge timing is schedulable arbitrage while a vehicle mid-charge is a service commitment carrying a required-ready-time, which is a judgement about the product stated here rather than computed into a column. ev_over_published_cap is the measurement for the open decision on whether charge_cap_kw should become binding inside the decide path -- and it is captured at tick time because it is unobservable afterwards: ottoq_active_charge_cap_kw filters status = ''executed'' and each prior cap is rewritten to ''superseded'', leaving only a run''s final command readable. tiers_sum_to_readings is 0341''s lesson as a column: if it reads false, a tier was added to the table and not to this view.';

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p4$
DECLARE v_idx text; v_rows int; v_sum boolean; v_cols int;
BEGIN
  SELECT pg_get_indexdef(i.indexrelid) INTO v_idx
    FROM pg_index i
   WHERE i.indrelid = 'public.ottoq_site_power_excursion_ledger'::regclass
     AND i.indisunique
     AND pg_get_indexdef(i.indexrelid) LIKE '%severity\_tier)%';
  IF v_idx IS NULL THEN
    RAISE EXCEPTION '0379 P4: the unique key was not widened to (snapshot_id, severity_tier)';
  END IF;

  SELECT count(*) INTO v_cols FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_site_power_excursion_ledger'
     AND column_name IN ('published_cap_kw','ev_over_cap_kw');
  IF v_cols <> 2 THEN
    RAISE EXCEPTION '0379 P4: expected both new columns, found %', v_cols;
  END IF;

  --: The new tier must be admissible and the old rows must be untouched.
  SELECT readings, tiers_sum_to_readings INTO v_rows, v_sum
    FROM public.ottoq_site_power_ledger
   WHERE depot_id = '11111111-1111-1111-1111-111111111111';
  IF NOT v_sum THEN
    RAISE EXCEPTION '0379 P4: tiers do not sum to readings over four tiers -- 0341 again';
  END IF;
  IF v_rows <> 18 THEN
    RAISE WARNING '0379 P4: expected 18 rows (16 backfill + 2 armed), found % -- a run '
                  'may have started since', v_rows;
  END IF;
  RAISE NOTICE '0379 P4: key widened, columns present, % readings, tiers sum', v_rows;
END $p4$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0379_the_engine_exceeding_its_own_published_budget_is_only_observable_at_tick_time', true,
  'Adds a fourth tier, ev_over_published_cap, to ottoq_site_power_excursion_ledger plus columns '
  'published_cap_kw and ev_over_cap_kw, and widens the unique key from (snapshot_id) to '
  '(snapshot_id, severity_tier). MEASURED ONLY: no assignment changes, EN.001 untouched, the cap '
  'stays advisory. 0378 deferred this finding to a view; that was WRONG per db/checks/0271 s6 -- '
  'ottoq_active_charge_cap_kw filters status = executed and twin.ottoq_sim_energy_controller '
  'rewrites each prior cap to superseded, so on run 5b37ee46 1,259 of 1,260 commands read '
  'superseded and the single executed row is the run final command. No query afterwards can '
  'reconstruct the cap in force at tick N, so it must be captured at tick time. The key had to '
  'widen because the new tier is INDEPENDENT of excursion/high_water (which come from one '
  'if/elsif and cannot both fire): under the snapshot-only key a second finding on one snapshot '
  'would be silently dropped by ON CONFLICT DO NOTHING, the exact suppression 0376 existed to '
  'prevent. ev_over_cap_kw is a separate column rather than a reuse of excess_kw because one '
  'column meaning two things by tier is G87/G90 defect class. Changes what the tick path reads '
  'and writes, so it invalidates canons.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
