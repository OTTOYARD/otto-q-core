-- migration-version: 20260921001618
-- migration-name:    kpi_four_stops_counting_the_shields_own_safe_defaults_as_human_labour
--
-- 0391  KPI 4 STOPS COUNTING THE DETERMINISTIC SHIELD'S OWN SAFE-DEFAULT FALLBACKS AS HUMAN
--       LABOUR. AND THE ROWS IT NOW EXCLUDES ARE PUBLISHED, NOT DISCARDED.
--
-- `forces_recert` **FALSE**, and the reason is checkable rather than asserted: the only reader
-- of `public.ottoq_kpi_touch_events_per_turn` anywhere in the database is
-- `public.ottoq_kpi_five_raw`, `ottoq_cert_columns` declares canons as
-- (depot, scenario, seed, ticks) and carries no KPI, and `touch_events` is not one of the
-- fourteen atoms. This changes REPORTING, not engine behaviour. Safe to apply while a run is
-- live, and one is (`e8b8eb3e`).
--
-- ══ 1. THE DEFECT, MEASURED ON TWO SEEDS ═══════════════════════════════════
--
-- `db/checks/0286` (seed 101959) and `0288` §4 (seed 100020) both measured it, so it is not
-- one run's mix:
--
--                                  seed 101959      seed 100020
--   touch_events_per_turn (published)   **1.459**      **1.091**
--     touch_events_operator                 67             78
--     **touch_events_override**            **505**        **532**
--   human-attributable                  **0.171**      **0.140**
--
-- **Every override row is the engine.** On both runs each one carries
-- `l2_engine='deterministic_v1'` and `outcome_status='overridden_to_default'` — the L1 shield
-- declining a proposed action and taking its safe default. On seed 101959 that was 272 at
-- `task_start`, 231 at `redeployment`, 2 at `stall_assignment`. **That is automation refusing
-- to act, which is the opposite of a human touching a vehicle**, and KPI 4 is defined in
-- CLAUDE.md 2.9 as *"human interventions per asset-turn"*.
--
-- ══ 2. THE ASYMMETRY BEING CLOSED ══════════════════════════════════════════
--
-- The view computed its two halves to different standards. The operator half filters on
-- `ottoq_kpi_touch_actor_types WHERE human_actor` — a careful table that marks
-- `ottoq_engine`, `system`, `system_scheduler`, `solar_controller` and `unknown` as non-human,
-- and whose `unknown` row carries its own warning: *"deliberately NOT a touch: counting
-- unknown as human would inflate KPI-4 with every unattributed row."* **Someone thought hard
-- about exactly this failure.** The override half applied no actor filter at all, and
-- contributed 88% of the number.
--
-- **The new predicate is `override_id IS NOT NULL` rather than `overridden`.** `override_id`
-- is the pointer to an actual override record — the evidence that a human acted. Across all
-- 12,082 decisions held at the time of measurement it was populated **0** times, as were
-- `override_reason` and `override_rule_code`, and `ottoq_rule_overrides` holds **0** rows. So
-- no human override has ever been recorded in this engine, and the clause the view already
-- had — `OR d.override_id IS NOT NULL` — has never matched a row.
--
-- ══ 3. WHY THE EXCLUDED ROWS ARE PUBLISHED RATHER THAN DROPPED ═════════════
--
-- `0286` §4(b) named the one way this fix can be wrong: if some caller sets `overridden` for a
-- genuine human action **without** writing `override_id`, the new predicate UNDER-counts. That
-- is not a risk I can retire by reading — `ottoq_decisions` is `class='engine'` and purged, so
-- "all 12,082" was a moment, not the engine's life.
--
-- **So the number is not deleted, it is moved.** A new column
-- `touch_events_override_flag_only` counts exactly the rows this migration stops crediting —
-- `overridden` true with no `override_id` — and `ottoq_kpi_five`'s audit block publishes it
-- beside the headline. Anyone who believes those rows are human labour can add them back and
-- get the old number, and the reversibility note in `0185`'s audit doctrine is preserved:
-- **KPI 4 headline + audit.touch_events_override_flag_only = the pre-0391 figure.**
--
-- ══ 4. WHAT THIS DOES TO ALREADY-PUBLISHED NUMBERS, SAID PLAINLY ═══════════
--
-- The view is retroactive: it re-derives from `ottoq_decisions`, so **every run's KPI 4
-- changes the moment this lands**, including runs already quoted. Concretely, run `c8f678fb`'s
-- published **1.091 becomes 0.140**. That is the correction, not a regression — but a reader
-- comparing KPI 4 across the 0391 boundary is comparing two definitions, and
-- `ottoq_kpi_five`'s provenance block is where that has to be visible. Neither the other four
-- KPIs nor `not_reproducible` are touched: `touch_events_per_turn` is the only one of the five
-- that reads `ottoq_decisions.overridden`.

BEGIN;

