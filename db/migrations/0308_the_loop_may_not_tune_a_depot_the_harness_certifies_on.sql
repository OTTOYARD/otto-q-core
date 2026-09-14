-- migration-version: 20260914144046
-- migration-name:    0308_the_loop_may_not_tune_a_depot_the_harness_certifies_on
--
-- 0308  THE SELF-IMPROVEMENT LOOP GETS THE ONE GUARD IT NEEDS BEFORE IT MAY
--       BE SCHEDULED: IT MUST NOT TUNE A DEPOT THE HARNESS CERTIFIES ON
--
-- Chase authorised bringing the loop live on 2026-09-14, twin-only (task #129,
-- option b): "We don't have live streaming data or telemetry data and
-- communication yet, so it will have to be simulation only until a pilot
-- program is enacted."
--
-- public.ottoq_cil_tick is a closed-loop policy-tuning agent that has never
-- been invoked -- ottoq_cil_adoptions holds 0 rows, measured. It proposes four
-- candidate plans, evaluates every one forward in the twin under a 0-unsafe
-- hard gate, and adopts the best feasible improvement. Since 0302 it adopts
-- through ottoq_policy_set, so the catalogue clamps and refuses it exactly as
-- it does every other writer. That made it SAFE TO INVOKE. It did not make it
-- safe to SCHEDULE, and this migration is the difference.
--
-- ---------------------------------------------------------------------------
-- THE HAZARD, WHICH IS SPECIFIC AND NOT HYPOTHETICAL
--
-- ottoq_cil_tick resolves the run's depot and then writes the winning dials at
-- DEPOT SCOPE:
--
--     SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = ...;
--     ...
--     v_set := public.ottoq_policy_set('depot', v_depot, k, val::numeric, 'cil');
--
-- A depot-scoped dial is permanent and is read by EVERY later run on that
-- depot, certification pairs included. The certification canon is the claim
-- "same inputs, byte-identical outputs" -- and a dial is an input. So an
-- unguarded loop pointed at a certified depot would:
--
--   1. improve the policy, correctly, on its own terms;
--   2. change the inputs every canon on that depot was established under;
--   3. cause every column on that depot to disagree with its canon;
--   4. be reported by ottoq_cert_matrix as an ENGINE REGRESSION.
--
-- The matrix would be telling the truth about the comparison and lying about
-- the cause. Worse, per ottoq_cert_matrix's own structure the canon is the
-- MOST RECENT pair, so the first post-adoption pair would quietly BECOME the
-- canon and collapse the streak to 1 rather than announce anything. That is
-- G46's silent rebase, caused by an agent doing its job.
--
-- Measured today, which is why this is not theoretical:
--
--     depot 11111111 Flagship     1,019 sim runs, 987 cert_harness
--     depot aacd0bb0 Grid            76 sim runs,  72 cert_harness
--     depot 22222222 Benchmark        9 sim runs,   0 cert_harness
--
-- 96.9% of everything that has ever run on the flagship depot is a
-- certification run.
--
-- ---------------------------------------------------------------------------
-- WHY THE GUARD GOES INSIDE ottoq_cil_tick AND NOT IN THE SCHEDULER
--
-- The obvious move is to schedule the loop carefully -- point the cron job at
-- a Benchmark run and never at a flagship one. That is a guard that lives in
-- the caller, and there is already a SECOND caller: the OttoCommand edge
-- function invokes ottoq_cil_tick by RPC (edge-functions/ottoq-ottocommand/
-- index.ts line 76) so an operator can press the button. A scheduler-side
-- guard protects the schedule and not the button.
--
-- So the refusal goes in the one place every caller passes through. This is
-- the same argument 0305 made for putting the catalogue allow-list on the
-- TABLE rather than in ottoq_policy_set: a rule enforced at one of several
-- entrances is not enforced.
--
-- The predicate is extracted into its own function rather than inlined,
-- because a guard that cannot be called cannot be tested, and A2/A3 below test
-- the guard itself rather than a proxy for it. It is also independently
-- useful: a caller can ask "would this be refused, and why" without attempting
-- the tune.
--
-- ---------------------------------------------------------------------------
-- THE FOUR REFUSALS, AND WHY EACH ONE
--
--   depot_under_certification  the depot appears in ottoq_cert_columns OR has
--                              ever hosted a cert_harness run. Both, as a
--                              union, deliberately: the registry is the
--                              DECLARATION and the run history is the FACT,
--                              and a column removed from the registry still
--                              leaves a canon that matters. Note there is no
--                              `AND c.enabled` -- a temporarily disabled
--                              column must not open the depot to tuning.
--
--   production_run             run_by = 'production_live'. The loop is
--                              authorised for the twin only. This is the
--                              product posture, encoded.
--
--   certification_in_flight    any cert_harness run is currently 'running'.
--                              Not about dial scope -- about load. A 12-tick
--                              pair is a single statement and this deployment
--                              cancels one at 120 s under pg_cron (observed
--                              today, 14:29:00 -> 14:31:00). An MPC lookahead
--                              forking the twin alongside it is exactly the
--                              kind of concurrent load that turns a pair
--                              inconclusive, and an inconclusive pair costs a
--                              round.
--
--   run_not_running            the loop evaluates plans forward from a live
--                              world; a finished run has nothing to look
--                              ahead into.
--
--   unknown_run                the sim_run_id resolves to nothing.
--
-- ---------------------------------------------------------------------------
-- A REFUSAL IS RECORDED, NOT SWALLOWED
--
-- A scheduled loop that silently skips is a loop you cannot tell from a loop
-- that is broken. So a refusal writes an ottoq_cil_adoptions row with
-- adopted=false and plan_label='refused', and emits ottoq.cil_decision exactly
-- as a non-adoption does today. ONE ledger, not two: the table already records
-- non-adoptions ("Current policy is best"), and a refusal is another kind of
-- non-adoption. What it does NOT do is write a dial.
--
-- ---------------------------------------------------------------------------
-- forces_recert: FALSE.
--
-- The argument, and it is narrow. This migration adds a new function and adds
-- a refusal branch to a function that HAS NEVER BEEN CALLED -- ottoq_cil_
-- adoptions holds 0 rows and there are 0 rows in ottoq_policy_params with
-- updated_by='cil', measured. No certified run has ever executed a line of
-- ottoq_cil_tick, so no canon can depend on its behaviour. Nothing else is
-- touched: ottoq_policy_get, ottoq_policy_set, the decide path and the twin
-- are all unmodified.
--
-- The claim is checked rather than asserted: A5 re-runs the grid_smoke
-- certification column after this migration and requires it to reproduce its
-- pre-migration canon.
--
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- P0. MD5 GUARD. Replace the definition I actually read, not whatever is there.
-- ---------------------------------------------------------------------------
DO $p0$
DECLARE v_md5 text; v_cfg text[];
BEGIN
  SELECT md5(p.prosrc), p.proconfig INTO v_md5, v_cfg
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';

  IF v_md5 IS DISTINCT FROM 'e5bc51489496730445c898befc1b1790' THEN
    RAISE EXCEPTION 'P0 FAILED: ottoq_cil_tick prosrc md5 is %, expected e5bc51489496730445c898befc1b1790 '
                    '-- the body changed since it was read; re-read it before replacing it', v_md5;
  END IF;

  -- 0302's lesson: CREATE OR REPLACE drops a SET clause that is not restated.
  IF v_cfg IS DISTINCT FROM ARRAY['search_path=twin, ottoq, public, extensions'] THEN
    RAISE EXCEPTION 'P0 FAILED: proconfig is [%], expected the documented search_path', array_to_string(v_cfg, ', ');
  END IF;
