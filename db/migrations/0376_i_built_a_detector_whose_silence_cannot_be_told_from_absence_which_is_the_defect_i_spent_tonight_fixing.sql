-- migration-version: 20260920131500
-- migration-name:    i_built_a_detector_whose_silence_cannot_be_told_from_absence_which_is_the_defect_i_spent_tonight_fixing
--
-- 0376  0374's DETECTOR WRITES NOTHING WHEN THE SITE IS QUIET, AND WRITES NOTHING
--       WHEN IT IS NOT RUNNING. THOSE TWO STATES MUST NOT LOOK THE SAME.
--
-- Second correction to 0374, and the reason it is worth a migration is that this is
-- **the exact defect class the whole night was spent on, reproduced by me in the code
-- that fixed it.** `forces_recert` **TRUE** -- it changes what the tick path writes.
--
-- ══ 1. HOW IT WAS CAUGHT, WHICH IS THE ONLY REASON IT WAS ═══════════════════
--
-- After applying 0374 the determinism pair ran (`db/checks/0270`) and
-- `ottoq_site_power_ledger` read **`live_rows = 0`**. That is the CORRECT outcome:
-- the pair's peak import was **1,050.1 kW** against a 1,500 kW (60%) warn threshold,
-- so the detector had nothing to record. Verified separately by calling it by hand on
-- the pair's own run, where it returned
-- `{"tier": null, "total_kw": 498.2, "cap_kw": 2500, "headroom_kw": 2001.8}` and
-- wrote nothing.
--
-- **But `live_rows = 0` is also what a detector that never executed would produce**,
-- and nothing in the ledger distinguishes the two. That is `G82` exactly:
-- `ottoq_release_unusable_reservations` was correct, wired into a function the live
-- engine never called, and its silence read as "nothing to do" for two migrations.
-- 0367 closed that by making the unreportable state reportable. **0374 reopened the
-- same hole in new code** -- I proved the function works and inferred that the tick
-- runs it from `prosrc` matching `ottoq_detect_site_power_excursion(`, which is
-- inference, not observation. Better evidence than 0360 ever had; still not evidence.
--
-- Seventh instance of BUILD_QUEUE's standing heuristic, and the first where the thing
-- that exists and might never be called is something I wrote hours after writing the
-- heuristic down.
--
-- ══ 2. THE FIX: ONE ROW PER RUN, NOT ONE PER TICK ═══════════════════════════
--
-- A third tier, `armed`, written the first time the detector executes within a run.
-- One row per run -- so the volume argument that kept 0374 from logging every tick
-- does not apply -- and it makes the coverage question answerable from evidence that
-- survives a purge: **every run whose detector ran has an `armed` row, so a run that
-- lacks one was never covered.**
--
-- Three implementation points, each of which was a bug avoided rather than a choice:
--
-- (a) **The `snapshot_id` unique index had to become PARTIAL.** 0374 declared it
--     UNIQUE on `snapshot_id` alone. An `armed` row carries the first snapshot it
--     saw, and that same instant can later qualify as `high_water` or `excursion` --
--     at which point `ON CONFLICT (snapshot_id) DO NOTHING` would silently suppress
--     **the real finding**. So the index is now `WHERE severity_tier <> 'armed'`,
--     which preserves 0374's "one row per metered instant" invariant exactly for the
--     tiers it was written for.
--
-- (b) **`armed` dedups on the run, by the 0020/0124 zero-uuid idiom**, so a
--     production call (NULL run) matches a NULL run instead of inserting forever --
--     NULL is not equal to NULL in a unique index.
--
-- (c) **An EXISTS probe, not `INSERT … ON CONFLICT`.** An unconditional insert per
--     tick would no-op correctly but burn a `bigserial` value every time, because
--     `nextval` is non-transactional -- which is precisely the mechanism behind the
--     "28,262 allocated ids absent" in `db/checks/0231`. An index probe against the
--     new partial unique index costs less and leaves no gaps.
--
-- ══ 3. WHAT IS DELIBERATELY *NOT* DONE ═════════════════════════════════════
--
-- **No backfill of `armed` rows for the two runs that already happened.** The
-- detector did run on them -- it is wired, and both arms completed -- but I cannot
-- prove it from evidence, and writing a liveness record for a run whose liveness I am
-- inferring would be fabricating exactly the assurance this file exists to provide.
-- The beacon starts working on the next run. `runs_with_detector_armed` will read 0
-- until then, and that is the honest reading, not a fault.
--
-- Preconditions: no `ottoq_sim_runs` row `running` or `paused`.

