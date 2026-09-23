-- migration-version: PENDING
-- migration-name:    the_ab_pair_filed_its_second_arms_fleet_reset_as_the_first_arms_evidence
--
-- 0442  **`ottoq_ab_pair` never received 0421's reset.** 0421 fixed the 0329 defect in `ottoq_determinism_pair`
--       only: both arms run in one transaction, `ottoq.ottoq_active_sim_run_id()` caches its answer in the
--       transaction-local GUC `ottoq.sim_run_id`, and `ottoq_sim_stop_and_reset` leaves that GUC pinned to the run it
--       tore down. So the next arm's `ottoq_tick_invariance_reset_fleet`, which runs before that arm's run exists,
--       is filed as the previous arm's evidence. `ottoq_ab_pair` (the C5 A/B rig) has the same shape and no reset.
--       FINDINGS G176.
--
-- ══ §1 MEASURED 2026-09-23, FROM SOURCE ══════════════════════════════════════════════════════════════════════
--
--   - `ottoq_ab_pair` (`md5(prosrc)` `a02d6601…`) opens its `FOR v_arm IN 1..2 LOOP` with
--     `ottoq_tick_invariance_reset_fleet` and then `twin.ottoq_sim_start_run`, and contains no
--     `set_config('ottoq.sim_run_id'` at all. `ottoq_determinism_pair` makes that call once, as the first statement
--     of the same loop, and 0439's `ottoq_dial_pair` makes it before each arm and once after the loop.
--   - Its verdicts are unaffected, for the reason 0329's were: each arm's digest is taken before the next reset
--     exists. What fails is re-deriving an A/B arm's event set from the archive.
--   - Nothing in the database calls it (no function, no cron job), so this changes no run that is scheduled.
--
-- ══ §2 WHAT THIS DOES ════════════════════════════════════════════════════════════════════════════════════════
--
--   (1) `set_config('ottoq.sim_run_id', 'none', true)` as the first statement of each arm, exactly as 0421.
--   (2) The same call once after the loop, exactly as 0439, so the verdict and score writes that follow belong to
--       no arm.
--
-- ══ §3 forces_recert FALSE ═══════════════════════════════════════════════════════════════════════════════════
--
--   `ottoq_ab_pair` is not the certification rig and nothing calls it; no canon column runs through it.

BEGIN;

-- ── P0: nothing in flight ──
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN RAISE EXCEPTION '0442 P0: certification jobs are still scheduled (%)', v_jobs; END IF;
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_ab_pair%' OR query ILIKE '%ottoq_dial_pair%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0442 P0: a pair is running right now'; END IF;
  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status IN ('running','paused');
  IF v_runs > 0 THEN RAISE EXCEPTION '0442 P0: % sim run(s) running/paused -- apply between runs', v_runs; END IF;
END $inflight$;

-- ── P1: the rig as read on 2026-09-23, with both anchors unique and no reset yet ──
DO $$
DECLARE v_src text; v_n int;
  c_open  CONSTANT text := E'  FOR v_arm IN 1..2 LOOP\n    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);';
  c_close CONSTANT text := E'    PERFORM public.ottoq_sim_stop_and_reset(v_run, ''ab_arm_complete'');\n  END LOOP;';
BEGIN
  SELECT prosrc INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_ab_pair(bigint,integer,text,uuid,timestamp with time zone,integer,text,text)'::regprocedure;
  IF md5(v_src) <> 'a02d660122e25f46e649ce334f93c223' THEN RAISE EXCEPTION '0442 P1: ottoq_ab_pair md5 is %', md5(v_src); END IF;
  v_n := (length(v_src) - length(replace(v_src, c_open, ''))) / length(c_open);
  IF v_n <> 1 THEN RAISE EXCEPTION '0442 P1: the loop-open anchor matched % times', v_n; END IF;
  v_n := (length(v_src) - length(replace(v_src, c_close, ''))) / length(c_close);
  IF v_n <> 1 THEN RAISE EXCEPTION '0442 P1: the loop-close anchor matched % times', v_n; END IF;
  IF position('set_config(''ottoq.sim_run_id''' IN v_src) > 0 THEN RAISE EXCEPTION '0442 P1: the rig already resets the GUC'; END IF;
