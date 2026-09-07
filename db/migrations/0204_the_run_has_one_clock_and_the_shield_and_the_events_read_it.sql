-- =====================================================================
-- 0204  The run has one clock, and the shield and the events read it
-- =====================================================================
-- forces_recert = TRUE. Six bodies change (ottoq_sim_advance_tick_world,
-- ottoq_record_event, ottoq_depot_local_time, two rule evaluators, the
-- pair), one is new (ottoq.ottoq_run_now). A0 pins every body; A1 proves
-- each rewrite differs from its pin in exactly the named fragments.
-- h_evt's canon moves on every column BY DESIGN (sim time enters the
-- hash); h_cmd, h_dec, h_bkg, h_nrg, h_prop, h_defr and h_cal must not.
-- Requires 0202 and 0203.
--
-- TWO FINDINGS, ONE CAUSE
-- ---------------------------------------------------------------------
-- G11 (known since the harness work). ottoq_events.occurred_at and
-- recorded_at are NOW(): transaction time. A certification pair runs both
-- arms in one transaction, so every event of both arms carries one
-- instant, h_evt can hash only event_type|entity_id, and no latency-shaped
-- KPI (p95_time_to_service, recall-to-first-op) can be computed for a
-- certified run. The twin has a clock -- ottoq_sim_runs.sim_clock_current,
-- advanced per tick -- and the events never heard it.
--
-- G15 (found 2026-09-06 while building 0202). A prosrc scan of the 29
-- active rule evaluators: eight call NOW(), four call
-- ottoq_depot_local_time, which is NOW() AT TIME ZONE
-- depot.operating_timezone. Six of the eight are sim-aware with a
-- wall-clock fallback (WIRE-3: COALESCE(context now_ts, NOW()); the tick
-- passes now_ts). SIX are not: SLA.003 (NOW() - arrival), SLA.006 (NOW()
-- AT TIME ZONE 'UTC'), and TW.001/003/004/005 through
-- ottoq_depot_local_time. Evidence: round 19's last pair (05:11:00 UTC)
-- wrote TW.001 result_payload local_time = 00:11:00.094288 -- Nashville
-- wall clock, midnight -- while simulating 2026-09-01 daytime. None of
-- the six is enforcement 'block', so decisions have not moved; the
-- ledger's answers and the rule.evaluated_fail events have. The pair
-- cannot see it because both arms share one NOW(); across rounds at
-- different hours the shield answers differently for the same simulated
-- day.
--
-- Both are the same absence: nothing in the engine answers "what time is
-- it in this run" from one place. The tick computes v_new_sim_clock and
-- hands it explicitly to the phases that take a clock argument; anything
-- that does not take one reaches for NOW().
--
-- WHAT CHANGES
-- ---------------------------------------------------------------------
--   1. ottoq.ottoq_run_now() -- the run's clock. Under no active run:
--      NOW(). Under a run: the GUC ottoq.sim_clock when it is tagged with
--      THIS run's id ('<run>|<clock>'), else the run row's
--      sim_clock_current, else NOW(). The tag is what makes a stale GUC
--      harmless: arm B of a pair ignores arm A's last tick, and boot-time
--      events (before the first tick) read sim_clock_start from the row.
--   2. ottoq_sim_advance_tick_world sets that GUC right after it fixes
--      v_new_sim_clock, before any phase runs. Without this the phases
--      that run ahead of the run-row UPDATE (visit atoms, energy
--      orchestration, arm cycles) would read the previous tick's clock.
--   3. ottoq_events.sim_clock_at timestamptz, NULL in production;
--      ottoq_record_event fills it with ottoq_run_now() when the caller
--      names a run. Metadata-only on 2.49M rows; no backfill (the rows
--      that exist have no sim time to recover). Not a run-id column, so
--      the run-scope registry has nothing to register; it follows
--      sim_run_id, which is registered.
--   4. h_evt = md5 over event_type|entity|sim_clock_at. The canon moves
--      once, everywhere, for this stated reason, and then holds.
--   5. ottoq_depot_local_time reads ottoq_run_now() -- four evaluators
--      fixed through one body. SLA.003 and SLA.006 read it directly.
--      Production behaviour is unchanged: no run, NOW().
--
-- NOT CHANGED, and why
-- ---------------------------------------------------------------------
--   - occurred_at/recorded_at stay wall clock: they are when the row was
--     written, which is true and useful; sim_clock_at is when it happened
--     in the run. Two facts, two columns.
--   - The six WIRE-3 evaluators keep COALESCE(now_ts, NOW()): they are
--     already sim-aware where the tick passes now_ts.
--   - h_rule stays measured (0203); the promotion is 0205, after round 21.
-- =====================================================================

