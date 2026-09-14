-- migration-version: PENDING
-- migration-name:    0318_the_engine_stopped_guessing_and_the_label_kept_saying_guess
--
-- 0318  THE ETA IS COMPUTED NOW AND eta_source STILL SAYS 'policy_constant'
--
-- ---------------------------------------------------------------------------
-- WHAT A LIVE TWIN RUN SHOWED, twenty minutes after 0316 and 0317 landed
--
-- Run a5bd449f, started through twin.ottoq_sim_start_run with run_by='otto_twin'
-- and advanced with ottoq_sim_advance_tick -- the twin's own path, nothing
-- hand-driven. After three ticks:
--
--   positions:  53 of 55 packets carried a position, 53 DISTINCT     (0317 works)
--   ETAs:       33 dispatches, 18 DISTINCT values, 1.6 to 48.8 min   (0316 works)
--   eta_source: 'policy_constant:return_eta_minutes' on EVERY ROW    (this defect)
--
-- The value stopped being a constant and the LABEL kept saying it was one.
--
-- That is worse than it sounds. Before today the engine was admirably honest
-- about its guess: twin.ottoq_sim_advance_deployed_telemetry stamped
-- eta_source = 'policy_constant:return_eta_minutes' and wrote
-- 'eta_minutes_is_a_parameter', true into the evidence blob. Anyone auditing the
-- ledger could see exactly what they were looking at. 0316 made the number real
-- and left both of those stamps hard-coded, so the engine now understates itself
-- on 17 of 33 rows and -- far worse -- an auditor who trusts the label cannot
-- tell the 17 computed rows from the 16 that genuinely did fall back.
--
-- A label that no longer matches its value is the same defect class this repo
-- has convicted a dozen times, and I introduced this one two migrations ago.
--
-- ---------------------------------------------------------------------------
-- THE FIX
--
-- The computation runs ONCE into v_eta_computed. The ETA and both stamps are
-- then derived from that single value:
--
--   v_eta_min  = COALESCE(v_eta_computed, the policy dial)
--   eta_source = computed:distance_over_speed  when v_eta_computed IS NOT NULL
--                policy_constant:return_eta_minutes  otherwise
--   'eta_minutes_is_a_parameter' = (v_eta_computed IS NULL)
--
-- The fallback deliberately inlines the dial rather than calling
-- ottoq_return_eta_minutes again: that function would re-run the very
-- computation that just returned NULL, doing the work twice on the one path
-- where it is known to be fruitless.
--
-- NOTE the existing 'twin_eta_delay_card:*' stamp at line 173 is untouched. It
-- is a different and still-correct statement -- a delay card ADDED time to an
-- existing plan -- and 8,706 rows carry it. Overwriting it would erase the
-- record of why an ETA moved.
--
-- ---------------------------------------------------------------------------
-- FIVE EXACT SUBSTITUTIONS, each verified to occur exactly ONCE as a SUBSTRING
-- of pg_get_functiondef before this migration was written. That distinction is
-- not pedantry: 0317 was refused by its own check because '  END IF;' occurs
-- twice as a substring while occurring once as a whole line, and an earlier
-- check of mine measured lines while the substitution measured substrings.
-- The function is 21,920 bytes; retyping it would be the larger risk.
--
-- forces_recert: TRUE. eta_source and the return_evidence blob are run-scoped
-- content. Batched with the recert already owed by 0313, 0316 and 0317.
-- ===========================================================================

DO $pre$
DECLARE v_md5 text; v_live int;
BEGIN
  SELECT md5(p.prosrc) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';
  IF v_md5 IS DISTINCT FROM 'b74974bb22752536188ab68c12171673' THEN
    RAISE EXCEPTION '0318 P1: prosrc md5 is %, not what this migration was written against', COALESCE(v_md5,'ABSENT');
  END IF;

  -- P2. THE COMPUTATION IS WIRED AND WORKING, or relabelling would be a lie in
  --     the other direction.
  IF (SELECT p.prosrc FROM pg_proc p WHERE p.proname='ottoq_return_eta_minutes')
       NOT LIKE '%ottoq_computed_eta_minutes%' THEN
    RAISE EXCEPTION '0318 P2: ottoq_return_eta_minutes does not compute; 0316 is not applied and '
                    'stamping "computed" would be false';
  END IF;

  IF EXISTS (SELECT 1 FROM pg_stat_activity
              WHERE state='active' AND pid <> pg_backend_pid()
                AND (query ILIKE '%determinism_pair%' OR query ILIKE '%cert_arm%')) THEN
    RAISE EXCEPTION '0318 P3: a certification pair is in flight';
  END IF;
END $pre$;

