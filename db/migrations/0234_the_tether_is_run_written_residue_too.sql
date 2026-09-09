-- migration-version: PENDING
-- migration-name:    the_tether_is_run_written_residue_too
--
-- G37 / db/checks/0153. The second attempt at a paired A/B died on
--
--   ERROR: duplicate key value violates unique constraint
--          "idx_stalls_one_vehicle_per_stall"
--   CONTEXT: sync_stall_occupancy() <- ottoq_fifo_tick line 24
--
-- because two triggers on public.vehicles mean different things by "tethered":
-- ottoq_arm_interlock_guard compares robotic_tether_until to a clock and so
-- PERMITS moving a vehicle whose tether expired, while sync_stall_occupancy
-- tests only "IS NOT NULL" and so REFUSES to vacate that vehicle's old stall.
-- The vehicle ends up recorded in two stalls and the unique index -- correctly --
-- kills the run.
--
-- 0153 §5 concluded the fix is not in either trigger: making
-- sync_stall_occupancy expiry-aware needs a clock it deliberately cannot afford
-- and could not choose correctly anyway (G34). The fix is upstream -- clear the
-- tether when it ends rather than letting it expire -- and 0153 filed that as a
-- schema-shaped, forces_recert TRUE piece of work.
--
-- THIS MIGRATION IS THE PART OF THAT WHICH IS NEITHER SCHEMA-SHAPED NOR IN THE
-- TICK PATH, and it turns out to be most of the practical benefit.
--
-- ---------------------------------------------------------------------------
-- THE OBSERVATION
-- ---------------------------------------------------------------------------
-- ottoq_benchmark_reset already has a residue-stripping clause, added by 0053
-- and carrying its own statement of intent:
--
--   config=((COALESCE(config,'{}'::jsonb)-'svc_step')-'service_manifest')
--     -'service_manifest_meta' - 'battery_soh_pct' - 'consumption_scalar'
--     - 'charge_curve_scalar' - 'soil_rate' - 'pm_interval_km'
--     - 'calib_interval_h' - 'service_speed_scalar' - 'wash_cadence_cycles'
--     - 'cycles_since_wash' - 'condition_drawn_run' - 'charge_plan'
--     - 'deploy_gate' - 'arm_fault_at' - 'arm_fault_reason'
--     - 'arm_fault_awaiting_disposition'
--     -- 0053: run-written residue must not leak into the next cert arm
--
-- Sixteen keys, three of them arm residue. So arm state was explicitly in
-- scope. But the tether is not a config key -- it is four COLUMNS on vehicles --
-- and the reset does not mention them at all:
--
--   robotic_tether occurrences in ottoq_benchmark_reset: 0 (measured)
--
-- The tether is run-written residue that the residue-stripper does not strip.
-- That is the whole bug, and it is a one-word category error: the author
-- enumerated the residue they could see inside `config` and the four columns
-- sitting beside it were invisible to that enumeration.
--
-- ---------------------------------------------------------------------------
-- WHY CLEARING IT IN THIS EXACT STATEMENT IS CORRECT AND NOT A HACK
-- ---------------------------------------------------------------------------
-- ottoq_arm_interlock_guard opens with:
--
--   -- Not tethered after this statement -- including the case where this very
--   -- statement is what lets go -- so the move is somebody's business, not ours.
--   IF NEW.robotic_tether_until IS NULL THEN RETURN NEW; END IF;
--
-- The guard was BUILT to allow precisely this: a statement that both moves the
-- vehicle and releases the tether. The reset simply never took it up. After
-- this migration:
--
--   ottoq_arm_interlock_guard   NEW.robotic_tether_until IS NULL -> RETURN NEW,
--                               no interlock exception, by the guard's own
--                               documented contract.
--   sync_stall_occupancy        NOT (NEW.robotic_tether_until IS NOT NULL AND ...)
--                               -> NOT(false) -> true -> vacates the old stall
--                               properly.
--
-- Both triggers agree, and they agree without either of them acquiring a clock.
-- That is the shape 0153 §5 asked for, applied at the one site where it costs
-- nothing.
--
-- ---------------------------------------------------------------------------
-- WHAT THIS DOES NOT DO
-- ---------------------------------------------------------------------------
-- It does not close G37. A tether that expires DURING a run, mid-tick, is still
-- a flag with no terminal write and the two triggers still disagree about it
-- then. This clears the residue BETWEEN arms, which is where every observed
-- occurrence has come from, and it removes the manual
-- twin.ottoq_arm_emergency_release step that has had to precede every arm today.
-- The in-run case needs the demate-completion path to clear the tether itself,
-- which is in the tick path and forces_recert TRUE. G37 stays open with that
-- scope.
--
-- It also does not touch ottoq_sim_release_depot or the flagship. Only the
-- benchmark lane's reset.
--
-- forces_recert: FALSE, on the same grounds as 0233 and re-asserted in P2:
-- ottoq_benchmark_reset is called only by the six cert-arm procedures, none in
-- the flagship tick path, and it carries its own guard --
-- RAISE EXCEPTION 'ottoq_benchmark_reset refuses non-benchmark depot %' --
-- so it physically cannot run against nashville-flagship. The floor is checked
-- after applying anyway.

