-- 0165  The fault assertion learns that faults end. Harness; forces_recert = false.
--
-- Assertion 14 (0161) required ZERO bookings on a faulted point for the whole
-- run. Right for an outage lasting the horizon, wrong the moment a fault heals -
-- which is now expressible, because 0163 gave a declared fault a repair_minutes
-- window that twin.ottoq_sim_recover_chargers honours.
--
-- Measured on grid-f5 (charger down 120 min of a 6-hour horizon):
--   bookings while faulted (02:00-04:00)   0
--   bookings after recovery                2   (04:30 and 06:00, charge_dcfc)
--   charger at end                         Available
-- The engine both routed around the dead point AND brought it back into service
-- by itself. Correct behaviour that assertion 14 called a failure.
--
-- The rule is now stated over the window the fault actually covers:
-- [first decision clock, + repair_minutes). Outside it the point is healthy and
-- using it is the recovery working, not a violation.
DO $patch$
DECLARE v_src text; v_before text; v_after text; v_n int;
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'twin' AND p.proname = 'ottoq_grid_assert';
  v_before := '      SELECT count(*) INTO n FROM public.ottoq_stall_bookings b' || chr(10)
           || '       WHERE b.sim_run_id = p_run AND b.stall_id = v_fstall' || chr(10)
           || '         AND b.state IN (''held'',''active'',''done'');';
  v_n := (length(v_src) - length(replace(v_src, v_before, ''))) / length(v_before);
  IF v_n <> 1 THEN RAISE EXCEPTION '0165: assertion-14 count anchor must occur exactly once, found %', v_n; END IF;
  v_after := '      SELECT count(*) INTO n FROM public.ottoq_stall_bookings b' || chr(10)
          || '       WHERE b.sim_run_id = p_run AND b.stall_id = v_fstall' || chr(10)
          || '         AND b.state IN (''held'',''active'',''done'')' || chr(10)
          || '         AND lower(b.during) < (SELECT min(d2.sim_clock) FROM public.ottoq_decisions d2' || chr(10)
          || '                                 WHERE d2.sim_run_id = p_run)' || chr(10)
          || '             + (COALESCE((v_f->>''repair_minutes'')::numeric, 100000)||'' minutes'')::interval;';
  v_src := replace(v_src, v_before, v_after);
  EXECUTE v_src;
END $patch$;

INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note, classified_at)
VALUES ('the_fault_assertion_learns_that_faults_end', false,
        'Harness: grid assertion 14 counts bookings on a faulted point only within the declared repair window, so a fault that heals mid-run and is then correctly reused no longer reads as a violation.', now())
ON CONFLICT (name) DO UPDATE SET forces_recert=EXCLUDED.forces_recert, note=EXCLUDED.note, classified_at=EXCLUDED.classified_at;
