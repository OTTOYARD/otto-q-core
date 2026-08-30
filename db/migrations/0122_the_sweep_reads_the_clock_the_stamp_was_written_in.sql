-- migration-version: 20260830210000
-- migration-name:    the_sweep_reads_the_clock_the_stamp_was_written_in
-- 0122 -- closes the wall-vs-sim proposal-TTL front (db/checks/0046 pair-14; named to the
-- founder as the production loop's gap (b)) -- and closes it the OPPOSITE way from the
-- original sketch, because the survey found the design already decided the domain:
--
--   * The deferral core is TICK-KEYED (ottoq_cuopt_deferrals.spent_at_tick = the arm tick;
--     no clock at all) -- the one-tick right-of-first-refusal needs no TTL fix.
--   * The proposal TTL is deliberately WALL-domain, twice, in writing: defer_hold
--     ("proposal TTL stays in the REAL domain, matching ottoq_l2_external_proposal") and
--     l2_external_proposal ("in the REAL domain (see migration note)"). A cuOpt proposal
--     goes stale in real time -- the optimizer solved a real snapshot. Production runs at
--     sim==wall, so live semantics are one domain anyway.
--   * Exactly ONE site mixes domains: decide_tick's expiry sweep compares the wall-stamped
--     TTL to the SIM clock (v_clock). A sim run's clock sits days ahead of wall, so
--     GREATEST(expires_at, created_at+35min) < v_clock is TRUE the moment the sweep runs:
--     every pending proposal insta-expires on its birth tick. Ledger, last 7 days of
--     cuOpt proposals: 27 enacted / 62 expired / 47 superseded -- enactment only ever
--     happens within the birth tick, because the deliberate 35-minute window is truncated
--     to one tick in every sim-feed run. Production (sim==wall) was coherent by luck.
--
-- FIX: the sweep compares in the domain the stamp was written in -- WALL. One comparison.
-- Cert note: within a determinism pair (one transaction) now() is frozen, so proposals no
-- longer expire mid-pair; l2's fresh-start DELETE still retires its own rows per tick, and
-- cuOpt is structurally absent from cert runs. Canon movement, if any, is handled by the
-- 0046 transition-pair rule.
--
-- Pre-image pin, read live 2026-08-30 (anchor verified at exactly 1 occurrence):
--   public.ottoq_decide_tick   807d8e72ede8e3b2eaefc438e76c9133

DO $patch$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'p.created_at+interval ''35 minutes'') < v_clock;';
  v_new text := 'p.created_at+interval ''35 minutes'') < now();  -- 0122: the stamp is wall-domain (deliberate); the sweep must read the same clock';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_decide_tick';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> '807d8e72ede8e3b2eaefc438e76c9133' THEN
    RAISE EXCEPTION '0122 abort: decide_tick drifted (md5 %)', md5(v_src);
  END IF;
  v_cnt := (length(v_src)-length(replace(v_src, v_old,'')))/length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0122 abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  IF position('the sweep must read the same clock' in pg_get_functiondef(v_oid)) = 0 THEN
    RAISE EXCEPTION '0122 abort: patch did not survive';
  END IF;
  RAISE NOTICE '0122 applied: the sweep reads the clock the stamp was written in.';
END
$patch$;
