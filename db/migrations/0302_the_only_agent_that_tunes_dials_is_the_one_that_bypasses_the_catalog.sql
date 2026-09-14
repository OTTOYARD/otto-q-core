-- migration-version: 20260914121021
-- migration-name:    0302_the_only_agent_that_tunes_dials_is_the_one_that_bypasses_the_catalog
--
-- 0302  THE ONLY AGENT THAT TUNES DIALS IS THE ONE THAT BYPASSES THE CATALOG
--
-- G62, and it turned out to be sharper than its title. The title said "the
-- catalog guards one of nine write paths". True, and measured again today:
-- nine database functions write public.ottoq_policy_params and exactly one --
-- public.ottoq_policy_set -- consults public.ottoq_policy_param_catalog.
--
-- But eight bypassers is not the finding. SEVEN of the eight are harness and
-- fixture code writing known, literal, catalogued keys onto their own scratch
-- runs: the determinism pair, its replay, the A/B pair, the cert arm, the grid
-- fixture, and the two MPC lookaheads (which delete their own rows again in the
-- same call). The finding is the ninth.
--
-- ---------------------------------------------------------------------------
-- WHAT public.ottoq_cil_tick ACTUALLY IS
--
-- It is a complete closed-loop policy-tuning agent, already built:
--
--   1. ottoq_cil_propose(run) generates four candidate policy plans --
--      'current', 'energy_shave_more', 'energy_relax', 'deploy_more'
--   2. ottoq_mpc_lookahead(run, plans, horizon, 'balanced') evaluates EVERY
--      plan forward in the twin, fork-and-rollback, with a 0-unsafe hard gate
--   3. it takes the best FEASIBLE plan that beats current by more than 0.01
--   4. IT ADOPTS IT -- writing the winning dials to DEPOT scope
--   5. it records the decision in ottoq_cil_adoptions and emits ottoq.cil_decision
--
-- Propose, simulate, score, adopt, record. That is the agentic loop, and it is
-- the only thing in this engine that changes a dial on its own judgement.
--
-- It writes them with a raw INSERT ... ON CONFLICT DO UPDATE. No catalog. So
-- the single autonomous dial-writer is the single write path with no allow-list
-- and no clamp, which is the precise inverse of what a day spent making the
-- catalog authoritative was for.
--
-- ---------------------------------------------------------------------------
-- AND THE TWO FLOORS DO NOT AGREE
--
-- ottoq_cil_propose self-clamps its own proposal:
--
--     GREATEST(0.15, v_efactor - 0.10)        -- energy_demand_factor_peak
--
-- The catalog says that dial's minimum is 0.25.
--
-- Because the adoption is a raw INSERT, the catalog's 0.25 never runs. Starting
-- from the 0.50 default, repeated adoptions of 'energy_shave_more' walk the
-- depot value 0.50 -> 0.40 -> 0.30 -> 0.20 -> 0.15, and the last two sit below
-- the floor the engine's own catalog declares safe. That dial is the
-- demand-target as a fraction of service_max: lower shaves the peak harder and
-- gives away charging throughput.
--
-- NOT CLAIMED: that this would be unsafe. The MPC's feasibility verdict stands
-- between the proposal and the adoption, and an infeasible plan is filtered out
-- by `WHERE (e->>'feasible')::boolean` before anything is written. The honest
-- claim is narrower and still worth fixing: TWO INDEPENDENT SAFETY MECHANISMS
-- DISAGREE ABOUT THE FLOOR BY 0.10, AND THE ONE IN THE PATH IS NOT THE ONE THAT
-- IS WRITTEN DOWN.
--
-- ---------------------------------------------------------------------------
-- BLAST RADIUS: ZERO, AND MEASURED
--
--   callers of ottoq_cil_tick in public/ottoq/twin    none
--   cron jobs referencing it                          none
--   rows ever written with updated_by='cil'           0
--   rows in ottoq_cil_adoptions                       0
--   ottoq.cil_decision events                         0
--
-- The loop has never run. Its only reachable caller is the OttoCommand edge
-- function (edge-functions/ottoq-ottocommand/index.ts line 76 calls it by RPC,
-- and line 78 exposes ottoq_cil_adoptions as "get_improvement_log"), so an
-- operator can invoke it and nobody ever has. P2 asserts all five zeros, which
-- is what makes this file safe to apply outside a certification window.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS FILE DOES, AND WHAT IT DELIBERATELY DOES NOT
--
-- DOES: routes the adoption through public.ottoq_policy_set, so the catalog
-- governs the agent exactly as it governs everything else, and records what the
-- setter actually did -- refused, clamped, or applied -- in the rationale that
-- the adoption row and the event carry. An adoption that got clamped now SAYS
-- it got clamped instead of recording a value that is not in force.
--
-- Note what that fixes without choosing a number: this file does not decide
-- whether 0.15 or 0.25 is the right floor. It routes the write through the
-- thing that already owns the answer, and makes the disagreement visible the
-- first time it bites.
--
-- DOES NOT: wire the loop to anything. Scheduling an agent that autonomously
-- adopts policy changes onto a live depot is the owner's decision, not a
-- migration's. It stays exactly as reachable as it was -- operator-invoked and
-- nothing else -- and it is now safe when someone does invoke it.
--
-- DOES NOT: touch ottoq_cil_propose's 0.15, ottoq_mpc_lookahead, the other
-- seven bypassing writers, or any grant.
--
-- ---------------------------------------------------------------------------
-- THE SET CLAUSE, WHICH 0295 COST US A MORNING TO LEARN
--
-- ottoq_cil_tick carries SET search_path TO 'twin','ottoq','public','extensions'.
-- CREATE OR REPLACE FUNCTION REPLACES proconfig -- omitting the SET clause
-- silently drops it. 0293 added a SET clause by accident and broke a procedure
-- for an hour; this is the same hazard from the other direction. The clause is
-- reproduced verbatim below and A2 asserts it survived.
--
-- forces_recert = FALSE. The function has no caller on any decide or tick path
-- -- it has no caller at all (P2) -- and has never executed, so no certified
-- run can have observed it.
-- ===========================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0302 P-: certification jobs are still scheduled (%)', v_jobs;
  END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0302 P-: a determinism pair is running right now';
  END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0302 P-: % sim run(s) are in flight', v_runs;
  END IF;
  RAISE NOTICE '0302 P-: nothing in flight';
