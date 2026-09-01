-- 0139: the end state is part of the verdict
--
-- ottoq_determinism_pair captures an end-of-run world image (endst) on every arm and then
-- never looks at it. The verdict is boot fingerprint + four stream hashes + tick count.
-- Anything the four streams do not cover can differ between two arms and the pair still
-- passes. That is a blind spot, and it was occupied: endst differed in 9 of the 9 most
-- recent pairs, every one of which passed.
--
-- The divergence is identity, not behaviour. Under a diff that pairs rows by vehicle_id
-- (an unpaired multiset diff lies here -- it matches row 1 of arm A against row 1 of arm B
-- and invents differences that are only orderings), every behavioural column and all 35
-- recall-evidence keys are byte-identical between arms. Exactly three fields carry a
-- per-run random uuid into the image:
--
--   ottoq_stall_bookings.visit_id                     -- a per-run FK, never stripped
--   ottoq_stall_bookings.why                          -- renders a leg id: "leg fc215503 (...)"
--   ottoq_vehicle_dispatches.return_evidence          -- appointment.correlation_id
--
-- So the instrument, not the engine, is what has been failing. This migration makes the
-- image id-blind and then puts it in the verdict, where an end-state divergence that the
-- streams cannot see becomes a failed pair instead of a silent pass.
--
-- Measured on the 00:12 pair (arms 952421ec / f3451a24), read-only, before writing this:
--   bookings   1064 rows both arms -- unscrubbed hashes differ, scrubbed roll up to 78ccd4b3 on both
--   dispatches  116 rows both arms -- unscrubbed hashes differ, scrubbed roll up to 8682d29e on both
--   legs, visit_needs -- already identical, unchanged by the scrub
-- The 8-hex-token rule was checked against ottoq_itinerary_legs: 812 tokens matched in the
-- two arms' why text, 512 distinct, 0 that are not a real leg-id prefix. It clobbers ids
-- and nothing else. Evidence: db/checks/0060.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- 1. The scrubber. One place where "this token is an identity, not a fact" is decided.
-- ---------------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_scrub_ids(p_text text)
RETURNS text LANGUAGE sql IMMUTABLE AS $fn$
  SELECT regexp_replace(
           regexp_replace(p_text,
             '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}', '<uuid>', 'g'),
           '\m[0-9a-f]{8}\M', '<id8>', 'g');
$fn$;

COMMENT ON FUNCTION public.ottoq_scrub_ids(text) IS
  'Replaces uuids and bare 8-hex id prefixes with placeholders so free-text explanation '
  'columns can be compared across two runs of the same seed. Behavioural words survive; '
  'only identities are collapsed.';

-- The scrubber must collapse identities AND MUST NOT collapse facts. Both directions,
-- asserted here, so this is a check that can fail rather than a comment claiming it works.
DO $chk$
BEGIN
  IF public.ottoq_scrub_ids('leg fc215503 (inspect, matched caller)')
     IS DISTINCT FROM public.ottoq_scrub_ids('leg 780826fe (inspect, matched caller)') THEN
    RAISE EXCEPTION '0139: scrubber failed to collapse two leg-id prefixes';
  END IF;
  IF public.ottoq_scrub_ids('a1b2c3d4-0000-0000-0000-000000000000 charge')
     IS DISTINCT FROM public.ottoq_scrub_ids('ffffffff-1111-2222-3333-444444444444 charge') THEN
    RAISE EXCEPTION '0139: scrubber failed to collapse two uuids';
  END IF;
  IF public.ottoq_scrub_ids('leg fc215503 (inspect, matched caller)')
     = public.ottoq_scrub_ids('leg fc215503 (charge, matched caller)') THEN
    RAISE EXCEPTION '0139: scrubber collapsed a behavioural difference (inspect vs charge)';
  END IF;
  IF public.ottoq_scrub_ids('NASH-STG-B012 temp_hold 02:30-02:45')
     = public.ottoq_scrub_ids('NASH-STG-B011 temp_hold 02:30-02:45') THEN
    RAISE EXCEPTION '0139: scrubber collapsed a stall code';
  END IF;
END
$chk$;