-- ══ PREFLIGHT ═══════════════════════════════════════════════════════════════

DO $p1$
DECLARE v_live int;
BEGIN
  SELECT count(*) INTO v_live FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_live > 0 THEN
    RAISE EXCEPTION '0376 P1: % sim run(s) live -- this file rewrites a tick-path callee', v_live;
  END IF;
  IF to_regclass('public.ottoq_site_power_excursion_ledger') IS NULL THEN
    RAISE EXCEPTION '0376 P1: 0374 must be applied first';
  END IF;
  RAISE NOTICE '0376 P1: no live run; 0374 is present';
END $p1$;

DO $p2$
DECLARE v_idx text;
BEGIN
  --: Assert the hazard 2(a) describes is REAL before changing the index, so the
  --: change is justified by the schema rather than by my description of it.
  SELECT pg_get_indexdef(i.indexrelid) INTO v_idx
    FROM pg_index i
   WHERE i.indrelid = 'public.ottoq_site_power_excursion_ledger'::regclass
     AND i.indisunique
     AND pg_get_indexdef(i.indexrelid) LIKE '%snapshot\_id%';
  IF v_idx IS NULL THEN
    RAISE EXCEPTION '0376 P2: no unique index on snapshot_id found -- 0374''s shape has changed';
  END IF;
  IF v_idx LIKE '%WHERE%' THEN
    RAISE EXCEPTION '0376 P2: the snapshot_id unique index is already partial: % '
                    '-- reconcile before applying', v_idx;
  END IF;
  RAISE NOTICE '0376 P2: confirmed -- the snapshot_id unique index is unconditional, so an '
               'armed row on the same snapshot would suppress a real finding';
END $p2$;

-- ══ 1. THE THIRD TIER ═══════════════════════════════════════════════════════

ALTER TABLE public.ottoq_site_power_excursion_ledger
  DROP CONSTRAINT ottoq_site_power_excursion_ledger_severity_tier_check;

ALTER TABLE public.ottoq_site_power_excursion_ledger
  ADD CONSTRAINT ottoq_site_power_excursion_ledger_severity_tier_check
  CHECK (severity_tier IN ('excursion','high_water','armed'));

--: PARTIAL, per 2(a): an armed row shares its snapshot with whatever that instant
--: later turns out to be, and an unconditional unique index would let the beacon
--: suppress the finding. 0374's invariant is preserved for the tiers it was written
--: for, which is what that index was actually protecting.
DROP INDEX public.ottoq_site_power_excursion_ledger_snapshot_uq;
CREATE UNIQUE INDEX ottoq_site_power_excursion_ledger_snapshot_uq
  ON public.ottoq_site_power_excursion_ledger (snapshot_id)
  WHERE severity_tier <> 'armed';

--: One beacon per run. COALESCE to the zero uuid per the 0020/0124 idiom, because
--: NULL is not equal to NULL in a unique index and a production call would otherwise
--: insert a beacon on every tick forever.
CREATE UNIQUE INDEX ottoq_site_power_excursion_ledger_armed_uq
  ON public.ottoq_site_power_excursion_ledger
     (COALESCE(sim_run_id, '00000000-0000-0000-0000-000000000000'::uuid))
  WHERE severity_tier = 'armed';

-- ══ 2. THE DETECTOR, WITH THE BEACON ════════════════════════════════════════

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
  v_cap      numeric;
  v_cap_src  text;
  v_warn     numeric;
  v_snap     public.site_energy_snapshots%ROWTYPE;
  v_tier     text;
  v_dom      text;
  v_charging numeric;
  v_base     numeric;
  v_written  int := 0;
  v_armed    boolean := false;