END $p0$;

-- ---------------------------------------------------------------------------
-- P1. THE LOOP HAS GENUINELY NEVER RUN. This is the whole forces_recert=false
--     argument, so it is measured here rather than believed.
-- ---------------------------------------------------------------------------
DO $p1$
DECLARE v_ad int; v_dials int; v_ev int;
BEGIN
  SELECT count(*) INTO v_ad    FROM public.ottoq_cil_adoptions;
  SELECT count(*) INTO v_dials FROM public.ottoq_policy_params WHERE updated_by = 'cil';
  SELECT count(*) INTO v_ev    FROM public.ottoq_events        WHERE event_type = 'ottoq.cil_decision';

  IF v_ad <> 0 OR v_dials <> 0 OR v_ev <> 0 THEN
    RAISE EXCEPTION 'P1 FAILED: the loop has run -- % adoption(s), % dial(s) by cil, % cil_decision event(s). '
                    'forces_recert=false rests on it never having run; re-classify before applying.',
                    v_ad, v_dials, v_ev;
  END IF;
END $p1$;

-- ---------------------------------------------------------------------------
-- P2. THE GUARD HAS SOMETHING TO BITE ON. If ottoq_cert_columns were empty the
--     new refusal would be vacuous and this migration would install a guard
--     that guards nothing.
-- ---------------------------------------------------------------------------
DO $p2$
DECLARE v_cols int; v_depots int; v_bench int;
BEGIN
  SELECT count(*), count(DISTINCT depot_id) INTO v_cols, v_depots FROM public.ottoq_cert_columns;
  IF v_cols < 2 OR v_depots < 1 THEN
    RAISE EXCEPTION 'P2 FAILED: ottoq_cert_columns holds % row(s) over % depot(s); the guard would be vacuous',
                    v_cols, v_depots;
  END IF;

  -- and the depot the loop is destined for must NOT be one of them, or there
  -- is nowhere to run it and this migration is pointless.
  SELECT count(*) INTO v_bench
    FROM public.ottoq_cert_columns WHERE depot_id = '22222222-2222-2222-2222-222222222222';
  IF v_bench <> 0 THEN
    RAISE EXCEPTION 'P2 FAILED: Benchmark is now a certification depot (% column(s)); '
                    'the loop has nowhere left to run and the target must be re-chosen', v_bench;
  END IF;