BEGIN;

CREATE TEMP TABLE pin_0204 ON COMMIT DROP AS
SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
       md5(pg_get_functiondef(p.oid)) AS h,
       p.prosecdef
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p');

CREATE TEMP TABLE pre_0204 ON COMMIT DROP AS
SELECT has_function_privilege('anon',         'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)', 'EXECUTE') AS p_anon,
       has_function_privilege('anon',         'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,int,text,text,text,uuid)', 'EXECUTE') AS e_anon,
       has_function_privilege('service_role', 'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,int,text,text,text,uuid)', 'EXECUTE') AS e_svc,
       has_function_privilege('anon',         'public.ottoq_depot_local_time(uuid)', 'EXECUTE') AS l_anon;

-- ---------------------------------------------------------------------
-- 0. Preconditions.
-- ---------------------------------------------------------------------
DO $pre$
DECLARE v_h text; r record;
BEGIN
  IF EXISTS (SELECT 1 FROM cron.job j WHERE j.jobname ~ '^r[0-9]+_')
     OR EXISTS (SELECT 1 FROM pg_stat_activity a
                 WHERE a.query ILIKE '%ottoq_determinism_pair%' AND a.pid <> pg_backend_pid() AND a.state <> 'idle') THEN
    RAISE EXCEPTION '0204 refused: a certification round is scheduled or in flight';
  END IF;
  IF EXISTS (SELECT 1 FROM public.ottoq_sim_runs WHERE status = 'running') THEN
    RAISE EXCEPTION '0204 refused: a sim run is running';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.ottoq_cert_lineage WHERE name ~ '^0203_') THEN
    RAISE EXCEPTION '0204 refused: 0203 is not applied';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_attribute WHERE attrelid = 'public.ottoq_events'::regclass AND attname = 'sim_clock_at' AND NOT attisdropped) THEN
    RAISE EXCEPTION '0204 refused: ottoq_events.sim_clock_at already exists';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_run_now') THEN
    RAISE EXCEPTION '0204 refused: ottoq_run_now already exists';
  END IF;
  FOR r IN SELECT * FROM (VALUES
      ('public.ottoq_sim_advance_tick_world(p_sim_run_id uuid)',                                          '9b49f2e4f8410ac553d31720eb266a00'),
      ('public.ottoq_depot_local_time(p_depot_id uuid)',                                                  'e0ac3c32f8c2d12ab32f13b7aa3ce759'),
      ('public.ottoq_eval_sla_003_max_visit_duration(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)', '3dba830a98f743a833157d9e5318773d'),
      ('public.ottoq_eval_sla_006_maintenance_window(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)',  'da076efe7ea162b4d513ae8f0f1a0ecb'),
      ('public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid, p_payload jsonb, p_actor_id text, p_actor_metadata jsonb, p_fleet_operator_id uuid, p_depot_id uuid, p_previous_state jsonb, p_new_state jsonb, p_severity text, p_correlation_id uuid, p_parent_event_id uuid, p_related_task_id uuid, p_related_schedule_id uuid, p_related_decision_id uuid, p_outcome text, p_latency_ms integer, p_ingest_source text, p_signing_key_id text, p_data_source text, p_sim_run_id uuid)', 'f1d96f941e1cecbdd9102ebafd2a53c7')
    ) AS t(sig, h)
  LOOP
    SELECT h INTO v_h FROM pin_0204 WHERE sig = r.sig;
    IF v_h IS DISTINCT FROM r.h THEN
      RAISE EXCEPTION '0204 refused: % is not the body this file was written against (md5 %, expected %)', r.sig, v_h, r.h;
    END IF;
  END LOOP;
  -- the pair: pinned as 0203 left it (A1 there proved the shape); its md5 is read live below
  IF NOT EXISTS (SELECT 1 FROM pin_0204 WHERE sig LIKE 'public.ottoq_determinism_pair(%') THEN
    RAISE EXCEPTION '0204 refused: no pair function';
  END IF;
  RAISE NOTICE '0204 pre: bodies pinned, column absent, nothing in flight';
