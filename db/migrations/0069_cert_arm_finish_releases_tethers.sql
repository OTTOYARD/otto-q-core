-- migration-version: 20260822031000
-- migration-name:    cert_arm_finish_releases_tethers
-- 0069 -- HARNESS ONLY. public.ottoq_cert_arm_finish now releases any robotic-arm tether
-- still held at the benchmark depot as part of teardown.
--
-- THE DEFECT, and it is a domain mismatch of exactly the family 0065 and 0067 hit.
-- public.ottoq_arm_interlock_guard blocks any move of a tethered vehicle, comparing
-- vehicles.robotic_tether_until against the sim clock of the RUNNING run:
--     v_clock := COALESCE((SELECT sim_clock_current FROM ottoq_sim_runs
--                           WHERE status = 'running' ORDER BY started_at DESC LIMIT 1), now());
-- Between two cert arms there IS no running run, so that COALESCE falls through to now() --
-- the REAL clock. Tethers are stamped in the SIM domain (since 0065, ~21-22 hours ahead), so a
-- leftover tether reads as far-future forever and ottoq_benchmark_reset can never move the
-- vehicle. Arming the second arm of a pair then dies with:
--     arm interlock: vehicle ... is held by the arm at stall ... refusing to move it to nowhere
--
-- WHY IT ONLY STARTED FIRING NOW: it is a symptom of the depot working. While the livelock was
-- in force a run ended with 5-12 charge sessions and almost none on DCFC, so a run essentially
-- never ended with a live mate. Post-0066 a run ends with 9-18 DCFC sessions and the arm gate
-- fires on 100% of DCFC, so there is nearly always a tether outstanding. Measured at the end of
-- re-cert #19 arm A: SIX vehicles still tethered (3 charging/charging, 3 demate/unlatch).
--
-- COST SO FAR: three arms discarded and hand-cleared across re-certs #19, #20 and #21, each one
-- a manual twin.ottoq_arm_emergency_release sweep before the next arm_start.
--
-- THE FIX: teardown releases what teardown created, through the documented escape hatch rather
-- than by nulling columns -- ottoq_arm_emergency_release closes the open arm_cycles rows and
-- emits the proper events, which a direct UPDATE would skip. The clock passed is the run's OWN
-- sim_clock_current, i.e. the sim-domain instant the run actually ended, never now(): passing a
-- real-clock value here would reintroduce the very mismatch this migration exists to remove.
-- The release runs BEFORE the status flips to 'aborted', so anything that keys on the run still
-- sees it live.
--
-- Scope: ottoq_cert_arm_finish is the determinism harness's teardown entry point and has no
-- caller outside it (verified against pg_proc by catalog sweep in the same session). Production
-- scheduling semantics are untouched.
--
-- Same self-verifying in-place mechanism as 0054-0068. Pre-image pin:
--   public.ottoq_cert_arm_finish ab24e6400142b925a98159e7215bbc77
-- Anchor pre-verified read-only: exactly one occurrence.

DO $do$
DECLARE
  v_oid oid; v_src text; v_cnt int;
  v_old text := E'  PERFORM ottoq_score_run(p_run);\n  UPDATE ottoq_sim_runs SET status=''aborted'' WHERE sim_run_id=p_run;';
  v_new text := E'  PERFORM ottoq_score_run(p_run);\n\n  /* ══════════ 0069: TEARDOWN RELEASES WHAT TEARDOWN LEAVES BEHIND ══════════\n     ottoq_arm_interlock_guard compares robotic_tether_until against the sim clock of the\n     RUNNING run and falls back to now() when none is running -- which is exactly the state\n     between two cert arms. Tethers are sim-stamped (since 0065, ~21-22h ahead of real time),\n     so a leftover tether reads as far-future forever and ottoq_benchmark_reset can never move\n     the vehicle: the next arm_start dies on the interlock. Six vehicles were still tethered at\n     the end of re-cert #19 arm A, and three arms were discarded and hand-cleared across\n     #19-#21 before this landed. Only visible once the depot started working -- the livelock\n     era ended runs with almost no DCFC sessions, and the arm gate fires on 100% of DCFC.\n     The documented escape hatch is used rather than nulling the columns, because it also\n     closes the open twin.arm_cycles rows and emits the proper events. The clock handed to it\n     is this run''s OWN sim_clock_current -- the sim-domain instant the run ended. Passing\n     now() here would reintroduce the exact mismatch this exists to remove. */\n  PERFORM twin.ottoq_arm_emergency_release(\n            v.id,\n            ''cert_arm_finish teardown (0069)'',\n            ''cert_harness'',\n            p_run,\n            COALESCE((SELECT r.sim_clock_current FROM ottoq_sim_runs r\n                       WHERE r.sim_run_id = p_run), now()))\n     FROM vehicles v\n    WHERE v.home_depot_id = d\n      AND v.robotic_tether_until IS NOT NULL;\n\n  UPDATE ottoq_sim_runs SET status=''aborted'' WHERE sim_run_id=p_run;';
BEGIN
  SELECT pr.oid INTO STRICT v_oid
    FROM pg_proc pr JOIN pg_namespace n ON n.oid = pr.pronamespace
   WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_finish';
  v_src := pg_get_functiondef(v_oid);
  IF md5(v_src) <> 'ab24e6400142b925a98159e7215bbc77' THEN
    RAISE EXCEPTION '0069: pre-image md5 % != pinned ab24e6400142b925a98159e7215bbc77', md5(v_src);
  END IF;

  v_cnt := (length(v_src) - length(replace(v_src, v_old, ''))) / length(v_old);
  IF v_cnt <> 1 THEN RAISE EXCEPTION '0069: anchor occurs % times (need 1)', v_cnt; END IF;
  v_src := replace(v_src, v_old, v_new);

  /* Post-conditions. The release must sit BEFORE the abort (so anything keying on the run
     still sees it live), and must not be handed a real clock. */
  IF position('ottoq_arm_emergency_release' in v_src) = 0 THEN
    RAISE EXCEPTION '0069: the tether release is not present';
  END IF;
  IF position('ottoq_arm_emergency_release' in v_src) > position('status=''aborted''' in v_src) THEN
    RAISE EXCEPTION '0069: the tether release must run BEFORE the run is aborted';
  END IF;

  EXECUTE v_src;
  RAISE NOTICE '0069 patched public.ottoq_cert_arm_finish -> md5 %',
    (SELECT md5(pg_get_functiondef(pr.oid)) FROM pg_proc pr
      JOIN pg_namespace n ON n.oid = pr.pronamespace
     WHERE n.nspname = 'public' AND pr.proname = 'ottoq_cert_arm_finish');
END
$do$;
