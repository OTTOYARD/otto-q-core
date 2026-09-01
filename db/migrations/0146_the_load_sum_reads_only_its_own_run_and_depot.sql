-- =====================================================================
-- 0146  The site-load sum reads only its own run and its own depot
-- =====================================================================
-- Convicted in db/checks/0067. public.ottoq_energy_orchestrate computes
-- v_desired_ev by summing the charge rate over ocpp_sessions with NO
-- sim_run_id predicate and NO depot_id predicate, filtering only on
-- id_token LIKE 'TWIN-%'. That token convention excludes production but
-- not other runs, and no reset clears sessions at other depots.
--
-- The contaminated sum reaches a decision through
--   v_ev := GREATEST(v_se.total_ev_charging_kw, v_desired_ev)
--   v_net_load := v_base_load + v_ev - v_solar
--   v_bess_dispatch := -LEAST(v_maxchg, GREATEST(0, v_recharge_ceiling - v_net_load))
-- Measured on the 14:10 pair: desired_ev_kw differed at 10 of 12 ticks
-- (up to 23 kW), net_load tracked it 1:1, and at tick 11 the difference
-- crossed a branch boundary — arm A held, arm B dispatched.
--
-- Both parameters this fix needs are ALREADY in the signature
--   (p_sim_run_id uuid, p_depot_id uuid, p_sim_clock timestamptz, p_tick_seq bigint)
-- so there is no signature change and no second arity to drop. This is a
-- pure body edit against a unique anchor.
--
-- The zero-uuid COALESCE idiom (0020/0124) keeps production, which runs
-- with a NULL sim_run_id, working unchanged.
-- =====================================================================

BEGIN;

-- ---------------------------------------------------------------------
-- 1. Pin: refuse to run against a body other than the one audited.
-- ---------------------------------------------------------------------
DO $pin$
DECLARE v_pin text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_pin
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';
  IF v_pin IS DISTINCT FROM '2a79619a6200bd259eee986159e44fa4' THEN
    RAISE EXCEPTION '0146 pin mismatch for ottoq_energy_orchestrate: got %', v_pin;
  END IF;
END $pin$;

-- ---------------------------------------------------------------------
-- 2. Exactly one arity, and the anchor appears exactly once.
--    Comments are stripped before counting (the comment-grep trap, 0062).
-- ---------------------------------------------------------------------
DO $anchor$
DECLARE
  v_arities int;
  v_src     text;
  v_anchor  text := $a$WHERE s.status='active' AND s.id_token LIKE 'TWIN-%';$a$;
  v_n       int;
BEGIN
  SELECT count(*) INTO v_arities
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';
  IF v_arities <> 1 THEN
    RAISE EXCEPTION '0146 expected exactly 1 arity, found %', v_arities;
  END IF;

  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g')
    INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';

  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN
    RAISE EXCEPTION '0146 expected the load-sum anchor exactly once, found %', v_n;
  END IF;
END $anchor$;

-- ---------------------------------------------------------------------
-- 3. Prove the new predicate actually excludes what the old one admitted.
--    Evaluated against synthetic values — nothing is inserted, so a
--    concurrent certification pair cannot see it. This check CAN fail:
--    if either added predicate were a no-op, the foreign row would still
--    match and the assert fires.
--
--    Be precise about what this establishes. It proves the PREDICATE
--    LOGIC excludes a foreign run and a foreign depot while still
--    admitting our own, and that the zero-uuid idiom leaves the
--    production (NULL run) path matching. It does NOT prove the function
--    behaves correctly end to end — §5 separately proves that this exact
--    logic is present in the installed body, and the behavioural proof is
--    the re-certification pairs that follow, not anything asserted here.
--    Stated plainly so the pair evidence is not skipped on the strength
--    of a green migration.
-- ---------------------------------------------------------------------
DO $proof$
DECLARE
  v_this_run   uuid := '11111111-1111-1111-1111-111111111111';
  v_other_run  uuid := '22222222-2222-2222-2222-222222222222';
  v_this_depot uuid := '33333333-3333-3333-3333-333333333333';
  v_other_depot uuid := '44444444-4444-4444-4444-444444444444';
  v_old bool; v_new_foreign_run bool; v_new_foreign_depot bool; v_new_own bool;