END $pre$;

-- ---------------------------------------------------------------------
-- 1. The clock.
-- ---------------------------------------------------------------------
CREATE FUNCTION ottoq.ottoq_run_now()
 RETURNS timestamp with time zone
 LANGUAGE plpgsql
 STABLE
 SET search_path TO 'ottoq', 'public', 'extensions'
AS $function$
DECLARE v_run uuid; v_txt text; v_clock timestamptz;
BEGIN
  -- 0204. "What time is it in this run." No run: the wall clock, so every
  -- production path is what it was. Under a run: the tick's clock when the
  -- tick has published it for THIS run (GUC ottoq.sim_clock = '<run>|<ts>';
  -- the tag makes another run's leftover harmless), else the run row's
  -- sim_clock_current (sim_clock_start before the first tick), else NOW().
  v_run := ottoq.ottoq_active_sim_run_id();
  IF v_run IS NULL THEN
    RETURN NOW();
  END IF;
  v_txt := NULLIF(current_setting('ottoq.sim_clock', true), '');
  IF v_txt IS NOT NULL AND split_part(v_txt, '|', 1) = v_run::text THEN
    RETURN split_part(v_txt, '|', 2)::timestamptz;
  END IF;
  SELECT r.sim_clock_current INTO v_clock FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
  RETURN COALESCE(v_clock, NOW());
END
$function$;
COMMENT ON FUNCTION ottoq.ottoq_run_now() IS
  '0204: the run''s clock. NOW() with no active run; under a run, the tick-published GUC ottoq.sim_clock when tagged with this run, else the run row''s sim_clock_current, else NOW(). The one place the shield and the event stream ask what time it is.';

-- ---------------------------------------------------------------------
-- 2. Six bodies from the catalog, one to three fragments each.
-- ---------------------------------------------------------------------
DO $rw$
DECLARE
  v_def text; v_n int; i int; k int;
  v_sig text[] := ARRAY[
    'public.ottoq_sim_advance_tick_world(uuid)',
    'public.ottoq_depot_local_time(uuid)',
    'public.ottoq_eval_sla_003_max_visit_duration(text,uuid,jsonb,jsonb)',
    'public.ottoq_eval_sla_006_maintenance_window(text,uuid,jsonb,jsonb)',
    'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,int,text,text,text,uuid)',
    'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'];
  -- fragments per body: old[k][i], new[k][i]; empty string = unused slot
  v_old text[][] := ARRAY[
    ARRAY[$f$IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;$f$, '', ''],
    ARRAY[$f$RETURN (NOW() AT TIME ZONE v_tz);$f$, '', ''],
    ARRAY[$f$EXTRACT(EPOCH FROM (NOW() - v_arrival_at))$f$, '', ''],
    ARRAY[$f$v_now_time := (NOW() AT TIME ZONE 'UTC')::TIME;$f$, '', ''],
    ARRAY[$f$data_source, sim_run_id$f$, $f$COALESCE(p_data_source, 'production'), p_sim_run_id$f$, ''],
    ARRAY[$f$ELSE COALESCE(entity_id::text,'-') END,
          E'\n' ORDER BY event_type,$f$,
          $f$END), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run)$f$, '']];
  v_new text[][] := ARRAY[
    ARRAY[$f$IF v_new_sim_clock >= v_run.sim_clock_end THEN v_new_sim_clock := v_run.sim_clock_end; v_completed := TRUE; END IF;
  PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|' || v_new_sim_clock::text, true);  /* 0204: publish the tick's clock for ottoq.ottoq_run_now() */$f$, '', ''],
    ARRAY[$f$RETURN (ottoq.ottoq_run_now() AT TIME ZONE v_tz);  /* 0204: the run's clock, NOW() outside a run */$f$, '', ''],
    ARRAY[$f$EXTRACT(EPOCH FROM (ottoq.ottoq_run_now() - v_arrival_at))$f$, '', ''],
    ARRAY[$f$v_now_time := (ottoq.ottoq_run_now() AT TIME ZONE 'UTC')::TIME;  /* 0204 */$f$, '', ''],
    ARRAY[$f$data_source, sim_run_id, sim_clock_at$f$, $f$COALESCE(p_data_source, 'production'), p_sim_run_id, CASE WHEN p_sim_run_id IS NOT NULL THEN ottoq.ottoq_run_now() END$f$, ''],
    ARRAY[$f$ELSE COALESCE(entity_id::text,'-') END||'|'||COALESCE(e.sim_clock_at::text,'-'),
          E'\n' ORDER BY event_type,$f$,
          $f$END, e.sim_clock_at), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run)$f$, '']];