BEGIN
  IF p_depot_id IS NULL THEN
    RETURN jsonb_build_object('skipped','no_depot');
  END IF;

  --: THE CAP IS READ, NEVER RE-DERIVED. ottoq_effective_charge_cap_kw is
  --: LEAST(service_max_kw, tightest active DR call) and is already the
  --: externally-declared site cap -- rule 5.
  v_cap := public.ottoq_effective_charge_cap_kw(p_sim_run_id, p_depot_id, p_sim_clock);

  --: NULL means no declared cap and is NOT zero. db/checks/0056 records the two
  --: depots where service_max_kw is NULL and EN.001's gate is therefore absent.
  IF v_cap IS NULL THEN
    RETURN jsonb_build_object('skipped','no_declared_cap','depot_id',p_depot_id);
  END IF;

  v_cap_src := CASE
    WHEN v_cap < (SELECT d.service_max_kw FROM public.depots d WHERE d.id = p_depot_id)
      THEN 'dr_call' ELSE 'service_max_kw' END;
  v_warn := v_cap * p_warn_frac;

  --: The snapshot for THIS tick already exists: twin.ottoq_sim_advance_site_energy is
  --: reached from ottoq_sim_advance_tick_world, which ottoq_demo_metronome calls at
  --: its line 100, before decide_and_dispatch at line 108. Checked against pg_proc
  --: rather than assumed -- G82 is what assuming a caller costs.
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
  -- 0376: THE BEACON. Without this, "ran and found the site quiet" and "never
  -- ran at all" are the same observation -- which is G82, and 0374 reproduced it
  -- in the code that fixed it. One row per run, so the volume argument that kept
  -- 0374 from logging every tick does not apply. EXISTS probe rather than
  -- INSERT … ON CONFLICT, because nextval is non-transactional and an
  -- unconditional per-tick insert would burn a bigserial value each time --
  -- the mechanism behind db/checks/0231's 28,262 absent ids.
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
      --: Another arm of the same pair beat us to it. Not an error.
      NULL;
    WHEN OTHERS THEN
      RAISE WARNING '0376 beacon: % %', SQLSTATE, SQLERRM;
    END;
  END IF;

  IF v_snap.grid_import_kw > v_cap THEN
    v_tier := 'excursion';
  ELSIF v_snap.grid_import_kw > v_warn THEN
    v_tier := 'high_water';
  ELSE
    RETURN jsonb_build_object('tier',NULL,'armed',v_armed,
                              'total_kw',v_snap.grid_import_kw,'cap_kw',v_cap,
                              'headroom_kw',round(v_cap - v_snap.grid_import_kw,1));
  END IF;

  --: Charging is bess_output_kw < 0. Surfaced as a positive magnitude because "the
  --: battery drew 968 kW" is the sentence a reader needs, and a sign convention is
  --: exactly what gets misread once the run is gone.
  v_charging := GREATEST(-COALESCE(v_snap.bess_output_kw, 0), 0);
  v_base     := COALESCE(v_snap.building_load_kw,0) + COALESCE(v_snap.lighting_load_kw,0);

  --: NOTE, per 0375: this is the LARGEST load, not the marginal one. Read
  --: ottoq_site_power_ledger's excursions_bess_deferral_clears to decide anything.
  v_dom := CASE
    WHEN COALESCE(v_snap.total_ev_charging_kw,0) >= GREATEST(v_charging, v_base) THEN 'ev_charging'
    WHEN v_charging >= v_base THEN 'bess_charging'
    ELSE 'base_load' END;

  INSERT INTO public.ottoq_site_power_excursion_ledger (
    sim_run_id, depot_id, snapshot_id, sim_clock, severity_tier,
    total_import_kw, cap_kw, excess_kw, warn_kw,
    ev_charging_kw, bess_output_kw, bess_charging_kw, base_load_kw, solar_kw,
    cap_source, dominant_component, source_kind)
  VALUES (
    p_sim_run_id, p_depot_id, v_snap.id, COALESCE(p_sim_clock, v_snap.timestamp), v_tier,
    v_snap.grid_import_kw, v_cap, round(v_snap.grid_import_kw - v_cap, 2), v_warn,
    v_snap.total_ev_charging_kw, v_snap.bess_output_kw, v_charging, v_base,
    v_snap.solar_generation_kw, v_cap_src, v_dom, 'live')
  ON CONFLICT (snapshot_id) WHERE severity_tier <> 'armed' DO NOTHING;

  v_written := CASE WHEN FOUND THEN 1 ELSE 0 END;

  --: The alarm fires for a true excursion only. A high_water row is tail data, not an
  --: incident, and an event per warm tick would train a reader to ignore the channel.
  --: Inside its own handler: an alarm that breaks a tick is worse than the condition.
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
                            'total_kw',v_snap.grid_import_kw,'cap_kw',v_cap,
                            'excess_kw',round(v_snap.grid_import_kw - v_cap,2),
                            'largest_component',v_dom,
                            'bess_deferral_would_clear',
                              (v_snap.grid_import_kw - v_charging) <= v_cap,
                            'snapshot_id',v_snap.id);