-- ══ P0. PREFLIGHT ══════════════════════════════════════════════════════════
DO $p0$
DECLARE v_readers int; v_flagonly bigint; v_withid bigint;
BEGIN
  --: the forces_recert FALSE claim rests on this being the only reader. Assert it.
  SELECT count(*) INTO v_readers FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prosrc LIKE '%ottoq_kpi_touch_events_per_turn%'
     AND p.proname <> 'ottoq_kpi_touch_events_per_turn';
  IF v_readers <> 1 THEN
    RAISE EXCEPTION '0391 P0: expected exactly 1 reader of the view (ottoq_kpi_five_raw), found %. '
                    'Re-derive the forces_recert classification before applying.', v_readers
      USING ERRCODE='22023';
  END IF;

  --: and the premise: override_id must still be unpopulated, or the predicate swap is not
  --: the no-op-on-humans this file argues it is.
  SELECT count(*) FILTER (WHERE overridden AND override_id IS NULL),
         count(*) FILTER (WHERE override_id IS NOT NULL)
    INTO v_flagonly, v_withid FROM public.ottoq_decisions;
  RAISE NOTICE '0391 P0: decisions with overridden-but-no-override_id = %, with override_id = %',
    v_flagonly, v_withid;
  IF v_withid > 0 THEN
    RAISE NOTICE '0391 P0: NOTE — override_id is now populated on % row(s). That is the '
                 'human-override path finally being used, which is exactly what the new '
                 'predicate counts. Proceeding.', v_withid;
  END IF;
END $p0$;

-- ══ P1. THE VIEW ═══════════════════════════════════════════════════════════
CREATE OR REPLACE VIEW public.ottoq_kpi_touch_events_per_turn AS
 WITH turns AS (
         SELECT b.sim_run_id,
            count(*) FILTER (WHERE b.state = 'done'::text) AS n,
            count(*) FILTER (WHERE b.state <> 'done'::text) AS not_a_turn
           FROM ottoq_stall_bookings b
          GROUP BY b.sim_run_id
        ), counted AS (
         SELECT t.sim_run_id,
            t.n,
            t.not_a_turn,
            --: THE HUMAN HALF, unchanged. ottoq_kpi_touch_actor_types marks ottoq_engine,
            --: system, system_scheduler, solar_controller and unknown as non-human.
                CASE
                    WHEN t.sim_run_id IS NOT NULL THEN ( SELECT count(*) AS count
                       FROM ottoq_events e
                      WHERE e.sim_run_id = t.sim_run_id AND (e.actor_type IN ( SELECT k.actor_type
                               FROM ottoq_kpi_touch_actor_types k
                              WHERE k.human_actor)))
                    ELSE ( SELECT count(*) AS count
                       FROM ottoq_events e
                      WHERE e.sim_run_id IS NULL AND (e.actor_type IN ( SELECT k.actor_type
                               FROM ottoq_kpi_touch_actor_types k
                              WHERE k.human_actor)))
                END AS n_op,
            --: 0391. THE OVERRIDE HALF NOW REQUIRES EVIDENCE OF A HUMAN. `override_id` is the
            --: pointer to an actual override record; the bare `overridden` flag is set by the
            --: deterministic path for outcome_status='overridden_to_default' -- the L1 shield
            --: taking its safe default, which is automation REFUSING to act. Counting that as
            --: a human intervention overstated KPI 4 by 8.5x on seed 101959 and 7.8x on
            --: seed 100020. db/checks/0286, 0288 s4.
                CASE
                    WHEN t.sim_run_id IS NOT NULL THEN ( SELECT count(*) AS count
                       FROM ottoq_decisions d
                      WHERE d.sim_run_id = t.sim_run_id AND d.override_id IS NOT NULL)
                    ELSE ( SELECT count(*) AS count
                       FROM ottoq_decisions d
                      WHERE d.sim_run_id IS NULL AND d.override_id IS NOT NULL)
                END AS n_ov,
            --: 0391. THE ROWS THIS MIGRATION STOPS CREDITING, PUBLISHED RATHER THAN DROPPED.
            --: 0286 s4(b) named the one way the predicate swap can be wrong -- a caller that
            --: sets `overridden` for a real human action without writing override_id -- and
            --: that cannot be retired by reading, because ottoq_decisions is class='engine'
            --: and purged. So the excluded count travels with the headline and
            --: KPI4 + this column = the pre-0391 figure, exactly.
                CASE
                    WHEN t.sim_run_id IS NOT NULL THEN ( SELECT count(*) AS count
                       FROM ottoq_decisions d
                      WHERE d.sim_run_id = t.sim_run_id
                        AND d.overridden AND d.override_id IS NULL)
                    ELSE ( SELECT count(*) AS count
                       FROM ottoq_decisions d
                      WHERE d.sim_run_id IS NULL
                        AND d.overridden AND d.override_id IS NULL)
                END AS n_ov_flag_only
           FROM turns t
        )
 SELECT sim_run_id,
    n_op + n_ov AS touch_events,
    n AS turns,
        CASE
            WHEN n > 0 THEN round((n_op + n_ov)::numeric / n::numeric, 3)
            ELSE NULL::numeric
        END AS touch_events_per_turn,
    not_a_turn AS bookings_not_a_turn,
    n_op AS touch_events_operator,
    n_ov AS touch_events_override,
    n_ov_flag_only AS touch_events_override_flag_only
   FROM counted;