-- (no explicit BEGIN/COMMIT: apply_migration supplies the transaction.)

-- ---------------------------------------------------------------------------
-- P-  NEVER APPLY WHILE A CERTIFICATION PAIR IS IN FLIGHT.
-- ---------------------------------------------------------------------------
DO $P$
DECLARE n int;
BEGIN
  SELECT count(*) INTO n FROM pg_stat_activity
   WHERE datname = current_database() AND pid <> pg_backend_pid()
     AND state = 'active' AND query LIKE '%ottoq_determinism_pair%';
  IF n > 0 THEN RAISE EXCEPTION 'P- REFUSED: % certification pair(s) in flight', n; END IF;
END $P$;

-- ---------------------------------------------------------------------------
-- P1  The body is 0233's output, byte-for-byte.
-- ---------------------------------------------------------------------------
DO $P1$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure));
  IF h <> 'ae412097c7b1b7cca8d110b9b91733a8' THEN
    RAISE EXCEPTION 'P1 REFUSED: benchmark_reset md5 is %, pinned ae412097c7b1b7cca8d110b9b91733a8 (0233 output)', h;
  END IF;
END $P1$;

-- ---------------------------------------------------------------------------
-- P2  Still benchmark-lane only. Same justification as 0233's forces_recert.
-- ---------------------------------------------------------------------------
DO $P2$
DECLARE bad text;
BEGIN
  SELECT string_agg(n.nspname||'.'||p.proname, ', ') INTO bad
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE p.prosrc ~* 'ottoq_benchmark_reset'
     AND p.proname <> 'ottoq_benchmark_reset'
     AND p.proname NOT IN ('ottoq_cert_arm','ottoq_cert_arm_start','ottoq_cert_arm_wave',
                           'ottoq_cert_arm_finish','ottoq_fr1_cert_arm','ottoq_safety_cert_arm');
  IF bad IS NOT NULL THEN
    RAISE EXCEPTION 'P2 REFUSED: unexpected caller(s): %', bad;
  END IF;
END $P2$;

-- ---------------------------------------------------------------------------
-- P3  The tether columns exist and the reset does not already touch them.
--     A second apply must be a no-op refusal, not a double edit.
-- ---------------------------------------------------------------------------
DO $P3$
DECLARE n int; d text;
BEGIN
  SELECT count(*) INTO n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='vehicles'
     AND column_name IN ('robotic_tether_until','robotic_tether_stall_id',
                         'robotic_tether_direction','robotic_tether_phase');
  IF n <> 4 THEN RAISE EXCEPTION 'P3 REFUSED: expected 4 tether columns on vehicles, found %', n; END IF;

  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);
  IF d ~* 'robotic_tether' THEN
    RAISE EXCEPTION 'P3 REFUSED: ottoq_benchmark_reset already mentions robotic_tether; not a fresh apply';
  END IF;
END $P3$;

-- ---------------------------------------------------------------------------
-- THE CHANGE. One anchored substitution, uniqueness asserted before use.
-- ---------------------------------------------------------------------------
DO $CHG$
DECLARE d text; a text; rep text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);

  a := E'current_stall_id=NULL, last_state_change=now(),';
  n := (length(d) - length(replace(d, a, ''))) / length(a);
  IF n <> 1 THEN RAISE EXCEPTION 'CHG REFUSED: anchor occurs % times, expected 1', n; END IF;

  rep := E'current_stall_id=NULL, last_state_change=now(),\n'
      || E'         -- 0234 / G37: the tether is run-written residue too. 0053 stripped the\n'
      || E'         -- arm residue it could see inside `config` and missed the four columns\n'
      || E'         -- sitting beside it. Cleared in the SAME statement that moves the\n'
      || E'         -- vehicle, which is exactly the case ottoq_arm_interlock_guard is\n'
      || E'         -- written to permit: "including the case where this very statement is\n'
      || E'         -- what lets go". With these NULL, sync_stall_occupancy also vacates the\n'
      || E'         -- old stall instead of leaking it -- so both triggers agree, and neither\n'
      || E'         -- needs a clock.\n'
      || E'         robotic_tether_until=NULL, robotic_tether_stall_id=NULL,\n'
      || E'         robotic_tether_direction=NULL, robotic_tether_phase=NULL,';

  EXECUTE replace(d, a, rep);