BEGIN
  FOR k IN 1..6 LOOP
    v_def := pg_get_functiondef(v_sig[k]::regprocedure);
    FOR i IN 1..3 LOOP
      CONTINUE WHEN v_old[k][i] = '';
      v_n := (length(v_def) - length(replace(v_def, v_old[k][i], ''))) / length(v_old[k][i]);
      IF v_n <> 1 THEN
        RAISE EXCEPTION '0204 step 2: body % fragment % occurs % times, expected exactly once', v_sig[k], i, v_n;
      END IF;
      v_def := replace(v_def, v_old[k][i], v_new[k][i]);
    END LOOP;
    EXECUTE v_def;
    RAISE NOTICE '0204 step 2: % rewritten from the catalog', v_sig[k];
  END LOOP;
END $rw$;

-- ---------------------------------------------------------------------
-- 3. The column.
-- ---------------------------------------------------------------------
ALTER TABLE public.ottoq_events ADD COLUMN sim_clock_at timestamp with time zone;
COMMENT ON COLUMN public.ottoq_events.sim_clock_at IS
  '0204: when this event happened in its run (ottoq.ottoq_run_now() at write time). NULL in production and for every row written before 0204. occurred_at stays the wall clock.';

-- ---------------------------------------------------------------------
-- ASSERTIONS
-- ---------------------------------------------------------------------
DO $assert$
DECLARE
  v_changed text[]; v_new text[]; v_def text; v_run uuid; v_tz text; v_got timestamptz; v_exp timestamptz;