-- ---------------------------------------------------------------------------------------
-- 2. Make the end-state image id-blind. Anchored surgery, not a rewrite.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_repl text; v_n int;
  c_pin CONSTANT text := '2a8fb5a995fe213ef0250b89a9206475';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_boot_state_fingerprint';

  IF v_src IS NULL THEN
    RAISE EXCEPTION '0139: public.ottoq_boot_state_fingerprint not found';
  END IF;
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0139: ottoq_boot_state_fingerprint moved under this migration (pin %, found %)',
      c_pin, md5(v_src);
  END IF;

  -- bookings: drop the per-run visit FK, scrub the rendered leg id out of the reason text.
  v_anchor := $a$md5((to_jsonb(t) - 'booking_id' - 'sim_run_id' - 'decision_id' - 'leg_id'
              - 'booked_at' - 'created_at' - 'updated_at')::text) AS h$a$;
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0139: bookings anchor matched % times, expected 1', v_n; END IF;

  v_repl := $r$md5(((to_jsonb(t) - 'booking_id' - 'sim_run_id' - 'decision_id' - 'leg_id'
              - 'visit_id' - 'booked_at' - 'created_at' - 'updated_at' - 'why')
              || jsonb_build_object('why', public.ottoq_scrub_ids(t.why)))::text) AS h$r$;
  v_new := replace(v_src, v_anchor, v_repl);

  -- dispatches: the recall-evidence blob carries an appointment correlation id.
  v_anchor := $a$md5((to_jsonb(t) - 'dispatch_id' - 'sim_run_id' - 'created_at')::text) AS h$a$;
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0139: dispatches anchor matched % times, expected 1', v_n; END IF;

  v_repl := $r$md5(((to_jsonb(t) - 'dispatch_id' - 'sim_run_id' - 'created_at' - 'return_evidence')
              || jsonb_build_object('return_evidence',
                   t.return_evidence #- '{appointment,correlation_id}'))::text) AS h$r$;
  v_new := replace(v_new, v_anchor, v_repl);

  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 3. Put the image in the verdict.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_repl text; v_n int;
  c_pin CONSTANT text := '3745106fde40d891c0570718c12cf1a5';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';

  IF v_src IS NULL THEN
    RAISE EXCEPTION '0139: public.ottoq_determinism_pair not found';
  END IF;
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0139: ottoq_determinism_pair moved under this migration (pin %, found %)',
      c_pin, md5(v_src);
  END IF;

  v_anchor := $a$AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks');$a$;
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0139: verdict anchor matched % times, expected 1', v_n; END IF;

  -- jsonb equality, not IS NOT DISTINCT FROM: a missing image must fail the pair, not pass it.
  v_repl := $r$AND (v_arms[1]->>'ticks') = (v_arms[2]->>'ticks')
         AND (v_arms[1]->'endst')  = (v_arms[2]->'endst');$r$;
  v_new := replace(v_src, v_anchor, v_repl);

  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 4. Post-conditions. Comments are stripped first: a migration that explains itself is
--    exactly the one whose prose contains the strings its own checks look for (0136, 0137).
-- ---------------------------------------------------------------------------------------
DO $chk$
DECLARE v_fp text; v_pair text;
BEGIN
  SELECT regexp_replace(pg_get_functiondef(p.oid), '/\*.*?\*/', '', 'g') INTO v_fp
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_boot_state_fingerprint';
  SELECT regexp_replace(pg_get_functiondef(p.oid), '/\*.*?\*/', '', 'g') INTO v_pair
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';

  IF v_fp NOT LIKE '%ottoq_scrub_ids(t.why)%' THEN
    RAISE EXCEPTION '0139: fingerprint does not scrub why';
  END IF;
  IF v_fp NOT LIKE '%{appointment,correlation_id}%' THEN
    RAISE EXCEPTION '0139: fingerprint does not strip the appointment correlation id';
  END IF;
  IF v_fp NOT LIKE '%- ''visit_id'' - ''booked_at''%' THEN
    RAISE EXCEPTION '0139: fingerprint does not strip visit_id from bookings';
  END IF;
  IF v_pair NOT LIKE '%(v_arms[1]->''endst'')  = (v_arms[2]->''endst'')%' THEN
    RAISE EXCEPTION '0139: the pair verdict still ignores the end state';
  END IF;

  -- The four sections that were never in question must all still be hashed.
  IF v_fp NOT LIKE '%visit_needs%' OR v_fp NOT LIKE '%bookings%'
     OR v_fp NOT LIKE '%legs%' OR v_fp NOT LIKE '%dispatches%' OR v_fp NOT LIKE '%chargers%' THEN
    RAISE EXCEPTION '0139: a fingerprint section was lost';
  END IF;
  -- The foreign-row leakage check must survive the edit.
  IF v_fp NOT LIKE '%WHERE fgn AND st IN%' THEN
    RAISE EXCEPTION '0139: the foreign-row leakage check was lost';
  END IF;
END
$chk$;

COMMIT;