END $CHG$;

-- ---------------------------------------------------------------------------
-- A1  All four columns are cleared, each exactly once.
-- ---------------------------------------------------------------------------
DO $A1$
DECLARE d text; c text; n int;
BEGIN
  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);
  FOREACH c IN ARRAY ARRAY['robotic_tether_until=NULL','robotic_tether_stall_id=NULL',
                           'robotic_tether_direction=NULL','robotic_tether_phase=NULL'] LOOP
    n := (length(d) - length(replace(d, c, ''))) / length(c);
    IF n <> 1 THEN RAISE EXCEPTION 'A1 FAILED: "%" appears % times, expected 1', c, n; END IF;
  END LOOP;
END $A1$;

-- ---------------------------------------------------------------------------
-- A2  0233's work is still present -- this migration must not have re-emitted
--     an older body over the top of it.
-- ---------------------------------------------------------------------------
DO $A2$
DECLARE d text;
BEGIN
  d := pg_get_functiondef('public.ottoq_benchmark_reset(uuid,numeric,numeric)'::regprocedure);
  IF position('GREATEST(o.started_at' in d) = 0
     OR position('stopped_reason=''benchmark_reset''' in d) = 0
     OR position('UPDATE ocpp_sessions SET status=''completed''' in d) > 0 THEN
    RAISE EXCEPTION 'A2 FAILED: 0233''s session fix is not intact after this rewrite';
  END IF;
END $A2$;

-- ---------------------------------------------------------------------------
-- A3  The certified path is untouched.
-- ---------------------------------------------------------------------------
DO $A3$
DECLARE h text;
BEGIN
  h := md5(pg_get_functiondef('public.ottoq_decide_tick(uuid)'::regprocedure));
  IF h <> 'ae98f71b879a0a11bdf366d21ff5b4eb' THEN
    RAISE EXCEPTION 'A3 FAILED: ottoq_decide_tick md5 is %, expected ae98f71b879a0a11bdf366d21ff5b4eb', h;
  END IF;
END $A3$;

-- ---------------------------------------------------------------------------
-- A4  The trigger contract this relies on is still what it was read to be.
--     If sync_stall_occupancy ever stops keying on IS NOT NULL, or the guard
--     stops early-returning on IS NULL, the reasoning above expires and someone
--     should be told rather than left with a comment that used to be true.
-- ---------------------------------------------------------------------------
DO $A4$
DECLARE g text; s text;
BEGIN
  SELECT prosrc INTO g FROM pg_proc WHERE proname='ottoq_arm_interlock_guard';
  SELECT prosrc INTO s FROM pg_proc WHERE proname='sync_stall_occupancy';
  IF g IS NULL OR s IS NULL THEN RAISE EXCEPTION 'A4 FAILED: a trigger function is missing'; END IF;
  IF g !~* 'robotic_tether_until IS NULL' THEN
    RAISE EXCEPTION 'A4 FAILED: the interlock guard no longer early-returns on a NULL tether; '
                    '0234 depends on that contract';
  END IF;
  IF s !~* 'robotic_tether_until IS NOT NULL' THEN
    RAISE EXCEPTION 'A4 FAILED: sync_stall_occupancy no longer keys on IS NOT NULL; re-derive 0234';
  END IF;
END $A4$;

-- ---------------------------------------------------------------------------
-- LINEAGE.
-- ---------------------------------------------------------------------------
INSERT INTO public.ottoq_cert_lineage (name, classified_at, forces_recert, note)
VALUES (
  'the_tether_is_run_written_residue_too',
  now(),
  false,
  'G37 / db/checks/0153. ottoq_arm_interlock_guard treats a tether as live by '
  'comparing robotic_tether_until to a clock; sync_stall_occupancy treats it as '
  'live if the column is merely non-NULL. For an expired-but-non-NULL tether the '
  'guard permits the move and the sync trigger refuses to vacate the old stall, '
  'so the vehicle occupies two stalls and idx_stalls_one_vehicle_per_stall kills '
  'the run -- which is how the second paired A/B attempt died. ottoq_benchmark_'
  'reset already strips sixteen run-written residue keys from vehicles.config '
  '(0053), three of them arm residue, but never touched the four robotic_tether_* '
  'COLUMNS beside it. This adds them to the same UPDATE, which is the case the '
  'interlock guard is explicitly written to permit ("including the case where this '
  'very statement is what lets go"), so both triggers then agree with no clock in '
  'either. Does NOT close G37: a tether expiring mid-run is still a flag with no '
  'terminal write, and that fix is in the tick path and forces_recert TRUE. '
  'forces_recert FALSE here: benchmark-lane only, asserted in P2, and the '
  'function refuses any non-benchmark depot by its own guard.'
);
