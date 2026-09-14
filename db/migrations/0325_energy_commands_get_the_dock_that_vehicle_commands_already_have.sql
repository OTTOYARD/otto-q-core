-- migration-version: PENDING
-- migration-name:    0325_energy_commands_get_the_dock_that_vehicle_commands_already_have
-- ============================================================================
-- 0325 — ENERGY COMMANDS GET THE DOCK THAT VEHICLE COMMANDS ALREADY HAVE,
--        AND THE DOCK REFUSES ANYTHING THAT IS NOT SCHEDULE-SHAPED.
-- ============================================================================
-- WHY. db/checks/0243 measured the hub's three sides. Inbound is real: twin and
-- production write the same tables, separated by data_source. The orchestration
-- floor is real. Outbound is two different problems, and this file closes the
-- one that is an actual hole:
--
--   ottoq_vehicle_commands  has delivered_at, delivered_to, confirmed_at,
--                           confirmed_by, and public.ottoq_fleet_claim_commands
--                           -- a real claim-and-lease. Built, gated correctly,
--                           never used (delivered_at set on 0 of 822,887 rows).
--                           A socket that is unplugged. NOT this file's concern.
--
--   ottoq_energy_commands   has NONE of those columns and no claim function
--                           anywhere in the database. 36,659 rows and no audited
--                           way for an external consumer to take delivery of an
--                           energy instruction or acknowledge one. A missing
--                           socket. THIS FILE.
--
-- Energy is a named inbound feed. A hub that accepts energy data and cannot ship
-- energy instructions back out through any audited path is not a hub on that
-- axis; it is a sink.
--
-- ── WHY THIS DOES NOT DISTURB THE CERTIFICATION ─────────────────────────────
-- h_nrg does NOT hash the row. It hashes an explicit column list, read from the
-- live ottoq_determinism_pair:
--
--     tick_seq | command_type | source | setpoint_kw | horizon_min
--              | issued_at | reason
--
-- None of the four columns added here appears in it, and h_cmd sets the same
-- precedent on the vehicle side -- it hashes issued_at|vehicle_id|command_type|
-- stall_id|status|reason_code and has never hashed delivered_at. Delivery is an
-- act of an EXTERNAL CONSUMER, and a certification has none, so these columns
-- stay NULL in both arms by construction. A2 asserts the column list, so if
-- someone later widens h_nrg to hash whole rows this migration's own assertion
-- is what fails.
--
-- The claim path is additionally gated data_source='production', mirroring
-- 0271's rule on the vehicle side, so a twin command is never delivered and a
-- cert (entirely twin) cannot be touched by this machinery at all.
--
-- ── THE PUBLICATION BOUNDARY, ENCODED RATHER THAN ASSERTED ──────────────────
-- CLAUDE.md 2.5: "production interfaces publish forward demand schedules
-- (smart-charging-profile shaped) to site controllers and vendor EMS. Real-time
-- setpoint commands to physical inverters are never issued by OTTO-Q directly."
--
-- The dock enforces it: NOTHING IS DELIVERED WITHOUT A POSITIVE horizon_min. A
-- setpoint with no horizon is a real-time device command, and it cannot leave
-- the building through this path even if some future writer creates one.
--
-- Measured before writing the guard, so it is neither vacuous nor a new
-- restriction -- every energy command already carries a horizon:
--
--     command_type        n        with horizon   min    max
--     charge_cap_kw       18,426        18,426     15    600
--     bess_setpoint_kw    18,425        18,425     35     35
--
-- Note which command type makes the guard worth having: bess_setpoint_kw is
-- named "setpoint" and is in fact a 35-minute planning setpoint. The guard is
-- what keeps that true.
--
-- ── SCOPE ──────────────────────────────────────────────────────────────────
-- Additive only. No function is replaced, so there is no md5 guard and no
-- pre-snapshot to take -- nothing existing is at risk. No DROP. The registry
-- needs no new entry: ottoq_run_scope_registry classifies a table by its
-- run-scoping column (ottoq_energy_commands -> sim_run_id, class 'engine'), and
-- none of these four columns is a run scope.
--
-- What this file does NOT do, deliberately, one concern per file:
--   * it does not plug a consumer into either dock (no traffic yet);
--   * it does not add retry, TTL or dead-letter (G8's remaining half);
--   * it does not touch the vehicle dock at all.
-- ============================================================================

-- P-. NOTHING IN FLIGHT ------------------------------------------------------
-- pg_stat_activity is the only authority: both arms of a pair run in ONE
-- transaction so ottoq_sim_runs cannot see them, and cron.job_run_details
-- reports an in-flight pair as succeeded/'SET'/~1s.
DO $inflight$
DECLARE v_jobs text; v_pairs int; v_runs int;
BEGIN
  SELECT string_agg(jobname, ', ' ORDER BY jobname) INTO v_jobs
    FROM cron.job WHERE jobname ~ '^r[0-9]+_';
  IF v_jobs IS NOT NULL THEN
    RAISE EXCEPTION '0325 P-: certification jobs are still scheduled (%) -- migrations wait for '
                    'the round, and unscheduling them is the deliberate act that says it is over',
                    v_jobs;
  END IF;

  SELECT count(*) INTO v_pairs FROM pg_stat_activity
   WHERE query ILIKE '%ottoq_determinism_pair%' AND state = 'active'
     AND pid <> pg_backend_pid();
  IF v_pairs > 0 THEN
    RAISE EXCEPTION '0325 P-: a determinism pair is running right now';
  END IF;

  SELECT count(*) INTO v_runs FROM public.ottoq_sim_runs WHERE status = 'running';
  IF v_runs > 0 THEN
    RAISE EXCEPTION '0325 P-: % sim run(s) are in flight', v_runs;
  END IF;

  RAISE NOTICE '0325 P-: no certification scheduled, no pair running, no sim run in flight';
END $inflight$;

-- P0. THE ATOM'S COLUMN LIST IS THE ONE THIS WAS WRITTEN AGAINST -------------
-- If h_nrg has been widened since this was drafted, the reasoning above is
-- void and this file must not apply.
DO $p0$
DECLARE v_src text;
BEGIN
  SELECT p.prosrc INTO v_src
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
   WHERE n.nspname = 'public' AND p.proname = 'ottoq_determinism_pair';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0325 P0: public.ottoq_determinism_pair not found';
  END IF;
  IF v_src !~ 'h_nrg' THEN
    RAISE EXCEPTION '0325 P0: ottoq_determinism_pair no longer mentions h_nrg';
  END IF;
  IF v_src ~* 'delivered_at|delivered_to' THEN
    RAISE EXCEPTION '0325 P0: the pair now hashes a delivery column; the '
                    'no-disturbance argument in this header is void';
  END IF;
  RAISE NOTICE '0325 P0: h_nrg present and hashes no delivery column';
END $p0$;

-- 1. THE COLUMNS -------------------------------------------------------------
ALTER TABLE public.ottoq_energy_commands
  ADD COLUMN IF NOT EXISTS delivered_at  timestamptz,
  ADD COLUMN IF NOT EXISTS delivered_to  text,
  ADD COLUMN IF NOT EXISTS confirmed_at  timestamptz,
  ADD COLUMN IF NOT EXISTS confirmed_by  text;

COMMENT ON COLUMN public.ottoq_energy_commands.delivered_at IS
  '0325: when an external consumer claimed this command. NULL means undelivered. '
  'Deliberately outside h_nrg -- delivery is an external act and a certification '
  'has no external consumer.';
COMMENT ON COLUMN public.ottoq_energy_commands.delivered_to IS
  '0325: the actor that claimed it. Mirrors ottoq_vehicle_commands.delivered_to.';

-- 2. THE DOCK ----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_energy_claim_commands(
  p_depot_id uuid    DEFAULT NULL,
  p_limit    integer DEFAULT 200,
  p_actor    text    DEFAULT NULL
) RETURNS TABLE (
  command_id   uuid,
  depot_id     uuid,
  command_type text,
  setpoint_kw  numeric,
  horizon_min  numeric,
  issued_at    timestamptz,
  reason       text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE v_actor text := COALESCE(NULLIF(p_actor,''), current_user);
BEGIN
  RETURN QUERY
  WITH picked AS (
    SELECT c.command_id AS cid
      FROM public.ottoq_energy_commands c
     WHERE c.status = 'issued'
       -- 0271's rule, mirrored: a twin command is never delivered.
       AND c.data_source = 'production'
       AND c.delivered_at IS NULL
       -- CLAUDE.md 2.5: forward schedules only. A setpoint with no horizon is a
       -- real-time device command and never leaves through this dock.
       AND c.horizon_min IS NOT NULL
       AND c.horizon_min > 0
       AND (p_depot_id IS NULL OR c.depot_id = p_depot_id)
     ORDER BY c.issued_at DESC
     LIMIT GREATEST(1, LEAST(p_limit, 1000))
    FOR UPDATE OF c SKIP LOCKED
  ), leased AS (
    UPDATE public.ottoq_energy_commands u
       SET delivered_at = COALESCE(u.delivered_at, now()),
           delivered_to = COALESCE(u.delivered_to, v_actor)
      FROM picked
     WHERE u.command_id = picked.cid
     RETURNING u.command_id, u.depot_id, u.command_type,
               u.setpoint_kw, u.horizon_min, u.issued_at, u.reason::text
  )
  SELECT * FROM leased;
END $fn$;

COMMENT ON FUNCTION public.ottoq_energy_claim_commands(uuid,integer,text) IS
  '0325: the energy dock. Claim-and-lease for external site controllers / vendor '
  'EMS, mirroring ottoq_fleet_claim_commands. Production-only, and refuses any '
  'command without a positive horizon_min so a real-time inverter setpoint can '
  'never be published through it (CLAUDE.md 2.5).';

-- 3. THE ACKNOWLEDGEMENT -----------------------------------------------------
CREATE OR REPLACE FUNCTION public.ottoq_energy_ack_command(
  p_command_id uuid,
  p_status     text,
  p_actor      text DEFAULT NULL,
  p_note       text DEFAULT NULL
) RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $fn$
DECLARE v_actor text := COALESCE(NULLIF(p_actor,''), current_user); v_n int;
BEGIN
  IF p_status NOT IN ('executed','refused') THEN
    RAISE EXCEPTION '0325: ack status must be executed or refused, got %', p_status;
  END IF;
  UPDATE public.ottoq_energy_commands u
     SET status        = p_status,
         confirmed_at  = COALESCE(u.confirmed_at, now()),
         confirmed_by  = COALESCE(u.confirmed_by, v_actor),
         executed_at   = CASE WHEN p_status = 'executed'
                              THEN COALESCE(u.executed_at, now()) ELSE u.executed_at END,
         executed_note = COALESCE(p_note, u.executed_note)
   WHERE u.command_id = p_command_id
     AND u.delivered_at IS NOT NULL      -- cannot acknowledge what was never delivered
     AND u.data_source = 'production';
  GET DIAGNOSTICS v_n = ROW_COUNT;
  RETURN v_n = 1;
END $fn$;

COMMENT ON FUNCTION public.ottoq_energy_ack_command(uuid,text,text,text) IS
  '0325: the consumer reports back. Refuses to acknowledge an undelivered command '
  'or any twin command.';

-- ASSERTIONS -----------------------------------------------------------------
DO $assert$
DECLARE v_n int; v_src text; v_cid uuid; v_depot uuid; v_claimed int;
BEGIN
  -- A1. All four columns exist.
  SELECT count(*) INTO v_n FROM information_schema.columns
   WHERE table_schema='public' AND table_name='ottoq_energy_commands'
     AND column_name IN ('delivered_at','delivered_to','confirmed_at','confirmed_by');
  IF v_n <> 4 THEN
    RAISE EXCEPTION '0325 A1: expected 4 delivery columns, found %', v_n;
  END IF;

  -- A2. The certified atom is untouched: h_nrg still hashes no delivery column.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_determinism_pair';
  IF v_src ~* 'delivered_at|delivered_to|confirmed_by' THEN
    RAISE EXCEPTION '0325 A2: the pair hashes a delivery column; h_nrg is no longer blind to the dock';
  END IF;

  -- A3. The dock is gated to production AND requires a horizon.
  SELECT p.prosrc INTO v_src FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
   WHERE n.nspname='public' AND p.proname='ottoq_energy_claim_commands';
  IF v_src IS NULL THEN
    RAISE EXCEPTION '0325 A3: ottoq_energy_claim_commands was not created';
  END IF;
  IF v_src !~* 'data_source\s*=\s*''production''' THEN
    RAISE EXCEPTION '0325 A3: the dock is not gated to production';
  END IF;
  IF v_src !~* 'horizon_min\s*>\s*0' THEN
    RAISE EXCEPTION '0325 A3: the dock does not require a positive horizon';
  END IF;

  -- A4. THE DOCK ACTUALLY REFUSES A TWIN COMMAND. Not a reading of the source --
  -- a call. The call is made inside a sub-block that ALWAYS exits by raising, so
  -- plpgsql's implicit savepoint rolls back every write the claim performed.
  -- Without that, this self-test would really deliver production commands as a
  -- side effect of asserting, which is the 0322 lesson.
  SELECT c.command_id, c.depot_id INTO v_cid, v_depot
    FROM public.ottoq_energy_commands c
   WHERE c.data_source = 'twin' AND c.status = 'issued'
   ORDER BY c.issued_at DESC LIMIT 1;

  IF v_cid IS NOT NULL THEN
    BEGIN
      SELECT count(*) INTO v_claimed
        FROM public.ottoq_energy_claim_commands(v_depot, 1000, 'ottoq_0325_selftest');
      SELECT count(*) INTO v_n FROM public.ottoq_energy_commands
       WHERE data_source = 'twin' AND delivered_at IS NOT NULL;
      IF v_n > 0 THEN
        RAISE EXCEPTION 'ottoq_0325_gate_failed:%', v_n;
      END IF;
      RAISE EXCEPTION 'ottoq_0325_selftest_rollback:%', v_claimed;
    EXCEPTION WHEN OTHERS THEN
      IF SQLERRM LIKE 'ottoq_0325_gate_failed:%' THEN
        RAISE EXCEPTION '0325 A4: the dock delivered a twin command; the production gate does not hold (%)', SQLERRM;
      ELSIF SQLERRM LIKE 'ottoq_0325_selftest_rollback:%' THEN
        RAISE NOTICE '0325 A4: dock asked for a twin depot, delivered 0 twin rows, self-test rolled back (%)', SQLERRM;
      ELSE
        RAISE;
      END IF;
    END;
  ELSE
    RAISE NOTICE '0325 A4: no issued twin energy command to test against; gate verified by source only';
  END IF;

  RAISE NOTICE '0325: energy dock created -- claim gated to production and to schedule-shaped commands, ack requires prior delivery';
END $assert$;
