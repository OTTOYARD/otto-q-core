-- migration-version: 20260926112403
-- migration-name:    the_energy_command_hashed_the_day_plans_solve_time_so_a_reserve_shaving_depot_could_not_certify
--
-- 0477  **The energy command's reason carried the day plan's wall-clock solve time, so the energy atom differed
--       between identical arms and a reserve-shaving depot could not certify.** `db/checks/0361`. FINDINGS G211.
--
-- ══ §1 MEASURED ════════════════════════════════════════════════════════════════════════════════════════════════
--
--   The overnight dial experiment b66fa99c (energy_reserve_shave 0 vs 1) concluded treatment_wins at 09:40 UTC
--   (4:40 AM CT) and the promoter set energy_reserve_shave = 1 at the twin depot. From then the recertification
--   runner failed busy_day / 171717 / 12 ticks on every attempt, 40 verdicts in 90 minutes, on one atom alone:
--   `energy`. 13 of 14 atoms matched, the world end state included, and `h_nrg` took a new value in every arm of
--   every attempt. The two arms' 24 `ottoq_energy_commands` rows match field for field except one key inside the
--   hashed `reason`: `day_plan.solve_ms`, the day-plan optimizer's wall-clock solve time (52 vs 61 ms, 33 vs 37,
--   40 vs 36, 63 vs 59, ...). The setpoints, modes, SoC, forecasts and plan values are identical. The depot was
--   rolled back to energy_reserve_shave = 0 at 11:08:57 UTC (6:08 AM CT) so certification could proceed.
--
-- ══ §2 THE MECHANISM ═══════════════════════════════════════════════════════════════════════════════════════════
--
--   `public.ottoq_bess_day_plan` measures its own solve with `clock_timestamp()` and returns it as `solve_ms`.
--   `public.ottoq_energy_orchestrate` embeds the plan in the BESS command's `reason`, already minus `forecast` and
--   `discharge_plan_kw`, and the energy atom hashes `reason`. A wall-clock duration is not a decision, so hashing it
--   makes a deterministic engine look nondeterministic: the class of 0137 (a write timestamp) and 0216 (a minted id).
--   The plan's solve time is also written, as latency, by `ottoq_publish_day_plan`, which keeps it.
--
-- ══ §3 WHAT THIS DOES ══════════════════════════════════════════════════════════════════════════════════════════
--
--   The reason's embedded plan also drops `solve_ms`. The publication ledger keeps the solve time as its latency, so
--   no telemetry is lost. Nothing the energy step decides changes.
--
-- ══ §4 forces_recert TRUE ══════════════════════════════════════════════════════════════════════════════════════
--
--   Tick path: energy commands' reasons move wherever the day plan is embedded, so the energy atom's content moves.
--
--   PREDICTED: with energy_reserve_shave = 1 at the twin depot, busy_day / 171717 / 12 ticks certifies (the energy
--   atom agrees across arms), and so does every other column.

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
  IF v_pairs > 0 THEN RAISE EXCEPTION '0477 P0: a pair or the recert runner is running right now'; END IF;
END $inflight$;

-- ── P2: the body this file patches, exactly as measured ──
DO $premises$
BEGIN
  IF md5(pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure))
     <> '48c452ebb2a0f0b749384918e1aa41eb' THEN
    RAISE EXCEPTION '0477 P2: public.ottoq_energy_orchestrate is not the body this file patches';
  END IF;
  -- the solve time is still measured by the day plan and still kept as latency by the publication ledger
  IF position($x$'solve_ms', round(EXTRACT(EPOCH FROM (clock_timestamp() - v_t0)) * 1000)$x$
              IN pg_get_functiondef('public.ottoq_bess_day_plan(uuid,uuid,timestamp with time zone,numeric)'::regprocedure)) = 0
     OR position($x$round(NULLIF(p_plan->>'solve_ms', '')::numeric)::int$x$
              IN pg_get_functiondef('public.ottoq_publish_day_plan(uuid,uuid,timestamp with time zone,bigint,jsonb,numeric,numeric)'::regprocedure)) = 0 THEN
    RAISE EXCEPTION '0477 P2: the day plan no longer measures solve_ms, or the publication ledger no longer keeps it';
  END IF;
END $premises$;

INSERT INTO public.ottoq_schema_snapshots
       (label, object_kind, schema_name, object_name, definition, def_md5)
SELECT '0477_pre', 'function', n.nspname, p.proname, pg_get_functiondef(p.oid), md5(pg_get_functiondef(p.oid))
  FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
 WHERE p.oid = 'public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure;

DO $patch_reason$
DECLARE
  v_def text := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
  v_pat text := $p$jsonb_build_object\('day_plan', v_day_plan - 'forecast' - 'discharge_plan_kw'\)$p$;
  v_new text := $r$jsonb_build_object('day_plan', v_day_plan - 'forecast' - 'discharge_plan_kw'
                                                      -- 0477 (G211): a wall-clock solve time is not a decision, and the energy atom hashes this reason
                                                      - 'solve_ms')$r$;
  n int;
BEGIN
  SELECT count(*) INTO n FROM regexp_matches(v_def, v_pat, 'g');
  IF n <> 1 THEN RAISE EXCEPTION '0477: the embedded day plan matched % times, not once', n; END IF;
  v_def := regexp_replace(v_def, v_pat, v_new);
  EXECUTE v_def;
END $patch_reason$;

-- ═══ verification ══════════════════════════════════════════════════════════════════════════════════════════════
DO $verify$
DECLARE v_s text := pg_get_functiondef('public.ottoq_energy_orchestrate(uuid,uuid,timestamp with time zone,bigint)'::regprocedure);
BEGIN
  -- V1: the embedded plan drops solve_ms, once, and the publication call still receives the whole plan.
  IF (SELECT count(*) FROM regexp_matches(v_s, $x$v_day_plan - 'forecast' - 'discharge_plan_kw'\s+-- 0477 \(G211\)[^\n]*\n\s+- 'solve_ms'\)$x$, 'g')) <> 1
     OR position('PERFORM public.ottoq_publish_day_plan(p_sim_run_id, p_depot_id, p_sim_clock, p_tick_seq, v_day_plan,' IN v_s) = 0 THEN
    RAISE EXCEPTION '0477 V1: the energy step is not the body this file writes';
  END IF;
  -- V2: one overload, the same grants.
  IF (SELECT count(*) FROM pg_proc p JOIN pg_namespace ns ON ns.oid = p.pronamespace
       WHERE ns.nspname = 'public' AND p.proname = 'ottoq_energy_orchestrate') <> 1 THEN
    RAISE EXCEPTION '0477 V2: an overload appeared';
  END IF;
END $verify$;

-- Rollback: restore the function from ottoq_schema_snapshots label '0477_pre' (CREATE OR REPLACE; the grants are kept).

INSERT INTO public.ottoq_cert_lineage(name, forces_recert, note, classified_at)
VALUES ('0477_the_energy_command_hashed_the_day_plans_solve_time_so_a_reserve_shaving_depot_could_not_certify', true,
  'Tick path: ottoq_energy_orchestrate drops the day plan''s wall-clock solve_ms from the BESS command reason the '
  'energy atom hashes. Energy command reasons move wherever the day plan is embedded.', now())
ON CONFLICT (name) DO NOTHING;
COMMIT;