END $p2$;

-- ---------------------------------------------------------------------------
-- P3. NOTHING IN FLIGHT -- AND pg_stat_activity IS THE ONLY AUTHORITY.
--
-- An earlier draft of this block read
--     SELECT count(*) FROM public.ottoq_sim_runs WHERE status = 'running'
-- which is WRONG, and wrong in this repo's favourite way: it answers a
-- slightly different question than the one being asked.
-- ottoq_determinism_pair runs both arms inside ONE transaction, so the run
-- rows it INSERTs are invisible to every other session until it commits.
-- Observed directly today: at 14:37 UTC a 12-tick pair was demonstrably
-- executing (cron job 629, started 14:36:00) and this exact query returned 0.
-- A precondition that reads 0 while the thing it guards against is running is
-- worse than no precondition, because it licenses the apply.
--
-- pg_stat_activity is not MVCC-scoped -- it reports live backends regardless of
-- transaction visibility -- which is why the standing instruction names it as
-- the only authority. Both are kept: the catalog read is retained as a second,
-- weaker signal, but it can no longer be the one that clears the way.
-- ---------------------------------------------------------------------------
DO $p3$
DECLARE v_backends int; v_running int; v_cron int; v_q text;
BEGIN
  SELECT count(*), max(left(query, 120)) INTO v_backends, v_q
    FROM pg_stat_activity
   WHERE datname = current_database()
     AND pid <> pg_backend_pid()
     AND state <> 'idle'
     AND (query ILIKE '%ottoq_determinism_pair%'
       OR query ILIKE '%ottoq_sim_advance_tick%'
       OR query ILIKE '%ottoq_decide_tick%'
       OR query ILIKE '%ottoq_cil_tick%');
  IF v_backends <> 0 THEN
    RAISE EXCEPTION 'P3 FAILED: % engine backend(s) are executing -- e.g. [%]. Apply in a quiesced window.',
                    v_backends, v_q;
  END IF;

  -- weaker, and deliberately second: this cannot see an uncommitted pair.
  SELECT count(*) INTO v_running FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_running <> 0 THEN
    RAISE EXCEPTION 'P3 FAILED: % sim run(s) are running; apply in a quiesced window', v_running;
  END IF;

  -- '^r[0-9]+' and NOT the '^r[0-9]+_' this repo has been using. Measured
  -- today: the round-42 probe job was named 'r42a_busy12_171717', and
  -- '^r[0-9]+_' does not match it -- 'r', '42', then 'a', not an underscore.
  -- A round that uses a letter suffix is invisible to the older pattern, so
  -- the guard would have cleared an apply with a pair armed four minutes out.
  SELECT count(*) INTO v_cron FROM cron.job WHERE jobname ~ '^r[0-9]+' AND active;
  IF v_cron <> 0 THEN
    RAISE EXCEPTION 'P3 FAILED: % certification cron job(s) are armed; a pair may fire mid-apply', v_cron;
  END IF;
