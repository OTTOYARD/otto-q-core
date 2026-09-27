-- migration-version: 20260921190457
-- migration-name:    thirteen_writers_were_reachable_with_the_browser_key_including_three_i_shipped_this_afternoon
--
-- 0406  **Thirteen SECURITY DEFINER functions that WRITE were executable by `anon`. Three of them I
--       created four hours ago. The gate that found them was added in `0405`, ninety seconds before.**
--
-- ══ HOW THIS WAS FOUND, WHICH IS THE ONLY REASON IT WAS FOUND ══════════════
--
-- `0405` restored `anon` EXECUTE on ten read-only cockpit RPCs and, because granting EXECUTE to an
-- anonymous role on SECURITY DEFINER functions is exactly where a careless change becomes a hole,
-- added `ottoq_assert_anon_rpc_surface()` as a standing gate: *"expected empty forever."*
--
-- **Its first invocation returned thirteen rows, none of them the ten just granted.**
--
-- ══ THE MECHANISM, AND IT IS NOT AN ACCIDENT ANYONE MADE ═══════════════════
--
-- Every one of the thirteen carries an **explicit** `anon=X/postgres` entry in `proacl` — not
-- inherited from PUBLIC. That is Supabase's project-level `ALTER DEFAULT PRIVILEGES`, which grants
-- EXECUTE on **every newly created function in `public`** to `anon`, `authenticated` and
-- `service_role`. So the default posture of this database is that **a new writer in `public` is
-- reachable with the browser key the moment it is created**, and stays that way until something
-- revokes it.
--
-- `0198` swept 331 functions on 2026-09-06. These thirteen are what the default privilege has
-- re-created since, plus what that sweep missed. **This is a standing tax on every future migration,
-- not a one-off cleanup** — which is why the fix is paired with the gate rather than shipped alone.
--
-- ══ WHAT WAS REACHABLE, ORDERED BY WHAT IT COULD DO ════════════════════════
--
--   ottoq_promote_dials              CHANGES ENGINE POLICY. Promotes a dial value to depot or
--                                    global scope. Created by me in `0404` at 17:43 UTC today.
--   ottoq_rollback_dial_promotion    Reverses one. Also `0404`, also today.
--   ottoq_proposal_replay_inject     Injects proposals into the propose/dispose path.
--   ottoq_promote_proposal_candidates Promotes proposal candidates.
--   ottoq_sim_run_scenario           Starts a scenario run.
--   ottoq_start_busy_run_once        Starts a busy_day run.
--   ottoq_intelligence_refresh       Rewrites intelligence state.
--   ottoq_refresh_return_eta         Rewrites return ETAs on live dispatches.
--   ottoq_log_model_call             Appends to the evidence ledger.
--   ottoq_proposal_replay_capture    Writes replay capture rows.
--   ottoq_capture_run_dials          TRIGGER fn (`0403`, today). Triggers execute as the table
--   ottoq_capture_proposal_disposition   owner regardless of grants, so EXECUTE to anon buys
--   ottoq_capture_site_power_plan        nothing and only widens the surface.
--
-- **The three from today are the ones worth sitting with.** `0403` and `0404` built the learning
-- loop — capture run dials, score them, promote a winner behind seven evidence gates. Every one of
-- those gates is inside `ottoq_promote_dials`. None of them is an authorization check, because none
-- of them needed to be: the function was never supposed to be reachable from a browser. It was,
-- from the moment it was created, and I did not look. A gate that checks evidence is not a gate that
-- checks *who is asking*.
--
-- ══ WHAT THIS DOES ═════════════════════════════════════════════════════════
--
-- `REVOKE EXECUTE … FROM anon, PUBLIC` on all thirteen. **`authenticated` and `service_role` are
-- left untouched**, and that is safe to assert rather than hope: all thirteen carry explicit
-- `service_role=X/postgres` entries, so revoking `anon` and `PUBLIC` cannot reach them. The
-- `otto-twin-control` edge function runs under `service_role` and is unaffected.
--
-- **No cockpit call site breaks.** `0405` censused all fifteen direct-anon RPC call sites in
-- `ottoyarddepot-sim/src`. **Not one of these thirteen appears among them** — the cockpit never
-- called any of them, so anon EXECUTE was pure exposure with no consumer.
--
-- **`forces_recert` FALSE.** REVOKEs only. No table, no function body, no engine behaviour, and
-- nothing in the fourteen-atom verdict can observe a privilege bit.
--
-- ══ THE STANDING LESSON, WHICH OUTLIVES THESE THIRTEEN ═════════════════════
--
-- **Any migration that creates a function in `public` must revoke `anon` unless it has a written
-- reason not to.** The database's default grants it. `ottoq_assert_anon_rpc_surface()` is now the
-- backstop and should be run after every migration that adds a function; it is a GATE, expected
-- empty, and a non-empty result is a security regression rather than hygiene.

BEGIN;

DO $preflight$
DECLARE
  v_targets text[] := ARRAY[
    'ottoq_capture_site_power_plan','ottoq_capture_proposal_disposition','ottoq_proposal_replay_inject',
    'ottoq_proposal_replay_capture','ottoq_log_model_call','ottoq_intelligence_refresh',
    'ottoq_refresh_return_eta','ottoq_promote_proposal_candidates','ottoq_start_busy_run_once',
    'ottoq_sim_run_scenario','ottoq_capture_run_dials','ottoq_promote_dials','ottoq_rollback_dial_promotion'];
  v_n int;
  v_bad text;