BEGIN
  -- ── A0. THE PIN.
  SELECT array_agg(a.sig ORDER BY a.sig) INTO v_changed
    FROM pin_0204 a
    JOIN (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig,
                 md5(pg_get_functiondef(p.oid)) AS h, p.prosecdef
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b USING (sig)
   WHERE a.h <> b.h OR a.prosecdef <> b.prosecdef;
  IF v_changed IS DISTINCT FROM ARRAY[
       'public.ottoq_depot_local_time(p_depot_id uuid)',
       'public.ottoq_determinism_pair(p_seed bigint, p_ticks integer, p_scenario text, p_depot uuid, p_sim_start timestamp with time zone, p_arm_budget_s integer)',
       'public.ottoq_eval_sla_003_max_visit_duration(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)',
       'public.ottoq_eval_sla_006_maintenance_window(p_entity_type text, p_entity_id uuid, p_context jsonb, p_parameters jsonb)',
       'public.ottoq_record_event(p_actor_type text, p_event_type text, p_entity_type text, p_entity_id uuid, p_payload jsonb, p_actor_id text, p_actor_metadata jsonb, p_fleet_operator_id uuid, p_depot_id uuid, p_previous_state jsonb, p_new_state jsonb, p_severity text, p_correlation_id uuid, p_parent_event_id uuid, p_related_task_id uuid, p_related_schedule_id uuid, p_related_decision_id uuid, p_outcome text, p_latency_ms integer, p_ingest_source text, p_signing_key_id text, p_data_source text, p_sim_run_id uuid)',
       'public.ottoq_sim_advance_tick_world(p_sim_run_id uuid)'] THEN
    RAISE EXCEPTION '0204 A0 FAILED: function bodies changed = %', v_changed;
  END IF;
  SELECT array_agg(b.sig ORDER BY b.sig) INTO v_new
    FROM (SELECT n.nspname || '.' || p.proname || '(' || pg_get_function_identity_arguments(p.oid) || ')' AS sig
            FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
           WHERE n.nspname IN ('public','ottoq','twin') AND p.prokind IN ('f','p')) b
    LEFT JOIN pin_0204 a USING (sig)
   WHERE a.sig IS NULL;
  IF v_new IS DISTINCT FROM ARRAY['ottoq.ottoq_run_now()'] THEN
    RAISE EXCEPTION '0204 A0 FAILED: new functions = %', v_new;
  END IF;
  IF (SELECT prosecdef FROM pg_proc WHERE proname = 'ottoq_run_now') THEN
    RAISE EXCEPTION '0204 A0 FAILED: ottoq_run_now is SECURITY DEFINER';
  END IF;
  RAISE NOTICE '0204 A0: pin holds; six bodies changed, one new';

  -- ── A1. Every rewritten body reverts to its pin under the reverse replacements.
  v_def := pg_get_functiondef('public.ottoq_sim_advance_tick_world(uuid)'::regprocedure);
  v_def := replace(v_def, $f$
  PERFORM set_config('ottoq.sim_clock', p_sim_run_id::text || '|' || v_new_sim_clock::text, true);  /* 0204: publish the tick's clock for ottoq.ottoq_run_now() */$f$, '');
  IF md5(v_def) <> '9b49f2e4f8410ac553d31720eb266a00' THEN RAISE EXCEPTION '0204 A1 FAILED: advance_tick_world differs outside its fragment'; END IF;
  v_def := pg_get_functiondef('public.ottoq_depot_local_time(uuid)'::regprocedure);
  v_def := replace(v_def, $f$RETURN (ottoq.ottoq_run_now() AT TIME ZONE v_tz);  /* 0204: the run's clock, NOW() outside a run */$f$, $f$RETURN (NOW() AT TIME ZONE v_tz);$f$);
  IF md5(v_def) <> 'e0ac3c32f8c2d12ab32f13b7aa3ce759' THEN RAISE EXCEPTION '0204 A1 FAILED: depot_local_time differs outside its fragment'; END IF;
  v_def := pg_get_functiondef('public.ottoq_eval_sla_003_max_visit_duration(text,uuid,jsonb,jsonb)'::regprocedure);
  v_def := replace(v_def, $f$EXTRACT(EPOCH FROM (ottoq.ottoq_run_now() - v_arrival_at))$f$, $f$EXTRACT(EPOCH FROM (NOW() - v_arrival_at))$f$);
  IF md5(v_def) <> '3dba830a98f743a833157d9e5318773d' THEN RAISE EXCEPTION '0204 A1 FAILED: SLA.003 differs outside its fragment'; END IF;
  v_def := pg_get_functiondef('public.ottoq_eval_sla_006_maintenance_window(text,uuid,jsonb,jsonb)'::regprocedure);
  v_def := replace(v_def, $f$v_now_time := (ottoq.ottoq_run_now() AT TIME ZONE 'UTC')::TIME;  /* 0204 */$f$, $f$v_now_time := (NOW() AT TIME ZONE 'UTC')::TIME;$f$);
  IF md5(v_def) <> 'da076efe7ea162b4d513ae8f0f1a0ecb' THEN RAISE EXCEPTION '0204 A1 FAILED: SLA.006 differs outside its fragment'; END IF;
  v_def := pg_get_functiondef('public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,int,text,text,text,uuid)'::regprocedure);
  v_def := replace(v_def, $f$data_source, sim_run_id, sim_clock_at$f$, $f$data_source, sim_run_id$f$);
  v_def := replace(v_def, $f$COALESCE(p_data_source, 'production'), p_sim_run_id, CASE WHEN p_sim_run_id IS NOT NULL THEN ottoq.ottoq_run_now() END$f$, $f$COALESCE(p_data_source, 'production'), p_sim_run_id$f$);
  IF md5(v_def) <> 'f1d96f941e1cecbdd9102ebafd2a53c7' THEN RAISE EXCEPTION '0204 A1 FAILED: record_event differs outside its fragments'; END IF;
  v_def := pg_get_functiondef('public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)'::regprocedure);
  v_def := replace(v_def, $f$ELSE COALESCE(entity_id::text,'-') END||'|'||COALESCE(e.sim_clock_at::text,'-'),
          E'\n' ORDER BY event_type,$f$, $f$ELSE COALESCE(entity_id::text,'-') END,
          E'\n' ORDER BY event_type,$f$);
  v_def := replace(v_def, $f$END, e.sim_clock_at), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run)$f$, $f$END), ''))
        FROM ottoq_events e WHERE e.sim_run_id = v_run)$f$);
  IF md5(v_def) <> (SELECT h FROM pin_0204 WHERE sig LIKE 'public.ottoq_determinism_pair(%') THEN
    RAISE EXCEPTION '0204 A1 FAILED: the pair differs outside its two fragments';
  END IF;
  RAISE NOTICE '0204 A1: all six bodies revert to their pins';

  -- ── A2. The clock's contract, in a rolled-back scope.
  SELECT r.sim_run_id INTO v_run FROM public.ottoq_sim_runs r
   WHERE r.depot_id = '11111111-1111-1111-1111-111111111111' AND r.status = 'completed'
   ORDER BY r.started_at DESC, r.sim_run_id DESC LIMIT 1;
  SELECT r.sim_clock_current INTO v_exp FROM public.ottoq_sim_runs r WHERE r.sim_run_id = v_run;
  SELECT d.operating_timezone INTO v_tz FROM public.depots d WHERE d.id = '11111111-1111-1111-1111-111111111111';
  BEGIN
    PERFORM set_config('ottoq.sim_run_id', 'none', true);
    PERFORM set_config('ottoq.sim_clock', v_run::text || '|2030-01-01 00:00:00+00', true);
    IF ottoq.ottoq_run_now() <> NOW() THEN RAISE EXCEPTION '0204 A2 FAILED: no run, GUC set: expected NOW()'; END IF;
    IF public.ottoq_depot_local_time('11111111-1111-1111-1111-111111111111') <> (NOW() AT TIME ZONE COALESCE(v_tz,'UTC')) THEN
      RAISE EXCEPTION '0204 A2 FAILED: no run: depot_local_time is not the wall clock';
    END IF;
    PERFORM set_config('ottoq.sim_run_id', v_run::text, true);
    PERFORM set_config('ottoq.sim_clock', '', true);
    v_got := ottoq.ottoq_run_now();
    IF v_got IS DISTINCT FROM v_exp THEN RAISE EXCEPTION '0204 A2 FAILED: under run %, no GUC: got %, expected the row''s %', v_run, v_got, v_exp; END IF;
    IF public.ottoq_depot_local_time('11111111-1111-1111-1111-111111111111') <> (v_exp AT TIME ZONE COALESCE(v_tz,'UTC')) THEN
      RAISE EXCEPTION '0204 A2 FAILED: under a run, depot_local_time is not the run''s clock';
    END IF;
    PERFORM set_config('ottoq.sim_clock', v_run::text || '|2030-01-01 00:00:00+00', true);
    IF ottoq.ottoq_run_now() <> '2030-01-01 00:00:00+00'::timestamptz THEN RAISE EXCEPTION '0204 A2 FAILED: tagged GUC for this run not honoured'; END IF;
    PERFORM set_config('ottoq.sim_clock', '00000000-0000-4000-8000-000000000000|2030-01-01 00:00:00+00', true);
    IF ottoq.ottoq_run_now() IS DISTINCT FROM v_exp THEN RAISE EXCEPTION '0204 A2 FAILED: another run''s GUC was honoured'; END IF;
    RAISE EXCEPTION USING ERRCODE = 'P0204', MESSAGE = 'scope rollback';
  EXCEPTION WHEN SQLSTATE 'P0204' THEN NULL;
  END;
  PERFORM set_config('ottoq.sim_run_id', '', true);
  PERFORM set_config('ottoq.sim_clock', '', true);
  RAISE NOTICE '0204 A2: run_now: NOW() without a run; the row''s clock under a run; the tagged GUC only for its own run';

  -- ── A3 IS NOT RUN INSIDE THIS TRANSACTION. See the APPLIED footer.
  --    The live grid pair takes longer than the client's statement budget, and
  --    its TW.001 clause was VACUOUS: the grid fixture never evaluates
  --    TW.001.operational_hours, so `v_lt = 0` and the assertion would have
  --    aborted the apply for the wrong reason. The probe now runs immediately
  --    after COMMIT, against the fixture that actually exercises each half:
  --    the grid pair for the event stream (G11) and the flagship census for
  --    the shield (G15). Both results are recorded in the footer and in
  --    db/checks/0118. A rerun of this file should do the same.

  -- ── A4. Privileges unchanged.
  IF (SELECT p_anon FROM pre_0204) IS DISTINCT FROM has_function_privilege('anon', 'public.ottoq_determinism_pair(bigint,int,text,uuid,timestamptz,int)', 'EXECUTE')
     OR (SELECT e_anon FROM pre_0204) IS DISTINCT FROM has_function_privilege('anon', 'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,int,text,text,text,uuid)', 'EXECUTE')
     OR (SELECT e_svc FROM pre_0204) IS DISTINCT FROM has_function_privilege('service_role', 'public.ottoq_record_event(text,text,text,uuid,jsonb,text,jsonb,uuid,uuid,jsonb,jsonb,text,uuid,uuid,uuid,uuid,uuid,text,int,text,text,text,uuid)', 'EXECUTE')
     OR (SELECT l_anon FROM pre_0204) IS DISTINCT FROM has_function_privilege('anon', 'public.ottoq_depot_local_time(uuid)', 'EXECUTE') THEN
    RAISE EXCEPTION '0204 A4 FAILED: a privilege moved';
  END IF;
  RAISE NOTICE '0204 A4: privileges unchanged';
  RAISE NOTICE '0204: structural assertions passed; the live probe runs next, outside this transaction';