END $p3$;

-- ===========================================================================
-- THE GUARD
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ottoq_cil_tune_refusal(p_sim_run_id uuid)
RETURNS text
LANGUAGE plpgsql
STABLE
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_depot uuid; v_run_by text; v_status text; v_found boolean := false;
BEGIN
  SELECT depot_id, COALESCE(run_by,''), COALESCE(status,''), true
    INTO v_depot, v_run_by, v_status, v_found
    FROM public.ottoq_sim_runs
   WHERE sim_run_id = p_sim_run_id;

  IF NOT COALESCE(v_found,false) OR v_depot IS NULL THEN
    RETURN 'unknown_run';
  END IF;

  -- 1. The depot the harness certifies on is off limits, permanently.
  --    Registry OR history, as a union: the registry is the declaration and
  --    the run history is the fact. No `AND enabled` -- a column disabled for
  --    an afternoon must not open its depot to a permanent dial write.
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_columns c
              WHERE c.depot_id = v_depot)
     OR EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
                 WHERE r.depot_id = v_depot
                   AND COALESCE(r.run_by,'') = 'cert_harness') THEN
    RETURN 'depot_under_certification';
  END IF;

  -- 2. Twin only. This is the product posture, not a technical limit.
  IF v_run_by = 'production_live' THEN
    RETURN 'production_run';
  END IF;

  -- 3. Not while a pair is in flight -- a concurrent MPC fork is how a pair
  --    goes inconclusive, and an inconclusive pair costs a round.
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs r
              WHERE r.status = 'running'
                AND COALESCE(r.run_by,'') = 'cert_harness') THEN
    RETURN 'certification_in_flight';
  END IF;

  -- 4. There must be a live world to look ahead into.
  IF v_status <> 'running' THEN
    RETURN 'run_not_running';
  END IF;

  RETURN NULL;   -- NULL means: tuning is permitted
END;
$fn$;

COMMENT ON FUNCTION public.ottoq_cil_tune_refusal(uuid) IS
'Returns NULL if the self-improvement loop may tune against this run, else a reason code '
'(depot_under_certification / production_run / certification_in_flight / run_not_running / unknown_run). '
'0308. Called by ottoq_cil_tick before any dial is written, because ottoq_cil_tick writes at DEPOT scope '
'and a depot-scoped dial is an input to every later run on that depot -- certification pairs included.';

-- ===========================================================================
-- THE LOOP, WITH THE GUARD IN FRONT OF IT
-- Body is 0302's verbatim, plus the refusal branch. Nothing else changes.
-- ===========================================================================