END;
$function$;

COMMENT ON FUNCTION ottoq.ottoq_detect_site_power_excursion(uuid,uuid,timestamptz,numeric) IS
'0374 (G89), beacon added by 0376, marginal-vs-largest wording corrected per 0375. Per-tick detector recording the instants at which this site''s TOTAL grid import crossed its declared cap, into ottoq_site_power_excursion_ledger (class=evidence). MEASURED ONLY: writes no assignment, refuses nothing, and does not touch EN.001.grid_capacity_ceiling -- whose load meter is EV-only, which is why a 2,738.8 kW total passed every rule the engine has. Reads the STORED total (site_energy_snapshots.grid_import_kw, asserted to reconstruct in 8,050 of 8,050 snapshots at a 0.10 kW worst residual) and reads the cap from ottoq_effective_charge_cap_kw: two second opinions are two things to keep in step. NULL cap means no declared cap and is skipped, not treated as zero (db/checks/0056). THREE TIERS: excursion (over cap, raises ottoq.site_power_excursion), high_water (over p_warn_frac, ledger row only, so a purge cannot erase how close the site ran), and armed -- ONE ROW PER RUN, written on first execution, because without it "ran and found the site quiet" and "never ran at all" are the same observation, which is G82 and which 0374 reproduced in the very code that fixed it. The beacon uses an EXISTS probe rather than INSERT ON CONFLICT because nextval is non-transactional and a per-tick insert would burn a bigserial value each time -- db/checks/0231''s 28,262 absent ids. dominant_component is the LARGEST load, not the marginal one; read ottoq_site_power_ledger''s excursions_bess_deferral_clears before acting on it.';

-- ══ 3. THE READER, WITH COVERAGE ════════════════════════════════════════════

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
    RAISE EXCEPTION '0376 P3: % object(s) depend on the view -- a DROP would take them too', v_deps;
  END IF;
  RAISE NOTICE '0376 P3: no dependents on the view';
END $p3$;

DROP VIEW public.ottoq_site_power_ledger;