COMMENT ON VIEW public.ottoq_kpi_touch_events_per_turn IS
  '0391. KPI 4, "human interventions per asset-turn" (CLAUDE.md 2.9). The override half '
  'requires override_id IS NOT NULL -- evidence a human acted -- because the bare `overridden` '
  'flag is set by the deterministic path for outcome_status=''overridden_to_default'', the L1 '
  'shield taking its safe default. Counting the shield as human labour overstated this KPI '
  '8.5x on seed 101959 and 7.8x on seed 100020 (db/checks/0286, 0288). '
  'touch_events_override_flag_only publishes the rows now excluded, so headline + that column '
  'reproduces the pre-0391 figure and nobody has to trust the reading.';

-- ══ P2. SURFACE THE NEW DIAGNOSTIC IN THE REPORTER'S AUDIT BLOCK ═══════════
-- 0185's doctrine: "a correction invisible from the command that ships the number is half a
-- fix." The reporter must publish what changed, not just the changed value.
DO $p2$
DECLARE v_src text; v_old text; v_new text;
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc WHERE proname = 'ottoq_kpi_five_raw';
  v_old := '''touch_events_override'', touch_events_override)';
  v_new := '''touch_events_override'', touch_events_override,'
        || ' ''touch_events_override_flag_only'', touch_events_override_flag_only)';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0391 P2: ottoq_kpi_five_raw not found' USING ERRCODE='42883';
  END IF;
  IF position(v_old in v_src) = 0 THEN
    RAISE EXCEPTION '0391 P2: could not find the audit tuple to extend in ottoq_kpi_five_raw; '
                    'the reporter has changed shape and this patch must be re-derived'
      USING ERRCODE='22023';
  END IF;
  IF (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old) <> 1 THEN
    RAISE EXCEPTION '0391 P2: the audit tuple is not unique in ottoq_kpi_five_raw'
      USING ERRCODE='22023';
  END IF;
  EXECUTE replace(pg_get_functiondef((SELECT oid FROM pg_proc WHERE proname='ottoq_kpi_five_raw')),
                  v_old, v_new);
END $p2$;

-- ── CERT LINEAGE ───────────────────────────────────────────────────────────────
INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0391_kpi_four_stops_counting_the_shields_own_safe_defaults_as_human_labour', false,
  'Changes ottoq_kpi_touch_events_per_turn''s override half from (overridden OR override_id '
  'IS NOT NULL) to override_id IS NOT NULL, and adds touch_events_override_flag_only '
  'publishing the rows thereby excluded. FALSE, and the preflight asserts rather than assumes '
  'the basis: ottoq_kpi_five_raw is the view''s only reader anywhere in the database, '
  'ottoq_cert_columns declares canons as (depot, scenario, seed, ticks) and carries no KPI, '
  'and touch_events is not one of the fourteen atoms. No engine behaviour changes -- this is '
  'reporting only, and it is retroactive by construction because the view re-derives from '
  'ottoq_decisions, so run c8f678fb''s published 1.091 becomes 0.140. That is the correction '
  'rather than a regression, and headline + touch_events_override_flag_only reproduces the '
  'pre-0391 number exactly, per 0185''s reversibility doctrine.',
  now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

-- ══ P3. POSTFLIGHT — the reversibility identity must hold ══════════════════
DO $p3$
DECLARE r record; v_run uuid;
BEGIN
  SELECT sr.sim_run_id INTO v_run FROM public.ottoq_sim_runs sr
   WHERE sr.depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY sr.started_at DESC LIMIT 1;

  SELECT * INTO r FROM public.ottoq_kpi_touch_events_per_turn WHERE sim_run_id = v_run;
  IF r IS NULL THEN
    RAISE NOTICE '0391 P3: no touch-event row for run % (no bookings yet); view compiles', v_run;
  ELSE
    --: THE IDENTITY 0185 REQUIRES: the old headline must be recoverable from the new one.
    IF (r.touch_events + r.touch_events_override_flag_only)
       <> (r.touch_events_operator + r.touch_events_override + r.touch_events_override_flag_only) THEN
      RAISE EXCEPTION '0391 P3: reversibility identity failed' USING ERRCODE='23514';
    END IF;
    RAISE NOTICE '0391 P3: run % — KPI4 %, operator %, override %, flag_only % (pre-0391 headline '
                 'recoverable as (operator+override+flag_only)/turns)',
      v_run, r.touch_events_per_turn, r.touch_events_operator,
      r.touch_events_override, r.touch_events_override_flag_only;
  END IF;

  --: and the reporter must still build, with the new key present.
  IF NOT (public.ottoq_kpi_five(v_run) -> 'kpis' -> 'audit' -> 'touch_events_per_turn'
            ? 'touch_events_override_flag_only') THEN
    RAISE EXCEPTION '0391 P3: ottoq_kpi_five does not publish touch_events_override_flag_only'
      USING ERRCODE='23514';
  END IF;
  RAISE NOTICE '0391 P3: ottoq_kpi_five publishes the new diagnostic';
END $p3$;

COMMIT;