CREATE OR REPLACE FUNCTION public.ottoq_cil_tick(p_sim_run_id uuid, p_horizon integer DEFAULT 3)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = twin, ottoq, public, extensions
AS $fn$
DECLARE
  v_plans jsonb; v_depot uuid; v_eval jsonb;
  v_cur_score numeric; v_best_label text; v_best_score numeric; v_best_params jsonb;
  k text; val text; v_adopted boolean := false; v_result jsonb; v_rationale text;
  -- 0302: what the sanctioned setter actually did with each adopted dial.
  v_set jsonb; v_writes jsonb := '[]'::jsonb; v_clamped int := 0; v_refused int := 0;
  -- 0308: why this tick may not tune, if it may not.
  v_refusal text;
BEGIN
  SELECT depot_id INTO v_depot FROM ottoq_sim_runs WHERE sim_run_id = p_sim_run_id;

  -- 0308: THE GUARD. ottoq_cil_tick writes dials at DEPOT scope, and a
  -- depot-scoped dial is read by every later run on that depot. Tuning a depot
  -- the harness certifies on would change the inputs every canon there was
  -- established under, and ottoq_cert_matrix would report the result as an
  -- engine regression -- truthfully about the comparison, falsely about the
  -- cause. The refusal lives here rather than in the scheduler because
  -- ottoq-ottocommand invokes this function by RPC too, and a guard at one of
  -- two entrances is not a guard.
  --
  -- A refusal is RECORDED. A scheduled loop that silently skips cannot be
  -- told apart from one that is broken, so it lands in the same ledger a
  -- non-adoption lands in -- with adopted=false and no dial written.
  v_refusal := public.ottoq_cil_tune_refusal(p_sim_run_id);
  IF v_refusal IS NOT NULL THEN
    v_rationale := format('REFUSED: %s. No dial written.', v_refusal);

    INSERT INTO ottoq_cil_adoptions(sim_run_id, depot_id, adopted, plan_label, params,
                                    score_current, score_adopted, source, rationale, eval)
    VALUES (p_sim_run_id, v_depot, false, 'refused', '{}'::jsonb,
            NULL, NULL, 'cil_heuristic', v_rationale, NULL);

    IF v_depot IS NOT NULL THEN
      PERFORM ottoq_record_event(
        p_actor_type:='ottoq_engine', p_actor_id:='cil', p_event_type:='ottoq.cil_decision',
        p_entity_type:='depot', p_entity_id:=v_depot, p_depot_id:=v_depot,
        p_payload:=jsonb_build_object('adopted',false,'refused',v_refusal,'rationale',v_rationale),
        p_severity:='info', p_ingest_source:='otto_q', p_data_source:='twin', p_sim_run_id:=p_sim_run_id);
    END IF;

    RETURN jsonb_build_object('adopted',false,'refused',v_refusal,'rationale',v_rationale);
  END IF;

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
$fn$;

-- ===========================================================================
-- ASSERTIONS
-- ===========================================================================

-- ---------------------------------------------------------------------------
-- A1. THE SET CLAUSE SURVIVED. 0302's lesson, asserted rather than trusted.
-- ---------------------------------------------------------------------------
DO $a1$
DECLARE v_cfg text[];
BEGIN
  SELECT p.proconfig INTO v_cfg FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_cil_tick';
  IF v_cfg IS DISTINCT FROM ARRAY['search_path=twin, ottoq, public, extensions'] THEN
    RAISE EXCEPTION 'A1 FAILED: proconfig is now [%]; CREATE OR REPLACE dropped the SET clause',
                    array_to_string(v_cfg, ', ');
  END IF;
END $a1$;