CREATE VIEW public.ottoq_site_power_ledger AS
SELECT l.depot_id,
       count(*)                                                       AS readings,
       count(*) FILTER (WHERE l.severity_tier = 'excursion')          AS excursions,
       count(*) FILTER (WHERE l.severity_tier = 'high_water')         AS high_water,
       --: 0376: one per run in which the detector executed. A run absent here was
       --: never covered, which is the question 0374 could not answer about itself.
       count(*) FILTER (WHERE l.severity_tier = 'armed')              AS detector_armed_runs,
       --: 0341's assertion as a column rather than a promise, now over three tiers.
       (count(*) FILTER (WHERE l.severity_tier = 'excursion')
        + count(*) FILTER (WHERE l.severity_tier = 'high_water')
        + count(*) FILTER (WHERE l.severity_tier = 'armed')) = count(*)
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
       --: 0375: the LARGEST load, not what pushed us over. See the two counts below.
       mode() WITHIN GROUP (ORDER BY l.dominant_component)
         FILTER (WHERE l.severity_tier = 'excursion')                 AS largest_component,
       --: 0375's actionable pair: deferring a battery is schedulable, refusing a
       --: vehicle mid-charge breaks a service commitment.
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
'0374, corrected by 0375 and extended by 0376. The per-depot answer to "how often has this site exceeded its declared power cap, what would have cleared it, and was the detector even running" -- none of which any surviving table could answer before, because the total lives in site_energy_snapshots (class=engine, purged by the next demo run). READ excursions_bess_deferral_clears AND excursions_needing_ev_action, NOT largest_component: 0374 shipped that column as usual_dominant_component claiming it answered "what pushed us over", and it does not -- it reports the biggest load, which here is ev_charging (1,691.8 kW) while deferring the 968 kW BESS charge alone brings 2,738.8 under the 2,500 cap with 729 kW to spare. BOTH removals clear the cap there, so magnitude cannot pick between them; the discriminator is that a battery''s charge timing is schedulable arbitrage while a vehicle mid-charge is a service commitment with a required-ready-time, which is a judgement about the product stated here rather than computed into a column. detector_armed_runs is 0376''s coverage answer: one row per run in which the detector executed, so a run absent from it was never covered -- because live_rows=0 previously meant either "the site stayed quiet" or "nothing ever ran", which is G82 and which 0374 reproduced in the code that fixed it. It reads 0 until the next run starts, and that is honest rather than faulty: the two runs predating the beacon are NOT backfilled, since writing a liveness record for a run whose liveness is inferred would fabricate the assurance this exists to give. tiers_sum_to_readings is 0341''s lesson as a column, now over three tiers.';

-- ══ POSTFLIGHT ══════════════════════════════════════════════════════════════

DO $p4$
DECLARE v_rows int; v_exc int; v_armed int; v_sum boolean; v_partial int;
BEGIN
  --: The partial indexes are the safety of the whole file. Assert both shapes.
  SELECT count(*) INTO v_partial
    FROM pg_index i
   WHERE i.indrelid = 'public.ottoq_site_power_excursion_ledger'::regclass
     AND i.indisunique
     AND i.indpred IS NOT NULL;
  IF v_partial <> 2 THEN
    RAISE EXCEPTION '0376 P4: expected 2 partial unique indexes (snapshot + armed), found %', v_partial;
  END IF;

  SELECT readings, excursions, detector_armed_runs, tiers_sum_to_readings
    INTO v_rows, v_exc, v_armed, v_sum
    FROM public.ottoq_site_power_ledger
   WHERE depot_id = '11111111-1111-1111-1111-111111111111';

  IF v_rows IS NULL THEN
    RAISE WARNING '0376 P4: no ledger rows for the twin depot';
  ELSIF NOT v_sum THEN
    RAISE EXCEPTION '0376 P4: tiers do not sum to readings over three tiers -- 0341 again';
  ELSE
    RAISE NOTICE '0376 P4: % readings, % excursions, % armed runs, tiers sum', v_rows, v_exc, v_armed;
  END IF;

  --: 0374's 16 rows must be untouched. This file changes indexes and a function, not data.
  IF v_rows <> 16 THEN
    RAISE WARNING '0376 P4: expected 0374''s 16 backfilled rows, found % -- a run may have '
                  'started since', v_rows;
  END IF;
END $p4$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0376_i_built_a_detector_whose_silence_cannot_be_told_from_absence_which_is_the_defect_i_spent_tonight_fixing', true,
  'Second correction to 0374. Adds a third ledger tier, armed -- one row per run, written on the '
  'detector''s first execution -- because 0374''s live_rows=0 meant either "the site stayed quiet" '
  'or "the detector never ran", which is G82 and which 0374 reproduced in the code that fixed it. '
  'Makes the snapshot_id unique index PARTIAL (WHERE severity_tier <> armed) because an armed row '
  'shares its snapshot with whatever that instant later proves to be, and an unconditional index '
  'would let the beacon suppress a real finding. Beacon dedups on the run by the 0020/0124 '
  'zero-uuid idiom and uses an EXISTS probe rather than INSERT ON CONFLICT, since nextval is '
  'non-transactional and a per-tick insert would burn a bigserial value each time (0231''s 28,262 '
  'absent ids). No backfill of armed rows for the two prior runs: their liveness is inferred, and '
  'recording inferred liveness would fabricate the assurance. Changes what the tick path writes, '
  'so it invalidates canons.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
