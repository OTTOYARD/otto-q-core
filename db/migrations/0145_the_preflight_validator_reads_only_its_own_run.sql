-- 0145: the pre-flight validator reads only its own run
--
-- The first ENGINE defect of this round. Everything in 0139-0144 was instrument; this one
-- changes what the engine does.
--
-- ============================================================================
-- WHAT IT IS
-- ============================================================================
--
-- ottoq.ottoq_validate_assignment is the pre-flight check that ottoq_emit_vehicle_command
-- runs before every vehicle command. Its last branch asks whether the target stall is already
-- spoken for on the forward calendar:
--
--     SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
--      WHERE b.stall_id = p_stall_id AND b.state IN ('held','active','done','interrupted')
--        AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
--      LIMIT 1;
--
-- There is no sim_run_id predicate. It reads EVERY run's bookings. Measured: of every
-- function in public, ottoq and twin that touches ottoq_stall_bookings, this is the ONLY one
-- whose body never mentions sim_run_id at all. It is the unique run-scope hole in the
-- database and it sits in the causal path of every proceed_to_stall.
--
-- ============================================================================
-- WHAT IT DID -- the 424242/12t canon step, finally explained
-- ============================================================================
--
-- db/checks/0063 section 12 recorded a state transition firing in one run and not the other
-- from identical recorded state one tick earlier, and could not account for it. This is it.
--
-- Both arms emitted a BYTE-IDENTICAL command at sim 07:30 (tick 11): vehicle
-- a1111111-0001-0001-0001-000000000006, proceed_to_stall, stall e0f2bf3a-04ca-48c7-81db-56a1217355b7,
-- payload {"new_state":"staged_awaiting_service"}. The payload carries the transition.
--
--   OLD run 55b69698 (armed 08-31 23:41): status executed, reason_code NULL, executed 08:00
--   NEW run d2923358 (armed 09-01 02:28): status refused, target_occupied, confirmed_by
--                                          otto_q_preflight,
--                                          "calendar booking held by b9ef130e-..."
--
-- OLD's command reached twin.ottoq_sim_confirm_commands, which applied payload.new_state and
-- moved the vehicle arrived_at_gate -> staged_awaiting_service, and the next tick promoted it
-- ready. NEW's was refused at emission and never reached the twin, so the vehicle stayed at
-- the gate and took a perimeter_hold instead. Every other difference between those two runs --
-- the stall rotation, the 240-minute hold, the displaced vehicle, the extra booking -- is
-- downstream of this single refusal.
--
-- The conflicting bookings are 100% FOREIGN. Twelve bookings currently cover that stall at
-- 07:30 and NOT ONE belongs to either arm; they come from runs armed 00:46, 00:58, 03:08,
-- 03:34, 09:40 and 10:06. At OLD's arming time none of them existed yet. That is the whole
-- mechanism: the calendar the validator consults keeps filling up with other runs' rows.
--
-- ============================================================================
-- WHY IT IS WORSE THAN A DETERMINISM BUG
-- ============================================================================
--
-- PROGRESSIVE. The conflict set grows monotonically as runs accumulate. Reproducibility does
-- not merely break, it decays -- and silently, because each refusal looks like an ordinary
-- occupancy check doing its job. Two of the twelve conflicts above came from the 09:40 and
-- 10:06 pairs of THIS MORNING's re-certification, so the matrix certified at 11:20 was
-- already standing on a fuller calendar than the one it was certified against.
--
-- NOT CONFINED TO THE TWIN. public.ottoq_stall_bookings holds simulation and production rows
-- together, separated only by sim_run_id -- that co-existence is deliberate (CLAUDE.md 2.8).
-- An unscoped read therefore lets simulation bookings refuse PRODUCTION commands on stalls
-- that are physically free, and lets production bookings refuse simulation ones. That is a
-- correctness fault, not just a reproducibility one.
--
-- IT HID FOR NINE TICKS. The same unscoped read also picks which conflicting vehicle to name.
-- reason_detail was already diverging between the arms from tick 2 onward -- 9, 8, 6, 9, 20,
-- 13, 13, 3, 2, 7 rows per tick -- with zero behavioural effect, because only the text
-- differed. It became visible only when the read finally flipped a status instead of a string.
--
-- ============================================================================
-- THE FIX
-- ============================================================================
--
-- Run-scope the calendar read with the zero-uuid idiom established in 0020/0124, so a
-- simulation sees only its own bookings and production (NULL run) sees only production's.
-- The validator gains p_sim_run_id; ottoq_emit_vehicle_command, its ONLY caller, passes the
-- p_run it already has.
--
-- The old 4-argument arity is DROPPED rather than left beside the new one. 0144 learned this:
-- a defaulted parameter creates a second function and PL/pgSQL keeps resolving existing calls
-- to the old body, so the fix looks applied and does nothing.
--
-- Second defect in the same statement, fixed here too: the LIMIT 1 had no ORDER BY, so which
-- conflicting vehicle got named was plan-dependent. That is the 0062/0063 ordering discipline
-- -- content keys first, unique id last -- and it is what made reason_detail nondeterministic
-- for nine ticks before anything else moved.