DO $swap$
DECLARE
  v_def text; v_new text;
  c_decl_old CONSTANT text := '  v_ret_deferrable boolean; v_book jsonb; v_eta_min numeric;';
  c_decl_new CONSTANT text := '  v_ret_deferrable boolean; v_book jsonb; v_eta_min numeric;' || E'\n' ||
                              '  v_eta_computed numeric;   -- 0318: NULL means the computation refused';

  c_eta_old CONSTANT text := '      v_eta_min := ottoq_return_eta_minutes(v_dispatch.vehicle_id, NULL, p_sim_run_id);';
  c_eta_new CONSTANT text :=
    '      -- 0318: compute ONCE, then label honestly from the same value. The' || E'\n' ||
    '      -- fallback inlines the dial rather than calling ottoq_return_eta_minutes,' || E'\n' ||
    '      -- which would re-run the computation that just returned NULL.' || E'\n' ||
    '      v_eta_computed := public.ottoq_computed_eta_minutes(' || E'\n' ||
    '                          v_dispatch.vehicle_id,' || E'\n' ||
    '                          (SELECT COALESCE(vv.home_depot_id, rr.depot_id)' || E'\n' ||
    '                             FROM public.ottoq_sim_runs rr' || E'\n' ||
    '                             LEFT JOIN public.vehicles vv ON vv.id = v_dispatch.vehicle_id' || E'\n' ||
    '                            WHERE rr.sim_run_id = p_sim_run_id),' || E'\n' ||
    '                          p_sim_run_id, p_sim_clock_now);' || E'\n' ||
    '      v_eta_min := COALESCE(v_eta_computed,' || E'\n' ||
    '                            GREATEST(1, COALESCE(ottoq_policy_get(p_sim_run_id,''return_eta_minutes'',30), 30)));';

  c_src_old CONSTANT text := '               eta_source           = ''policy_constant:return_eta_minutes'',';
  c_src_new CONSTANT text := '               eta_source           = CASE WHEN v_eta_computed IS NOT NULL' || E'\n' ||
                             '                                      THEN ''computed:distance_over_speed''' || E'\n' ||
                             '                                      ELSE ''policy_constant:return_eta_minutes'' END,';

  c_par_old CONSTANT text := '                 ''eta_minutes_is_a_parameter'', true,';
  c_par_new CONSTANT text := '                 ''eta_minutes_is_a_parameter'', (v_eta_computed IS NULL),';

  c_ev_old CONSTANT text := '                 ''eta_source'', ''policy_constant:return_eta_minutes'',';
  c_ev_new CONSTANT text := '                 ''eta_source'', CASE WHEN v_eta_computed IS NOT NULL' || E'\n' ||
                            '                                 THEN ''computed:distance_over_speed''' || E'\n' ||
                            '                                 ELSE ''policy_constant:return_eta_minutes'' END,';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';

  IF (length(v_def) - length(replace(v_def, c_decl_old, ''))) / length(c_decl_old) <> 1 THEN
    RAISE EXCEPTION '0318 SWAP: DECLARE anchor not unique'; END IF;
  IF (length(v_def) - length(replace(v_def, c_eta_old,  ''))) / length(c_eta_old)  <> 1 THEN
    RAISE EXCEPTION '0318 SWAP: ETA assignment anchor not unique'; END IF;
  IF (length(v_def) - length(replace(v_def, c_src_old,  ''))) / length(c_src_old)  <> 1 THEN
    RAISE EXCEPTION '0318 SWAP: eta_source column anchor not unique'; END IF;
  IF (length(v_def) - length(replace(v_def, c_par_old,  ''))) / length(c_par_old)  <> 1 THEN
    RAISE EXCEPTION '0318 SWAP: is_a_parameter anchor not unique'; END IF;
  IF (length(v_def) - length(replace(v_def, c_ev_old,   ''))) / length(c_ev_old)   <> 1 THEN
    RAISE EXCEPTION '0318 SWAP: evidence eta_source anchor not unique'; END IF;

  v_new := replace(v_def, c_decl_old, c_decl_new);
  v_new := replace(v_new, c_eta_old,  c_eta_new);
  v_new := replace(v_new, c_src_old,  c_src_new);
  v_new := replace(v_new, c_par_old,  c_par_new);
  v_new := replace(v_new, c_ev_old,   c_ev_new);

  IF v_new = v_def THEN RAISE EXCEPTION '0318 SWAP: identical definition'; END IF;
  EXECUTE v_new;
END $swap$;

DO $post$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='twin' AND p.proname='ottoq_sim_advance_deployed_telemetry';

  IF position('computed:distance_over_speed' in v_src) = 0 THEN
    RAISE EXCEPTION '0318 A1: the honest label is absent'; END IF;
  IF position('v_eta_computed' in v_src) = 0 THEN
    RAISE EXCEPTION '0318 A1: the single computed value is absent'; END IF;
  -- The delay-card stamp must survive: 8,706 rows carry it and it says something
  -- different and still true.
  IF position('twin_eta_delay_card:' in v_src) = 0 THEN
    RAISE EXCEPTION '0318 A2: the delay-card eta_source stamp was destroyed'; END IF;
  -- The fallback label must survive too -- 0318 relabels, it does not delete.
  IF position('policy_constant:return_eta_minutes' in v_src) = 0 THEN
    RAISE EXCEPTION '0318 A2: the fallback label was destroyed; runs that genuinely fall back '
                    'must still say so'; END IF;
  -- Computed exactly once per dispatch on the tick path.
  IF (length(v_src) - length(replace(v_src, 'ottoq_computed_eta_minutes', ''))) / length('ottoq_computed_eta_minutes') <> 1 THEN
    RAISE EXCEPTION '0318 A3: the computation appears more than once on the tick path'; END IF;

  RAISE NOTICE '0318 applied. eta_source now reports which path produced the number.';
END $post$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES
  ('0318_the_engine_stopped_guessing_and_the_label_kept_saying_guess', true,
   'A live twin run (a5bd449f, run_by=otto_twin, three ticks) showed 0316 and 0317 working -- 53 of 55 '
   'packets positioned with 53 distinct positions, 33 dispatches carrying 18 distinct ETAs from 1.6 to '
   '48.8 min -- while eta_source still read ''policy_constant:return_eta_minutes'' on every row and the '
   'evidence blob still carried eta_minutes_is_a_parameter=true. The value stopped being a constant and '
   'the label kept saying it was one, so an auditor could not tell the 17 computed rows from the 16 that '
   'genuinely fell back. 0318 computes once into v_eta_computed and derives the ETA and both stamps from '
   'that single value. The delay-card stamp (8,706 rows) and the fallback label are both preserved and '
   'asserted -- this relabels, it does not delete. forces_recert=true; batched with the recert already '
   'owed by 0313, 0316 and 0317.',
   now())
ON CONFLICT (name) DO NOTHING;