END $inflight$;

-- P0. MD5 GUARD. Replace the definition this file was written against.
DO $p0$
DECLARE v_md5 text;
BEGIN
  SELECT md5(pg_get_functiondef(p.oid)) INTO v_md5
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';
  IF v_md5 IS DISTINCT FROM 'ea9798b79a672df456bf1222bd8ea04b' THEN
    RAISE EXCEPTION '0302 P0: ottoq_cil_tick is not the definition this file was '
                    'written against (live md5 %). Re-read it before replacing it.',
                    COALESCE(v_md5, '(absent)');
  END IF;
  RAISE NOTICE '0302 P0: ottoq_cil_tick md5 matches';
END $p0$;

-- P1. THE RAW INSERT THIS FILE REMOVES IS REALLY THERE, EXACTLY ONCE, and the
-- SET clause it must preserve is really there too.
DO $p1$
DECLARE v_src text; v_cfg text;
BEGIN
  SELECT p.prosrc, array_to_string(p.proconfig, ' | ') INTO v_src, v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';
  IF position('INSERT INTO ottoq_policy_params(scope_type, scope_id, param_key, param_value, updated_by)' in v_src) = 0 THEN
    RAISE EXCEPTION '0302 P1: the raw INSERT into ottoq_policy_params is not in '
                    'ottoq_cil_tick; this file has nothing to remove';
  END IF;
  IF position('VALUES (''depot'', v_depot, k, val::numeric, ''cil'')' in v_src) = 0 THEN
    RAISE EXCEPTION '0302 P1: the depot-scope VALUES clause is not as this file read it';
  END IF;
  IF position('public.ottoq_policy_set' in v_src) > 0 THEN
    RAISE EXCEPTION '0302 P1: ottoq_cil_tick already calls the setter; already fixed?';
  END IF;
  IF v_cfg IS DISTINCT FROM 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION '0302 P1: proconfig is %, not the search_path this file reproduces. '
                    'CREATE OR REPLACE would silently drop or change it (the 0293/0295 '
                    'hazard).', COALESCE(v_cfg, '(none)');
  END IF;
  RAISE NOTICE '0302 P1: raw INSERT present once, setter absent, search_path pinned';