BEGIN
  -- (1) The gate must exist. This migration is meaningless without the thing that found the problem.
  IF to_regprocedure('public.ottoq_assert_anon_rpc_surface()') IS NULL THEN
    RAISE EXCEPTION '0406 P1: ottoq_assert_anon_rpc_surface() is missing -- apply 0405 first';
  END IF;

  -- (2) Every target still exists.
  SELECT count(DISTINCT p.proname) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_targets);
  IF v_n <> array_length(v_targets, 1) THEN
    RAISE EXCEPTION '0406 P2: expected % targets in public, found % -- re-run the gate before revoking',
      array_length(v_targets, 1), v_n;
  END IF;

  -- (3) THE SAFETY ASSERTION THIS FILE RESTS ON. service_role must hold EXECUTE explicitly on every
  --     target, so that revoking anon and PUBLIC cannot strand the edge function. If any target
  --     relies on PUBLIC for its service_role access, revoking PUBLIC would break it, and this
  --     refuses rather than finding out in production.
  SELECT string_agg(p.proname, ', ') INTO v_bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_targets)
     AND NOT (coalesce(array_to_string(p.proacl, ' '), '') LIKE '%service_role=X%');
  IF v_bad IS NOT NULL THEN
    RAISE EXCEPTION '0406 P3: service_role lacks an EXPLICIT grant on: % -- revoking PUBLIC would strand these', v_bad;
  END IF;

  -- (4) The premise: these are currently anon-reachable. If they are not, the hole closed some
  --     other way and this file should be re-read rather than applied blind.
  SELECT count(*) INTO v_n
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = ANY(v_targets)
     AND has_function_privilege('anon', p.oid, 'EXECUTE');
  IF v_n = 0 THEN
    RAISE WARNING '0406 P4: no target is anon-reachable any more; revoke is idempotent but the premise has moved';
  END IF;
END
$preflight$;

DO $revoke$
DECLARE
  r record;
  v_count int := 0;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
      FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
     WHERE n.nspname = 'public'
       AND p.proname IN ('ottoq_capture_site_power_plan','ottoq_capture_proposal_disposition',
                         'ottoq_proposal_replay_inject','ottoq_proposal_replay_capture','ottoq_log_model_call',
                         'ottoq_intelligence_refresh','ottoq_refresh_return_eta','ottoq_promote_proposal_candidates',
                         'ottoq_start_busy_run_once','ottoq_sim_run_scenario','ottoq_capture_run_dials',
                         'ottoq_promote_dials','ottoq_rollback_dial_promotion')
  LOOP
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM anon', r.sig);
    EXECUTE format('REVOKE EXECUTE ON FUNCTION %s FROM PUBLIC', r.sig);
    v_count := v_count + 1;
  END LOOP;
  RAISE NOTICE '0406: revoked anon/PUBLIC EXECUTE on % overload(s)', v_count;
END
$revoke$;

DO $verify$
DECLARE v_left int;
BEGIN
  SELECT count(*) INTO v_left FROM public.ottoq_assert_anon_rpc_surface();
  IF v_left > 0 THEN
    RAISE EXCEPTION '0406 P5: gate still reports % problem(s) after the revoke -- do not ship a partial fix', v_left;
  END IF;
  RAISE NOTICE '0406: ottoq_assert_anon_rpc_surface() is empty';
END
$verify$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('0406_thirteen_writers_were_reachable_with_the_browser_key_including_three_i_shipped_this_afternoon',
        FALSE,
        'Revokes anon and PUBLIC EXECUTE on thirteen SECURITY DEFINER functions that WRITE and were '
        'reachable with the cockpit browser key. Found by ottoq_assert_anon_rpc_surface(), the gate '
        'added by 0405 ninety seconds earlier, whose first invocation returned thirteen rows -- none '
        'of them the ten RPCs 0405 had just granted. Mechanism: every one carries an EXPLICIT '
        'anon=X/postgres entry in proacl, from Supabase project-level ALTER DEFAULT PRIVILEGES, '
        'which grants EXECUTE on EVERY newly created public function to anon/authenticated/'
        'service_role. So the default posture is that a new writer in public is browser-reachable '
        'from creation. That makes this a standing tax on every future migration, not a one-off '
        'cleanup, which is why the revoke ships paired with the gate. THREE OF THE THIRTEEN WERE '
        'CREATED TODAY BY 0403/0404 -- ottoq_promote_dials, ottoq_rollback_dial_promotion and '
        'ottoq_capture_run_dials. ottoq_promote_dials changes engine policy and carries seven '
        'evidence gates, none of which is an authorization check, because it was never supposed to '
        'be reachable from a browser; it was, from creation, and I did not look. The other ten are '
        'proposal replay injection, proposal candidate promotion, two run starters, intelligence '
        'refresh, return-ETA refresh, the model-call ledger writer and two capture triggers. Safety: '
        'preflight (3) refuses unless service_role holds an EXPLICIT grant on every target, so '
        'revoking anon and PUBLIC cannot strand the otto-twin-control edge function, which runs '
        'under service_role. No cockpit call site breaks -- 0405 censused all fifteen direct-anon '
        'RPC call sites in ottoyarddepot-sim/src and not one of these thirteen appears among them, '
        'so anon EXECUTE was pure exposure with no consumer. A post-revoke assertion inside the same '
        'transaction refuses to commit a partial fix. STANDING LESSON: any migration creating a '
        'function in public must revoke anon unless it has a written reason not to, and the gate '
        'should be run after every such migration. forces_recert FALSE: REVOKEs only, no table, no '
        'function body, no engine behaviour, and nothing hashed can observe a privilege bit.',
        now())
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert,
      note          = EXCLUDED.note,
      classified_at = EXCLUDED.classified_at;

COMMIT;