BEGIN;

-- ---------------------------------------------------------------------------------------
-- 0. Self-classification (0142 convention). Engine behaviour changes: forces re-certification.
-- ---------------------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, forces_recert, note) VALUES
  ('the_preflight_validator_reads_only_its_own_run', true,
   '0145: run-scopes the forward-calendar check in ottoq_validate_assignment and gives its '
   'LIMIT 1 a total order. Changes which commands are refused -- engine behaviour -- so it '
   'forces re-certification.')
ON CONFLICT (name) DO UPDATE
  SET forces_recert = EXCLUDED.forces_recert, note = EXCLUDED.note, classified_at = now();

-- ---------------------------------------------------------------------------------------
-- 1. Capture the defect on the historical case BEFORE changing anything, so the migration
--    carries its own before/after rather than asking the reader to trust the prose.
-- ---------------------------------------------------------------------------------------
CREATE TEMP TABLE pg_temp_0145_before AS
SELECT ottoq.ottoq_validate_assignment(
         'a1111111-0001-0001-0001-000000000006'::uuid,
         'e0f2bf3a-04ca-48c7-81db-56a1217355b7'::uuid,
         'proceed_to_stall',
         '2026-09-01 07:30:00+00'::timestamptz) AS verdict;

DO $chk$
DECLARE v jsonb;
BEGIN
  SELECT verdict INTO v FROM pg_temp_0145_before;
  IF COALESCE((v->>'ok')::boolean, true) THEN
    RAISE EXCEPTION
      '0145: the historical case no longer refuses (%). The defect this migration fixes could '
      'not be reproduced, so its proof would be vacuous -- investigate before proceeding.', v;
  END IF;
  RAISE NOTICE '0145: before = %', v;
END
$chk$;

