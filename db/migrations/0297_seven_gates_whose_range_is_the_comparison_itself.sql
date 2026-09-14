-- migration-version: PENDING
-- migration-name:    0297_seven_gates_whose_range_is_the_comparison_itself
--
-- 0297  SEVEN GATES WHOSE RANGE IS THE COMPARISON ITSELF, AND THREE CLAMPS
--       0291 MISSED BECAUSE OF A CAST
--
-- Ten more dials out of the 37 ottoq_policy_set refuses. Every bound here is
-- READ OFF THE CONSUMER; none is chosen. All ten have ZERO live rows in
-- ottoq_policy_params -- they have only ever run on the caller's own fallback.
--
-- ---------------------------------------------------------------------------
-- PART 1 -- THE SEVEN GATES, AND WHY 0..1 IS A MEASUREMENT
--
-- A dial whose ONLY use in its consumer is a comparison against a fixed
-- threshold has exactly two behaviours. Every value on one side of the
-- threshold is behaviourally identical to every other value on that side: the
-- consumer cannot tell 1 from 7 from 10^9. So the range is not a judgement
-- call about what is "sensible" -- 0..1 is the SMALLEST interval that still
-- expresses both behaviours, and any wider interval admits values the consumer
-- provably cannot distinguish. Verified for each: P1 pins the comparison by
-- its exact source text, and the key is quoted nowhere else in the engine
-- except in comments, so there is no second site with different arithmetic.
--
--   key                                  cmp       min max dflt  consumer
--   one_live_bay_reservation_per_purpose >= 1      0   1   1     ottoq.ottoq_book_stall
--   overnight_recall_enabled             > 0       0   1   1     twin.ottoq_sim_auto_dispatch_tick
--   parking_may_use_inspection_zone      < 1       0   1   0     ottoq.ottoq_book_stall
--   prearrival_bay_reservation           < 1       0   1   1     ottoq.ottoq_reserve_inbound_bays
--   reopened_need_readmit_enabled        < 1       0   1   1     ottoq.ottoq_readmit_reopened_needs
--   stale_itinerary_unblocks_replan      >= 1      0   1   1     public.ottoq_plan_visit_itinerary
--   tech_approvals_required              > 0       0   1   0     ottoq.ottoq_stage_advance_approval
--
-- AND ONE OF THOSE SEVEN IS A NAME THAT LIES, which is worth catching here
-- rather than in a deck. `tech_approvals_required` reads like a COUNT -- how
-- many technician approvals a stage advance needs. Its consumer is
--
--     v_need_tech := COALESCE(
--       public.ottoq_policy_get(p_sim_run_id, 'tech_approvals_required', 0), 0) > 0;
--
-- a BOOLEAN. Setting it to 3 does not require three approvals; it requires
-- one, exactly as 1 does. Cataloguing it 0..1 is therefore the honest range
-- AND it is the loud failure: the day someone wires a real count, the catalog
-- refuses their 3 and they come here, instead of quietly getting "true".
-- Recorded in the row's own description so the next reader sees it.
--
-- ---------------------------------------------------------------------------
-- PART 2 -- THREE INLINE CLAMPS 0291 SHOULD HAVE CAUGHT, AND THE REASON IT DID NOT
--
--   booking_no_show_grace_min  min 0, no ceiling, dflt 15  ottoq.ottoq_release_vacated_spaces
--   leg_replan_max_attempts    min 0, no ceiling, dflt 3   ottoq.ottoq_release_vacated_spaces
--   visit_reopen_max_attempts  min 0, no ceiling, dflt 3   public.ottoq_reopen_visit_atoms
--
-- These are the 0291 shape exactly -- a GREATEST wrapping the read with a
-- literal floor -- so 0291's sweep should have found them and did not. The
-- difference is a CAST:
--
--   0291 found:  GREATEST(COALESCE(public.ottoq_policy_get(...,'reopened_need_dwell_min',5),5), 0)
--   0291 missed: GREATEST(public.ottoq_policy_get(...,'booking_no_show_grace_min',15)::int, 0)
--                                                                              ^^^^^
--
-- `::int` between the closing paren and the comma. 0291's own header already
-- recorded that the bounding literal sits on either side of the GREATEST and
-- that a COALESCE fallback impersonates a bound; the cast is a third variant
-- of the same lesson, and it is the reason "the inline-clamp shape is
-- exhausted" was wrong when I wrote it. It was not exhausted; my sweep was.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE DOES NOT PROVE
--
-- A3 proves the round trip the catalog exists to permit: ottoq_policy_set now
-- ACCEPTS each key (P2 proves it refuses them beforehand), clamps it to the
-- bound this file derived, and ottoq_policy_get reads the stored value back.
-- It does NOT prove the consumer's behaviour flips -- that needs a run, and
-- claiming it from a round trip would be the gap between "the write landed"
-- and "the engine acted on it". What connects them is asserted separately and
-- narrowly: P1 pins that the consumer reads the key AT the comparison, and
-- ottoq_policy_get is the engine's only read path for a dial.
--
-- forces_recert = FALSE. Inserts into ottoq_policy_param_catalog only.
-- ottoq_policy_get never reads that table (P3 asserts it), so no decide or
-- tick path can observe this file at all. No live row is written: A3's writes
-- go to a scratch run inside a block that raises on success, so the implicit
-- savepoint discards them.
--
-- EXPECTED EFFECT, PREDICTED BEFORE APPLYING
--   ottoq_policy_param_catalog rows                 123 -> 133
--   ottoq_policy_catalog_gap, read_uncatalogued      37 ->  27
--   ottoq_policy_params rows                       unchanged
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0297 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0297 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0297 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0297 P-: nothing in flight';
END $inflight$;

