-- migration-version: PENDING
-- migration-name:    a_dial_promotion_the_canon_keeps_failing_under_now_rolls_itself_back
--
-- 0481  **A dial promotion the canon keeps failing under now rolls itself back.** `db/checks/0361` §3. FINDINGS
--       G211 (its open half).
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   Promotion 9 (energy_reserve_shave 0 -> 1 at the twin depot, 09:40 UTC) moved the recertification floor. The recert
--   runner (cron 746) then ran busy_day / 171717 / 12 ticks back to back and failed it 40 times in 78 minutes, never
--   reaching the other six twin-depot columns, until a human rolled the promotion back at 11:08:57 UTC. The runner
--   picks the first column below the floor and runs a pair. It has no notion of a column that keeps failing, or of
--   what moved the floor.
--
-- ══ §2 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_recert_promotion_guard(scenario, seed, ticks, depot, min_failures := 3)`, called by the runner just
--   before its pair. It rolls a promotion back only when all four hold:
--     (a) the latest floor-moving lineage row is a dial promotion's (`dial_promotion_<id>_<key>`) and IS the floor,
--         so nothing applied since could be the cause;
--     (b) that promotion is enacted and not already rolled back;
--     (c) the column about to run has failed at least min_failures times since the floor, and passed none;
--     (d) no lineage row named `rollback_dial_promotion_<id>_<key>` exists yet.
--   It then calls the existing `public.ottoq_rollback_dial_promotion(id)` (through the setter, as every promotion
--   and rollback does), writes the failing column and verdict ids into that rollback's ledger row, and records a
--   forces_recert lineage row, so the canon re-certifies under the incumbent. The runner returns, and its next
--   minute starts the sweep. Otherwise the guard returns `action: none` with the reason, and the runner runs its pair.
--
--   Three failures of one column, about six minutes for a 12-tick column, against G211's 78. A promotion rolled back
--   this way can be re-proposed by a later experiment; a rollback is never the loss a promotion that cannot certify is.
--
-- ══ §3 forces_recert FALSE ═════════════════════════════════════════════════════════════════════════════════════
--
--   The runner, not the tick. No atom's content moves. The guard can move the floor itself, by design, only through
--   the rollback it performs.

BEGIN;

-- ── P0: no pair in flight ──
DO $inflight$
DECLARE v_pairs int;
BEGIN
  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE (query ILIKE '%ottoq_determinism_pair%' OR query ILIKE '%ottoq_dial_pair%'
          OR query ILIKE '%ottoq_dial_experiment_runner%' OR query ILIKE '%ottoq_ab_pair%'
          -- G194: the recert runner names the pair past pg_stat_activity's 1 kB of query text.
          OR query ILIKE '%ottoq_recert_runner%')
     AND state = 'active' AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN RAISE EXCEPTION '0481 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the runner and the pieces the guard stands on, exactly as measured ──
DO $premises$
BEGIN
  IF md5((SELECT command FROM cron.job WHERE jobid = 746)) <> '3d4093cc50ae6e43dfd2aebfcd3cf175' THEN
    RAISE EXCEPTION '0481 P2: cron 746 is not the runner this file patches';
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'ottoq_recert_promotion_guard')
     OR pg_get_function_arguments('public.ottoq_rollback_dial_promotion(bigint)'::regprocedure) <> 'p_promotion_id bigint'
     OR position('rolled_back_of' IN pg_get_functiondef('public.ottoq_rollback_dial_promotion(bigint)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0481 P2: the guard exists, or the rollback no longer takes a promotion id and writes rolled_back_of';
  END IF;
  -- the promoter still names its lineage row dial_promotion_<id>_<key>
  IF position($x$v_lineage := 'dial_promotion_' || v_prom || '_' || x.param_key;$x$
              IN pg_get_functiondef('public.ottoq_promote_dial_experiment(uuid,boolean)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0481 P2: the promoter no longer names its lineage row dial_promotion_<id>_<key>';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0481_pre', 'cron_job', 'cron', 'job_746', j.command, md5(j.command) FROM cron.job j WHERE j.jobid = 746;

-- ── the guard ──
CREATE FUNCTION public.ottoq_recert_promotion_guard(p_scenario text, p_seed bigint, p_ticks integer, p_depot uuid,
                                                    p_min_failures integer DEFAULT 3)
RETURNS jsonb
LANGUAGE plpgsql
SET search_path = pg_catalog, public
AS $fn$
DECLARE
  v_floor  timestamptz := public.ottoq_cert_recert_floor();
  v_lin    record;
  v_prom   bigint;
  v_row    record;
  v_name   text;
  v_failed int;
  v_passed int;
  v_ids    bigint[];
  v_rb     jsonb;
BEGIN
  /* 0481 (G211): roll back a dial promotion the canon keeps failing under. (a) the latest floor-moving lineage
     row is a promotion's and is the floor, (b) the promotion is enacted and not rolled back, (c) this column has
     failed p_min_failures times since the floor and passed none, (d) no rollback lineage row exists yet. */
  SELECT l.name, l.classified_at INTO v_lin
    FROM public.ottoq_cert_lineage l WHERE l.forces_recert ORDER BY l.classified_at DESC LIMIT 1;
  IF v_lin.name IS NULL OR v_lin.name !~ '^dial_promotion_[0-9]+_' OR v_lin.classified_at IS DISTINCT FROM v_floor THEN
    RETURN jsonb_build_object('action', 'none', 'why', 'the floor was not moved by a dial promotion');
  END IF;
  v_prom := substring(v_lin.name FROM '^dial_promotion_([0-9]+)_')::bigint;
  SELECT * INTO v_row FROM public.ottoq_dial_promotion_ledger p WHERE p.promotion_id = v_prom;
  IF v_row.promotion_id IS NULL OR v_row.outcome IS DISTINCT FROM 'enacted'
     OR EXISTS (SELECT 1 FROM public.ottoq_dial_promotion_ledger r WHERE r.rolled_back_of = v_prom) THEN
    RETURN jsonb_build_object('action', 'none', 'why', 'the promotion is not enacted, or is already rolled back',
                              'promotion_id', v_prom);
  END IF;
  SELECT count(*) FILTER (WHERE v.outcome = 'failed'), count(*) FILTER (WHERE v.outcome = 'passed'),
         array_agg(v.verdict_id ORDER BY v.verdict_id) FILTER (WHERE v.outcome = 'failed')
    INTO v_failed, v_passed, v_ids
    FROM public.ottoq_determinism_verdict_ledger v
   WHERE v.scenario = p_scenario AND v.seed = p_seed AND v.ticks = p_ticks AND v.depot_id = p_depot
     AND v.certified_at >= v_floor;
  IF v_passed > 0 OR v_failed < p_min_failures THEN
    RETURN jsonb_build_object('action', 'none', 'why', 'the column has not failed enough times since the promotion',
                              'promotion_id', v_prom, 'failed', v_failed, 'passed', v_passed);
  END IF;
  v_name := 'rollback_dial_promotion_' || v_prom || '_' || v_row.param_key;
  IF EXISTS (SELECT 1 FROM public.ottoq_cert_lineage l WHERE l.name = v_name) THEN
    RETURN jsonb_build_object('action', 'none', 'why', 'a rollback lineage row already exists for this promotion',
                              'promotion_id', v_prom, 'lineage', v_name);
  END IF;

  v_rb := public.ottoq_rollback_dial_promotion(v_prom);
  UPDATE public.ottoq_dial_promotion_ledger r
     SET reason = format('the canon could not certify it: %s / %s / %s ticks failed %s times since the promotion and '
                         'passed none (verdicts %s). Rolled back by the recert runner (0481).',
                         p_scenario, p_seed, p_ticks, v_failed, array_to_string(v_ids, ', ')),
         evidence = jsonb_build_object('by', 'ottoq_recert_promotion_guard', 'floor', v_floor,
                                       'column', jsonb_build_object('scenario', p_scenario, 'seed', p_seed,
                                                                    'ticks', p_ticks, 'depot', p_depot),
                                       'failed_verdicts', to_jsonb(v_ids))
   WHERE r.rolled_back_of = v_prom;
  INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
  VALUES (v_name, true,
          format('0481: the recert runner rolled back promotion %s (%s %s -> %s at depot %s) after %s / %s / %s ticks '
                 'failed %s times under it. The canon re-certifies under the incumbent.',
                 v_prom, v_row.param_key, v_row.from_value, v_row.to_value, v_row.depot_id,
                 p_scenario, p_seed, p_ticks, v_failed),
          now());
  RETURN jsonb_build_object('action', 'rolled_back', 'promotion_id', v_prom, 'failed_verdicts', to_jsonb(v_ids),
                            'lineage', v_name, 'setter', v_rb);
END
$fn$;

COMMENT ON FUNCTION public.ottoq_recert_promotion_guard(text, bigint, integer, uuid, integer) IS
  '0481 (G211): called by the recert runner before each pair. Rolls back a dial promotion that moved the floor when the '
  'column about to run has failed min_failures times since, and passed none. Returns action none or rolled_back.';

REVOKE ALL ON FUNCTION public.ottoq_recert_promotion_guard(text, bigint, integer, uuid, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ottoq_recert_promotion_guard(text, bigint, integer, uuid, integer) TO service_role;

-- ── the runner calls it ──
DO $patch_runner$
DECLARE
  v_cmd text := (SELECT command FROM cron.job WHERE jobid = 746);
  v_pat text := $p$  IF NOT FOUND THEN RETURN; END IF;
  PERFORM public.ottoq_determinism_pair($p$;
  v_new text := $r$  IF NOT FOUND THEN RETURN; END IF;
  -- 0481 (G211): a dial promotion this column keeps failing under rolls itself back, and the sweep restarts
  IF public.ottoq_recert_promotion_guard(c.scenario, c.seed, c.ticks, c.depot_id)->>'action' = 'rolled_back' THEN RETURN; END IF;
  PERFORM public.ottoq_determinism_pair($r$;
BEGIN
  IF (length(v_cmd) - length(replace(v_cmd, v_pat, ''))) / length(v_pat) <> 1 THEN
    RAISE EXCEPTION '0481: the runner''s pick-then-pair seam matched other than once';
  END IF;
  PERFORM cron.alter_job(job_id := 746, command := replace(v_cmd, v_pat, v_new));
END $patch_runner$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE
  v_cmd text := (SELECT command FROM cron.job WHERE jobid = 746);
  v_g   regprocedure := 'public.ottoq_recert_promotion_guard(text,bigint,integer,uuid,integer)'::regprocedure;
BEGIN
  -- V1: the runner calls the guard once, between the pick and the pair, and is otherwise the command it was.
  IF (length(v_cmd) - length(replace(v_cmd, 'ottoq_recert_promotion_guard(c.scenario, c.seed, c.ticks, c.depot_id)', '')))
       / length('ottoq_recert_promotion_guard(c.scenario, c.seed, c.ticks, c.depot_id)') <> 1
     OR md5(replace(v_cmd, $x$
  -- 0481 (G211): a dial promotion this column keeps failing under rolls itself back, and the sweep restarts
  IF public.ottoq_recert_promotion_guard(c.scenario, c.seed, c.ticks, c.depot_id)->>'action' = 'rolled_back' THEN RETURN; END IF;$x$, ''))
        <> '3d4093cc50ae6e43dfd2aebfcd3cf175'
     OR (SELECT active FROM cron.job WHERE jobid = 746) IS NOT TRUE THEN
    RAISE EXCEPTION '0481 V1: the runner is not the command this file writes, or it is no longer active';
  END IF;
  -- V2: the guard exists once, only service_role (and its owner) may call it, and today it does nothing, since the
  -- floor was last moved by 0479, not by a promotion.
  IF (SELECT count(*) FROM pg_proc WHERE proname = 'ottoq_recert_promotion_guard') <> 1
     OR has_function_privilege('anon', v_g, 'EXECUTE') OR has_function_privilege('authenticated', v_g, 'EXECUTE')
     OR NOT has_function_privilege('service_role', v_g, 'EXECUTE') THEN
    RAISE EXCEPTION '0481 V2: the guard is not what this file creates';
  END IF;
END $verify$;

-- Rollback: cron.alter_job(746, command := the definition of ottoq_schema_snapshots label '0481_pre', kind cron_job),
-- then DROP FUNCTION public.ottoq_recert_promotion_guard(text, bigint, integer, uuid, integer).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0481_a_dial_promotion_the_canon_keeps_failing_under_now_rolls_itself_back', false,
  'Runner, not tick: cron 746 calls ottoq_recert_promotion_guard before each pair, which rolls back a dial promotion '
  'that moved the floor once the column about to run has failed three times since and passed none.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