END $p1$;

-- P2. BLAST RADIUS IS ZERO. Five independent zeros. If any is non-zero the loop
-- has run or is reachable from inside the engine, and this stops being a change
-- that can be made outside a certification window.
DO $p2$
DECLARE v_callers text; v_cron text; v_rows int; v_adopt int; v_events int;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin')
     AND p.proname <> 'ottoq_cil_tick'
     AND p.prosrc ~ 'ottoq_cil_tick';
  IF v_callers IS NOT NULL THEN
    RAISE EXCEPTION '0302 P2: ottoq_cil_tick now has in-database callers (%); the '
                    'zero-blast-radius argument is void', v_callers;
  END IF;

  SELECT string_agg(jobid::text||':'||jobname, ', ') INTO v_cron
    FROM cron.job WHERE command ~* 'cil_tick';
  IF v_cron IS NOT NULL THEN
    RAISE EXCEPTION '0302 P2: a cron job now invokes the loop (%)', v_cron;
  END IF;

  SELECT count(*) INTO v_rows  FROM public.ottoq_policy_params WHERE updated_by = 'cil';
  SELECT count(*) INTO v_adopt FROM public.ottoq_cil_adoptions;
  SELECT count(*) INTO v_events FROM public.ottoq_events WHERE event_type = 'ottoq.cil_decision';
  IF v_rows <> 0 OR v_adopt <> 0 OR v_events <> 0 THEN
    RAISE EXCEPTION '0302 P2: the loop HAS run -- % policy rows, % adoptions, % events. '
                    'Re-read what it did before changing it.', v_rows, v_adopt, v_events;
  END IF;

  RAISE NOTICE '0302 P2: no callers, no cron, 0 rows, 0 adoptions, 0 events -- never run';
END $p2$;

-- P3. THE TWO KEYS THE LOOP CAN WRITE ARE CATALOGUED, AND THE FLOOR
-- DISAGREEMENT THIS FILE DESCRIBES IS REAL. If propose stops floor-ing at 0.15,
-- or the catalog stops flooring at 0.25, the header is describing something
-- that no longer exists.
DO $p3$
DECLARE v_psrc text; v_min numeric; v_n int;
BEGIN
  SELECT p.prosrc INTO v_psrc
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_propose';
  IF position('GREATEST(0.15, v_efactor-0.10)' in v_psrc) = 0 THEN
    RAISE EXCEPTION '0302 P3: ottoq_cil_propose no longer floors '
                    'energy_demand_factor_peak at 0.15; re-read the header';
  END IF;

  SELECT count(*) INTO v_n FROM public.ottoq_policy_param_catalog
   WHERE param_key IN ('energy_demand_factor_peak','deploy_peak_fraction');
  IF v_n <> 2 THEN
    RAISE EXCEPTION '0302 P3: only % of the two keys the loop writes are catalogued; '
                    'routing through the setter would make it REFUSE them', v_n;
  END IF;

  SELECT min_value INTO v_min FROM public.ottoq_policy_param_catalog
   WHERE param_key = 'energy_demand_factor_peak';
  IF v_min IS DISTINCT FROM 0.25 THEN
    RAISE EXCEPTION '0302 P3: the catalog floor for energy_demand_factor_peak is %, '
                    'not the 0.25 this file contrasts against propose''s 0.15', v_min;
  END IF;
  RAISE NOTICE '0302 P3: both keys catalogued; propose floors 0.15, catalog floors 0.25';
END $p3$;