-- P0. ALL TEN ARE UNCATALOGUED, AND NONE HAS A LIVE ROW. The second half
-- matters: a dial with a live row has been written by a path that bypassed the
-- setter, and its effective default is not the caller's fallback.
DO $p0$
DECLARE v_cat int; v_live int; v_keys text[] := ARRAY[
  'one_live_bay_reservation_per_purpose','overnight_recall_enabled',
  'parking_may_use_inspection_zone','prearrival_bay_reservation',
  'reopened_need_readmit_enabled','stale_itinerary_unblocks_replan',
  'tech_approvals_required','booking_no_show_grace_min',
  'leg_replan_max_attempts','visit_reopen_max_attempts'];
BEGIN
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog
   WHERE param_key = ANY (v_keys);
  IF v_cat <> 0 THEN
    RAISE EXCEPTION '0297 P0: % of the ten are already catalogued; this file '
                    'would collide or silently no-op', v_cat;
  END IF;
  SELECT count(*) INTO v_live FROM public.ottoq_policy_params
   WHERE param_key = ANY (v_keys);
  IF v_live <> 0 THEN
    RAISE EXCEPTION '0297 P0: % live rows exist for these keys; the derivation '
                    'assumed the caller fallback is the effective value', v_live;
  END IF;
  RAISE NOTICE '0297 P0: ten keys uncatalogued, zero live rows -- fallback is the only value in force';
END $p0$;