END $$;

-- ── SNAPSHOT ──
INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0442_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_ab_pair(bigint,integer,text,uuid,timestamp with time zone,integer,text,text)'::regprocedure;

-- ── (1)+(2) THE TWO RESETS ──
DO $splice$
DECLARE v_def text; v_new text;
  c_open  CONSTANT text := E'  FOR v_arm IN 1..2 LOOP\n    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);';
  c_close CONSTANT text := E'    PERFORM public.ottoq_sim_stop_and_reset(v_run, ''ab_arm_complete'');\n  END LOOP;';
BEGIN
  v_def := pg_get_functiondef('public.ottoq_ab_pair(bigint,integer,text,uuid,timestamp with time zone,integer,text,text)'::regprocedure);
  v_new := replace(v_def, c_open,
       E'  FOR v_arm IN 1..2 LOOP\n'
    || E'    PERFORM set_config(''ottoq.sim_run_id'', ''none'', true);  /* 0442 (0421 in this rig): the reset runs BEFORE this arm''s run exists */\n'
    || E'    PERFORM public.ottoq_tick_invariance_reset_fleet(p_depot, p_seed, p_sim_start);');
  v_new := replace(v_new, c_close,
       c_close || E'\n'
    || E'  -- 0442: stop_and_reset pins the tagging GUC to the run it tore down; what follows belongs to no arm\n'
    || E'  PERFORM set_config(''ottoq.sim_run_id'', ''none'', true);');
  IF v_new = v_def OR (length(v_new) - length(replace(v_new, 'set_config(''ottoq.sim_run_id''', ''))) / length('set_config(''ottoq.sim_run_id''') <> 2 THEN
    RAISE EXCEPTION '0442: the splices did not both apply';
  END IF;
  EXECUTE v_new;
END $splice$;

-- ── V1: in comment-stripped source, the reset precedes the fleet reset inside the loop, and closes it ──
DO $$
DECLARE v_src text; v_loop int; v_reset int; v_fleet int; v_stop int; v_after int;
BEGIN
  SELECT regexp_replace(regexp_replace(prosrc, '/\*.*?\*/', '', 'g'), '--[^\n]*', '', 'g') INTO v_src FROM pg_proc
   WHERE oid = 'public.ottoq_ab_pair(bigint,integer,text,uuid,timestamp with time zone,integer,text,text)'::regprocedure;
  v_loop  := position('FOR v_arm IN 1..2 LOOP' IN v_src);
  v_reset := position('set_config(''ottoq.sim_run_id'', ''none'', true)' IN v_src);
  v_fleet := position('ottoq_tick_invariance_reset_fleet' IN v_src);
  v_stop  := position('ottoq_sim_stop_and_reset' IN v_src);
  v_after := position('set_config(''ottoq.sim_run_id'', ''none'', true)' IN substring(v_src FROM v_stop));
  IF v_loop = 0 OR v_reset < v_loop OR v_reset > v_fleet OR v_after = 0 THEN
    RAISE EXCEPTION '0442 V1: the resets are not where 0421 and 0439 put them (loop %, reset %, fleet %, after-stop %)',
      v_loop, v_reset, v_fleet, v_after;
  END IF;
END $$;

-- ── LINEAGE ──
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('0442_the_ab_pair_filed_its_second_arms_fleet_reset_as_the_first_arms_evidence',
   false,
   'G176: ottoq_ab_pair resets ottoq.sim_run_id before each arm''s fleet reset (0421''s fix) and after its arm loop '
   '(0439''s), so the second arm''s reset is no longer filed as the first arm''s evidence. The A/B rig is not the '
   'certification rig and has no caller.')
ON CONFLICT (name) DO UPDATE SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note;

COMMIT;

-- forces_recert FALSE. Rollback: restore ottoq_ab_pair from ottoq_schema_snapshots label '0442_pre'.