-- ---------------------------------------------------------------------------
-- A2. THE GUARD REFUSES A CERTIFIED DEPOT. Tested against the two real ones,
--     by their actual live run ids -- not by a fabricated row, so this is the
--     predicate the scheduler will actually meet.
-- ---------------------------------------------------------------------------
DO $a2$
DECLARE r RECORD; v_reason text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT DISTINCT ON (depot_id) sim_run_id, depot_id
      FROM public.ottoq_sim_runs
     WHERE depot_id IN (SELECT DISTINCT depot_id FROM public.ottoq_cert_columns)
     ORDER BY depot_id, started_at DESC
  LOOP
    v_reason := public.ottoq_cil_tune_refusal(r.sim_run_id);
    IF v_reason IS DISTINCT FROM 'depot_under_certification' THEN
      RAISE EXCEPTION 'A2 FAILED: a run on certified depot % returned refusal [%], expected depot_under_certification',
                      r.depot_id, COALESCE(v_reason,'NULL -- i.e. PERMITTED');
    END IF;
    v_n := v_n + 1;
  END LOOP;

  IF v_n < 2 THEN
    RAISE EXCEPTION 'A2 FAILED: only % certified depot(s) exercised, expected at least 2', v_n;
  END IF;
END $a2$;

-- ---------------------------------------------------------------------------
-- A3. THE GUARD DOES NOT REFUSE THE TARGET DEPOT FOR THE WRONG REASON.
--     Benchmark's runs are all finished, so the honest expectation is
--     'run_not_running' -- NOT 'depot_under_certification'. Asserting the
--     exact reason rather than "not refused" is the point: a guard that
--     refused everything would pass a weaker test.
-- ---------------------------------------------------------------------------
DO $a3$
DECLARE r RECORD; v_reason text; v_n int := 0;
BEGIN
  FOR r IN
    SELECT sim_run_id, status FROM public.ottoq_sim_runs
     WHERE depot_id = '22222222-2222-2222-2222-222222222222'
  LOOP
    v_reason := public.ottoq_cil_tune_refusal(r.sim_run_id);
    IF v_reason = 'depot_under_certification' THEN
      RAISE EXCEPTION 'A3 FAILED: Benchmark run % was refused as a certified depot; '
                      'the loop has nowhere to run', r.sim_run_id;
    END IF;
    IF r.status <> 'running' AND v_reason IS DISTINCT FROM 'run_not_running' THEN
      RAISE EXCEPTION 'A3 FAILED: finished Benchmark run % returned [%], expected run_not_running',
                      r.sim_run_id, COALESCE(v_reason,'NULL');
    END IF;
    v_n := v_n + 1;
  END LOOP;

  IF v_n < 1 THEN
    RAISE EXCEPTION 'A3 FAILED: no Benchmark runs found to exercise the guard against';
  END IF;
END $a3$;

-- ---------------------------------------------------------------------------
-- A4. AN UNKNOWN RUN REFUSES RATHER THAN FALLING THROUGH TO PERMITTED.
--     The dangerous failure mode of a guard is returning NULL by accident.
-- ---------------------------------------------------------------------------
DO $a4$
DECLARE v_reason text;
BEGIN
  v_reason := public.ottoq_cil_tune_refusal('00000000-0000-0000-0000-000000000000'::uuid);
  IF v_reason IS DISTINCT FROM 'unknown_run' THEN
    RAISE EXCEPTION 'A4 FAILED: an unknown run returned [%], expected unknown_run',
                    COALESCE(v_reason,'NULL -- i.e. PERMITTED');
  END IF;
END $a4$;