-- P1. EVERY BOUND IS PINNED TO THE SOURCE IT WAS READ OFF. If a consumer's
-- comparison or clamp is edited, this file refuses rather than leaving a stale
-- copy in the catalog. Each fragment must appear EXACTLY ONCE in its own
-- function, and the key must be quoted nowhere else outside comments.
DO $p1$
DECLARE r record; v_hits int; v_n int := 0;
BEGIN
  FOR r IN
    SELECT * FROM (VALUES
      ('ottoq','ottoq_book_stall','one_live_bay_reservation_per_purpose',
       'AND public.ottoq_policy_get(p_sim_run_id, ''one_live_bay_reservation_per_purpose'', 1) >= 1'),
      ('ottoq','ottoq_book_stall','parking_may_use_inspection_zone',
       'AND public.ottoq_policy_get(p_sim_run_id, ''parking_may_use_inspection_zone'', 0) < 1 THEN'),
      ('ottoq','ottoq_reserve_inbound_bays','prearrival_bay_reservation',
       'IF public.ottoq_policy_get(p_sim_run_id, ''prearrival_bay_reservation'', 1) < 1 THEN'),
      ('ottoq','ottoq_readmit_reopened_needs','reopened_need_readmit_enabled',
       'IF COALESCE(public.ottoq_policy_get(p_sim_run_id,''reopened_need_readmit_enabled'',1),1) < 1'),
      ('public','ottoq_plan_visit_itinerary','stale_itinerary_unblocks_replan',
       'AND public.ottoq_policy_get(p_sim_run_id, ''stale_itinerary_unblocks_replan'', 1) >= 1 THEN'),
      ('ottoq','ottoq_stage_advance_approval','tech_approvals_required',
       'public.ottoq_policy_get(p_sim_run_id, ''tech_approvals_required'', 0), 0) > 0;'),
      ('twin','ottoq_sim_auto_dispatch_tick','overnight_recall_enabled',
       'ottoq_policy_get(p_sim_run_id,''overnight_recall_enabled'',1) > 0;'),
      ('ottoq','ottoq_release_vacated_spaces','booking_no_show_grace_min',
       'GREATEST(public.ottoq_policy_get(p_sim_run_id,''booking_no_show_grace_min'',15)::int, 0)'),
      ('ottoq','ottoq_release_vacated_spaces','leg_replan_max_attempts',
       'GREATEST(public.ottoq_policy_get(p_sim_run_id,''leg_replan_max_attempts'',3)::int, 0)'),
      ('public','ottoq_reopen_visit_atoms','visit_reopen_max_attempts',
       'GREATEST(COALESCE(public.ottoq_policy_get(v_run,''visit_reopen_max_attempts'',3)::int, 3), 0)')
    ) AS t(nsp, fn, param_key, frag)
  LOOP
    SELECT count(*) INTO v_hits
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = r.nsp AND p.proname = r.fn
       AND position(r.frag in p.prosrc) > 0;
    IF v_hits <> 1 THEN
      RAISE EXCEPTION '0297 P1: %.% no longer contains the exact clamp/comparison '
                      'this file read the range off for % (found %). Re-read it.',
                      r.nsp, r.fn, r.param_key, v_hits;
    END IF;
    v_n := v_n + 1;
  END LOOP;
  IF v_n <> 10 THEN
    RAISE EXCEPTION '0297 P1: pinned % sites, expected 10', v_n;
  END IF;
  RAISE NOTICE '0297 P1: all ten consumers still say what this file copied';
END $p1$;