END $assert$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0204_the_run_has_one_clock_and_the_shield_and_the_events_read_it', TRUE,
  'G11 + G15. ottoq.ottoq_run_now() is the run''s clock (NOW() outside a run; the tick-published, run-tagged GUC ottoq.sim_clock '
  'or the run row''s sim_clock_current under one). ottoq_sim_advance_tick_world publishes the clock before any phase runs. '
  'ottoq_events.sim_clock_at is filled by ottoq_record_event for run-scoped events and enters h_evt, so the h_evt canon moves '
  'once on every column by design. ottoq_depot_local_time and SLA.003/SLA.006 read the run''s clock, so TW.001/003/004/005, '
  'SLA.003 and SLA.006 stop judging a simulated day by Nashville''s wall clock; none is enforcement block, so h_cmd is '
  'predicted not to move. No backfill of sim_clock_at. The live probe runs immediately after COMMIT, not inside it: the '
  'grid pair for the event stream and the flagship TW.001 census for the shield. See the APPLIED footer and db/checks/0118.',
  now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;

COMMIT;

-- =====================================================================
-- APPLIED 2026-09-07 18:18:01 UTC (1:18 PM CT) -- one transaction as
-- postgres, sent directly (statement_timeout 55s), first attempt after
-- the two failures recorded below. Verified immediately after:
--
--   lineage row                 present, 18:18:01.484, forces_recert TRUE
--   ottoq.ottoq_run_now()       present, not SECURITY DEFINER
--   ottoq_events.sim_clock_at   present (nullable timestamptz, no default)
--   ottoq_sim_advance_tick_world  9b49f2e4 -> 7ef368f36476e38b0985af722e1f7062
--   ottoq_record_event            f1d96f94 -> 1b324db698715430265acc2fcd67a950
--   ottoq_depot_local_time        e0ac3c32 -> 23438748b1c5245ae025f1e4457f7803
--   ottoq_determinism_pair        7b8faece -> 4b344be9e7287d376a97ff597b949f7c
--   recert floor                20:42:00 (0207) -> 2026-09-07 18:18:01
--
-- TWO FAILURES FIRST, BOTH WORTH KEEPING
-- ---------------------------------------------------------------------
-- 1. A MALFORMED LOG LINE ABORTED THE COMPILE. The A3 RAISE NOTICE wrote
--    "h_evt %% -> %%" -- in RAISE, %% is a literal percent and consumes no
--    argument, so the format string carried six placeholders for eight
--    arguments and PL/pgSQL refused the block at compile time: "too many
--    parameters specified for RAISE". Nothing applied; the transaction
--    rolled back clean (pins and floor unmoved, verified). Fixed to
--    "h_evt % -> %". A scan of 0204, 0205 and 0206 for the same class
--    found no other mismatch.
--
-- 2. pg_cron REPORTED SUCCESS FOR A JOB THAT APPLIED NOTHING. The retry
--    ran as job 416 at 18:15:00, finished in 0.3 s, and cron.job_run_details
--    recorded status "succeeded" with command tag COMMENT. Nothing had
--    applied: no lineage row, no ottoq_run_now, no column, every md5 still
--    at its pin, and no grid run rows. The stored command was complete
--    (21,243 chars, COMMIT and the A4 text both present), so it was not
--    truncated -- the job simply stopped after a COMMENT and pg_cron called
--    that success. THE PROTOCOL LESSON, which supersedes the "long
--    migrations go through a one-shot pg_cron job" rule as stated: a
--    pg_cron run row is NOT evidence that a migration applied. Only the
--    post-apply catalog read is. Every future apply verifies the lineage
--    row and the body md5s before it is called done, whatever the job
--    status says.
--
-- A3 WAS RESTRUCTURED, AND WHY (the file above reflects what ran)
-- ---------------------------------------------------------------------
-- A3 as originally written asserted, inside the transaction, that
-- TW.001.operational_hours wrote more than one distinct local_time on the
-- grid arm. THE GRID FIXTURE NEVER EVALUATES TW.001: measured on the
-- post-apply grid pair, 0 evaluations carry a local_time. The assertion
-- was vacuous in the strong sense -- it could only ever have aborted the
-- apply, and for a reason that says nothing about the change. It is the
-- mirror of the house rule: a check that can only fail is no better than
-- one that cannot.
--
-- The probe therefore runs after COMMIT, against the fixture that actually
-- exercises each half. Both halves measured 2026-09-07 18:19-18:21 UTC:
--
--   G11, the event stream (grid pair bc331b9c / b9c57f3b, 6 ticks,
--   seed 424242, grid-0169-smoke, sim start 2026-09-01 02:00:00+00):
--     equal / passed; arms agree on h_cmd (e4158c95), h_evt (79fa107a)
--     and h_rule (3fde30ff)
--     138 events on arm A, 0 with a NULL sim_clock_at, 0 outside the run
--     window, 7 DISTINCT sim times spanning 02:00:00+00 .. 05:00:00+00
--     1 DISTINCT occurred_at across all 138 -- the wall clock is still one
--       instant for the whole pair, which is precisely the G11 defect, and
--       is now harmless because sim_clock_at carries the run's time
--     h_evt moved ce7e2218 -> 79fa107a against the last pre-0204 grid pair,
--       so sim time is in the hash
--
--   G15, the shield (flagship, round 21's last pair, 24 ticks, fired
--   2026-09-06 22:51 UTC): the BEFORE census, which is the number this
--   migration exists to change --
--     TW.001.operational_hours  1,162 evaluations, ALL carrying local_time,
--                               1 DISTINCT value: 17:51:00
--   22:51 UTC is 17:51 CDT. The simulated day advanced twelve hours; the
--   shield read Nashville's wall clock at the instant the pair ran and
--   judged all 1,162 evaluations by it. TW.003, TW.005 and SLA.006 carry no
--   local_time in their payloads, so they are not directly observable this
--   way, but they read the same ottoq_depot_local_time and A2 proved that
--   function now returns the run's clock.
--
-- ROUND 22 IS THE RECERTIFICATION and the AFTER census. Predictions:
--   1. h_evt moves on ALL SIX columns. By design: sim_clock_at is in the
--      hash and no run had it before.
--   2. h_cmd, h_dec, h_bkg, h_nrg, h_prop, h_defr and h_cal DO NOT MOVE on
--      any column, and every one equals round 21's canon in
--      db/canons/round21.md. None of the six evaluators this migration
--      touches is enforcement=block, so a changed verdict cannot change a
--      command. If h_cmd moves, that reasoning is wrong and the move is
--      this migration's to explain.
--   3. h_rule MAY move: the evaluations' passed/severity can legitimately
--      change once the shield judges the simulated hour instead of the
--      Nashville hour. A move here is expected and is the point.
--   4. TW.001 reports MORE THAN ONE distinct local_time per 24-tick arm,
--      and the values track the simulated clock rather than the fire time.
--      One distinct value means the shield is still on the wall clock.
-- =====================================================================
