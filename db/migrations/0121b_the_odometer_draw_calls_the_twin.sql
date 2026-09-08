-- migration-version: 20260830142542
-- migration-name:    the_odometer_draw_calls_the_twin
--
-- ---------------------------------------------------------------------------
-- RECOVERED 2026-09-08, not authored then. Applied to gxdrcyphqjzjsuhxuqtg on
-- 2026-08-30 14:25:42 UTC with no file. The second of the two changes Section A
-- of the drift check named on the first day the alarm could fire (task G18);
-- the other is 0110b.
--
-- The body below is VERBATIM from supabase_migrations.schema_migrations.
--
-- WHAT IT DID: 0121 pointed the life-miles draw at
-- public.ottoq_sim_seeded_random, but that function lives in the twin schema.
-- The text-anchored post-check in 0121 could not see a call-time error, so
-- every certification reset aborted until this landed. Note the lesson it
-- states about itself, which the repo has since adopted everywhere: "this time
-- the post-condition EXECUTES the reset" — an assertion that runs the thing
-- rather than grepping for it.
--
-- Safe to re-run in principle (it is anchored and idempotent-by-abort), but it
-- will abort if the anchor is not found exactly once, which is correct.
-- ---------------------------------------------------------------------------

-- 0121b -- the 0121 draw named the wrong schema (ottoq_sim_seeded_random lives in twin);
-- the text-anchored post-check could not catch a call-time error, so every cert reset
-- aborted. Corrected in place, and this time the post-condition EXECUTES the reset.

DO $fix$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := 'public.ottoq_sim_seeded_random(p_seed, ''veh_lifemiles:''';
  v_new text := 'twin.ottoq_sim_seeded_random(p_seed, ''veh_lifemiles:''';
BEGIN
  SELECT p.oid INTO STRICT v_oid FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_tick_invariance_reset_fleet';
  v_src := pg_get_functiondef(v_oid);
  v_cnt := (length(v_src)-length(replace(v_src, v_old,'')))/length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0121b abort: anchor found % times', v_cnt; END IF;
  EXECUTE replace(v_src, v_old, v_new);
  -- the post-condition that actually bites: run the reset end to end
  PERFORM public.ottoq_tick_invariance_reset_fleet('11111111-1111-1111-1111-111111111111'::uuid, 42);
  RAISE NOTICE '0121b applied: the draw calls the twin, and the reset executes clean.';
END
$fix$;