-- S. SNAPSHOT ---------------------------------------------------------------
INSERT INTO public.ottoq_schema_snapshots
  (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0302_pre', 'function', 'public', 'ottoq_cil_tick',
       pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';

-- ===========================================================================
-- THE CHANGE -- identical to the definition above except the adoption loop,
-- the three new DECLARE variables, and the rationale/payload that now carry
-- what the setter actually did. The SET clause is reproduced verbatim.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ottoq_cil_tick(p_sim_run_id uuid, p_horizon integer DEFAULT 3)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'twin', 'ottoq', 'public', 'extensions'
AS $function$
DECLARE
  v_plans jsonb; v_depot uuid; v_eval jsonb;
  v_cur_score numeric; v_best_label text; v_best_score numeric; v_best_params jsonb;
  k text; val text; v_adopted boolean := false; v_result jsonb; v_rationale text;
  -- 0302: what the sanctioned setter actually did with each adopted dial.
  v_set jsonb; v_writes jsonb := '[]'::jsonb; v_clamped int := 0; v_refused int := 0;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;
  v_plans := ottoq_cil_propose(p_sim_run_id);

  -- evaluate every plan forward in the twin (fork+rollback, 0-unsafe hard gate inside the MPC)
  SELECT jsonb_agg(jsonb_build_object('label',plan_label,'score',score,'feasible',feasible,
                                      'peak',predicted_peak_kw,'throughput',throughput,'readiness',am_readiness))
    INTO v_eval
    FROM ottoq_mpc_lookahead(p_sim_run_id, v_plans, p_horizon, 'balanced')
   WHERE NOT is_best AND plan_label IS NOT NULL;

  SELECT (e->>'score')::numeric INTO v_cur_score
    FROM jsonb_array_elements(v_eval) e WHERE e->>'label' = 'current';
  SELECT e->>'label', (e->>'score')::numeric INTO v_best_label, v_best_score
    FROM jsonb_array_elements(v_eval) e
   WHERE (e->>'feasible')::boolean AND (e->>'score') IS NOT NULL
   ORDER BY (e->>'score')::numeric DESC LIMIT 1;

  IF v_best_label IS NOT NULL AND v_best_label <> 'current'
     AND v_best_score > COALESCE(v_cur_score, -1) + 0.01 THEN
    SELECT e->'params' INTO v_best_params FROM jsonb_array_elements(v_plans) e WHERE e->>'label' = v_best_label;
    FOR k, val IN SELECT * FROM jsonb_each_text(v_best_params) LOOP
      -- 0302 (G62): this is the ONE agent in the engine that changes a dial on
      -- its own judgement, and it used to do it with a raw INSERT -- the single
      -- write path with no allow-list and no clamp. It goes through the
      -- sanctioned setter now, so the catalog governs the agent exactly as it
      -- governs everything else, and an uncatalogued key is REFUSED rather than
      -- silently written. The setter's verdict is kept, because an adoption
      -- that was clamped must not record the value it asked for.
      v_set := public.ottoq_policy_set('depot', v_depot, k, val::numeric, 'cil');
      v_writes := v_writes || jsonb_build_array(v_set);
      IF NOT COALESCE((v_set->>'ok')::boolean, false) THEN
        v_refused := v_refused + 1;
      ELSIF COALESCE((v_set->>'clamped')::boolean, false) THEN
        v_clamped := v_clamped + 1;
      END IF;
    END LOOP;
    v_adopted := true;
    v_rationale := format('Twin A/B: %s scored %s vs current %s (0-unsafe) → adopted to depot policy.',
                          v_best_label, round(v_best_score,3), round(coalesce(v_cur_score,0),3));
    -- 0302: say it plainly when the catalog overruled the agent. Silence here
    -- would leave ottoq_cil_adoptions.params claiming a value that is not in force.
    IF v_clamped > 0 OR v_refused > 0 THEN
      v_rationale := v_rationale || format(' CATALOG OVERRULED THE AGENT: %s of %s dial(s) clamped, %s refused as uncatalogued — see writes.',
                                           v_clamped, jsonb_array_length(v_writes), v_refused);
    END IF;
  ELSE
    v_rationale := format('Current policy is best (%s); no tweak beat it on a 0-unsafe basis.', round(coalesce(v_cur_score,0),3));
  END IF;

  INSERT INTO ottoq_cil_adoptions(sim_run_id, depot_id, adopted, plan_label, params, score_current, score_adopted, source, rationale, eval)
  VALUES (p_sim_run_id, v_depot, v_adopted, CASE WHEN v_adopted THEN v_best_label ELSE 'current' END,
          COALESCE(v_best_params,'{}'::jsonb), v_cur_score, CASE WHEN v_adopted THEN v_best_score ELSE v_cur_score END,
          'cil_heuristic', v_rationale, v_eval);

  PERFORM ottoq_record_event(
    p_actor_type:='ottoq_engine', p_actor_id:='cil', p_event_type:='ottoq.cil_decision',
    p_entity_type:='depot', p_entity_id:=v_depot, p_depot_id:=v_depot,
    p_payload:=jsonb_build_object('adopted',v_adopted,'plan',v_best_label,'rationale',v_rationale,'eval',v_eval,
                                  'writes',v_writes,'clamped',v_clamped,'refused',v_refused),
    p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);

  v_result := jsonb_build_object('adopted',v_adopted,'chosen',COALESCE(v_best_label,'current'),
     'score_current',v_cur_score,'score_chosen',COALESCE(v_best_score,v_cur_score),'rationale',v_rationale,'eval',v_eval,
     'writes',v_writes,'clamped',v_clamped,'refused',v_refused);
  RETURN v_result;
END;
$function$;

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- A1. The raw INSERT is gone and the setter is in its place, once.
DO $a1$
DECLARE v_src text; v_n int;
BEGIN
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';
  IF position('INSERT INTO ottoq_policy_params' in v_src) > 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the raw INSERT into ottoq_policy_params is still there';
  END IF;
  SELECT count(*) INTO v_n FROM regexp_matches(v_src, 'public\.ottoq_policy_set\(', 'g');
  IF v_n <> 1 THEN
    RAISE EXCEPTION 'A1 FAILED: ottoq_policy_set is called % times, expected exactly 1', v_n;
  END IF;
  IF position('''depot'', v_depot, k, val::numeric, ''cil''' in v_src) = 0 THEN
    RAISE EXCEPTION 'A1 FAILED: the setter is not being called with the depot scope, '
                    'the loop key and the cil attribution';
  END IF;
  RAISE NOTICE 'A1 OK: raw INSERT gone, exactly one setter call, depot-scoped and attributed';
END $a1$;

-- A2. THE SET CLAUSE SURVIVED. 0293 dropped one by accident and it cost a
-- morning; CREATE OR REPLACE replaces proconfig wholesale, so this is asserted
-- rather than assumed.
DO $a2$
DECLARE v_cfg text;
BEGIN
  SELECT array_to_string(p.proconfig, ' | ') INTO v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';
  IF v_cfg IS DISTINCT FROM 'search_path=twin, ottoq, public, extensions' THEN
    RAISE EXCEPTION 'A2 FAILED: proconfig is now %, not the search_path the function '
                    'had before. CREATE OR REPLACE dropped or changed it.',
                    COALESCE(v_cfg, '(none)');
  END IF;
  RAISE NOTICE 'A2 OK: search_path preserved verbatim';
END $a2$;

-- A3. THE CLAMP THIS FILE EXISTS FOR IS REAL. Not "the setter is called" -- the
-- actual number. 0.15 is what ottoq_cil_propose can propose after two
-- adoptions; the catalog floor is 0.25; the setter must move it and say so.
-- Written to a scratch depot inside a block that raises on success, so the
-- implicit savepoint discards every row.
DO $a3$
DECLARE
  v_scratch uuid := '00000000-0000-0000-0000-0000030200cc'::uuid;
  v_r jsonb; v_ok jsonb;
BEGIN
  BEGIN
    v_r := public.ottoq_policy_set('depot', v_scratch, 'energy_demand_factor_peak', 0.15, '0302_proof');
    IF COALESCE((v_r->>'applied')::numeric, -1) <> 0.25
       OR NOT COALESCE((v_r->>'clamped')::boolean, false) THEN
      RAISE EXCEPTION 'A3 FAILED: the agent''s 0.15 must clamp to the catalog''s 0.25 '
                      'and be reported as clamped; the setter said %', v_r;
    END IF;
    -- and a value inside the range must pass through untouched, or the clamp is
    -- just a constant and this test would pass for the wrong reason.
    v_ok := public.ottoq_policy_set('depot', v_scratch, 'energy_demand_factor_peak', 0.40, '0302_proof');
    IF COALESCE((v_ok->>'applied')::numeric, -1) <> 0.40
       OR COALESCE((v_ok->>'clamped')::boolean, true) THEN
      RAISE EXCEPTION 'A3 FAILED: 0.40 is inside 0.25..0.95 and must pass through '
                      'unclamped; the setter said %', v_ok;
    END IF;
    RAISE EXCEPTION 'A3_OK_ROLLBACK';
  EXCEPTION
    WHEN OTHERS THEN
      IF SQLERRM <> 'A3_OK_ROLLBACK' THEN RAISE; END IF;
  END;
  RAISE NOTICE 'A3 OK: 0.15 -> 0.25 clamped and reported; 0.40 passes through; writes discarded';
END $a3$;

-- A4. THE LOOP IS NO MORE REACHABLE THAN IT WAS. This file makes the agent
-- safe; it must not also switch it on. Same five zeros as P2.
DO $a4$
DECLARE v_callers text; v_cron text; v_rows int; v_adopt int; v_events int;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO v_callers
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname IN ('public','ottoq','twin') AND p.proname <> 'ottoq_cil_tick'
     AND p.prosrc ~ 'ottoq_cil_tick';
  SELECT string_agg(jobid::text, ', ') INTO v_cron FROM cron.job WHERE command ~* 'cil_tick';
  SELECT count(*) INTO v_rows   FROM public.ottoq_policy_params WHERE updated_by = 'cil';
  SELECT count(*) INTO v_adopt  FROM public.ottoq_cil_adoptions;
  SELECT count(*) INTO v_events FROM public.ottoq_events WHERE event_type = 'ottoq.cil_decision';
  IF v_callers IS NOT NULL OR v_cron IS NOT NULL OR v_rows <> 0 OR v_adopt <> 0 OR v_events <> 0 THEN
    RAISE EXCEPTION 'A4 FAILED: this file changed how reachable the loop is — callers %, '
                    'cron %, rows %, adoptions %, events %. It is meant to make the agent '
                    'safe, not to switch it on.', v_callers, v_cron, v_rows, v_adopt, v_events;
  END IF;
  RAISE NOTICE 'A4 OK: still operator-invoked only, still never run';
END $a4$;

-- A5. NO RESIDUE from A3's scratch writes.
DO $a5$
DECLARE v_n int;
BEGIN
  SELECT count(*) INTO v_n FROM public.ottoq_policy_params
   WHERE scope_id = '00000000-0000-0000-0000-0000030200cc'::uuid
      OR updated_by = '0302_proof';
  IF v_n <> 0 THEN
    RAISE EXCEPTION 'A5 FAILED: % scratch row(s) survived', v_n;
  END IF;
  RAISE NOTICE 'A5 OK: no scratch rows survived';
END $a5$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0302_the_only_agent_that_tunes_dials_is_the_one_that_bypasses_the_catalog', false,
 'Routes public.ottoq_cil_tick''s policy adoption through public.ottoq_policy_set instead of a '
 'raw INSERT, so the catalog governs the one agent in the engine that changes a dial on its own '
 'judgement (G62). Records the setter''s verdict in the rationale and the event so a clamped '
 'adoption cannot record a value that is not in force. forces_recert=false, and provably so: '
 'ottoq_cil_tick has NO caller anywhere in public/ottoq/twin, no cron job invokes it, and it has '
 'never executed -- 0 rows with updated_by=''cil'', 0 rows in ottoq_cil_adoptions, 0 '
 'ottoq.cil_decision events, all asserted in P2 and re-asserted unchanged in A4. No certified run '
 'can have observed it. Does NOT wire the loop to anything: switching on an agent that '
 'autonomously adopts policy onto a live depot is the owner''s decision.',
 now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;