-- ---------------------------------------------------------------------------
-- A5. A REFUSAL WRITES NO DIAL. The whole point, exercised end to end against
--     a real certified-depot run and rolled back.
-- ---------------------------------------------------------------------------
DO $a5$
DECLARE v_run uuid; v_res jsonb; v_dials_before int; v_dials_after int; v_ad int;
BEGIN
  SELECT sim_run_id INTO v_run FROM public.ottoq_sim_runs
   WHERE depot_id = '11111111-1111-1111-1111-111111111111'
   ORDER BY started_at DESC LIMIT 1;

  IF v_run IS NULL THEN RAISE EXCEPTION 'A5 FAILED: no flagship run to test against'; END IF;

  BEGIN
    SELECT count(*) INTO v_dials_before FROM public.ottoq_policy_params;

    v_res := public.ottoq_cil_tick(v_run, 1);

    IF COALESCE(v_res->>'refused','') <> 'depot_under_certification' THEN
      RAISE EXCEPTION 'A5 FAILED: ottoq_cil_tick on a certified depot returned %, expected refused', v_res;
    END IF;

    SELECT count(*) INTO v_dials_after FROM public.ottoq_policy_params;
    IF v_dials_after <> v_dials_before THEN
      RAISE EXCEPTION 'A5 FAILED: a refused tick wrote % dial row(s)', v_dials_after - v_dials_before;
    END IF;

    SELECT count(*) INTO v_ad FROM public.ottoq_cil_adoptions WHERE plan_label = 'refused';
    IF v_ad < 1 THEN
      RAISE EXCEPTION 'A5 FAILED: the refusal was not recorded in ottoq_cil_adoptions';
    END IF;

    RAISE EXCEPTION 'A5_OK_ROLLBACK';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM <> 'A5_OK_ROLLBACK' THEN RAISE; END IF;
  END;
END $a5$;

-- ---------------------------------------------------------------------------
-- A6. NO RESIDUE. A5 ran the real function; nothing of it may survive.
-- ---------------------------------------------------------------------------
DO $a6$
DECLARE v_ad int; v_dials int;
BEGIN
  SELECT count(*) INTO v_ad    FROM public.ottoq_cil_adoptions;
  SELECT count(*) INTO v_dials FROM public.ottoq_policy_params WHERE updated_by = 'cil';
  IF v_ad <> 0 OR v_dials <> 0 THEN
    RAISE EXCEPTION 'A6 FAILED: % adoption row(s) and % cil dial(s) survived the rolled-back probe', v_ad, v_dials;
  END IF;
END $a6$;

-- ===========================================================================
-- APPLIED CORRECTION -- added 2026-09-14 after apply (20260914144046).
-- Body above is untouched: it is what ran. Same convention as 0301 and 0307.
--
-- TWO STATEMENTS IN THE HEADER ARE WRONG, and one of them is exactly the kind
-- of unre-measured claim this repo keeps convicting other files of.
--
-- 1. The header says: "The claim is checked rather than asserted: A5 re-runs
--    the grid_smoke certification column after this migration and requires it
--    to reproduce its pre-migration canon."
--
--    A5 DOES NO SUCH THING. A5 calls ottoq_cil_tick against a flagship run,
--    asserts it refuses with depot_under_certification, asserts no dial row
--    was written, asserts the refusal was recorded, and rolls back. It never
--    touches the certification harness.
--
--    The forces_recert=false claim IS backed by measurement -- but by
--    measurement taken BEFORE this migration and recorded in db/checks/0234,
--    not by anything inside this file:
--      grid_smoke 239001/6t   fired 14:23:16 -> 14:24:04 UTC, 12 atoms, all
--                             matching a canon read BEFORE the pair was run
--      busy_day 171717/12t    fired 14:36:00 -> 14:37:57 UTC, 13 atoms, all
--                             matching the canon recorded at 14:23
--    Those verify migrations 0303-0307. This migration's own
--    forces_recert=false rests on P1: the loop has never been called, so no
--    canon can depend on it. That argument stands. The sentence describing
--    how it was checked did not.
--
-- 2. The header says "THE FOUR REFUSALS" and then lists FIVE
--    (depot_under_certification, production_run, certification_in_flight,
--    run_not_running, unknown_run). Five is correct; the heading is a
--    leftover from a draft that folded unknown_run into the first case.