-- ---------------------------------------------------------------------------------------
-- 2. The validator takes a run and reads only that run's calendar.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_repl text; v_n int;
  c_pin CONSTANT text := '2592d5f1fed3f992d026322e1d88b8de';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_validate_assignment'
     AND pg_get_function_identity_arguments(p.oid)
         = 'p_vehicle_id uuid, p_stall_id uuid, p_command_type text, p_clock timestamp with time zone';
  IF v_src IS NULL THEN RAISE EXCEPTION '0145: the 4-arg validator was not found'; END IF;
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0145: validator moved under this migration (pin %, found %)', c_pin, md5(v_src);
  END IF;

  v_anchor := 'ottoq.ottoq_validate_assignment(p_vehicle_id uuid, p_stall_id uuid, p_command_type text, p_clock timestamp with time zone)';
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0145: signature anchor matched % times, expected 1', v_n; END IF;
  v_repl := 'ottoq.ottoq_validate_assignment(p_vehicle_id uuid, p_stall_id uuid, p_command_type text, p_clock timestamp with time zone, p_sim_run_id uuid DEFAULT NULL)';
  v_new := replace(v_src, v_anchor, v_repl);

  v_anchor := '  SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
   WHERE b.stall_id = p_stall_id AND b.state IN (''held'',''active'',''done'',''interrupted'')
     AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
   LIMIT 1;';
  v_n := (length(v_new) - length(replace(v_new, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0145: calendar anchor matched % times, expected 1', v_n; END IF;

  -- 0020/0124 zero-uuid idiom: a run sees its own bookings, production (NULL) sees production's.
  -- ORDER BY made total (0062/0063): content key first, unique booking_id last, so WHICH
  -- blocker gets named is no longer plan-dependent.
  v_repl := '  SELECT b.vehicle_id INTO v_cal_conflict FROM ottoq_stall_bookings b
   WHERE b.stall_id = p_stall_id AND b.state IN (''held'',''active'',''done'',''interrupted'')
     AND b.vehicle_id <> p_vehicle_id AND b.during @> p_clock
     AND COALESCE(b.sim_run_id,''00000000-0000-0000-0000-000000000000''::uuid)
       = COALESCE(p_sim_run_id,''00000000-0000-0000-0000-000000000000''::uuid)
   ORDER BY lower(b.during), b.vehicle_id, b.booking_id
   LIMIT 1;';
  v_new := replace(v_new, v_anchor, v_repl);

  DROP FUNCTION ottoq.ottoq_validate_assignment(uuid, uuid, text, timestamptz);
  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 3. Its only caller hands it the run it already holds.
-- ---------------------------------------------------------------------------------------
DO $do$
DECLARE
  v_src text; v_new text; v_anchor text; v_n int;
  c_pin CONSTANT text := '7f0ffdbd4950d1232c36071d38544689';
BEGIN
  SELECT pg_get_functiondef(p.oid) INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_emit_vehicle_command';
  IF md5(v_src) <> c_pin THEN
    RAISE EXCEPTION '0145: emit_vehicle_command moved (pin %, found %)', c_pin, md5(v_src);
  END IF;

  v_anchor := 'p_vehicle, NULLIF(p_payload->>''stall_id'','''')::uuid, p_type, p_clock);';
  v_n := (length(v_src) - length(replace(v_src, v_anchor, ''))) / length(v_anchor);
  IF v_n <> 1 THEN RAISE EXCEPTION '0145: emit call-site anchor matched % times, expected 1', v_n; END IF;
  v_new := replace(v_src, v_anchor,
             'p_vehicle, NULLIF(p_payload->>''stall_id'','''')::uuid, p_type, p_clock, p_run);');
  EXECUTE v_new;
END
$do$;

-- ---------------------------------------------------------------------------------------
-- 4. Post-conditions, including the before/after the defect itself.
-- ---------------------------------------------------------------------------------------
DO $chk$
DECLARE
  v_src text; v_args text; v_arities int;
  v_before jsonb; v_old jsonb; v_new jsonb; v_prod jsonb;
BEGIN
  SELECT pg_get_function_identity_arguments(p.oid),
         regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/','','g')
    INTO v_args, v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_validate_assignment';

  SELECT count(*) INTO v_arities FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_validate_assignment';
  IF v_arities <> 1 THEN
    RAISE EXCEPTION '0145: % arities of the validator survive -- old calls may still be unscoped', v_arities;
  END IF;
  IF v_args <> 'p_vehicle_id uuid, p_stall_id uuid, p_command_type text, p_clock timestamp with time zone, p_sim_run_id uuid' THEN
    RAISE EXCEPTION '0145: unexpected validator signature: %', v_args;
  END IF;
  IF v_src NOT LIKE '%COALESCE(b.sim_run_id%' THEN
    RAISE EXCEPTION '0145: the calendar read is still not run-scoped';
  END IF;
  IF v_src NOT LIKE '%ORDER BY lower(b.during), b.vehicle_id, b.booking_id%' THEN
    RAISE EXCEPTION '0145: the calendar LIMIT 1 still has no total order';
  END IF;
  -- The other refusal branches must survive untouched.
  IF v_src NOT LIKE '%target_unknown%' OR v_src NOT LIKE '%vehicle_unresponsive%'
     OR v_src NOT LIKE '%target_occupied%' THEN
    RAISE EXCEPTION '0145: the validator lost a refusal branch';
  END IF;

  SELECT regexp_replace(pg_get_functiondef(p.oid),'/\*.*?\*/','','g') INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='ottoq' AND p.proname='ottoq_emit_vehicle_command';
  IF v_src NOT LIKE '%p_type, p_clock, p_run)%' THEN
    RAISE EXCEPTION '0145: emit_vehicle_command does not pass its run to the validator';
  END IF;

  -- THE PROOF. Same vehicle, same stall, same clock as the historical divergence.
  SELECT verdict INTO v_before FROM pg_temp_0145_before;
  v_old  := ottoq.ottoq_validate_assignment('a1111111-0001-0001-0001-000000000006'::uuid,
              'e0f2bf3a-04ca-48c7-81db-56a1217355b7'::uuid,'proceed_to_stall',
              '2026-09-01 07:30:00+00'::timestamptz,'55b69698-4d5c-4ce9-b7da-b3028869fd67'::uuid);
  v_new  := ottoq.ottoq_validate_assignment('a1111111-0001-0001-0001-000000000006'::uuid,
              'e0f2bf3a-04ca-48c7-81db-56a1217355b7'::uuid,'proceed_to_stall',
              '2026-09-01 07:30:00+00'::timestamptz,'d2923358-cbc3-4430-b359-27b69d2caa89'::uuid);
  v_prod := ottoq.ottoq_validate_assignment('a1111111-0001-0001-0001-000000000006'::uuid,
              'e0f2bf3a-04ca-48c7-81db-56a1217355b7'::uuid,'proceed_to_stall',
              '2026-09-01 07:30:00+00'::timestamptz, NULL);

  IF NOT COALESCE((v_old->>'ok')::boolean,false) OR NOT COALESCE((v_new->>'ok')::boolean,false) THEN
    RAISE EXCEPTION
      '0145: run-scoping did not clear the foreign conflict (old=%, new=%). Every blocker on '
      'that stall at that clock belongs to another run, so both arms must now accept.',
      v_old, v_new;
  END IF;
  IF NOT COALESCE((v_prod->>'ok')::boolean,false) THEN
    RAISE EXCEPTION '0145: production (NULL run) sees a simulation booking as a blocker: %', v_prod;
  END IF;

  RAISE NOTICE '0145: before % -> old-arm % / new-arm % / production %',
    v_before, v_old, v_new, v_prod;
END
$chk$;

COMMIT;
