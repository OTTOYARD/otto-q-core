-- migration-version: 20260820070000
-- migration-name:    vehicle_state_trigger_preserve_caller_clock
-- 0057 — C7 FOLLOW-UP #11, found by re-certification #11 (post-0056 arms
-- 112fea03 vs 5a209c14: 3/20 identical, first divergence sim-min 120). The
-- 0056 quiesce is proven working: 40 ledger-logged 'policy_disabled' gate
-- refusals, ZERO real cuOpt HTTP calls, deferral holds inert. At tick 4 every
-- state and SoC is paired; the residue is the decide path's task_start
-- PROCESSING ORDER, fully scrambled across the pair. The task_start cursors
-- order by (last_state_change, id) — and the vehicles trigger
-- public.log_vehicle_state_change (trg_vehicle_state_change) unconditionally
-- overwrites NEW.last_state_change with NOW() on every state change,
-- clobbering the sim-clock stamp every twin write site passes. That makes
-- last_state_change a REAL-clock column inside twin runs, so the fairness
-- cursors ranked vehicles by wall-clock execution physics, not by the seed.
-- This is the 'last_state_change real-clock ordering' finding parked since
-- re-cert #4, now measured directly.
--
-- THE FIX: one guard. If the UPDATE did not itself set last_state_change,
-- the trigger defaults it to NOW() exactly as before (production callers
-- unchanged, byte-for-byte). If the caller DID set it — as every twin path
-- deliberately does — the stamp is preserved. Same in-place mechanism as
-- 0054-0056; pre-image pin 84114b89d22276da9359ec134150878d.

DO $do$
DECLARE
  p RECORD; v_oid oid; v_src text; v_cnt int;
BEGIN
  FOR p IN
    SELECT * FROM (VALUES
    ('public','log_vehicle_state_change','84114b89d22276da9359ec134150878d',1,$anchor$    NEW.last_state_change = NOW();$anchor$,$anchor$    /* ══════════ 0057: PRESERVE THE CALLER'S CLOCK ══════════
       This trigger unconditionally stamped NOW() over last_state_change,
       clobbering the SIM-CLOCK stamp that every twin write site carefully
       passes (p_sim_clock / v_clock / p_sim_clock_now — 40+ sites swept).
       That made last_state_change a REAL-clock column in twin runs, and two
       decide-path fairness cursors ORDER BY it — so vehicle processing order
       tracked wall-clock execution physics instead of the seed (measured:
       re-cert #11, tick-4 task_start order fully scrambled across a same-seed
       pair with every state and SoC paired). The guard keeps the old behavior
       byte-for-byte for callers that DON'T set the column (it defaults to
       NOW() exactly as before) and stops clobbering callers that DO. */
    IF NEW.last_state_change IS NOT DISTINCT FROM OLD.last_state_change THEN
      NEW.last_state_change = NOW();
    END IF;$anchor$)
    ) AS t(sch, fn, pre_md5, n_expected, old, new)
  LOOP
    SELECT pr.oid INTO STRICT v_oid
      FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = p.sch AND pr.proname = p.fn;
    v_src := pg_get_functiondef(v_oid);
    IF md5(v_src) <> p.pre_md5 THEN
      RAISE EXCEPTION '0057: %.% pre-image md5 % != pinned %', p.sch, p.fn, md5(v_src), p.pre_md5;
    END IF;
    v_cnt := (length(v_src) - length(replace(v_src, p.old, ''))) / length(p.old);
    IF v_cnt <> p.n_expected THEN
      RAISE EXCEPTION '0057: %.% anchor occurs % times (need %)', p.sch, p.fn, v_cnt, p.n_expected;
    END IF;
    EXECUTE replace(v_src, p.old, p.new);
    RAISE NOTICE '0057 patched %.% -> md5 %', p.sch, p.fn,
      (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
        JOIN pg_namespace n ON n.oid = pr.pronamespace
       WHERE n.nspname = p.sch AND pr.proname = p.fn);
  END LOOP;
END
$do$;