BEGIN
  -- old predicate: status + token only
  v_old := ('active' = 'active' AND 'TWIN-abc' LIKE 'TWIN-%');

  -- new predicate against a session from ANOTHER RUN at our own depot
  v_new_foreign_run := v_old
    AND COALESCE(v_other_run,  '00000000-0000-0000-0000-000000000000'::uuid)
      = COALESCE(v_this_run,   '00000000-0000-0000-0000-000000000000'::uuid)
    AND v_this_depot = v_this_depot;

  -- new predicate against a session from OUR run at ANOTHER DEPOT
  v_new_foreign_depot := v_old
    AND COALESCE(v_this_run,   '00000000-0000-0000-0000-000000000000'::uuid)
      = COALESCE(v_this_run,   '00000000-0000-0000-0000-000000000000'::uuid)
    AND v_other_depot = v_this_depot;

  -- new predicate against our own run at our own depot: must still match
  v_new_own := v_old
    AND COALESCE(v_this_run,   '00000000-0000-0000-0000-000000000000'::uuid)
      = COALESCE(v_this_run,   '00000000-0000-0000-0000-000000000000'::uuid)
    AND v_this_depot = v_this_depot;

  IF NOT v_old THEN
    RAISE EXCEPTION '0146 proof broken: the old predicate did not admit the synthetic row';
  END IF;
  IF v_new_foreign_run THEN
    RAISE EXCEPTION '0146 run predicate is a no-op: a foreign run still matched';
  END IF;
  IF v_new_foreign_depot THEN
    RAISE EXCEPTION '0146 depot predicate is a no-op: a foreign depot still matched';
  END IF;
  IF NOT v_new_own THEN
    RAISE EXCEPTION '0146 new predicate rejects our own run at our own depot';
  END IF;

  -- production keeps working: NULL run on both sides collapses to the zero uuid
  IF NOT (COALESCE(NULL::uuid,'00000000-0000-0000-0000-000000000000'::uuid)
        = COALESCE(NULL::uuid,'00000000-0000-0000-0000-000000000000'::uuid)) THEN
    RAISE EXCEPTION '0146 zero-uuid idiom broke the production (NULL run) path';
  END IF;
END $proof$;

-- ---------------------------------------------------------------------
-- 4. The edit.
-- ---------------------------------------------------------------------
DO $edit$
DECLARE
  v_def    text;
  v_anchor text := $a$WHERE s.status='active' AND s.id_token LIKE 'TWIN-%';$a$;
  v_repl   text := $a$WHERE s.status='active' AND s.id_token LIKE 'TWIN-%'
    AND COALESCE(s.sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
      = COALESCE(p_sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)
    AND st.depot_id = p_depot_id;$a$;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_def
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';

  IF position(v_anchor in v_def) = 0 THEN
    RAISE EXCEPTION '0146 anchor absent from pg_get_functiondef output';
  END IF;

  EXECUTE replace(v_def, v_anchor, v_repl);
END $edit$;

-- ---------------------------------------------------------------------
-- 5. Post-check: both predicates are present exactly once, the arity is
--    still one, and the body changed.
-- ---------------------------------------------------------------------
DO $post$
DECLARE
  v_src text; v_arities int; v_pin text;
BEGIN
  SELECT count(*) INTO v_arities
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';
  IF v_arities <> 1 THEN
    RAISE EXCEPTION '0146 arity changed to %', v_arities;
  END IF;

  SELECT regexp_replace(regexp_replace(p.prosrc,'/\*.*?\*/','','g'),'--[^\n]*','','g'),
         md5(pg_get_functiondef(p.oid))
    INTO v_src, v_pin
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate';

  IF v_pin = '2a79619a6200bd259eee986159e44fa4' THEN
    RAISE EXCEPTION '0146 body did not change — the replace was a no-op';
  END IF;
  IF position($a$AND st.depot_id = p_depot_id;$a$ in v_src) = 0 THEN
    RAISE EXCEPTION '0146 depot predicate missing after edit';
  END IF;
  IF position($a$= COALESCE(p_sim_run_id,'00000000-0000-0000-0000-000000000000'::uuid)$a$ in v_src) = 0 THEN
    RAISE EXCEPTION '0146 run predicate missing after edit';
  END IF;

  RAISE NOTICE '0146 applied; new pin %', v_pin;
END $post$;

-- ---------------------------------------------------------------------
-- 6. Every migration classifies itself (established by 0142).
--    This one changes engine behaviour, so it forces re-certification.
-- ---------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0146_the_load_sum_reads_only_its_own_run_and_depot', true,
        'Run- and depot-scopes the ocpp_sessions load sum in ottoq_energy_orchestrate. Changes BESS setpoints, so every canon moves.',
        now())
ON CONFLICT (name) DO UPDATE
   SET forces_recert = EXCLUDED.forces_recert,
       note          = EXCLUDED.note,
       classified_at = EXCLUDED.classified_at;

COMMIT;