-- P1b. NO SECOND READ SITE. A bound read off one site is wrong if another site
-- reads the same key with different arithmetic. Quoted mentions outside
-- comments must be exactly one per key.
DO $p1b$
DECLARE r record; v_reads int;
BEGIN
  FOR r IN SELECT unnest(ARRAY[
      'one_live_bay_reservation_per_purpose','overnight_recall_enabled',
      'parking_may_use_inspection_zone','prearrival_bay_reservation',
      'reopened_need_readmit_enabled','stale_itinerary_unblocks_replan',
      'tech_approvals_required','booking_no_show_grace_min',
      'leg_replan_max_attempts','visit_reopen_max_attempts']) AS k
  LOOP
    SELECT count(*) INTO v_reads
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace,
           LATERAL regexp_matches(p.prosrc,
             'ottoq_policy_get\s*\(\s*[^,]+,\s*''' || r.k || '''', 'g')
     WHERE n.nspname IN ('public','ottoq','twin');
    IF v_reads <> 1 THEN
      RAISE EXCEPTION '0297 P1b: % is read at % sites, not 1. The range was read '
                      'off one of them and may not hold at the others.', r.k, v_reads;
    END IF;
  END LOOP;
  RAISE NOTICE '0297 P1b: every one of the ten has exactly one read site';
END $p1b$;

-- P2. THE SETTER REFUSES ALL TEN RIGHT NOW. This is the finding itself,
-- executed rather than asserted: these are knobs no agent can turn.
DO $p2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029700cc'::uuid;
  r record; v_r jsonb; v_refused int := 0;
BEGIN
  FOR r IN SELECT unnest(ARRAY[
      'one_live_bay_reservation_per_purpose','overnight_recall_enabled',
      'parking_may_use_inspection_zone','prearrival_bay_reservation',
      'reopened_need_readmit_enabled','stale_itinerary_unblocks_replan',
      'tech_approvals_required','booking_no_show_grace_min',
      'leg_replan_max_attempts','visit_reopen_max_attempts']) AS k
  LOOP
    v_r := public.ottoq_policy_set('run', v_scratch, r.k, 1, '0297_probe');
    IF COALESCE((v_r->>'ok')::boolean, true) OR v_r->>'error' <> 'unknown_param' THEN
      RAISE EXCEPTION '0297 P2: the setter did NOT refuse % -- it answered %. '
                      'Either the key is catalogued or the setter no longer '
                      'guards on the catalog, and this file''s premise is void.',
                      r.k, v_r;
    END IF;
    v_refused := v_refused + 1;
  END LOOP;
  IF v_refused <> 10 THEN
    RAISE EXCEPTION '0297 P2: only % refusals, expected 10', v_refused;
  END IF;
  RAISE NOTICE '0297 P2: ottoq_policy_set refuses all ten (unknown_param)';
END $p2$;

-- P3. THE forces_recert=false ARGUMENT, EXECUTED. The read path must not be
-- able to see the catalog, or inserting rows into it changes engine behaviour.
DO $p3$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_policy_get'
     AND p.prosrc ~ 'ottoq_policy_param_catalog';
  IF v_n > 0 THEN
    RAISE EXCEPTION '0297 P3: ottoq_policy_get reads the catalog; this file is '
                    'no longer forces_recert=false';
  END IF;
  RAISE NOTICE '0297 P3: the read path still ignores the catalog';
END $p3$;

-- ===========================================================================
-- THE CHANGE -- ten catalog rows, every bound copied from the source P1 pins
-- ===========================================================================

INSERT INTO public.ottoq_policy_param_catalog
  (param_key, description, default_value, min_value, max_value, affects)
VALUES
  ('one_live_bay_reservation_per_purpose',
   '0297: gate. ottoq.ottoq_book_stall admits at most one live bay reservation '
   'per purpose while this is >= 1. The consumer''s only use is that comparison, '
   'so 0 and 1 are the only distinguishable values.',
   1, 0, 1, 'ottoq.ottoq_book_stall'),

  ('overnight_recall_enabled',
   '0297: gate. twin.ottoq_sim_auto_dispatch_tick runs the overnight surplus '
   'recall while this is > 0. Only use is that comparison.',
   1, 0, 1, 'twin.ottoq_sim_auto_dispatch_tick'),

  ('parking_may_use_inspection_zone',
   '0297: gate, and a KILL SWITCH -- default 0 is the new behaviour, >= 1 '
   'restores the old one (parking allowed to occupy the inspection zone). '
   'ottoq.ottoq_book_stall tests < 1. Only use is that comparison.',
   0, 0, 1, 'ottoq.ottoq_book_stall'),

  ('prearrival_bay_reservation',
   '0297: gate. ottoq.ottoq_reserve_inbound_bays returns immediately when this '
   'is < 1, so 0 disables pre-arrival bay reservation entirely.',
   1, 0, 1, 'ottoq.ottoq_reserve_inbound_bays'),

  ('reopened_need_readmit_enabled',
   '0297: gate. ottoq.ottoq_readmit_reopened_needs returns immediately when this '
   'is < 1. Only use is that comparison.',
   1, 0, 1, 'ottoq.ottoq_readmit_reopened_needs'),

  ('stale_itinerary_unblocks_replan',
   '0297: gate. public.ottoq_plan_visit_itinerary lets a stale itinerary be '
   'replanned while this is >= 1. Only use is that comparison.',
   1, 0, 1, 'public.ottoq_plan_visit_itinerary'),

  ('tech_approvals_required',
   '0297: gate, AND A NAME THAT LIES. Reads like a count of required technician '
   'approvals; the consumer is COALESCE(get(...),0) > 0, a boolean, so 3 '
   'requires exactly as many approvals as 1 -- one. Catalogued 0..1 because '
   'that is what the consumer can distinguish, and because the day someone '
   'wires a real count the catalog refuses their 3 loudly instead of silently '
   'answering "true". 0 = no technicians on site, stages auto-advance.',
   0, 0, 1, 'ottoq.ottoq_stage_advance_approval'),

  ('booking_no_show_grace_min',
   '0297: sim-minutes of grace before an un-enacted bay reservation is swept as '
   'no_show_grace_elapsed. Floor 0 COPIED from the GREATEST(...::int, 0) at the '
   'read site; no ceiling exists there, so none is invented here. 0291 missed '
   'this clamp because the ::int cast sits between the read and the comma.',
   15, 0, NULL, 'ottoq.ottoq_release_vacated_spaces'),

  ('leg_replan_max_attempts',
   '0297: how many times a travel leg may be replanned before the sweep gives '
   'up. Floor 0 COPIED from GREATEST(...::int, 0); no ceiling at the read site. '
   'Same ::int blind spot as booking_no_show_grace_min.',
   3, 0, NULL, 'ottoq.ottoq_release_vacated_spaces'),

  ('visit_reopen_max_attempts',
   '0297: loop bound so a thrashing vehicle terminates -- at this many reopen '
   'attempts public.ottoq_reopen_visit_atoms escalates instead of reopening. '
   'Floor 0 COPIED from GREATEST(COALESCE(...::int, 3), 0); no ceiling there.',
   3, 0, NULL, 'public.ottoq_reopen_visit_atoms');

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. Ten rows, and the counts this file predicted in its own header.
DO $a1$
DECLARE v_rows int; v_gap int; v_cat int;
BEGIN
  SELECT count(*) INTO v_rows FROM public.ottoq_policy_param_catalog
   WHERE description LIKE '0297:%';
  IF v_rows <> 10 THEN
    RAISE EXCEPTION 'A1 FAILED: % rows tagged 0297, expected 10', v_rows;
  END IF;
  SELECT count(*) INTO v_cat FROM public.ottoq_policy_param_catalog;
  IF v_cat <> 133 THEN
    RAISE EXCEPTION 'A1 FAILED: catalog holds % rows, predicted 133', v_cat;
  END IF;
  SELECT count(*) INTO v_gap FROM public.ottoq_policy_catalog_gap
   WHERE status = 'read_uncatalogued';
  IF v_gap <> 27 THEN
    RAISE EXCEPTION 'A1 FAILED: gap is %, predicted 27', v_gap;
  END IF;
  RAISE NOTICE 'A1 OK: catalog 123 -> 133, gap 37 -> 27';
END $a1$;

-- A2. EVERY BOUND FIRES AT ITS OWN NUMBER. Filtered on the description tag,
-- not on a hand-typed key list, so the test cannot silently cover fewer dials
-- than the file inserted (G25's defect class).
DO $a2$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029700cc'::uuid;
  v_r jsonb; r record; v_n int := 0;
BEGIN
  BEGIN
    FOR r IN
      SELECT c.param_key, c.min_value, c.max_value
        FROM public.ottoq_policy_param_catalog c
       WHERE c.description LIKE '0297:%'
       ORDER BY c.param_key
    LOOP
      v_r := public.ottoq_policy_set('run', v_scratch, r.param_key,
                                     r.min_value - 1, '0297_proof');
      IF COALESCE((v_r->>'applied')::numeric, -999) <> r.min_value
         OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
        RAISE EXCEPTION 'A2 FAILED: % below its floor must clamp to % and say so: %',
                        r.param_key, r.min_value, v_r;
      END IF;

      IF r.max_value IS NULL THEN
        v_r := public.ottoq_policy_set('run', v_scratch, r.param_key, 99999, '0297_proof');
        IF COALESCE((v_r->>'applied')::numeric, -1) <> 99999
           OR COALESCE((v_r->>'clamped')::boolean, true) THEN
          RAISE EXCEPTION 'A2 FAILED: % has no ceiling and must not clamp at 99999: %',
                          r.param_key, v_r;
        END IF;
      ELSE
        v_r := public.ottoq_policy_set('run', v_scratch, r.param_key,
                                       r.max_value + 1, '0297_proof');
        IF COALESCE((v_r->>'applied')::numeric, -1) <> r.max_value
           OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
          RAISE EXCEPTION 'A2 FAILED: % has a ceiling of % and must clamp to it: %',
                          r.param_key, r.max_value, v_r;
        END IF;
      END IF;
      v_n := v_n + 1;
    END LOOP;

    IF v_n <> 10 THEN
      RAISE EXCEPTION 'A2 FAILED: tested % dials, the file inserted 10', v_n;
    END IF;
    -- Reaching here means every check passed; raise to roll the scratch writes
    -- back through the implicit savepoint, exactly as 0290/0291 do.
    RAISE EXCEPTION 'A2_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A2_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A2 OK: all ten bounds fire at their own number; scratch writes discarded';
END $a2$;

-- A3. THE ROUND TRIP THE CATALOG EXISTS TO PERMIT. P2 proved the setter
-- refused these ten; this proves it now accepts one, clamps it, and that
-- ottoq_policy_get -- the engine's only read path for a dial -- reads back what
-- was stored. It does NOT prove the consumer's behaviour flips; see the header.
DO $a3$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000029700cc'::uuid;
  v_r jsonb; v_got numeric; v_got_hi numeric;
BEGIN
  BEGIN
    v_r := public.ottoq_policy_set('run', v_scratch, 'tech_approvals_required', 1, '0297_proof');
    IF NOT COALESCE((v_r->>'ok')::boolean, false) THEN
      RAISE EXCEPTION 'A3 FAILED: the setter still refuses tech_approvals_required: %', v_r;
    END IF;
    v_got := public.ottoq_policy_get(v_scratch, 'tech_approvals_required', 0);
    IF v_got IS DISTINCT FROM 1 THEN
      RAISE EXCEPTION 'A3 FAILED: set 1, read back %. The write did not reach the '
                      'read path the consumer uses.', v_got;
    END IF;

    -- the name that lies, demonstrated: 7 stores 1, and the consumer's "> 0"
    -- sees the same "on" either way.
    v_r := public.ottoq_policy_set('run', v_scratch, 'tech_approvals_required', 7, '0297_proof');
    v_got_hi := public.ottoq_policy_get(v_scratch, 'tech_approvals_required', 0);
    IF v_got_hi IS DISTINCT FROM 1 OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'A3 FAILED: 7 should clamp to 1 and say so; set returned %, read back %',
                      v_r, v_got_hi;
    END IF;

    RAISE EXCEPTION 'A3_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A3_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A3 OK: set -> clamp -> get round trip works; 7 lands as 1; scratch writes discarded';
END $a3$;

-- A4. NO RESIDUE. The probes above must have left nothing behind, or a later
-- run would resolve a dial off a scratch row instead of its fallback.
DO $a4$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000029700cc'::uuid
      OR updated_by IN ('0297_probe','0297_proof');
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: % probe row(s) survived; the savepoint rollback '
                    'did not work and a dial now has a live value it should not', v_n;
  END IF;
  RAISE NOTICE 'A4 OK: no probe rows survived';
END $a4$;
